-- 047_statement_preview.sql
-- 명세서 조회 권한 + 선적일정 도착 예정일 연동

create or replace function public.statement_arrival_date(
  p_route text,
  p_year integer,
  p_voyage text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  result text;
begin
  if public.current_role() = 'partner' then
    raise exception '협력/파트너 계정은 명세서를 조회할 수 없습니다.';
  end if;

  select s.estimated_arrival_date::text
  into result
  from public.shipping_schedules s
  where s.route = p_route
    and regexp_replace(coalesce(s.year,''), '[^0-9]', '', 'g') = p_year::text
    and regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g')
        = regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g')
    and coalesce(s.deletion_status,'') <> 'pending'
  order by s.id desc
  limit 1;

  return result;
end;
$$;

create or replace function public.statement_rows_for_receipt(
  p_route text,
  p_year integer,
  p_voyage text,
  p_receipt_number text
)
returns setof public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  role_name text := public.current_role();
  my_name text;
  my_phone text;
begin
  if role_name = 'partner' then
    raise exception '협력/파트너 계정은 명세서를 조회할 수 없습니다.';
  end if;

  if role_name in ('admin','staff') then
    return query
    select s.*
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g')
          = regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g')
      and btrim(coalesce(s.receipt_number,'')) = btrim(p_receipt_number)
      and s.deletion_requested_at is null
    order by s.box_number, s.id;
    return;
  end if;

  if role_name <> 'member' then
    raise exception '명세서 조회 권한이 없습니다.';
  end if;

  select coalesce(p.name,''), coalesce(p.phone,'')
  into my_name, my_phone
  from public.profiles p
  where p.id = auth.uid();

  return query
  select s.*
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g')
        = regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g')
    and btrim(coalesce(s.receipt_number,'')) = btrim(p_receipt_number)
    and s.deletion_requested_at is null
    and (
      (
        regexp_replace(coalesce(my_phone,''), '[^0-9]', '', 'g') <> ''
        and regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g')
            = regexp_replace(my_phone, '[^0-9]', '', 'g')
      )
      or (
        btrim(my_name) <> ''
        and lower(btrim(coalesce(s.consignee_name,''))) = lower(btrim(my_name))
      )
    )
  order by s.box_number, s.id;
end;
$$;

grant execute on function public.statement_arrival_date(text,integer,text)
  to authenticated;
grant execute on function public.statement_rows_for_receipt(text,integer,text,text)
  to authenticated;
