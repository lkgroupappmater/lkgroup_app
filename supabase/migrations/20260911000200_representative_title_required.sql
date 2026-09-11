-- Require an explicit representative title; protect the namesake customer.
CREATE OR REPLACE FUNCTION public.lk_is_park_seongho(p_name text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
 select regexp_replace(coalesce(p_name,''),'[[:space:]]','','g')
   in ('박성호대표','박성호대표님');
$function$;

CREATE OR REPLACE FUNCTION public.lk_excel_discount_rule_id(p_route_key text, p_name text, p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select r.id from public.customer_rate_overrides r
 where r.active and r.route_key in (p_route_key,'all')
  and public.lk_excel_rule_rank(p_name,p_phone,r.customer_name||coalesce(r.company_name,''),r.phone)<9999
  and not (
    coalesce(r.discount_percent,0)=1
    and public.lk_excel_name(r.customer_name)='박성호'
    and not public.lk_is_park_seongho(coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name))
  )
 order by (r.route_key=p_route_key) desc,
 public.lk_excel_rule_rank(p_name,p_phone,r.customer_name||coalesce(r.company_name,''),r.phone),
 r.excel_source_row desc nulls last,r.id desc limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.lk_excel_receipt_plan(p_route text, p_year integer, p_voyage text)
 RETURNS TABLE(shipment_id bigint, identity_key text, old_receipt text, new_receipt text, priority integer, is_unknown boolean, is_park boolean, locked boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 with rd as (
   select * from public.route_definitions where route_key=btrim(p_route) or display_name=btrim(p_route)
   order by (display_name=btrim(p_route)) desc limit 1
 ), source_rows as materialized (
   select s.* from public.shipments s cross join rd
   where s.route=rd.display_name and s.shipment_year=p_year
     and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=lpad(regexp_replace(p_voyage,'[^0-9]','','g'),2,'0')
     and s.deleted_at is null and s.deletion_requested_at is null
 ), customers as materialized (
   select distinct consignee_name,consignee_phone from source_rows
 ), profiles as materialized (
   select c.*,public.lk_excel_customer_key(c.consignee_name,c.consignee_phone) k,
     public.lk_excel_delivery_profile_id(rd.route_key,c.consignee_name,c.consignee_phone) delivery_id
   from customers c cross join rd
 ), rows as materialized (
   select s.*,p.k,public.lk_is_park_seongho(s.consignee_name)
     and left(p.k,2)<>'R|' park,d.delivery_type
   from source_rows s join profiles p on p.consignee_name is not distinct from s.consignee_name
     and p.consignee_phone is not distinct from s.consignee_phone
   left join public.local_delivery_profiles d on d.id=p.delivery_id
 ), keyed as (
   select *,case when k='XX' then 'XX' when park then '__PARK__' else k end ik,
     case when left(k,2)='R|' then 6 when delivery_type='province' then 1 when delivery_type='city' then 2 else 3 end pri
   from rows
 ), groups as (
   select ik, (array_agg(pri order by box_number collate "C",id))[1] pri,
     min(nullif(btrim(receipt_number),'')) filter(where data_locked) fixed_receipt
   from keyed where k not in ('','XX') and not park group by ik
 ), reserved as (
   select distinct nullif(regexp_replace(receipt_number,'[^0-9]','','g'),'')::integer n from keyed
   where data_locked and coalesce(receipt_number,'') ~ '[0-9]+$'
   union select 100
 ), ordered as (
   select *,row_number() over(order by pri,public.lk_excel_sort_key(ik) collate "C",ik collate "C") seq
   from groups where fixed_receipt is null
 ), slots as (
   select n,row_number() over(order by n) seq from generate_series(1,
     (select count(*)::integer from groups)+(select count(*)::integer from reserved)+1) available(n)
   where not exists(select 1 from reserved r where r.n=available.n)
 ), assignments as (
   select o.ik,s.n from ordered o join slots s using(seq)
 )
 select k.id,k.ik,btrim(coalesce(k.receipt_number,'')),
   case when coalesce(k.data_locked,false) then k.receipt_number
     when k.k='' then ''
     else coalesce(g.fixed_receipt,btrim(rd.receipt_prefix)||case when rd.route_key in ('kr_la_sea','kr_la_air') then ' ' else '' end||
       case when k.k='XX' then 'XX' when k.park then '100' else
        case when a.n<10 then '0' else '' end||a.n::text end) end,
   k.pri,k.k='XX',k.park,coalesce(k.data_locked,false)
 from keyed k cross join rd left join groups g on g.ik=k.ik left join assignments a on a.ik=k.ik;
$function$;

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

  -- A bare namesake must not inherit the representative's old BASE row.
  if coalesce(v_rule.discount_percent,0)=1
     and public.lk_excel_name(v_rule.customer_name)='박성호'
     and not public.lk_is_park_seongho(p_name) then
    v_rule := null;
    select * into v_rule from public.customer_rate_overrides r
    where r.id=public.lk_excel_discount_rule_id(p_route_key,p_name,p_phone);
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
$function$;


