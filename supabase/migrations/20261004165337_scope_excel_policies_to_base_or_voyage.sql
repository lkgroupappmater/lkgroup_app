-- BASE defaults are global inputs. A voyage upload records only its differences.
create table public.excel_workbook_policies (
 route_key text not null references public.route_definitions(route_key),
 shipment_year integer not null,
 voyage text not null,
 changes jsonb not null default '{}',
 source_file_name text not null default '',
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 primary key(route_key,shipment_year,voyage),
 check ((voyage='00' and shipment_year=0) or (voyage ~ '^[0-9]{2,3}$' and voyage::int>0 and shipment_year between 1900 and 2099))
);
alter table public.excel_workbook_policies enable row level security;
revoke all on public.excel_workbook_policies from public,anon,authenticated;
grant select on public.excel_workbook_policies to authenticated;
grant all on public.excel_workbook_policies to service_role;
create policy excel_policy_read on public.excel_workbook_policies for select to authenticated
 using ((select auth.uid()) is not null and public.is_approved_user());

create function public.lk_excel_policy_key(kind text,r jsonb) returns text
language sql immutable set search_path='' as $$
 select case kind
 when 'deliveries' then coalesce(r->>'delivery_type','province')||'|'||coalesce(r->>'source_no','')
 when 'discounts' then public.lk_registry_name(r->>'customer_name')||'|'||public.lk_registry_phone(r->>'phone')
 when 'shares' then public.lk_registry_name(r->>'customer_name')||'|'||public.lk_registry_phone(coalesce(r->>'phone_display',r->>'phone'))
 when 'zones' then public.lk_registry_name(r->>'customer_name')
 else coalesce(r->>'key','') end;
$$;

create function public.lk_excel_policy_fields(kind text,r jsonb,prior jsonb default '{}') returns jsonb
language plpgsql immutable set search_path='' as $$
declare result jsonb:='{}'; field text; allowed text[]; total numeric; special numeric; regular numeric;
begin
 allowed:=case kind
 when 'deliveries' then array['source_no','original_source_no','source_sheet','source_row','customer_name','alternate_name','company_name','phone','phone_display','delivery_type','local_company','destination_address','paid_by','notes','preferred','active']
 when 'discounts' then array['customer_name','phone','discount_percent','special_discount_percent','group_name','active','notes','rate_override','bulk_threshold','bulk_discount_percent','excel_source_row','source_detail']
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
end $$;

create function public.lk_excel_base_policy(p_route_key text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'deliveries',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.local_delivery_profiles r where r.route_key=p_route_key),
 'discounts',(select coalesce(jsonb_agg(to_jsonb(r) order by (r.route_key=p_route_key),r.id),'[]') from public.customer_rate_overrides r where r.route_key in(p_route_key,'all')),
 'shares',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.customer_statement_share_rules r where r.route_key=p_route_key),
 'zones',(select coalesce(jsonb_agg(to_jsonb(r) order by (r.route_key=p_route_key),r.id),'[]') from public.customer_zone_overrides r where r.route_key in(p_route_key,'all')),
 'reviews',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.excel_delivery_match_reviews r where r.route_key=p_route_key),
 'appearance','{"province":"FFC000","province_prepaid":"9DC3E6","city":"A9D18E","city_prepaid":"D6B18A"}'::jsonb||coalesce((select changes->'appearance' from public.excel_workbook_policies where route_key=p_route_key and shipment_year=0 and voyage='00'),'{}'));
$$;

