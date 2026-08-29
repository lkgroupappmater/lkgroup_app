-- 054_route_delete_schema_repair.sql
-- Patch079 삭제 RPC의 실제 shipment_excel_templates 스키마 호환 수정.
-- 해당 테이블에는 active 컬럼이 없으므로 30일 대기 중 metadata는 그대로 보관하고,
-- route_definitions.status='deleted'로 신규 메뉴/업무 노출을 차단한다.
-- 30일 후 purge-deleted-routes가 metadata와 Storage 파일을 완전 삭제한다.

create or replace function public.admin_soft_delete_route(
  p_route_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  select status
  into v_status
  from public.route_definitions
  where route_key = p_route_key
  for update;

  if v_status is null then
    raise exception '운송 경로를 찾을 수 없습니다.';
  end if;

  if v_status = 'deleted' then
    raise exception '이미 삭제 대기 중인 운송 경로입니다.';
  end if;

  insert into public.route_definition_audit(
    route_key, action, snapshot, changed_by
  )
  select
    p_route_key,
    'soft_delete_30d',
    to_jsonb(r),
    auth.uid()
  from public.route_definitions r
  where r.route_key = p_route_key;

  update public.route_definitions
  set
    status = 'deleted',
    deleted_at = now(),
    purge_after = now() + interval '30 days',
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key;

  -- 삭제 즉시 계산/신규 적용 방지.
  update public.freight_rate_tiers
  set
    active = false,
    updated_at = now()
  where route_key = p_route_key;

  -- BASE template 테이블에는 active 컬럼이 있으므로 비활성화.
  update public.shipment_excel_base_templates
  set active = false
  where route_key = p_route_key;

  -- shipment_excel_templates에는 active 컬럼이 없음.
  -- 30일 보관 정책에 따라 metadata/Storage 원본은 그대로 보존하고
  -- purge-deleted-routes에서 30일 후 완전 삭제한다.
end
$$;

grant execute on function public.admin_soft_delete_route(text)
  to authenticated;
