-- 042_shipment_delete_pending_export_and_restore_renumber.sql
-- 삭제 대기 화물은 일반 검색/Excel export에서 제외하고,
-- 삭제 취소 시 원래 박스번호가 이미 사용 중이면 해당 항차의 마지막 번호 다음으로 이동합니다.

create or replace function public.manager_cancel_shipment_deletion(
  p_shipment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.shipments%rowtype;
  v_prefix text;
  v_current_number integer;
  v_next_number integer;
  v_digits integer;
  v_new_box text;
  v_conflict boolean := false;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  select *
  into v_row
  from public.shipments
  where id = p_shipment_id
    and deletion_requested_at is not null
  for update;

  if not found then
    raise exception 'pending shipment not found';
  end if;

  -- 원래 박스번호가 활성 화물에 이미 사용 중인지 확인합니다.
  select exists(
    select 1
    from public.shipments s
    where s.id <> v_row.id
      and s.route = v_row.route
      and s.shipment_year = v_row.shipment_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0')
          = lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0')
      and lower(trim(coalesce(s.box_number,'')))
          = lower(trim(coalesce(v_row.box_number,'')))
      and s.deletion_requested_at is null
  )
  into v_conflict;

  if v_conflict then
    -- 박스번호의 끝 숫자를 기준으로 prefix / 자릿수를 유지합니다.
    v_prefix := regexp_replace(coalesce(v_row.box_number,''), '[0-9]+$', '');
    v_digits := greatest(
      3,
      length(coalesce(substring(v_row.box_number from '([0-9]+)$'), ''))
    );

    select coalesce(max(
      nullif(
        substring(s.box_number from '([0-9]+)$'),
        ''
      )::integer
    ), 0)
    into v_current_number
    from public.shipments s
    where s.route = v_row.route
      and s.shipment_year = v_row.shipment_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0')
          = lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0')
      and s.deletion_requested_at is null
      and s.box_number like v_prefix || '%';

    v_next_number := v_current_number + 1;
    v_new_box := v_prefix || lpad(v_next_number::text, v_digits, '0');

    update public.shipments
    set box_number = v_new_box,
        import_key = trim(v_row.route) || '|' ||
                     coalesce(v_row.shipment_year::text, '') || '|' ||
                     lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0') || '|' ||
                     v_new_box,
        deletion_requested_at = null,
        deletion_requested_by = null
    where id = p_shipment_id;
  else
    update public.shipments
    set deletion_requested_at = null,
        deletion_requested_by = null
    where id = p_shipment_id;
  end if;
end;
$$;

grant execute on function public.manager_cancel_shipment_deletion(bigint)
to authenticated;

-- 검색 RPC에서 삭제 대기 자료가 보이지 않도록 기존 함수에 적용할 조건:
--   and s.deletion_requested_at is null
-- 아래 함수는 현재 프로젝트의 검색 반환 형식과 동일하게 유지합니다.
create or replace function public.search_shipments_for_current_user(
  p_route text default '',
  p_year integer default null,
  p_voyage text default '',
  p_box_number text default '',
  p_invoice text default '',
  p_recipient text default '',
  p_phone text default ''
)
returns setof public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.current_role();
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'),
    2,
    '0'
  );
begin
  if v_role not in ('admin','staff','partner','member') then
    return;
  end if;

  return query
  select s.*
  from public.shipments s
  where s.deletion_requested_at is null
    and (coalesce(trim(p_route),'') = '' or s.route = p_route)
    and (p_year is null or s.shipment_year = p_year)
    and (
      coalesce(trim(p_voyage),'') = ''
      or lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
    )
    and (
      coalesce(trim(p_box_number),'') = ''
      or lower(coalesce(s.box_number,'')) like '%' || lower(trim(p_box_number)) || '%'
    )
    and (
      coalesce(trim(p_invoice),'') = ''
      or lower(coalesce(s.invoice_number,'')) like '%' || lower(trim(p_invoice)) || '%'
    )
    and (
      coalesce(trim(p_recipient),'') = ''
      or lower(coalesce(s.consignee_name,'')) like '%' || lower(trim(p_recipient)) || '%'
    )
    and (
      coalesce(trim(p_phone),'') = ''
      or regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g')
         like '%' || regexp_replace(trim(p_phone), '[^0-9]', '', 'g') || '%'
    )
  order by s.created_at desc, s.id desc;
end;
$$;

grant execute on function public.search_shipments_for_current_user(
  text,integer,text,text,text,text,text
) to authenticated;
