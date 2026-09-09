-- Public app information is readable without login, while every guest access
-- remains read-only. Cargo, member, quote and settlement data are unchanged.
begin;

alter table public.notices enable row level security;
alter table public.shipping_schedules enable row level security;
alter table public.website_articles enable row level security;
alter table public.site_public_text enable row level security;

-- Guest clients only need SELECT on these four public-information tables.
revoke insert, update, delete, truncate, references, trigger on table
  public.notices,
  public.shipping_schedules,
  public.website_articles,
  public.site_public_text
from anon;

grant select on table
  public.notices,
  public.shipping_schedules,
  public.website_articles,
  public.site_public_text
to anon, authenticated;

-- Consolidate legacy overlapping policies. Public notices are visible only
-- after publication; content managers retain their separate full-read policy.
drop policy if exists cargoflow_public_active_notices on public.notices;
drop policy if exists "public can read active notices" on public.notices;
drop policy if exists "public reads active notices" on public.notices;
create policy "public reads published active notices"
on public.notices
for select
to anon, authenticated
using (
  deletion_status = 'active'
  and deleted_at is null
  and (published_at is null or published_at <= now())
);

-- Hidden schedules remain visible only through the existing manager policy.
drop policy if exists cargoflow_public_active_schedules on public.shipping_schedules;
drop policy if exists "public can read active schedules" on public.shipping_schedules;
drop policy if exists "public reads active schedules" on public.shipping_schedules;
create policy "public reads visible active schedules"
on public.shipping_schedules
for select
to anon, authenticated
using (
  is_visible is true
  and deletion_status = 'active'
  and deleted_at is null
);

commit;
