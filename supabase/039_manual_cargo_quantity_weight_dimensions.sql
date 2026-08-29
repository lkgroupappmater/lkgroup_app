-- 039_manual_cargo_quantity_weight_dimensions.sql
-- 화물 추가 입력에서 수량/중량/L/W/H를 저장하도록 RPC 확장.

drop function if exists public.manager_add_manual_shipment(
  text, integer, text, text, text, text, text, timestamptz, text
);

create or replace function public.manager_add_manual_shipment(
  p_route text,
  p_year integer,
  p_voyage text,
  p_box_number text,
  p_invoice_number text default '',
  p_consignee_name text default '',
  p_consignee_phone text default '',
  p_received_at timestamptz default null,
  p_notes text default '',
  p_quantity integer default 1,
  p_weight_kg numeric default null,
  p_length_cm numeric default null,
  p_width_cm numeric default null,
  p_height_cm numeric default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'),
    2,
    '0'
  );
  v_id bigint;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  if coalesce(trim(p_box_number),'') = '' then
    raise exception 'box number required';
  end if;

  if coalesce(p_quantity, 0) <= 0 then
    raise exception 'quantity must be at least 1';
  end if;

  if exists(
    select 1
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and lpad(
        regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
        2,
        '0'
      ) = v_voyage
      and lower(trim(coalesce(s.box_number,''))) =
          lower(trim(p_box_number))
  ) then
    raise exception 'duplicate box number';
  end if;

  insert into public.shipments(
    route,
    shipment_year,
    voyage,
    box_number,
    invoice_number,
    consignee_name,
    consignee_phone,
    received_at,
    notes,
    import_key,
    quantity,
    weight_kg,
    length_cm,
    width_cm,
    height_cm,
    status
  ) values (
    trim(p_route),
    p_year,
    v_voyage,
    trim(p_box_number),
    trim(coalesce(p_invoice_number,'')),
    trim(coalesce(p_consignee_name,'')),
    trim(coalesce(p_consignee_phone,'')),
    p_received_at,
    trim(coalesce(p_notes,'')),
    trim(p_route)||'|'||p_year::text||'|'||v_voyage||'|'||trim(p_box_number),
    p_quantity,
    p_weight_kg,
    p_length_cm,
    p_width_cm,
    p_height_cm,
    'registered'
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

grant execute on function public.manager_add_manual_shipment(
  text, integer, text, text, text, text, text, timestamptz, text,
  integer, numeric, numeric, numeric, numeric
) to authenticated;
