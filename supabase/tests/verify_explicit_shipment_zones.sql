-- Integration regression for the shared App/Web DB.
-- All fixtures, approval notifications and revisions roll back, even on success.
do $verify$
declare
  r text := '한국->라오스 해상'; y integer := 2099; v text := '97';
  target_id bigint; automatic_id bigint; custom_id bigint; req_id bigint;
  payload jsonb; result jsonb; row_data public.shipments%rowtype;
begin
  begin
    if exists(select 1 from public.shipments where shipment_year=y and voyage=v) then
      raise exception 'Zone regression voyage is not empty';
    end if;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true)
    from public.profiles where role='admin' and approval_status='approved'
      and coalesce(deletion_status,'active')='active' limit 1;
    if auth.uid() is null then raise exception 'Approved administrator required for regression'; end if;
    execute 'set local role authenticated';

    payload:=jsonb_build_object('route',r,'shipment_year',y,'voyage',v,
      'box_number','LK900001','import_key',r||'|'||y||'|'||v||'|LK900001',
      'consignee_name','뷰티판다','consignee_phone','02052934444',
      'quantity',25,'unloading_zone','F','notes','Zone regression');
    perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload));
    select id into strict target_id from public.shipments where import_key=payload->>'import_key';
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    if not exists(select 1 from public.shipments where id=target_id and unloading_zone='F'
      and unloading_zone_override is null) then raise exception 'Cached automatic Zone was frozen'; end if;

    -- A pending upload must not change live data before approval.
    perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||'{"unloading_zone":"ST"}'));
    select id into strict req_id from public.shipment_change_requests where shipment_id=target_id and status='pending';
    if (select unloading_zone from public.shipments where id=target_id)<>'F' then raise exception 'Unapproved change applied'; end if;
    perform public.review_shipment_change_request(req_id,'approve');
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    perform public.admin_finalize_excel_import_preserve_layout(r,y,v);
    if not exists(select 1 from public.shipments where id=target_id and unloading_zone='ST'
      and unloading_zone_override='ST') then raise exception 'Approved ST overwritten by finalization'; end if;
    result:=public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||'{"unloading_zone":"ST"}'));
    if (result->>'unchanged')::integer<>1 then raise exception 'Reupload generated a spurious Zone request'; end if;

    perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||'{"unloading_zone":"ST-2"}'));
    select id into strict req_id from public.shipment_change_requests where shipment_id=target_id and status='pending';
    perform public.review_shipment_change_request(req_id,'reject');
    if (select unloading_zone from public.shipments where id=target_id)<>'ST' then raise exception 'Rejected Zone applied'; end if;
    perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||'{"unloading_zone":"ST-2"}'));
    select id into strict req_id from public.shipment_change_requests where shipment_id=target_id and status='pending';
    perform public.review_shipment_change_request(req_id,'modified_approve','{"unloading_zone":"창고-2"}');
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    if (select unloading_zone from public.shipments where id=target_id)<>'창고-2' then raise exception 'Modified approval lost'; end if;

    insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,quantity)
      values(r,y,v,'LK900002','ZoneRegressionAlpha','02055558881',1) returning id into automatic_id;
    if not exists(select 1 from public.shipments where id=automatic_id and unloading_zone='A'
      and unloading_zone_override is null) then raise exception 'Automatic A failed'; end if;
    update public.shipments set quantity=12 where id=automatic_id;
    if (select unloading_zone from public.shipments where id=automatic_id)<>'C' then raise exception 'Automatic quantity C failed'; end if;
    update public.shipments set unloading_zone='B' where id=automatic_id;
    update public.shipments set quantity=25 where id=automatic_id;
    if not exists(select 1 from public.shipments where id=automatic_id and unloading_zone='B'
      and unloading_zone_override='B') then raise exception 'Explicit standard Zone was overwritten'; end if;
    update public.shipments set unloading_zone='' where id=automatic_id;
    if not exists(select 1 from public.shipments where id=automatic_id and unloading_zone='F'
      and unloading_zone_override is null) then raise exception 'Clearing Zone did not restore automatic rules'; end if;

    -- New Excel rows and both client bulk editors use arbitrary text.
    perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||
      jsonb_build_object('box_number','LK900003','import_key',r||'|'||y||'|'||v||'|LK900003',
        'consignee_name','ZoneRegressionBeta','consignee_phone','02055558882','unloading_zone','ST')));
    select * into strict row_data from public.shipments where route=r and shipment_year=y and voyage=v and box_number='LK900003';
    custom_id:=row_data.id;
    perform public.admin_excel_bulk_update(row_data.id,row_data.box_number,row_data.invoice_number,
      row_data.sender_name,row_data.consignee_name,row_data.consignee_phone,row_data.receipt_number,'Z-임시',row_data.notes);
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    if (select unloading_zone from public.shipments where id=custom_id)<>'Z-임시' then raise exception 'Bulk editor Zone lost'; end if;

    select * into row_data from public.admin_add_shipment_row(r,y,v,'LK900004',
      p_consignee_name=>'ZoneRegressionGamma',p_consignee_phone=>'02055558883',p_unloading_zone=>'B');
    if not exists(select 1 from public.shipments where id=row_data.id and unloading_zone='B'
      and unloading_zone_override='B') then raise exception 'App manual add Zone lost'; end if;
    select * into row_data from public.web_add_next_shipment(r,y,v,
      p_consignee_name=>'ZoneRegressionDelta',p_consignee_phone=>'02055558884',p_unloading_zone=>'ST-WEB');
    if not exists(select 1 from public.shipments where id=row_data.id and unloading_zone='ST-WEB'
      and unloading_zone_override='ST-WEB') then raise exception 'Web manual add Zone lost'; end if;

    execute 'reset role'; -- Internal maintenance functions are not client RPCs.
    perform public.normalize_shipment_batch_fast_impl(r,y,v);
    perform public.lk_apply_excel_logic_parity(r,y,v);
    execute 'set local role authenticated';
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    if (select unloading_zone from public.shipments where id=target_id)<>'창고-2'
      or (select unloading_zone from public.shipments where id=custom_id)<>'Z-임시'
      or (select unloading_zone_override from public.shipments where id=automatic_id) is not null
      then raise exception 'Legacy recalculation lost custom Zone or froze automatic Zone'; end if;
    update public.shipments set data_locked=true where id=custom_id;
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
    if (select unloading_zone from public.shipments where id=custom_id)<>'Z-임시' then raise exception 'Locked Zone changed'; end if;
    if current_setting('lkgroup.calculating_zone',true)='1'
      or current_setting('lkgroup.normalizing_shipments',true)='1'
      or current_setting('lkgroup.bulk_import',true)='1' then raise exception 'Calculation context leaked'; end if;
    if has_function_privilege('anon','public.capture_shipment_zone_override()','EXECUTE') then
      raise exception 'Trigger function exposed to anonymous callers';
    end if;
    raise exception using errcode='Z0001',message='Zone regression passed; rolling back fixtures';
  exception when sqlstate 'Z0001' then null;
  end;
  if exists(select 1 from public.shipments where shipment_year=y and voyage=v) then
    raise exception 'Zone regression fixtures were not rolled back';
  end if;
end $verify$;
