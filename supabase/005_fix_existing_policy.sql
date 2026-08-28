-- 005_fix_existing_policy.sql
-- ERROR 42710 repair. Safe to run repeatedly.
-- Run this after the previously applied migrations. Do not rerun the whole combined SQL.

drop policy if exists shipments_read_scoped on public.shipments;
drop policy if exists shipments_staff_partner_admin_write on public.shipments;
drop policy if exists shipments_staff_partner_admin_update on public.shipments;
drop policy if exists shipments_member_change_request_only on public.shipments;

create or replace function public.normalize_person_name(value text)
returns text language sql immutable
as $$ select lower(regexp_replace(btrim(coalesce(value,'')), '\s+', ' ', 'g')) $$;

create or replace function public.normalize_phone(value text)
returns text language sql immutable
as $$ select regexp_replace(coalesce(value,''), '[^0-9]', '', 'g') $$;

create or replace function public.current_profile_name()
returns text language sql stable security definer set search_path=public
as $$ select name from public.profiles where id=auth.uid() $$;

create or replace function public.current_profile_phone()
returns text language sql stable security definer set search_path=public
as $$ select phone from public.profiles where id=auth.uid() $$;

create policy shipments_read_scoped on public.shipments
for select using (
  public.current_role() in ('admin','staff','partner')
  or (
    public.current_role() = 'member'
    and public.normalize_person_name(consignee_name) = public.normalize_person_name(public.current_profile_name())
    and public.normalize_phone(consignee_phone) = public.normalize_phone(public.current_profile_phone())
  )
);

create policy shipments_staff_partner_admin_write on public.shipments
for insert with check (public.current_role() in ('admin','staff','partner'));

create policy shipments_staff_partner_admin_update on public.shipments
for update using (public.current_role() in ('admin','staff','partner'))
with check (public.current_role() in ('admin','staff','partner'));
