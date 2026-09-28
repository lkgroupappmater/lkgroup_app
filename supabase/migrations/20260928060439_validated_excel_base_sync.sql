-- Validated BASE refresh queue. Issued voyage files and shipment numbers are
-- deliberately outside this worker's write surface.
create sequence if not exists public.excel_base_revision_seq;
revoke all on sequence public.excel_base_revision_seq from public,anon,authenticated;
create table public.excel_base_sync_state (
 route_key text primary key references public.shipment_excel_base_templates(route_key) on delete cascade,
 revision bigint not null default nextval('public.excel_base_revision_seq'),
 completed_revision bigint not null default 0,
 exporter_revision text not null default '',
 status text not null default 'pending' check(status in ('pending','running','ready','error')),
 requested_at timestamptz not null default now(),
 completed_at timestamptz,
 lease_token uuid,
 lease_until timestamptz,
 retry_after timestamptz,
 attempts integer not null default 0,
 last_error text,
 integrity jsonb
);
alter table public.excel_base_sync_state enable row level security;
revoke all on public.excel_base_sync_state from public,anon,authenticated;
grant all on public.excel_base_sync_state to service_role;
grant usage on sequence public.excel_base_revision_seq to service_role;
grant select on public.excel_base_sync_state to authenticated;
create policy excel_base_sync_admin_read on public.excel_base_sync_state for select to authenticated using (
 exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.deleted_at is null)
);

create function public.lk_queue_excel_base_sync() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.excel_base_sync_state(route_key)
 select b.route_key from public.shipment_excel_base_templates b where b.active
 on conflict(route_key) do update set revision=nextval('public.excel_base_revision_seq'),
 status=case when public.excel_base_sync_state.lease_until>now() then 'running' else 'pending' end,
 requested_at=now(),retry_after=null,last_error=null;
 return null;
end $$;
revoke all on function public.lk_queue_excel_base_sync() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['customer_registry','customer_registry_aliases','customer_rate_overrides','customer_statement_share_rules','local_delivery_profiles','excel_delivery_match_reviews','exchange_rate_settings','freight_rate_tiers','route_definitions'] loop
  execute format('create trigger excel_base_sync_changed after insert or update or delete on public.%I for each statement execute function public.lk_queue_excel_base_sync()',t);
 end loop;
end $$;
create function public.lk_queue_uploaded_excel_base() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.active and (tg_op='INSERT' or new.storage_path is distinct from old.storage_path or new.active is distinct from old.active) then
  -- Only the private commit RPC marks a generated file with this revision.
  if coalesce(new.policy_summary->>'validated_source_revision','') = coalesce((select revision::text from public.excel_base_sync_state where route_key=new.route_key),'missing') then return new; end if;
  insert into public.excel_base_sync_state(route_key) values(new.route_key)
  on conflict(route_key) do update set revision=nextval('public.excel_base_revision_seq'),status='pending',requested_at=now(),retry_after=null,last_error=null;
 end if;
 return new;
end $$;
revoke all on function public.lk_queue_uploaded_excel_base() from public,anon,authenticated;
create trigger excel_base_uploaded after insert or update on public.shipment_excel_base_templates for each row execute function public.lk_queue_uploaded_excel_base();

create function public.lk_excel_discount_context(p_route_key text) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.customer_rate_overrides r where r.route_key in (p_route_key,'all');
$$;
revoke all on function public.lk_excel_discount_context(text) from public,anon,authenticated;
grant execute on function public.lk_excel_discount_context(text) to service_role;

create function public.lk_commit_validated_excel_base(
 p_route_key text,p_revision bigint,p_exporter_revision text,p_old_path text,p_old_updated_at timestamptz,
 p_path text,p_file_name text,p_version text,p_integrity jsonb,p_actor uuid default null
) returns boolean language plpgsql security definer set search_path='' as $$
declare q public.excel_base_sync_state; b public.shipment_excel_base_templates; begin
 select * into q from public.excel_base_sync_state where route_key=p_route_key for update;
 if not found or q.revision<>p_revision then raise exception 'BASE_INPUT_CHANGED_RETRY'; end if;
 if p_integrity->>'shared_formula_errors' is distinct from '0' or coalesce((p_integrity->>'sheet_count')::int,0)<1 then raise exception 'BASE_VALIDATION_REQUIRED'; end if;
 select * into b from public.shipment_excel_base_templates where route_key=p_route_key and active for update;
 if not found or b.storage_path<>p_old_path or b.updated_at<>p_old_updated_at then raise exception 'BASE_UPLOAD_CHANGED_RETRY'; end if;
 if p_path not like 'base/'||p_route_key||'/%' then raise exception 'INVALID_BASE_PATH'; end if;
 update public.shipment_excel_base_templates set storage_path=p_path,file_name=p_file_name,source_sha256=null,
 policy_summary=coalesce(b.policy_summary,'{}'::jsonb)||jsonb_build_object(
  'automation_version',p_version,'exporter_revision',p_exporter_revision,'validated_source_revision',p_revision,
  'validated_at',now(),'integrity',p_integrity,'previous_storage_path',b.storage_path,
  'source_history',(select coalesce(jsonb_agg(v),'[]'::jsonb) from (select value v from jsonb_array_elements(jsonb_build_array(b.storage_path)||coalesce(b.policy_summary->'source_history','[]'::jsonb)) limit 20) h)),
 updated_by=coalesce(p_actor,b.updated_by),updated_at=now() where route_key=p_route_key;
 update public.excel_base_sync_state set completed_revision=p_revision,exporter_revision=p_exporter_revision,status='ready',completed_at=now(),last_error=null,integrity=p_integrity,lease_token=null,lease_until=null,retry_after=null,attempts=0 where route_key=p_route_key;
 return true;
