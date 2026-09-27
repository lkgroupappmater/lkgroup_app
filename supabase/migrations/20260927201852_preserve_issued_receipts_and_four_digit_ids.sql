-- Four-digit display, without truncating existing numeric identities.
create or replace function public.lk_customer_display_code(p_number bigint) returns text
language sql immutable set search_path='' as $$
 select case when p_number>0 then 'LK '||lpad(p_number::text,greatest(4,length(p_number::text)),'0') end;
$$;
create or replace function public.lk_customer_statement_code(p_number bigint,p_unknown boolean) returns text
language sql immutable set search_path='' as $$
 select case when p_number>0 then case when coalesce(p_unknown,false) then '9' else '' end||lpad(p_number::text,greatest(case when coalesce(p_unknown,false) then 3 else 4 end,length(p_number::text)),'0') end;
$$;
-- Existing printed voyages keep their issued receipt numbers. Customer identity
-- remains independent and searchable across old and new voyages.
create or replace function public.lk_uses_customer_id_receipts(p_route text,p_year integer,p_voyage text)
returns boolean language sql stable set search_path='' as $$
 select coalesce(case when p_voyage='00' then true when p_year>2026 then true when p_year<2026 then false
 when coalesce((select route_key from public.route_definitions where route_key=p_route or display_name=p_route limit 1),p_route)='kr_la_sea' then nullif(regexp_replace(p_voyage,'[^0-9]','','g'),'')::integer>=10
 when coalesce((select route_key from public.route_definitions where route_key=p_route or display_name=p_route limit 1),p_route)='kr_la_air' then nullif(regexp_replace(p_voyage,'[^0-9]','','g'),'')::integer>=19
 else true end,false);
$$;
revoke all on function public.lk_uses_customer_id_receipts(text,integer,text) from public,anon;
grant execute on function public.lk_uses_customer_id_receipts(text,integer,text) to authenticated,service_role;

-- ID-number transitions preserve approved/imported layout and all cargo fields.
CREATE OR REPLACE FUNCTION public.normalize_shipment_batch(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rk text; label text; v text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'); changed boolean;
begin
 if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
 if not public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) then return; end if;
 select route_key,display_name into rk,label from public.route_definitions
 where route_key=btrim(p_route) or display_name=btrim(p_route)
 order by (display_name=btrim(p_route)) desc limit 1;
 if rk is null or p_year is null or v='' or v='00' then return; end if;
 -- A full Excel snapshot owns the voyage's receipt and zone assignments.
 -- Reassigning these here would bypass pending requests or undo an approval.
 if current_setting('lkgroup.apply_customer_ids',true) is distinct from '1' and (exists(select 1 from public.shipment_excel_sync_runs r
   where r.route in (rk,label) and r.shipment_year=p_year and r.voyage=v)
 or exists(select 1 from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id where q.request_source='excel_import' and q.changes?'receipt_number' and s.route in(rk,label) and s.shipment_year=p_year and s.voyage=v)) then return; end if;
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
   update public.domestic_parcels d set statement_receipt=m.new_receipt from _lk_sync_map m
   where d.statement_route=label and d.statement_year=p_year and d.statement_voyage=v and d.statement_receipt=m.old_receipt;
   update public.domestic_parcels d set link_receipt_number=m.new_receipt from _lk_sync_map m
   where d.link_route=label and d.link_year=p_year and d.link_voyage=v and d.link_receipt_number=m.old_receipt;
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
 update public.shipments s set receipt_number=p.new_receipt,recipient_unknown=case when current_setting('lkgroup.apply_customer_ids',true)='1' then s.recipient_unknown else p.is_unknown end,unloading_zone=case when current_setting('lkgroup.apply_customer_ids',true)='1' then s.unloading_zone else coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone) end
 from _lk_sync_plan p join _lk_sync_zone z using(new_receipt)
 where s.id=p.shipment_id and not coalesce(s.data_locked,false) and
  (s.receipt_number is distinct from p.new_receipt or (current_setting('lkgroup.apply_customer_ids',true) is distinct from '1' and (s.recipient_unknown is distinct from p.is_unknown or s.unloading_zone is distinct from coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone))));
 perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
 perform set_config('lkgroup.normalizing_shipments','',true); raise;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_excel_statement_controls(p_route text, p_year integer, p_voyage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rd public.route_definitions; receipts jsonb; reviews jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','staff','partner') and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.receipt_number),'[]') into receipts from (
 select s.receipt_number,string_agg(distinct s.consignee_name,' / ') name,string_agg(distinct s.consignee_phone,' / ') phone,
 array_agg(distinct public.lk_customer_display_code(m.customer_no)) filter(where m.customer_no is not null) customer_codes,
 bool_or(s.receipt_number_locked) locked,bool_or(s.data_locked) data_locked,bool_or(s.receipt_number_override is not null) manual,
 count(*) as "rows",case when public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) and count(distinct m.statement_customer_code)=1 and count(m.customer_no)=count(*) then rd.receipt_prefix||' '||min(m.statement_customer_code) end suggested_number
 from public.shipments s left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null
 group by s.receipt_number) r;
 select coalesce(jsonb_agg(jsonb_build_object('name',r.name,'phone',r.phone,'candidates',r.candidates)),'[]') into reviews
 from public.lk_excel_delivery_review_batch(rd.route_key,(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'phone',c.phone)),'[]') from (
 select distinct consignee_name name,consignee_phone phone from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and deleted_at is null and deletion_requested_at is null)c))r
 where r.profile_id is null and jsonb_array_length(r.candidates)>0;
 return jsonb_build_object('numbering_mode',case when public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) then 'customer_id' else 'legacy' end,'route_key',rd.route_key,'receipts',receipts,'delivery_reviews',reviews,'review_count',jsonb_array_length(reviews),'can_edit',public.current_role()='admin');
