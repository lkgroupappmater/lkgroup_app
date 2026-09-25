-- Fix bulk approval timeout without changing validation, authorization,
-- receipt charge remapping, atomicity, or the 60-second API timeout.
CREATE OR REPLACE FUNCTION public.review_shipment_change_requests(p_requests jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '60s'
AS $function$
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
 -- Apply the selected batch in one statement. Receipt/quantity-only edits do
 -- not touch identity columns: their UPDATE OF triggers are expensive even
 -- when the assigned identity is unchanged.
 with desired as materialized (
  select p.shipment_id,p.final_values,c.* from pg_temp._lk_review p
  cross join lateral jsonb_populate_record(null::public.shipments,p.before_values||p.final_values) c
  where p.action<>'reject'
 )
  update public.shipments s set
   box_number=desired_row.box_number,import_key=case when desired_row.final_values->>'_excel_action'='삭제함 이동' then null else desired_row.route||'|'||desired_row.shipment_year||'|'||desired_row.voyage||'|'||desired_row.box_number end,
   invoice_number=desired_row.invoice_number,sender_name=desired_row.sender_name,contents=desired_row.contents,package_type=desired_row.package_type,quantity=desired_row.quantity,weight_kg=desired_row.weight_kg,length_cm=desired_row.length_cm,width_cm=desired_row.width_cm,height_cm=desired_row.height_cm,
   receipt_number=desired_row.receipt_number,unloading_zone=desired_row.unloading_zone,unloading_zone_override=case when desired_row.final_values?'unloading_zone' then nullif(btrim(desired_row.unloading_zone),'') else s.unloading_zone_override end,notes=desired_row.notes,received_at=desired_row.received_at,
   deletion_requested_at=case when desired_row.final_values->>'_excel_action'='삭제함 이동' then now() when desired_row.final_values->>'_excel_action'='복원' then null else s.deletion_requested_at end,
   deletion_requested_by=case when desired_row.final_values->>'_excel_action'='삭제함 이동' then auth.uid() when desired_row.final_values->>'_excel_action'='복원' then null else s.deletion_requested_by end,
   excel_removed_at=case when desired_row.final_values->>'_excel_action'='삭제함 이동' then now() when desired_row.final_values->>'_excel_action'='복원' then null else s.excel_removed_at end,
   updated_at=now()
  from desired desired_row where s.id=desired_row.shipment_id;

 -- Identity-dependent Remark/discount/delivery and identity-group triggers
 -- run exactly once, and only for identities that actually changed. Keep
 -- those existing triggers authoritative; no parallel calculation or bypass.
 with desired as materialized (
  select p.shipment_id,p.final_values,c.* from pg_temp._lk_review p
  cross join lateral jsonb_populate_record(null::public.shipments,p.before_values||p.final_values) c
  where p.action<>'reject'
 )
 update public.shipments s
 set consignee_name=desired_row.consignee_name,consignee_phone=desired_row.consignee_phone
 from desired desired_row where s.id=desired_row.shipment_id
  and (s.consignee_name is distinct from desired_row.consignee_name
    or s.consignee_phone is distinct from desired_row.consignee_phone);
 update public.receipt_extra_costs e set receipt_number=m.new_receipt from _lk_review_receipt_map m where e.route=m.route and e.shipment_year=m.shipment_year and e.voyage=m.voyage and btrim(e.receipt_number)=m.old_receipt;
 update public.receipt_discount_overrides d set receipt_number='__LK_REVIEW__'||m.new_receipt from _lk_review_receipt_map m join public.route_definitions rd on m.route in(rd.route_key,rd.display_name) where d.route_key=rd.route_key and d.shipment_year=m.shipment_year and d.voyage=m.voyage and btrim(d.receipt_number)=m.old_receipt;
 update public.receipt_discount_overrides d set receipt_number=substr(d.receipt_number,14) where left(d.receipt_number,13)='__LK_REVIEW__';
 delete from public.voyage_settlement_snapshots s using _lk_review p,public.route_definitions rd where p.action<>'reject' and p.before_values->>'route' in(rd.route_key,rd.display_name) and s.route_key in(rd.route_key,rd.display_name) and s.shipment_year=(p.before_values->>'shipment_year')::integer and s.voyage=p.before_values->>'voyage';
 -- Reconcile only selected cargo and write notifications as sets.
 update public.shipment_change_requests q
 set status='already_applied',reviewed_at=now(),reviewed_by=null,review_result=null
 from public.shipments s
 where s.id=q.shipment_id and q.status='pending' and q.request_source='excel_import'
  and exists(select 1 from pg_temp._lk_review p where p.shipment_id=s.id)
  and public.lk_excel_import_changes(q.changes,s)='{}'::jsonb;
 insert into public.user_notifications(user_id,notification_type,title,message,related_request_id)
 select q.requested_by,'shipment_change','화물 정보 수정 요청',
  case when p.action='reject' then '수정 요청이 거절 되었습니다.' else '승인 되었습니다.' end,q.id
 from public.shipment_change_requests q join pg_temp._lk_review p on p.request_id=q.id
 where q.requested_by is not null;
 for batch in select distinct before_values->>'route' route,(before_values->>'shipment_year')::integer AS shipment_year,before_values->>'voyage' voyage from _lk_review where action<>'reject' and source<>'excel_import' loop
  perform public.normalize_shipment_batch(batch.route,batch.shipment_year,batch.voyage);
 end loop;
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
exception when unique_violation then
 perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
 raise exception '변경할 화물번호가 이미 사용 중입니다. 번호를 교환하는 요청은 함께 선택해 승인해 주세요.';
when others then perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true); raise;
end $function$;
notify pgrst,'reload schema';
