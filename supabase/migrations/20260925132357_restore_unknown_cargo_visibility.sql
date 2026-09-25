-- Restore owner-check visibility without renumbering or changing cargo values.
create or replace function public.lk_cargo_needs_owner_check(s public.shipments)
returns boolean language sql stable set search_path=''
as $body$
 select s.deleted_at is null and s.deletion_requested_at is null
  and s.recipient_unknown_confirmed_at is null
  and (coalesce(s.recipient_unknown,false) or coalesce(s.manual_uncertain,false)
    or (not coalesce(s.data_locked,false)
      and public.lk_recipient_needs_review(s.consignee_name,s.consignee_phone)));
$body$;
revoke all on function public.lk_cargo_needs_owner_check(public.shipments) from public,anon;
grant execute on function public.lk_cargo_needs_owner_check(public.shipments) to authenticated,service_role;

create or replace function public.list_unknown_recipient_cargo()
returns table(id bigint,route text,shipment_year integer,voyage text,box_number text,
 invoice_number text,consignee_name text,consignee_phone text,claim_pending boolean,created_at timestamptz)
language plpgsql security definer set search_path=''
as $body$
declare can_view_full boolean;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 can_view_full:=coalesce(public.current_role() in ('admin','staff','partner'),false);
 return query select s.id,s.route,s.shipment_year,s.voyage,s.box_number,s.invoice_number,
  case when can_view_full then s.consignee_name else public.lk_mask_recipient_name(s.consignee_name) end,
  case when can_view_full then s.consignee_phone else public.lk_mask_recipient_phone(s.consignee_phone) end,
  exists(select 1 from public.unknown_recipient_claims c where c.shipment_id=s.id
    and c.requester_id=auth.uid() and c.status='pending'),s.created_at
 from public.shipments s where public.lk_cargo_needs_owner_check(s)
 -- No age cutoff: keep unresolved cargo visible until resolved or deleted.
 order by s.created_at asc,s.shipment_year desc,s.route,s.voyage,s.box_number;
end $body$;
revoke all on function public.list_unknown_recipient_cargo() from public,anon;
grant execute on function public.list_unknown_recipient_cargo() to authenticated,service_role;

-- Queue maintenance used to be coupled to receipt renumbering. Keep it
-- independent so Excel-preserved receipt assignments cannot suppress review.
create or replace function public.sync_unknown_recipient_review_queue()
returns trigger language plpgsql security definer set search_path=''
as $body$
begin
 if new.deleted_at is null and new.deletion_requested_at is null
   and new.recipient_unknown_confirmed_at is null and coalesce(new.recipient_unknown,false) then
  insert into public.unmatched_recipient_review_queue as q
   (shipment_id,detected_name,detected_phone,detected_by,first_detected_at)
  values(new.id,coalesce(new.consignee_name,''),coalesce(new.consignee_phone,''),auth.uid(),coalesce(new.created_at,now()))
  on conflict(shipment_id) do update set status='pending',detected_name=excluded.detected_name,
   detected_phone=excluded.detected_phone,detected_by=coalesce(excluded.detected_by,q.detected_by),
   resolved_at=null,resolved_by=null,updated_at=now()
  where q.status='resolved' or q.detected_name is distinct from excluded.detected_name
    or q.detected_phone is distinct from excluded.detected_phone;
 else
  update public.unmatched_recipient_review_queue set status='resolved',resolved_at=now(),
   resolved_by=auth.uid(),updated_at=now() where shipment_id=new.id and status in ('pending','kept_unknown');
 end if;
 return new;
end $body$;
revoke all on function public.sync_unknown_recipient_review_queue() from public,anon,authenticated;
drop trigger if exists shipments_sync_unknown_review on public.shipments;
create trigger shipments_sync_unknown_review
 after insert or update of consignee_name,consignee_phone,recipient_unknown,
 recipient_unknown_confirmed_at,deletion_requested_at,deleted_at on public.shipments
 for each row execute function public.sync_unknown_recipient_review_queue();

insert into public.unmatched_recipient_review_queue
 (shipment_id,detected_name,detected_phone,first_detected_at)
select s.id,coalesce(s.consignee_name,''),coalesce(s.consignee_phone,''),coalesce(s.created_at,now())
from public.shipments s where s.recipient_unknown and s.recipient_unknown_confirmed_at is null
 and s.deleted_at is null and s.deletion_requested_at is null
on conflict(shipment_id) do nothing;

-- Use the same eligibility for display and the existing member claim action.
create or replace function public.create_unknown_recipient_claim(p_shipment_id bigint,
 p_claimant_name text,p_claimant_phone text,p_note text default '')
returns bigint language plpgsql security definer set search_path=''
as $body$
declare claim_id bigint;
begin
 if auth.uid() is null or public.current_role() is distinct from 'member' then
  raise exception '일반 회원만 본인 화물 확인 요청을 할 수 있습니다.';
 end if;
 if nullif(btrim(p_claimant_name),'') is null or nullif(btrim(p_claimant_phone),'') is null then
  raise exception '본인 이름과 연락처를 모두 입력해 주세요.';
 end if;
 if not exists(select 1 from public.shipments s where s.id=p_shipment_id and public.lk_cargo_needs_owner_check(s)) then
  raise exception '현재 수취인 확인이 필요한 화물이 아닙니다.';
 end if;
 if exists(select 1 from public.unknown_recipient_claims where shipment_id=p_shipment_id
  and requester_id=auth.uid() and status='pending') then raise exception '이미 확인 대기 중인 요청이 있습니다.'; end if;
 insert into public.unknown_recipient_claims(shipment_id,requester_id,claimant_name,claimant_phone,note)
 values(p_shipment_id,auth.uid(),btrim(p_claimant_name),btrim(p_claimant_phone),coalesce(p_note,'')) returning id into claim_id;
 return claim_id;
end $body$;
revoke all on function public.create_unknown_recipient_claim(bigint,text,text,text) from public,anon;
grant execute on function public.create_unknown_recipient_claim(bigint,text,text,text) to authenticated,service_role;
notify pgrst,'reload schema';
