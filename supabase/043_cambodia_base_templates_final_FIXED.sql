-- 043_cambodia_base_templates_final_FIXED.sql
-- Cambodia 양방향 BASE Excel 메타데이터 등록/갱신.
-- 실제 테이블 필수 컬럼 file_name 포함.

insert into public.shipment_excel_base_templates
  (route_key, route_label, file_name, storage_path)
values
  (
    'la_kh_land',
    '라오스->캄보디아 육로',
    'LA_KH_LAND_2026_V00_SHIPMENTS.xlsx',
    'base/la_kh_land/LA_KH_LAND_2026_V00_SHIPMENTS.xlsx'
  ),
  (
    'kh_la_land',
    '캄보디아->라오스 육로',
    'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx',
    'base/kh_la_land/KH_LA_LAND_2026_V00_SHIPMENTS.xlsx'
  )
on conflict (route_key) do update
set
  route_label = excluded.route_label,
  file_name = excluded.file_name,
  storage_path = excluded.storage_path;
