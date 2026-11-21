-- Discounts only: complete phone tokens and ordered member aliases.
alter table public.customer_rate_overrides add column if not exists phone_display text not null default '';

create or replace function public.lk_discount_phone_tokens(value text)
returns text[] language plpgsql immutable set search_path='' as $$
declare raw text:=replace(replace(replace(replace(coalesce(value,''),E'\\r\\n',chr(10)),E'\\n',chr(10)),E'\\r',chr(10)),'／','/'); digits text; token text; result text[]:=array[]::text[];
begin
 digits:=regexp_replace(raw,'[^0-9]','','g');
 if raw !~ E'[/;|,\\r\\n]' and length(digits)>15 and digits ~ '^(0(20|10)[0-9]{8})+$' then
   select array_agg(m[1]) into result from regexp_matches(digits,'(0(20|10)[0-9]{8})','g') m;
   return result;
 end if;
 if btrim(raw)='' then return result; end if;
 foreach token in array regexp_split_to_array(raw,E'[/;|,\\r\\n]+') loop
   digits:=regexp_replace(token,'[^0-9]','','g');
   digits:=case when digits ~ '^00856[0-9]{8,10}$' then '0'||substr(digits,6)
     when digits ~ '^856[0-9]{8,10}$' then '0'||substr(digits,4)
     when digits ~ '^0082[0-9]{8,11}$' then '0'||substr(digits,5)
     when digits ~ '^82[0-9]{8,11}$' then '0'||substr(digits,3) else digits end;
   result:=array_append(result,case when digits ~ '^[0-9]{8,15}$' then digits else '' end);
 end loop;
 return result;
end $$;

create or replace function public.lk_discount_name_parts(value text)
returns text[] language sql immutable set search_path='' as $$
 select coalesce(array_agg(n) filter(where n<>''),array[]::text[]) from (
 select public.lk_excel_name(t) n from regexp_split_to_table(
 replace(replace(replace(replace(coalesce(value,''),E'\\r\\n',chr(10)),E'\\n',chr(10)),E'\\r',chr(10)),'／','/'),E'[/;|,\\r\\n()]+') t) x;
$$;

create or replace function public.lk_discount_rule_rank(p_name text,p_phone text,r_name text,r_company text,r_phone text)
returns integer language plpgsql immutable set search_path='' as $$
declare names text[]; phones text[]; registered text[]; members text[]; groups text[]; eligible text[]; i integer; result integer:=9999; recovered text;
begin
 if public.lk_excel_customer_key(p_name,p_phone) in ('','XX') then return 9999; end if;
 recovered:=coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name);
 names:=public.lk_discount_name_parts(recovered); phones:=public.lk_discount_phone_tokens(p_phone);
 if cardinality(names)=0 or cardinality(phones)=0 then return 9999; end if;
 registered:=public.lk_discount_phone_tokens(r_phone);members:=public.lk_discount_name_parts(r_name);
 select coalesce(array_agg(t) filter(where cardinality(public.lk_discount_name_parts(t))>0),array[]::text[]) into groups
 from regexp_split_to_table(replace(replace(replace(replace(coalesce(r_name,''),E'\\r\\n',chr(10)),E'\\n',chr(10)),E'\\r',chr(10)),'／','/'),E'[/;|,\\r\\n]+') t;
 if cardinality(groups)<>cardinality(registered) and cardinality(members)=cardinality(registered) then groups:=members; end if;
 for i in 1..cardinality(registered) loop
  if registered[i]='' or not registered[i]=any(phones) then continue; end if;
  if public.lk_discount_name_parts(r_company)&&names then result:=least(result,1); end if;
  eligible:=case when cardinality(groups)=1 or cardinality(registered)=1 then members
    when cardinality(groups)=cardinality(registered) then public.lk_discount_name_parts(groups[i]) else array[]::text[] end;
  if eligible&&names then return 0; end if;
 end loop;
 return result;
end $$;


