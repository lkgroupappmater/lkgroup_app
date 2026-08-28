-- 006_signup_approval_content_retention.sql
-- 기존 스키마/004/005 적용 후 실행.
-- 가입 권한 요청 + 회원 승인/거절 + 공지/일정 30일 보관/복구/즉시삭제 지원.
-- 재실행 가능하게 작성.

-- 1) 가입 신청 권한 보관
alter table public.profiles
  add column if not exists requested_role text not null default 'member';

alter table public.profiles
  drop constraint if exists profiles_requested_role_check;

alter table public.profiles
  add constraint profiles_requested_role_check
  check (requested_role in ('member','staff','partner','admin'));

-- 기존 계정은 현재 role을 requested_role로 정렬
update public.profiles
set requested_role = role
where requested_role is null
   or requested_role = '';

-- 2) 신규 가입 trigger
-- 일반회원: 즉시 approved/member
-- 관리자/파트너: 실제 role은 member, requested_role에 희망 권한 저장, pending
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

-- 3) 관리자 회원 관리에 필요한 권한
-- RLS가 최종 권한을 통제하며 admin policy가 이미 존재해야 합니다.
grant select, update on table public.profiles to authenticated;

-- 4) 일정/공지 보관 컬럼 보강
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

-- 5) 만료된 삭제 대기 자료 완전 삭제.
-- 앱에서 목록을 불러올 때 이 함수를 호출하므로 30일이 지나면 자동 정리됩니다.
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

-- 6) 홈 공개 조회는 active + 미삭제만.
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

-- 관리자/직원이 삭제 대기 자료까지 볼 수 있도록 기존 manager read policy 유지/복구.
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

-- 관리자가 즉시 delete할 수 있도록 기존 delete policy도 보장.
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
