-- Applies on future source edits only. Existing source links are not backfilled.
create or replace function lk_private.register_shipment_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid; n text:=public.lk_customer_base_name(new.consignee_name); unknown_name boolean:=coalesce(new.consignee_name,'') ~ '수취인[[:space:]]*불명';
begin
 if new.deleted_at is not null or n is null or (coalesce(new.recipient_unknown,false) and not unknown_name) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 -- Preserve normal customer links. Only a user edit that removes the unknown
 -- prefix may replace a legacy unknown-only link with the actual customer.
 if exists(select 1 from public.customer_registry_sources where source_kind='shipment' and source_id=new.id::text)
 and (unknown_name or exists(
  select 1 from public.customer_registry_sources s join public.customer_registry r on r.id=s.customer_registry_id
  where s.source_kind='shipment' and s.source_id=new.id::text and r.name !~ '수취인[[:space:]]*불명'
 )) then return new; end if;
 target:=public.customer_registry_match(new.consignee_name,new.consignee_phone,unknown_name);
 if target is null then
  if unknown_name then return new; end if;
  insert into public.customer_registry(name,phone) values(n,coalesce(new.consignee_phone,'')) returning id into target;
 end if;
 if not unknown_name then
  insert into public.customer_registry_aliases values(public.lk_registry_name(n),public.lk_registry_phone(new.consignee_phone),target,now()) on conflict do nothing;
 end if;
 insert into public.customer_registry_sources values('shipment',new.id::text,target)
 on conflict(source_kind,source_id) do update set customer_registry_id=excluded.customer_registry_id;
 return new;
end $$;
