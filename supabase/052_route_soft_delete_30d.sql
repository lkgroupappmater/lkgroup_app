-- 052_route_soft_delete_30d.sql
-- 운송 경로 삭제 정책:
-- 즉시 메뉴/업무 선택에서 제거 -> 30일 보관 -> 자동 완전 삭제.
-- 즉시 hard delete RPC는 만들지 않는다.

alter table public.route_definitions
  drop constraint if exists route_definitions_status_check;

alter table public.route_definitions
  add constraint route_definitions_status_check
  check (status in ('draft','active','disabled','deleted'));

alter table public.route_definitions
  add column if not exists deleted_at timestamptz;

alter table public.route_definitions
  add column if not exists purge_after timestamptz;

-- 앱 런타임 RouteCatalog용. draft도 전달하지만 앱에서는 active만 표시한다.
-- deleted key도 전달해야 내장 11개 fallback이 다시 나타나지 않는다.
create or replace function public.list_route_catalog_definitions()
returns table(
  route_key text,
  display_name text,
  status text,
  base_route_key text,
  file_prefix text,
  box_prefix text,
  receipt_prefix text
)
language sql
security definer
set search_path = public
as $$
  select
    r.route_key,
    r.display_name,
    r.status,
    coalesce(r.base_route_key, ''),
    r.file_prefix,
    r.box_prefix,
    r.receipt_prefix
  from public.route_definitions r
  order by r.created_at, r.display_name
$$;

revoke all on function public.list_route_catalog_definitions() from public;
grant execute on function public.list_route_catalog_definitions()
  to anon, authenticated;

-- 관리 화면에서도 삭제된 경로는 즉시 목록에서 사라진다.
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
  where status <> 'deleted'
  order by status, display_name;
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

  -- 항차별 템플릿도 더 이상 신규 업무에서 선택되지 않도록 비활성화.
  update public.shipment_excel_templates
  set active = false
  where route_key = p_route_key;
end
$$;

grant execute on function public.admin_soft_delete_route(text)
  to authenticated;

-- 자동 정리 Function 호출.
-- Function 자체가 purge_after <= now()만 처리하므로 외부에서 호출되어도 조기 삭제되지 않는다.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$
begin
  if exists (
    select 1 from cron.job where jobname = 'purge-deleted-routes-hourly'
  ) then
    perform cron.unschedule('purge-deleted-routes-hourly');
  end if;
end $$;

select cron.schedule(
  'purge-deleted-routes-hourly',
  '15 * * * *',
  $cron$
    select net.http_post(
      url := 'https://rkqwzxfcnciptnwesfbr.supabase.co/functions/v1/purge-deleted-routes',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := '{"source":"pg_cron"}'::jsonb
    );
  $cron$
);
