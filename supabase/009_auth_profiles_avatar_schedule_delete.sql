-- 009_auth_profiles_avatar_schedule_delete.sql
-- 회원가입/권한/프로필사진/선적일정 완전삭제 보강.
-- 기존 데이터는 유지하며 재실행 가능.

-- 1. profiles 보강
alter table public.profiles add column if not exists requested_role text not null default 'member';
alter table public.profiles add column if not exists approval_status text not null default 'approved';
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists company text not null default '';
alter table public.profiles add column if not exists address text not null default '';
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

alter table public.profiles drop constraint if exists profiles_requested_role_check;
alter table public.profiles add constraint profiles_requested_role_check
  check (requested_role in ('member','staff','partner','admin'));

-- 일반회원은 즉시 승인, 관리자/파트너 신청은 pending.
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
    id,email,name,phone,company,role,requested_role,approval_status
  )
  values (
    new.id,
    coalesce(new.email,''),
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'phone',''),
    coalesce(new.raw_user_meta_data->>'company',''),
    'member',
    requested,
    case when requested='member' then 'approved' else 'pending' end
  )
  on conflict (id) do update set
    email=excluded.email,
    name=excluded.name,
    phone=excluded.phone,
    company=excluded.company,
    requested_role=excluded.requested_role,
    approval_status=case
      when excluded.requested_role='member' then 'approved'
      else public.profiles.approval_status
    end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- 2. profile RLS: 본인 조회/수정 + 총괄 관리자 전체 조회/수정.
alter table public.profiles enable row level security;

drop policy if exists "profile owner reads own profile" on public.profiles;
drop policy if exists "owner updates own profile" on public.profiles;
drop policy if exists "admin manages profiles" on public.profiles;
drop policy if exists admin_updates_profiles on public.profiles;
drop policy if exists profiles_owner_select on public.profiles;
drop policy if exists profiles_owner_update on public.profiles;
drop policy if exists profiles_admin_all on public.profiles;

create policy profiles_owner_select on public.profiles
for select using (id = auth.uid());

create policy profiles_owner_update on public.profiles
for update using (id = auth.uid())
with check (
  id = auth.uid()
  and role = public.current_role()
);

create policy profiles_admin_all on public.profiles
for all using (public.current_role() = 'admin')
with check (public.current_role() = 'admin');

grant select, update on public.profiles to authenticated;

-- 3. 프로필 이미지 Storage bucket.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars public read" on storage.objects;
drop policy if exists "avatars owner insert" on storage.objects;
drop policy if exists "avatars owner update" on storage.objects;
drop policy if exists "avatars owner delete" on storage.objects;

create policy "avatars public read"
on storage.objects for select
using (bucket_id = 'avatars');

create policy "avatars owner insert"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "avatars owner update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "avatars owner delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 4. 선적 일정 완전 삭제 시 schedule_reservations FK가 막지 않도록 CASCADE.
do $$
begin
  if to_regclass('public.schedule_reservations') is not null
     and exists (
       select 1 from information_schema.columns
       where table_schema='public'
         and table_name='schedule_reservations'
         and column_name='schedule_id'
     ) then

    alter table public.schedule_reservations
      drop constraint if exists schedule_reservations_schedule_id_fkey;

    alter table public.schedule_reservations
      add constraint schedule_reservations_schedule_id_fkey
      foreign key (schedule_id)
      references public.shipping_schedules(id)
      on delete cascade;
  end if;
end $$;
