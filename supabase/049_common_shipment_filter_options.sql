-- 049_common_shipment_filter_options.sql
-- 조회 화면 공통 년도/항차 옵션
-- 실제 삭제되지 않은 화물 데이터가 1건 이상 존재하는 조합만 반환합니다.

create or replace function public.list_shipment_filter_batches()
returns table(
  route text,
  shipment_year integer,
  voyage text
)
language sql
security definer
set search_path = public
as $$
  select distinct
    s.route,
    s.shipment_year,
    s.voyage
  from public.shipments s
  where auth.uid() is not null
    and nullif(btrim(coalesce(s.route, '')), '') is not null
    and s.shipment_year is not null
    and nullif(btrim(coalesce(s.voyage, '')), '') is not null
    and s.deletion_requested_at is null
  order by shipment_year desc, route asc, voyage desc;
$$;

revoke all on function public.list_shipment_filter_batches() from public;
grant execute on function public.list_shipment_filter_batches() to authenticated;
