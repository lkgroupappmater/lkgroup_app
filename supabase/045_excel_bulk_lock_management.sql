-- 045_excel_bulk_lock_management.sql
-- 관리자(총괄) 전용 Excel 데이터 일괄 관리 / 편집 잠금

alter table public.shipments
  add column if not exists data_locked boolean not null default false;
alter table public.shipments
  add column if not exists data_locked_at timestamptz;
alter table public.shipments
  add column if not exists data_locked_by uuid references auth.users(id);

create index if not exists shipments_data_locked_idx
  on public.shipments(data_locked)
  where data_locked = true;

-- 잠금된 화물은 총괄 admin 이외 직접 UPDATE 금지.
-- 회원 정정 요청을 총괄 admin이 승인하는 경우 caller가 admin이므로 변경 가능하며
-- data_locked 값은 건드리지 않아 잠금 상태가 그대로 유지됩니다.
create or replace function public.protect_locked_shipment_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.data_locked = true
     and coalesce(public.current_role(), '') <> 'admin' then
    raise exception '데이터 수정 잠금된 화물입니다. 관리자(총괄)만 직접 수정할 수 있습니다.';
  end if;
  return new;
end;
$$;

drop trigger if exists shipments_protect_locked_update on public.shipments;
create trigger shipments_protect_locked_update
before update on public.shipments
for each row execute function public.protect_locked_shipment_update();

-- 실제 데이터가 존재하는 항차만 목록 제공.
create or replace function public.admin_excel_bulk_batches()
returns table(route text, shipment_year integer, voyage text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  return query
  select distinct s.route, s.shipment_year, s.voyage
  from public.shipments s
  where s.shipment_year is not null
    and coalesce(s.voyage, '') <> ''
    and s.deletion_requested_at is null
  order by s.route, s.shipment_year desc, s.voyage;
end;
$$;

create or replace function public.admin_excel_bulk_rows(
  p_route text,
  p_year integer,
  p_voyage text
)
returns table(
  id bigint,
  box_number text,
  invoice_number text,
  consignee_name text,
  consignee_phone text,
  receipt_number text,
  unloading_zone text,
  notes text,
  data_locked boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  return query
  select
    s.id,
    s.box_number,
    s.invoice_number,
    s.consignee_name,
    s.consignee_phone,
    s.receipt_number,
    s.unloading_zone,
    s.notes,
    s.data_locked
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and s.voyage = p_voyage
    and s.deletion_requested_at is null
  order by
    nullif(btrim(s.receipt_number), '') nulls last,
    btrim(s.receipt_number),
    s.box_number,
    s.id;
end;
$$;

create or replace function public.admin_excel_bulk_set_lock(
  p_ids bigint[],
  p_locked boolean
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  update public.shipments
  set
    data_locked = p_locked,
    data_locked_at = case when p_locked then now() else null end,
    data_locked_by = case when p_locked then auth.uid() else null end
  where id = any(p_ids);

  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function public.admin_excel_bulk_update(
  p_shipment_id bigint,
  p_box_number text,
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
    raise exception '박스번호는 비워둘 수 없습니다.';
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
    raise exception '같은 항차에 이미 존재하는 박스번호입니다.';
  end if;

  next_key :=
    current_row.route || '|' ||
    coalesce(current_row.shipment_year::text, '') || '|' ||
    current_row.voyage || '|' ||
    btrim(p_box_number);

  update public.shipments
  set
    box_number = btrim(p_box_number),
    import_key = next_key,
    consignee_name = coalesce(p_consignee_name, ''),
    consignee_phone = coalesce(p_consignee_phone, ''),
    receipt_number = coalesce(p_receipt_number, ''),
    unloading_zone = coalesce(p_unloading_zone, ''),
    notes = coalesce(p_notes, '')
  where id = p_shipment_id;
end;
$$;

-- Excel 업로드: 신규행은 추가, 기존 잠금행은 절대 덮어쓰지 않음.
-- admin/staff/partner 기존 업로드 권한은 유지.
create or replace function public.manager_upsert_unlocked_shipments(
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  affected integer := 0;
  changed integer;
  k text;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception '화물 Excel 업로드 권한이 없습니다.';
  end if;

  if jsonb_typeof(p_rows) <> 'array' then
    raise exception '화물 데이터 형식이 올바르지 않습니다.';
  end if;

  for item in select value from jsonb_array_elements(p_rows)
  loop
    k := coalesce(item->>'import_key', '');
    if k = '' then
      continue;
    end if;

    insert into public.shipments (
      box_number, invoice_number, route, shipment_year, voyage, import_key,
      sender_name, consignee_name, consignee_phone, contents, package_type,
      quantity, weight_kg, length_cm, width_cm, height_cm,
      receipt_number, unloading_zone, notes, received_at, status
    )
    values (
      coalesce(item->>'box_number',''),
      coalesce(item->>'invoice_number',''),
      coalesce(item->>'route',''),
      nullif(item->>'shipment_year','')::integer,
      coalesce(item->>'voyage',''),
      k,
      coalesce(item->>'sender_name',''),
      coalesce(item->>'consignee_name',''),
      coalesce(item->>'consignee_phone',''),
      coalesce(item->>'contents',''),
      coalesce(item->>'package_type',''),
      coalesce(nullif(item->>'quantity','')::integer,1),
      nullif(item->>'weight_kg','')::numeric,
      nullif(item->>'length_cm','')::numeric,
      nullif(item->>'width_cm','')::numeric,
      nullif(item->>'height_cm','')::numeric,
      coalesce(item->>'receipt_number',''),
      coalesce(item->>'unloading_zone',''),
      coalesce(item->>'notes',''),
      nullif(item->>'received_at','')::timestamptz,
      coalesce(nullif(item->>'status',''),'registered')
    )
    on conflict (import_key)
      where import_key is not null and import_key <> ''
    do update set
      box_number = excluded.box_number,
      invoice_number = excluded.invoice_number,
      sender_name = excluded.sender_name,
      consignee_name = excluded.consignee_name,
      consignee_phone = excluded.consignee_phone,
      contents = excluded.contents,
      package_type = excluded.package_type,
      quantity = excluded.quantity,
      weight_kg = excluded.weight_kg,
      length_cm = excluded.length_cm,
      width_cm = excluded.width_cm,
      height_cm = excluded.height_cm,
      receipt_number = excluded.receipt_number,
      unloading_zone = excluded.unloading_zone,
      notes = excluded.notes,
      received_at = excluded.received_at,
      status = excluded.status
    where public.shipments.data_locked = false;

    get diagnostics changed = row_count;
    affected := affected + changed;
  end loop;

  return affected;
end;
$$;

grant execute on function public.admin_excel_bulk_batches() to authenticated;
grant execute on function public.admin_excel_bulk_rows(text,integer,text) to authenticated;
grant execute on function public.admin_excel_bulk_set_lock(bigint[],boolean) to authenticated;
grant execute on function public.admin_excel_bulk_update(bigint,text,text,text,text,text,text) to authenticated;
grant execute on function public.manager_upsert_unlocked_shipments(jsonb) to authenticated;
