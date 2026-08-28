-- 011_member_role_requests_and_account_retention.sql
-- 목적:
-- 1) 어떤 권한으로 가입 신청해도 실제 가입/로그인은 일반회원으로 즉시 허용
-- 2) requested_role은 권한 승인 요청으로만 유지
-- 3) 회원 탈퇴/관리자 삭제는 30일 보관 후 auth.users까지 완전 삭제

alter table public.profiles add column if not exists deletion_status text not null default 'active';
alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.profiles add column if not exists purge_after timestamptz;

alter table public.profiles drop constraint if exists profiles_deletion_status_check;
alter table public.profiles add constraint profiles_deletion_status_check
  check (deletion_status in ('active','pending'));

-- 기존 '권한 승인 대기' 계정도 일반회원으로 즉시 사용할 수 있게 전환합니다.
-- requested_role은 그대로 두므로 총괄 관리자 화면의 승인 요청에는 계속 나타납니다.
update public.profiles
set role = 'member',
    approval_status = 'approved'
where approval_status = 'pending'
  and requested_role in ('admin','partner');

-- 신규 가입은 요청 권한과 관계없이 일반회원 + approved로 생성합니다.
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
    'member'
  );
  if requested not in ('member','partner','admin') then
    requested := 'member';
  end if;

  insert into public.profiles(
    id,email,name,phone,company,role,requested_role,approval_status,
    deletion_status,deleted_at,purge_after
  ) values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'company', ''),
    'member', requested, 'approved', 'active', null, null
  )
  on conflict (id) do update set
    email = excluded.email,
    name = excluded.name,
    phone = excluded.phone,
    company = excluded.company,
    requested_role = excluded.requested_role,
    role = 'member',
    approval_status = 'approved',
    deletion_status = 'active',
    deleted_at = null,
    purge_after = null;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 30일이 지난 탈퇴 계정의 Auth 사용자를 삭제합니다.
-- profiles가 auth.users를 참조하는 일반적인 Supabase FK 구성에서는 profile도 cascade 삭제됩니다.
create or replace function public.purge_expired_member_accounts()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- 업무 이력 자체는 보존하되 탈퇴 계정과 연결된 Auth FK 식별자는 제거합니다.
  update public.shipment_change_requests set requested_by = null
    where requested_by in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.shipping_schedules set created_by = null
    where created_by in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.shipments set customer_id = null
    where customer_id in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.shipments set assigned_partner_id = null
    where assigned_partner_id in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.quote_requests set requested_by = null
    where requested_by in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.account_provision_requests set reviewed_by = null
    where reviewed_by in (select id from public.profiles where deletion_status='pending' and purge_after <= now());
  update public.exchange_rate_settings set updated_by = null
    where updated_by in (select id from public.profiles where deletion_status='pending' and purge_after <= now());

  delete from auth.users u
  using public.profiles p
  where p.id = u.id
    and p.deletion_status = 'pending'
    and p.purge_after is not null
    and p.purge_after <= now();

  -- FK가 cascade가 아닌 프로젝트에서도 남은 profile을 정리합니다.
  delete from public.profiles p
  where p.deletion_status = 'pending'
    and p.purge_after is not null
    and p.purge_after <= now()
    and not exists (select 1 from auth.users u where u.id = p.id);
end;
$$;

revoke all on function public.purge_expired_member_accounts() from public, anon, authenticated;

-- pg_cron 사용 가능 프로젝트에서는 매일 03:20에 자동 정리합니다.
create extension if not exists pg_cron with schema extensions;
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-expired-member-accounts') then
    perform cron.unschedule('purge-expired-member-accounts');
  end if;
  perform cron.schedule(
    'purge-expired-member-accounts',
    '20 3 * * *',
    'select public.purge_expired_member_accounts();'
  );
end $$;
