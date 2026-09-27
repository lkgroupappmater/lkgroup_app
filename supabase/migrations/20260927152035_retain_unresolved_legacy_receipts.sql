-- Leave unmatched legacy rows without a receipt unassigned; assign only verified IDs.
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
 select s.id,case when s.customer_no is null and nullif(btrim(s.receipt_number),'') is null and s.old_key<>'XX' then '' else s.ik end,btrim(coalesce(s.receipt_number,'')),
 case when s.fixed then coalesce(s.receipt_number_override,s.receipt_number)
 when f.number is not null then f.number
 when s.statement_code_conflict then ''
 when s.customer_no is not null then btrim(rd.receipt_prefix)||' '||s.statement_customer_code
 when nullif(btrim(s.receipt_number),'') is not null then s.receipt_number
 when s.old_key='XX' then btrim(rd.receipt_prefix)||' XX' else '' end,
 s.pri,s.old_key='XX',public.lk_is_park_seongho(s.consignee_name),s.fixed
 from keyed s cross join rd left join fixed f on f.ik=s.ik;
$$;
