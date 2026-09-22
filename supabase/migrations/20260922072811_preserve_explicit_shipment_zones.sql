-- Preserve approved/manual Zones without freezing quantity-based defaults.
-- Shared by the App and website. Existing receipt and monetary rules are unchanged.
alter table public.shipments add column if not exists unloading_zone_override text;
comment on column public.shipments.unloading_zone_override is
  'Explicit per-shipment Zone. NULL uses automatic customer/quantity rules; blank manual Zone clears the override.';

create or replace function public.capture_shipment_zone_override()
returns trigger language plpgsql security invoker set search_path = public
as $zone$
begin
  if current_setting('lkgroup.normalizing_shipments',true)='1'
     or current_setting('lkgroup.calculating_zone',true)='1' then
    if tg_op='UPDATE' then
      new.unloading_zone := coalesce(nullif(btrim(old.unloading_zone_override),''),
        case when btrim(old.unloading_zone) not in ('','A','B','C','F','102')
          then btrim(old.unloading_zone) end, new.unloading_zone);
    end if;
    return new;
  end if;

  new.unloading_zone := btrim(coalesce(new.unloading_zone,''));
  if tg_op='INSERT' then
    -- Excel clients send cached A/B/C/F/102 defaults. Keep those automatic.
    -- New custom locations have no built-in formula and are always explicit.
    if new.unloading_zone not in ('','A','B','C','F','102') then
      new.unloading_zone_override := new.unloading_zone;
    end if;
  elsif new.unloading_zone is distinct from btrim(old.unloading_zone) then
    new.unloading_zone_override := nullif(new.unloading_zone,'');
  end if;
  return new;
end $zone$;
revoke all on function public.capture_shipment_zone_override() from public, anon, authenticated;

drop trigger if exists shipments_capture_zone_override on public.shipments;
create trigger shipments_capture_zone_override
before insert or update of unloading_zone on public.shipments
for each row execute function public.capture_shipment_zone_override();

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

