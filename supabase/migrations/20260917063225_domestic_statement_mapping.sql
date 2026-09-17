-- Reuse the existing delivery table and reconcile the two earlier link contracts.
alter table public.domestic_parcels
 add column if not exists reference_type text,
 add column if not exists reference_number text;

alter table public.domestic_parcels drop constraint domestic_parcels_link_scope_check;
alter table public.domestic_parcels add constraint domestic_parcels_link_scope_check check (
 (link_scope='cargo' and shipment_id is not null)
 or (link_scope='statement' and shipment_id is null
  and num_nonnulls(link_route,link_year,link_voyage,link_receipt_number)=4
  and length(btrim(link_route)) between 1 and 160 and link_year between 1900 and 2200
  and length(btrim(link_voyage)) between 1 and 40 and length(btrim(link_receipt_number)) between 1 and 80)
 or (link_scope='standalone' and shipment_id is null)
 or (link_scope='reference' and shipment_id is null
  and reference_type in ('ecommerce','local') and reference_type is not null
  and reference_number is not null and reference_number ~ '^[A-Z0-9][A-Z0-9./_-]{0,79}$')
);
alter table public.domestic_parcels add constraint domestic_reference_complete check (
 (link_scope='reference' and num_nonnulls(reference_type,reference_number)=2)
 or (link_scope<>'reference' and num_nonnulls(reference_type,reference_number)=0)
);

-- Preserve either earlier representation without discarding waybills or photos.
update public.domestic_parcels set link_scope='statement',link_route=statement_route,
 link_year=statement_year,link_voyage=statement_voyage,link_receipt_number=statement_receipt
 where statement_route is not null and link_scope<>'statement';
update public.domestic_parcels set statement_route=link_route,statement_year=link_year,
 statement_voyage=link_voyage,statement_receipt=link_receipt_number
 where link_scope='statement' and statement_route is null;

create index domestic_parcels_reference_idx on public.domestic_parcels
 (reference_type,reference_number,created_at,id) where link_scope='reference';
create index domestic_parcels_link_statement_idx on public.domestic_parcels
 (link_route,link_year,link_voyage,public.domestic_receipt_key(link_receipt_number))
 where link_scope='statement';

-- Only the authenticated Edge Function service may call these internal helpers.
-- receipt_only prevents a supplier invoice from being mistaken for an LK receipt.
create function public.domestic_find_delivery_cargo(p_number text,p_route text default null,
 p_year integer default null,p_voyage text default null,p_receipt_only boolean default false)
returns table(id bigint,box_number text,invoice_number text,receipt_number text,route text,
 shipment_year integer,voyage text,customer_id uuid,consignee_name text,consignee_phone text)
language sql stable security invoker set search_path='' as $$
 select s.id,s.box_number,s.invoice_number,s.receipt_number,s.route,s.shipment_year,s.voyage,
  s.customer_id,s.consignee_name,s.consignee_phone
 from public.shipments s
 where s.deleted_at is null and s.deletion_requested_at is null
 and (p_route is null or s.route=p_route) and (p_year is null or s.shipment_year=p_year)
 and (p_voyage is null or public.domestic_receipt_key(s.voyage)=public.domestic_receipt_key(p_voyage))
 and (public.domestic_receipt_key(s.receipt_number)=public.domestic_receipt_key(p_number)
  or (p_receipt_only and p_route is not null and p_year is not null and p_voyage is not null
   and public.domestic_receipt_key(p_number) ~ '^[0-9]+$'
   and regexp_replace(public.domestic_receipt_key(s.receipt_number),'^[A-Z]+','')=public.domestic_receipt_key(p_number))
  or (not p_receipt_only and (upper(btrim(s.box_number))=upper(btrim(p_number))
   or upper(btrim(s.invoice_number))=upper(btrim(p_number)))))
 order by s.id limit 501;
$$;
create or replace function public.domestic_parcels_for_statement(p_route text,p_year integer,p_voyage text,p_receipt text)
returns setof public.domestic_parcels
language sql stable security invoker set search_path='' as $$
 select p.* from public.domestic_parcels p
 where (coalesce(p.link_route,p.statement_route)=p_route
  and coalesce(p.link_year,p.statement_year)=p_year
  and public.domestic_receipt_key(coalesce(p.link_voyage,p.statement_voyage))=public.domestic_receipt_key(p_voyage)
  and public.domestic_receipt_key(coalesce(p.link_receipt_number,p.statement_receipt))=public.domestic_receipt_key(p_receipt))
 or exists(select 1 from public.shipments s where s.id=p.shipment_id
  and s.route=p_route and s.shipment_year=p_year
  and public.domestic_receipt_key(s.voyage)=public.domestic_receipt_key(p_voyage)
  and public.domestic_receipt_key(s.receipt_number)=public.domestic_receipt_key(p_receipt)
  and s.deleted_at is null and s.deletion_requested_at is null)
 order by p.created_at,p.id;
$$;
revoke all on function public.domestic_find_delivery_cargo(text,text,integer,text,boolean) from public,anon,authenticated;
revoke all on function public.domestic_parcels_for_statement(text,integer,text,text) from public,anon,authenticated;
grant execute on function public.domestic_find_delivery_cargo(text,text,integer,text,boolean) to service_role;
grant execute on function public.domestic_parcels_for_statement(text,integer,text,text) to service_role;
