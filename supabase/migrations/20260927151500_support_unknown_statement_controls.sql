create or replace function public.admin_import_excel_statement_controls(p_route text,p_year integer,p_voyage text,p_controls jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; rd public.route_definitions; n bigint; special boolean; current_number text; target text; baseline jsonb; ids bigint[]; request_count integer; applied integer:=0; pending integer:=0;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_controls)<>'array' or jsonb_array_length(p_controls)>1000 then raise exception 'INVALID_CONTROLS'; end if;
 if p_voyage='00' then return jsonb_build_object('applied',0,'pending',0); end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rd.route_key||'|'||p_year||'|'||p_voyage,0));
 for item in select value from jsonb_array_elements(p_controls) loop
  if coalesce(item->>'key','') !~ '^(ID\|[0-9]+\|[01]|UNKNOWN)$' then raise exception 'INVALID_CUSTOMER_KEY'; end if;
  n:=case when item->>'key'='UNKNOWN' then null else split_part(item->>'key','|',2)::bigint end;special:=split_part(item->>'key','|',3)='1';baseline:=item->'baseline';
  select array_agg(s.id),case when count(distinct s.receipt_number)=1 then min(s.receipt_number) end into ids,current_number
  from public.shipments s join public.customer_registry_statement_mapping m on m.shipment_id=s.id
  where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null and ((n is not null and m.customer_no=n and public.lk_statement_special_prefix(s.consignee_name)=special) or (n is null and m.customer_no is null and public.lk_excel_customer_key(s.consignee_name,s.consignee_phone)='XX'));
  if cardinality(ids) is null then continue; end if;
  if current_number is null then raise exception '같은 고객 ID에 여러 명세서가 있습니다. 앱·웹에서 번호별로 확인하세요.'; end if;
  target:=case when (item->>'locked')::boolean then nullif(btrim(item->>'fixed'),'') else coalesce(nullif(btrim(item->>'manual'),''),rd.receipt_prefix||' '||case when n is null then 'XX' else public.lk_customer_statement_code(n,special) end) end;
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
end $$;
