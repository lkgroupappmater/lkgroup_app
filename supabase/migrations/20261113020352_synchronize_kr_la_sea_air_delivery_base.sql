-- Common Korea-to-Laos sea/air delivery defaults. Apply once to the shared Supabase project.
-- Full backup stays in the private schema; no customer records are stored in Git.
select pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
create schema if not exists lk_private;
create table if not exists lk_private.delivery_base_backups (
 migration text primary key, saved_at timestamptz not null default now(), payload jsonb not null
);
alter table lk_private.delivery_base_backups enable row level security;
revoke all on lk_private.delivery_base_backups from public, anon, authenticated;
insert into lk_private.delivery_base_backups(migration,payload)
select '20261111_kr_la_shared_delivery',jsonb_build_object(
 'profiles',(select jsonb_agg(to_jsonb(d)) from public.local_delivery_profiles d where route_key in ('kr_la_sea','kr_la_air')),
 'policies',(select jsonb_agg(to_jsonb(p)) from public.excel_workbook_policies p where route_key in ('kr_la_sea','kr_la_air')),
 'reviews',(select jsonb_agg(to_jsonb(r)) from public.excel_delivery_match_reviews r where route_key in ('kr_la_sea','kr_la_air')))
on conflict do nothing;

-- Serialize BASE imports, voyage comparisons and direct admin edits in the same order.
select pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));

create or replace function lk_private.delivery_identity(r jsonb) returns text
language sql immutable set search_path='' as $$
 select coalesce(r->>'delivery_type','province')||'|'||public.lk_registry_name(r->>'customer_name')||'|'||public.lk_registry_phone(r->>'phone');
$$;
revoke all on function lk_private.delivery_identity(jsonb) from public,anon,authenticated;

-- Reconcile by full customer identity, never by the old route-local row number.
create temporary table lk_delivery_old on commit drop as
 select d.*,lk_private.delivery_identity(to_jsonb(d)) as identity_key
 from public.local_delivery_profiles d where route_key=any(array['kr_la_sea','kr_la_air']);
create temporary table lk_delivery_common (identity_key text primary key, data jsonb not null, new_no integer unique) on commit drop;
insert into lk_delivery_common(identity_key,data)
 select distinct on(identity_key) identity_key,to_jsonb(d)-'identity_key'
 from lk_delivery_old d order by identity_key,updated_at desc,case route_key when 'kr_la_sea' then 0 when 'kr_la_air' then 1 else 2 end,id;
do $$
declare r record; n integer;
begin
 for r in select * from lk_delivery_common order by case data->>'route_key' when 'kr_la_sea' then 0 when 'kr_la_air' then 1 else 2 end,(data->>'source_no')::int,identity_key loop
  n:=(r.data->>'source_no')::int;
  if r.data->>'delivery_type'='city' and n<10000 then n:=n+10000; end if;
  if exists(select 1 from lk_delivery_common where new_no=n) then
   select coalesce(max(new_no),case when r.data->>'delivery_type'='city' then 10000 else 0 end)+1 into n from lk_delivery_common where data->>'delivery_type'=r.data->>'delivery_type';
  end if;
  update lk_delivery_common set new_no=n,data=data||jsonb_build_object('source_no',n,'original_source_no',case when r.data->>'delivery_type'='city' then n-10000 else n end,'source_sheet',case when r.data->>'delivery_type'='city' then '시내배송' else '지방배송' end) where identity_key=r.identity_key;
 end loop;
end $$;
-- Keep the existing per-route IDs so approved matching references remain attached.
update public.local_delivery_profiles d set source_no=-d.id::integer
where d.route_key=any(array['kr_la_sea','kr_la_air']);
update public.local_delivery_profiles d set source_no=r.source_no,original_source_no=r.original_source_no,source_sheet=r.source_sheet,source_row=r.source_row,customer_name=r.customer_name,alternate_name=r.alternate_name,company_name=r.company_name,phone=r.phone,phone_display=r.phone_display,delivery_type=r.delivery_type,local_company=r.local_company,destination_address=r.destination_address,paid_by=r.paid_by,notes=r.notes,preferred=r.preferred,active=r.active,updated_at=now() from lk_delivery_old o join lk_delivery_common c using(identity_key) cross join lateral jsonb_populate_record(null::public.local_delivery_profiles,c.data) r where d.id=o.id;
insert into public.local_delivery_profiles(route_key,source_no,original_source_no,source_sheet,source_row,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred,active) select target,r.source_no,r.original_source_no,r.source_sheet,r.source_row,r.customer_name,r.alternate_name,r.company_name,r.phone,r.phone_display,r.delivery_type,r.local_company,r.destination_address,r.paid_by,r.notes,r.preferred,r.active from lk_delivery_common c cross join unnest(array['kr_la_sea','kr_la_air']) target cross join lateral jsonb_populate_record(null::public.local_delivery_profiles,c.data) r where not exists(select 1 from public.local_delivery_profiles d where d.route_key=target and d.source_no=r.source_no);

