-- Invalidation signals only. Existing table policies and shipment RPCs remain
-- the source of truth; this stream never contains names, phones or amounts.
create table public.app_data_revisions (
  topic text primary key check (topic in ('content', 'shipments')),
  revision bigint not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);
alter table public.app_data_revisions enable row level security;
revoke all on public.app_data_revisions from public, anon, authenticated;
grant select on public.app_data_revisions to anon, authenticated;
grant all on public.app_data_revisions to service_role;
create policy app_revision_public_content on public.app_data_revisions
  for select to anon using (topic = 'content');
create policy app_revision_signed_in on public.app_data_revisions
  for select to authenticated using (true);

insert into public.app_data_revisions(topic) values ('content'), ('shipments');

create function public.app_bump_data_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.app_data_revisions
  set revision = revision + 1, updated_at = clock_timestamp()
  where topic = TG_ARGV[0];
  return null;
end;
$$;
revoke all on function public.app_bump_data_revision() from public, anon, authenticated;

do $$
declare
  source_table text;
begin
  foreach source_table in array array[
    'notices', 'shipping_schedules', 'schedules', 'website_articles'
  ] loop
    execute format(
      'create trigger app_content_revision after insert or update or delete on public.%I '
      'for each statement execute function public.app_bump_data_revision(''content'')',
      source_table
    );
  end loop;
  foreach source_table in array array[
    'shipments', 'receipt_discount_overrides', 'customer_rate_overrides',
    'local_delivery_profiles'
  ] loop
    execute format(
      'create trigger app_shipment_revision after insert or update or delete on public.%I '
      'for each statement execute function public.app_bump_data_revision(''shipments'')',
      source_table
    );
  end loop;
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  alter publication supabase_realtime add table public.app_data_revisions;
end;
$$;
