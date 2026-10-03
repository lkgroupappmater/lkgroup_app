create or replace function public.lk_claim_statement_macro_upgrade()
returns jsonb language plpgsql security definer set search_path=public as $$
declare job public.excel_statement_macro_updates%rowtype;
begin
 insert into public.excel_statement_macro_updates(resource_key,source_path,kind,route_key,shipment_year,voyage,file_name)
 select 'base:'||b.route_key,b.storage_path,'base',b.route_key,null,null,b.file_name from public.shipment_excel_base_templates b where b.active and (b.file_name ilike '%.xlsm' or b.file_name ilike '%.xlsx')
 union all select 'voyage:'||t.route_key||':'||t.shipment_year||':'||t.voyage,t.storage_path,'voyage',t.route_key,t.shipment_year,t.voyage,t.file_name from public.shipment_excel_templates t where t.file_name ilike '%.xlsm'
 on conflict(resource_key) do update set source_path=excluded.source_path,target_path=null,file_name=excluded.file_name,status='pending',attempts=0,error=null,updated_at=now()
 where excel_statement_macro_updates.status<>'running' and excluded.source_path is distinct from coalesce(excel_statement_macro_updates.target_path,excel_statement_macro_updates.source_path);
 select * into job from public.excel_statement_macro_updates where status='pending' or (status='running' and updated_at<now()-interval '5 minutes') or (status='failed' and attempts<3 and updated_at<now()-interval '2 minutes') order by resource_key for update skip locked limit 1;
 if not found then return null;end if;
 update public.excel_statement_macro_updates set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),updated_at=now() where resource_key=job.resource_key returning * into job;
 return to_jsonb(job);
end $$;