create function public.lk_excel_policy_delta(kind text,base_rows jsonb,incoming jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare baseline jsonb:='{}'; seen jsonb:='{}'; delta jsonb:='{}'; r jsonb; b jsonb; normalized jsonb; patch jsonb; k text; field record;
begin
 if incoming is null or incoming='null'::jsonb then return null; end if;
 if jsonb_typeof(incoming)<>'array' then raise exception 'Excel 규칙 목록 형식이 올바르지 않습니다.'; end if;
 for r in select value from jsonb_array_elements(coalesce(base_rows,'[]')) loop
  baseline:=baseline||jsonb_build_object(public.lk_excel_policy_key(kind,r),r);
 end loop;
 for r in select value from jsonb_array_elements(incoming) loop
  k:=public.lk_excel_policy_key(kind,r);b:=coalesce(baseline->k,'{}'); if b<>'{}' then b:=b||public.lk_excel_policy_fields(kind,b,b); end if;
  if seen?k then raise exception '중복 Excel 규칙을 확인해 주세요: %',kind; end if;
  seen:=seen||jsonb_build_object(k,true); normalized:=public.lk_excel_policy_fields(kind,r,b);patch:='{}';
  for field in select * from jsonb_each(normalized) loop
   if field.value is distinct from b->field.key and not (field.value in ('null'::jsonb,'""'::jsonb) and (not (b ? field.key) or b->field.key='null'::jsonb)) then patch:=patch||jsonb_build_object(field.key,field.value); end if;
  end loop;
  if patch<>'{}' then delta:=delta||jsonb_build_object(k,jsonb_build_object('patch',patch,'identity',jsonb_build_object('customer_name',r->'customer_name','phone',r->'phone','source_no',r->'source_no','delivery_type',r->'delivery_type'))); end if;
 end loop;
 -- Missing whole sheets are null; an explicitly present empty sheet clears only
 -- that voyage's rules. Manual/non-Excel discounts absent from the workbook stay.
 for field in select * from jsonb_each(baseline) loop
  if not (seen ? field.key) and (kind<>'discounts' or field.value->>'excel_source_row' is not null) then
   delta:=delta||jsonb_build_object(field.key,jsonb_build_object('deleted',true));
  end if;
 end loop;
 return delta;
end $$;

create function public.lk_excel_effective_policy(p_route_key text,p_year integer,p_voyage text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb:=public.lk_excel_base_policy(p_route_key); overrides jsonb; kind text; rows_by_key jsonb; r jsonb; pair record; output jsonb; ordinal bigint;
begin
 if coalesce(p_voyage,'') !~ '^[0-9]{1,3}$' or p_voyage::int=0 then return result; end if;
 select changes into overrides from public.excel_workbook_policies
 where route_key=p_route_key and shipment_year=p_year and voyage=lpad((p_voyage::int)::text,greatest(2,length((p_voyage::int)::text)),'0');
 if overrides is null then return result; end if;
 foreach kind in array array['deliveries','discounts','shares','zones'] loop
  if not (overrides ? kind) then continue; end if;
  rows_by_key:='{}';
  for r in select value from jsonb_array_elements(result->kind) loop if kind='discounts' then r:=r||public.lk_excel_policy_fields(kind,r,r); end if; rows_by_key:=rows_by_key||jsonb_build_object(public.lk_excel_policy_key(kind,r),r); end loop;
  for pair in select * from jsonb_each(overrides->kind) loop
   if pair.value->>'deleted'='true' then rows_by_key:=rows_by_key-pair.key;
   else rows_by_key:=rows_by_key||jsonb_build_object(pair.key,coalesce(rows_by_key->pair.key,jsonb_strip_nulls(pair.value->'identity'))||(pair.value->'patch')||jsonb_build_object('route_key',p_route_key)); end if;
  end loop;
  output:='[]';ordinal:=0;
  for pair in select * from jsonb_each(rows_by_key) order by key loop
   ordinal:=ordinal+1;r:=pair.value;
   if r->>'id' is null then r:=r||jsonb_build_object('id',-(abs(hashtextextended(kind||':'||pair.key,0)%9007199254740990)+1)); end if;
   if kind='discounts' then r:=r||jsonb_build_object('discount_percent',coalesce((r->>'regular_discount_percent')::numeric,greatest(0,coalesce((r->>'discount_percent')::numeric,0)-coalesce((r->>'special_discount_percent')::numeric,0)))+coalesce((r->>'special_discount_percent')::numeric,0)); end if;
   output:=output||jsonb_build_array(r);
  end loop;
  result:=jsonb_set(result,array[kind],output);
 end loop;
 result:=jsonb_set(result,'{appearance}',coalesce(result->'appearance','{}')||coalesce(overrides->'appearance','{}'));
 if overrides?'reviews' then result:=jsonb_set(result,'{reviews}',(overrides->'reviews')||coalesce((select jsonb_agg(b) from jsonb_array_elements(result->'reviews') b where not exists(select 1 from jsonb_array_elements(overrides->'reviews') o where o->>'name_key'=b->>'name_key' and o->>'phone_key'=b->>'phone_key')),'[]')); end if;
 return result;
end $$;

-- Old clients must not silently promote voyage values to shared defaults.
alter function public.web_import_excel_rules(text,jsonb,jsonb,jsonb) rename to lk_import_excel_base_rules_impl;
alter function public.web_import_excel_zone_rules(text,jsonb) rename to lk_import_excel_base_zones_impl;
revoke all on function public.lk_import_excel_base_rules_impl(text,jsonb,jsonb,jsonb),public.lk_import_excel_base_zones_impl(text,jsonb) from public,anon,authenticated;
create function public.web_import_excel_rules(p_route_key text,p_deliveries jsonb default null,p_discounts jsonb default '[]',p_shares jsonb default null) returns void language plpgsql set search_path='' as $$begin raise exception '엑셀 적용 범위를 확인할 수 없습니다. 앱을 업데이트하거나 웹을 새로고침한 뒤 다시 업로드하세요.';end$$;
create function public.web_import_excel_zone_rules(p_route_key text,p_zones jsonb) returns void language plpgsql set search_path='' as $$begin raise exception '엑셀 적용 범위를 확인할 수 없습니다. 앱을 업데이트하거나 웹을 새로고침한 뒤 다시 업로드하세요.';end$$;

CREATE OR REPLACE FUNCTION public.lk_import_excel_base_rules_impl(p_route_key text, p_deliveries jsonb DEFAULT NULL::jsonb, p_discounts jsonb DEFAULT '[]'::jsonb, p_shares jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_saved_percent numeric;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if not exists(select 1 from public.route_definitions where route_key=p_route_key and deleted_at is null) then raise exception '운송 경로를 확인하세요.'; end if;
  if jsonb_typeof(p_discounts)<>'array' or (p_deliveries is not null and jsonb_typeof(p_deliveries)<>'array') or (p_shares is not null and jsonb_typeof(p_shares)<>'array') then raise exception 'Invalid rule arrays'; end if;
  if p_deliveries is not null then
    delete from public.local_delivery_profiles where route_key=p_route_key;
    for r in select value from jsonb_array_elements(p_deliveries) loop
      insert into public.local_delivery_profiles(route_key,source_no,original_source_no,source_sheet,source_row,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred,active)
      values(p_route_key,(r->>'source_no')::integer,(r->>'original_source_no')::integer,r->>'source_sheet',(r->>'source_row')::integer,r->>'customer_name',r->>'alternate_name',r->>'company_name',r->>'phone',r->>'phone_display',r->>'delivery_type',r->>'local_company',r->>'destination_address',r->>'paid_by',r->>'notes',coalesce((r->>'preferred')::boolean,false),coalesce((r->>'active')::boolean,false));
    end loop;
  end if;
  for r in select value from jsonb_array_elements(p_discounts) loop
    if (r->>'discount_percent') is null or (r->>'discount_percent')::numeric not between 0 and 1 or coalesce((r->>'special_discount_percent')::numeric,0) not between 0 and (r->>'discount_percent')::numeric then raise exception '할인율 범위를 확인하세요.'; end if;
    insert into public.customer_rate_overrides(customer_name,phone,route_key,discount_percent,group_name,source_detail,active,excel_source_row,special_discount_percent)
    values(r->>'customer_name',r->>'phone',p_route_key,(r->>'discount_percent')::numeric,coalesce(r->>'group_name',''),coalesce(r->>'source_detail',''),coalesce((r->>'active')::boolean,false),(r->>'excel_source_row')::integer,(r->>'special_discount_percent')::numeric)
    on conflict(customer_name,phone,route_key) do update set discount_percent=(case when r->>'regular_discount_present'='false' then greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end)) else greatest(0,excluded.discount_percent-coalesce(excluded.special_discount_percent,0)) end)+(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),special_discount_percent=(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),group_name=case when r->>'regular_discount_present'='false' and greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end))>0 then customer_rate_overrides.group_name else excluded.group_name end,source_detail=excluded.source_detail,active=excluded.active,excel_source_row=excluded.excel_source_row,updated_at=now() returning discount_percent into v_saved_percent;
    if v_saved_percent not between 0 and 1 then raise exception '일반 할인과 특별할인의 합계는 100%%를 초과할 수 없습니다.'; end if;
  end loop;
  if p_shares is not null then
    delete from public.customer_statement_share_rules where route_key=p_route_key;
    for r in select value from jsonb_array_elements(p_shares) loop
      insert into public.customer_statement_share_rules(route_key,source_no,customer_name,phone,phone_display,content,active)
      values(p_route_key,(r->>'source_no')::integer,r->>'customer_name',r->>'phone',r->>'phone_display',r->>'content',true);
    end loop;
  end if;
