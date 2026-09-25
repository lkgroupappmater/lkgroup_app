-- Existing cargo from a full voyage workbook always requires explicit review.
alter table public.shipment_change_requests add column if not exists excel_before_values jsonb;
alter table public.shipment_change_requests add column if not exists excel_sync_token text;

CREATE OR REPLACE FUNCTION public.lk_excel_import_changes(p_item jsonb, p_existing shipments)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_changes jsonb:='{}'::jsonb;
  v_text text;
  v_number numeric;
  v_quantity integer;
  v_date date;
begin
  if jsonb_typeof(p_item)<>'object' then
    raise exception '화물 데이터 행 형식이 올바르지 않습니다.';
  end if;

  if p_item?'invoice_number' then
    v_text:=btrim(coalesce(p_item->>'invoice_number',''));
    if v_text is distinct from btrim(coalesce(p_existing.invoice_number,'')) then
      v_changes:=v_changes||jsonb_build_object('invoice_number',v_text);
    end if;
  end if;
  if p_item?'sender_name' then
    v_text:=btrim(coalesce(p_item->>'sender_name',''));
    if v_text is distinct from btrim(coalesce(p_existing.sender_name,'')) then
      v_changes:=v_changes||jsonb_build_object('sender_name',v_text);
    end if;
  end if;
  if p_item?'consignee_name' then
    v_text:=btrim(coalesce(p_item->>'consignee_name',''));
    if v_text is distinct from btrim(coalesce(p_existing.consignee_name,'')) then
      v_changes:=v_changes||jsonb_build_object('consignee_name',v_text);
    end if;
  end if;
  if p_item?'consignee_phone' then
    v_text:=btrim(coalesce(p_item->>'consignee_phone',''));
    if v_text is distinct from btrim(coalesce(p_existing.consignee_phone,'')) then
      v_changes:=v_changes||jsonb_build_object('consignee_phone',v_text);
    end if;
  end if;
  if p_item?'contents' then
    v_text:=btrim(coalesce(p_item->>'contents',''));
    if v_text is distinct from btrim(coalesce(p_existing.contents,'')) then
      v_changes:=v_changes||jsonb_build_object('contents',v_text);
    end if;
  end if;
  if p_item?'package_type' then
    v_text:=btrim(coalesce(p_item->>'package_type',''));
    if v_text is distinct from btrim(coalesce(p_existing.package_type,'')) then
      v_changes:=v_changes||jsonb_build_object('package_type',v_text);
    end if;
  end if;
  if p_item?'quantity' then
    v_quantity:=coalesce(nullif(replace(p_item->>'quantity',',',''),'')::integer,1);
    if v_quantity is distinct from coalesce(p_existing.quantity,1) then
      v_changes:=v_changes||jsonb_build_object('quantity',v_quantity);
    end if;
  end if;
  if p_item?'weight_kg' then
    v_number:=nullif(replace(p_item->>'weight_kg',',',''),'')::numeric;
    if v_number is distinct from p_existing.weight_kg then
      v_changes:=v_changes||jsonb_build_object('weight_kg',v_number);
    end if;
  end if;
  if p_item?'length_cm' then
    v_number:=nullif(replace(p_item->>'length_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.length_cm then
      v_changes:=v_changes||jsonb_build_object('length_cm',v_number);
    end if;
  end if;
  if p_item?'width_cm' then
    v_number:=nullif(replace(p_item->>'width_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.width_cm then
      v_changes:=v_changes||jsonb_build_object('width_cm',v_number);
    end if;
  end if;
  if p_item?'height_cm' then
    v_number:=nullif(replace(p_item->>'height_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.height_cm then
      v_changes:=v_changes||jsonb_build_object('height_cm',v_number);
    end if;
  end if;
  if p_item?'receipt_number' then
    v_text:=btrim(coalesce(p_item->>'receipt_number',''));
    if v_text is distinct from btrim(coalesce(p_existing.receipt_number,'')) then
      v_changes:=v_changes||jsonb_build_object('receipt_number',v_text);
    end if;
  end if;
  if p_item?'unloading_zone' then
    v_text:=btrim(coalesce(p_item->>'unloading_zone',''));
    if v_text is distinct from btrim(coalesce(p_existing.unloading_zone,'')) then
      v_changes:=v_changes||jsonb_build_object('unloading_zone',v_text);
    end if;
  end if;
  if p_item?'notes' then
    v_text:=btrim(coalesce(p_item->>'notes',''));
    if v_text is distinct from btrim(coalesce(p_existing.notes,'')) then
      v_changes:=v_changes||jsonb_build_object('notes',v_text);
    end if;
  end if;
  if p_item?'received_at' then
    v_date:=nullif(p_item->>'received_at','')::date;
    if v_date is distinct from p_existing.received_at then
      v_changes:=v_changes||jsonb_build_object('received_at',v_date);
    end if;
  end if;

  if p_item?'box_number' and btrim(coalesce(p_item->>'box_number','')) is distinct from btrim(coalesce(p_existing.box_number,'')) then
    v_changes:=v_changes||jsonb_build_object('box_number',btrim(p_item->>'box_number'));
  end if;
  if p_item->>'_excel_action'='삭제함 이동' and p_existing.deletion_requested_at is null then
    v_changes:=v_changes||jsonb_build_object('_excel_action','삭제함 이동');
  elsif p_item->>'_excel_action'='복원' and p_existing.deletion_requested_at is not null then
    v_changes:=v_changes||jsonb_build_object('_excel_action','복원');
  end if;
  return v_changes;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_preview_shipment_excel_sync(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '45s'
AS $function$
declare
  r text; y integer; v text; item jsonb; matched jsonb; changes jsonb;
  old_row public.shipments%rowtype; empty_row public.shipments%rowtype;
  incoming jsonb:='[]'; existing jsonb; items jsonb:='[]'; used bigint[]:='{}';
  chosen bigint; n integer; token text; field text; val numeric; kind text;
begin
  if auth.uid() is null or coalesce(public.current_role(),'')<>'admin'
    or not exists(select 1 from public.profiles p where p.id=auth.uid()
      and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active')
    then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Excel 행 형식이 올바르지 않습니다.'; end if;
  if jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)>10000 then
    raise exception '화물 행이 없거나 너무 많습니다. 빈 파일로 항차 전체를 삭제할 수 없습니다.';
  end if;
  r:=btrim(p_rows->0->>'route'); y:=(p_rows->0->>'shipment_year')::integer; v:=p_rows->0->>'voyage';
  if coalesce(r,'')='' or y is null or y not between 1900 and 2099 or coalesce(v,'')!~'^[0-9]{2,3}$' or v::integer=0 then
    raise exception '운송 경로·년도·항차를 확인해 주세요. BASE는 화물 동기화 대상이 아닙니다.';
  end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(item)<>'object' or item->>'route' is distinct from r
      or (item->>'shipment_year')::integer is distinct from y or item->>'voyage' is distinct from v
      or btrim(coalesce(item->>'box_number',''))='' then raise exception '동일 항차의 전체 화물 목록과 화물번호가 필요합니다.'; end if;
    if not (item ?& array['invoice_number','consignee_name','consignee_phone','quantity']) then
      raise exception '화물 필수 열이 누락되었습니다.';
    end if;
    for field in select unnest(array['quantity','weight_kg','length_cm','width_cm','height_cm']) loop
      val:=nullif(replace(item->>field,',',''),'')::numeric;
      if val<0 or val::text in ('NaN','Infinity','-Infinity') or (field='quantity' and (val<1 or val>999999 or trunc(val)<>val)) then
        raise exception '화물 %의 % 값을 확인해 주세요.', item->>'box_number',field;
      end if;
      if item ? field then item:=jsonb_set(item,array[field],coalesce(to_jsonb(val),case when field='quantity' then '1'::jsonb else 'null'::jsonb end)); end if;
    end loop;
    item:=item||jsonb_build_object('box_number',btrim(item->>'box_number'),'invoice_number',btrim(coalesce(item->>'invoice_number','')));
    -- Reuse the existing typed comparison to validate dates and normalize cells.
    changes:=public.lk_excel_import_changes(item,empty_row);
    incoming:=incoming||jsonb_build_array(item||changes);
  end loop;
  if exists(select 1 from jsonb_array_elements(incoming) x group by lower(x->>'box_number') having count(*)>1) then
    raise exception '중복 화물번호를 수정한 뒤 다시 업로드해 주세요.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]') into existing from public.shipments s
    where s.route=r and s.shipment_year=y and s.voyage=v;

  -- First use a unique invoice to preserve IDs when box numbers change or swap.
  -- Otherwise use the box number. A row can never be matched twice.
  for item in select value from jsonb_array_elements(incoming) loop
    chosen:=null;
    if item->>'invoice_number'<>'' and (select count(*) from jsonb_array_elements(incoming) a where a->>'invoice_number'=item->>'invoice_number')=1 then
      select count(*),min((e->>'id')::bigint) into n,chosen from jsonb_array_elements(existing) e
        where btrim(e->>'invoice_number')=item->>'invoice_number' and e->>'deleted_at' is null
        and (e->>'deletion_requested_at' is null or e->>'deletion_requested_at'=e->>'excel_removed_at');
      if n<>1 then chosen:=null; end if;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object('_data',item,'shipment_id',chosen));
  end loop;
  for item in select value from jsonb_array_elements(items) where value->>'shipment_id' is not null loop
    used:=array_append(used,(item->>'shipment_id')::bigint);
  end loop;
  incoming:=items; items:='[]';
  for matched in select value from jsonb_array_elements(incoming) loop
    item:=matched->'_data'; chosen:=(matched->>'shipment_id')::bigint;
    if chosen is null then
      select count(*),min((e->>'id')::bigint) into n,chosen from jsonb_array_elements(existing) e
        where lower(btrim(e->>'box_number'))=lower(item->>'box_number') and not (e->>'id')::bigint=any(used)
        and e->>'deleted_at' is null and (e->>'deletion_requested_at' is null or e->>'deletion_requested_at'=e->>'excel_removed_at');
      if n>1 then raise exception '화물번호 %의 기존 화물이 여러 건입니다.',item->>'box_number'; end if;
      if n=0 then chosen:=null; end if;
      if chosen is not null then used:=array_append(used,chosen); end if;
    end if;
    if chosen is null then
      if exists(select 1 from jsonb_array_elements(existing) e where lower(btrim(e->>'box_number'))=lower(item->>'box_number') and (e->>'deleted_at' is not null or (e->>'deletion_requested_at' is not null and (e->>'excel_removed_at' is null or e->>'deletion_requested_at' is distinct from e->>'excel_removed_at')))) then
        raise exception '화물번호 %는 삭제함에 있습니다. 먼저 삭제 취소 여부를 확인해 주세요.',item->>'box_number';
      end if;
      kind:='new'; changes:='{}';
    else
      select * into old_row from jsonb_populate_record(null::public.shipments,(select e from jsonb_array_elements(existing) e where (e->>'id')::bigint=chosen));
      changes:=public.lk_excel_import_changes(item,old_row);
      if item->>'box_number' is distinct from old_row.box_number then changes:=changes||jsonb_build_object('box_number',item->>'box_number'); end if;
      kind:=case when old_row.deletion_requested_at is not null then 'restore' when changes<>'{}' then 'update' else 'unchanged' end;
      if kind<>'unchanged' and old_row.data_locked and exists(select 1 from public.shipment_change_requests q where q.shipment_id=chosen and q.status='pending' and q.request_source<>'excel_import') then
        raise exception '잠금 화물 %의 회원 변경 요청을 먼저 처리해 주세요.',old_row.box_number;
      end if;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object('shipment_id',chosen,'status',kind,'box_number',item->>'box_number','excel_row',item->'_row','changes',changes,'current_values',case when chosen is not null then to_jsonb(old_row) else '{}'::jsonb end,'_data',item));
  end loop;
  for item in select e from jsonb_array_elements(existing) e where not (e->>'id')::bigint=any(used) and e->>'deleted_at' is null and e->>'deletion_requested_at' is null loop
    items:=items||jsonb_build_array(jsonb_build_object('shipment_id',item->'id','status','remove','box_number',item->>'box_number','current_values',item));
  end loop;
  token:=md5('approval-v1|'||auth.uid()::text||p_rows::text||existing::text||coalesce((select jsonb_agg(jsonb_build_array(q.id,q.status,q.changes) order by q.id)::text from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id where s.route=r and s.shipment_year=y and s.voyage=v),'[]'));
  return jsonb_build_object('preview_token',token,'route',r,'shipment_year',y,'voyage',v,
    'new_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='new'),
    'updated_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='update'),
    'restored_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='restore'),
    'removed_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='remove'),
    'unchanged',(select count(*) from jsonb_array_elements(items) x where x->>'status'='unchanged'),
    'items',items);
end $function$
;
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
   where r.route in (rk,label) and r.shipment_year=p_year and r.voyage=v) then return; end if;
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
create or replace function public.admin_apply_shipment_excel_sync(p_rows jsonb,p_preview_token text)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='45s'
as $$
declare
 plan jsonb; item jsonb; payload jsonb; result jsonb; v_changes jsonb; request_id bigint;
 new_row public.shipments%rowtype; old_row public.shipments%rowtype;
 r text; y integer; v text; requested integer:=0; pending integer:=0;
 prior_flag text:=current_setting('lkgroup.bulk_import',true);
begin
 if auth.uid() is null or coalesce(public.current_role(),'')<>'admin' or not exists(select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('excel-sync:'||coalesce(p_rows->0->>'route','')||'|'||coalesce(p_rows->0->>'shipment_year','')||'|'||coalesce(p_rows->0->>'voyage',''),0));
 select summary into result from public.shipment_excel_sync_runs where preview_token=p_preview_token and actor_id=auth.uid() and input_hash=md5(p_rows::text);
 if found then return result; end if;
 r:=p_rows->0->>'route'; y:=(p_rows->0->>'shipment_year')::integer; v:=p_rows->0->>'voyage';
 perform 1 from public.shipments s where s.route=r and s.shipment_year=y and s.voyage=v order by s.id for update;
 plan:=public.admin_preview_shipment_excel_sync(p_rows);
 if p_preview_token is null or plan->>'preview_token'<>p_preview_token then raise exception '비교 이후 항차 데이터가 변경되었습니다. 미리보기를 다시 확인해 주세요.'; end if;
 result:=(plan-'items')||jsonb_build_object('approval_required',true);
 insert into public.shipment_excel_sync_runs(preview_token,actor_id,input_hash,route,shipment_year,voyage,summary) values(p_preview_token,auth.uid(),md5(p_rows::text),r,y,v,result);
 perform set_config('lkgroup.bulk_import','1',true);
 for item in select value from jsonb_array_elements(plan->'items') loop
  if item->>'status'='new' then
   payload:=item->'_data';
   select * into new_row from jsonb_populate_record(null::public.shipments,payload);
   insert into public.shipments(box_number,invoice_number,route,shipment_year,voyage,import_key,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,received_at,status)
   values(new_row.box_number,coalesce(new_row.invoice_number,''),r,y,v,r||'|'||y||'|'||v||'|'||new_row.box_number,coalesce(new_row.sender_name,''),new_row.consignee_name,new_row.consignee_phone,coalesce(new_row.contents,''),coalesce(new_row.package_type,''),coalesce(new_row.quantity,1),new_row.weight_kg,new_row.length_cm,new_row.width_cm,new_row.height_cm,coalesce(new_row.receipt_number,''),coalesce(new_row.unloading_zone,''),coalesce(new_row.notes,''),new_row.received_at,'registered') returning * into new_row;
   insert into public.shipment_excel_sync_changes values(p_preview_token,new_row.id,'new',null,to_jsonb(new_row));
  else
   select * into old_row from public.shipments where id=(item->>'shipment_id')::bigint;
   v_changes:=coalesce(item->'changes','{}');
   if item->>'status'='remove' then v_changes:=jsonb_build_object('_excel_action','삭제함 이동');
   elsif item->>'status'='restore' then v_changes:=v_changes||jsonb_build_object('_excel_action','복원'); end if;
   -- A newer complete file supersedes older Excel proposals, including omissions.
   update public.shipment_change_requests set status='rejected',review_result='rejected',reviewed_by=auth.uid(),reviewed_at=now()
    where shipment_id=old_row.id and status='pending' and request_source='excel_import' and shipment_change_requests.changes is distinct from v_changes;
   if v_changes='{}' then continue; end if;
   select q.id into request_id from public.shipment_change_requests q where q.shipment_id=old_row.id and q.status='pending' and q.request_source='excel_import' and q.changes=v_changes order by q.id limit 1;
   if found then pending:=pending+1;
   else
    insert into public.shipment_change_requests(shipment_id,requested_by,changes,status,request_source,excel_before_values,excel_sync_token)
     values(old_row.id,auth.uid(),v_changes,'pending','excel_import',to_jsonb(old_row),p_preview_token) returning id into request_id;
    requested:=requested+1;
   end if;
   insert into public.shipment_excel_sync_changes values(p_preview_token,old_row.id,item->>'status',to_jsonb(old_row),to_jsonb(old_row)||v_changes);
  end if;
 end loop;
 result:=result||jsonb_build_object('change_requests',requested,'already_pending',pending);
 update public.shipment_excel_sync_runs set summary=result where preview_token=p_preview_token;
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
 return result;
exception when others then
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true); raise;
end $$;

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
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
exception when unique_violation then
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
 raise exception '변경할 화물번호가 이미 사용 중입니다. 번호를 교환하는 요청은 함께 선택해 승인해 주세요.';
when others then perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true); raise;
end $$;

create or replace function public.review_shipment_change_request(p_request_id bigint,p_action text,p_admin_changes jsonb default '{}')
returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.review_shipment_change_requests(jsonb_build_array(jsonb_build_object('request_id',p_request_id,'action',p_action,'admin_changes',p_admin_changes)));
end $$;
revoke all on function public.review_shipment_change_requests(jsonb),public.review_shipment_change_request(bigint,text,jsonb),public.admin_apply_shipment_excel_sync(jsonb,text) from public,anon;
grant execute on function public.review_shipment_change_requests(jsonb),public.review_shipment_change_request(bigint,text,jsonb),public.admin_apply_shipment_excel_sync(jsonb,text) to authenticated;
notify pgrst,'reload schema';
