-- 066_fix_admin_excel_bulk_rows_for_voyage_total.sql
-- Patch121: 항차별 총액 계산이 실제 화물 계산에 필요한 전체 shipment 필드를 받도록 수정.
-- PostgreSQL 42804(date vs timestamp) 문제를 피하기 위해 received_at은 원본 타입을 그대로 반환하지 않고 text로 반환.

drop function if exists public.admin_excel_bulk_rows(text, integer, text);

create function public.admin_excel_bulk_rows(
  p_route text,
  p_year integer,
  p_voyage text
)
returns table(
  id bigint,
  box_number text,
  invoice_number text,
  sender_name text,
  consignee_name text,
  consignee_phone text,
  contents text,
  package_type text,
  quantity numeric,
  weight_kg numeric,
  length_cm numeric,
  width_cm numeric,
  height_cm numeric,
  receipt_number text,
  unloading_zone text,
  notes text,
  special_note_auto text,
  received_at text,
  data_locked boolean,
  route text,
  shipment_year integer,
  voyage text
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
    coalesce(s.box_number,'')::text,
    coalesce(s.invoice_number,'')::text,
    coalesce(s.sender_name,'')::text,
    coalesce(s.consignee_name,'')::text,
    coalesce(s.consignee_phone,'')::text,
    coalesce(s.contents,'')::text,
    coalesce(s.package_type,'')::text,
    coalesce(s.quantity,1)::numeric,
    coalesce(s.weight_kg,0)::numeric,
    coalesce(s.length_cm,0)::numeric,
    coalesce(s.width_cm,0)::numeric,
    coalesce(s.height_cm,0)::numeric,
    coalesce(s.receipt_number,'')::text,
    coalesce(s.unloading_zone,'')::text,
    coalesce(s.notes,'')::text,
    coalesce(s.special_note_auto,'')::text,
    coalesce(s.received_at::text,'')::text,
    coalesce(s.data_locked,false),
    coalesce(s.route,'')::text,
    s.shipment_year,
    coalesce(s.voyage,'')::text
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

grant execute on function public.admin_excel_bulk_rows(text, integer, text) to authenticated;
