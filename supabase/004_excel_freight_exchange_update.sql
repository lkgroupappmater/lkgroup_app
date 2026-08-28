-- 004_excel_freight_exchange_update.sql
-- 기존 001/002/003 실행 후 전체 실행.
-- 요청 범위: Excel 원장 연동, 운송구간별 운임정책, 특별고객 override, 환율, 조회 RLS.

-- 1) shipments: 현재 Excel "물품 입고 내역" 구조 보강
alter table public.shipments add column if not exists shipment_year integer;
alter table public.shipments add column if not exists voyage text not null default '';
alter table public.shipments add column if not exists import_key text;
alter table public.shipments add column if not exists sender_name text not null default '';
alter table public.shipments add column if not exists contents text not null default '';
alter table public.shipments add column if not exists package_type text not null default '';
alter table public.shipments add column if not exists receipt_number text not null default '';
alter table public.shipments add column if not exists unloading_zone text not null default '';

-- 송장번호가 없는 용달/퀵 직접 입고 허용
alter table public.shipments alter column invoice_number set default '';

create unique index if not exists shipments_import_key_uidx
  on public.shipments(import_key)
  where import_key is not null and import_key <> '';

create index if not exists shipments_route_year_voyage_idx
  on public.shipments(route, shipment_year, voyage);
create index if not exists shipments_box_idx on public.shipments(box_number);
create index if not exists shipments_receipt_idx on public.shipments(receipt_number);

-- 2) 환율: 총괄 관리자 입력값 + 고정 가산값
create table if not exists public.exchange_rate_settings (
  id integer primary key default 1 check (id = 1),
  base_kip numeric not null default 0,
  base_thb numeric not null default 0,
  base_krw numeric not null default 0,
  kip_adjustment numeric not null default 2000,
  thb_adjustment numeric not null default 1.5,
  krw_adjustment numeric not null default 40,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

insert into public.exchange_rate_settings
  (id, base_kip, base_thb, base_krw, kip_adjustment, thb_adjustment, krw_adjustment)
values (1, 0, 0, 0, 2000, 1.5, 40)
on conflict (id) do nothing;

-- 3) 운임 정책
create table if not exists public.freight_rate_tiers (
  id bigint generated always as identity primary key,
  route_key text not null,
  min_weight_kg numeric not null default 0,
  rate_per_kg numeric not null,
  minimum_charge numeric not null default 0,
  volumetric_factor numeric not null default 0.00022,
  source_note text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(route_key, min_weight_kg)
);

-- 공유 Excel 2026 V00 기준.
-- 이후 총괄 관리용 운임 편집 화면을 붙일 수 있도록 DB 테이블로 분리함.
insert into public.freight_rate_tiers
(route_key,min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note)
values
-- Korea -> Laos
('kr_la_sea',0,1.5,1.5,0.00022,'KR_LA_SEA_2026_V00_SHIPMENTS.xlsx'),
('kr_la_air',0,14,14,0.00022,'KR_LA_AIR_2026_V00_SHIPMENTS.xlsx'),

-- China -> Laos
('ch_la_land',0,1.2,1.2,0.00022,'CH_LA_LAND_2026_V00_SHIPMENTS.xlsx'),

-- Laos -> Korea Air Express
('la_kr_air_exp',0,18,18,0.00022,'0~1kg'),
('la_kr_air_exp',2,16,18,0.00022,'2~5kg'),
('la_kr_air_exp',6,14,18,0.00022,'6~9kg'),
('la_kr_air_exp',10,12,18,0.00022,'10~14kg'),
('la_kr_air_exp',15,10,18,0.00022,'15kg+'),

-- Thailand -> Laos
('th_la_land',0,4,4,0.00022,'0~1kg'),
('th_la_land',2,2.5,4,0.00022,'2~5kg'),
('th_la_land',6,1.5,4,0.00022,'6~9kg'),
('th_la_land',10,1.25,4,0.00022,'10~14kg'),
('th_la_land',15,1.15,4,0.00022,'15~17kg'),
('th_la_land',18,1.13,4,0.00022,'18~20kg'),
('th_la_land',21,1.1,4,0.00022,'21kg+'),

