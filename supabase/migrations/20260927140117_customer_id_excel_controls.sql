-- Customer identity display and independent statement controls. No money/rate changes.
create or replace function public.lk_customer_display_code(p_number bigint) returns text
language sql immutable set search_path='' as $$
 select case when p_number>0 then 'LK '||lpad(p_number::text,greatest(5,length(p_number::text)),'0') end;
$$;
create or replace function public.lk_statement_special_prefix(p_name text) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(btrim(split_part(p_name,'/',1)) ~* '^(수취인[[:space:]]*불명|비엔티엔[[:space:]]*픽업|시내[[:space:]]*픽업|운임[[:space:]]*따로[[:space:]]*지불)$' and position('/' in p_name)>0,false);
$$;
create or replace function public.lk_customer_base_name(v text) returns text
language plpgsql immutable set search_path='' as $$
declare n text:=btrim(coalesce(v,''));
begin
 if public.lk_statement_special_prefix(n) then n:=btrim(substr(n,position('/' in n)+1));
 elsif n ~ '수취인[[:space:]]*불명' then return null; end if;
 if n='' or n ~ '[?*＊？]' or public.lk_registry_name(n) in ('수취인불명','미상','unknown','불명') or n !~ '[[:alnum:]가-힣ກ-ໝ]' then return null; end if;
 return n;
end $$;
create or replace function public.lk_customer_statement_code(p_number bigint,p_unknown boolean) returns text
language sql immutable set search_path='' as $$
 select case when p_number>0 then case when coalesce(p_unknown,false) then '9' else '' end||lpad(p_number::text,greatest(5,length(p_number::text)),'0') end;
$$;

create or replace function public.lk_delivery_phone_tokens(v text) returns text[]
language sql immutable set search_path='' as $$
 select coalesce(array_agg(distinct p order by p),'{}'::text[]) from
 (select public.lk_registry_phone(t) p from regexp_split_to_table(coalesce(v,''),'[/,;|\r\n]+') t) q
 where length(p) between 8 and 15;
$$;
create or replace function public.lk_delivery_match_fingerprint(d public.local_delivery_profiles) returns text
language sql immutable set search_path='' as $$
 select md5(jsonb_build_array(d.customer_name,d.alternate_name,d.company_name,d.phone,d.phone_display,d.delivery_type,d.local_company,d.destination_address,d.paid_by,d.active)::text);
$$;
create table public.excel_delivery_match_reviews (
 route_key text not null references public.route_definitions(route_key),
 name_key text not null, phone_key text not null,
 delivery_profile_id bigint not null references public.local_delivery_profiles(id) on delete cascade,
 profile_fingerprint text not null, approved boolean not null,
 reviewed_by uuid not null references public.profiles(id), reviewed_at timestamptz not null default now(),
 primary key(route_key,name_key,phone_key,delivery_profile_id)
);
alter table public.excel_delivery_match_reviews enable row level security;
revoke all on public.excel_delivery_match_reviews from anon,authenticated;
grant all on public.excel_delivery_match_reviews to service_role;

-- Partial names and a phone alone are candidates, never confirmed delivery assignments.
create or replace function public.lk_excel_delivery_profile_id(p_route_key text,p_shipment_name text,p_shipment_phone text) returns bigint
language sql stable security definer set search_path='' as $$
 with n as (select public.lk_registry_name(public.lk_customer_base_name(p_shipment_name)) nk,
 public.lk_registry_name(p_shipment_name) source_nk,public.lk_registry_phone(p_shipment_phone) pk,
 public.lk_delivery_phone_tokens(p_shipment_phone) phones), candidates as (
 select d.*,r.approved,
 exists(select 1 from unnest(array[d.customer_name,d.alternate_name,d.company_name]) x
 where public.lk_registry_name(x)<>'' and public.lk_registry_name(x)=n.nk) exact_name,
 public.lk_delivery_phone_tokens(coalesce(nullif(d.phone_display,''),d.phone)) && n.phones phone_match
 from public.local_delivery_profiles d cross join n
 left join public.excel_delivery_match_reviews r on r.route_key=d.route_key and r.name_key=n.source_nk and r.phone_key=n.pk
 and r.delivery_profile_id=d.id and r.profile_fingerprint=public.lk_delivery_match_fingerprint(d)
 where d.active and d.route_key=p_route_key and n.nk<>''
 ), valid as (select * from candidates where approved is true or (approved is null and exact_name and phone_match))
 select id from valid order by (approved is true) desc,(delivery_type='province') desc,preferred desc,coalesce(source_row,source_no,0) desc,id desc limit 1;
