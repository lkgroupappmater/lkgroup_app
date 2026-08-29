-- 055_route_delete_restore_countdown.sql
-- 운송 경로 삭제 후 30일 이내 복구(삭제 취소) 기능.
-- 기존 hard delete 정책은 그대로 유지하며 즉시 완전 삭제 기능은 만들지 않는다.

alter table public.route_definitions
  add column if not exists deleted_from_status text;

-- 이미 삭제 대기 중인데 이전 상태 기록이 없는 기존 테스트 데이터 보정.
-- base_route_key가 있고 route_ 형태의 신규 draft는 draft로, 그 외는 active로 추정.
update public.route_definitions
set deleted_from_status =
  case
    when deleted_from_status is not null then deleted_from_status
    when status = 'deleted'
         and coalesce(base_route_key, '') <> ''
         and route_key like 'route_%'
      then 'draft'
    when status = 'deleted' then 'active'
    else deleted_from_status
  end
where status = 'deleted'
  and deleted_from_status is null;

-- 관리 화면은 active/draft/deleted를 모두 받아서 화면에서 구분한다.
create or replace function public.admin_route_definitions()
returns setof public.route_definitions
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  return query
  select *
  from public.route_definitions
  order by
    case status
      when 'active' then 1
      when 'draft' then 2
      when 'deleted' then 3
      else 4
    end,
    display_name;
end
$$;

grant execute on function public.admin_route_definitions()
  to authenticated;

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

  update public.freight_rate_tiers
  set
    active = false,
    updated_at = now()
  where route_key = p_route_key;

  update public.shipment_excel_base_templates
  set active = false
  where route_key = p_route_key;
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

  if v_restore_status = 'active' then
    update public.freight_rate_tiers
    set
      active = true,
      updated_at = now()
    where route_key = p_route_key;

    update public.shipment_excel_base_templates
    set active = true
    where route_key = p_route_key;
  else
    -- draft 복구 시에는 아직 실제 업무에 적용되지 않도록 운임/BASE 비활성 상태 유지.
    update public.freight_rate_tiers
    set
      active = false,
      updated_at = now()
    where route_key = p_route_key;

    update public.shipment_excel_base_templates
    set active = false
    where route_key = p_route_key;
  end if;
end
$$;

grant execute on function public.admin_restore_deleted_route(text)
  to authenticated;