-- Laos -> Thailand
('la_th_land',0,12.4,12.4,0.00022,'0~1kg'),
('la_th_land',2,5.3,12.4,0.00022,'2~5kg'),
('la_th_land',6,3.6,12.4,0.00022,'6~9kg'),
('la_th_land',10,3.6,12.4,0.00022,'10~14kg'),
('la_th_land',15,3.3,12.4,0.00022,'15~17kg'),
('la_th_land',18,3.4,12.4,0.00022,'18~20kg'),
('la_th_land',21,3.5,12.4,0.00022,'21~24kg'),
('la_th_land',25,3.7,12.4,0.00022,'25~29kg'),
('la_th_land',30,3.8,12.4,0.00022,'30~34kg'),
('la_th_land',35,3.9,12.4,0.00022,'35~39kg'),
('la_th_land',40,4,12.4,0.00022,'40~44kg'),
('la_th_land',45,4,12.4,0.00022,'45kg+'),

-- Laos <-> Vietnam (현재 공유 파일의 적용운임 동일)
('la_vn_land',0,13.6,13.6,0.00022,'~1kg'),
('la_vn_land',2,8.7,13.6,0.00022,'~2kg'),
('la_vn_land',3,7.1,13.6,0.00022,'~3kg'),
('la_vn_land',4,6.3,13.6,0.00022,'4~5kg'),
('la_vn_land',6,5.4,13.6,0.00022,'6~9kg'),
('la_vn_land',10,4.8,13.6,0.00022,'10~14kg'),
('la_vn_land',15,4.5,13.6,0.00022,'15~19kg'),
('la_vn_land',20,4.3,13.6,0.00022,'20kg+'),
('vn_la_land',0,13.6,13.6,0.00022,'~1kg'),
('vn_la_land',2,8.7,13.6,0.00022,'~2kg'),
('vn_la_land',3,7.1,13.6,0.00022,'~3kg'),
('vn_la_land',4,6.3,13.6,0.00022,'4~5kg'),
('vn_la_land',6,5.4,13.6,0.00022,'6~9kg'),
('vn_la_land',10,4.8,13.6,0.00022,'10~14kg'),
('vn_la_land',15,4.5,13.6,0.00022,'15~19kg'),
('vn_la_land',20,4.3,13.6,0.00022,'20kg+'),

-- Laos -> Cambodia
('la_kh_land',0,22.5,22.5,0.00022,'~1kg'),
('la_kh_land',2,14.3,22.5,0.00022,'~2kg'),
('la_kh_land',3,11.5,22.5,0.00022,'~3kg'),
('la_kh_land',4,10.2,22.5,0.00022,'4~5kg'),
('la_kh_land',6,8.8,22.5,0.00022,'6~9kg'),
('la_kh_land',10,7.7,22.5,0.00022,'10~14kg'),
('la_kh_land',15,7.1,22.5,0.00022,'15~19kg'),
('la_kh_land',20,6.9,22.5,0.00022,'20kg+'),

-- Laos -> China
('la_ch_land',0,13.4,13.4,0.00022,'0~1kg'),
('la_ch_land',2,10.6,13.4,0.00022,'2~4kg'),
('la_ch_land',5,9,13.4,0.00022,'5~8kg'),
('la_ch_land',9,8.5,13.4,0.00022,'9~12kg'),
('la_ch_land',13,8.3,13.4,0.00022,'13~16kg'),
('la_ch_land',17,8.2,13.4,0.00022,'17~19kg'),
('la_ch_land',20,8.1,13.4,0.00022,'20kg+')
on conflict (route_key,min_weight_kg) do update set
  rate_per_kg = excluded.rate_per_kg,
  minimum_charge = excluded.minimum_charge,
  volumetric_factor = excluded.volumetric_factor,
  source_note = excluded.source_note,
  updated_at = now();

