-- 044_kh_la_land_freight_rate.sql
-- 신규 KH -> LA BASE 실제 운임표를 DB 공통 운임 정책에도 추가.
-- 기존 다른 노선 운임은 건드리지 않습니다.

insert into public.freight_rate_tiers
(route_key,min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note)
values
('kh_la_land',0,22.5,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / ~1kg'),
('kh_la_land',2,14.3,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / ~2kg'),
('kh_la_land',3,11.5,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / ~3kg'),
('kh_la_land',4,10.2,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / 4~5kg'),
('kh_la_land',6,8.8,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / 6~9kg'),
('kh_la_land',10,7.7,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / 10~14kg'),
('kh_la_land',15,7.1,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / 15~19kg'),
('kh_la_land',20,6.9,22.5,0.00022,'KH_LA_LAND_2026_V00_SHIPMENTS.xlsx / 20kg+')
on conflict (route_key,min_weight_kg) do update set
  rate_per_kg = excluded.rate_per_kg,
  minimum_charge = excluded.minimum_charge,
  volumetric_factor = excluded.volumetric_factor,
  source_note = excluded.source_note,
  active = true,
  updated_at = now();
