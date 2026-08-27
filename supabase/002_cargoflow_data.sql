-- CargoFlow production-oriented schema.
-- Run after 001_roles_and_permissions.sql in Supabase SQL Editor.
-- account_provision_requests intentionally accepts staff/partner only.
-- Member approval is represented by profiles.approval_status and is approved by admin.

create table if not exists public.shipping_schedules (
  id bigint generated always as identity primary key,
  route text not null,
  year text not null default '',
  voyage text not null default '',
  origin text not null default '',
  destination text not null default '',
  booking_close_date date,
  estimated_arrival_date date,
  status text not null default 'scheduled',
  detail text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shipments (
  id bigint generated always as identity primary key,
  box_number text not null default '',
  invoice_number text not null,
  route text not null default '',
  consignee_name text not null default '',
  consignee_phone text not null default '',
  customer_id uuid references auth.users(id),
  assigned_partner_id uuid references auth.users(id),
  origin text not null default '',
  destination text not null default '',
  status text not null default 'registered',
  received_at date,
  estimated_arrival date,
  actual_arrival date,
  weight_kg numeric,
  width_cm numeric,
  length_cm numeric,
  height_cm numeric,
  quantity integer,
  cargo_type text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Safe migration for projects where shipments was created by an earlier
-- connection-test schema using shipment_no instead of invoice_number.
alter table public.shipments add column if not exists box_number text not null default '';
alter table public.shipments add column if not exists invoice_number text;
alter table public.shipments add column if not exists route text not null default '';
alter table public.shipments add column if not exists consignee_name text not null default '';
alter table public.shipments add column if not exists consignee_phone text not null default '';
alter table public.shipments add column if not exists customer_id uuid references auth.users(id);
alter table public.shipments add column if not exists assigned_partner_id uuid references auth.users(id);
alter table public.shipments add column if not exists origin text not null default '';
alter table public.shipments add column if not exists destination text not null default '';
alter table public.shipments add column if not exists status text not null default 'registered';
alter table public.shipments add column if not exists received_at date;
alter table public.shipments add column if not exists estimated_arrival date;
alter table public.shipments add column if not exists actual_arrival date;
alter table public.shipments add column if not exists weight_kg numeric;
alter table public.shipments add column if not exists width_cm numeric;
alter table public.shipments add column if not exists length_cm numeric;
alter table public.shipments add column if not exists height_cm numeric;
alter table public.shipments add column if not exists quantity integer;
alter table public.shipments add column if not exists cargo_type text not null default '';
alter table public.shipments add column if not exists notes text not null default '';
alter table public.shipments add column if not exists created_at timestamptz not null default now();
alter table public.shipments add column if not exists updated_at timestamptz not null default now();

-- Preserve values from the old test schema when present.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shipments'
      and column_name = 'shipment_no'
  ) then
    update public.shipments
    set invoice_number = coalesce(nullif(invoice_number, ''), shipment_no)
    where invoice_number is null or invoice_number = '';
  end if;
end $$;

alter table public.shipments alter column invoice_number set default '';
update public.shipments set invoice_number = '' where invoice_number is null;
alter table public.shipments alter column invoice_number set not null;

create table if not exists public.quote_requests (
  id bigint generated always as identity primary key,
  requested_by uuid references auth.users(id),
  customer_name text not null default '',
  contact_phone text not null default '',
  contact_email text not null default '',
  route text not null,
  origin text not null default '',
  destination text not null default '',
  boxes jsonb not null default '[]'::jsonb,
  total_weight_kg numeric,
  status text not null default 'pending',
  admin_note text not null default '',
  quoted_amount numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Add approval state without changing the requested role vocabulary.
alter table public.profiles add column if not exists approval_status text not null default 'approved';
alter table public.profiles drop constraint if exists profiles_approval_status_check;
alter table public.profiles add constraint profiles_approval_status_check
  check (approval_status in ('pending','approved','rejected'));
alter table public.account_provision_requests add column if not exists reviewed_by uuid references auth.users(id);
alter table public.account_provision_requests add column if not exists reviewed_at timestamptz;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, email, name, phone, company, role, approval_status)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'company', ''),
    'member',
    'pending'
  )
  on conflict (id) do update set email = excluded.email, name = excluded.name,
    phone = excluded.phone, company = excluded.company;
  return new;
end;
$$;

-- New member registrations require administrator approval.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create index if not exists shipments_invoice_idx on public.shipments (invoice_number);
create index if not exists shipments_customer_idx on public.shipments (customer_id);
create index if not exists shipments_partner_idx on public.shipments (assigned_partner_id);
create index if not exists schedules_route_idx on public.shipping_schedules (route);
create index if not exists quotes_requester_idx on public.quote_requests (requested_by);

create or replace function public.current_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.is_approved_user()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and approval_status = 'approved') $$;

alter table public.shipping_schedules enable row level security;
alter table public.shipments enable row level security;
alter table public.quote_requests enable row level security;

-- Re-runnable policy deployment.
drop policy if exists schedules_read_all_authenticated on public.shipping_schedules;
drop policy if exists schedules_admin_write on public.shipping_schedules;
create policy schedules_read_all_authenticated on public.shipping_schedules
  for select using (auth.uid() is not null and public.is_approved_user());
create policy schedules_admin_write on public.shipping_schedules
  for all using (public.current_role() = 'admin') with check (public.current_role() = 'admin');

drop policy if exists shipments_read_scoped on public.shipments;
drop policy if exists shipments_staff_partner_admin_write on public.shipments;
drop policy if exists shipments_member_change_request_only on public.shipments;
create policy shipments_read_scoped on public.shipments for select using (
  public.current_role() in ('admin','staff')
  or (public.current_role() = 'partner' and assigned_partner_id = auth.uid())
  or (public.current_role() = 'member' and customer_id = auth.uid())
);
create policy shipments_staff_partner_admin_write on public.shipments for insert with check (
  public.current_role() in ('admin','staff','partner')
);
create policy shipments_staff_partner_admin_update on public.shipments for update using (
  public.current_role() in ('admin','staff','partner')
) with check (public.current_role() in ('admin','staff','partner'));

drop policy if exists quotes_insert_approved on public.quote_requests;
drop policy if exists quotes_read_scoped on public.quote_requests;
drop policy if exists quotes_admin_update on public.quote_requests;
create policy quotes_insert_approved on public.quote_requests for insert with check (
  requested_by = auth.uid() and public.is_approved_user()
);
create policy quotes_read_scoped on public.quote_requests for select using (
  public.current_role() in ('admin','staff') or requested_by = auth.uid()
);
create policy quotes_admin_update on public.quote_requests for update using (
  public.current_role() in ('admin','staff')
) with check (public.current_role() in ('admin','staff'));

-- Admin may approve member profiles and staff/partner requests.
drop policy if exists admin_updates_profiles on public.profiles;
create policy admin_updates_profiles on public.profiles for update
  using (public.current_role() = 'admin') with check (public.current_role() = 'admin');

drop policy if exists admin_manages_provision_requests on public.account_provision_requests;
create policy admin_manages_provision_requests on public.account_provision_requests for all
  using (public.current_role() = 'admin') with check (
    public.current_role() = 'admin' and role in ('staff','partner')
  );

-- Import helper: only admin/staff can bulk insert through the client.
-- For large files prefer a server-side Edge Function or Supabase CSV import.
comment on table public.shipments is 'Excel import target; map invoice_number, box_number, route, consignee_name, consignee_phone, received_at.';

