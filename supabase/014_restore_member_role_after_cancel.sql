-- 014_restore_member_role_after_cancel.sql
-- 탈퇴 취소 시 탈퇴 직전의 권한/승인 상태를 확실히 복원합니다.
-- 화면 디자인/다른 기능과 무관한 회원 복원 로직만 보강합니다.

create or replace function public.cancel_member_deletion(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  snap jsonb;
  restored_role text;
  restored_requested_role text;
  restored_approval_status text;
begin
  select * into p
    from public.profiles
   where id = target_user_id
   for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  if p.deletion_status <> 'pending' then
    raise exception 'NOT_PENDING_DELETION';
  end if;

  select d.profile_snapshot
    into snap
    from public.deleted_member_accounts d
   where d.user_id = target_user_id
   order by d.deleted_at desc
   limit 1;

  -- snapshot이 있으면 탈퇴 직전 권한을 우선 복원합니다.
  -- 예전 데이터처럼 snapshot이 없더라도 현재 profile 값을 유지합니다.
  restored_role := coalesce(nullif(snap->>'role', ''), p.role, 'member');
  restored_requested_role := coalesce(
    nullif(snap->>'requested_role', ''),
    p.requested_role,
    restored_role
  );
  restored_approval_status := coalesce(
    nullif(snap->>'approval_status', ''),
    p.approval_status,
    'approved'
  );

  update public.profiles
     set role = restored_role,
         requested_role = restored_requested_role,
         approval_status = restored_approval_status,
         deletion_status = 'active',
         deletion_type = null,
         deleted_at = null,
         purge_after = null,
         updated_at = now()
   where id = target_user_id;

  delete from public.deleted_member_accounts
   where user_id = target_user_id;

  delete from public.account_deletion_email_otps
   where user_id = target_user_id;

  return jsonb_build_object(
    'ok', true,
    'email', p.email,
    'role', restored_role,
    'requested_role', restored_requested_role,
    'approval_status', restored_approval_status
  );
end;
$$;

revoke all on function public.cancel_member_deletion(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_member_deletion(uuid)
  to service_role;
