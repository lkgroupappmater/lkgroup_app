-- All fixture rows, approval requests and notifications are rolled back.
begin;
do $$
declare
 admin_id uuid; member_id uuid; r text; rows jsonb; p jsonb; result jsonb; again jsonb;
 a bigint; b bigint; c bigint; other bigint; qa bigint; qb bigint; qc bigint;
 before_a jsonb; before_other jsonb; blocked boolean;
begin
 select id into admin_id from public.profiles where role='admin' and approval_status='approved' and deletion_status='active' limit 1;
 select id into member_id from public.profiles where role='member' and approval_status='approved' and deletion_status='active' limit 1;
 select display_name into r from public.route_definitions where route_key='kr_la_sea';
 if exists(select 1 from public.shipments where route=r and shipment_year=2099 and voyage in ('97','98')) then raise exception 'fixture voyage occupied'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 perform set_config('lkgroup.bulk_import','1',true);
 insert into public.shipments(route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,quantity,receipt_number,import_key,data_locked)
 values(r,2099,'97','QA001','INV001','Before','01011111111',1,'LKS 01',r||'|2099|97|QA001',true) returning id into a;
 insert into public.shipments(route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,quantity,receipt_number,import_key)
 values(r,2099,'97','QA002','INV002','Second','01022222222',2,'LKS 02',r||'|2099|97|QA002') returning id into b;
 insert into public.shipments(route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,quantity,receipt_number,import_key)
 values(r,2099,'97','QA003','INV003','Third','01033333333',3,'LKS 03',r||'|2099|97|QA003') returning id into c;
 insert into public.shipments(route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,quantity,import_key)
 values(r,2099,'98','QA001','OTHER','Other','01011111111',4,r||'|2099|98|QA001') returning id into other;
 select to_jsonb(s) into before_a from public.shipments s where id=a;
 select to_jsonb(s) into before_other from public.shipments s where id=other;
 insert into public.receipt_extra_costs(route,shipment_year,voyage,receipt_number,cost_name,amount_usd) values(r,2099,'97','LKS 01','Review fixture',12.5);
 insert into public.receipt_discount_overrides(route_key,shipment_year,voyage,receipt_number,discount_name,discount_percent) values('kr_la_sea',2099,'97','LKS 01','Review fixture A',0.03),('kr_la_sea',2099,'97','LKS 02','Review fixture B',0.05);
 rows:=jsonb_build_array(
  jsonb_build_object('route',r,'shipment_year',2099,'voyage','97','box_number','QA002','invoice_number','INV001','sender_name','New sender','consignee_name','박성호대표','consignee_phone','02099999999','contents','Changed contents','package_type','Box','quantity',9,'weight_kg',10.5,'length_cm',12,'width_cm',13,'height_cm',14,'receipt_number','LKS 02','unloading_zone','B','notes','Changed note','received_at','2026-09-25'),
  jsonb_build_object('route',r,'shipment_year',2099,'voyage','97','box_number','QA001','invoice_number','INV002','consignee_name','Second','consignee_phone','01022222222','quantity',2,'receipt_number','LKS 01'));
 p:=public.admin_preview_shipment_excel_sync(rows);
 result:=public.admin_apply_shipment_excel_sync(rows,p->>'preview_token');
 if (result->>'change_requests')::int<>3 then raise exception 'updates and removal not queued: %',result; end if;
 if (select to_jsonb(s) from public.shipments s where id=a)<>before_a or exists(select 1 from public.shipments where id=c and deletion_requested_at is not null) then raise exception 'cargo modified before approval'; end if;
 if public.admin_apply_shipment_excel_sync(rows,p->>'preview_token')<>result then raise exception 'retry not idempotent'; end if;
 p:=public.admin_preview_shipment_excel_sync(rows);
 again:=public.admin_apply_shipment_excel_sync(rows,p->>'preview_token');
 if (again->>'already_pending')::int<>3 or (again->>'change_requests')::int<>0 then raise exception 'duplicate requests created'; end if;
 select id into qa from public.shipment_change_requests where shipment_id=a and status='pending';
 select id into qb from public.shipment_change_requests where shipment_id=b and status='pending';
 select id into qc from public.shipment_change_requests where shipment_id=c and status='pending';
 if not exists(select 1 from public.get_pending_shipment_change_requests() where request_id=qa and requested_changes ?& array['box_number','receipt_number','sender_name','contents','package_type','quantity','weight_kg','length_cm','width_cm','height_cm','unloading_zone','notes','received_at','consignee_phone','consignee_name']) then raise exception 'approval list omits fields'; end if;
 if not exists(select 1 from public.get_pending_shipment_change_requests() where request_id=qc and requested_changes->>'_excel_action'='삭제함 이동') then raise exception 'removal hidden by reconciliation'; end if;
 perform public.admin_finalize_excel_batch_rules_fast(r,2099,'97',true);
 if not exists(select 1 from public.shipments where id=a and receipt_number='LKS 01') then raise exception 'finalizer bypassed review'; end if;
 blocked:=false;
 begin perform public.review_shipment_change_request(qa,'approve'); exception when others then blocked:=true; end;
 if not blocked or not exists(select 1 from public.shipment_change_requests where id=qa and status='pending') then raise exception 'partial swap must roll back'; end if;
 perform public.review_shipment_change_requests(jsonb_build_array(jsonb_build_object('request_id',qa,'action','approve'),jsonb_build_object('request_id',qb,'action','approve'),jsonb_build_object('request_id',qc,'action','approve')));
 if not exists(select 1 from public.shipments where id=a and box_number='QA002' and receipt_number='LKS 02' and consignee_name='박성호대표' and quantity=9 and weight_kg=10.5 and data_locked) then raise exception 'approved values failed'; end if;
 if not exists(select 1 from public.shipments where id=a and special_note_auto like '%대표 고정 할인%' and special_note_auto=public.compute_shipment_special_note(route,consignee_name,consignee_phone)) then raise exception 'changed identity did not refresh automatic Remark'; end if;
 if not exists(select 1 from public.shipments where id=b and box_number='QA001' and receipt_number='LKS 01') then raise exception 'swap lost identity'; end if;
 if not exists(select 1 from public.shipments where id=c and deletion_requested_at=excel_removed_at and import_key is null) then raise exception 'approved removal missing'; end if;
 if not exists(select 1 from public.receipt_extra_costs where route=r and shipment_year=2099 and voyage='97' and receipt_number='LKS 02' and amount_usd=12.5) then raise exception 'receipt cost not moved'; end if;
 if not exists(select 1 from public.receipt_discount_overrides where route_key='kr_la_sea' and shipment_year=2099 and voyage='97' and receipt_number='LKS 01' and discount_name='Review fixture B') then raise exception 'receipt discount swap failed'; end if;
 perform public.admin_finalize_excel_batch_rules_fast(r,2099,'97',true);
 if not exists(select 1 from public.shipments where id=b and receipt_number='LKS 01') then raise exception 'approved receipt overwritten'; end if;
 rows:=rows||jsonb_build_array(jsonb_build_object('route',r,'shipment_year',2099,'voyage','97','box_number','QA003','invoice_number','INV003','consignee_name','Restored','consignee_phone','01033333333','quantity',3,'receipt_number','LKS 03'));
 rows:=jsonb_set(rows,'{0,receipt_number}','"LKS 77"');
 p:=public.admin_preview_shipment_excel_sync(rows);
 perform public.admin_apply_shipment_excel_sync(rows,p->>'preview_token');
 select id into qa from public.shipment_change_requests where shipment_id=a and status='pending';
 select id into qc from public.shipment_change_requests where shipment_id=c and status='pending';
 if not exists(select 1 from public.shipments where id=c and deletion_requested_at is not null) then raise exception 'restore bypassed review'; end if;
 perform public.review_shipment_change_request(qa,'reject');
 perform public.review_shipment_change_request(qc,'approve');
 if not exists(select 1 from public.shipments where id=a and receipt_number='LKS 02') then raise exception 'reject changed receipt'; end if;
 if not exists(select 1 from public.shipments where id=c and deletion_requested_at is null and excel_removed_at is null and consignee_name='Restored' and import_key=r||'|2099|97|QA003') then raise exception 'restore lost original identity'; end if;
 p:=public.admin_preview_shipment_excel_sync(rows);
 perform public.admin_apply_shipment_excel_sync(rows,p->>'preview_token');
 select id into qa from public.shipment_change_requests where shipment_id=a and status='pending';
 perform public.review_shipment_change_request(qa,'modified_approve','{"receipt_number":"LKS 88"}');
 if not exists(select 1 from public.shipments where id=a and receipt_number='LKS 88') then raise exception 'modified receipt approval failed'; end if;
 if (select to_jsonb(s) from public.shipments s where id=other)<>before_other then raise exception 'other voyage changed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',member_id,'role','authenticated')::text,true);
 blocked:=false;
 begin perform public.admin_preview_shipment_excel_sync(rows); exception when others then blocked:=true; end;
 if not blocked then raise exception 'member can import'; end if;
 blocked:=false;
 begin perform public.review_shipment_change_request(qa,'approve'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'member can approve'; end if;
end $$;
rollback;
