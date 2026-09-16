-- Additive statement links; existing cargo links, waybills and photos remain intact.
alter table public.domestic_parcels
 add column statement_route text,
 add column statement_year integer,
 add column statement_voyage text,
 add column statement_receipt text,
 add constraint domestic_statement_link_complete check (
  num_nonnulls(statement_route,statement_year,statement_voyage,statement_receipt)=0 or
  (num_nonnulls(statement_route,statement_year,statement_voyage,statement_receipt)=4
   and shipment_id is null and length(statement_route) between 1 and 160
   and statement_year between 1900 and 2200 and length(statement_voyage) between 1 and 40
   and length(statement_receipt) between 1 and 80));

create function public.domestic_receipt_key(p_value text) returns text
language plpgsql immutable strict set search_path='' as $$
declare v text; m text[];
begin
 v:=upper(regexp_replace(trim(p_value),'\s','','g'));
 m:=regexp_match(v,'^([A-Z]*)([0-9]+)$');
 if m is null then return v; end if;
 return m[1]||coalesce(nullif(ltrim(m[2],'0'),''),'0');
end $$;
create index domestic_parcels_statement_idx on public.domestic_parcels
 (statement_route,statement_year,statement_voyage,public.domestic_receipt_key(statement_receipt))
 where statement_route is not null;
-- Existing shipment editing continues without depending on a privileged helper.
create index shipments_domestic_receipt_idx on public.shipments
 (route,shipment_year,voyage,receipt_number)
 where deleted_at is null and deletion_requested_at is null;

create function public.domestic_tracking_batches()
returns table(route text,shipment_year integer,voyage text)
language sql stable security invoker set search_path='' as $$
 select distinct s.route,s.shipment_year,s.voyage from public.shipments s
 where s.deleted_at is null and s.deletion_requested_at is null
 and s.route is not null and s.shipment_year is not null and s.voyage is not null
 order by s.route,s.shipment_year desc,s.voyage desc;
$$;

create function public.domestic_statement_cargo(p_route text,p_year integer,p_voyage text,p_receipt text)
returns table(id bigint,box_number text,route text,shipment_year integer,voyage text,
 receipt_number text,customer_id uuid,consignee_name text,consignee_phone text)
language sql stable security invoker set search_path='' as $$
 select s.id,s.box_number,s.route,s.shipment_year,s.voyage,s.receipt_number,
 s.customer_id,s.consignee_name,s.consignee_phone from public.shipments s
 where s.route=p_route and s.shipment_year=p_year and s.voyage=p_voyage
 and s.deleted_at is null and s.deletion_requested_at is null
 and (public.domestic_receipt_key(s.receipt_number)=public.domestic_receipt_key(p_receipt)
 or (public.domestic_receipt_key(p_receipt) ~ '^[0-9]+$' and
 regexp_replace(public.domestic_receipt_key(s.receipt_number),'^[A-Z]+','')=public.domestic_receipt_key(p_receipt)))
 order by s.id;
$$;

create function public.domestic_parcels_for_statement(p_route text,p_year integer,p_voyage text,p_receipt text)
returns setof public.domestic_parcels
language sql stable security invoker set search_path='' as $$
 select p.* from public.domestic_parcels p
 where (p.statement_route=p_route and p.statement_year=p_year and p.statement_voyage=p_voyage
 and public.domestic_receipt_key(p.statement_receipt)=public.domestic_receipt_key(p_receipt))
 or exists(select 1 from public.shipments s where s.id=p.shipment_id
 and s.route=p_route and s.shipment_year=p_year and s.voyage=p_voyage
 and public.domestic_receipt_key(s.receipt_number)=public.domestic_receipt_key(p_receipt)
 and s.deleted_at is null and s.deletion_requested_at is null)
 order by p.created_at,p.id;
$$;

revoke all on function public.domestic_receipt_key(text) from public,anon,authenticated;
revoke all on function public.domestic_tracking_batches() from public,anon,authenticated;
revoke all on function public.domestic_statement_cargo(text,integer,text,text) from public,anon,authenticated;
revoke all on function public.domestic_parcels_for_statement(text,integer,text,text) from public,anon,authenticated;
grant execute on function public.domestic_receipt_key(text) to service_role;
grant execute on function public.domestic_tracking_batches() to service_role;
grant execute on function public.domestic_statement_cargo(text,integer,text,text) to service_role;
grant execute on function public.domestic_parcels_for_statement(text,integer,text,text) to service_role;