-- Move existing voyage deltas with the customer when its BASE number changes.
-- All non-delivery voyage overrides remain byte-for-byte unchanged.
do $$
declare p record; e record; oldrow record; c record; outmap jsonb; k text; v jsonb;
begin
 for p in select * from public.excel_workbook_policies where voyage<>'00' and route_key=any(array['kr_la_sea','kr_la_air']) and jsonb_typeof(changes->'deliveries')='object' loop
  outmap:='{}';
  for e in select * from jsonb_each(p.changes->'deliveries') loop
   k:=e.key;v:=e.value;
   select * into oldrow from lk_delivery_old o where o.route_key=p.route_key and public.lk_excel_policy_key('deliveries',to_jsonb(o))=e.key;
   if found then
    select * into c from lk_delivery_common where identity_key=oldrow.identity_key;
    k:=public.lk_excel_policy_key('deliveries',c.data);
    if v?'identity' then v:=jsonb_set(v,'{identity}',(v->'identity')||jsonb_build_object('source_no',c.new_no)); end if;
    if v->'patch'?'source_no' then v:=jsonb_set(v,'{patch,source_no}',to_jsonb(c.new_no)); end if;
    if v->'patch'?'original_source_no' then v:=jsonb_set(v,'{patch,original_source_no}',c.data->'original_source_no'); end if;
   end if;
   if outmap?k then raise exception 'Delivery override identity conflict; migration rolled back'; end if;
   outmap:=outmap||jsonb_build_object(k,v);
  end loop;
  update public.excel_workbook_policies set changes=jsonb_set(changes,'{deliveries}',outmap) where route_key=p.route_key and shipment_year=p.shipment_year and voyage=p.voyage;
 end loop;
end $$;
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

