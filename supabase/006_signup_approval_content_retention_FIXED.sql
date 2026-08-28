-- 006_signup_approval_content_retention_FIXED.sql
-- 기존 스키마/004/005 적용 후 실행.
-- is_content_manager()가 없는 기존 DB에서도 단독 실행 가능.
-- 재실행 가능.

-- 0) 관리자/직원 콘텐츠 관리 판별 함수 보장
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

grant execute on function public.is_content_manager() to anon, authenticated;

-- 1) 가입 신청 권한 보관
alter table public.profiles
  add column if not exists requested_role text not null default 'member';

alter table public.profiles
  drop constraint if exists profiles_requested_role_check;

alter table public.profiles
  add constraint profiles_requested_role_check
  check (requested_role in ('member','staff','partner','admin'));

update public.profiles
set requested_role = role
where requested_role is null
   or requested_role = '';

-- 2) 신규 가입 trigger
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested text;
begin
  requested := coalesce(
    new.raw_user_meta_data->>'requested_role',
    new.raw_user_meta_data->>'role',
    'member'
  );

  if requested not in ('member','partner','admin') then
    requested := 'member';
  end if;

  insert into public.profiles(
    id,
    email,
    name,
    phone,
    company,
    role,
    requested_role,
    approval_status
  )
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'company', ''),
    'member',
    requested,
    case when requested = 'member' then 'approved' else 'pending' end
  )
  on conflict (id) do update set
    email = excluded.email,
    name = excluded.name,
    phone = excluded.phone,
    company = excluded.company,
    requested_role = excluded.requested_role,
    role = case
      when excluded.requested_role = 'member' then 'member'
      else public.profiles.role
    end,
    approval_status = case
      when excluded.requested_role = 'member' then 'approved'
      else public.profiles.approval_status
    end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 3) 관리자 회원 관리 권한
grant select, update on table public.profiles to authenticated;

-- 4) 일정/공지 보관 컬럼
alter table public.shipping_schedules
  add column if not exists deletion_status text not null default 'active';
alter table public.shipping_schedules
  add column if not exists deleted_at timestamptz;
alter table public.shipping_schedules
  add column if not exists purge_after timestamptz;

alter table public.notices
  add column if not exists deletion_status text not null default 'active';
alter table public.notices
  add column if not exists deleted_at timestamptz;
alter table public.notices
  add column if not exists purge_after timestamptz;

-- 5) 30일 지난 삭제대기 자료 완전삭제
create or replace function public.purge_expired_content()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.shipping_schedules
  where deletion_status = 'pending'
    and purge_after is not null
    and purge_after <= now();

  delete from public.notices
  where deletion_status = 'pending'
    and purge_after is not null
    and purge_after <= now();
end;
$$;

grant execute on function public.purge_expired_content() to anon, authenticated;

-- 6) 홈 공개 조회: active만
drop policy if exists "public can read active schedules"
  on public.shipping_schedules;
drop policy if exists cargoflow_public_active_schedules
  on public.shipping_schedules;

create policy cargoflow_public_active_schedules
on public.shipping_schedules
for select
using (
  deleted_at is null
  and deletion_status = 'active'
);

drop policy if exists "public can read active notices"
  on public.notices;
drop policy if exists cargoflow_public_active_notices
  on public.notices;

create policy cargoflow_public_active_notices
on public.notices
for select
using (
  deleted_at is null
  and deletion_status = 'active'
);

-- 관리자/직원은 삭제 대기 자료까지 조회
drop policy if exists "managers can read all schedules"
  on public.shipping_schedules;
create policy "managers can read all schedules"
on public.shipping_schedules
for select
using (public.is_content_manager());

drop policy if exists "managers can read all notices"
  on public.notices;
create policy "managers can read all notices"
on public.notices
for select
using (public.is_content_manager());

-- 관리자는 즉시 삭제 가능
drop policy if exists "managers can delete schedules"
  on public.shipping_schedules;
create policy "managers can delete schedules"
on public.shipping_schedules
for delete
using (public.is_content_manager());

drop policy if exists "managers can delete notices"
  on public.notices;
create policy "managers can delete notices"
on public.notices
for delete
using (public.is_content_manager());

grant select, insert, update, delete
on table public.shipping_schedules, public.notices
to authenticated;

grant select
on table public.shipping_schedules, public.notices
to anon;
