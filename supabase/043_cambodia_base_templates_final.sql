-- 043_cambodia_base_templates_final.sql
-- Cambodia route BASE Excel metadata finalization.
-- Run after uploading the two files to the shipment-excel-templates bucket.

insert into public.shipment_excel_base_templates
  (route_key, route_label, storage_path, is_active)
values
  ('la_kh_land', '라오스->캄보디아 육로',
   'base/la_kh_land/LA_KH_LAND_2026_V00_SHIPMENTS.xlsx', true),
  ('kh_la_land', '캄보디아->라오스 육로',
   'base/kh_la_land/KH_LA_LAND_2026_V00_SHIPMENTS.xlsx', true)
on conflict (route_key) do update
set route_label = excluded.route_label,
    storage_path = excluded.storage_path,
    is_active = true,
    updated_at = now();
