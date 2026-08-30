-- Patch127
-- Edge Function(service_role)이 voyage_settlement_snapshots를 항상 조회할 수 있도록
-- 수동으로 적용했던 권한을 migration 파일로 고정합니다.
grant select on public.voyage_settlement_snapshots to service_role;
