-- Keep an immutable uploaded workbook reference; regenerated files never become
-- the common layout source. Existing table permissions and RPC grants stay intact.
create or replace function lk_private.share_uploaded_delivery_layout() returns trigger
language plpgsql security definer set search_path='' as $$
declare target text; descriptor jsonb;
begin
 if pg_trigger_depth()>1 or new.route_key not in ('kr_la_sea','kr_la_air') or not new.active then return new; end if;
 if tg_op='UPDATE' and new.storage_path is not distinct from old.storage_path then return new; end if;
 if new.policy_summary ? 'validated_source_revision' then return new; end if;
 if new.storage_path not like 'base/'||new.route_key||'/%' and new.storage_path not like 'macro-updates/'||new.route_key||'/%' then return new; end if;
 target:=case new.route_key when 'kr_la_sea' then 'kr_la_air' else 'kr_la_sea' end;
 descriptor:=jsonb_build_object('version',1,'route_key',new.route_key,'storage_path',new.storage_path,'uploaded_at',clock_timestamp());
 new.policy_summary:=coalesce(new.policy_summary,'{}'::jsonb)||jsonb_build_object('common_delivery_layout',descriptor);
 update public.shipment_excel_base_templates set policy_summary=coalesce(policy_summary,'{}'::jsonb)||jsonb_build_object('common_delivery_layout',descriptor) where route_key=target and active;
 insert into public.excel_base_sync_state(route_key) select route_key from public.shipment_excel_base_templates where route_key=target and active
 on conflict(route_key) do update set revision=nextval('public.excel_base_revision_seq'),status='pending',requested_at=now(),retry_after=null,last_error=null;
 return new;
end $$;
revoke all on function lk_private.share_uploaded_delivery_layout() from public,anon,authenticated;
create trigger a_common_delivery_template_lock before insert or update on public.shipment_excel_base_templates
for each statement execute function lk_private.lock_common_delivery();
create trigger b_common_delivery_template before insert or update on public.shipment_excel_base_templates
for each row execute function lk_private.share_uploaded_delivery_layout();

-- Same lock order for generated commits and uploads; no changes to its API.
CREATE OR REPLACE FUNCTION public.lk_commit_validated_excel_base(p_route_key text, p_revision bigint, p_exporter_revision text, p_old_path text, p_old_updated_at timestamp with time zone, p_path text, p_file_name text, p_version text, p_integrity jsonb, p_actor uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q public.excel_base_sync_state; b public.shipment_excel_base_templates; begin
 perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
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
end $function$;


-- The user selected the latest SEA upload as the initial common form. Its
-- preserved pre-generation object is checked before either BASE is queued.
do $$
declare b public.shipment_excel_base_templates; source_path text; descriptor jsonb;
begin
 select * into b from public.shipment_excel_base_templates where route_key='kr_la_sea' and active;
 if not found then return; end if;
 if not (coalesce(b.policy_summary,'{}'::jsonb) ? 'validated_source_revision') then source_path:=b.storage_path;
 else
  select value into source_path from jsonb_array_elements_text(coalesce(b.policy_summary->'source_history','[]'::jsonb)) with ordinality h(value,n)
  where value like 'macro-updates/kr_la_sea/%' order by n limit 1;
 end if;
 if source_path is null or not exists(select 1 from storage.objects where bucket_id='shipment-excel-templates' and name=source_path) then
  raise exception 'The latest uploaded SEA delivery workbook must be verified before activating layout sync';
 end if;
 descriptor:=jsonb_build_object('version',1,'route_key','kr_la_sea','storage_path',source_path,'uploaded_at',b.updated_at);
 update public.shipment_excel_base_templates set policy_summary=coalesce(policy_summary,'{}'::jsonb)||jsonb_build_object('common_delivery_layout',descriptor) where route_key in ('kr_la_sea','kr_la_air') and active;
 update public.excel_base_sync_state set revision=nextval('public.excel_base_revision_seq'),status='pending',requested_at=now(),retry_after=null,last_error=null where route_key in ('kr_la_sea','kr_la_air');
end $$;

