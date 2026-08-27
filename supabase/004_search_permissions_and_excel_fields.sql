-- CargoFlow search/permission alignment migration
-- Run after 001_roles_and_permissions.sql, 002_cargoflow_data.sql,
-- 003_route_column_repair.sql and supabase/migrations/001_content_management.sql.
-- Safe to run repeatedly.

-- Columns used by the Flutter search result and the home screen.
alter table public.shipments add column if not exists receipt_number text not null default '';
alter table public.shipping_schedules add column if not exists departure_date date;
alter table public.shipping_schedules add column if not exists estimated_arrival_date date;
alter table public.shipping_schedules add column if not exists deleted_at timestamptz;
alter table public.shipping_schedules add column if not exists deletion_status text not null default 'active';
alter table public.shipping_schedules add column if not exists purge_after timestamptz;
alter table public.notices add column if not exists deleted_at timestamptz;
alter table public.notices add column if not exists published_at timestamptz not null default now();
alter table public.notices add column if not exists is_new boolean not null default false;
alter table public.notices add column if not exists deletion_status text not null default 'active';
alter table public.notices add column if not exists purge_after timestamptz;

create index if not exists shipments_box_number_idx on public.shipments (box_number);
create index if not exists shipments_receipt_number_idx on public.shipments (receipt_number);
create index if not exists shipments_route_idx on public.shipments (route);

-- The business rule is:
-- member: only own customer_id rows; UI pre-fills name/phone from profiles.
-- staff/admin/partner: all shipment rows.
-- RLS is the final authority; client-side role checks are only presentation.
alter table public.shipments enable row level security;
drop policy if exists shipments_read_scoped on public.shipments;
create policy shipments_read_scoped on public.shipments
for select using (
  public.current_role() in ('admin', 'staff', 'partner')
  or (public.current_role() = 'member' and customer_id = auth.uid())
);

-- Staff, admin, and partner may write shipment data. A future deployment can
-- narrow partner writes without changing the search policy above.
drop policy if exists shipments_staff_partner_admin_write on public.shipments;
drop policy if exists shipments_staff_partner_admin_update on public.shipments;
create policy shipments_staff_partner_admin_write on public.shipments
for insert with check (public.current_role() in ('admin', 'staff', 'partner'));
create policy shipments_staff_partner_admin_update on public.shipments
for update using (public.current_role() in ('admin', 'staff', 'partner'))
with check (public.current_role() in ('admin', 'staff', 'partner'));

-- Schedules and notices are public read data, but only staff/admin can manage
-- them. Empty tables naturally render as empty sections in the app.
alter table public.shipping_schedules enable row level security;
alter table public.notices enable row level security;
drop policy if exists cargoflow_public_active_schedules on public.shipping_schedules;
drop policy if exists cargoflow_public_active_notices on public.notices;
create policy cargoflow_public_active_schedules on public.shipping_schedules
for select using (deleted_at is null and deletion_status = 'active');
create policy cargoflow_public_active_notices on public.notices
for select using (deleted_at is null and deletion_status = 'active');

comment on column public.shipments.receipt_number is 'Excel import field displayed in cargo search results';
comment on table public.shipments is 'Excel import target. Recommended unique business key: route + year + voyage + invoice_number + box_number.';

