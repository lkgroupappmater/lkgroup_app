-- 056_route_base_template_schema_repair.sql
-- 실제 shipment_excel_base_templates 스키마:
-- route_key, route_label, storage_path
-- file_name / active 컬럼을 사용하지 않는다.

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
    deleted_from_status = v_status,
    status = 'deleted',
    deleted_at = now(),
    purge_after = now() + interval '30 days',
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key;

  -- 운임만 즉시 비활성화.
  update public.freight_rate_tiers
  set
    active = false,
    updated_at = now()
  where route_key = p_route_key;

  -- shipment_excel_base_templates / shipment_excel_templates는
  -- 30일 보관 정책상 metadata와 Storage 원본을 그대로 둔다.
  -- 메뉴/신규 업무 노출은 route_definitions.status='deleted'가 차단한다.
end
$$;

grant execute on function public.admin_soft_delete_route(text)
  to authenticated;

create or replace function public.admin_restore_deleted_route(
  p_route_key text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_restore_status text;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  select
    case
      when deleted_from_status in ('active','draft','disabled')
        then deleted_from_status
      else 'active'
    end
  into v_restore_status
  from public.route_definitions
  where route_key = p_route_key
    and status = 'deleted'
    and purge_after > now()
  for update;

  if v_restore_status is null then
    raise exception '복구 가능한 삭제 대기 운송 경로를 찾을 수 없습니다.';
  end if;

  insert into public.route_definition_audit(
    route_key, action, snapshot, changed_by
  )
  select
    p_route_key,
    'restore_deleted_route',
    to_jsonb(r),
    auth.uid()
  from public.route_definitions r
  where r.route_key = p_route_key;

  update public.route_definitions
  set
    status = v_restore_status,
    deleted_at = null,
    purge_after = null,
    deleted_from_status = null,
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key
    and status = 'deleted';

  update public.freight_rate_tiers
  set
    active = (v_restore_status = 'active'),
    updated_at = now()
  where route_key = p_route_key;

  -- BASE/항차 template metadata와 Storage 원본은 삭제 대기 중에도 보존되므로
  -- 복구 시 별도 복원 작업이 필요 없다.
end
$$;

grant execute on function public.admin_restore_deleted_route(text)
  to authenticated;