$$;
revoke all on function public.lk_excel_delivery_profile_id(text,text,text) from public,anon;
grant execute on function public.lk_excel_delivery_profile_id(text,text,text) to authenticated,service_role;

create or replace function public.admin_review_excel_delivery_match(p_route_key text,p_name text,p_phone text,p_profile_id bigint,p_fingerprint text,p_approved boolean) returns void
language plpgsql security definer set search_path='' as $$
declare d public.local_delivery_profiles;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into d from public.local_delivery_profiles where id=p_profile_id and route_key=p_route_key and active for update;
 if not found or public.lk_delivery_match_fingerprint(d) is distinct from p_fingerprint then raise exception 'RECORD_CHANGED'; end if;
 if p_approved then
  update public.excel_delivery_match_reviews set approved=false,reviewed_by=auth.uid(),reviewed_at=now()
  where route_key=p_route_key and name_key=public.lk_registry_name(p_name) and phone_key=public.lk_registry_phone(p_phone);
 end if;
 insert into public.excel_delivery_match_reviews values(p_route_key,public.lk_registry_name(p_name),public.lk_registry_phone(p_phone),d.id,p_fingerprint,p_approved,auth.uid(),now())
 on conflict(route_key,name_key,phone_key,delivery_profile_id) do update set profile_fingerprint=excluded.profile_fingerprint,approved=excluded.approved,reviewed_by=excluded.reviewed_by,reviewed_at=excluded.reviewed_at;
 -- Names, customer IDs and monetary data are never merged by a delivery confirmation.
 update public.shipments s set special_note_auto=public.compute_shipment_special_note(s.route,s.consignee_name,s.consignee_phone)
 where s.route=(select display_name from public.route_definitions where route_key=p_route_key) and public.lk_registry_name(s.consignee_name)=public.lk_registry_name(p_name) and public.lk_registry_phone(s.consignee_phone)=public.lk_registry_phone(p_phone) and s.deleted_at is null and not s.data_locked;
end $$;
revoke all on function public.admin_review_excel_delivery_match(text,text,text,bigint,text,boolean) from public,anon;
grant execute on function public.admin_review_excel_delivery_match(text,text,text,bigint,text,boolean) to authenticated;

alter table public.shipments add column receipt_number_locked boolean not null default false;
alter table public.shipments add column receipt_number_override text;
create table public.shipment_receipt_aliases (
 shipment_id bigint not null references public.shipments(id) on delete cascade,
 receipt_number text not null, created_at timestamptz not null default now(),
 primary key(shipment_id,receipt_number)
);
alter table public.shipment_receipt_aliases enable row level security;
revoke all on public.shipment_receipt_aliases from anon,authenticated;
grant all on public.shipment_receipt_aliases to service_role;
create or replace function lk_private.protect_statement_number() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.receipt_number is distinct from old.receipt_number then
  if (old.receipt_number_locked or exists(select 1 from public.shipments s where s.route=old.route and s.shipment_year=old.shipment_year and s.voyage=old.voyage and s.receipt_number=old.receipt_number and s.receipt_number_locked and s.deleted_at is null)) and current_setting('lkgroup.statement_control',true) is distinct from '1' then raise exception '명세서 번호가 잠겨 있습니다. 번호 잠금을 먼저 해제하세요.'; end if;
  if current_setting('lkgroup.normalizing_shipments',true) is distinct from '1' then new.receipt_number_override:=new.receipt_number; end if;
  if nullif(btrim(old.receipt_number),'') is not null then
   insert into public.shipment_receipt_aliases(shipment_id,receipt_number) values(old.id,old.receipt_number) on conflict do nothing;
  end if;
 end if;
 return new;
