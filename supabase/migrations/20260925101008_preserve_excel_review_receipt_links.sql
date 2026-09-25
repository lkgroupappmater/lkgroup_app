CREATE OR REPLACE FUNCTION public.normalize_shipment_batch(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rk text; label text; v text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'); changed boolean;
begin
 if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
 select route_key,display_name into rk,label from public.route_definitions
 where route_key=btrim(p_route) or display_name=btrim(p_route)
 order by (display_name=btrim(p_route)) desc limit 1;
 if rk is null or p_year is null or v='' or v='00' then return; end if;
 -- A full Excel snapshot owns the voyage's receipt and zone assignments.
 -- Reassigning these here would bypass pending requests or undo an approval.
 if exists(select 1 from public.shipment_excel_sync_runs r
   where r.route in (rk,label) and r.shipment_year=p_year and r.voyage=v)
 or exists(select 1 from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id where q.request_source='excel_import' and q.changes?'receipt_number' and s.route in(rk,label) and s.shipment_year=p_year and s.voyage=v) then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(rk||'|'||p_year||'|'||v,0));
 perform set_config('lkgroup.normalizing_shipments','1',true);
 drop table if exists pg_temp._lk_sync_plan;
 drop table if exists pg_temp._lk_sync_map;
 drop table if exists pg_temp._lk_sync_zone;
 create temporary table _lk_sync_plan on commit drop as select * from public.lk_excel_receipt_plan(label,p_year,v);
 if exists(select 1 from _lk_sync_plan where identity_key<>'' and coalesce(new_receipt,'')='') then
   raise exception '고객별 명세서 번호를 확정할 수 없습니다.';
 end if;
 if exists(select 1 from _lk_sync_plan where locked group by identity_key having count(distinct old_receipt)>1) then
   raise exception '동일 고객에 잠긴 명세서 번호가 여러 개 있습니다. 잠금 상태를 먼저 확인하세요.';
 end if;
 -- A split receipt with explicit money attached cannot be assigned by guessing.
 if exists(select 1 from _lk_sync_plan p where p.old_receipt<>'' and (
   exists(select 1 from public.receipt_extra_costs e where e.route=label and e.shipment_year=p_year and e.voyage=v and btrim(e.receipt_number)=p.old_receipt)
   or exists(select 1 from public.receipt_discount_overrides d where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and btrim(d.receipt_number)=p.old_receipt)
 ) group by old_receipt having count(distinct new_receipt)>1) then
   raise exception '고객 분리 전 해당 명세서의 수동 할인·추가비용 연결을 확인하세요.';
 end if;
 create temporary table _lk_sync_map on commit drop as
 select old_receipt,min(new_receipt) new_receipt from _lk_sync_plan
 where old_receipt<>'' group by old_receipt having count(distinct new_receipt)=1;
 if exists(select 1 from public.receipt_discount_overrides d join _lk_sync_map m on btrim(d.receipt_number)=m.old_receipt
   where d.route_key=rk and d.shipment_year=p_year and d.voyage=v
   group by m.new_receipt having count(*)>1) then
   raise exception '고객 병합 대상에 수동 할인이 둘 이상 있습니다. 할인 내용을 먼저 확인하세요.';
 end if;
 -- Do not let an orphan charge attach to a newly reused numeric slot.
 if exists(select 1 from public.receipt_extra_costs e where e.route=label and e.shipment_year=p_year and e.voyage=v
   and exists(select 1 from _lk_sync_plan p where p.new_receipt=btrim(e.receipt_number))
   and not exists(select 1 from _lk_sync_map m where m.old_receipt=btrim(e.receipt_number)))
 or exists(select 1 from public.receipt_discount_overrides d where d.route_key=rk and d.shipment_year=p_year and d.voyage=v
   and exists(select 1 from _lk_sync_plan p where p.new_receipt=btrim(d.receipt_number))
   and not exists(select 1 from _lk_sync_map m where m.old_receipt=btrim(d.receipt_number))) then
   raise exception '화물과 연결되지 않은 할인·추가비용 번호가 있습니다. 해당 연결을 먼저 확인하세요.';
 end if;
 select exists(select 1 from _lk_sync_plan where old_receipt is distinct from new_receipt) into changed;
 if changed then
   insert into public.shipment_automation_history(route_key,shipment_year,voyage,receipt_mapping,prior_snapshots)
   values(rk,p_year,v,coalesce((select jsonb_agg(to_jsonb(m)) from _lk_sync_plan m),'[]'),
     coalesce((select jsonb_agg(to_jsonb(s)) from public.voyage_settlement_snapshots s where s.route_key in (rk,label) and s.shipment_year=p_year and s.voyage=v),'[]'));
   update public.receipt_extra_costs e set receipt_number=m.new_receipt
   from _lk_sync_map m where e.route=label and e.shipment_year=p_year and e.voyage=v
     and btrim(e.receipt_number)=m.old_receipt and e.receipt_number is distinct from m.new_receipt;
   -- Temporary keys avoid the unique constraint during swaps such as 03 <-> 04.
   update public.receipt_discount_overrides d set receipt_number='__LK_SYNC__'||m.new_receipt
   from _lk_sync_map m where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and btrim(d.receipt_number)=m.old_receipt;
   update public.receipt_discount_overrides d set receipt_number=substr(receipt_number,12)
   where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and left(receipt_number,11)='__LK_SYNC__';
   -- This is a derived cache; the prior value is archived above. Both clients
   -- recalculate from current shipments before rendering/exporting a settlement.
   delete from public.voyage_settlement_snapshots where route_key in (rk,label) and shipment_year=p_year and voyage=v;
 end if;
 create temporary table _lk_sync_zone on commit drop as
 with g as (
   select p.new_receipt,sum(greatest(coalesce(s.quantity,1),1)) qty,
     (array_agg(s.consignee_name order by s.box_number collate "C",s.id))[1] name,
     (array_agg(s.consignee_phone order by s.box_number collate "C",s.id))[1] phone,
     bool_or(p.is_unknown) unknown
   from _lk_sync_plan p join public.shipments s on s.id=p.shipment_id group by p.new_receipt
 ) select g.new_receipt,
   case when g.unknown then 'F'
     when rk='kr_la_air' then '102'
     when public.lk_excel_delivery_profile_id(rk,g.name,g.phone) is not null then 'F'
     when z.zone is not null then z.zone
     when g.qty>=20 then 'F' when g.qty>=10 then 'C' when g.qty>=5 then 'B' else 'A' end zone
 from g left join lateral (
   select o.zone from public.customer_zone_overrides o
   where o.active and o.route_key in (rk,'all') and public.lk_excel_name(o.customer_name)<>'' and public.lk_excel_match_name(g.name,g.phone)<>''
    and (position(public.lk_excel_name(o.customer_name) in public.lk_excel_match_name(g.name,g.phone))>0
      or position(public.lk_excel_match_name(g.name,g.phone) in public.lk_excel_name(o.customer_name))>0)
   order by (o.route_key=rk) desc,o.id desc limit 1
 ) z on true;
 update public.shipments s set receipt_number=p.new_receipt,recipient_unknown=p.is_unknown,unloading_zone=coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone)
 from _lk_sync_plan p join _lk_sync_zone z using(new_receipt)
 where s.id=p.shipment_id and not p.locked and
  (s.receipt_number is distinct from p.new_receipt or s.recipient_unknown is distinct from p.is_unknown or s.unloading_zone is distinct from coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone));
 perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
 perform set_config('lkgroup.normalizing_shipments','',true); raise;