end $function$;
create function public.import_excel_workbook_policy(p_route_key text,p_year integer,p_voyage text,p_file_name text,p_rules jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v text; y integer; baseline jsonb; changes jsonb; kind text; delta jsonb; appearance jsonb; field record;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
 if p_year is null or p_rules is null or p_year not between 1900 and 2099 or coalesce(p_voyage,'')!~'^[0-9]{1,3}$' or not exists(select 1 from public.route_definitions where route_key=p_route_key and deleted_at is null) or jsonb_typeof(p_rules)<>'object' then raise exception '운송 경로·연도·항차·규칙 형식을 확인하세요.'; end if;
 v:=lpad((p_voyage::int)::text,greatest(2,length((p_voyage::int)::text)),'0');y:=case when v='00' then 0 else p_year end;
 if v='00' and coalesce(p_file_name,'')!~*'(^|[^a-z0-9])(base|v?xx|v0{1,3})([^a-z0-9]|$)|xx\s*항차|0{1,3}\s*항차|기본' then raise exception '공통 기본값은 XX/BASE/V00 엑셀로만 변경할 수 있습니다.'; end if;
 if v='00' and coalesce(p_file_name,'')~*'(^|[^a-z0-9])v(oyage)?[ _-]*0*[1-9][0-9]*([^0-9]|$)|(^|[^0-9])0*[1-9][0-9]*[[:space:]]*항차' then raise exception '항차 파일은 BASE로 저장할 수 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('excel-policy:'||p_route_key||':'||y||':'||v,0));
 baseline:=public.lk_excel_base_policy(p_route_key);
 select p.changes into changes from public.excel_workbook_policies p where p.route_key=p_route_key and p.shipment_year=y and p.voyage=v;
 changes:=coalesce(changes,'{}');
 foreach kind in array array['deliveries','discounts','shares','zones'] loop
  delta:=public.lk_excel_policy_delta(kind,baseline->kind,p_rules->kind);
  if delta is not null then changes:=jsonb_set(changes,array[kind],delta); end if;
 end loop;
 if p_rules?'appearance' and p_rules->'appearance'<>'{}'::jsonb then
  if jsonb_typeof(p_rules->'appearance')<>'object' then raise exception 'Excel 색상 형식을 확인하세요.'; end if;
  appearance:='{}';
  for field in select * from jsonb_each(p_rules->'appearance') loop
   if field.value::text!~'^"[A-Fa-f0-9]{6}"$' then raise exception 'Excel 색상 값이 올바르지 않습니다.'; end if;
   if v='00' or field.value is distinct from baseline->'appearance'->field.key then appearance:=appearance||jsonb_build_object(field.key,field.value); end if;
  end loop;
  changes:=jsonb_set(changes,'{appearance}',appearance);
 end if;
 if v='00' then
  if jsonb_typeof(p_rules->'discounts')='array' then
   delete from public.customer_rate_overrides d where d.route_key=p_route_key and d.excel_source_row is not null and not exists(select 1 from jsonb_array_elements(p_rules->'discounts') r where public.lk_excel_policy_key('discounts',r)=public.lk_excel_policy_key('discounts',to_jsonb(d)));
  end if;
  perform public.lk_import_excel_base_rules_impl(p_route_key,nullif(p_rules->'deliveries','null'::jsonb),coalesce(nullif(p_rules->'discounts','null'::jsonb),'[]'),nullif(p_rules->'shares','null'::jsonb));
  perform public.lk_import_excel_base_zones_impl(p_route_key,nullif(p_rules->'zones','null'::jsonb));
  changes:=jsonb_build_object('appearance',coalesce(changes->'appearance','{}'));
 end if;
 insert into public.excel_workbook_policies(route_key,shipment_year,voyage,changes,source_file_name,updated_by)
 values(p_route_key,y,v,changes,p_file_name,auth.uid()) on conflict(route_key,shipment_year,voyage)
 do update set changes=excluded.changes,source_file_name=excluded.source_file_name,updated_by=excluded.updated_by,updated_at=now();
 -- Voyage settings invalidate only the voyage's derived settlement cache.
 if v<>'00' then delete from public.voyage_settlement_snapshots where route_key=p_route_key and shipment_year=p_year and voyage=v; end if;
 return jsonb_build_object('scope',case when v='00' then 'base' else 'voyage' end,'route_key',p_route_key,'shipment_year',y,'voyage',v,'changes',changes);
end $$;

revoke all on function public.lk_excel_policy_key(text,jsonb),public.lk_excel_policy_fields(text,jsonb,jsonb),public.lk_excel_base_policy(text),public.lk_excel_policy_delta(text,jsonb,jsonb),public.lk_excel_effective_policy(text,integer,text),public.import_excel_workbook_policy(text,integer,text,text,jsonb) from public,anon;
grant execute on function public.lk_excel_policy_key(text,jsonb),public.lk_excel_policy_fields(text,jsonb,jsonb),public.lk_excel_base_policy(text),public.lk_excel_policy_delta(text,jsonb,jsonb),public.lk_excel_effective_policy(text,integer,text),public.import_excel_workbook_policy(text,integer,text,text,jsonb) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.lk_excel_discount_rule_id_scoped(p_route_key text, p_year integer, p_voyage text, p_name text, p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select r.id from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
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

CREATE OR REPLACE FUNCTION public.lk_excel_delivery_review_batch_scoped(p_route_key text, p_year integer, p_voyage text, p_customers jsonb)
 RETURNS TABLE(name text, phone text, profile_id bigint, candidates jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with identity_pairs as materialized (
 select r.name_key nk,r.phone_key pk,r.id customer_id from public.customer_registry r
 where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명' and not public.lk_statement_special_prefix(r.name)
 union all
 select a.name_key,a.phone_key,r.id from public.customer_registry_aliases a join public.customer_registry r on r.id=a.customer_registry_id
 where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명' and not public.lk_statement_special_prefix(r.name)
 ), identities as materialized (
 select nk,pk,(array_agg(distinct customer_id))[1] customer_id from identity_pairs where nk<>'' and pk<>'' group by nk,pk having count(distinct customer_id)=1
 ), inputs as materialized (
 select i.*,k.customer_id from (
 select distinct x->>'name' name,x->>'phone' phone,public.lk_registry_name(public.lk_customer_base_name(x->>'name')) nk,
 public.lk_registry_name(x->>'name') source_nk,public.lk_registry_phone(x->>'phone') pk,public.lk_delivery_phone_tokens(x->>'phone') phones
 from jsonb_array_elements(coalesce(p_customers,'[]')) x
 )i left join identities k on k.nk=i.nk and k.pk=i.pk
 ), profiles as materialized (
 select d.*,public.lk_delivery_match_fingerprint(d) fingerprint,k.customer_id,
 count(*) over(partition by k.customer_id) customer_profile_count,
 array_remove(array[nullif(public.lk_registry_name(customer_name),''),nullif(public.lk_registry_name(alternate_name),''),nullif(public.lk_registry_name(company_name),'')],null) names,
 public.lk_delivery_phone_tokens(coalesce(nullif(phone_display,''),d.phone)) phones
 from jsonb_populate_recordset(null::public.local_delivery_profiles,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'deliveries') d left join identities k
 on k.nk=public.lk_registry_name(public.lk_customer_base_name(d.customer_name)) and k.pk=public.lk_registry_phone(coalesce(nullif(d.phone_display,''),d.phone))
 where d.active and d.route_key=p_route_key
 ), matched as materialized (
 select i.name,i.phone,p.id,p.customer_name,p.alternate_name,p.phone_display,p.phone profile_phone,p.delivery_type,p.local_company,p.destination_address,p.fingerprint,p.preferred,p.source_row,p.source_no,
 r.approved,i.nk=any(p.names) exact_name,i.phones&&p.phones phone_match,
 coalesce(i.customer_id=p.customer_id,false) same_customer,
 coalesce(i.customer_id=p.customer_id and p.customer_profile_count=1,false) unique_customer,
 exists(select 1 from unnest(p.names) n where length(i.nk)>=2 and length(n)>=2 and (position(i.nk in n)>0 or position(n in i.nk)>0)) partial_name
 from inputs i cross join profiles p left join jsonb_populate_recordset(null::public.excel_delivery_match_reviews,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'reviews') r
 on r.route_key=p_route_key and r.name_key=i.source_nk and r.phone_key=i.pk and r.delivery_profile_id=p.id and r.profile_fingerprint=p.fingerprint
 where i.nk<>''
 ), ranked as materialized (
 select m.*,row_number() over(partition by name,phone order by (approved is true) desc,(exact_name and phone_match) desc,unique_customer desc,same_customer desc,phone_match desc,exact_name desc,id) rn
 from matched m where approved is distinct from false and (exact_name or phone_match or partial_name or same_customer or approved is true)
 ), confirmed as (
 select distinct on(name,phone) name,phone,id from ranked where approved is true or(exact_name and phone_match) or unique_customer
 order by name,phone,(approved is true) desc,(approved is true or(exact_name and phone_match)) desc,(delivery_type='province') desc,preferred desc,coalesce(source_row,source_no,0) desc,id desc
 ), lists as (
 select name,phone,jsonb_agg(jsonb_build_object('id',id,'name',customer_name,'receiver',alternate_name,'phone',coalesce(nullif(phone_display,''),profile_phone),'type',delivery_type,'company',local_company,'address',destination_address,'fingerprint',fingerprint,'reason',case when exact_name and phone_match then '이름·연락처 일치' when unique_customer then '통합 고객 ID 일치' when same_customer then '동일 고객 ID · 배송지 확인 필요' when phone_match then '연락처 일치 · 이름 확인 필요' when exact_name then '이름 일치 · 연락처 확인 필요' else '이름 일부 유사 · 확인 필요' end) order by rn) candidates
 from ranked where rn<=20 group by name,phone
 )
 select i.name,i.phone,c.id,coalesce(l.candidates,'[]'::jsonb) from inputs i left join confirmed c on c.name is not distinct from i.name and c.phone is not distinct from i.phone left join lists l on l.name is not distinct from i.name and l.phone is not distinct from i.phone;
$function$;

CREATE OR REPLACE FUNCTION public.lk_excel_delivery_profile_id_scoped(p_route_key text, p_year integer, p_voyage text, p_shipment_name text, p_shipment_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select profile_id from public.lk_excel_delivery_review_batch_scoped(p_route_key,p_year,p_voyage,jsonb_build_array(jsonb_build_object('name',p_shipment_name,'phone',p_shipment_phone))) limit 1;
$function$;

create function public.lk_excel_delivery_matches_scoped(p_route_key text,p_year integer,p_voyage text,p_customers jsonb) returns jsonb language sql stable set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object('name',name,'phone',phone,'id',profile_id)),'[]') from public.lk_excel_delivery_review_batch_scoped(p_route_key,p_year,p_voyage,p_customers);$$;

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
begin
  if public.lk_is_park_seongho(coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name)) then
    v_group := '대표 고정 할인';
    v_discount := 1;
  else
    select coalesce(r.group_name,''),coalesce(r.discount_percent,0),coalesce(r.notes,'')
      into v_group,v_discount,v_discount_notes
    from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'discounts') r
    where r.id=public.lk_excel_discount_rule_id_scoped(v_route_key,p_year,p_voyage,p_name,p_phone);
  end if;

  v_delivery_id := public.lk_excel_delivery_profile_id_scoped(
    v_route_key,p_year,p_voyage,p_name,p_phone
  );
  if v_delivery_id is not null then
    select coalesce(d.delivery_type,''),coalesce(d.paid_by,'')
      into v_delivery_type,v_paid_by
    from jsonb_populate_recordset(null::public.local_delivery_profiles,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'deliveries') d
    where d.id=v_delivery_id;
  end if;

  select coalesce(s.content,'') into v_share_text
  from jsonb_populate_recordset(null::public.customer_statement_share_rules,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'shares') s
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
    from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
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
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
    where r.id=public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone);

    v_qty := 0;
  end if;

  -- A bare namesake must not inherit the representative's old BASE row.
  if coalesce(v_rule.discount_percent,0)=1
     and public.lk_excel_name(v_rule.customer_name)='박성호'
     and not public.lk_is_park_seongho(p_name) then
    v_rule := null;
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
    where r.id=public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone);
  end if;

  -- Identity-group membership must not suppress the same Excel name/phone
  -- rule used by automatic remarks when no group-linked override exists.
  if v_rule.id is null and v_gid is not null then
    select * into v_rule from jsonb_populate_recordset(null::public.customer_rate_overrides,public.lk_excel_effective_policy(p_route_key,p_year,p_voyage)->'discounts') r
    where r.id=public.lk_excel_discount_rule_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone);
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

