-- 013_separate_deletion_otp_and_signup_cooldown.sql
-- 통합 변경:
-- 1) 회원 탈퇴 전용 이메일 OTP 분리
-- 2) 자진 탈퇴는 동일 이메일 3일 재가입 제한
-- 3) 총괄 관리자에 의한 탈퇴 요청은 재가입 제한 없음
-- 4) 모든 탈퇴 요청은 profiles에 pending 상태로 30일 보관
-- 5) 총괄 관리자 화면에서 탈퇴 취소 / 탈퇴 확정 처리
-- 6) 탈퇴 확정 시 즉시 Auth/Profile을 완전 삭제하고 3일 제한도 제거
-- 7) 30일간 아무 처리 없으면 자동 완전 삭제

create extension if not exists pgcrypto with schema extensions;

alter table public.profiles add column if not exists deletion_status text not null default 'active';
alter table public.profiles add column if not exists deletion_type text;
alter table public.profiles add column if not exists deleted_at timestamptz;
alter table public.profiles add column if not exists purge_after timestamptz;

alter table public.profiles drop constraint if exists profiles_deletion_status_check;
alter table public.profiles add constraint profiles_deletion_status_check
  check (deletion_status in ('active','pending'));

alter table public.profiles drop constraint if exists profiles_deletion_type_check;
alter table public.profiles add constraint profiles_deletion_type_check
  check (deletion_type is null or deletion_type in ('self','admin'));

create table if not exists public.deleted_member_accounts (
  deletion_id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null,
  email text not null,
  deletion_type text not null,
  deleted_at timestamptz not null default now(),
  signup_block_until timestamptz,
  purge_after timestamptz not null,
  profile_snapshot jsonb not null default '{}'::jsonb,
  constraint deleted_member_accounts_deletion_type_check
    check (deletion_type in ('self','admin'))
);

create index if not exists deleted_member_accounts_email_lower_idx
  on public.deleted_member_accounts (lower(email));
create index if not exists deleted_member_accounts_user_id_idx
  on public.deleted_member_accounts (user_id);
create index if not exists deleted_member_accounts_purge_after_idx
  on public.deleted_member_accounts (purge_after);

revoke all on table public.deleted_member_accounts from public, anon, authenticated;
grant select, insert, update, delete on table public.deleted_member_accounts to service_role;

create table if not exists public.account_deletion_email_otps (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz not null,
  sent_at timestamptz not null default now(),
  attempts integer not null default 0
);

revoke all on table public.account_deletion_email_otps from public, anon, authenticated;
grant select, insert, update, delete on table public.account_deletion_email_otps to service_role;

-- 신규 가입 시 자진 탈퇴 이메일의 3일 제한을 서버에서 강제합니다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested text;
  blocked_until timestamptz;
begin
  select max(d.signup_block_until)
    into blocked_until
    from public.deleted_member_accounts d
   where lower(d.email) = lower(coalesce(new.email, ''))
     and d.deletion_type = 'self'
     and d.signup_block_until is not null
     and d.signup_block_until > now();

  if blocked_until is not null then
    raise exception 'SELF_DELETION_EMAIL_COOLDOWN:%', blocked_until;
  end if;

  requested := coalesce(new.raw_user_meta_data->>'requested_role', 'member');
  if requested not in ('member','partner','admin') then
    requested := 'member';
  end if;

  insert into public.profiles(
    id,email,name,phone,company,role,requested_role,approval_status,
    deletion_status,deletion_type,deleted_at,purge_after
  ) values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'company', ''),
    'member', requested, 'approved', 'active', null, null, null
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
    deletion_type = null,
    deleted_at = null,
    purge_after = null;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Edge Function에서 Auth 이메일을 임시 tombstone 주소로 바꾼 뒤 호출합니다.