end $$;
revoke all on function lk_private.protect_statement_number() from public;
create trigger shipments_protect_statement_number before update of receipt_number on public.shipments for each row execute function lk_private.protect_statement_number();

create or replace function public.admin_set_statement_control(p_route text,p_year integer,p_voyage text,p_receipt text,p_number text default null,p_locked boolean default null,p_manual boolean default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rd public.route_definitions; target text:=btrim(coalesce(p_number,p_receipt)); ids bigint[]; affected integer;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rd.route_key||'|'||p_year||'|'||p_voyage,0));
 perform 1 from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt and deleted_at is null for update;
 select array_agg(id) into ids from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt and deleted_at is null and deletion_requested_at is null;
 if cardinality(ids) is null then raise exception 'RECORD_CHANGED'; end if;
 if p_manual is false then
  select case when count(distinct m.statement_customer_code)=1 and count(m.customer_no)=count(*) then rd.receipt_prefix||' '||min(m.statement_customer_code) end into target
  from public.customer_registry_statement_mapping m where m.shipment_id=any(ids);
  if target is null then raise exception '고객 ID 연결을 먼저 확인하세요.'; end if;
 end if;
 if target='' or length(target)>80 or target !~ '^[A-Za-z0-9][A-Za-z0-9 _-]*$' then raise exception 'INVALID_RECEIPT'; end if;
 if target is distinct from p_receipt then
  if exists(select 1 from public.shipments where id=any(ids) and (data_locked or receipt_number_locked)) then raise exception '번호 또는 자료 잠금을 먼저 해제하세요.'; end if;
  if exists(select 1 from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=target and not(id=any(ids)) and deleted_at is null) then raise exception 'DUPLICATE_RECEIPT'; end if;
  if exists(select 1 from public.receipt_discount_overrides where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage and receipt_number=target)
   or exists(select 1 from public.receipt_extra_costs where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=target) then raise exception '대상 번호에 연결된 할인·추가비용을 먼저 확인하세요.'; end if;
 end if;
 perform set_config('lkgroup.normalizing_shipments','1',true);
 insert into public.shipment_automation_history(route_key,shipment_year,voyage,receipt_mapping,prior_snapshots)
 values(rd.route_key,p_year,p_voyage,(select jsonb_agg(jsonb_build_object('shipment_id',id,'old_receipt',receipt_number,'new_receipt',target,'prior_locked',receipt_number_locked,'prior_override',receipt_number_override)) from public.shipments where id=any(ids)),case when target is distinct from p_receipt then coalesce((select jsonb_agg(to_jsonb(v)) from public.voyage_settlement_snapshots v where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage),'[]') else '[]'::jsonb end);
 if target is distinct from p_receipt then
  update public.receipt_extra_costs set receipt_number=target where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt;
  update public.receipt_discount_overrides set receipt_number=target where route_key=rd.route_key and shipment_year=p_year and voyage=p_voyage and receipt_number=p_receipt;
  update public.domestic_parcels set statement_receipt=target where statement_route=rd.display_name and statement_year=p_year and statement_voyage=p_voyage and statement_receipt=p_receipt;
  update public.domestic_parcels set link_receipt_number=target where link_route=rd.display_name and link_year=p_year and link_voyage=p_voyage and link_receipt_number=p_receipt;
  delete from public.voyage_settlement_snapshots where route_key in(rd.route_key,rd.display_name) and shipment_year=p_year and voyage=p_voyage;
 end if;
 update public.shipments set receipt_number=target,receipt_number_locked=coalesce(p_locked,receipt_number_locked),
 receipt_number_override=case when p_manual is false then null when p_manual is true or target is distinct from p_receipt then target else receipt_number_override end where id=any(ids);
 get diagnostics affected=row_count;
 perform set_config('lkgroup.normalizing_shipments','',true);
 return jsonb_build_object('rows',affected,'receipt_number',target);
