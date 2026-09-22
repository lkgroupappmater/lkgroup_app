-- Run after the migration. All test data, queue changes and notifications roll back.
do $test$
declare r text:='한국->라오스 해상'; y integer:=2099; v text:='96';
  payload jsonb; candidate jsonb; result jsonb; s public.shipments%rowtype;
  first_request bigint; combined_request bigint; visible jsonb;
begin
 begin
  if exists(select 1 from public.shipments where shipment_year=y and voyage=v) then raise exception 'Test voyage occupied'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true)
  from public.profiles where role='admin' and approval_status='approved' and coalesce(deletion_status,'active')='active' limit 1;
  if auth.uid() is null then raise exception 'Approved admin required'; end if;
  execute 'set local role authenticated';
  payload:=jsonb_build_object('route',r,'shipment_year',y,'voyage',v,'box_number','LK990001',
    'import_key',r||'|'||y||'|'||v||'|LK990001','consignee_name','ZoneApprovalRegression',
    'consignee_phone','02055559991','quantity',25,'unloading_zone','F','notes','original');
  perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload));
  perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
  select * into strict s from public.shipments where import_key=payload->>'import_key';

  perform public.manager_import_shipment_differences_bulk(jsonb_build_array(payload||'{"unloading_zone":"C"}'));
  select id into strict first_request from public.shipment_change_requests where shipment_id=s.id and status='pending';
  candidate:=payload||'{"unloading_zone":"C","notes":"Excel note"}';
  perform public.manager_import_shipment_differences_bulk(jsonb_build_array(candidate));
  select id into strict combined_request from public.shipment_change_requests where shipment_id=s.id and status='pending' and id<>first_request;
  update public.shipments set unloading_zone='C' where id=s.id;
  -- A partially applied old request and the same new Excel diff are one request.
  result:=public.manager_preview_shipment_import(jsonb_build_array(candidate));
  if (result->>'already_pending')::integer<>1 or (result->>'change_requests')::integer<>0 then raise exception 'Partial request duplicated in preview'; end if;
  result:=public.manager_import_shipment_differences_bulk(jsonb_build_array(candidate));
  if (result->>'already_pending')::integer<>1 or (result->>'change_requests')::integer<>0 then raise exception 'Partial request duplicated on import'; end if;
  if not exists(select 1 from public.shipment_change_requests where id=first_request and status='already_applied'
    and reviewed_by is null and review_result is null and changes='{"unloading_zone":"C"}') then raise exception 'No-op audit was erased or fabricated as approval'; end if;
  select to_jsonb(a) into strict visible from public.get_pending_shipment_change_requests() a where a.request_id=combined_request;
  if visible->'requested_changes'<>'{"notes":"Excel note"}' or visible->>'unloading_zone'<>'C' then raise exception 'Queue shows equal fields or stale current Zone'; end if;
  if (select changes from public.shipment_change_requests where id=combined_request)<> '{"unloading_zone":"C","notes":"Excel note"}' then raise exception 'Original request audit was altered'; end if;
  perform public.review_shipment_change_request(first_request,'approve');
  perform public.review_shipment_change_request(combined_request,'approve');
  perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
  result:=public.manager_preview_shipment_import(jsonb_build_array(candidate));
  if (result->>'unchanged')::integer<>1 then raise exception 'Approved F to C reappears'; end if;
  result:=public.manager_import_shipment_differences_bulk(jsonb_build_array(candidate));
  if (result->>'unchanged')::integer<>1 then raise exception 'Identical C upload is not idempotent'; end if;

  -- Every editable Excel field persists through review and both client finalizers.
  candidate:=candidate||jsonb_build_object('invoice_number','QA-INV-1234','sender_name','QA Sender',
    'consignee_name','ZoneApprovalRegression','consignee_phone','02055559991','contents','Clothes',
    'package_type','box','quantity',26,'weight_kg',12.5,'length_cm',45,'width_cm',35,'height_cm',25,
    'receipt_number',s.receipt_number,'unloading_zone','ST','notes','Reviewed Excel data','received_at','2026-09-22');
  perform public.manager_import_shipment_differences_bulk(jsonb_build_array(candidate));
  select id into strict combined_request from public.shipment_change_requests where shipment_id=s.id and status='pending';
  perform public.review_shipment_change_request(combined_request,'modified_approve','{}');
  perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
  perform public.admin_finalize_excel_import_preserve_layout(r,y,v);
  select * into strict s from public.shipments where id=s.id;
  execute 'reset role'; -- Compare persisted rows with the internal canonical diff.
  if public.lk_excel_import_changes(candidate,s)<>'{}' then raise exception 'Approved Excel data differs: %',public.lk_excel_import_changes(candidate,s); end if;
  execute 'set local role authenticated';
  for i in 1..2 loop
    result:=public.manager_preview_shipment_import(jsonb_build_array(candidate));
    if (result->>'unchanged')::integer<>1 or (result->>'change_requests')::integer<>0 then raise exception 'ST to ST preview reappears'; end if;
    result:=public.manager_import_shipment_differences_bulk(jsonb_build_array(candidate));
    if (result->>'unchanged')::integer<>1 or (result->>'change_requests')::integer<>0 then raise exception 'ST to ST import reappears'; end if;
    perform public.admin_finalize_excel_batch_rules_fast(r,y,v);
  end loop;
  if exists(select 1 from public.get_pending_shipment_change_requests() a where a.shipment_id=s.id) then raise exception 'Already-applied cargo still in approval queue'; end if;
  if has_function_privilege('anon','public.get_pending_shipment_change_requests()','EXECUTE')
    or has_function_privilege('authenticated','public.reconcile_applied_excel_requests(bigint)','EXECUTE') then raise exception 'Internal request cleanup exposed'; end if;
  raise exception using errcode='Z0002',message='Regression passed; roll back fixtures';
 exception when sqlstate 'Z0002' then null;
 end;
 if exists(select 1 from public.shipments where shipment_year=y and voyage=v) then raise exception 'Test fixture escaped rollback'; end if;
end $test$;
