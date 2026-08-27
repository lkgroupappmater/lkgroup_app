-- CargoFlow: 선적 일정·공지사항 관리 테이블과 권한 정책
-- Supabase SQL Editor에서 한 번 실행하거나 Supabase migration으로 적용하세요.
-- 앱의 삭제 버튼은 실제 삭제가 아닌 30일 후 삭제 대기 상태로 변경합니다.

create table if not exists public.shipping_schedules (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  route text not null,
  origin text not null default '',
  destination text not null default '',
  departure_date date,
  closing_date date,
  arrival_date date,
  detail text not null default '',
  deletion_status text not null default 'active'
    check (deletion_status in ('active', 'pending')),
  deleted_at timestamptz,
  purge_after timestamptz
);

create table if not exists public.notices (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  title text not null,
  content text not null,
  is_pinned boolean not null default false,
  published_at timestamptz not null default now(),
  deletion_status text not null default 'active'
    check (deletion_status in ('active', 'pending')),
  deleted_at timestamptz,
  purge_after timestamptz
);

-- AuthService also reads this table after Supabase login. If it already exists,
-- this statement leaves the existing table unchanged.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member'
);

create or replace function public.is_content_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('staff', 'admin')
  )
  or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('staff', 'admin')
  or coalesce(auth.jwt() -> 'user_metadata' ->> 'role', '') in ('staff', 'admin');
$$;

alter table public.shipping_schedules enable row level security;
alter table public.notices enable row level security;

drop policy if exists "public can read active schedules" on public.shipping_schedules;
drop policy if exists "managers can read all schedules" on public.shipping_schedules;
drop policy if exists "managers can insert schedules" on public.shipping_schedules;
drop policy if exists "managers can update schedules" on public.shipping_schedules;
drop policy if exists "managers can delete schedules" on public.shipping_schedules;

create policy "public can read active schedules"
on public.shipping_schedules for select
using (deleted_at is null and deletion_status = 'active');

create policy "managers can read all schedules"
on public.shipping_schedules for select
using (public.is_content_manager());

create policy "managers can insert schedules"
on public.shipping_schedules for insert
with check (public.is_content_manager());

create policy "managers can update schedules"
on public.shipping_schedules for update
using (public.is_content_manager())
with check (public.is_content_manager());

create policy "managers can delete schedules"
on public.shipping_schedules for delete
using (public.is_content_manager());

drop policy if exists "public can read active notices" on public.notices;
drop policy if exists "managers can read all notices" on public.notices;
drop policy if exists "managers can insert notices" on public.notices;
drop policy if exists "managers can update notices" on public.notices;
drop policy if exists "managers can delete notices" on public.notices;

create policy "public can read active notices"
on public.notices for select
using (deleted_at is null and deletion_status = 'active');

create policy "managers can read all notices"
on public.notices for select
using (public.is_content_manager());

create policy "managers can insert notices"
on public.notices for insert
with check (public.is_content_manager());

create policy "managers can update notices"
on public.notices for update
using (public.is_content_manager())
with check (public.is_content_manager());

create policy "managers can delete notices"
on public.notices for delete
using (public.is_content_manager());

create index if not exists shipping_schedules_active_order_idx
  on public.shipping_schedules (deleted_at, departure_date, closing_date);
create index if not exists notices_active_order_idx
  on public.notices (deleted_at, is_pinned, published_at desc);

-- 주의: public.profiles 테이블은 auth.uid()와 role(staff/admin/member 등)을
-- 저장하는 기존 사용자 프로필 테이블을 사용해야 합니다. 테이블이 없다면
-- 먼저 profiles를 만들고, 관리자 계정에 role='staff' 또는 role='admin'을 부여하세요.