end $$;
revoke all on function public.admin_set_statement_control(text,integer,text,text,text,boolean,boolean) from public,anon;
grant execute on function public.admin_set_statement_control(text,integer,text,text,text,boolean,boolean) to authenticated;

create or replace function public.lk_excel_delivery_candidates(p_route_key text,p_name text,p_phone text) returns jsonb
language sql stable set search_path='' as $$
 with n as (select public.lk_registry_name(public.lk_customer_base_name(p_name)) nk,public.lk_delivery_phone_tokens(p_phone) phones), matched as (
 select d.*,public.lk_delivery_match_fingerprint(d) fingerprint,
 exists(select 1 from unnest(array[d.customer_name,d.alternate_name,d.company_name]) x where public.lk_registry_name(x)<>'' and public.lk_registry_name(x)=n.nk) exact_name,
 public.lk_delivery_phone_tokens(coalesce(nullif(d.phone_display,''),d.phone)) && n.phones phone_match,
 exists(select 1 from unnest(array[d.customer_name,d.alternate_name,d.company_name]) x where length(n.nk)>=2 and length(public.lk_registry_name(x))>=2 and (position(n.nk in public.lk_registry_name(x))>0 or position(public.lk_registry_name(x) in n.nk)>0)) partial_name
 from public.local_delivery_profiles d cross join n where d.route_key=p_route_key and d.active and n.nk<>''
 ), candidates as (
 select d.* from matched d where (exact_name or phone_match or partial_name) and not exists(
 select 1 from public.excel_delivery_match_reviews r where r.route_key=p_route_key and r.name_key=public.lk_registry_name(p_name) and r.phone_key=public.lk_registry_phone(p_phone) and r.delivery_profile_id=d.id and r.profile_fingerprint=d.fingerprint and not r.approved)
 order by (exact_name and phone_match) desc,phone_match desc,exact_name desc,id limit 20)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',customer_name,'receiver',alternate_name,'phone',coalesce(nullif(phone_display,''),phone),'type',delivery_type,'company',local_company,'address',destination_address,'fingerprint',fingerprint,'reason',case when exact_name and phone_match then '이름·연락처 일치' when phone_match then '연락처 일치 · 이름 확인 필요' when exact_name then '이름 일치 · 연락처 확인 필요' else '이름 일부 유사 · 확인 필요' end)),'[]') from candidates;
$$;
revoke all on function public.lk_excel_delivery_candidates(text,text,text) from public,anon,authenticated;
grant execute on function public.lk_excel_delivery_candidates(text,text,text) to service_role;

create or replace function public.admin_excel_statement_controls(p_route text,p_year integer,p_voyage text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rd public.route_definitions; receipts jsonb; reviews jsonb;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','staff','partner') and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.receipt_number),'[]') into receipts from (
 select s.receipt_number,string_agg(distinct s.consignee_name,' / ') name,string_agg(distinct s.consignee_phone,' / ') phone,
 array_agg(distinct public.lk_customer_display_code(m.customer_no)) filter(where m.customer_no is not null) customer_codes,
 bool_or(s.receipt_number_locked) locked,bool_or(s.data_locked) data_locked,bool_or(s.receipt_number_override is not null) manual,
 count(*) as "rows",case when count(distinct m.statement_customer_code)=1 and count(m.customer_no)=count(*) then rd.receipt_prefix||' '||min(m.statement_customer_code) end suggested_number
 from public.shipments s left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null
 group by s.receipt_number) r;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]') into reviews from (
 select c.*,public.lk_excel_delivery_candidates(rd.route_key,c.name,c.phone) candidates from (
 select distinct consignee_name name,consignee_phone phone from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and deleted_at is null and deletion_requested_at is null)c
 where public.lk_excel_delivery_profile_id(rd.route_key,c.name,c.phone) is null)r where jsonb_array_length(r.candidates)>0;
 return jsonb_build_object('route_key',rd.route_key,'receipts',receipts,'delivery_reviews',reviews,'review_count',jsonb_array_length(reviews),'can_edit',public.current_role()='admin');