-- 4) 특별 고객별 적용운임/할인/Zone override
create table if not exists public.customer_rate_overrides (
  id bigint generated always as identity primary key,
  customer_name text not null,
  phone text not null default '',
  route_key text not null default 'all',
  rate_override numeric,
  discount_percent numeric not null default 0,
  zone_override text not null default '',
  notes text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(customer_name, route_key)
);

-- 5) Zone 계산 helper
create or replace function public.default_unloading_zone(
  p_route text,
  p_box_count integer,
  p_override text default ''
)
returns text
language sql
immutable
as $$
  select case
    when nullif(btrim(p_override), '') is not null then btrim(p_override)
    when p_route = '한국->라오스 항공' then '102'
    when coalesce(p_box_count,0) >= 20 then 'F'
    when coalesce(p_box_count,0) >= 10 then 'C'
    when coalesce(p_box_count,0) >= 5 then 'B'
    else 'A'
  end
$$;

-- 6) 일반 회원은 가입한 이름+연락처와 일치하는 화물만 조회.
create or replace function public.normalize_person_name(value text)
returns text language sql immutable
as $$ select lower(regexp_replace(btrim(coalesce(value,'')), '\s+', ' ', 'g')) $$;

create or replace function public.normalize_phone(value text)
returns text language sql immutable
as $$ select regexp_replace(coalesce(value,''), '[^0-9]', '', 'g') $$;

create or replace function public.current_profile_name()
returns text language sql stable security definer set search_path=public
as $$ select name from public.profiles where id=auth.uid() $$;

create or replace function public.current_profile_phone()
returns text language sql stable security definer set search_path=public
as $$ select phone from public.profiles where id=auth.uid() $$;

drop policy if exists shipments_read_scoped on public.shipments;
create policy shipments_read_scoped on public.shipments for select using (
  public.current_role() in ('admin','staff','partner')
  or (
    public.current_role() = 'member'
    and public.normalize_person_name(consignee_name)
        = public.normalize_person_name(public.current_profile_name())
    and public.normalize_phone(consignee_phone)
        = public.normalize_phone(public.current_profile_phone())
  )
);

-- 7) RLS: 환율/운임은 승인 회원 조회, 총괄 admin 수정.
alter table public.exchange_rate_settings enable row level security;
alter table public.freight_rate_tiers enable row level security;
alter table public.customer_rate_overrides enable row level security;

drop policy if exists exchange_read_authenticated on public.exchange_rate_settings;
drop policy if exists exchange_admin_write on public.exchange_rate_settings;
create policy exchange_read_authenticated on public.exchange_rate_settings
  for select using (auth.uid() is not null and public.is_approved_user());
create policy exchange_admin_write on public.exchange_rate_settings
  for all using (public.current_role()='admin')
  with check (public.current_role()='admin');

drop policy if exists freight_rates_read_authenticated on public.freight_rate_tiers;
drop policy if exists freight_rates_admin_write on public.freight_rate_tiers;
create policy freight_rates_read_authenticated on public.freight_rate_tiers
  for select using (auth.uid() is not null and public.is_approved_user());
create policy freight_rates_admin_write on public.freight_rate_tiers
  for all using (public.current_role()='admin')
  with check (public.current_role()='admin');

drop policy if exists customer_rules_read_authenticated on public.customer_rate_overrides;
drop policy if exists customer_rules_staff_admin_write on public.customer_rate_overrides;
create policy customer_rules_read_authenticated on public.customer_rate_overrides
  for select using (auth.uid() is not null and public.is_approved_user());
create policy customer_rules_staff_admin_write on public.customer_rate_overrides
  for all using (public.current_role() in ('admin','staff'))
  with check (public.current_role() in ('admin','staff'));

comment on table public.freight_rate_tiers is
'공유 Excel 거래명세서의 실제/용적중량 비교 운임표. volumetric_factor 기본 0.00022.';
comment on table public.exchange_rate_settings is
'총괄 관리자 수기 입력 현찰 살 때 기준환율. 적용환율은 KIP +2000, THB +1.5, KRW +40.';
