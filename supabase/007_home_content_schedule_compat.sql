-- 007_home_content_schedule_compat.sql
-- 최신 앱의 shipping_schedules.route 필드와
-- 기존 DB에 남아 있는 route_category NOT NULL 컬럼 충돌을 안전하게 해소합니다.
-- 기존 데이터/화면/기능은 삭제하지 않습니다.
-- 재실행 가능.

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'shipping_schedules'
      and column_name = 'route_category'
  ) then
    -- 최신 앱은 route를 실제 운송 경로 필드로 사용합니다.
    -- 예전 route_category 값은 그대로 보존하고,
    -- 신규 일정 저장 시 NULL이어도 실패하지 않도록 NOT NULL만 해제합니다.
    execute
      'alter table public.shipping_schedules
       alter column route_category drop not null';
  end if;
end $$;

-- 홈에는 active + 미삭제 자료만 공개.
alter table public.shipping_schedules enable row level security;
alter table public.notices enable row level security;

drop policy if exists cargoflow_public_active_schedules
  on public.shipping_schedules;
create policy cargoflow_public_active_schedules
on public.shipping_schedules
for select
using (
  deleted_at is null
  and deletion_status = 'active'
);

drop policy if exists cargoflow_public_active_notices
  on public.notices;
create policy cargoflow_public_active_notices
on public.notices
for select
using (
  deleted_at is null
  and deletion_status = 'active'
);

-- 공개 홈 조회용 기본 GRANT 보장.
grant select on table public.shipping_schedules to anon, authenticated;
grant select on table public.notices to anon, authenticated;
