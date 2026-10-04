-- Evaluate scoped lookup IDs once, not once for every JSON record.
-- Preserve all policy selection and receipt/approval behavior.
CREATE OR REPLACE FUNCTION public.compute_shipment_special_note_scoped(p_route text, p_year integer, p_voyage text, p_name text, p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_route_key text := public.route_base_key_for_label(p_route);
  v_group text := '';
  v_discount numeric := 0;
  v_discount_notes text := '';
  v_discount_text text := '';
  v_delivery_type text := '';
  v_paid_by text := '';
  v_delivery_text text := '';
  v_share_text text := '';
  v_delivery_id bigint;
  v_discount_id bigint;
  v_policy jsonb:=public.lk_excel_effective_policy(v_route_key,p_year,p_voyage);
begin
  if public.lk_is_park_seongho(coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name)) then
    v_group := '대표 고정 할인';
    v_discount := 1;
  else
    v_discount_id:=public.lk_excel_discount_rule_id_scoped(v_route_key,p_year,p_voyage,p_name,p_phone);
    select coalesce(r.group_name,''),coalesce(r.discount_percent,0),coalesce(r.notes,'')
      into v_group,v_discount,v_discount_notes
    from jsonb_populate_recordset(null::public.customer_rate_overrides,v_policy->'discounts') r
    where r.id=v_discount_id;
  end if;

  v_delivery_id := public.lk_excel_delivery_profile_id_scoped(
    v_route_key,p_year,p_voyage,p_name,p_phone
  );
  if v_delivery_id is not null then
    select coalesce(d.delivery_type,''),coalesce(d.paid_by,'')
      into v_delivery_type,v_paid_by
    from jsonb_populate_recordset(null::public.local_delivery_profiles,v_policy->'deliveries') d
    where d.id=v_delivery_id;
  end if;

  select coalesce(s.content,'') into v_share_text
  from jsonb_populate_recordset(null::public.customer_statement_share_rules,v_policy->'shares') s
  where s.active=true and s.route_key=v_route_key
    and public.lk_excel_rule_rank(p_name,p_phone,s.customer_name,coalesce(nullif(s.phone_display,''),s.phone))<9999
  order by public.lk_excel_rule_rank(p_name,p_phone,s.customer_name,coalesce(nullif(s.phone_display,''),s.phone)),s.source_no desc,s.id desc
  limit 1;

  if coalesce(v_delivery_type,'')<>'' then
    if coalesce(v_share_text,'')='' then
      v_share_text := case
        when public.lk_delivery_is_prepaid(v_paid_by)
          then '한국 카톡 명세서 선공유 및 온라인 결재'
        else '카톡 명세서 선공유'
      end;
    end if;
    v_delivery_text :=
      case when v_delivery_type='city' then '시내배송' else '지방배송' end
      || case when public.lk_delivery_is_prepaid(v_paid_by)
              then '(선결제)' else '' end;
  end if;

  if coalesce(v_discount,0)>0 then
    v_discount_text :=
      case
        when btrim(coalesce(v_group,''))='' then '할인'
        when btrim(v_group) like '%할인%' then btrim(v_group)
        else btrim(v_group)||' 할인'
      end
      || ' ' || trim(to_char(v_discount*100,'FM999990.##')) || '% 적용';
  end if;

  return concat_ws(
    ' / ',
    nullif(btrim(v_share_text),''),
    nullif(btrim(v_discount_text),''),
    nullif(btrim(v_discount_notes),''),
    nullif(btrim(v_delivery_text),'')
  );
end;
$function$;

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
  v_special numeric := 0;
  v_regular numeric := 0;
  v_statement_mode text := 'separate';
  v_rules jsonb:=public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts';
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
    from jsonb_populate_recordset(null::public.customer_rate_overrides,v_rules) r
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
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,v_rules) r
    where r.id=(select public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone));

    v_qty := 0;
  end if;

  -- A bare namesake must not inherit the representative's old BASE row.
  if coalesce(v_rule.discount_percent,0)=1
     and public.lk_excel_name(v_rule.customer_name)='박성호'
     and not public.lk_is_park_seongho(p_name) then
    v_rule := null;
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,v_rules) r
    where r.id=(select public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone));
  end if;

  -- Identity-group membership must not suppress the same Excel name/phone
  -- rule used by automatic remarks when no group-linked override exists.
  if v_rule.id is null and v_gid is not null then
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,v_rules) r
    where r.id=(select public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone));
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
      'regular_discount_percent',1,
      'special_discount_percent',0,
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

  v_special := coalesce(v_rule.special_discount_percent,
    case when regexp_replace(coalesce(v_rule.group_name,''),'\s','','g')='특별할인'
      then coalesce(v_rule.discount_percent,0) else 0 end);
  v_regular := greatest(0,coalesce(v_rule.discount_percent,0)-v_special);
  v_effective := v_regular;

  if v_rule.bulk_threshold is not null
     and v_rule.bulk_discount_percent is not null
     and v_qty >= v_rule.bulk_threshold then
    if v_regular=0 and regexp_replace(coalesce(v_rule.group_name,''),'\s','','g')='특별할인' then
      v_special := v_rule.bulk_discount_percent;
    else
      v_effective := v_rule.bulk_discount_percent;
    end if;
  end if;

  v_regular := least(1,greatest(0,v_effective));
  v_special := least(greatest(0,v_special),1-v_regular);
  v_effective := v_regular + v_special;

  return jsonb_build_object(
    'id',v_rule.id,
    'customer_name',v_rule.customer_name,
    'company_name',v_rule.company_name,
    'group_name',v_rule.group_name,
    'rate_override',v_rule.rate_override,
    'discount_percent',v_effective,
    'regular_discount_percent',v_regular,
    'special_discount_percent',v_special,
    'base_discount_percent',coalesce(v_rule.discount_percent,0),
    'bulk_threshold',v_rule.bulk_threshold,
    'bulk_discount_percent',v_rule.bulk_discount_percent,
    'combined_quantity',v_qty,
    'customer_group_id',v_gid,
    'statement_mode',v_statement_mode
  );
end
$function$;
