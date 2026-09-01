-- Patch178: V00 BASE Excel route-wide update support
-- V00는 실제 항차가 아니라 해당 운송경로의 정책/고객/배송/Remark BASE 업데이트용입니다.

create or replace function public.list_route_shipment_batches(
  p_route text
)
returns table(
  shipment_year integer,
  voyage text
)
language sql
security definer
set search_path=public
as $$
  select distinct
    s.shipment_year,
    s.voyage
  from public.shipments s
  where s.route=btrim(p_route)
    and s.deletion_requested_at is null
    and s.shipment_year is not null
    and coalesce(btrim(s.voyage),'')<>''
    and regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g') <> '00'
  order by s.shipment_year, s.voyage;
$$;

revoke all on function public.list_route_shipment_batches(text) from public;
grant execute on function public.list_route_shipment_batches(text)
  to authenticated, service_role;
