-- Each imported row evaluates the shared delivery/discount rules. The default
-- authenticated 8s timeout is shorter than a measured 100-row rule evaluation.
-- Bound this one import RPC; do not relax timeouts for unrelated queries.
alter function public.manager_import_shipment_differences_bulk(jsonb)
  set statement_timeout = '45s';

create or replace function public.list_route_catalog_definitions()
returns table(route_key text, display_name text, status text, base_route_key text,
  file_prefix text, box_prefix text, receipt_prefix text, document_title text, remark text)
language sql security definer set search_path=public as $$
  select r.route_key,r.display_name,r.status,coalesce(r.base_route_key,''),
    r.file_prefix,r.box_prefix,r.receipt_prefix,r.document_title,r.remark
  from public.route_definitions r
  order by array_position(array[
    'kr_la_sea','kr_la_air','la_kr_air_exp','la_th_land','th_la_land',
    'la_vn_land','vn_la_land','la_ch_land','ch_la_land','la_kh_land','kh_la_land'
  ]::text[],r.route_key) nulls last, r.created_at,r.display_name;
$$;

create or replace function public.admin_route_definitions()
returns setof public.route_definitions
language plpgsql security definer set search_path=public as $$
begin
  if coalesce(public.current_role(),'') <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;
  return query select r.* from public.route_definitions r
  order by case r.status when 'active' then 1 when 'draft' then 2
    when 'deleted' then 3 else 4 end,
    array_position(array[
      'kr_la_sea','kr_la_air','la_kr_air_exp','la_th_land','th_la_land',
      'la_vn_land','vn_la_land','la_ch_land','ch_la_land','la_kh_land','kh_la_land'
    ]::text[],r.route_key) nulls last,r.created_at,r.display_name;
end;
$$;

notify pgrst, 'reload schema';
