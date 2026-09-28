-- Reuse reviewed canonical identity without changing customer or shipment data.
-- A full name/phone registry pair (or saved alias) must resolve unambiguously.
-- Identity alone confirms a delivery only when this route has one profile for it.
create or replace function public.lk_excel_delivery_review_batch(p_route_key text,p_customers jsonb)
returns table(name text,phone text,profile_id bigint,candidates jsonb)
language sql stable set search_path='' as $$
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
 from public.local_delivery_profiles d left join identities k
 on k.nk=public.lk_registry_name(public.lk_customer_base_name(d.customer_name)) and k.pk=public.lk_registry_phone(coalesce(nullif(d.phone_display,''),d.phone))
 where d.active and d.route_key=p_route_key
 ), matched as materialized (
 select i.name,i.phone,p.id,p.customer_name,p.alternate_name,p.phone_display,p.phone profile_phone,p.delivery_type,p.local_company,p.destination_address,p.fingerprint,p.preferred,p.source_row,p.source_no,
 r.approved,i.nk=any(p.names) exact_name,i.phones&&p.phones phone_match,
 coalesce(i.customer_id=p.customer_id,false) same_customer,
 coalesce(i.customer_id=p.customer_id and p.customer_profile_count=1,false) unique_customer,
 exists(select 1 from unnest(p.names) n where length(i.nk)>=2 and length(n)>=2 and (position(i.nk in n)>0 or position(n in i.nk)>0)) partial_name
 from inputs i cross join profiles p left join public.excel_delivery_match_reviews r
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
$$;
revoke all on function public.lk_excel_delivery_review_batch(text,jsonb) from public,anon,authenticated;
grant execute on function public.lk_excel_delivery_review_batch(text,jsonb) to service_role;