CREATE OR REPLACE FUNCTION public.lk_excel_discount_rule_id(p_route_key text, p_name text, p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select r.id from public.customer_rate_overrides r
 where r.active and r.route_key in (p_route_key,'all')
  and public.lk_discount_rule_rank(p_name,p_phone,r.customer_name,r.company_name,coalesce(nullif(r.phone_display,''),r.phone))<9999
  and not (
    coalesce(r.discount_percent,0)=1
    and public.lk_excel_name(r.customer_name)='박성호'
    and not public.lk_is_park_seongho(coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name))
  )
 order by (r.route_key=p_route_key) desc,
 public.lk_discount_rule_rank(p_name,p_phone,r.customer_name,r.company_name,coalesce(nullif(r.phone_display,''),r.phone)),
 r.excel_source_row desc nulls last,r.id desc limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.lk_excel_discount_rule_id_scoped(p_route_key text, p_year integer, p_voyage text, p_name text, p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select r.id from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
 where r.active and r.route_key in (p_route_key,'all')
  and public.lk_discount_rule_rank(p_name,p_phone,r.customer_name,r.company_name,coalesce(nullif(r.phone_display,''),r.phone))<9999
  and not (
    coalesce(r.discount_percent,0)=1
    and public.lk_excel_name(r.customer_name)='박성호'
    and not public.lk_is_park_seongho(coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name))
  )
 order by (r.route_key=p_route_key) desc,
 public.lk_discount_rule_rank(p_name,p_phone,r.customer_name,r.company_name,coalesce(nullif(r.phone_display,''),r.phone)),
 r.excel_source_row desc nulls last,r.id desc limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.lk_import_excel_base_rules_impl(p_route_key text, p_deliveries jsonb DEFAULT NULL::jsonb, p_discounts jsonb DEFAULT '[]'::jsonb, p_shares jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_saved_percent numeric;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if not exists(select 1 from public.route_definitions where route_key=p_route_key and deleted_at is null) then raise exception '운송 경로를 확인하세요.'; end if;
  if jsonb_typeof(p_discounts)<>'array' or (p_deliveries is not null and jsonb_typeof(p_deliveries)<>'array') or (p_shares is not null and jsonb_typeof(p_shares)<>'array') then raise exception 'Invalid rule arrays'; end if;
  if p_deliveries is not null then
    perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
    if exists(select 1 from jsonb_array_elements(p_deliveries) x group by x->>'source_no' having count(*)>1) then raise exception '배송 번호가 중복되어 있습니다.'; end if;
    -- A different customer at an occupied number indicates an older, conflicting BASE.
    -- Reject the whole transaction instead of replacing another customer's identity.
    if p_route_key=any(array['kr_la_sea','kr_la_air']) and exists(
      select 1 from jsonb_array_elements(p_deliveries) x join public.local_delivery_profiles d
      on d.route_key=p_route_key and d.source_no=(x->>'source_no')::int
      where public.lk_registry_name(d.customer_name)<>public.lk_registry_name(x->>'customer_name')
    ) then raise exception '배송 번호에 다른 고객이 등록되어 있습니다. 최신 공통 BASE를 다운로드하여 수정해 주세요.'; end if;
    delete from public.local_delivery_profiles d where d.route_key=p_route_key and not exists(select 1 from jsonb_array_elements(p_deliveries) x where (x->>'source_no')::int=d.source_no);
    for r in select value from jsonb_array_elements(p_deliveries) loop
      if nullif(btrim(r->>'customer_name'),'') is null or r->>'delivery_type' not in ('province','city') or r->>'source_no' is null then raise exception '배송 고객·종류·번호를 확인하세요.'; end if;
      insert into public.local_delivery_profiles(route_key,source_no,original_source_no,source_sheet,source_row,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred,active)
      values(p_route_key,(r->>'source_no')::integer,(r->>'original_source_no')::integer,r->>'source_sheet',(r->>'source_row')::integer,r->>'customer_name',r->>'alternate_name',r->>'company_name',r->>'phone',r->>'phone_display',r->>'delivery_type',r->>'local_company',r->>'destination_address',r->>'paid_by',r->>'notes',coalesce((r->>'preferred')::boolean,false),coalesce((r->>'active')::boolean,false))
      on conflict(route_key,source_no) do update set original_source_no=excluded.original_source_no,source_sheet=excluded.source_sheet,source_row=excluded.source_row,customer_name=excluded.customer_name,alternate_name=excluded.alternate_name,company_name=excluded.company_name,phone=excluded.phone,phone_display=excluded.phone_display,delivery_type=excluded.delivery_type,local_company=excluded.local_company,destination_address=excluded.destination_address,paid_by=excluded.paid_by,notes=excluded.notes,preferred=excluded.preferred,active=excluded.active,updated_at=now();
    end loop;
  end if;
  for r in select value from jsonb_array_elements(p_discounts) loop
    if (r->>'discount_percent') is null or (r->>'discount_percent')::numeric not between 0 and 1 or coalesce((r->>'special_discount_percent')::numeric,0) not between 0 and (r->>'discount_percent')::numeric then raise exception '할인율 범위를 확인하세요.'; end if;
    insert into public.customer_rate_overrides(customer_name,company_name,phone_display,phone,route_key,discount_percent,group_name,source_detail,active,excel_source_row,special_discount_percent)
    values(r->>'customer_name',coalesce(r->>'company_name',''),coalesce(r->>'phone_display',r->>'phone',''),r->>'phone',p_route_key,(r->>'discount_percent')::numeric,coalesce(r->>'group_name',''),coalesce(r->>'source_detail',''),coalesce((r->>'active')::boolean,false),(r->>'excel_source_row')::integer,(r->>'special_discount_percent')::numeric)
    on conflict(customer_name,phone,route_key) do update set company_name=case when r ? 'company_name' then excluded.company_name else customer_rate_overrides.company_name end,phone_display=case when r ? 'phone_display' then excluded.phone_display else customer_rate_overrides.phone_display end,discount_percent=(case when r->>'regular_discount_present'='false' then greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end)) else greatest(0,excluded.discount_percent-coalesce(excluded.special_discount_percent,0)) end)+(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),special_discount_percent=(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),group_name=case when r->>'regular_discount_present'='false' and greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end))>0 then customer_rate_overrides.group_name else excluded.group_name end,source_detail=excluded.source_detail,active=excluded.active,excel_source_row=excluded.excel_source_row,updated_at=now() returning discount_percent into v_saved_percent;
    if v_saved_percent not between 0 and 1 then raise exception '일반 할인과 특별할인의 합계는 100%%를 초과할 수 없습니다.'; end if;
  end loop;
  if p_shares is not null then
    delete from public.customer_statement_share_rules where route_key=p_route_key;
    for r in select value from jsonb_array_elements(p_shares) loop
      insert into public.customer_statement_share_rules(route_key,source_no,customer_name,phone,phone_display,content,active)
      values(p_route_key,(r->>'source_no')::integer,r->>'customer_name',r->>'phone',r->>'phone_display',r->>'content',true);
    end loop;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.lk_excel_policy_fields(kind text, r jsonb, prior jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare result jsonb:='{}'; field text; allowed text[]; total numeric; special numeric; regular numeric;
begin
 allowed:=case kind
 when 'deliveries' then array['source_no','original_source_no','source_sheet','source_row','customer_name','alternate_name','company_name','phone','phone_display','delivery_type','local_company','destination_address','paid_by','notes','preferred','active']
 when 'discounts' then array['customer_name','company_name','phone','phone_display','discount_percent','special_discount_percent','group_name','active','notes','rate_override','bulk_threshold','bulk_discount_percent','excel_source_row','source_detail']
 when 'shares' then array['source_no','customer_name','phone','phone_display','content','active']
 when 'zones' then array['customer_name','zone','active'] else array[]::text[] end;
 foreach field in array allowed loop
  if r ? field then result:=result||jsonb_build_object(field,r->field); end if;
 end loop;
 if kind='discounts' then
  total:=coalesce((r->>'discount_percent')::numeric,0);
  special:=coalesce((r->>'special_discount_percent')::numeric,case when regexp_replace(coalesce(r->>'group_name',''),'\s','','g')='특별할인' then total else 0 end);
  regular:=greatest(0,total-special);
  if r->>'regular_discount_present'='false' then regular:=greatest(0,coalesce((prior->>'discount_percent')::numeric,0)-coalesce((prior->>'special_discount_percent')::numeric,0)); end if;
  if r->>'special_discount_present'='false' then special:=coalesce((prior->>'special_discount_percent')::numeric,0); end if;
  if total not between 0 and 1 or regular+special not between 0 and 1 or special<0 then raise exception '할인율 합계는 0~100%%여야 합니다.'; end if;
  result:=result||jsonb_build_object('regular_discount_percent',regular,'special_discount_percent',special);
 end if;
 if not (result ? 'active') then result:=result||'{"active":true}'; end if;
 if kind='discounts' then result:=result-'discount_percent'; end if;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.admin_confirm_discount_rule(p_id bigint, p_customer_name text, p_company_name text, p_phone text, p_group_name text, p_discount_percent numeric, p_notes text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone text:=public.normalize_phone(p_phone);
begin
  if v_phone='' then
    raise exception '전화번호를 입력해야 할인 고객으로 확정할 수 있습니다.';
  end if;
  if p_discount_percent is null or p_discount_percent<0 or p_discount_percent>1 then
    raise exception '할인율은 0~100%% 범위여야 합니다.';
  end if;

  update public.customer_rate_overrides
  set customer_name=btrim(coalesce(p_customer_name,'')),
      company_name=btrim(coalesce(p_company_name,'')),
      phone=v_phone,
      phone_display=btrim(coalesce(p_phone,'')),
      group_name=btrim(coalesce(p_group_name,'')),
      discount_percent=p_discount_percent,
      notes=btrim(coalesce(p_notes,'')),
      active=true
  where id=p_id;

  if not found then
    raise exception '할인 규칙을 찾지 못했습니다.';
  end if;

  perform public.admin_refresh_shipment_special_notes();
end
$function$
;

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
      and public.lk_discount_rule_rank(p_name,p_phone,r.customer_name,r.company_name,coalesce(nullif(r.phone_display,''),r.phone))<9999
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
$function$
;


-- Retain rollback evidence inside the existing private schema. Rates, active
-- flags and all other business data are copied but never rewritten here.
create table if not exists lk_private.discount_identity_backup_20261121 as
 select id,customer_name,company_name,phone,phone_display,route_key,group_name,active,discount_percent,updated_at
 from public.customer_rate_overrides;
revoke all on table lk_private.discount_identity_backup_20261121 from public,anon,authenticated;

create or replace function public.lk_discount_preserve_phone_display()
returns trigger language plpgsql set search_path='' as $$
declare tokens text[];
begin
 if btrim(coalesce(new.phone_display,''))='' or regexp_replace(new.phone_display,'[^0-9]','','g')<>regexp_replace(coalesce(new.phone,''),'[^0-9]','','g') then
  tokens:=public.lk_discount_phone_tokens(new.phone);
  new.phone_display:=case when cardinality(tokens)>0 and not ''=any(tokens)
    then array_to_string(tokens,' / ') else coalesce(new.phone,'') end;
 end if;
 return new;
end $$;
drop trigger if exists trg_discount_phone_display on public.customer_rate_overrides;
create trigger trg_discount_phone_display before insert or update of phone,phone_display
 on public.customer_rate_overrides for each row execute function public.lk_discount_preserve_phone_display();

-- Restore only unambiguous company metadata lost by the old BASE importer.
-- The exact route, registered member name and discount group must all agree.
with known as (
 select a.id,min(b.company_name) company_name
 from public.customer_rate_overrides a join public.customer_rate_overrides b
 on b.route_key=a.route_key and public.lk_registry_name(b.customer_name)=public.lk_registry_name(a.customer_name)
 and b.group_name=a.group_name and nullif(btrim(b.company_name),'') is not null
 where a.active and coalesce(a.company_name,'')='' and a.source_detail like 'BASE Excel%'
 group by a.id having count(distinct b.company_name)=1
)
update public.customer_rate_overrides r set company_name=k.company_name from known k where r.id=k.id;

-- Existing identity keys remain unchanged, so voyage-only overrides keep their
-- exact scope. The display value retains boundaries for matching and editing.
update public.customer_rate_overrides
 set phone_display=case when length(regexp_replace(phone,'[^0-9]','','g'))>15 and not ''=any(public.lk_discount_phone_tokens(phone)) then array_to_string(public.lk_discount_phone_tokens(phone),' / ') else coalesce(phone,'') end
 where coalesce(phone_display,'')='' and nullif(btrim(phone),'') is not null;
