-- 069_voyage_settlement_snapshots.sql
-- FreightService가 계산한 영수번호별 실제 정산 결과를 DB에 snapshot으로 저장.
-- Excel Row data / 항차 총액 / 향후 동적 명세서가 같은 결과를 사용하기 위한 연결층.

create table if not exists public.voyage_settlement_snapshots (
  id bigint generated always as identity primary key,
  route_key text not null,
  route_label text not null default '',
  shipment_year integer not null,
  voyage text not null,
  total_quantity integer not null default 0,
  gross_usd numeric not null default 0,
  discount_usd numeric not null default 0,
  net_usd numeric not null default 0,
  discount_by_group jsonb not null default '{}'::jsonb,
  receipts jsonb not null default '[]'::jsonb,
  calculated_by uuid references auth.users(id),
  calculated_at timestamptz not null default now(),
  unique(route_key,shipment_year,voyage)
);

alter table public.voyage_settlement_snapshots enable row level security;

drop policy if exists voyage_settlement_snapshots_admin_read
  on public.voyage_settlement_snapshots;
create policy voyage_settlement_snapshots_admin_read
  on public.voyage_settlement_snapshots
  for select using (public.current_role()='admin');

grant select on public.voyage_settlement_snapshots to authenticated;

create or replace function public.admin_save_voyage_settlement_snapshot(
  p_route_key text,
  p_route_label text,
  p_year integer,
  p_voyage text,
  p_total_quantity integer,
  p_gross_usd numeric,
  p_discount_usd numeric,
  p_net_usd numeric,
  p_discount_by_group jsonb,
  p_receipts jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_role()<>'admin' then
    raise exception '관리자 권한이 필요합니다.';
  end if;

  insert into public.voyage_settlement_snapshots(
    route_key,route_label,shipment_year,voyage,
    total_quantity,gross_usd,discount_usd,net_usd,
    discount_by_group,receipts,calculated_by,calculated_at
  ) values (
    p_route_key,coalesce(p_route_label,''),p_year,coalesce(p_voyage,''),
    greatest(coalesce(p_total_quantity,0),0),
    coalesce(p_gross_usd,0),coalesce(p_discount_usd,0),coalesce(p_net_usd,0),
    coalesce(p_discount_by_group,'{}'::jsonb),
    coalesce(p_receipts,'[]'::jsonb),
    auth.uid(),now()
  )
  on conflict(route_key,shipment_year,voyage) do update set
    route_label=excluded.route_label,
    total_quantity=excluded.total_quantity,
    gross_usd=excluded.gross_usd,
    discount_usd=excluded.discount_usd,
    net_usd=excluded.net_usd,
    discount_by_group=excluded.discount_by_group,
    receipts=excluded.receipts,
    calculated_by=excluded.calculated_by,
    calculated_at=excluded.calculated_at;
end
$$;

grant execute on function public.admin_save_voyage_settlement_snapshot(
  text,text,integer,text,integer,numeric,numeric,numeric,jsonb,jsonb
) to authenticated;

comment on table public.voyage_settlement_snapshots is
'중앙 FreightService가 계산한 항차/영수번호별 실제 정산 snapshot. Excel Row data는 이 결과를 사용하며 별도 운임 공식을 만들지 않는다.';
