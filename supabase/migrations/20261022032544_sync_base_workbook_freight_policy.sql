-- BASE uploads synchronize common freight settings. Voyage files never enter this queue.
alter table public.excel_quote_sources add column freight_version text;
alter table public.excel_quote_sources add column freight_policy jsonb;
alter table public.excel_quote_sources add column source_sha256 text;

create or replace function public.lk_queue_excel_quote_source() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name <> 'shipment_excel_base_templates' then return new; end if;
 if not new.active or new.policy_summary ? 'validated_source_revision' then return new; end if;
 insert into public.excel_quote_sources(route_key,storage_path,source_at)
 values(new.route_key,new.storage_path,clock_timestamp())
 on conflict(route_key) do update set storage_path=excluded.storage_path,source_at=excluded.source_at,
 synced_at=null,last_error=null,attempted_at=null,freight_version=null,source_sha256=null;
 return new;
end $$;
revoke all on function public.lk_queue_excel_quote_source() from public,anon,authenticated;

create function public.lk_commit_excel_base_freight(
 p_route_key text,p_path text,p_source_at timestamptz,p_policy jsonb,p_footer_lines jsonb,p_sha256 text
) returns boolean language plpgsql security definer set search_path='' as $$
declare q public.excel_quote_sources; r public.route_definitions; t jsonb;
 minimum numeric; factor numeric; previous_weight numeric:=-1; previous_policy jsonb;
begin
 -- Only the authenticated server importer can submit values extracted from the registered file.
 select * into q from public.excel_quote_sources where route_key=p_route_key for update;
 if not found or q.storage_path is distinct from p_path or q.source_at is distinct from p_source_at then return false; end if;
 select * into r from public.route_definitions where route_key=p_route_key and deleted_at is null and status='active';
 if not found or not exists(select 1 from public.shipment_excel_base_templates where route_key=p_route_key and active) then raise exception 'ACTIVE_BASE_REQUIRED'; end if;
 if q.freight_version='base-freight-v1' and q.synced_at is not null and q.source_sha256=p_sha256 then return true; end if;
 if p_policy->>'version' is distinct from 'base-freight-v1' or coalesce(jsonb_typeof(p_policy->'tiers'),'')<>'array'
 or jsonb_array_length(p_policy->'tiers') not between 1 and 100
 or p_sha256 !~ '^[a-f0-9]{64}$' or p_sha256 is null then raise exception 'INVALID_BASE_FREIGHT'; end if;
 minimum:=(p_policy->>'minimum_charge')::numeric;
 factor:=coalesce((p_policy->>'volumetric_factor')::numeric,r.volumetric_factor);
 if minimum is null or minimum<=0 or minimum>=1000000 or factor is null or factor<=0 or factor>=1 then raise exception 'INVALID_BASE_FREIGHT'; end if;
 for t in select value from jsonb_array_elements(p_policy->'tiers') loop
  if jsonb_typeof(t->'min_weight_kg') is distinct from 'number' or jsonb_typeof(t->'rate_per_kg') is distinct from 'number'
   or (t->>'min_weight_kg')::numeric <= previous_weight or (previous_weight=-1 and (t->>'min_weight_kg')::numeric<>0)
   or (t->>'rate_per_kg')::numeric<=0 or (t->>'rate_per_kg')::numeric>=1000000 then raise exception 'INVALID_BASE_FREIGHT_TIER'; end if;
  previous_weight:=(t->>'min_weight_kg')::numeric;
 end loop;
 if coalesce(jsonb_typeof(p_footer_lines),'')<>'array' or jsonb_array_length(p_footer_lines)>30 or length(p_footer_lines::text)>30000
 or exists(select 1 from jsonb_array_elements(p_footer_lines) e where jsonb_typeof(e)<>'string') then raise exception 'INVALID_DOCUMENT_COPY'; end if;
 select jsonb_agg(to_jsonb(f) order by f.min_weight_kg) into previous_policy from public.freight_rate_tiers f where route_key=p_route_key and active;
 insert into public.freight_rate_tiers(route_key,min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note,active,updated_at)
 select p_route_key,(e->>'min_weight_kg')::numeric,(e->>'rate_per_kg')::numeric,minimum,factor,'BASE Excel: '||coalesce(p_policy->>'source',''),true,now()
 from jsonb_array_elements(p_policy->'tiers') e
 on conflict(route_key,min_weight_kg) do update set rate_per_kg=excluded.rate_per_kg,minimum_charge=excluded.minimum_charge,
 volumetric_factor=excluded.volumetric_factor,source_note=excluded.source_note,active=true,updated_at=now()
 where (freight_rate_tiers.rate_per_kg,freight_rate_tiers.minimum_charge,freight_rate_tiers.volumetric_factor,freight_rate_tiers.active)
 is distinct from (excluded.rate_per_kg,excluded.minimum_charge,excluded.volumetric_factor,true);
 update public.freight_rate_tiers f set active=false,updated_at=now() where f.route_key=p_route_key and f.active
 and not exists(select 1 from jsonb_array_elements(p_policy->'tiers') e where (e->>'min_weight_kg')::numeric=f.min_weight_kg);
 update public.route_definitions set minimum_charge=minimum,volumetric_factor=factor,updated_at=now()
 where route_key=p_route_key and (minimum_charge,volumetric_factor) is distinct from (minimum,factor);
 update public.excel_quote_sources set freight_policy=p_policy||jsonb_build_object('previous_tiers',previous_policy),
 freight_version='base-freight-v1',source_sha256=p_sha256,footer_lines=p_footer_lines,synced_at=now(),attempted_at=now(),last_error=null where route_key=p_route_key;
 return true;
end $$;
revoke all on function public.lk_commit_excel_base_freight(text,text,timestamptz,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.lk_commit_excel_base_freight(text,text,timestamptz,jsonb,jsonb,text) to service_role;
