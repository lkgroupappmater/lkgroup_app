-- Read-only consistency: follow reviewed aliases after rename/merge, and display canonical IDs in waybill candidates.
create or replace function public.customer_registry_match(p_name text,p_phone text,p_unknown boolean default false) returns uuid
language plpgsql stable security invoker set search_path='' as $$
declare n text:=public.lk_customer_base_name(p_name); nk text; pk text:=public.lk_registry_phone(p_phone); found uuid[]; first_name text;
begin
 if n is null then return null; end if; nk:=public.lk_registry_name(n);
 -- Exact name + full phone (or a reviewed alias) takes priority over namesakes.
 select array_agg(distinct r.id) into found from public.customer_registry r
 where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'
 and ((r.name_key=nk and r.phone_key=pk) or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=r.id and a.name_key=nk and a.phone_key=pk));
 if cardinality(found)=1 then return found[1]; elsif cardinality(found)>1 then return null; end if;
 if not p_unknown then return null; end if;
 -- Unknown-prefixed cargo follows a unique full suffix name. Phone differences remain reviewable.
 select array_agg(distinct r.id) into found from public.customer_registry r where r.merged_into is null and (r.name_key=nk or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=r.id and a.name_key=nk)) and r.name !~ '수취인[[:space:]]*불명';
 if cardinality(found)=1 then return found[1]; elsif cardinality(found)>1 then return null; end if;
 -- A/B stays intact when registered as such. Otherwise the first explicit name
 -- after the prefix may match, but only with the same complete phone number.
 first_name:=public.lk_registry_name(split_part(n,'/',1));
 if first_name<>nk and length(pk)>=8 then
  select array_agg(distinct r.id) into found from public.customer_registry r where r.merged_into is null and r.name_key=first_name and r.phone_key=pk and r.name !~ '수취인[[:space:]]*불명';
  if cardinality(found)=1 then return found[1]; end if;
 end if;
 return null;
end $$;
revoke all on function public.customer_registry_match(text,text,boolean) from public,anon,authenticated;
grant execute on function public.customer_registry_match(text,text,boolean) to service_role;


create or replace function public.waybill_recipient_candidates(p_name text,p_phone text) returns jsonb
language sql stable security invoker set search_path='' as $$
 with keys as (select public.lk_registry_name(p_name) n,public.lk_registry_phone(p_phone) p), matched as (
 select s.*,r.customer_no,k.n,k.p,public.lk_registry_name(s.consignee_name) nk,public.lk_registry_phone(s.consignee_phone) pk
 from public.shipments s cross join keys k
 left join public.customer_registry_sources l on l.source_kind='shipment' and l.source_id=s.id::text
 left join public.customer_registry r on r.id=case when s.consignee_name ~ '수취인[[:space:]]*불명' then public.customer_registry_match(s.consignee_name,s.consignee_phone,true) else l.customer_registry_id end
 where s.deleted_at is null and s.deletion_requested_at is null
 and ((k.n<>'' and public.lk_registry_name(s.consignee_name)=k.n) or (length(k.p)>=8 and public.lk_registry_phone(s.consignee_phone)=k.p))
 ), grouped as (
 select distinct on (route,shipment_year,voyage,coalesce(nullif(receipt_number,''),id::text),nk,pk) * from matched
 order by route,shipment_year,voyage,coalesce(nullif(receipt_number,''),id::text),nk,pk,id
 ), output as (
 select jsonb_build_object('exact',n<>'' and p<>'' and n=nk and p=pk,'customer_no',customer_no,
 'receiver_name',consignee_name,'receiver_phone',consignee_phone,
 'link_scope',case when nullif(receipt_number,'') is null then 'cargo' else 'statement' end,
 'shipment_id',case when nullif(receipt_number,'') is null then id else null end,
 'statement',case when nullif(receipt_number,'') is not null then jsonb_build_object('route',route,'shipment_year',shipment_year,'voyage',voyage,'receipt_number',receipt_number) else null end,
 'label',concat_ws(' · ',case when customer_no is not null then lpad(customer_no::text,greatest(3,length(customer_no::text)),'0') end,consignee_name,consignee_phone,route,shipment_year,voyage,coalesce(nullif(receipt_number,''),box_number))) item
 from grouped order by (n<>'' and p<>'' and n=nk and p=pk) desc,shipment_year desc,voyage desc,id desc limit 100
 ) select coalesce(jsonb_agg(item),'[]'::jsonb) from output;
$$;
revoke all on function public.waybill_recipient_candidates(text,text) from public,anon,authenticated;
grant execute on function public.waybill_recipient_candidates(text,text) to service_role;


create or replace view public.customer_registry_statement_mapping with (security_invoker=true) as
select s.id shipment_id,s.route,s.shipment_year,s.voyage,s.receipt_number current_receipt_number,s.consignee_name source_name,s.consignee_phone source_phone,
 r.id customer_registry_id,r.customer_no,r.name customer_name,r.phone customer_phone,
 public.lk_customer_statement_code(r.customer_no,false) customer_code,
 s.consignee_name ~ '수취인[[:space:]]*불명' is_unknown_name,
 public.lk_customer_statement_code(r.customer_no,s.consignee_name ~ '수취인[[:space:]]*불명') statement_customer_code,
 coalesce(s.consignee_name ~ '수취인[[:space:]]*불명' and exists(select 1 from public.customer_registry c where c.merged_into is null and c.name !~ '수취인[[:space:]]*불명' and c.customer_no::text=public.lk_customer_statement_code(r.customer_no,true)),false) statement_code_conflict
from public.shipments s left join public.customer_registry_sources l on l.source_kind='shipment' and l.source_id=s.id::text
left join public.customer_registry r on r.id=case when s.consignee_name ~ '수취인[[:space:]]*불명' then public.customer_registry_match(s.consignee_name,s.consignee_phone,true) else l.customer_registry_id end and r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'
where s.deleted_at is null and s.deletion_requested_at is null;
revoke all on public.customer_registry_statement_mapping from public,anon,authenticated;
grant select on public.customer_registry_statement_mapping to service_role;