CREATE OR REPLACE FUNCTION public.review_shipment_change_request(p_request_id bigint, p_action text, p_admin_changes jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req public.shipment_change_requests%rowtype;
  v_final jsonb;
  v_message text;
  v_result text;
  v_route text;
  v_year integer;
  v_voyage text;
begin
  if public.current_role()<>'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  select * into v_req from public.shipment_change_requests
  where id=p_request_id and status='pending' for update;
  if not found then raise exception '처리 가능한 요청을 찾을 수 없습니다.'; end if;

  if p_action='reject' then
    update public.shipment_change_requests
    set status='rejected',review_result='rejected',admin_changes='{}'::jsonb,
        reviewed_by=auth.uid(),reviewed_at=now()
    where id=p_request_id;
    v_message:='수정 요청이 거절 되었습니다.';
    v_result:='rejected';
  elsif p_action in ('approve','modified_approve') then
    v_final:=coalesce(v_req.changes,'{}'::jsonb)||coalesce(p_admin_changes,'{}'::jsonb);
    select route,shipment_year,voyage into v_route,v_year,v_voyage
    from public.shipments where id=v_req.shipment_id;

    if v_req.request_source='excel_import' then
      perform set_config('lkgroup.bulk_import','1',true);
    end if;
    update public.shipments
    set invoice_number=case when v_final?'invoice_number' then coalesce(v_final->>'invoice_number','') else invoice_number end,
        sender_name=case when v_final?'sender_name' then coalesce(v_final->>'sender_name','') else sender_name end,
        consignee_name=case when v_final?'consignee_name' then coalesce(v_final->>'consignee_name','') else consignee_name end,
        consignee_phone=case when v_final?'consignee_phone' then coalesce(v_final->>'consignee_phone','') else consignee_phone end,
        contents=case when v_final?'contents' then coalesce(v_final->>'contents','') else contents end,
        package_type=case when v_final?'package_type' then coalesce(v_final->>'package_type','') else package_type end,
        quantity=case when v_final?'quantity' then coalesce(nullif(v_final->>'quantity','')::integer,1) else quantity end,
        weight_kg=case when v_final?'weight_kg' then nullif(v_final->>'weight_kg','')::numeric else weight_kg end,
        length_cm=case when v_final?'length_cm' then nullif(v_final->>'length_cm','')::numeric else length_cm end,
        width_cm=case when v_final?'width_cm' then nullif(v_final->>'width_cm','')::numeric else width_cm end,
        height_cm=case when v_final?'height_cm' then nullif(v_final->>'height_cm','')::numeric else height_cm end,
        receipt_number=case when v_final?'receipt_number' then coalesce(v_final->>'receipt_number','') else receipt_number end,
        unloading_zone=case when v_final?'unloading_zone' then coalesce(v_final->>'unloading_zone','') else unloading_zone end,
        unloading_zone_override=case when v_final?'unloading_zone' then nullif(btrim(v_final->>'unloading_zone'),'') else unloading_zone_override end,
        notes=case when v_final?'notes' then coalesce(v_final->>'notes','') else notes end,
        received_at=case when v_final?'received_at' then nullif(v_final->>'received_at','')::date else received_at end,
        updated_at=now()
    where id=v_req.shipment_id;
    if v_req.request_source='excel_import' then
      update public.shipments
      set recipient_unknown=public.lk_recipient_true_unknown(consignee_name,consignee_phone),
          special_note_auto=public.compute_shipment_special_note(route,consignee_name,consignee_phone)
      where id=v_req.shipment_id;
      perform set_config('lkgroup.bulk_import','',true);
    else
      perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
    end if;

    if p_action='modified_approve' and coalesce(p_admin_changes,'{}'::jsonb)<>'{}'::jsonb then
      v_result:='modified_approved';
      v_message:='관리자의 추가 수정 후 승인 되었습니다.';
    else
      v_result:='approved';
      v_message:='승인 되었습니다.';
    end if;
    update public.shipment_change_requests
    set status='approved',review_result=v_result,
        admin_changes=coalesce(p_admin_changes,'{}'::jsonb),
        reviewed_by=auth.uid(),reviewed_at=now()
    where id=p_request_id;
  else
    raise exception '지원하지 않는 처리 방식입니다.';
  end if;

  if v_req.requested_by is not null then
    insert into public.user_notifications(
      user_id,notification_type,title,message,related_request_id
    ) values(
      v_req.requested_by,'shipment_change','화물 정보 수정 요청',v_message,p_request_id
    );
  end if;
exception when others then
  perform set_config('lkgroup.bulk_import','',true);
  raise;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_add_shipment_row(p_route text, p_year integer, p_voyage text, p_box_number text, p_invoice_number text DEFAULT ''::text, p_consignee_name text DEFAULT ''::text, p_consignee_phone text DEFAULT ''::text, p_notes text DEFAULT ''::text, p_unloading_zone text DEFAULT ''::text, p_weight_kg numeric DEFAULT NULL::numeric, p_length_cm numeric DEFAULT NULL::numeric, p_width_cm numeric DEFAULT NULL::numeric, p_height_cm numeric DEFAULT NULL::numeric)
 RETURNS shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.shipments%rowtype;
  v_voyage text := lpad(nullif(regexp_replace(coalesce(p_voyage, ''), '[^0-9]', '', 'g'), ''), 2, '0');
  v_box text := trim(coalesce(p_box_number, ''));
begin
  if auth.uid() is null or not exists (select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') or coalesce(public.current_role(), '') <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;
  if trim(coalesce(p_route, '')) = '' or p_year is null or v_voyage is null or v_box = '' then
    raise exception '운송 경로, 년도, 항차, 박스번호가 필요합니다.';
  end if;

  if exists (
    select 1 from public.shipments s
     where s.route = p_route
       and s.shipment_year = p_year
       and lpad(regexp_replace(coalesce(s.voyage, ''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
       and s.box_number = v_box
  ) then
    raise exception '이미 존재하는 박스번호입니다.';
  end if;

  insert into public.shipments(
    route, shipment_year, voyage, box_number, import_key,
    invoice_number, consignee_name, consignee_phone, notes, unloading_zone, unloading_zone_override,
    quantity, weight_kg, length_cm, width_cm, height_cm, status, received_at
  ) values (
    p_route, p_year, v_voyage, v_box,
    concat(p_route, '|', p_year::text, '|', v_voyage, '|', v_box),
    trim(coalesce(p_invoice_number, '')),
    trim(coalesce(p_consignee_name, '')),
    trim(coalesce(p_consignee_phone, '')),
    trim(coalesce(p_notes, '')),
    trim(coalesce(p_unloading_zone, '')),
    nullif(trim(p_unloading_zone), ''),
    1, p_weight_kg, p_length_cm, p_width_cm, p_height_cm, 'registered', now()
  ) returning * into v_row;

  return v_row;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.normalize_shipment_batch_fast_impl(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
  declare
  v_route_key text;
  v_prefix text;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_xx text;
  v_start integer;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or v_voyage='' then
    perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return;
  end if;

  select rd.route_key, coalesce(btrim(rd.receipt_prefix),'')
    into v_route_key, v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(v_route_key,'')='' then
    if p_route in ('한국->라오스 해상','한국→라오스 해상') then
      v_route_key:='kr_la_sea'; v_prefix:='LKS';
    elsif p_route in ('한국->라오스 항공','한국→라오스 항공') then
      v_route_key:='kr_la_air'; v_prefix:='LKA';
    end if;
  end if;

  v_xx := case
    when coalesce(v_prefix,'')='' then 'XX'
    when v_route_key in ('kr_la_sea','kr_la_air') then v_prefix||' XX'
    else v_prefix||'XX'
  end;

  create temporary table if not exists _norm_batch (
    id bigint primary key,
    customer_key text not null,
    is_unknown boolean not null,
    old_receipt text,
    qty integer not null
  ) on commit drop;
  truncate _norm_batch;

  insert into _norm_batch(id,customer_key,is_unknown,old_receipt,qty)
  select
    s.id,
    lower(btrim(coalesce(s.consignee_name,''))) || '|' ||
      regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g'),
    public.shipment_name_is_explicit_unknown(s.consignee_name),
    btrim(coalesce(s.receipt_number,'')),
    greatest(coalesce(s.quantity,1),1)
  from public.shipments s
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;

  if not exists(select 1 from _norm_batch) then
    perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return;
  end if;

  create index if not exists _norm_batch_customer_idx on _norm_batch(customer_key);
  create index if not exists _norm_batch_receipt_idx on _norm_batch(old_receipt);

  update public.shipments s
     set recipient_unknown=b.is_unknown,
         receipt_number=case
           when b.is_unknown then v_xx
           when b.old_receipt=v_xx then ''
           else b.old_receipt
         end,
         unloading_zone=case
           when b.is_unknown then 'F'
           else s.unloading_zone
         end
  from _norm_batch b
  where s.id=b.id
    and (
      s.recipient_unknown is distinct from b.is_unknown
      or (b.is_unknown and coalesce(s.receipt_number,'') is distinct from v_xx)
      or (not b.is_unknown and b.old_receipt=v_xx)
      or (b.is_unknown and coalesce(s.unloading_zone,'') is distinct from 'F')
    );

  insert into public.unmatched_recipient_review_queue(
    shipment_id,status,detected_name,detected_phone,detected_by
  )
  select
    s.id,
    'pending',
    coalesce(s.consignee_name,''),
    coalesce(s.consignee_phone,''),
    auth.uid()
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where b.is_unknown
  on conflict (shipment_id) do update set
    status='pending',
    detected_name=excluded.detected_name,
    detected_phone=excluded.detected_phone,
    detected_by=coalesce(
      excluded.detected_by,
      public.unmatched_recipient_review_queue.detected_by
    ),
    updated_at=now(),
    resolved_by=null,
    resolved_at=null
  where public.unmatched_recipient_review_queue.status is distinct from 'pending'
     or public.unmatched_recipient_review_queue.detected_name is distinct from excluded.detected_name
     or public.unmatched_recipient_review_queue.detected_phone is distinct from excluded.detected_phone;

  update public.unmatched_recipient_review_queue q
     set status='resolved',
         resolved_by=auth.uid(),
         resolved_at=coalesce(q.resolved_at,now()),
         updated_at=now()
  from _norm_batch b
  where q.shipment_id=b.id
    and not b.is_unknown
    and q.status='pending';

  update _norm_batch b
     set old_receipt=btrim(coalesce(s.receipt_number,''))
  from public.shipments s
  where s.id=b.id;

  create temporary table if not exists _customer_receipt (
    customer_key text primary key,
    receipt text
  ) on commit drop;
  truncate _customer_receipt;

  insert into _customer_receipt(customer_key,receipt)
  select customer_key, receipt
  from (
    select
      b.customer_key,
      b.old_receipt receipt,
      row_number() over (
        partition by b.customer_key
        order by
          coalesce(
            (regexp_match(b.old_receipt,'(\d+)\s*$'))[1]::integer,
            2147483647
          ),
          b.id
      ) rn
    from _norm_batch b
    where not b.is_unknown
      and b.old_receipt<>''
      and b.old_receipt<>v_xx
  ) x
  where rn=1;

  update public.shipments s
     set receipt_number=cr.receipt
  from _norm_batch b
  join _customer_receipt cr on cr.customer_key=b.customer_key
  where s.id=b.id
    and not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')='';

  select
    coalesce(
      max(
        (regexp_match(
          btrim(coalesce(s.receipt_number,'')),
          '(\d+)\s*$'
        ))[1]::integer
      ),
      0
    ) + 1
  into v_start
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where not b.is_unknown
    and btrim(coalesce(s.receipt_number,''))<>''
    and btrim(coalesce(s.receipt_number,''))<>v_xx;

  v_start:=coalesce(v_start,1);

  create temporary table if not exists _new_receipts (
    customer_key text primary key,
    receipt text not null
  ) on commit drop;
  truncate _new_receipts;

  insert into _new_receipts(customer_key,receipt)
  select
    customer_key,
    case
      when coalesce(v_prefix,'')='' then
        'ID-'||lpad((v_start+rn-1)::text,2,'0')
      when v_route_key in ('kr_la_sea','kr_la_air') then
        v_prefix||' '||lpad((v_start+rn-1)::text,2,'0')
      else
        v_prefix||lpad((v_start+rn-1)::text,2,'0')
    end
  from (
    select
      customer_key,
      row_number() over(order by min(id))::integer rn
    from _norm_batch b
    where not b.is_unknown
      and not exists(
        select 1
        from _customer_receipt cr
        where cr.customer_key=b.customer_key
      )
    group by customer_key
  ) g;

  update public.shipments s
     set receipt_number=nr.receipt
  from _norm_batch b
  join _new_receipts nr on nr.customer_key=b.customer_key
  where s.id=b.id
    and not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')='';

  create temporary table if not exists _receipt_qty (
    receipt text primary key,
    qty integer not null
  ) on commit drop;
  truncate _receipt_qty;

  insert into _receipt_qty(receipt,qty)
  select
    btrim(s.receipt_number),
    sum(greatest(coalesce(s.quantity,1),1))::integer
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  -- PATCH138F: target table alias s는 FROM의 JOIN ON 안에서 참조하지 않음.
  update public.shipments s
     set unloading_zone=case
       when v_route_key='kr_la_air' then '102'
       when rq.qty>=20 then 'F'
       when rq.qty>=10 then 'C'
       when rq.qty>=5 then 'B'
       else 'A'
     end
  from _norm_batch b, _receipt_qty rq
  where s.id=b.id
    and not b.is_unknown
    and rq.receipt=btrim(s.receipt_number);

end;
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.lk_apply_excel_logic_parity_legacy_v103(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
  declare
  v_route_key text;
  v_prefix text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'
  );
begin
  select rd.route_key,rd.receipt_prefix into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;
  if coalesce(v_route_key,'')='' then perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return; end if;

  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' XX'
        else btrim(v_prefix)||'XX'
      end,
      unloading_zone='F'
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  update public.shipments s
  set recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  -- Merge only whitespace variants of the same complete name and phone.
  with grouped as (
    select
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g') full_name_key,
      right(public.normalize_phone(s.consignee_phone),8) phone_key,
      coalesce(
        min(btrim(s.receipt_number)) filter(where coalesce(s.data_locked,false)),
        min(btrim(s.receipt_number))
      ) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and btrim(coalesce(s.receipt_number,''))<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g'),
      right(public.normalize_phone(s.consignee_phone),8)
  )
  update public.shipments s
  set receipt_number=g.receipt_number,recipient_unknown=false
  from grouped g
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g')=g.full_name_key
    and right(public.normalize_phone(s.consignee_phone),8)=g.phone_key;

  -- 이우용/이*용 follows a single confirmed 이우용 receipt.
  with known as (
    select public.lk_receipt_name_key(s.consignee_name) name_key,
           min(btrim(s.receipt_number)) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and public.lk_receipt_name_key(s.consignee_name)<>''
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and coalesce(btrim(s.receipt_number),'')<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by public.lk_receipt_name_key(s.consignee_name)
    having count(distinct right(public.normalize_phone(s.consignee_phone),8))=1
       and count(distinct btrim(s.receipt_number))=1
  )
  update public.shipments s
  set receipt_number=k.receipt_number,recipient_unknown=false
  from known k
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
    and public.lk_recipient_phone_uncertain(s.consignee_phone)
    and public.lk_receipt_name_key(s.consignee_name)=k.name_key;

  update public.shipments s
  set receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' 100'
        else btrim(v_prefix)||'100'
      end,
      unloading_zone='102',recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_is_park_seongho(s.consignee_name);

  with qty as (
    select btrim(s.receipt_number) receipt,
           sum(greatest(coalesce(s.quantity,1),1))::integer total_qty
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
    group by btrim(s.receipt_number)
  )
  update public.shipments s
  set unloading_zone=case
    when public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      then 'F'
    when public.lk_is_park_seongho(s.consignee_name) then '102'
    when exists(
      select 1 from public.customer_zone_overrides z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
    ) then coalesce((
      select z.zone from public.customer_zone_overrides z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
      order by
        public.lk_name_match_rank(s.consignee_name,z.customer_name),
        case when z.route_key=v_route_key then 0 else 1 end,z.id
      limit 1
    ),'102')
    when public.lk_receipt_name_key(s.consignee_name)
           =public.normalize_person_name('김요셉')
      or lower(coalesce(s.consignee_name,'')) like '%beauty panda%'
      or coalesce(s.consignee_name,'') like '%뷰티판다%' then 'F'
    when exists(
      select 1 from public.local_delivery_profiles d
      where d.active=true and d.route_key=v_route_key
        and public.lk_delivery_candidate_rank(
          d.paid_by,d.customer_name,d.alternate_name,d.company_name,d.phone,
          s.consignee_name,s.consignee_phone
        )<9999
    ) then 'F'
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from qty q
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  update public.shipments s
  set special_note_auto=public.compute_shipment_special_note(
    s.route,s.consignee_name,s.consignee_phone
  )
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;
end;
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.lk_apply_excel_logic_parity(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
  declare
  v_route_key text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'
  );
begin
  perform public.lk_apply_excel_logic_parity_legacy_v103(
    p_route,p_year,p_voyage
  );

  select rd.route_key into v_route_key
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(v_route_key,'')='' then perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return; end if;

  update public.shipments s
  set unloading_zone='F',
      special_note_auto=public.compute_shipment_special_note(
        s.route,s.consignee_name,s.consignee_phone
      )
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_resolve_delivery_profile_id(
      v_route_key,s.consignee_name,s.consignee_phone
    ) is not null;
end;
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.shipments_auto_normalize_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if current_setting('lkgroup.calculating_zone',true)='1' then return coalesce(new,old); end if;
  -- Existing recursion guard + Patch168 bulk-import guard.
  if current_setting('lkgroup.normalizing_shipments', true) = '1'
     or current_setting('lkgroup.bulk_import', true) = '1'
     or pg_trigger_depth() > 1
  then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    perform public.normalize_shipment_batch(
      old.route, old.shipment_year, old.voyage
    );
    return old;
  end if;

  perform public.normalize_shipment_batch(
    new.route, new.shipment_year, new.voyage
  );

  if tg_op = 'UPDATE'
     and (
       old.route is distinct from new.route
       or old.shipment_year is distinct from new.shipment_year
       or old.voyage is distinct from new.voyage
     )
  then
    perform public.normalize_shipment_batch(
      old.route, old.shipment_year, old.voyage
    );
  end if;

  return new;
end
$function$
;

drop trigger if exists trg_shipments_auto_normalize on public.shipments;
create trigger trg_shipments_auto_normalize
after insert or delete or update of route, shipment_year, voyage, consignee_name,
  consignee_phone, receipt_number, quantity, deletion_requested_at, data_locked, unloading_zone
on public.shipments for each row execute function public.shipments_auto_normalize_trigger();
notify pgrst, 'reload schema';
