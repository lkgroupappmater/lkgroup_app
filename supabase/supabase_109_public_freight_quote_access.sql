begin;

-- Public freight checks need only the active calculation inputs. Keep the
-- underlying management tables private and expose a narrow, read-only RPC.
create or replace function public.list_public_freight_rate_tiers(
  p_route_key text
)
returns table (
  min_weight_kg numeric,
  rate_per_kg numeric,
  minimum_charge numeric,
  volumetric_factor numeric,
  source_note text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select
    f.min_weight_kg,
    f.rate_per_kg,
    f.minimum_charge,
    f.volumetric_factor,
    ''::text as source_note
  from public.freight_rate_tiers f
  where f.route_key = p_route_key
    and f.active is true
  order by f.min_weight_kg, f.id;
$function$;

create or replace function public.get_public_exchange_rate_settings()
returns table (
  base_kip numeric,
  base_thb numeric,
  base_krw numeric,
  kip_adjustment numeric,
  thb_adjustment numeric,
  krw_adjustment numeric
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select
    e.base_kip,
    e.base_thb,
    e.base_krw,
    e.kip_adjustment,
    e.thb_adjustment,
    e.krw_adjustment
  from public.exchange_rate_settings e
  where e.id = 1
  limit 1;
$function$;

revoke all on function public.list_public_freight_rate_tiers(text) from public;
revoke all on function public.get_public_exchange_rate_settings() from public;

grant execute on function public.list_public_freight_rate_tiers(text)
  to anon, authenticated, service_role;
grant execute on function public.get_public_exchange_rate_settings()
  to anon, authenticated, service_role;

comment on function public.list_public_freight_rate_tiers(text) is
  'Read-only active freight calculation inputs for public app and web checks.';
comment on function public.get_public_exchange_rate_settings() is
  'Read-only public exchange-rate values used by app and web freight checks.';

commit;
