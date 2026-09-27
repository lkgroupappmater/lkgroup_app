create or replace function public.lk_excel_delivery_review_batch(p_route_key text,p_customers jsonb)
returns table(name text,phone text,profile_id bigint,candidates jsonb)
language sql stable set search_path='' as $$
 with inputs as materialized (
 select distinct x->>'name' name,x->>'phone' phone,public.lk_registry_name(public.lk_customer_base_name(x->>'name')) nk,
 public.lk_registry_name(x->>'name') source_nk,public.lk_registry_phone(x->>'phone') pk,public.lk_delivery_phone_tokens(x->>'phone') phones
 from jsonb_array_elements(coalesce(p_customers,'[]')) x
 ), profiles as materialized (
 select d.*,public.lk_delivery_match_fingerprint(d) fingerprint,
 array_remove(array[nullif(public.lk_registry_name(customer_name),''),nullif(public.lk_registry_name(alternate_name),''),nullif(public.lk_registry_name(company_name),'')],null) names,
 public.lk_delivery_phone_tokens(coalesce(nullif(phone_display,''),d.phone)) phones
 from public.local_delivery_profiles d where active and route_key=p_route_key
 ), matched as materialized (
 select i.name,i.phone,p.id,p.customer_name,p.alternate_name,p.phone_display,p.phone profile_phone,p.delivery_type,p.local_company,p.destination_address,p.fingerprint,p.preferred,p.source_row,p.source_no,
 r.approved,i.nk=any(p.names) exact_name,i.phones&&p.phones phone_match,
 exists(select 1 from unnest(p.names) n where length(i.nk)>=2 and length(n)>=2 and (position(i.nk in n)>0 or position(n in i.nk)>0)) partial_name
 from inputs i cross join profiles p left join public.excel_delivery_match_reviews r
 on r.route_key=p_route_key and r.name_key=i.source_nk and r.phone_key=i.pk and r.delivery_profile_id=p.id and r.profile_fingerprint=p.fingerprint
 where i.nk<>''
 ), ranked as materialized (
 select m.*,row_number() over(partition by name,phone order by (approved is true) desc,(exact_name and phone_match) desc,phone_match desc,exact_name desc,id) rn
 from matched m where approved is distinct from false and (exact_name or phone_match or partial_name or approved is true)
 ), confirmed as (
 select distinct on(name,phone) name,phone,id from ranked where approved is true or(exact_name and phone_match)
 order by name,phone,(approved is true) desc,(delivery_type='province') desc,preferred desc,coalesce(source_row,source_no,0) desc,id desc
 ), lists as (
 select name,phone,jsonb_agg(jsonb_build_object('id',id,'name',customer_name,'receiver',alternate_name,'phone',coalesce(nullif(phone_display,''),profile_phone),'type',delivery_type,'company',local_company,'address',destination_address,'fingerprint',fingerprint,'reason',case when exact_name and phone_match then '이름·연락처 일치' when phone_match then '연락처 일치 · 이름 확인 필요' when exact_name then '이름 일치 · 연락처 확인 필요' else '이름 일부 유사 · 확인 필요' end) order by rn) candidates
 from ranked where rn<=20 group by name,phone
 )
 select i.name,i.phone,c.id,coalesce(l.candidates,'[]'::jsonb) from inputs i left join confirmed c on c.name is not distinct from i.name and c.phone is not distinct from i.phone left join lists l on l.name is not distinct from i.name and l.phone is not distinct from i.phone;
$$;
revoke all on function public.lk_excel_delivery_review_batch(text,jsonb) from public,anon,authenticated;
grant execute on function public.lk_excel_delivery_review_batch(text,jsonb) to service_role;
create or replace function public.lk_excel_delivery_profile_id(p_route_key text,p_shipment_name text,p_shipment_phone text) returns bigint
language sql stable security definer set search_path='' as $$
 select profile_id from public.lk_excel_delivery_review_batch(p_route_key,jsonb_build_array(jsonb_build_object('name',p_shipment_name,'phone',p_shipment_phone))) limit 1;
$$;
create or replace function public.lk_excel_delivery_candidates(p_route_key text,p_name text,p_phone text) returns jsonb
language sql stable set search_path='' as $$
 select candidates from public.lk_excel_delivery_review_batch(p_route_key,jsonb_build_array(jsonb_build_object('name',p_name,'phone',p_phone))) limit 1;
$$;

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
 select coalesce(jsonb_agg(jsonb_build_object('name',r.name,'phone',r.phone,'candidates',r.candidates)),'[]') into reviews
 from public.lk_excel_delivery_review_batch(rd.route_key,(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'phone',c.phone)),'[]') from (
 select distinct consignee_name name,consignee_phone phone from public.shipments where route=rd.display_name and shipment_year=p_year and voyage=p_voyage and deleted_at is null and deletion_requested_at is null)c))r
 where r.profile_id is null and jsonb_array_length(r.candidates)>0;
 return jsonb_build_object('route_key',rd.route_key,'receipts',receipts,'delivery_reviews',reviews,'review_count',jsonb_array_length(reviews),'can_edit',public.current_role()='admin');
end $$;
create or replace function public.lk_excel_receipt_plan(p_route text,p_year integer,p_voyage text)
returns table(shipment_id bigint,identity_key text,old_receipt text,new_receipt text,priority integer,is_unknown boolean,is_park boolean,locked boolean)
language sql stable set search_path='' as $$
 with rd as (select * from public.route_definitions where route_key=btrim(p_route) or display_name=btrim(p_route) order by (display_name=btrim(p_route)) desc limit 1), source as materialized (
 select s.*,m.customer_registry_id,m.customer_no,m.statement_customer_code,m.statement_code_conflict,
 public.lk_excel_customer_key(s.consignee_name,s.consignee_phone) old_key,
 null::bigint unused_delivery_id
 from public.shipments s cross join rd left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
 where s.route=rd.display_name and s.shipment_year=p_year and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=lpad(regexp_replace(p_voyage,'[^0-9]','','g'),2,'0') and s.deleted_at is null and s.deletion_requested_at is null
 ), deliveries as materialized (
 select d.* from rd cross join lateral public.lk_excel_delivery_review_batch(rd.route_key,(select jsonb_agg(jsonb_build_object('name',n.consignee_name,'phone',n.consignee_phone)) from (select distinct consignee_name,consignee_phone from source)n))d
 ), keyed as materialized (
 select s.*,case when customer_no is not null then 'ID|'||customer_no||'|'||public.lk_statement_special_prefix(consignee_name)::integer else old_key end ik,
 case when public.lk_statement_special_prefix(consignee_name) then 6 when old_key='XX' then 5 when d.delivery_type='province' then 1 when d.delivery_type='city' then 2 when public.lk_is_park_seongho(consignee_name) then 4 else 3 end pri,
 coalesce(data_locked,false) or receipt_number_locked or receipt_number_override is not null fixed
 from source s left join deliveries dm on dm.name is not distinct from s.consignee_name and dm.phone is not distinct from s.consignee_phone left join public.local_delivery_profiles d on d.id=dm.profile_id
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