-- profile의 원래 이메일/회원정보는 30일간 그대로 보관됩니다.
create or replace function public.mark_member_deletion_pending(
  target_user_id uuid,
  deletion_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  block_until timestamptz;
  purge_at timestamptz := now() + interval '30 days';
begin
  if deletion_kind not in ('self','admin') then
    raise exception 'INVALID_DELETION_KIND';
  end if;

  select * into p
    from public.profiles
   where id = target_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  if p.deletion_status = 'pending' then
    raise exception 'ALREADY_PENDING_DELETION';
  end if;

  block_until := case
    when deletion_kind = 'self' then now() + interval '3 days'
    else null
  end;

  delete from public.deleted_member_accounts where user_id = target_user_id;

  insert into public.deleted_member_accounts(
    user_id,email,deletion_type,deleted_at,signup_block_until,purge_after,profile_snapshot
  ) values (
    p.id,
    coalesce(p.email,''),
    deletion_kind,
    now(),
    block_until,
    purge_at,
    to_jsonb(p)
  );

  update public.profiles
     set deletion_status = 'pending',
         deletion_type = deletion_kind,
         deleted_at = now(),
         purge_after = purge_at,
         updated_at = now()
   where id = target_user_id;

  delete from public.account_deletion_email_otps where user_id = target_user_id;

  return jsonb_build_object(
    'ok', true,
    'deletion_type', deletion_kind,
    'signup_block_until', block_until,
    'purge_after', purge_at,
    'email', p.email
  );
end;
$$;

revoke all on function public.mark_member_deletion_pending(uuid,text)
  from public, anon, authenticated;
grant execute on function public.mark_member_deletion_pending(uuid,text)
  to service_role;

-- Auth 이메일 원복/ban 해제에 성공한 뒤 호출합니다.
create or replace function public.cancel_member_deletion(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
begin
  select * into p from public.profiles where id = target_user_id for update;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  if p.deletion_status <> 'pending' then raise exception 'NOT_PENDING_DELETION'; end if;

  delete from public.deleted_member_accounts where user_id = target_user_id;
  delete from public.account_deletion_email_otps where user_id = target_user_id;

  update public.profiles
     set deletion_status = 'active',
         deletion_type = null,
         deleted_at = null,
         purge_after = null,
         updated_at = now()
   where id = target_user_id;

  return jsonb_build_object('ok', true, 'email', p.email);
end;
$$;

revoke all on function public.cancel_member_deletion(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_member_deletion(uuid)
  to service_role;

-- 업무 이력 자체는 보존하되 탈퇴 회원 UUID 연결만 제거한 뒤 Auth/Profile을 완전 삭제합니다.
create or replace function public.hard_delete_member_account(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  update public.shipment_change_requests set requested_by = null where requested_by = target_user_id;
  update public.shipping_schedules set created_by = null where created_by = target_user_id;
  update public.shipments set customer_id = null where customer_id = target_user_id;
  update public.shipments set assigned_partner_id = null where assigned_partner_id = target_user_id;
  update public.quote_requests set requested_by = null where requested_by = target_user_id;
  update public.account_provision_requests set reviewed_by = null where reviewed_by = target_user_id;
  update public.exchange_rate_settings set updated_by = null where updated_by = target_user_id;

  delete from public.account_deletion_email_otps where user_id = target_user_id;
  delete from public.deleted_member_accounts where user_id = target_user_id;

  delete from auth.users where id = target_user_id;
  delete from public.profiles where id = target_user_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.hard_delete_member_account(uuid)
  from public, anon, authenticated;
grant execute on function public.hard_delete_member_account(uuid)
  to service_role;

create or replace function public.purge_expired_member_accounts()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  r record;
begin
  for r in
    select id from public.profiles
     where deletion_status = 'pending'
       and purge_after is not null
       and purge_after <= now()
  loop
    perform public.hard_delete_member_account(r.id);
  end loop;

  -- 이전 버전에서 profile 없이 보관소만 남은 데이터도 정리합니다.
  delete from public.deleted_member_accounts where purge_after <= now();
end;
$$;

revoke all on function public.purge_expired_member_accounts() from public, anon, authenticated;

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
