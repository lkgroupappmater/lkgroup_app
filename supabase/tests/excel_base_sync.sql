begin;
do $$
declare before_revision bigint; current_revision bigint; b public.shipment_excel_base_templates; count_before bigint; begin
 select * into b from public.shipment_excel_base_templates where route_key='kr_la_sea';
 select revision into before_revision from public.excel_base_sync_state where route_key=b.route_key;
 select count(*) into count_before from public.shipments;
 update public.customer_registry set name=name where id=(select id from public.customer_registry order by customer_no limit 1);
 select revision into current_revision from public.excel_base_sync_state where route_key=b.route_key;
 if current_revision<=before_revision then raise exception 'Input change did not queue BASE refresh'; end if;
 begin
  perform public.lk_commit_validated_excel_base(b.route_key,before_revision,'test',b.storage_path,b.updated_at,'base/kr_la_sea/test.xlsx','test.xlsx','test','{"sheet_count":1,"shared_formula_errors":0}');
  raise exception 'Stale revision was accepted';
 exception when others then if sqlerrm<>'BASE_INPUT_CHANGED_RETRY' then raise; end if; end;
 begin
  perform public.lk_commit_validated_excel_base(b.route_key,current_revision,'test',b.storage_path,b.updated_at,'base/kr_la_sea/test.xlsx','test.xlsx','test','{"sheet_count":1,"shared_formula_errors":1}');
  raise exception 'Invalid workbook was accepted';
 exception when others then if sqlerrm<>'BASE_VALIDATION_REQUIRED' then raise; end if; end;
 perform public.lk_commit_validated_excel_base(b.route_key,current_revision,'test',b.storage_path,b.updated_at,'base/kr_la_sea/test.xlsx','test.xlsx','test','{"sheet_count":1,"shared_formula_errors":0}');
 if not exists(select 1 from public.excel_base_sync_state where route_key=b.route_key and revision=current_revision and completed_revision=current_revision and status='ready') then raise exception 'Commit requeued itself'; end if;
 if (select count(*) from public.shipments)<>count_before then raise exception 'Cargo changed'; end if;
 if public.lk_validate_excel_worker(repeat('x',64)) then raise exception 'Invalid worker token accepted'; end if;
 if has_function_privilege('authenticated','public.lk_commit_validated_excel_base(text,bigint,text,text,timestamptz,text,text,text,jsonb,uuid)','execute') then raise exception 'Member can publish BASE'; end if;
 if has_function_privilege('anon','public.lk_claim_excel_base_sync(text)','execute') then raise exception 'Anonymous can claim BASE'; end if;
end $$;
rollback;
