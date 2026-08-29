-- 057_clone_route_base_service_role_grants.sql
-- clone-route-base Edge Function은 SUPABASE_SERVICE_ROLE_KEY로 public 테이블을 직접 조회/갱신합니다.
-- service_role은 RLS를 우회하지만 SQL GRANT 자체가 없으면 42501 permission denied가 발생할 수 있습니다.

grant usage on schema public to service_role;

grant select
on table public.route_definitions
to service_role;

grant select, insert, update
on table public.shipment_excel_base_templates
to service_role;

-- 향후 30일 purge / route 연계 서버 처리에서도 같은 테이블 접근이 필요하므로
-- 직접 연계된 운임/항차 템플릿 테이블 권한도 명시적으로 보장합니다.
grant select, delete
on table public.shipment_excel_templates
to service_role;

grant select, update, delete
on table public.freight_rate_tiers
to service_role;

grant select, delete
on table public.route_definition_audit
to service_role;
