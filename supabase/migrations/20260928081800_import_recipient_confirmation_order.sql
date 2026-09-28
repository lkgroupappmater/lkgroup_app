-- Display order is independent of issued bill numbers and their locks.
create or replace function public.admin_import_recipient_confirmation_order(
 p_route text,p_year integer,p_voyage text,p_items jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare rd public.route_definitions; item jsonb; ids bigint[]; old_order bigint; requested bigint; affected integer:=0; n integer;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>1000 then raise exception 'INVALID_CONTROLS'; end if;
 if p_voyage='00' then return 0; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended('recipient_recovered_order',0));
 perform set_config('lkgroup.import_recipient_order','yes',true);
 for item in select value from jsonb_array_elements(p_items) loop
  if coalesce(item->>'order','') !~ '^[0-9]{1,9}$' then raise exception '확인 순서는 양의 정수로 입력하세요.'; end if;
  requested:=(item->>'order')::bigint;
  if requested<1 then raise exception '확인 순서는 양의 정수로 입력하세요.'; end if;
  select array_agg(s.id),min(s.recipient_recovered_order) into ids,old_order
  from public.shipments s left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
  where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage
   and s.deleted_at is null and s.deletion_requested_at is null
   and public.lk_unknown_prefix_zone(s.consignee_name)
   and public.lk_excel_recovered_name(s.consignee_name,s.consignee_phone) is not null
   and ((item->>'key' like 'LEGACY|%' and s.receipt_number=substr(item->>'key',8))
    or item->>'key'='ID|'||m.customer_no||'|1');
  if cardinality(ids) is null then raise exception '확인 순서를 적용할 고객이 아직 반영되지 않았습니다. 고객 변경 승인 후 다시 업로드하세요.'; end if;
  if coalesce((item->>'baseline_order')::bigint,0)>0 and old_order is distinct from (item->>'baseline_order')::bigint and old_order is distinct from requested then raise exception '확인 순서가 변경되었습니다. 최신 Excel을 다시 다운로드하세요.'; end if;
  update public.shipments set recipient_recovered_order=requested where id=any(ids) and recipient_recovered_order is distinct from requested;
  get diagnostics n=row_count;affected:=affected+n;
 end loop;
 if exists(select 1 from public.shipments s where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null and s.recipient_recovered_order is not null
   group by s.recipient_recovered_order having count(distinct public.lk_excel_customer_key(s.consignee_name,s.consignee_phone))>1) then raise exception '서로 다른 고객의 확인 순서가 중복되었습니다.'; end if;
 perform setval('public.recipient_recovered_order_seq',greatest((select last_value from public.recipient_recovered_order_seq),(select coalesce(max(recipient_recovered_order),1) from public.shipments)),true);
 perform set_config('lkgroup.import_recipient_order','',true);
 return affected;
end $$;
revoke all on function public.admin_import_recipient_confirmation_order(text,integer,text,jsonb) from public,anon;
grant execute on function public.admin_import_recipient_confirmation_order(text,integer,text,jsonb) to authenticated;

create or replace function public.capture_recipient_recovered_order()
returns trigger language plpgsql set search_path=public as $$
begin
 if current_setting('lkgroup.import_recipient_order',true)='yes' then return new; end if;
 if tg_op='UPDATE' and old.recipient_recovered_order is not null then
   new.recipient_recovered_order:=old.recipient_recovered_order;
 elsif public.lk_unknown_prefix_zone(new.consignee_name)
   and public.lk_excel_recovered_name(new.consignee_name,new.consignee_phone) is not null then
   perform pg_advisory_xact_lock(hashtextextended('recipient_recovered_order',0));
   select min(s.recipient_recovered_order) into new.recipient_recovered_order
     from public.shipments s where s.route=new.route and s.shipment_year=new.shipment_year and s.voyage=new.voyage
       and public.lk_excel_customer_key(s.consignee_name,s.consignee_phone)=public.lk_excel_customer_key(new.consignee_name,new.consignee_phone)
       and s.deleted_at is null and s.deletion_requested_at is null;
   new.recipient_recovered_order:=coalesce(new.recipient_recovered_order,nextval('public.recipient_recovered_order_seq'));
 else new.recipient_recovered_order:=null;
 end if;
 return new;
end $$;
