-- 032_excel_base_template_registry.sql
-- 운송 경로별 기본 Excel 폼 + 항차별 변경 폼 이중 구조.
-- 기존 shipment_excel_templates는 항차별 override 용도로 그대로 유지합니다.

create table if not exists public.shipment_excel_base_templates (
  route_key text primary key,
  route_label text not null,
  file_name text not null,
  storage_path text not null,
  active boolean not null default true,
  updated_by uuid references auth.users(id) default auth.uid(),
  updated_at timestamptz not null default now()
);

alter table public.shipment_excel_base_templates enable row level security;

drop policy if exists "excel base templates managers read" on public.shipment_excel_base_templates;
create policy "excel base templates managers read"
on public.shipment_excel_base_templates for select
using (public.current_role() in ('admin','staff','partner'));

drop policy if exists "excel base templates managers insert" on public.shipment_excel_base_templates;
create policy "excel base templates managers insert"
on public.shipment_excel_base_templates for insert
with check (public.current_role() in ('admin','staff','partner'));

drop policy if exists "excel base templates managers update" on public.shipment_excel_base_templates;
create policy "excel base templates managers update"
on public.shipment_excel_base_templates for update
using (public.current_role() in ('admin','staff','partner'))
with check (public.current_role() in ('admin','staff','partner'));

grant select, insert, update on public.shipment_excel_base_templates to authenticated;

-- 아래 경로로 기본 폼을 Storage에 1회 업로드한 뒤 메타데이터를 등록합니다.
insert into public.shipment_excel_base_templates
(route_key, route_label, file_name, storage_path, active)
values
('kr_la_sea','한국->라오스 해상','KR_LA_SEA_2026_V00_SHIPMENTS.xlsx','base/kr_la_sea/KR_LA_SEA_2026_V00_SHIPMENTS.xlsx',true),
('kr_la_air','한국->라오스 항공','KR_LA_AIR_2026_V00_SHIPMENTS.xlsx','base/kr_la_air/KR_LA_AIR_2026_V00_SHIPMENTS.xlsx',true),
('la_kr_air_exp','라오스->한국 항공 특송','LA_KR_AIR_EXP_2026_V00_SHIPMENTS.xlsx','base/la_kr_air_exp/LA_KR_AIR_EXP_2026_V00_SHIPMENTS.xlsx',true),
('la_th_land','라오스->태국 육로','LA_TH_LAND_2026_V00_SHIPMENTS.xlsx','base/la_th_land/LA_TH_LAND_2026_V00_SHIPMENTS.xlsx',true),
('th_la_land','태국->라오스 육로','TH_LA_LAND_2026_V00_SHIPMENTS.xlsx','base/th_la_land/TH_LA_LAND_2026_V00_SHIPMENTS.xlsx',true),
('la_vn_land','라오스->베트남 육로','LA_VN_LAND_2026_V00_SHIPMENTS.xlsx','base/la_vn_land/LA_VN_LAND_2026_V00_SHIPMENTS.xlsx',true),
('vn_la_land','베트남->라오스 육로','VN_LA_LAND_2026_V00_SHIPMENTS.xlsx','base/vn_la_land/VN_LA_LAND_2026_V00_SHIPMENTS.xlsx',true),
('la_ch_land','라오스->중국 육로','LA_CH_LAND_2026_V00_SHIPMENTS.xlsx','base/la_ch_land/LA_CH_LAND_2026_V00_SHIPMENTS.xlsx',true),
('ch_la_land','중국->라오스 육로','CH_LA_LAND_2026_V00_SHIPMENTS.xlsx','base/ch_la_land/CH_LA_LAND_2026_V00_SHIPMENTS.xlsx',true),
('la_kh_land','라오스->캄보디아 육로','LA_KH_LAND_2026_V00_SHIPMENTS.xlsx','base/la_kh_land/LA_KH_LAND_2026_V00_SHIPMENTS.xlsx',true)
on conflict (route_key) do update set
  route_label = excluded.route_label,
  file_name = excluded.file_name,
  storage_path = excluded.storage_path,
  active = excluded.active,
  updated_at = now();

comment on table public.shipment_excel_base_templates is
'운송 경로별 기본 Excel 폼. export는 항차별 shipment_excel_templates가 있으면 우선 사용하고 없으면 이 기본 폼을 사용.';
