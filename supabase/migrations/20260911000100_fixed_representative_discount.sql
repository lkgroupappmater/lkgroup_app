-- 206: Apply the representative fixed 100% rule to financial calculations.
CREATE OR REPLACE FUNCTION public.resolve_customer_discount_context(p_route_key text, p_year integer, p_voyage text, p_name text, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_gid bigint;
  v_qty integer := 0;
  v_rule public.customer_rate_overrides%rowtype;
  v_effective numeric := 0;
  v_statement_mode text := 'separate';
begin
  if public.lk_excel_customer_key(p_name,p_phone) in ('','XX') then
    return '{}'::jsonb;
  end if;

  p_name := coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name);
  v_gid := public.resolve_customer_identity_group(p_name,p_phone);

  if v_gid is not null then
    select coalesce(sum(greatest(coalesce(s.quantity,1),1)),0)::integer
      into v_qty
    from public.shipments s
    where s.customer_identity_group_id=v_gid
      and public.route_base_key_for_label(s.route)=p_route_key
      and (p_year is null or s.shipment_year=p_year)
      and (
        coalesce(btrim(p_voyage),'')=''
        or lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')
           = lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0')
      )
      and s.deletion_requested_at is null;

    select *
      into v_rule
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=p_route_key or r.route_key='all')
      and (
        r.customer_group_id=v_gid
        or (
          public.phone_matches(r.phone,p_phone)
          and (
            public.normalize_person_name(r.customer_name)
                = public.normalize_person_name(p_name)
            or public.normalize_person_name(r.company_name)
                = public.normalize_person_name(p_name)
          )
        )
      )
    order by
      case when r.route_key=p_route_key then 0 else 1 end,
      case when r.customer_group_id=v_gid then 0 else 1 end,
      r.id
    limit 1;

    select coalesce(statement_mode,'separate')
      into v_statement_mode
    from public.customer_identity_groups
    where id=v_gid;
  else
    select * into v_rule from public.customer_rate_overrides r
    where r.id=public.lk_excel_discount_rule_id(p_route_key,p_name,p_phone);

    v_qty := 0;
  end if;

  -- Identity-group membership must not suppress the same Excel name/phone
  -- rule used by automatic remarks when no group-linked override exists.
  if v_rule.id is null and v_gid is not null then
    select * into v_rule from public.customer_rate_overrides r
    where r.id=public.lk_excel_discount_rule_id(p_route_key,p_name,p_phone);
  end if;

  -- The fixed representative benefit must match the fixed zone/remark rule,
  -- including honorific names and verified recovered recipients.
  if public.lk_is_park_seongho(p_name) then
    return jsonb_build_object(
      'id',v_rule.id,
      'customer_name',p_name,
      'company_name',v_rule.company_name,
      'group_name','대표 고정 할인',
      'rate_override',v_rule.rate_override,
      'discount_percent',1,
      'base_discount_percent',1,
      'bulk_threshold',null,
      'bulk_discount_percent',null,
      'combined_quantity',v_qty,
      'customer_group_id',v_gid,
      'statement_mode',v_statement_mode
    );
  end if;

  if v_rule.id is null then
    return jsonb_build_object(
      'customer_group_id',v_gid,
      'combined_quantity',v_qty,
      'statement_mode',v_statement_mode
    );
  end if;

  v_effective := coalesce(v_rule.discount_percent,0);

  if v_rule.bulk_threshold is not null
     and v_rule.bulk_discount_percent is not null
     and v_qty >= v_rule.bulk_threshold then
    v_effective := v_rule.bulk_discount_percent;
  end if;

  return jsonb_build_object(
    'id',v_rule.id,
    'customer_name',v_rule.customer_name,
    'company_name',v_rule.company_name,
    'group_name',v_rule.group_name,
    'rate_override',v_rule.rate_override,
    'discount_percent',v_effective,
    'base_discount_percent',coalesce(v_rule.discount_percent,0),
    'bulk_threshold',v_rule.bulk_threshold,
    'bulk_discount_percent',v_rule.bulk_discount_percent,
    'combined_quantity',v_qty,
    'customer_group_id',v_gid,
    'statement_mode',v_statement_mode
  );
end
$function$