end $$;
revoke all on function public.admin_excel_statement_controls(text,integer,text) from public,anon;
grant execute on function public.admin_excel_statement_controls(text,integer,text) to authenticated;

create or replace function public.admin_set_statement_controls(p_route text,p_year integer,p_voyage text,p_receipts jsonb,p_locked boolean) returns integer
language plpgsql security definer set search_path='' as $$
declare item jsonb; affected integer:=0;
begin
 if jsonb_typeof(p_receipts)<>'array' or jsonb_array_length(p_receipts) not between 1 and 500 then raise exception 'INVALID_SELECTION'; end if;
 for item in select distinct value from jsonb_array_elements(p_receipts) order by value loop
  perform public.admin_set_statement_control(p_route,p_year,p_voyage,item#>>'{}',null,p_locked,null);
  affected:=affected+1;
 end loop;
 return affected;
end $$;
revoke all on function public.admin_set_statement_controls(text,integer,text,jsonb,boolean) from public,anon;
grant execute on function public.admin_set_statement_controls(text,integer,text,jsonb,boolean) to authenticated;

create or replace view public.customer_registry_statement_mapping with (security_invoker=true) as
select s.id shipment_id,s.route,s.shipment_year,s.voyage,s.receipt_number current_receipt_number,s.consignee_name source_name,s.consignee_phone source_phone,
 r.id customer_registry_id,r.customer_no,r.name customer_name,r.phone customer_phone,
 public.lk_customer_statement_code(r.customer_no,false) customer_code,
 s.consignee_name ~ '수취인[[:space:]]*불명' is_unknown_name,
 public.lk_customer_statement_code(r.customer_no,public.lk_statement_special_prefix(s.consignee_name)) statement_customer_code,
 coalesce(public.lk_statement_special_prefix(s.consignee_name) and exists(select 1 from public.customer_registry c where c.merged_into is null and c.name !~ '수취인[[:space:]]*불명' and public.lk_customer_statement_code(c.customer_no,false)=public.lk_customer_statement_code(r.customer_no,true)),false) statement_code_conflict
from public.shipments s left join public.customer_registry_sources l on l.source_kind='shipment' and l.source_id=s.id::text
left join public.customer_registry r on r.id=case when public.lk_statement_special_prefix(s.consignee_name) then public.customer_registry_match(s.consignee_name,s.consignee_phone,true) else l.customer_registry_id end and r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'
where s.deleted_at is null and s.deletion_requested_at is null;
revoke all on public.customer_registry_statement_mapping from public,anon,authenticated;
grant select on public.customer_registry_statement_mapping to service_role;


create or replace function public.lk_excel_receipt_plan(p_route text,p_year integer,p_voyage text)
returns table(shipment_id bigint,identity_key text,old_receipt text,new_receipt text,priority integer,is_unknown boolean,is_park boolean,locked boolean)
language sql stable set search_path='' as $$
 with rd as (select * from public.route_definitions where route_key=btrim(p_route) or display_name=btrim(p_route) order by (display_name=btrim(p_route)) desc limit 1), source as materialized (
 select s.*,m.customer_registry_id,m.customer_no,m.statement_customer_code,m.statement_code_conflict,
 public.lk_excel_customer_key(s.consignee_name,s.consignee_phone) old_key,
 public.lk_excel_delivery_profile_id(rd.route_key,s.consignee_name,s.consignee_phone) delivery_id
 from public.shipments s cross join rd left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=lpad(regexp_replace(p_voyage,'[^0-9]','','g'),2,'0') and s.deleted_at is null and s.deletion_requested_at is null
 ), keyed as materialized (
 select s.*,case when customer_no is not null then 'ID|'||customer_no||'|'||public.lk_statement_special_prefix(consignee_name)::integer else old_key end ik,
 case when public.lk_statement_special_prefix(consignee_name) then 6 when old_key='XX' then 5 when d.delivery_type='province' then 1 when d.delivery_type='city' then 2 when public.lk_is_park_seongho(consignee_name) then 4 else 3 end pri,
 coalesce(data_locked,false) or receipt_number_locked or receipt_number_override is not null fixed
 from source s left join public.local_delivery_profiles d on d.id=s.delivery_id
 ), fixed as (select ik,min(coalesce(receipt_number_override,nullif(btrim(receipt_number),''))) number from keyed where fixed group by ik)
 select s.id,s.ik,btrim(coalesce(s.receipt_number,'')),
 case when s.fixed then coalesce(s.receipt_number_override,s.receipt_number)
 when f.number is not null then f.number
 when s.statement_code_conflict then ''
 when s.customer_no is not null then btrim(rd.receipt_prefix)||' '||s.statement_customer_code
 when nullif(btrim(s.receipt_number),'') is not null then s.receipt_number
 when s.old_key='XX' then btrim(rd.receipt_prefix)||' XX' else '' end,
 s.pri,s.old_key='XX',public.lk_is_park_seongho(s.consignee_name),s.fixed
 from keyed s cross join rd left join fixed f on f.ik=s.ik;
$$;

CREATE OR REPLACE FUNCTION public.normalize_shipment_batch(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rk text; label text; v text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'); changed boolean;
begin
 if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
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
     when public.lk_excel_delivery_profile_id(rk,g.name,g.phone) is not null then 'F'
     when z.zone is not null then z.zone
     when g.qty>=20 then 'F' when g.qty>=10 then 'C' when g.qty>=5 then 'B' else 'A' end zone
 from g left join lateral (
   select o.zone from public.customer_zone_overrides o
   where o.active and o.route_key in (rk,'all') and public.lk_excel_name(o.customer_name)<>'' and public.lk_excel_match_name(g.name,g.phone)<>''
    and (position(public.lk_excel_name(o.customer_name) in public.lk_excel_match_name(g.name,g.phone))>0
      or position(public.lk_excel_match_name(g.name,g.phone) in public.lk_excel_name(o.customer_name))>0)
   order by (o.route_key=rk) desc,o.id desc limit 1
 ) z on true;
 update public.shipments s set receipt_number=p.new_receipt,recipient_unknown=p.is_unknown,unloading_zone=coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone)
 from _lk_sync_plan p join _lk_sync_zone z using(new_receipt)
 where s.id=p.shipment_id and not coalesce(s.data_locked,false) and
  (s.receipt_number is distinct from p.new_receipt or s.recipient_unknown is distinct from p.is_unknown or s.unloading_zone is distinct from coalesce(nullif(btrim(s.unloading_zone_override),''), case when btrim(s.unloading_zone) not in ('','A','B','C','F','102') then btrim(s.unloading_zone) end, z.zone));
 perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
 perform set_config('lkgroup.normalizing_shipments','',true); raise;
end $function$;


create or replace function public.admin_apply_customer_id_receipts(p_route text,p_year integer,p_voyage text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') and coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'FORBIDDEN'; end if;
 perform set_config('lkgroup.apply_customer_ids','1',true);
 perform public.normalize_shipment_batch(p_route,p_year,p_voyage);
 perform set_config('lkgroup.apply_customer_ids','',true);
end $$;
revoke all on function public.admin_apply_customer_id_receipts(text,integer,text) from public,anon;
grant execute on function public.admin_apply_customer_id_receipts(text,integer,text) to authenticated,service_role;

create or replace function public.admin_register_excel_customers(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; n text; p text; target uuid; created integer:=0;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>5000 then raise exception 'INVALID_CUSTOMERS'; end if;
 perform pg_advisory_xact_lock(7092601);
 for item in select value from jsonb_array_elements(p_rows) loop
  n:=public.lk_customer_base_name(item->>'name');p:=coalesce(item->>'phone','');
  if n is null or length(n)>200 or length(p)>200 or public.lk_statement_special_prefix(item->>'name') then continue; end if;
  target:=public.customer_registry_match(n,p,false);
  if target is null then
   insert into public.customer_registry(name,phone) values(n,p) returning id into target;
   insert into public.customer_registry_aliases values(public.lk_registry_name(n),public.lk_registry_phone(p),target,now()) on conflict do nothing;
   created:=created+1;
  end if;
 end loop;
 return jsonb_build_object('created',created);
end $$;
revoke all on function public.admin_register_excel_customers(jsonb) from public,anon;
grant execute on function public.admin_register_excel_customers(jsonb) to authenticated;

create or replace function public.lk_excel_identity_context(p_route_key text) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object(
 'customers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'customer_no',customer_no,'name',name,'phone',phone,'name_key',name_key,'phone_key',phone_key) order by customer_no),'[]') from public.customer_registry where merged_into is null and name !~ '수취인[[:space:]]*불명'),
 'sources',(select coalesce(jsonb_agg(jsonb_build_object('customer_no',m.customer_no,'source_name',m.source_name,'source_phone',m.source_phone)),'[]') from public.customer_registry_statement_mapping m join public.route_definitions rd on rd.display_name=m.route where rd.route_key=p_route_key and m.customer_no is not null),
 'aliases',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.customer_registry_aliases a join public.customer_registry r on r.id=a.customer_registry_id where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'),
 'deliveries',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('fingerprint',public.lk_delivery_match_fingerprint(d)) order by source_row,id),'[]') from public.local_delivery_profiles d where active and route_key=p_route_key),
 'reviews',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.excel_delivery_match_reviews r where route_key=p_route_key));
