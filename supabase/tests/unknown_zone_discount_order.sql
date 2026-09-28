begin;
-- Every fixture is rolled back. Only sequence gaps may remain, as with any
-- rolled-back insert; no customer or shipment test data persists.
do $verify$
declare a bigint; b bigint; aid bigint; payload jsonb; row_data public.shipments; bill text; rule jsonb;
begin
 begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true)
   from public.profiles where role='admin' and approval_status='approved' and coalesce(deletion_status,'active')='active' limit 1;
  execute 'set local role authenticated';
  insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,quantity)
   values('한국->라오스 해상',2099,'96','LKQA920001','수취인 불명 / 유연경QA','02099998201',1) returning id,recipient_recovered_order,receipt_number into aid,a,bill;
  if a is null then raise exception 'Confirmation order missing'; end if;
  select * into row_data from public.shipments where id=aid;
  if row_data.unloading_zone<>'F' then raise exception 'Recovered Zone is not F'; end if;
  if public.lk_excel_import_changes('{"unloading_zone":"A"}',row_data)?'unloading_zone' then raise exception 'Stale Excel cached zone creates false change'; end if;
  insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,quantity)
   values('한국->라오스 해상',2099,'96','LKQA920002','수취인 불명 / 박진경QA','02099998202',1) returning recipient_recovered_order into b;
  if b<=a then raise exception 'Alphabetic second recipient overtook first'; end if;
  update public.shipments set quantity=12,unloading_zone='B' where id=aid;
  perform public.admin_finalize_excel_batch_rules_fast('한국->라오스 해상',2099,'96',true);
  if not exists(select 1 from public.shipments where id=aid and unloading_zone='F' and recipient_recovered_order=a and receipt_number=bill) then raise exception 'Recalculation changed F, order, or bill'; end if;
  insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,quantity,unloading_zone)
   values('한국->라오스 항공',2099,'96','AQ920003','수취인 불명 / 항공QA','02099998203',1,'102');
  if exists(select 1 from public.shipments where shipment_year=2099 and voyage='96' and public.lk_unknown_prefix_zone(consignee_name) and unloading_zone<>'F') then raise exception 'Air forced zone failed'; end if;
  rule:='{"customer_name":"DiscountSyncQA9200","phone":"02099998209","discount_percent":0.25,"special_discount_percent":0.05,"group_name":"기업 할인","active":true}';
  perform public.web_import_excel_rules('kr_la_sea',p_discounts=>jsonb_build_array(rule));
  perform public.web_import_excel_rules('kr_la_sea',p_discounts=>jsonb_build_array(rule||'{"discount_percent":0.3,"special_discount_percent":0,"regular_discount_present":true,"special_discount_present":false}'));
  if not exists(select 1 from public.customer_rate_overrides where customer_name='DiscountSyncQA9200' and discount_percent=.35 and special_discount_percent=.05) then raise exception 'Absent special discount was lost'; end if;
  perform public.web_import_excel_rules('kr_la_sea',p_discounts=>jsonb_build_array(rule||'{"discount_percent":0.1,"special_discount_percent":0.1,"regular_discount_present":false,"special_discount_present":true,"group_name":"특별할인"}'));
  if not exists(select 1 from public.customer_rate_overrides where customer_name='DiscountSyncQA9200' and discount_percent=.4 and special_discount_percent=.1 and group_name='기업 할인') then raise exception 'Special-only adjustment lost regular discount'; end if;
  perform public.web_import_excel_rules('kr_la_sea',p_discounts=>jsonb_build_array(rule||'{"discount_percent":0,"special_discount_percent":0,"regular_discount_present":false,"special_discount_present":true}'));
  if not exists(select 1 from public.customer_rate_overrides where customer_name='DiscountSyncQA9200' and discount_percent=.3 and special_discount_percent=0) then raise exception 'Explicit zero did not clear special'; end if;
  raise exception using errcode='Z0001',message='PASS: zone, confirmation order, stable bills, adjusted discounts';
 exception when sqlstate 'Z0001' then raise notice '%',sqlerrm;
 end;
end $verify$;

rollback;
