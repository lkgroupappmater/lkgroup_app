-- Patch164 FIXED2 / 096
create or replace function public.compute_shipment_special_note(
  p_route text,
  p_name text,
  p_phone text
)
returns text
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_route_key text := public.route_base_key_for_label(p_route);
  v_group text := '';
  v_discount numeric := 0;
  v_delivery text := '';
  v_discount_text text := '';
begin
  if public.normalize_phone(p_phone) <> '' and public.normalize_person_name(p_name) <> '' then
    select coalesce(group_name,''), coalesce(discount_percent,0)
      into v_group, v_discount
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=v_route_key or r.route_key='all')
      and public.phone_matches(r.phone,p_phone)
      and (
        public.normalize_person_name(r.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(r.company_name,'')<>'' and public.normalize_person_name(r.company_name)=public.normalize_person_name(p_name))
      )
    order by case when r.route_key=v_route_key then 0 else 1 end, r.id
    limit 1;

    select case when d.delivery_type='city' then '시내배송' else '지방배송' end
      into v_delivery
    from public.local_delivery_profiles d
    where d.active=true
      and d.route_key=v_route_key
      and public.phone_matches(d.phone,p_phone)
      and (
        public.normalize_person_name(d.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(d.alternate_name,'')<>'' and public.normalize_person_name(d.alternate_name)=public.normalize_person_name(p_name))
        or (coalesce(d.company_name,'')<>'' and public.normalize_person_name(d.company_name)=public.normalize_person_name(p_name))
      )
    order by d.preferred desc, d.source_no nulls last, d.id
    limit 1;
  end if;

  if coalesce(v_discount,0)>0 then
    v_discount_text := concat(
      case when lower(v_group) like '%특별%' then '특별할인 ' else '할인 ' end,
      trim(to_char(v_discount*100,'FM999990.##')),
      '% 적용'
    );
  end if;

  return concat_ws(' / ', nullif(v_discount_text,''), nullif(v_delivery,''));
end
$$;

update public.shipments s
set special_note_auto=public.compute_shipment_special_note(
  s.route,s.consignee_name,s.consignee_phone
);