$$;
revoke all on function public.lk_excel_identity_context(text) from public,anon,authenticated;
grant execute on function public.lk_excel_identity_context(text) to service_role;

-- Workbook lock choices follow the existing Excel correction approval boundary.
create table public.excel_statement_pending_controls (
 request_id bigint primary key references public.shipment_change_requests(id) on delete cascade,
 target_receipt text not null, locked boolean not null, manual_number text,
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), applied_at timestamptz
);
alter table public.excel_statement_pending_controls enable row level security;
revoke all on public.excel_statement_pending_controls from anon,authenticated;
grant all on public.excel_statement_pending_controls to service_role;
create or replace function lk_private.apply_approved_statement_control() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.excel_statement_pending_controls;
begin
 if new.status='approved' and old.status is distinct from new.status then
  select * into c from public.excel_statement_pending_controls where request_id=new.id and applied_at is null;
  if found then
   update public.shipments set receipt_number_locked=c.locked,receipt_number_override=c.manual_number
   where id=new.shipment_id and receipt_number=c.target_receipt;
   if found then update public.excel_statement_pending_controls set applied_at=now() where request_id=new.id; end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function lk_private.apply_approved_statement_control() from public;
create trigger apply_approved_statement_control after update of status on public.shipment_change_requests for each row execute function lk_private.apply_approved_statement_control();