CREATE OR REPLACE FUNCTION public.admin_finalize_excel_batch_rules(p_route text, p_year integer, p_voyage text, p_resequence boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(public.current_role(),'')<>'admin'
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception '관리자(총괄)만 항차 재계산을 실행할 수 있습니다.';
  end if;
  perform set_config('lkgroup.bulk_import','1',true);
  perform public.normalize_shipment_batch(p_route,p_year,p_voyage);
  with batch as materialized (
    select s.id,s.route,s.consignee_name,s.consignee_phone
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')
        =lpad(regexp_replace(p_voyage,'[^0-9]','','g'),2,'0')
      and s.deleted_at is null and s.deletion_requested_at is null
      and not coalesce(s.data_locked,false)
  ), customer_notes as materialized (
    select c.*,public.compute_shipment_special_note_scoped(
      c.route,p_year,p_voyage,c.consignee_name,c.consignee_phone) as note
    from (select distinct route,consignee_name,consignee_phone from batch) c
  )
  update public.shipments s set special_note_auto=n.note
  from batch b join customer_notes n
    on n.route is not distinct from b.route
    and n.consignee_name is not distinct from b.consignee_name
    and n.consignee_phone is not distinct from b.consignee_phone
  where s.id=b.id and s.special_note_auto is distinct from n.note;
  perform set_config('lkgroup.bulk_import','',true);
exception when others then
  perform set_config('lkgroup.bulk_import','',true);
  raise;
end;
$function$;

CREATE OR REPLACE FUNCTION public.normalize_shipment_batch(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rk text; label text; v text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'); changed boolean;
begin
 if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
 if not public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) then return; end if;
 select route_key,display_name into rk,label from public.route_definitions
 where route_key=btrim(p_route) or display_name=btrim(p_route)
 order by (display_name=btrim(p_route)) desc limit 1;
 if rk is null or p_year is null or v='' or v='00' then return; end if;
 -- A full Excel snapshot owns the voyage's receipt and zone assignments.
 -- Reassigning these here would bypass pending requests or undo an approval.
 if current_setting('lkgroup.apply_customer_ids',true) is distinct from '1' and (exists(select 1 from public.shipment_excel_sync_runs r
   where r.route in (rk,label) and r.shipment_year=p_year and r.voyage=v)
 or exists(select 1 from public.shipment_change_requests q join public.shipments s on s.id=q.shipment_id where q.request_source='excel_import' and q.changes?'receipt_number' and s.route in(rk,label) and s.shipment_year=p_year and s.voyage=v)) then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(rk||'|'||p_year||'|'||v,0));
 perform set_config('lkgroup.normalizing_shipments','1',true);
 drop table if exists pg_temp._lk_sync_plan;
 drop table if exists pg_temp._lk_sync_map;
 drop table if exists pg_temp._lk_sync_zone;
 create temporary table _lk_sync_plan on commit drop as select * from public.lk_excel_receipt_plan(label,p_year,v);
 if exists(select 1 from _lk_sync_plan where identity_key<>'' and coalesce(new_receipt,'')='') then
   raise exception '고객별 명세서 번호를 확정할 수 없습니다.';
 end if;
 if exists(select 1 from _lk_sync_plan where locked group by identity_key having count(distinct old_receipt)>1) then
   raise exception '동일 고객에 잠긴 명세서 번호가 여러 개 있습니다. 잠금 상태를 먼저 확인하세요.';
 end if;
 -- A split receipt with explicit money attached cannot be assigned by guessing.
 if exists(select 1 from _lk_sync_plan p where p.old_receipt<>'' and (
   exists(select 1 from public.receipt_extra_costs e where e.route=label and e.shipment_year=p_year and e.voyage=v and btrim(e.receipt_number)=p.old_receipt)
   or exists(select 1 from public.receipt_discount_overrides d where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and btrim(d.receipt_number)=p.old_receipt)
 ) group by old_receipt having count(distinct new_receipt)>1) then
   raise exception '고객 분리 전 해당 명세서의 수동 할인·추가비용 연결을 확인하세요.';
 end if;
 create temporary table _lk_sync_map on commit drop as
 select old_receipt,min(new_receipt) new_receipt from _lk_sync_plan
 where old_receipt<>'' group by old_receipt having count(distinct new_receipt)=1;
 if exists(select 1 from public.receipt_discount_overrides d join _lk_sync_map m on btrim(d.receipt_number)=m.old_receipt
   where d.route_key=rk and d.shipment_year=p_year and d.voyage=v
   group by m.new_receipt having count(*)>1) then
   raise exception '고객 병합 대상에 수동 할인이 둘 이상 있습니다. 할인 내용을 먼저 확인하세요.';
 end if;
 -- Do not let an orphan charge attach to a newly reused numeric slot.
 if exists(select 1 from public.receipt_extra_costs e where e.route=label and e.shipment_year=p_year and e.voyage=v
   and exists(select 1 from _lk_sync_plan p where p.new_receipt=btrim(e.receipt_number))
   and not exists(select 1 from _lk_sync_map m where m.old_receipt=btrim(e.receipt_number)))
 or exists(select 1 from public.receipt_discount_overrides d where d.route_key=rk and d.shipment_year=p_year and d.voyage=v
   and exists(select 1 from _lk_sync_plan p where p.new_receipt=btrim(d.receipt_number))
   and not exists(select 1 from _lk_sync_map m where m.old_receipt=btrim(d.receipt_number))) then
   raise exception '화물과 연결되지 않은 할인·추가비용 번호가 있습니다. 해당 연결을 먼저 확인하세요.';
 end if;
 select exists(select 1 from _lk_sync_plan where old_receipt is distinct from new_receipt) into changed;
 if changed then
   insert into public.shipment_automation_history(route_key,shipment_year,voyage,receipt_mapping,prior_snapshots)
   values(rk,p_year,v,coalesce((select jsonb_agg(to_jsonb(m)) from _lk_sync_plan m),'[]'),
     coalesce((select jsonb_agg(to_jsonb(s)) from public.voyage_settlement_snapshots s where s.route_key in (rk,label) and s.shipment_year=p_year and s.voyage=v),'[]'));
   update public.receipt_extra_costs e set receipt_number=m.new_receipt
   from _lk_sync_map m where e.route=label and e.shipment_year=p_year and e.voyage=v
     and btrim(e.receipt_number)=m.old_receipt and e.receipt_number is distinct from m.new_receipt;
   -- Temporary keys avoid the unique constraint during swaps such as 03 <-> 04.
   update public.receipt_discount_overrides d set receipt_number='__LK_SYNC__'||m.new_receipt
   from _lk_sync_map m where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and btrim(d.receipt_number)=m.old_receipt;
   update public.receipt_discount_overrides d set receipt_number=substr(receipt_number,12)
   where d.route_key=rk and d.shipment_year=p_year and d.voyage=v and left(receipt_number,11)='__LK_SYNC__';
   update public.domestic_parcels d set statement_receipt=m.new_receipt from _lk_sync_map m
   where d.statement_route=label and d.statement_year=p_year and d.statement_voyage=v and d.statement_receipt=m.old_receipt;
   update public.domestic_parcels d set link_receipt_number=m.new_receipt from _lk_sync_map m
   where d.link_route=label and d.link_year=p_year and d.link_voyage=v and d.link_receipt_number=m.old_receipt;
   -- This is a derived cache; the prior value is archived above. Both clients
   -- recalculate from current shipments before rendering/exporting a settlement.
   delete from public.voyage_settlement_snapshots where route_key in (rk,label) and shipment_year=p_year and voyage=v;
 end if;
 create temporary table _lk_sync_zone on commit drop as
 with g as (
   select p.new_receipt,sum(greatest(coalesce(s.quantity,1),1)) qty,
     (array_agg(s.consignee_name order by s.box_number collate "C",s.id))[1] name,
     (array_agg(s.consignee_phone order by s.box_number collate "C",s.id))[1] phone,
     bool_or(p.is_unknown) unknown
   from _lk_sync_plan p join public.shipments s on s.id=p.shipment_id group by p.new_receipt
 ) select g.new_receipt,
   case when g.unknown then 'F'
     when rk='kr_la_air' then '102'
     when public.lk_excel_delivery_profile_id_scoped(rk,p_year,p_voyage,g.name,g.phone) is not null then 'F'
     when z.zone is not null then z.zone
     when g.qty>=20 then 'F' when g.qty>=10 then 'C' when g.qty>=5 then 'B' else 'A' end zone
 from g left join lateral (
   select o.zone from jsonb_populate_recordset(null::public.customer_zone_overrides,public.lk_excel_effective_policy(rk,p_year,p_voyage)->'zones') o
   where o.active and o.route_key in (rk,'all') and public.lk_excel_name(o.customer_name)<>'' and public.lk_excel_match_name(g.name,g.phone)<>''
    and (position(public.lk_excel_name(o.customer_name) in public.lk_excel_match_name(g.name,g.phone))>0
      or position(public.lk_excel_match_name(g.name,g.phone) in public.lk_excel_name(o.customer_name))>0)
   order by (o.route_key=rk) desc,o.id desc limit 1
 ) z on true;
 update public.shipments s set receipt_number=p.new_receipt,recipient_unknown=case when current_setting('lkgroup.apply_customer_ids',true)='1' then s.recipient_unknown else p.is_unknown end,unloading_zone=case when current_setting('lkgroup.apply_customer_ids',true)='1' then s.unloading_zone else coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone) end
 from _lk_sync_plan p join _lk_sync_zone z using(new_receipt)
 where s.id=p.shipment_id and not coalesce(s.data_locked,false) and
  (s.receipt_number is distinct from p.new_receipt or (current_setting('lkgroup.apply_customer_ids',true) is distinct from '1' and (s.recipient_unknown is distinct from p.is_unknown or s.unloading_zone is distinct from coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone))));
 perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
 perform set_config('lkgroup.normalizing_shipments','',true); raise;
