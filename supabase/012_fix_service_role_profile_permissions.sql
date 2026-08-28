-- 012_fix_service_role_profile_permissions.sql
-- Edge Functions(admin-create-user / member-account-delete)이 profiles 테이블에
-- service_role로 접근할 때 발생하는 "permission denied for table profiles" 수정.
--
-- 앱의 화면/권한 구조/RLS 정책은 변경하지 않습니다.

-- service_role은 서버 전용 Edge Function에서만 사용되며 클라이언트에는 노출되지 않습니다.
grant usage on schema public to service_role;
grant select, insert, update, delete on table public.profiles to service_role;

-- 혹시 기존 프로젝트에서 함수 실행 권한이 제한되어 있어도 현재 역할 조회 함수는
-- 서버에서 사용할 수 있도록 보장합니다.
grant execute on function public.current_role() to service_role;

-- 현재 접속자가 총괄 관리자(role='admin')인지 서버에서 안전하게 확인하는 함수.
-- auth.uid()가 아니라 전달된 UUID를 사용하며, service_role만 실행할 수 있습니다.
create or replace function public.is_total_admin_user(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = target_user_id
       and p.role = 'admin'
       and coalesce(p.approval_status, 'approved') = 'approved'
       and coalesce(p.deletion_status, 'active') = 'active'
  );
$$;

revoke all on function public.is_total_admin_user(uuid) from public, anon, authenticated;
grant execute on function public.is_total_admin_user(uuid) to service_role;