end $function$

;
CREATE OR REPLACE FUNCTION public.admin_set_statement_control(p_route text, p_year integer, p_voyage text, p_receipt text, p_number text DEFAULT NULL::text, p_locked boolean DEFAULT NULL::boolean, p_manual boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rd public.route_definitions; target text:=btrim(coalesce(p_number,p_receipt)); ids bigint[]; affected integer;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rd.route_key||'|'||p_year||'|'||p_voyage,0));
 perform 1 from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt and deleted_at is null for update;
 select array_agg(id) into ids from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt and deleted_at is null and deletion_requested_at is null;
 if cardinality(ids) is null then raise exception 'RECORD_CHANGED'; end if;
 if p_manual is false and not public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) then raise exception '이미 발행된 항차입니다. 기존 명세서 번호를 유지하고 고객 ID는 별도로 표시합니다.'; end if;
 if p_manual is false then
  select case when count(distinct m.statement_customer_code)=1 and count(m.customer_no)=count(*) then rd.receipt_prefix||' '||min(m.statement_customer_code) end into target
  from public.customer_registry_statement_mapping m where m.shipment_id=any(ids);
  if target is null then raise exception '고객 ID 연결을 먼저 확인하세요.'; end if;
 end if;
 if target='' or length(target)>80 or target !~ '^[A-Za-z0-9][A-Za-z0-9 _-]*$' then raise exception 'INVALID_RECEIPT'; end if;
 if target is distinct from p_receipt then
  if exists(select 1 from public.shipments where id=any(ids) and (data_locked or receipt_number_locked)) then raise exception '번호 또는 자료 잠금을 먼저 해제하세요.'; end if;
  if exists(select 1 from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=target and not(id=any(ids)) and deleted_at is null) then raise exception 'DUPLICATE_RECEIPT'; end if;
  if exists(select 1 from public.receipt_discount_overrides where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage and receipt_number=target)
   or exists(select 1 from public.receipt_extra_costs where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=target) then raise exception '대상 번호에 연결된 할인·추가비용을 먼저 확인하세요.'; end if;
 end if;
 perform set_config('lkgroup.normalizing_shipments','1',true);
 insert into public.shipment_automation_history(route_key,shipment_year,voyage,receipt_mapping,prior_snapshots)
 values(rd.route_key,p_year,p_voyage,(select jsonb_agg(jsonb_build_object('shipment_id',id,'old_receipt',receipt_number,'new_receipt',target,'prior_locked',receipt_number_locked,'prior_override',receipt_number_override)) from public.shipments where id=any(ids)),case when target is distinct from p_receipt then coalesce((select jsonb_agg(to_jsonb(v)) from public.voyage_settlement_snapshots v where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage),'[]') else '[]'::jsonb end);
 if target is distinct from p_receipt then
  update public.receipt_extra_costs set receipt_number=target where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt;
  update public.receipt_discount_overrides set receipt_number=target where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt;
  update public.domestic_parcels set statement_receipt=target where statement_route=rd.display_name and statement_year=p_year and statement_voyage=p_voyage and statement_receipt=p_receipt;
  update public.domestic_parcels set link_receipt_number=target where link_route=rd.display_name and link_year=p_year and link_voyage=p_voyage and link_receipt_number=p_receipt;
  delete from public.voyage_settlement_snapshots where route_key in(rd.route_key,rd.display_name) and shipment_year=p_year and voyage=p_voyage;
 end if;
 update public.shipments set receipt_number=target,receipt_number_locked=coalesce(p_locked,receipt_number_locked),
 receipt_number_override=case when p_manual is false then null when p_manual is true or target is distinct from p_receipt then target else receipt_number_override end where id=any(ids);
 get diagnostics affected=row_count;
 perform set_config('lkgroup.normalizing_shipments','',true);
 return jsonb_build_object('rows',affected,'receipt_number',target);
end $function$