end $function$;

CREATE OR REPLACE FUNCTION public.lk_excel_receipt_plan(p_route text, p_year integer, p_voyage text)
 RETURNS TABLE(shipment_id bigint, identity_key text, old_receipt text, new_receipt text, priority integer, is_unknown boolean, is_park boolean, locked boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with rd as (select * from public.route_definitions where route_key=btrim(p_route) or display_name=btrim(p_route) order by (display_name=btrim(p_route)) desc limit 1), source as materialized (
 select s.*,m.customer_registry_id,m.customer_no,m.statement_customer_code,m.statement_code_conflict,
 public.lk_excel_customer_key(s.consignee_name,s.consignee_phone) old_key,
 null::bigint unused_delivery_id
 from public.shipments s cross join rd left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=lpad(regexp_replace(p_voyage,'[^0-9]','','g'),2,'0') and s.deleted_at is null and s.deletion_requested_at is null
 ), deliveries as materialized (
 select d.* from rd cross join lateral public.lk_excel_delivery_review_batch_scoped(rd.route_key,p_year,p_voyage,(select jsonb_agg(jsonb_build_object('name',n.consignee_name,'phone',n.consignee_phone)) from (select distinct consignee_name,consignee_phone from source)n))d
 ), keyed as materialized (
 select s.*,case when customer_no is not null then 'ID|'||customer_no||'|'||public.lk_statement_special_prefix(consignee_name)::integer else old_key end ik,
 case when public.lk_statement_special_prefix(consignee_name) then 6 when old_key='XX' then 5 when d.delivery_type='province' then 1 when d.delivery_type='city' then 2 when public.lk_is_park_seongho(consignee_name) then 4 else 3 end pri,
 coalesce(data_locked,false) or receipt_number_locked or receipt_number_override is not null fixed
 from source s left join deliveries dm on dm.name is not distinct from s.consignee_name and dm.phone is not distinct from s.consignee_phone left join jsonb_populate_recordset(null::public.local_delivery_profiles,public.lk_excel_effective_policy((select route_key from rd),p_year,p_voyage)->'deliveries') d on d.id=dm.profile_id
 ), fixed as (select ik,min(coalesce(receipt_number_override,nullif(btrim(receipt_number),''))) number from keyed where fixed group by ik)
 select s.id,case when s.customer_no is null and nullif(btrim(s.receipt_number),'') is null and s.old_key<>'XX' then '' else s.ik end,btrim(coalesce(s.receipt_number,'')),
 case when s.fixed then coalesce(s.receipt_number_override,s.receipt_number)
 when f.number is not null then f.number
 when s.statement_code_conflict then ''
 when s.customer_no is not null then btrim(rd.receipt_prefix)||' '||s.statement_customer_code
 when nullif(btrim(s.receipt_number),'') is not null then s.receipt_number
 when s.old_key='XX' then btrim(rd.receipt_prefix)||' XX' else '' end,
 s.pri,s.old_key='XX',public.lk_is_park_seongho(s.consignee_name),s.fixed
 from keyed s cross join rd left join fixed f on f.ik=s.ik;
$function$;

CREATE OR REPLACE FUNCTION public.admin_excel_statement_controls(p_route text, p_year integer, p_voyage text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rd public.route_definitions; receipts jsonb; reviews jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','staff','partner') and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.receipt_number),'[]') into receipts from (
 select s.receipt_number,string_agg(distinct s.consignee_name,' / ') name,string_agg(distinct s.consignee_phone,' / ') phone,
 array_agg(distinct public.lk_customer_display_code(m.customer_no)) filter(where m.customer_no is not null) customer_codes,
 bool_or(s.receipt_number_locked) locked,bool_or(s.data_locked) data_locked,bool_or(s.receipt_number_override is not null) manual,
 count(*) as "rows",case when public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) and count(distinct m.statement_customer_code)=1 and count(m.customer_no)=count(*) then rd.receipt_prefix||' '||min(m.statement_customer_code) end suggested_number
 from public.shipments s left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null
 group by s.receipt_number) r;
 select coalesce(jsonb_agg(jsonb_build_object('name',r.name,'phone',r.phone,'candidates',r.candidates)),'[]') into reviews
 from public.lk_excel_delivery_review_batch_scoped(rd.route_key,p_year,p_voyage,(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'phone',c.phone)),'[]') from (
 select distinct consignee_name name,consignee_phone phone from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and deleted_at is null and deletion_requested_at is null)c))r
 where r.profile_id is null and jsonb_array_length(r.candidates)>0;
 return jsonb_build_object('numbering_mode',case when public.lk_uses_customer_id_receipts(p_route,p_year,p_voyage) then 'customer_id' else 'legacy' end,'route_key',rd.route_key,'receipts',receipts,'delivery_reviews',reviews,'review_count',jsonb_array_length(reviews),'can_edit',public.current_role()='admin');