create or replace function public.admin_import_excel_statement_controls(p_route text,p_year integer,p_voyage text,p_controls jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; rd public.route_definitions; n bigint; special boolean; current_number text; target text; baseline jsonb; ids bigint[]; request_count integer; applied integer:=0; pending integer:=0;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_controls)<>'array' or jsonb_array_length(p_controls)>1000 then raise exception 'INVALID_CONTROLS'; end if;
 if p_voyage='00' then return jsonb_build_object('applied',0,'pending',0); end if;
 select * into rd from public.route_definitions where route_key=p_route or display_name=p_route order by (route_key=p_route) desc limit 1;
 if rd.route_key is null then raise exception 'INVALID_ROUTE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(rd.route_key||'|'||p_year||'|'||p_voyage,0));
 for item in select value from jsonb_array_elements(p_controls) loop
  if coalesce(item->>'key','') !~ '^ID\|[0-9]+\|[01]$' then raise exception 'INVALID_CUSTOMER_KEY'; end if;
  n:=split_part(item->>'key','|',2)::bigint;special:=split_part(item->>'key','|',3)='1';baseline:=item->'baseline';
  select array_agg(s.id),case when count(distinct s.receipt_number)=1 then min(s.receipt_number) end into ids,current_number
  from public.shipments s join public.customer_registry_statement_mapping m on m.shipment_id=s.id
  where s.route=rd.display_name and s.shipment_year=p_year and s.voyage=p_voyage and s.deleted_at is null and s.deletion_requested_at is null and m.customer_no=n and public.lk_statement_special_prefix(s.consignee_name)=special;
  if cardinality(ids) is null then continue; end if;
  if current_number is null then raise exception '같은 고객 ID에 여러 명세서가 있습니다. 앱·웹에서 번호별로 확인하세요.'; end if;
  target:=case when (item->>'locked')::boolean then nullif(btrim(item->>'fixed'),'') else coalesce(nullif(btrim(item->>'manual'),''),rd.receipt_prefix||' '||public.lk_customer_statement_code(n,special)) end;
  if target is null or target !~ '^[A-Za-z0-9][A-Za-z0-9 _-]*$' or length(target)>80 then raise exception 'INVALID_RECEIPT'; end if;
  if current_number is distinct from baseline->>'receipt_number' and current_number is distinct from target then raise exception 'RECORD_CHANGED'; end if;
  if current_number=target then
   perform public.admin_set_statement_control(rd.display_name,p_year,p_voyage,current_number,null,(item->>'locked')::boolean,null);
   update public.shipments set receipt_number_override=nullif(btrim(item->>'manual'),'') where id=any(ids);
   applied:=applied+1;
  else
   -- An explicitly requested unlock must precede approving a new receipt.
   if not (item->>'locked')::boolean and coalesce((baseline->>'locked')::boolean,false) then perform public.admin_set_statement_control(rd.display_name,p_year,p_voyage,current_number,null,false,null); end if;
   insert into public.excel_statement_pending_controls(request_id,target_receipt,locked,manual_number,created_by)
   select q.id,target,(item->>'locked')::boolean,nullif(btrim(item->>'manual'),''),auth.uid() from public.shipment_change_requests q
   where q.shipment_id=any(ids) and q.status='pending' and q.request_source='excel_import' and q.changes->>'receipt_number'=target
   on conflict(request_id) do update set target_receipt=excluded.target_receipt,locked=excluded.locked,manual_number=excluded.manual_number,created_by=excluded.created_by,created_at=now(),applied_at=null;
   get diagnostics request_count=row_count;
   if request_count=0 then raise exception '명세서 번호 변경 승인을 먼저 확인하세요.'; end if;
   pending:=pending+1;
  end if;
 end loop;
 return jsonb_build_object('applied',applied,'pending',pending);
end $$;
revoke all on function public.admin_import_excel_statement_controls(text,integer,text,jsonb) from public,anon;
grant execute on function public.admin_import_excel_statement_controls(text,integer,text,jsonb) to authenticated;