;
CREATE OR REPLACE FUNCTION public.admin_import_excel_statement_controls(p_route text, p_year integer, p_voyage text, p_controls jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item jsonb; rd public.route_definitions; n bigint; special boolean; current_number text; target text; baseline jsonb; ids bigint[]; request_count integer; applied integer:=0; pending integer:=0; legacy boolean:=not public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage);
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_controls)<>'array' or jsonb_array_length(p_controls)>1000 then raise exception 'INVALID_CONTROLS'; end if;
 if p_voyage='00' then return jsonb_build_object('applied',0,'pending',0); end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rd.route_key||'|'||p_year||'|'||p_voyage,0));
 for item in select value from jsonb_array_elements(p_controls) loop
  if coalesce(item->>'key','') !~ '^(ID\|[0-9]+\|[01]|UNKNOWN|LEGACY\|.+)$' then raise exception 'INVALID_CUSTOMER_KEY'; end if;
  if legacy and item->>'key' not like 'LEGACY|%' then raise exception '기존 항차 번호를 보존한 최신 Excel을 다시 다운로드하세요.'; end if;
  if not legacy and item->>'key' like 'LEGACY|%' then raise exception 'INVALID_CUSTOMER_KEY'; end if;
  n:=case when legacy or item->>'key'='UNKNOWN' then null else split_part(item->>'key','|',2)::bigint end;special:=split_part(item->>'key','|',3)='1';baseline:=item->'baseline';
  select array_agg(s.id),case when count(distinct s.receipt_number)=1 then min(s.receipt_number) end into ids,current_number
  from public.shipments s join public.customer_registry_statement_mapping m on m.shipment_id=s.id
  where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null and ((legacy and s.receipt_number=substr(item->>'key',8)) or (not legacy and n is not null and m.customer_no=n and public.lk_statement_special_prefix(s.consignee_name)=special) or (not legacy and n is null and m.customer_no is null and public.lk_excel_customer_key(s.consignee_name,s.consignee_phone)='XX'));
  if cardinality(ids) is null then continue; end if;
  if current_number is null then raise exception '같은 고객 ID에 여러 명세서가 있습니다. 앱·웹에서 번호별로 확인하세요.'; end if;
  target:=case when (item->>'locked')::boolean then nullif(btrim(item->>'fixed'),'') else coalesce(nullif(btrim(item->>'manual'),''),case when legacy then baseline->>'receipt_number' else rd.receipt_prefix||' '||case when n is null then 'XX' else public.lk_customer_statement_code(n,special) end end) end;
  if target is null or target !~ '^[A-Za-z0-9][A-Za-z0-9 _-]*$' or length(target)>80 then raise exception 'INVALID_RECEIPT'; end if;
  if current_number is distinct from baseline->>'receipt_number' and current_number is distinct from target then raise exception 'RECORD_CHANGED'; end if;
  if exists(select 1 from public.shipments where id=any(ids) and data_locked) and not (item->>'locked')::boolean then raise exception '자료 전체가 잠겨 있습니다. 기존 자료 잠금을 먼저 확인하세요.';end if;
  if (select bool_or(receipt_number_locked or data_locked) from public.shipments where id=any(ids)) is distinct from coalesce((baseline->>'locked')::boolean,false)
   and (select bool_or(receipt_number_locked or data_locked) from public.shipments where id=any(ids)) is distinct from (item->>'locked')::boolean then raise exception '잠금 상태가 변경되었습니다. 최신 Excel을 다시 다운로드하세요.';end if;
  if current_number=target then
   perform public.admin_set_statement_control(rd.display_name,p_year,p_voyage,current_number,null,(item->>'locked')::boolean,null);
   update public.shipments set receipt_number_override=nullif(btrim(item->>'manual'),'') where id=any(ids);
   applied:=applied+1;
  else
   -- An explicitly requested unlock must precede approving a new receipt.
   if not (item->>'locked')::boolean and coalesce((baseline->>'locked')::boolean,false) then perform public.admin_set_statement_control(rd.display_name,p_year,p_voyage,current_number,null,false,null); end if;
   insert into public.excel_statement_pending_controls(request_id,target_receipt,locked,manual_number,created_by)
   select q.id,target,(item->>'locked')::boolean,nullif(btrim(item->>'manual'),''),auth.uid() from public.shipment_change_requests q
   where q.shipment_id=any(ids) and q.status='pending' and q.request_source='excel_import' and q.changes->>'receipt_number'=target
   on conflict(request_id) do update set target_receipt=excluded.target_receipt,locked=excluded.locked,manual_number=excluded.manual_number,created_by=excluded.created_by,created_at=now(),applied_at=null;
   get diagnostics request_count=row_count;
   if request_count=0 then raise exception '명세서 번호 변경 승인을 먼저 확인하세요.'; end if;
   pending:=pending+1;
  end if;
 end loop;
 return jsonb_build_object('applied',applied,'pending',pending);
end $function$

;