end $function$
;

create or replace function public.review_shipment_change_requests(p_requests jsonb)
returns void language plpgsql security definer set search_path='' set statement_timeout='60s'
as $$
declare
 item jsonb; req public.shipment_change_requests%rowtype; cargo public.shipments%rowtype;
 final_values jsonb; edited jsonb; row_plan record; batch record; key text;
 prior_flag text:=current_setting('lkgroup.bulk_import',true);
begin
 if auth.uid() is null or coalesce(public.current_role(),'')<>'admin' or not exists(select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
 if jsonb_typeof(p_requests) is distinct from 'array' or jsonb_array_length(p_requests) not between 1 and 10000 then raise exception '처리할 요청을 다시 확인해 주세요.'; end if;
 if exists(select 1 from jsonb_array_elements(p_requests) x group by x->>'request_id' having count(*)>1) then raise exception '같은 요청이 중복 선택되었습니다.'; end if;
 for batch in select distinct s.route,s.shipment_year,s.voyage from public.shipments s join public.shipment_change_requests q on q.shipment_id=s.id where q.id in(select (x->>'request_id')::bigint from jsonb_array_elements(p_requests) x) order by 1,2,3 loop
  perform pg_advisory_xact_lock(hashtextextended('excel-sync:'||batch.route||'|'||batch.shipment_year||'|'||batch.voyage,0));
 end loop;
 perform 1 from public.shipments s where s.id in(select q.shipment_id from public.shipment_change_requests q where q.id in(select (x->>'request_id')::bigint from jsonb_array_elements(p_requests) x)) order by s.id for update;
 perform 1 from public.shipment_change_requests q where q.id in(select (x->>'request_id')::bigint from jsonb_array_elements(p_requests) x) order by q.id for update;
 drop table if exists pg_temp._lk_review;
 create temporary table _lk_review(request_id bigint primary key,shipment_id bigint,action text,source text,final_values jsonb,admin_changes jsonb,before_values jsonb) on commit drop;
 for item in select value from jsonb_array_elements(p_requests) loop
  select * into req from public.shipment_change_requests where id=(item->>'request_id')::bigint;
  if not found then raise exception '처리 가능한 요청을 찾을 수 없습니다.'; end if;
  if item->>'action' not in ('approve','modified_approve','reject') or item->>'action' is null then raise exception '지원하지 않는 처리 방식입니다.'; end if;
  if req.status='already_applied' and item->>'action' in ('approve','modified_approve') and coalesce(item->'admin_changes','{}')='{}' then continue; end if;
  if req.status<>'pending' then raise exception '이미 처리된 요청입니다. 목록을 새로고침해 주세요.'; end if;
  select * into cargo from public.shipments where id=req.shipment_id;
  edited:=case when item->>'action'='modified_approve' then coalesce(item->'admin_changes','{}') else '{}'::jsonb end;
  if jsonb_typeof(edited)<>'object' then raise exception '수정 값 형식을 확인해 주세요.'; end if;
  final_values:=req.changes||edited;
  if item->>'action'<>'reject' then
   if req.excel_before_values is not null and (public.lk_excel_import_changes(req.excel_before_values,cargo)<>'{}' or (req.excel_before_values->>'deletion_requested_at') is distinct from to_jsonb(cargo)->>'deletion_requested_at') then raise exception '요청 이후 화물 %의 정보가 변경되었습니다. 최신 Excel을 다시 비교해 주세요.',cargo.box_number; end if;
   for key in select jsonb_object_keys(final_values) loop
    if key<>all(array['box_number','invoice_number','sender_name','consignee_name','consignee_phone','contents','package_type','quantity','weight_kg','length_cm','width_cm','height_cm','receipt_number','unloading_zone','notes','received_at','_excel_action']) then raise exception '지원하지 않는 변경 항목: %',key; end if;
   end loop;
   if final_values?'_excel_action' and (req.request_source<>'excel_import' or final_values->>'_excel_action' not in ('삭제함 이동','복원')) then raise exception '삭제·복원 요청을 다시 확인해 주세요.'; end if;
   if cargo.deleted_at is not null or (cargo.deletion_requested_at is not null and (final_values->>'_excel_action' is distinct from '복원' or cargo.excel_removed_at is distinct from cargo.deletion_requested_at)) then raise exception '삭제함의 화물 상태를 먼저 확인해 주세요.'; end if;
   if final_values?'box_number' and btrim(coalesce(final_values->>'box_number',''))='' then raise exception '화물번호는 비워 둘 수 없습니다.'; end if;
   if final_values?'quantity' and coalesce((final_values->>'quantity')::numeric,0)<1 then raise exception '수량은 1 이상이어야 합니다.'; end if;
   for key in select unnest(array['weight_kg','length_cm','width_cm','height_cm']) loop
    if (final_values->>key)::numeric<0 then raise exception '중량·크기는 음수일 수 없습니다.'; end if;
   end loop;
  end if;
  insert into _lk_review values(req.id,cargo.id,item->>'action',req.request_source,final_values,edited,to_jsonb(cargo));
 end loop;
 if exists(select 1 from _lk_review where action<>'reject' group by shipment_id having count(*)>1) then raise exception '같은 화물의 승인 요청은 한 건만 선택해 주세요.'; end if;
 -- Compute all resulting receipt assignments before touching money or cargo.
 drop table if exists pg_temp._lk_review_receipts;
 create temporary table _lk_review_receipts on commit drop as
 select s.id,s.route,s.shipment_year,s.voyage,btrim(coalesce(s.receipt_number,'')) old_receipt,
  btrim(coalesce(case when q.action<>'reject' and q.final_values?'receipt_number' then q.final_values->>'receipt_number' else s.receipt_number end,'')) new_receipt
 from public.shipments s left join _lk_review q on q.shipment_id=s.id and q.action<>'reject'
 where s.deleted_at is null and exists(select 1 from _lk_review a where a.action<>'reject' and a.final_values?'receipt_number' and a.before_values->>'route'=s.route and (a.before_values->>'shipment_year')::integer=s.shipment_year and a.before_values->>'voyage'=s.voyage);
 if exists(select 1 from _lk_review_receipts p where p.old_receipt<>'' and (
  exists(select 1 from public.receipt_extra_costs e where e.route=p.route and e.shipment_year=p.shipment_year and e.voyage=p.voyage and btrim(e.receipt_number)=p.old_receipt)
  or exists(select 1 from public.receipt_discount_overrides d join public.route_definitions rd on rd.route_key=d.route_key where p.route in(rd.route_key,rd.display_name) and d.shipment_year=p.shipment_year and d.voyage=p.voyage and btrim(d.receipt_number)=p.old_receipt))
  group by route,shipment_year,voyage,old_receipt having count(distinct new_receipt)>1 or min(new_receipt)='') then raise exception '추가비용·수동 할인이 연결된 명세서입니다. 해당 명세서의 화물 변경 요청을 함께 선택해 승인해 주세요.'; end if;
 drop table if exists pg_temp._lk_review_receipt_map;
 create temporary table _lk_review_receipt_map on commit drop as select route,shipment_year,voyage,old_receipt,min(new_receipt) new_receipt from _lk_review_receipts where old_receipt<>'' group by route,shipment_year,voyage,old_receipt having count(distinct new_receipt)=1 and min(new_receipt)<>old_receipt;
 if exists(select 1 from public.receipt_discount_overrides d join public.route_definitions rd on rd.route_key=d.route_key left join _lk_review_receipt_map m on m.route in(rd.route_key,rd.display_name) and m.shipment_year=d.shipment_year and m.voyage=d.voyage and m.old_receipt=btrim(d.receipt_number)
  group by d.route_key,d.shipment_year,d.voyage,coalesce(m.new_receipt,d.receipt_number) having count(*)>1) then raise exception '명세서 변경 대상의 수동 할인 연결이 중복됩니다. 할인 내용을 먼저 확인해 주세요.'; end if;
 if exists(select 1 from _lk_review_receipt_map m where
  exists(select 1 from public.receipt_extra_costs e where e.route=m.route and e.shipment_year=m.shipment_year and e.voyage=m.voyage and btrim(e.receipt_number)=m.new_receipt)
  and not exists(select 1 from _lk_review_receipts p where p.route=m.route and p.shipment_year=m.shipment_year and p.voyage=m.voyage and p.old_receipt=m.new_receipt)) then
  raise exception '변경 대상 번호에 연결되지 않은 추가비용이 있습니다. 명세서 연결을 확인해 주세요.';
 end if;
 perform set_config('lkgroup.bulk_import','1',true);
 update public.shipment_change_requests q set status=case when p.action='reject' then 'rejected' else 'approved' end,review_result=case when p.action='reject' then 'rejected' when p.action='modified_approve' and p.admin_changes<>'{}' then 'modified_approved' else 'approved' end,admin_changes=p.admin_changes,reviewed_by=auth.uid(),reviewed_at=now() from _lk_review p where q.id=p.request_id;
 -- Release only the selected keys, transactionally, so a two-way swap can succeed.
 update public.shipments s set import_key=null from _lk_review p where p.shipment_id=s.id and p.action<>'reject' and (p.final_values?'box_number' or p.final_values?'_excel_action');
 for row_plan in select * from _lk_review where action<>'reject' order by shipment_id loop
  select * into cargo from jsonb_populate_record(null::public.shipments,row_plan.before_values||row_plan.final_values);
  update public.shipments s set
   box_number=cargo.box_number,import_key=case when row_plan.final_values->>'_excel_action'='삭제함 이동' then null else cargo.route||'|'||cargo.shipment_year||'|'||cargo.voyage||'|'||cargo.box_number end,
   invoice_number=cargo.invoice_number,sender_name=cargo.sender_name,consignee_name=cargo.consignee_name,consignee_phone=cargo.consignee_phone,contents=cargo.contents,package_type=cargo.package_type,quantity=cargo.quantity,weight_kg=cargo.weight_kg,length_cm=cargo.length_cm,width_cm=cargo.width_cm,height_cm=cargo.height_cm,
   receipt_number=cargo.receipt_number,unloading_zone=cargo.unloading_zone,unloading_zone_override=case when row_plan.final_values?'unloading_zone' then nullif(btrim(cargo.unloading_zone),'') else s.unloading_zone_override end,notes=cargo.notes,received_at=cargo.received_at,
   deletion_requested_at=case when row_plan.final_values->>'_excel_action'='삭제함 이동' then now() when row_plan.final_values->>'_excel_action'='복원' then null else s.deletion_requested_at end,
   deletion_requested_by=case when row_plan.final_values->>'_excel_action'='삭제함 이동' then auth.uid() when row_plan.final_values->>'_excel_action'='복원' then null else s.deletion_requested_by end,
   excel_removed_at=case when row_plan.final_values->>'_excel_action'='삭제함 이동' then now() when row_plan.final_values->>'_excel_action'='복원' then null else s.excel_removed_at end,
   recipient_unknown=public.lk_recipient_true_unknown(cargo.consignee_name,cargo.consignee_phone),special_note_auto=public.compute_shipment_special_note(cargo.route,cargo.consignee_name,cargo.consignee_phone),updated_at=now()
  where s.id=row_plan.shipment_id;
 end loop;
 update public.receipt_extra_costs e set receipt_number=m.new_receipt from _lk_review_receipt_map m where e.route=m.route and e.shipment_year=m.shipment_year and e.voyage=m.voyage and btrim(e.receipt_number)=m.old_receipt;
 update public.receipt_discount_overrides d set receipt_number='__LK_REVIEW__'||m.new_receipt from _lk_review_receipt_map m join public.route_definitions rd on m.route in(rd.route_key,rd.display_name) where d.route_key=rd.route_key and d.shipment_year=m.shipment_year and d.voyage=m.voyage and btrim(d.receipt_number)=m.old_receipt;
 update public.receipt_discount_overrides d set receipt_number=substr(d.receipt_number,14) where left(d.receipt_number,13)='__LK_REVIEW__';
 delete from public.voyage_settlement_snapshots s using _lk_review p,public.route_definitions rd where p.action<>'reject' and p.before_values->>'route' in(rd.route_key,rd.display_name) and s.route_key in(rd.route_key,rd.display_name) and s.shipment_year=(p.before_values->>'shipment_year')::integer and s.voyage=p.before_values->>'voyage';
 for row_plan in select * from _lk_review loop
  perform public.reconcile_applied_excel_requests(row_plan.shipment_id);
  insert into public.user_notifications(user_id,notification_type,title,message,related_request_id)
   select q.requested_by,'shipment_change','화물 정보 수정 요청',case when row_plan.action='reject' then '수정 요청이 거절 되었습니다.' else '승인 되었습니다.' end,q.id from public.shipment_change_requests q where q.id=row_plan.request_id and q.requested_by is not null;
 end loop;
 for batch in select distinct before_values->>'route' route,(before_values->>'shipment_year')::integer AS shipment_year,before_values->>'voyage' voyage from _lk_review where action<>'reject' and source<>'excel_import' loop
  perform public.normalize_shipment_batch(batch.route,batch.shipment_year,batch.voyage);
 end loop;
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
exception when unique_violation then
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
 raise exception '변경할 화물번호가 이미 사용 중입니다. 번호를 교환하는 요청은 함께 선택해 승인해 주세요.';
when others then perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true); raise;
end $$;


notify pgrst,'reload schema';
