create table public.excel_statement_macro_updates(
 resource_key text primary key,source_path text not null,target_path text,kind text not null,route_key text not null,shipment_year integer,voyage text,file_name text not null,
 version text not null default 'current-voyage-statements-v1',status text not null default 'pending',attempts integer not null default 0,lease_token uuid,
 details jsonb not null default '{}',error text,updated_at timestamptz not null default now()
);
alter table public.excel_statement_macro_updates enable row level security;
create policy macro_upgrade_admin_read on public.excel_statement_macro_updates for select to authenticated using(public.current_role() in ('admin','staff'));
grant select on public.excel_statement_macro_updates to authenticated;
create or replace function public.lk_claim_statement_macro_upgrade()
returns jsonb language plpgsql security definer set search_path=public as $$
declare job public.excel_statement_macro_updates%rowtype;
begin
 insert into public.excel_statement_macro_updates(resource_key,source_path,kind,route_key,shipment_year,voyage,file_name)
 select 'base:'||b.route_key,b.storage_path,'base',b.route_key,null,null,b.file_name from public.shipment_excel_base_templates b where b.active and b.file_name ilike '%.xlsm'
 union all select 'voyage:'||t.route_key||':'||t.shipment_year||':'||t.voyage,t.storage_path,'voyage',t.route_key,t.shipment_year,t.voyage,t.file_name from public.shipment_excel_templates t where t.file_name ilike '%.xlsm'
 on conflict(resource_key) do update set source_path=excluded.source_path,target_path=null,file_name=excluded.file_name,status='pending',attempts=0,error=null,updated_at=now()
 where excel_statement_macro_updates.status<>'running' and excluded.source_path is distinct from coalesce(excel_statement_macro_updates.target_path,excel_statement_macro_updates.source_path);
 select * into job from public.excel_statement_macro_updates where status='pending' or (status='running' and updated_at<now()-interval '5 minutes') or (status='failed' and attempts<3 and updated_at<now()-interval '2 minutes') order by resource_key for update skip locked limit 1;
 if not found then return null;end if;
 update public.excel_statement_macro_updates set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),updated_at=now() where resource_key=job.resource_key returning * into job;
 return to_jsonb(job);
end $$;
create or replace function public.lk_finish_statement_macro_upgrade(p_resource_key text,p_lease_token uuid,p_target_path text,p_details jsonb,p_error text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare job public.excel_statement_macro_updates%rowtype; changed integer;
begin
 select * into job from public.excel_statement_macro_updates where resource_key=p_resource_key and lease_token=p_lease_token and status='running' for update;
 if not found then return false;end if;
 if p_error is not null then update public.excel_statement_macro_updates set status='failed',error=left(p_error,2000),updated_at=now() where resource_key=job.resource_key;return true;end if;
 if p_target_path is not null and p_target_path<>job.source_path then
  if job.kind='base' then
   update public.shipment_excel_base_templates set storage_path=p_target_path,updated_at=now(),policy_summary=coalesce(policy_summary,'{}')||jsonb_build_object('statement_macro',p_details)
    where route_key=job.route_key and storage_path=job.source_path;
  else
   update public.shipment_excel_templates set storage_path=p_target_path where route_key=job.route_key and shipment_year=job.shipment_year and voyage=job.voyage and storage_path=job.source_path;
  end if;
  get diagnostics changed=row_count;
  if changed<>1 then update public.excel_statement_macro_updates set status='stale',error='A newer file was uploaded; preserved the newer file',updated_at=now() where resource_key=job.resource_key;return false;end if;
 end if;
 update public.excel_statement_macro_updates set status=case when coalesce((p_details->>'present')::boolean,false) then 'ready' else 'not_applicable' end,target_path=coalesce(p_target_path,job.source_path),details=p_details,error=null,updated_at=now() where resource_key=job.resource_key;
 return true;
end $$;
revoke all on function public.lk_claim_statement_macro_upgrade(),public.lk_finish_statement_macro_upgrade(text,uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lk_claim_statement_macro_upgrade(),public.lk_finish_statement_macro_upgrade(text,uuid,text,jsonb,text) to service_role;
