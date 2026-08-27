-- Immediate repair for an existing CargoFlow Supabase project.
-- Run this once if the previous schema stopped with:
-- ERROR: 42703: column "route" does not exist
-- It is safe to run repeatedly.

do $$
begin
  if to_regclass('public.shipping_schedules') is not null then
    execute format('alter table public.shipping_schedules add column if not exists route text not null default %L', '');
  end if;

  if to_regclass('public.shipments') is not null then
    execute format('alter table public.shipments add column if not exists route text not null default %L', '');
  end if;

  if to_regclass('public.quote_requests') is not null then
    execute format('alter table public.quote_requests add column if not exists route text not null default %L', '');
  end if;
end $$;

-- Create only the indexes whose tables and columns now exist.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'shipping_schedules'
      and column_name = 'route'
  ) then
    execute 'create index if not exists schedules_route_idx on public.shipping_schedules (route)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'shipments'
      and column_name = 'route'
  ) then
    execute 'create index if not exists shipments_route_idx on public.shipments (route)';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'quote_requests'
      and column_name = 'route'
  ) then
    execute 'create index if not exists quote_requests_route_idx on public.quote_requests (route)';
  end if;
end $$;

select
  table_name,
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('shipping_schedules', 'shipments', 'quote_requests')
  and column_name = 'route'
order by table_name;




