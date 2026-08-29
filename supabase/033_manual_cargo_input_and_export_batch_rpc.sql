-- 033_manual_cargo_input_and_export_batch_rpc.sql
create or replace function public.list_shipment_export_batches()
returns table(route text, shipment_year integer, voyage text)
language sql security definer set search_path = public
as $$
  select distinct s.route, s.shipment_year, s.voyage
  from public.shipments s
  where public.current_role() in ('admin','staff','partner')
    and coalesce(trim(s.route), '') <> ''
    and s.shipment_year is not null
    and coalesce(trim(s.voyage), '') <> ''
    and coalesce(trim(s.box_number), '') <> ''
  order by s.shipment_year desc, s.route, s.voyage desc;
$$;
grant execute on function public.list_shipment_export_batches() to authenticated;

create or replace function public.manager_check_shipment_duplicates(
  p_route text, p_year integer, p_voyage text, p_box_number text, p_invoice_number text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'), 2, '0');
  v_box boolean := false; v_invoice boolean := false;
begin
  if public.current_role() not in ('admin','staff','partner') then raise exception 'not authorized'; end if;
  if coalesce(trim(p_box_number),'') <> '' then
    select exists(select 1 from public.shipments s
      where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),2,'0')=v_voyage
      and lower(trim(coalesce(s.box_number,'')))=lower(trim(p_box_number))) into v_box;
  end if;
  if coalesce(trim(p_invoice_number),'') <> '' then
    select exists(select 1 from public.shipments s
      where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),2,'0')=v_voyage
      and lower(trim(coalesce(s.invoice_number,'')))=lower(trim(p_invoice_number))) into v_invoice;
  end if;
  return jsonb_build_object('box_duplicate',v_box,'invoice_duplicate',v_invoice);
end; $$;
grant execute on function public.manager_check_shipment_duplicates(text,integer,text,text,text) to authenticated;

create or replace function public.manager_add_manual_shipment(
  p_route text, p_year integer, p_voyage text, p_box_number text,
  p_invoice_number text default '', p_consignee_name text default '',
  p_consignee_phone text default '', p_received_at timestamptz default null,
  p_notes text default ''
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'),2,'0');
  v_id bigint;
begin
  if public.current_role() not in ('admin','staff','partner') then raise exception 'not authorized'; end if;
  if coalesce(trim(p_box_number),'')='' then raise exception 'box number required'; end if;
  if exists(select 1 from public.shipments s where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),2,'0')=v_voyage
    and lower(trim(coalesce(s.box_number,'')))=lower(trim(p_box_number)))
  then raise exception 'duplicate box number'; end if;

  insert into public.shipments(
    route,shipment_year,voyage,box_number,invoice_number,consignee_name,consignee_phone,
    received_at,notes,import_key,quantity,status
  ) values (
    trim(p_route),p_year,v_voyage,trim(p_box_number),trim(coalesce(p_invoice_number,'')),
    trim(coalesce(p_consignee_name,'')),trim(coalesce(p_consignee_phone,'')),
    p_received_at,trim(coalesce(p_notes,'')),
    trim(p_route)||'|'||p_year::text||'|'||v_voyage||'|'||trim(p_box_number),1,'registered'
  ) returning id into v_id;
  return jsonb_build_object('id',v_id);
end; $$;
grant execute on function public.manager_add_manual_shipment(text,integer,text,text,text,text,text,timestamptz,text) to authenticated;
