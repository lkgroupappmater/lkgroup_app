-- A small catalog of registered voyages; never return cargo or storage paths.
create or replace function public.list_excel_file_batches()
returns table(route_key text, route_label text, shipment_year integer, voyage text,
  has_voyage_template boolean, has_base_template boolean)
language sql stable security invoker set search_path = public, pg_temp
as $$
  with batches as (
    select coalesce(d.route_key,s.route) as route_key, s.route as route_label,
      s.shipment_year,s.voyage
    from public.shipments s
    left join public.route_definitions d on d.display_name=s.route or d.route_key=s.route
    where public.current_role() in ('admin','staff','partner')
      and s.deleted_at is null and s.deletion_requested_at is null
      and coalesce(trim(s.box_number),'')<>'' and coalesce(trim(s.route),'')<>''
      and s.shipment_year is not null and coalesce(trim(s.voyage),'')<>''
      and s.voyage !~ '^(V)?0+$' and d.deleted_at is null
    union
    select t.route_key,t.route_label,t.shipment_year,t.voyage
    from public.shipment_excel_templates t
    left join public.route_definitions d on d.route_key=t.route_key
    where public.current_role() in ('admin','staff','partner')
      and coalesce(trim(t.voyage),'')<>'' and t.voyage !~ '^(V)?0+$'
      and d.deleted_at is null
  )
  select b.route_key,b.route_label,b.shipment_year,b.voyage,
    exists(select 1 from public.shipment_excel_templates t where t.route_key=b.route_key
      and t.shipment_year=b.shipment_year and t.voyage=b.voyage),
    exists(select 1 from public.shipment_excel_base_templates t where t.route_key=b.route_key and t.active)
  from batches b order by b.shipment_year desc,b.route_label,b.voyage desc;
$$;
revoke all on function public.list_excel_file_batches() from public,anon;
grant execute on function public.list_excel_file_batches() to authenticated;
