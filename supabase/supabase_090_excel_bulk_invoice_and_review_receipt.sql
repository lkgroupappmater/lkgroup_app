-- 090_excel_bulk_invoice_and_review_receipt.sql
-- Patch155 DB support

-- ------------------------------------------------------------
-- 1. Excel bulk update: invoice number editable
-- ------------------------------------------------------------
drop function if exists public.admin_excel_bulk_update(
  bigint,text,text,text,text,text,text,text
);
drop function if exists public.admin_excel_bulk_update(
  bigint,text,text,text,text,text,text
);

create or replace function public.admin_excel_bulk_update(
  p_shipment_id bigint,
  p_box_number text,
  p_invoice_number text,
  p_sender_name text,
  p_consignee_name text,
  p_consignee_phone text,
  p_receipt_number text,
  p_unloading_zone text,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_row public.shipments%rowtype;
  next_key text;
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  select * into current_row
  from public.shipments
  where id = p_shipment_id;

  if not found then
    raise exception '화물을 찾을 수 없습니다.';
  end if;

  if nullif(btrim(p_box_number), '') is null then
    raise exception '화물번호는 비워둘 수 없습니다.';
  end if;

  if exists (
    select 1
    from public.shipments s
    where s.id <> p_shipment_id
      and s.route = current_row.route
      and s.shipment_year = current_row.shipment_year
      and s.voyage = current_row.voyage
      and s.box_number = btrim(p_box_number)
      and s.deletion_requested_at is null
  ) then
    raise exception '같은 항차에 이미 존재하는 화물번호입니다.';
  end if;

  next_key :=
    current_row.route || '|' ||
    coalesce(current_row.shipment_year::text, '') || '|' ||
    current_row.voyage || '|' ||
    btrim(p_box_number);

  update public.shipments
  set box_number = btrim(p_box_number),
      import_key = next_key,
      invoice_number = coalesce(p_invoice_number, ''),
      sender_name = coalesce(p_sender_name, ''),
      consignee_name = coalesce(p_consignee_name, ''),
      consignee_phone = coalesce(p_consignee_phone, ''),
      receipt_number = coalesce(p_receipt_number, ''),
      unloading_zone = coalesce(p_unloading_zone, ''),
      notes = coalesce(p_notes, ''),
      updated_at = now()
  where id = p_shipment_id;
end;
$$;

revoke all on function public.admin_excel_bulk_update(
  bigint,text,text,text,text,text,text,text,text
) from public;
grant execute on function public.admin_excel_bulk_update(
  bigint,text,text,text,text,text,text,text,text
) to authenticated, service_role;

-- ------------------------------------------------------------
-- 2. Receipt duplicate check + next receipt recommendation
-- Same shipment's current receipt is not considered a duplicate.
-- Existing receipt used by other shipment(s) is warned.
-- ------------------------------------------------------------
create or replace function public.admin_check_receipt_number(
  p_shipment_id text,
  p_receipt_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.shipments%rowtype;
  v_receipt text := btrim(coalesce(p_receipt_number,''));
  v_duplicate boolean := false;
  v_prefix text;
  v_max integer := 0;
  v_suggested text := '';
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자 권한이 필요합니다.';
  end if;

  select *
  into v_row
  from public.shipments s
  where s.id::text = btrim(p_shipment_id)
  limit 1;

  if not found then
    raise exception '화물을 찾을 수 없습니다.';
  end if;

  if v_receipt = '' or v_receipt = coalesce(v_row.receipt_number,'') then
    return jsonb_build_object('duplicate',false,'suggested_receipt','');
  end if;

  select exists(
    select 1
    from public.shipments s
    where s.id::text <> v_row.id::text
      and s.route = v_row.route
      and s.shipment_year = v_row.shipment_year
      and s.voyage = v_row.voyage
      and btrim(coalesce(s.receipt_number,'')) = v_receipt
      and s.deletion_requested_at is null
  ) into v_duplicate;

  if not v_duplicate then
    return jsonb_build_object('duplicate',false,'suggested_receipt','');
  end if;

  -- Preserve the entered/current prefix and recommend max+1.
  v_prefix := regexp_replace(v_receipt, '[0-9]+\s*$', '');
  if coalesce(v_prefix,'') = '' then
    v_prefix := regexp_replace(coalesce(v_row.receipt_number,''), '[0-9]+\s*$', '');
  end if;

  select coalesce(max(
    nullif(
      (regexp_match(btrim(coalesce(s.receipt_number,'')), '([0-9]+)\s*$'))[1],
      ''
    )::integer
  ),0)
  into v_max
  from public.shipments s
  where s.route = v_row.route
    and s.shipment_year = v_row.shipment_year
    and s.voyage = v_row.voyage
    and s.deletion_requested_at is null
    and coalesce(s.receipt_number,'') <> '';

  v_suggested := coalesce(v_prefix,'') || lpad((v_max + 1)::text, 2, '0');

  return jsonb_build_object(
    'duplicate', true,
    'suggested_receipt', v_suggested
  );
end;
$$;

revoke all on function public.admin_check_receipt_number(text,text) from public;
grant execute on function public.admin_check_receipt_number(text,text)
  to authenticated,service_role;

-- ------------------------------------------------------------
-- 3. Incomplete review: invoice + receipt editable
-- ------------------------------------------------------------
drop function if exists public.admin_review_incomplete_shipment(
  text,text,text,text,boolean
);

create or replace function public.admin_review_incomplete_shipment(
  p_shipment_id text,
  p_invoice_number text,
  p_consignee_name text,
  p_consignee_phone text,
  p_receipt_number text,
  p_notes text,
  p_lock boolean
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text;
  v_route text;
  v_year integer;
  v_voyage text;
begin
  if coalesce(btrim(p_shipment_id),'')='' then
    raise exception '화물 ID가 비어 있습니다.';
  end if;

  select s.id::text,s.route,s.shipment_year,s.voyage
    into v_id,v_route,v_year,v_voyage
  from public.shipments s
  where s.id::text=btrim(p_shipment_id)
  limit 1;

  if v_id is null then
    raise exception '화물을 찾을 수 없습니다. id=%',p_shipment_id;
  end if;

  update public.shipments s
  set invoice_number=btrim(coalesce(p_invoice_number,'')),
      consignee_name=btrim(coalesce(p_consignee_name,'')),
      consignee_phone=btrim(coalesce(p_consignee_phone,'')),
      receipt_number=btrim(coalesce(p_receipt_number,'')),
      notes=coalesce(p_notes,''),
      data_locked=coalesce(p_lock,false),
      updated_at=now()
  where s.id::text=v_id;

  -- User-entered receipt must be preserved. Normalize only when receipt is blank.
  if coalesce(btrim(p_receipt_number),'') = '' then
    perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
  end if;
end $$;

revoke all on function public.admin_review_incomplete_shipment(
  text,text,text,text,text,text,boolean
) from public;
grant execute on function public.admin_review_incomplete_shipment(
  text,text,text,text,text,text,boolean
) to authenticated,service_role;
