-- 040_export_auto_receipt_linkage.sql
-- Excel export가 새 영수번호를 자동 부여하고 DB에 저장할 수 있도록 service_role UPDATE 권한 추가.
grant update on table public.shipments to service_role;
