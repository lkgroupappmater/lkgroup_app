-- 008_shipping_schedule_status_and_home_visibility.sql
-- 현재 실DB의 legacy shipping_schedules_status_check 충돌 복구 +
-- 홈에서 삭제대기 자료가 노출되지 않도록 정책을 다시 고정.
-- 기존 데이터/화면 구조는 변경하지 않음. 재실행 가능.

-- 1) 현재 앱은 신규 일정에 status를 직접 지정하지 않고 DB 기본값을 사용합니다.
-- 과거 DB의 status CHECK가 최신 'scheduled' 값과 충돌하므로 해당 legacy CHECK만 제거합니다.
alter table public.shipping_schedules
  drop constraint if exists shipping_schedules_status_check;

alter table public.shipping_schedules
  alter column status set default 'scheduled';

-- 2) 홈 공개 조회는 반드시 active + 미삭제만 허용.
alter table public.shipping_schedules enable row level security;
alter table public.notices enable row level security;

drop policy if exists cargoflow_public_active_schedules
  on public.shipping_schedules;
create policy cargoflow_public_active_schedules
on public.shipping_schedules
for select
using (
  deletion_status = 'active'
  and deleted_at is null
);

drop policy if exists cargoflow_public_active_notices
  on public.notices;
create policy cargoflow_public_active_notices
on public.notices
for select
using (
  deletion_status = 'active'
  and deleted_at is null
);

-- 기존 public policy 이름도 제거해서 중복 허용 경로를 없앱니다.
drop policy if exists "public can read active schedules"
  on public.shipping_schedules;
drop policy if exists "public can read active notices"
  on public.notices;

grant select on table public.shipping_schedules to anon, authenticated;
grant select on table public.notices to anon, authenticated;