end $function$;

CREATE OR REPLACE FUNCTION public.lk_apply_excel_logic_parity_legacy_v103(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
  declare
  v_route_key text;
  v_prefix text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'
  );
begin
  select rd.route_key,rd.receipt_prefix into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;
  if coalesce(v_route_key,'')='' then perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return; end if;

  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' XX'
        else btrim(v_prefix)||'XX'
      end,
      unloading_zone='F'
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  update public.shipments s
  set recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  -- Merge only whitespace variants of the same complete name and phone.
  with grouped as (
    select
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g') full_name_key,
      right(public.normalize_phone(s.consignee_phone),8) phone_key,
      coalesce(
        min(btrim(s.receipt_number)) filter(where coalesce(s.data_locked,false)),
        min(btrim(s.receipt_number))
      ) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and btrim(coalesce(s.receipt_number,''))<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g'),
      right(public.normalize_phone(s.consignee_phone),8)
  )
  update public.shipments s
  set receipt_number=g.receipt_number,recipient_unknown=false
  from grouped g
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g')=g.full_name_key
    and right(public.normalize_phone(s.consignee_phone),8)=g.phone_key;

  -- 이우용/이*용 follows a single confirmed 이우용 receipt.
  with known as (
    select public.lk_receipt_name_key(s.consignee_name) name_key,
           min(btrim(s.receipt_number)) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and public.lk_receipt_name_key(s.consignee_name)<>''
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and coalesce(btrim(s.receipt_number),'')<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by public.lk_receipt_name_key(s.consignee_name)
    having count(distinct right(public.normalize_phone(s.consignee_phone),8))=1
       and count(distinct btrim(s.receipt_number))=1
  )
  update public.shipments s
  set receipt_number=k.receipt_number,recipient_unknown=false
  from known k
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
    and public.lk_recipient_phone_uncertain(s.consignee_phone)
    and public.lk_receipt_name_key(s.consignee_name)=k.name_key;

  update public.shipments s
  set receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' 100'
        else btrim(v_prefix)||'100'
      end,
      unloading_zone='102',recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_is_park_seongho(s.consignee_name);

  with qty as (
    select btrim(s.receipt_number) receipt,
           sum(greatest(coalesce(s.quantity,1),1))::integer total_qty
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
    group by btrim(s.receipt_number)
  )
  update public.shipments s
  set unloading_zone=case
    when public.lk_unknown_prefix_zone(s.consignee_name) then 'F'
      when public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      then 'F'
    when public.lk_is_park_seongho(s.consignee_name) then '102'
    when exists(
      select 1 from jsonb_populate_recordset(null::public.customer_zone_overrides,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'zones') z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
    ) then coalesce((
      select z.zone from jsonb_populate_recordset(null::public.customer_zone_overrides,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'zones') z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
      order by
        public.lk_name_match_rank(s.consignee_name,z.customer_name),
        case when z.route_key=v_route_key then 0 else 1 end,z.id
      limit 1
    ),'102')
    when public.lk_receipt_name_key(s.consignee_name)
           =public.normalize_person_name('김요셉')
      or lower(coalesce(s.consignee_name,'')) like '%beauty panda%'
      or coalesce(s.consignee_name,'') like '%뷰티판다%' then 'F'
    when exists(
      select 1 from jsonb_populate_recordset(null::public.local_delivery_profiles,public.lk_excel_effective_policy(v_route_key,p_year,p_voyage)->'deliveries') d
      where d.active=true and d.route_key=v_route_key
        and public.lk_delivery_candidate_rank(
          d.paid_by,d.customer_name,d.alternate_name,d.company_name,d.phone,
          s.consignee_name,s.consignee_phone
        )<9999
    ) then 'F'
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from qty q
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  update public.shipments s
  set special_note_auto=public.compute_shipment_special_note_scoped(
    s.route,p_year,p_voyage,s.consignee_name,s.consignee_phone
  )
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;
end;
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$;

