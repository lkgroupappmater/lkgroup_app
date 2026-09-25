-- Reproduce the pending batch without committing any approval or cargo change.
-- The nested exception rolls back every table mutation, including notifications.
do $test$
declare
  admin_id uuid; requests jsonb; request_ids bigint[]; cargo_ids bigint[];
  before_cargo jsonb; before_requests jsonb; before_revisions jsonb;
  after_cargo jsonb; after_requests jsonb; notification_count bigint;
  started timestamptz; elapsed_ms numeric; changed_identities integer;
begin
  select q.requested_by into admin_id
  from public.shipment_change_requests q join public.profiles p on p.id=q.requested_by
  join public.shipments s on s.id=q.shipment_id
  where q.status='pending' and q.request_source='excel_import'
    and s.route=(select display_name from public.route_definitions where route_key='kr_la_sea')
    and s.shipment_year=2026 and s.voyage='09'
    and p.role='admin' and p.approval_status='approved' and p.deletion_status='active'
  order by q.id desc limit 1;
  if admin_id is null then raise exception 'No authorized pending-batch requester for regression'; end if;
  select jsonb_agg(jsonb_build_object('request_id',q.id,'action','approve') order by q.id),
    array_agg(q.id),array_agg(s.id),
    count(*) filter(where (q.changes?'consignee_name' and q.changes->>'consignee_name' is distinct from s.consignee_name)
      or (q.changes?'consignee_phone' and q.changes->>'consignee_phone' is distinct from s.consignee_phone))
    into requests,request_ids,cargo_ids,changed_identities
  from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id
  where q.status='pending' and q.request_source='excel_import'
    and s.route=(select display_name from public.route_definitions where route_key='kr_la_sea')
    and s.shipment_year=2026 and s.voyage='09';
  if jsonb_array_length(requests)<282 then raise exception 'Reported 282-request regression batch has changed; re-inspect first'; end if;
  select jsonb_agg(to_jsonb(s) order by s.id) into before_cargo from public.shipments s where id=any(cargo_ids);
  select jsonb_agg(to_jsonb(q) order by q.id) into before_requests from public.shipment_change_requests q where id=any(request_ids);
  select jsonb_agg(to_jsonb(r) order by r.topic) into before_revisions from public.app_data_revisions r;
  select count(*) into notification_count from public.user_notifications where related_request_id=any(request_ids);
  begin
    perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
    started:=clock_timestamp();
    perform public.review_shipment_change_requests(requests);
    elapsed_ms:=extract(epoch from clock_timestamp()-started)*1000;
    if exists(select 1 from public.shipment_change_requests q where id=any(request_ids) and status<>'approved') then raise exception 'Selected approval missing'; end if;
    if exists(select 1 from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id where q.id=any(request_ids) and public.lk_excel_import_changes(q.changes,s)<>'{}') then raise exception 'Approved values differ from requested values'; end if;
    if exists(select 1 from public.shipments s join jsonb_array_elements(before_cargo) b on s.id=(b->>'id')::bigint
       where ((s.consignee_name is distinct from b->>'consignee_name') or (s.consignee_phone is distinct from b->>'consignee_phone'))
         and s.special_note_auto is distinct from public.compute_shipment_special_note(s.route,s.consignee_name,s.consignee_phone)) then raise exception 'Changed-identity Remark stale'; end if;
    if exists(select 1 from public.shipments s join jsonb_array_elements(before_cargo) b on s.id=(b->>'id')::bigint
       where s.consignee_name is not distinct from b->>'consignee_name' and s.consignee_phone is not distinct from b->>'consignee_phone'
         and s.special_note_auto is distinct from b->>'special_note_auto') then raise exception 'Unchanged-identity Remark changed'; end if;
    if current_setting('lkgroup.bulk_import',true)='1' then raise exception 'Bulk context leaked'; end if;
    raise sqlstate 'ZQ001' using message='Rollback successful approval regression';
  exception when sqlstate 'ZQ001' then null;
  end;
  select jsonb_agg(to_jsonb(s) order by s.id) into after_cargo from public.shipments s where id=any(cargo_ids);
  select jsonb_agg(to_jsonb(q) order by q.id) into after_requests from public.shipment_change_requests q where id=any(request_ids);
  if after_cargo is distinct from before_cargo or after_requests is distinct from before_requests then raise exception 'Regression failed to roll back business data'; end if;
  if (select count(*) from public.user_notifications where related_request_id=any(request_ids))<>notification_count then raise exception 'Regression notification leaked'; end if;
  if (select jsonb_agg(to_jsonb(r) order by r.topic) from public.app_data_revisions r) is distinct from before_revisions then raise exception 'Regression revision leaked'; end if;
  if elapsed_ms>20000 then raise exception 'Bulk approval still too slow: % ms',elapsed_ms; end if;
  perform set_config('lkgroup.review_timeout_test',jsonb_build_object('requests',jsonb_array_length(requests),'changed_identities',changed_identities,'duration_ms',elapsed_ms,'all_values_applied',true,'all_mutations_rolled_back',true)::text,true);
end $test$;
select current_setting('lkgroup.review_timeout_test')::jsonb as result;
