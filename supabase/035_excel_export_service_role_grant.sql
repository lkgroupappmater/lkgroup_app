-- 035_excel_export_service_role_grant.sql
-- export-shipment-excel Edge Function이 service_role로 템플릿 메타데이터를 조회할 수 있도록
-- 필요한 SELECT 권한만 추가합니다.

grant select on table public.shipment_excel_templates to service_role;
grant select on table public.shipment_excel_base_templates to service_role;
