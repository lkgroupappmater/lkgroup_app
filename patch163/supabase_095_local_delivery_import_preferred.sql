-- Patch163 / 095
-- Local-delivery BASE import support.
-- IMPORTANT: discount rules remain route-specific. This migration does not
-- merge sea/air/land discount rows and does not create route_key='all'.

alter table public.local_delivery_profiles
  add column if not exists preferred boolean not null default false;

create index if not exists local_delivery_profiles_route_preferred_idx
  on public.local_delivery_profiles(route_key, preferred desc, source_no);

comment on column public.local_delivery_profiles.preferred is
'BASE Excel yellow-highlighted preferred local company/destination row. App matching should prefer true before source_no.';

-- Existing data is intentionally left unchanged.
-- New BASE uploads populate preferred from the workbook fill color:
-- green row => city, white/default row => province,
-- yellow local-company/destination cell => preferred.
