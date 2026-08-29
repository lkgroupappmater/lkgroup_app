-- 058_route_document_metadata.sql
-- 문서용 운송경로 타이틀/Remark를 DB 기준 데이터로 관리.
-- 회사명/주소/전화번호는 BASE 문서 자체의 고정정보로 유지하고 관리 UI 기본 편집대상에서 제외.

alter table public.route_definitions
  add column if not exists document_title text not null default '';

alter table public.route_definitions
  add column if not exists remark text not null default '';

-- 기존 11개 노선 문서 타이틀 초기값.
update public.route_definitions set document_title = case route_key
  when 'kr_la_sea' then 'Kor-Lao Sea'
  when 'kr_la_air' then 'Kor-Lao Air'
  when 'la_kr_air_exp' then 'Lao-Kor Air Exp'
  when 'la_th_land' then 'Lao-Thai Land'
  when 'th_la_land' then 'Thai-Lao Land'
  when 'la_vn_land' then 'Lao-Viet Land'
  when 'vn_la_land' then 'Viet-Lao Land'
  when 'la_ch_land' then 'Lao-China Land'
  when 'ch_la_land' then 'China-Lao Land'
  when 'la_kh_land' then 'Lao-Cambodia Land'
  when 'kh_la_land' then 'Cambodia-Lao Land'
  else coalesce(nullif(document_title,''), display_name)
end
where nullif(btrim(document_title),'') is null
   or route_key in (
      'kr_la_sea','kr_la_air','la_kr_air_exp','la_th_land','th_la_land',
      'la_vn_land','vn_la_land','la_ch_land','ch_la_land','la_kh_land','kh_la_land'
   );

update public.route_definitions
set document_title = display_name
where nullif(btrim(document_title),'') is null;

-- 앱 전체 동적 경로 메타데이터.
create or replace function public.list_route_catalog_definitions()
returns table(
  route_key text,
  display_name text,
  status text,
  base_route_key text,
  file_prefix text,
  box_prefix text,
  receipt_prefix text,
  document_title text,
  remark text
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
    r.document_title,
    r.remark
  from public.route_definitions r
  order by r.created_at, r.display_name
$$;

revoke all on function public.list_route_catalog_definitions() from public;
grant execute on function public.list_route_catalog_definitions()
  to anon, authenticated;

-- 기존 extension RPC는 호환을 위해 남기고, 문서 메타데이터 포함 overload 추가.
create or replace function public.admin_set_route_extension(
  p_route_key text,
  p_file_prefix text,
  p_document_title text,
  p_remark text,
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
    document_title = btrim(coalesce(p_document_title, '')),
    remark = coalesce(p_remark, ''),
    template_overrides = coalesce(p_template_overrides, '[]'::jsonb),
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key;

  insert into public.route_definition_audit(
    route_key, action, snapshot, changed_by
  )
  select
    p_route_key,
    'document_metadata_update',
    to_jsonb(r),
    auth.uid()
  from public.route_definitions r
  where r.route_key = p_route_key;
end
$$;

grant execute on function public.admin_set_route_extension(
  text,text,text,text,jsonb
) to authenticated;

grant select on table public.route_definitions to service_role;