end $$;
revoke all on function public.lk_commit_validated_excel_base(text,bigint,text,text,timestamptz,text,text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.lk_commit_validated_excel_base(text,bigint,text,text,timestamptz,text,text,text,jsonb,uuid) to service_role;

-- This secret stays in Vault. It is neither a user password nor an exposed
-- service key, and the public worker cannot run without validating it.
do $$ begin
 if not exists(select 1 from vault.secrets where name='lk_excel_base_worker_token') then
  perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'lk_excel_base_worker_token');
 end if;
end $$;
create function public.lk_validate_excel_worker(p_token text) returns boolean language sql stable security definer set search_path='' as $$
 select length(coalesce(p_token,''))=64 and exists(select 1 from vault.decrypted_secrets where name='lk_excel_base_worker_token' and extensions.digest(decrypted_secret,'sha256')=extensions.digest(p_token,'sha256'));
$$;
revoke all on function public.lk_validate_excel_worker(text) from public,anon,authenticated;
grant execute on function public.lk_validate_excel_worker(text) to service_role;
create function public.lk_claim_excel_base_sync(p_exporter_revision text) returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.excel_base_sync_state; begin
 if coalesce(p_exporter_revision,'')='' then raise exception 'MISSING_EXPORTER_REVISION'; end if;
 insert into public.excel_base_sync_state(route_key) select route_key from public.shipment_excel_base_templates where active on conflict do nothing;
 select s.* into q from public.excel_base_sync_state s join public.shipment_excel_base_templates b using(route_key)
 where b.active and (s.revision<>s.completed_revision or s.exporter_revision<>p_exporter_revision)
 and (s.lease_until is null or s.lease_until<now()) and (s.retry_after is null or s.retry_after<=now())
 order by s.requested_at,s.route_key for update of s skip locked limit 1;
 if not found then return null; end if;
 update public.excel_base_sync_state set status='running',lease_token=gen_random_uuid(),lease_until=now()+interval '10 minutes',attempts=attempts+1 where route_key=q.route_key returning * into q;
 return jsonb_build_object('route_key',q.route_key,'revision',q.revision,'lease_token',q.lease_token);
end $$;
revoke all on function public.lk_claim_excel_base_sync(text) from public,anon,authenticated;
grant execute on function public.lk_claim_excel_base_sync(text) to service_role;
create function public.lk_fail_excel_base_sync(p_route_key text,p_lease_token uuid,p_error text) returns void language sql security definer set search_path='' as $$
 update public.excel_base_sync_state set status='error',last_error=left(p_error,1000),lease_until=null,lease_token=null,retry_after=now()+interval '5 minutes' where route_key=p_route_key and lease_token=p_lease_token;
$$;
revoke all on function public.lk_fail_excel_base_sync(text,uuid,text) from public,anon,authenticated;
grant execute on function public.lk_fail_excel_base_sync(text,uuid,text) to service_role;

insert into public.excel_base_sync_state(route_key) select route_key from public.shipment_excel_base_templates where active;
-- Installed disabled; enable only after the authenticated worker is deployed.
select cron.schedule('lkgroup-validated-excel-base-sync','* * * * *',
 $cron$select net.http_post(
  url:='https://rkqwzxfcnciptnwesfbr.supabase.co/functions/v1/sync-excel-bases',
  headers:=jsonb_build_object('Content-Type','application/json','x-excel-worker-token',(select decrypted_secret from vault.decrypted_secrets where name='lk_excel_base_worker_token')),
  body:='{}'::jsonb,timeout_milliseconds:=1000
 );$cron$);
select cron.alter_job((select jobid from cron.job where jobname='lkgroup-validated-excel-base-sync'),active:=false);
