-- CargoFlow Supabase roles and permissions
create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade, email text not null default '', name text not null default '', phone text not null default '', country_code text not null default '+82', address text not null default '', company text not null default '', role text not null default 'member' check (role in ('member','staff','partner','admin')), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table if not exists public.account_provision_requests (id bigint generated always as identity primary key, name text not null, email text not null, role text not null check (role in ('staff','partner')), company text not null default '', phone text not null default '', status text not null default 'pending' check (status in ('pending','approved','rejected')), created_at timestamptz not null default now());
create table if not exists public.shipment_change_requests (id bigint generated always as identity primary key, shipment_id bigint, requested_by uuid references auth.users(id), changes jsonb not null default '{}'::jsonb, status text not null default 'pending' check (status in ('pending','approved','rejected')), created_at timestamptz not null default now());
alter table public.profiles enable row level security;
alter table public.account_provision_requests enable row level security;
alter table public.shipment_change_requests enable row level security;
create or replace function public.current_role() returns text language sql stable security definer set search_path = public as $$ select role from public.profiles where id = auth.uid() $$;

-- Make this migration safe to run again in an existing project.
drop policy if exists "profile owner reads own profile" on public.profiles;
drop policy if exists "member creates own profile" on public.profiles;
drop policy if exists "owner updates own profile" on public.profiles;
drop policy if exists "admin manages profiles" on public.profiles;
drop policy if exists "admin creates provision requests" on public.account_provision_requests;
drop policy if exists "admin reads provision requests" on public.account_provision_requests;
drop policy if exists "admin updates provision requests" on public.account_provision_requests;
drop policy if exists "member creates own change request" on public.shipment_change_requests;
drop policy if exists "admin reads all change requests" on public.shipment_change_requests;
drop policy if exists "admin decides change requests" on public.shipment_change_requests;

create policy "profile owner reads own profile" on public.profiles for select using (id = auth.uid() or public.current_role() = 'admin');
create policy "member creates own profile" on public.profiles for insert with check (id = auth.uid() and role = 'member');
create policy "owner updates own profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = 'member');
create policy "admin manages profiles" on public.profiles for all using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
create policy "admin creates provision requests" on public.account_provision_requests for insert with check (public.current_role() = 'admin');
create policy "admin reads provision requests" on public.account_provision_requests for select using (public.current_role() = 'admin');
create policy "admin updates provision requests" on public.account_provision_requests for update using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
create policy "member creates own change request" on public.shipment_change_requests for insert with check (requested_by = auth.uid() and public.current_role() = 'member');
create policy "admin reads all change requests" on public.shipment_change_requests for select using (public.current_role() = 'admin');
create policy "admin decides change requests" on public.shipment_change_requests for update using (public.current_role() = 'admin') with check (public.current_role() = 'admin');
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$ begin insert into public.profiles(id,email,name,phone,country_code,address,role) values (new.id, coalesce(new.email,''), coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.raw_user_meta_data->>'phone',''), coalesce(new.raw_user_meta_data->>'country_code','+82'), coalesce(new.raw_user_meta_data->>'address',''), 'member') on conflict (id) do update set email=excluded.email, name=excluded.name, phone=excluded.phone, country_code=excluded.country_code, address=excluded.address; return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
