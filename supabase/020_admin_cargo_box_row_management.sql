-- 020_admin_cargo_box_row_management.sql
-- 총괄 관리자 전용: 박스번호 수정 + 선택 항차의 다음 박스번호 계산 + 새 화물 행 추가
-- 기존 화면/데이터 구조는 변경하지 않습니다.

create or replace function public.admin_next_box_number(
  p_route text,
  p_year integer,
  p_voyage text,
  p_prefix text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next integer;
  v_voyage text := lpad(nullif(regexp_replace(coalesce(p_voyage, ''), '[^0-9]', '', 'g'), ''), 2, '0');
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;
  if trim(coalesce(p_prefix, '')) = '' then
    raise exception '박스번호 접두어가 필요합니다.';
  end if;

  select coalesce(max(
    nullif(regexp_replace(substring(s.box_number from length(p_prefix) + 1), '[^0-9]', '', 'g'), '')::integer
  ), 0) + 1
    into v_next
    from public.shipments s
   where s.route = p_route
     and s.shipment_year = p_year
     and lpad(regexp_replace(coalesce(s.voyage, ''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
     and s.box_number like p_prefix || '%';

  return p_prefix || lpad(v_next::text, 3, '0');
end;
$$;

grant execute on function public.admin_next_box_number(text,integer,text,text) to authenticated;

create or replace function public.admin_update_shipment_box_number(
  p_shipment_id bigint,
  p_box_number text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.shipments%rowtype;
  v_box text := trim(coalesce(p_box_number, ''));
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;
  if v_box = '' then raise exception '박스번호를 입력해 주세요.'; end if;

  select * into v_row from public.shipments where id = p_shipment_id for update;
  if not found then raise exception '화물을 찾을 수 없습니다.'; end if;

  if exists (
    select 1 from public.shipments s
     where s.id <> p_shipment_id
       and s.route = v_row.route
       and s.shipment_year = v_row.shipment_year
       and coalesce(s.voyage, '') = coalesce(v_row.voyage, '')
       and s.box_number = v_box
  ) then
    raise exception '같은 운송경로/년도/항차에 이미 존재하는 박스번호입니다.';
  end if;

  update public.shipments
     set box_number = v_box,
         import_key = concat(v_row.route, '|', coalesce(v_row.shipment_year::text, ''), '|', coalesce(v_row.voyage, ''), '|', v_box),
         updated_at = now()
   where id = p_shipment_id;
end;
$$;

grant execute on function public.admin_update_shipment_box_number(bigint,text) to authenticated;

create or replace function public.admin_add_shipment_row(
  p_route text,
  p_year integer,
  p_voyage text,
  p_box_number text,
  p_invoice_number text default '',
  p_consignee_name text default '',
  p_consignee_phone text default '',
  p_notes text default '',
  p_unloading_zone text default '',
  p_weight_kg numeric default null,
  p_length_cm numeric default null,
  p_width_cm numeric default null,
  p_height_cm numeric default null
) returns public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.shipments%rowtype;
  v_voyage text := lpad(nullif(regexp_replace(coalesce(p_voyage, ''), '[^0-9]', '', 'g'), ''), 2, '0');
  v_box text := trim(coalesce(p_box_number, ''));
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;
  if trim(coalesce(p_route, '')) = '' or p_year is null or v_voyage is null or v_box = '' then
    raise exception '운송 경로, 년도, 항차, 박스번호가 필요합니다.';
  end if;

  if exists (
    select 1 from public.shipments s
     where s.route = p_route
       and s.shipment_year = p_year
       and lpad(regexp_replace(coalesce(s.voyage, ''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
       and s.box_number = v_box
  ) then
    raise exception '이미 존재하는 박스번호입니다.';
  end if;

  insert into public.shipments(
    route, shipment_year, voyage, box_number, import_key,
    invoice_number, consignee_name, consignee_phone, notes, unloading_zone,
    quantity, weight_kg, length_cm, width_cm, height_cm, status, received_at
  ) values (
    p_route, p_year, v_voyage, v_box,
    concat(p_route, '|', p_year::text, '|', v_voyage, '|', v_box),
    trim(coalesce(p_invoice_number, '')),
    trim(coalesce(p_consignee_name, '')),
    trim(coalesce(p_consignee_phone, '')),
    trim(coalesce(p_notes, '')),
    trim(coalesce(p_unloading_zone, '')),
    1, p_weight_kg, p_length_cm, p_width_cm, p_height_cm, 'registered', now()
  ) returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.admin_add_shipment_row(
  text,integer,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric
) to authenticated;
