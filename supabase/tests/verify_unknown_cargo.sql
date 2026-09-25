-- Rollback-only fixtures. No real cargo, receipts or approvals are changed.
begin;
do $$
declare admin_id uuid; member_id uuid; r text; a bigint; b bigint; c bigint; d bigint; e bigint;
 q bigint; claim_id bigint; blocked boolean; before_receipt text;
begin
 select id into admin_id from public.profiles where role='admin' and approval_status='approved' and deletion_status='active' limit 1;
 select id into member_id from public.profiles where role='member' and approval_status='approved' and deletion_status='active' limit 1;
 select display_name into r from public.route_definitions where route_key='kr_la_sea';
 if admin_id is null or member_id is null then raise exception 'approved test roles unavailable'; end if;
 if exists(select 1 from public.shipments where route=r and shipment_year=2099 and voyage='96') then raise exception 'fixture voyage occupied'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 perform set_config('lkgroup.bulk_import','1',true);
 insert into public.shipments(route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,receipt_number,created_at)
 values(r,2099,'96','QAUNKNOWN','QAUNKNOWN','수취인 불명','?', 'LKS XX','2020-01-01') returning id into a;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number)
 values(r,2099,'96','QAINCOMPLETE','가나다','?', 'LKS 02') returning id into b;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number,manual_uncertain)
 values(r,2099,'96','QAMANUAL','라마바','01012345678','LKS 03',true) returning id into c;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number)
 values(r,2099,'96','QAKNOWN','사아자','01012345678','LKS 04') returning id into d;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number,data_locked)
 values(r,2099,'96','QALOCKED','차카타','?','LKS 05',true) returning id into e;
 if not exists(select 1 from public.admin_list_auto_unmatched_recipients() where shipment_id=a) then raise exception 'unknown absent from review'; end if;
 if not exists(select 1 from public.admin_list_incomplete_shipments() where shipment_id=b) then raise exception 'incomplete absent from review'; end if;
 if (select count(*) from public.list_unknown_recipient_cargo() where id in(a,b,c,d,e))<>3 then raise exception 'eligibility regression'; end if;
 if not exists(select 1 from public.list_unknown_recipient_cargo() where id=c and consignee_name='라마바' and consignee_phone='01012345678') then raise exception 'admin details masked'; end if;
 select id into q from public.unmatched_recipient_review_queue where shipment_id=a;
 perform public.admin_keep_auto_unmatched_recipient(q);
 update public.shipments set quantity=2 where id=a;
 if exists(select 1 from public.admin_list_auto_unmatched_recipients() where shipment_id=a) then raise exception 'unchanged kept cargo reopened'; end if;
 if not exists(select 1 from public.list_unknown_recipient_cargo() where id=a and created_at<'2021-01-01') then raise exception 'old kept cargo disappeared'; end if;
 update public.shipments set consignee_name='수취인 불명 / ?' where id=a;
 if not exists(select 1 from public.admin_list_auto_unmatched_recipients() where shipment_id=a) then raise exception 'changed identity not requeued'; end if;
 if not exists(select 1 from public.shipments where id=a and receipt_number='LKS XX') then raise exception 'queue changed receipt'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',member_id,'role','authenticated')::text,true);
 if not exists(select 1 from public.list_unknown_recipient_cargo() where id=c and consignee_name='라*바' and consignee_phone='0101234****') then raise exception 'member masking failed'; end if;
 claim_id:=public.create_unknown_recipient_claim(a,'회원확인','01055556666','rollback fixture');
 perform public.create_unknown_recipient_claim(b,'회원확인','01055556666','incomplete fixture');
 if not exists(select 1 from public.list_unknown_recipient_cargo() where id=a and claim_pending) then raise exception 'claim pending missing'; end if;
 blocked:=false;
 begin perform public.create_unknown_recipient_claim(a,'회원확인','01055556666','duplicate'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'duplicate accepted'; end if;
 blocked:=false;
 begin perform public.create_unknown_recipient_claim(d,'회원확인','01055556666','known'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'known cargo claim accepted'; end if;
 perform set_config('request.jwt.claims','{}',true);
 blocked:=false;
 begin perform public.list_unknown_recipient_cargo(); exception when others then blocked:=true; end;
 if not blocked then raise exception 'anonymous list allowed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 perform public.admin_review_unknown_recipient_claim(claim_id,'approve');
 if exists(select 1 from public.list_unknown_recipient_cargo() where id=a) or exists(select 1 from public.admin_list_auto_unmatched_recipients() where shipment_id=a) then raise exception 'resolved cargo still listed'; end if;
 update public.shipments set deletion_requested_at=now() where id=b;
 if exists(select 1 from public.list_unknown_recipient_cargo() where id=b) then raise exception 'trashed cargo listed'; end if;
 update public.shipments set deletion_requested_at=null where id=b;
 if not exists(select 1 from public.list_unknown_recipient_cargo() where id=b) then raise exception 'restored cargo absent'; end if;
 -- A recovered recipient must retain the existing false flag and receipt.
 update public.shipments set consignee_name='수취인 불명 / 사아자' where id=d;
 update public.shipments set recipient_unknown=false where id=d;
 if exists(select 1 from public.list_unknown_recipient_cargo() where id=d) or exists(select 1 from public.admin_list_auto_unmatched_recipients() where shipment_id=d) then raise exception 'recovered cargo reclassified'; end if;
 if not exists(select 1 from public.shipments where id=d and receipt_number='LKS 04') then raise exception 'recovered receipt changed'; end if;
end $$;
rollback;
