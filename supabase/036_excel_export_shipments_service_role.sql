-- 036_excel_export_shipments_service_role.sql
-- export-shipment-excel Edge Function(service_role)이 화물 데이터를 조회할 수 있도록
-- shipments 테이블 SELECT 권한만 추가합니다.

grant select on table public.shipments to service_role;