-- Read the same effective policy in mobile, web and Excel export.
create function public.get_excel_workbook_policy(p_route_key text,p_year integer,p_voyage text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' and not exists(select 1 from public.profiles where id=auth.uid() and approval_status='approved' and deleted_at is null and coalesce(deletion_status,'active')='active') then raise exception 'FORBIDDEN'; end if;
 result:=public.lk_excel_effective_policy(p_route_key,p_year,p_voyage);
 result:=jsonb_set(result,'{deliveries}',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('fingerprint',public.lk_delivery_match_fingerprint(d),'display_color',result->'appearance'->>(d.delivery_type||case when public.lk_delivery_is_prepaid(d.paid_by) then '_prepaid' else '' end))) from jsonb_populate_recordset(null::public.local_delivery_profiles,result->'deliveries') d where d.active),'[]'));
 return result;
end $$;

create function public.get_excel_delivery_profile(p_route_key text,p_year integer,p_voyage text,p_name text,p_phone text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb; target bigint;
begin
 result:=public.get_excel_workbook_policy(p_route_key,p_year,p_voyage);
 target:=public.lk_excel_delivery_profile_id_scoped(p_route_key,p_year,p_voyage,p_name,p_phone);
 return (select value from jsonb_array_elements(result->'deliveries') where (value->>'id')::bigint=target limit 1);
end $$;

create function public.admin_review_excel_delivery_match_scoped(p_route_key text,p_year integer,p_voyage text,p_name text,p_phone text,p_profile_id bigint,p_fingerprint text,p_approved boolean) returns void
language plpgsql security definer set search_path='' as $$
declare d public.local_delivery_profiles; v text; reviews jsonb; nk text:=public.lk_registry_name(p_name); pk text:=public.lk_registry_phone(p_phone);
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if p_year is null or p_year not between 1900 and 2099 or coalesce(p_voyage,'')!~'^[0-9]{1,3}$' then raise exception 'INVALID_SCOPE'; end if;
 v:=lpad((p_voyage::int)::text,greatest(2,length((p_voyage::int)::text)),'0');
 if v='00' then perform public.admin_review_excel_delivery_match(p_route_key,p_name,p_phone,p_profile_id,p_fingerprint,p_approved); return; end if;
 perform pg_advisory_xact_lock(hashtextextended('excel-policy:'||p_route_key||':'||p_year||':'||v,0));
 select * into d from jsonb_populate_recordset(null::public.local_delivery_profiles,public.lk_excel_effective_policy(p_route_key,p_year,v)->'deliveries') where id=p_profile_id and active;
 if not found or public.lk_delivery_match_fingerprint(d) is distinct from p_fingerprint then raise exception 'RECORD_CHANGED'; end if;
 select coalesce(changes->'reviews','[]') into reviews from public.excel_workbook_policies where route_key=p_route_key and shipment_year=p_year and voyage=v;
 reviews:=coalesce((select jsonb_agg(case when p_approved and r->>'name_key'=nk and r->>'phone_key'=pk then r||'{"approved":false}' else r end) from jsonb_array_elements(coalesce(reviews,'[]')) r where not(r->>'name_key'=nk and r->>'phone_key'=pk and (r->>'delivery_profile_id')::bigint=p_profile_id)),'[]');
 reviews:=reviews||jsonb_build_array(jsonb_build_object('route_key',p_route_key,'name_key',nk,'phone_key',pk,'delivery_profile_id',p_profile_id,'profile_fingerprint',p_fingerprint,'approved',p_approved,'reviewed_by',auth.uid(),'reviewed_at',now()));
 insert into public.excel_workbook_policies(route_key,shipment_year,voyage,changes,updated_by) values(p_route_key,p_year,v,jsonb_build_object('reviews',reviews),auth.uid())
 on conflict(route_key,shipment_year,voyage) do update set changes=jsonb_set(excel_workbook_policies.changes,'{reviews}',reviews),updated_by=auth.uid(),updated_at=now();
 perform public.admin_finalize_excel_batch_rules((select display_name from public.route_definitions where route_key=p_route_key),p_year,v,false);
end $$;

-- Any older global refresh must still respect the voyage's overrides.
create function public.lk_protect_voyage_excel_notes() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if current_setting('lkgroup.bulk_import',true) is distinct from '1' and not coalesce(new.data_locked,false) and exists(select 1 from public.excel_workbook_policies p where p.route_key=public.route_base_key_for_label(new.route) and p.shipment_year=new.shipment_year and p.voyage=new.voyage) then
  new.special_note_auto:=public.compute_shipment_special_note_scoped(new.route,new.shipment_year,new.voyage,new.consignee_name,new.consignee_phone);
 end if;
 return new;
end $$;
create trigger zz_excel_voyage_notes before insert or update of special_note_auto,route,shipment_year,voyage,consignee_name,consignee_phone on public.shipments for each row execute function public.lk_protect_voyage_excel_notes();

create function public.lk_queue_base_policy_appearance() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.voyage='00' then
  insert into public.excel_base_sync_state(route_key) values(new.route_key) on conflict(route_key) do update set revision=nextval('public.excel_base_revision_seq'),status=case when excel_base_sync_state.lease_until>now() then 'running' else 'pending' end,requested_at=now(),retry_after=null,last_error=null;
 end if;
 return null;
end $$;
create trigger excel_base_policy_changed after insert or update on public.excel_workbook_policies for each row execute function public.lk_queue_base_policy_appearance();

revoke all on function public.lk_protect_voyage_excel_notes(),public.lk_queue_base_policy_appearance() from public,anon,authenticated;
revoke all on function public.get_excel_workbook_policy(text,integer,text),public.get_excel_delivery_profile(text,integer,text,text,text),public.admin_review_excel_delivery_match_scoped(text,integer,text,text,text,bigint,text,boolean),public.lk_excel_delivery_review_batch_scoped(text,integer,text,jsonb),public.lk_excel_delivery_profile_id_scoped(text,integer,text,text,text),public.lk_excel_delivery_matches_scoped(text,integer,text,jsonb),public.lk_excel_discount_rule_id_scoped(text,integer,text,text,text),public.compute_shipment_special_note_scoped(text,integer,text,text,text) from public,anon;
grant execute on function public.get_excel_workbook_policy(text,integer,text),public.get_excel_delivery_profile(text,integer,text,text,text),public.admin_review_excel_delivery_match_scoped(text,integer,text,text,text,bigint,text,boolean),public.lk_excel_delivery_review_batch_scoped(text,integer,text,jsonb),public.lk_excel_delivery_profile_id_scoped(text,integer,text,text,text),public.lk_excel_delivery_matches_scoped(text,integer,text,jsonb),public.lk_excel_discount_rule_id_scoped(text,integer,text,text,text),public.compute_shipment_special_note_scoped(text,integer,text,text,text) to authenticated,service_role;

comment on table public.excel_workbook_policies is 'XX/BASE/V00 updates common defaults. Route/year/voyage uploads store field differences only and never queue or modify BASE policy.';