CREATE OR REPLACE FUNCTION public.import_excel_workbook_policy(p_route_key text, p_year integer, p_voyage text, p_file_name text, p_rules jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v text; y integer; baseline jsonb; changes jsonb; kind text; delta jsonb; appearance jsonb; field record;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
 if p_year is null or p_rules is null or p_year not between 1900 and 2099 or coalesce(p_voyage,'')!~'^[0-9]{1,3}$' or not exists(select 1 from public.route_definitions where route_key=p_route_key and deleted_at is null) or jsonb_typeof(p_rules)<>'object' then raise exception '운송 경로·연도·항차·규칙 형식을 확인하세요.'; end if;
 v:=lpad((p_voyage::int)::text,greatest(2,length((p_voyage::int)::text)),'0');y:=case when v='00' then 0 else p_year end;
 if v='00' and coalesce(p_file_name,'')!~*'(^|[^a-z0-9])(base|v?xx|v0{1,3})([^a-z0-9]|$)|xx\s*항차|0{1,3}\s*항차|기본' then raise exception '공통 기본값은 XX/BASE/V00 엑셀로만 변경할 수 있습니다.'; end if;
 if v='00' and coalesce(p_file_name,'')~*'(^|[^a-z0-9])v(oyage)?[ _-]*0*[1-9][0-9]*([^0-9]|$)|(^|[^0-9])0*[1-9][0-9]*[[:space:]]*항차' then raise exception '항차 파일은 BASE로 저장할 수 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
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
end $function$;


create or replace function lk_private.lock_common_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
 return null;
end $$;
revoke all on function lk_private.lock_common_delivery() from public,anon,authenticated;
create trigger a_common_delivery_lock before insert or update or delete on public.local_delivery_profiles
for each statement execute function lk_private.lock_common_delivery();

create trigger a_common_delivery_policy_lock before insert or update or delete on public.excel_workbook_policies
for each statement execute function lk_private.lock_common_delivery();

create or replace function lk_private.mirror_common_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
declare target text; source public.local_delivery_profiles;
begin
 if pg_trigger_depth()>1 then return null; end if;
 if tg_op='DELETE' then source:=old; else source:=new; end if;
 if not(source.route_key=any(array['kr_la_sea','kr_la_air'])) then return null; end if;
 if auth.uid() is not null and not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active' and deleted_at is null) then raise exception '총괄 관리자 권한이 필요합니다.' using errcode='42501'; end if;
 if tg_op='UPDATE' and old.route_key<>new.route_key then raise exception '공통 배송정보의 경로는 변경할 수 없습니다.'; end if;
 foreach target in array array['kr_la_sea','kr_la_air'] loop
  if target=source.route_key then continue; end if;
  if tg_op='DELETE' then
   delete from public.local_delivery_profiles where route_key=target and source_no=old.source_no;
  else
   if tg_op='UPDATE' and old.source_no<>new.source_no then
    update public.local_delivery_profiles set source_no=new.source_no where route_key=target and source_no=old.source_no;
   end if;
   insert into public.local_delivery_profiles(route_key,source_no,original_source_no,source_sheet,source_row,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred,active)
   values(target,source.source_no,source.original_source_no,source.source_sheet,source.source_row,source.customer_name,source.alternate_name,source.company_name,source.phone,source.phone_display,source.delivery_type,source.local_company,source.destination_address,source.paid_by,source.notes,source.preferred,source.active)
   on conflict(route_key,source_no) do update set original_source_no=excluded.original_source_no,source_sheet=excluded.source_sheet,source_row=excluded.source_row,customer_name=excluded.customer_name,alternate_name=excluded.alternate_name,company_name=excluded.company_name,phone=excluded.phone,phone_display=excluded.phone_display,delivery_type=excluded.delivery_type,local_company=excluded.local_company,destination_address=excluded.destination_address,paid_by=excluded.paid_by,notes=excluded.notes,preferred=excluded.preferred,active=excluded.active,updated_at=now();
  end if;
 end loop;
 return null;
end $$;
revoke all on function lk_private.mirror_common_delivery() from public,anon,authenticated;
create trigger common_delivery_mirror after insert or update or delete on public.local_delivery_profiles
for each row execute function lk_private.mirror_common_delivery();

create or replace function lk_private.mirror_common_delivery_colors() returns trigger
language plpgsql security definer set search_path='' as $$
declare colors jsonb; target text;
begin
 if pg_trigger_depth()>1 or new.voyage<>'00' or not(new.route_key=any(array['kr_la_sea','kr_la_air'])) then return null; end if;
 select coalesce(jsonb_object_agg(key,value),'{}') into colors from jsonb_each(coalesce(new.changes->'appearance','{}')) where key in ('province','province_prepaid','city','city_prepaid');
 if colors='{}'::jsonb then return null; end if;
 perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));
 foreach target in array array['kr_la_sea','kr_la_air'] loop
  if target=new.route_key then continue; end if;
  insert into public.excel_workbook_policies(route_key,shipment_year,voyage,changes,source_file_name,updated_by)
  values(target,0,'00',jsonb_build_object('appearance',colors),'Shared local delivery colors',new.updated_by)
  on conflict(route_key,shipment_year,voyage) do update
  set changes=jsonb_set(public.excel_workbook_policies.changes,'{appearance}',coalesce(public.excel_workbook_policies.changes->'appearance','{}')||colors),updated_at=now();
 end loop;
 return null;
end $$;
revoke all on function lk_private.mirror_common_delivery_colors() from public,anon,authenticated;
create trigger common_delivery_colors after insert or update on public.excel_workbook_policies
for each row execute function lk_private.mirror_common_delivery_colors();
-- Reuse the latest BASE colors through the same path used by future imports.
update public.excel_workbook_policies set changes=changes where (route_key,shipment_year,voyage)=(
 select route_key,shipment_year,voyage from public.excel_workbook_policies where voyage='00' and route_key=any(array['kr_la_sea','kr_la_air']) order by updated_at desc limit 1
);

-- Preserve existing RPC privileges. The internal implementation is already
-- owner-only; authenticated/service_role access to import_excel_workbook_policy
-- remains unchanged by CREATE OR REPLACE FUNCTION.
-- Existing public RPC keeps the same signature for installed app and website clients.
notify pgrst, 'reload schema';
