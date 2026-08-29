-- 051_dynamic_route_base_automation.sql
-- 중앙 운임/신규 경로를 앱 전체에서 동적으로 사용하기 위한 보강.

alter table public.route_definitions
  add column if not exists file_prefix text not null default '';

alter table public.route_definitions
  add column if not exists template_overrides jsonb not null default '[]'::jsonb;

update public.route_definitions set file_prefix = case route_key
  when 'kr_la_sea' then 'KR_LA_SEA'
  when 'kr_la_air' then 'KR_LA_AIR'
  when 'la_kr_air_exp' then 'LA_KR_AIR_EXP'
  when 'la_th_land' then 'LA_TH_LAND'
  when 'th_la_land' then 'TH_LA_LAND'
  when 'la_vn_land' then 'LA_VN_LAND'
  when 'vn_la_land' then 'VN_LA_LAND'
  when 'la_ch_land' then 'LA_CH_LAND'
  when 'ch_la_land' then 'CH_LA_LAND'
  when 'la_kh_land' then 'LA_KH_LAND'
  when 'kh_la_land' then 'KH_LA_LAND'
  else file_prefix
end
where nullif(btrim(file_prefix), '') is null;

update public.route_definitions
set receipt_prefix = 'LKLCB'
where route_key = 'la_kh_land';

update public.route_definitions
set receipt_prefix = 'LKCBL'
where route_key = 'kh_la_land';

create or replace function public.list_active_route_definitions()
returns table(
  route_key text,
  display_name text,
  status text,
  base_route_key text,
  file_prefix text,
  box_prefix text,
  receipt_prefix text,
  volumetric_factor numeric,
  minimum_charge numeric
)
language sql
security definer
set search_path = public
as $$
  select
    r.route_key,
    r.display_name,
    r.status,
    coalesce(r.base_route_key, ''),
    r.file_prefix,
    r.box_prefix,
    r.receipt_prefix,
    r.volumetric_factor,
    r.minimum_charge
  from public.route_definitions r
  where r.status = 'active'
  order by r.created_at, r.display_name
$$;

revoke all on function public.list_active_route_definitions() from public;
grant execute on function public.list_active_route_definitions()
  to anon, authenticated;

create or replace function public.admin_set_route_extension(
  p_route_key text,
  p_file_prefix text,
  p_template_overrides jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  if not exists(
    select 1 from public.route_definitions where route_key = p_route_key
  ) then
    raise exception '운송 경로를 찾을 수 없습니다.';
  end if;

  update public.route_definitions
  set
    file_prefix = upper(regexp_replace(
      coalesce(nullif(btrim(p_file_prefix), ''), p_route_key),
      '[^A-Za-z0-9]+',
      '_',
      'g'
    )),
    template_overrides = coalesce(p_template_overrides, '[]'::jsonb),
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key;

  insert into public.route_definition_audit(
    route_key, action, snapshot, changed_by
  )
  select
    p_route_key,
    'extension_update',
    to_jsonb(r),
    auth.uid()
  from public.route_definitions r
  where r.route_key = p_route_key;
end
$$;

grant execute on function public.admin_set_route_extension(
  text, text, jsonb
) to authenticated;

-- 기존 SQL050과 동일 signature를 유지하되 신규 key는 안전한 ASCII key로 생성.
create or replace function public.admin_create_route_draft(
 p_label text,
 p_base_route_key text,
 p_company_name text,
 p_phone text,
 p_address text,
 p_box_prefix text,
 p_receipt_prefix text,
 p_volumetric_factor numeric,
 p_minimum_charge numeric,
 p_tiers jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  k text;
  t jsonb;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  if not exists(
    select 1 from public.route_definitions
    where route_key = p_base_route_key and status = 'active'
  ) then
    raise exception '기반 BASE 운송 경로를 찾을 수 없습니다.';
  end if;

  k := 'route_' || substr(md5(
    coalesce(p_label, '') || clock_timestamp()::text || auth.uid()::text
  ), 1, 12);

  insert into public.route_definitions(
    route_key, display_name, status, base_route_key,
    company_name, phone, address,
    box_prefix, receipt_prefix,
    volumetric_factor, minimum_charge,
    created_by, updated_by
  )
  values(
    k, btrim(p_label), 'draft', p_base_route_key,
    coalesce(p_company_name, ''), coalesce(p_phone, ''),
    coalesce(p_address, ''), coalesce(p_box_prefix, ''),
    coalesce(p_receipt_prefix, ''),
    coalesce(p_volumetric_factor, 0.00022),
    coalesce(p_minimum_charge, 0),
    auth.uid(), auth.uid()
  );

  for t in select * from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb))
  loop
    insert into public.freight_rate_tiers(
      route_key, min_weight_kg, rate_per_kg,
      minimum_charge, volumetric_factor,
      source_note, active
    )
    values(
      k,
      (t->>'min_weight_kg')::numeric,
      (t->>'rate_per_kg')::numeric,
      coalesce(p_minimum_charge, 0),
      coalesce(p_volumetric_factor, 0.00022),
      '신규 경로 draft',
      false
    )
    on conflict(route_key, min_weight_kg) do update set
      rate_per_kg = excluded.rate_per_kg,
      minimum_charge = excluded.minimum_charge,
      volumetric_factor = excluded.volumetric_factor,
      source_note = excluded.source_note,
      active = false,
      updated_at = now();
  end loop;

  return k;
end
$$;

grant execute on function public.admin_create_route_draft(
  text,text,text,text,text,text,text,numeric,numeric,jsonb
) to authenticated;
