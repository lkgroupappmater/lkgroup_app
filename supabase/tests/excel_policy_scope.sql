-- Run inside a transaction; synthetic policy rows and BASE edits are rolled back.
begin;
do $$
declare admin_id uuid; baseline jsonb; before_hash text; after_hash text; before_queue jsonb;
 rules jsonb; changed jsonb; effective jsonb; result jsonb; route text:='kr_la_sea'; d jsonb;
begin
 select id into admin_id from public.profiles where role='admin' and approval_status='approved' and deleted_at is null and coalesce(deletion_status,'active')='active' limit 1;
 if admin_id is null then raise exception 'Test requires an existing active administrator'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
 baseline:=public.lk_excel_base_policy(route);
 select md5(jsonb_build_array((select jsonb_agg(x order by route_key) from (select route_key,public.lk_excel_base_policy(route_key) policy from public.route_definitions)x))::text) into before_hash;
 select jsonb_agg(to_jsonb(s) order by route_key) into before_queue from public.excel_base_sync_state s;

 -- An additional ordinary + special discount, temporary Remark, new delivery,
 -- fixed zone and custom color must all be visible only in this exact voyage.
 rules:=jsonb_build_object(
 'discounts',jsonb_build_array(jsonb_build_object('customer_name','SCOPE QA 2098','phone','02000009998','discount_percent',0.25,'special_discount_percent',0.05,'group_name','기업 할인','active',true,'regular_discount_present',true,'special_discount_present',true)),
 'shares',jsonb_build_array(jsonb_build_object('source_no',999,'customer_name','SCOPE QA 2098','phone','02000009998','phone_display','02000009998','content','이번 항차만 추가 확인','active',true)),
 'deliveries',jsonb_build_array(jsonb_build_object('source_no',9999,'customer_name','SCOPE QA 2098','phone','02000009998','phone_display','02000009998','delivery_type','province','local_company','QA','destination_address','Voyage only','paid_by','선결제','active',true)),
 'zones',jsonb_build_array(jsonb_build_object('customer_name','SCOPE QA 2098','zone','F','active',true)),
 'appearance',jsonb_build_object('province_prepaid','ABCDEF'));
 result:=public.import_excel_workbook_policy(route,2098,'98','KR_LA_SEA_2098_V98.xlsx',rules);
 assert result->>'scope'='voyage','Voyage must have voyage scope';
 effective:=public.get_excel_workbook_policy(route,2098,'98');
 assert effective->'appearance'->>'province_prepaid'='ABCDEF','Scoped color missing';
 assert (public.resolve_customer_discount_context(route,2098,'98','SCOPE QA 2098','02000009998')->>'discount_percent')::numeric=0.25,'Scoped discount missing';
 assert public.compute_shipment_special_note_scoped(route,2098,'98','SCOPE QA 2098','02000009998') like '%이번 항차만 추가 확인%','Scoped Remark missing';
 assert public.compute_shipment_special_note_scoped(route,2098,'98','SCOPE QA 2098','02000009998') like '%지방배송(선결제)%','Scoped delivery missing';
 d:=public.get_excel_delivery_profile(route,2098,'98','SCOPE QA 2098','02000009998');
 assert d->>'destination_address'='Voyage only' and d->>'display_color'='ABCDEF','App/web profile must use voyage settings';
 assert public.lk_excel_effective_policy(route,2098,'97')=baseline,'Other voyage changed';
 assert public.lk_excel_effective_policy(route,2097,'98')=baseline,'Other year changed';
 assert coalesce(public.resolve_customer_discount_context('kr_la_air',2098,'98','SCOPE QA 2098','02000009998')->>'discount_percent','0')='0','Other route changed';
 select md5(jsonb_build_array((select jsonb_agg(x order by route_key) from (select route_key,public.lk_excel_base_policy(route_key) policy from public.route_definitions)x))::text) into after_hash;
 assert before_hash=after_hash,'Voyage upload modified shared defaults';
 assert before_queue=(select jsonb_agg(to_jsonb(s) order by route_key) from public.excel_base_sync_state s),'Voyage settings queued BASE regeneration';

 -- Independent ordinary/special deltas inherit later BASE changes correctly.
 -- Use an isolated test customer and a second voyage; all writes roll back.
 perform public.import_excel_workbook_policy(route,2098,'00','KR_LA_SEA_2098_XX_BASE.xlsx',jsonb_build_object('discounts',coalesce(baseline->'discounts','[]')||jsonb_build_array(jsonb_build_object('customer_name','CATEGORY QA','phone','02000009997','discount_percent',0.1,'special_discount_percent',0.02,'group_name','기업 할인','active',true))));
 effective:=public.lk_excel_base_policy(route);
 changed:=jsonb_set(effective,'{discounts}',(select jsonb_agg(case when r->>'customer_name'='CATEGORY QA' then r||'{"discount_percent":0.13,"special_discount_percent":0.05}' else r end) from jsonb_array_elements(effective->'discounts') r));
 perform public.import_excel_workbook_policy(route,2098,'96','KR_LA_SEA_2098_V96.xlsx',jsonb_build_object('discounts',changed->'discounts'));
 effective:=jsonb_set(effective,'{discounts}',(select jsonb_agg(case when r->>'customer_name'='CATEGORY QA' then r||'{"discount_percent":0.30,"special_discount_percent":0.02}' else r end) from jsonb_array_elements(effective->'discounts') r));
 perform public.import_excel_workbook_policy(route,2098,'00','KR_LA_SEA_2098_XX_BASE.xlsx',jsonb_build_object('discounts',effective->'discounts'));
 assert (public.resolve_customer_discount_context(route,2098,'96','CATEGORY QA','02000009997')->>'discount_percent')::numeric=0.33,'Independent discount category inheritance failed';

 -- A zero discount is a deliberate override, not a missing value.
 rules:=jsonb_set(rules,'{discounts,0,discount_percent}','0');rules:=jsonb_set(rules,'{discounts,0,special_discount_percent}','0');
 perform public.import_excel_workbook_policy(route,2098,'98','KR_LA_SEA_2098_V98.xlsx',rules);
 assert (public.resolve_customer_discount_context(route,2098,'98','SCOPE QA 2098','02000009998')->>'discount_percent')::numeric=0,'Explicit zero lost';

 -- Only BASE is allowed to change the defaults. Local color overrides survive.
 perform public.import_excel_workbook_policy(route,2098,'00','KR_LA_SEA_2098_XX_BASE.xlsx','{"appearance":{"province":"112233","province_prepaid":"445566"}}');
 assert public.lk_excel_effective_policy(route,2098,'97')->'appearance'->>'province'='112233','BASE default did not propagate';
 assert public.lk_excel_effective_policy(route,2098,'98')->'appearance'->>'province'='112233','Unchanged local field did not inherit BASE';
 assert public.lk_excel_effective_policy(route,2098,'98')->'appearance'->>'province_prepaid'='ABCDEF','BASE overwrote voyage override';

 -- Reuploading values equal to BASE removes that field's override.
 perform public.import_excel_workbook_policy(route,2098,'98','KR_LA_SEA_2098_V98.xlsx','{"appearance":{"province_prepaid":"445566"},"shares":[]}');
 assert public.lk_excel_effective_policy(route,2098,'98')->'shares'='[]'::jsonb,'Explicit empty Remark list not cleared locally';
 assert (select changes->'appearance'='{}'::jsonb from public.excel_workbook_policies where route_key=route and shipment_year=2098 and voyage='98'),'Equal-to-BASE color stayed pinned';

 begin
  perform public.import_excel_workbook_policy(route,2098,'00','KR_LA_SEA_2098_V98.xlsx','{}');
  raise exception 'Expected BASE marker rejection';
 exception when others then if sqlerrm='Expected BASE marker rejection' then raise; end if; end;
 begin
  perform public.web_import_excel_rules(route,null,'[]',null);
  raise exception 'Expected old unscoped endpoint rejection';
 exception when others then if sqlerrm='Expected old unscoped endpoint rejection' then raise; end if; end;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin
  perform public.import_excel_workbook_policy(route,2098,'98','KR_LA_SEA_2098_V98.xlsx','{}');
  raise exception 'Expected authorization rejection';
 exception when others then if sqlerrm='Expected authorization rejection' then raise; end if; end;
end $$;
rollback;
