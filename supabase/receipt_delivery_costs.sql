-- Retain the original RPCs for installed clients. New clients can identify
-- delivery charges even after staff edit their display names.
alter table public.receipt_extra_costs
  add column if not exists delivery_type text
  check (delivery_type in ('province', 'city'));

create unique index if not exists receipt_extra_costs_one_delivery_type
  on public.receipt_extra_costs
    (route, shipment_year, (regexp_replace(voyage,'[^0-9]','','g')), receipt_number, delivery_type)
  where delivery_type is not null;

create or replace function public.list_receipt_extra_costs_v2(
  p_route text, p_year integer, p_voyage text, p_receipt_number text
) returns table(id bigint, cost_name text, amount_usd numeric,
  discount_applies boolean, delivery_type text)
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  -- Use the same receipt ownership / role check as statement printing.
  perform 1 from public.statement_rows_for_receipt(p_route,p_year,p_voyage,p_receipt_number) limit 1;
  if not found then return; end if;
  return query select e.id,e.cost_name,e.amount_usd,e.discount_applies,e.delivery_type
    from public.receipt_extra_costs e
    where e.route=btrim(p_route) and e.shipment_year=p_year
      and regexp_replace(e.voyage,'[^0-9]','','g')=regexp_replace(p_voyage,'[^0-9]','','g')
      and btrim(e.receipt_number)=btrim(p_receipt_number)
    order by e.id;
end $$;

create or replace function public.save_receipt_extra_cost_v2(
  p_id bigint, p_route text, p_year integer, p_voyage text,
  p_receipt_number text, p_cost_name text, p_amount_usd numeric,
  p_discount_applies boolean default false, p_delivery_type text default null
) returns bigint
language plpgsql security definer set search_path=public as $$
declare v_id bigint;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id=auth.uid() and role in ('admin','staff')
  ) then raise exception '기타 비용 수정 권한이 없습니다.'; end if;
  if nullif(btrim(p_route),'') is null or p_year is null
    or nullif(btrim(p_voyage),'') is null or nullif(btrim(p_receipt_number),'') is null
    then raise exception '명세서 정보를 확인해 주세요.'; end if;
  if p_amount_usd is null or p_amount_usd < 0 or p_amount_usd::text in ('NaN','Infinity','-Infinity')
    then raise exception '금액을 확인해 주세요.'; end if;
  if p_delivery_type is not null and p_delivery_type not in ('province','city')
    then raise exception '배송 유형을 확인해 주세요.'; end if;
  if p_id is not null and not exists (
    select 1 from public.receipt_extra_costs e where e.id=p_id and e.route=btrim(p_route)
      and e.shipment_year=p_year and btrim(e.receipt_number)=btrim(p_receipt_number)
      and regexp_replace(e.voyage,'[^0-9]','','g')=regexp_replace(p_voyage,'[^0-9]','','g')
  ) then raise exception '이 명세서의 비용 항목이 아닙니다.'; end if;
  v_id := public.save_receipt_extra_cost(p_id,p_route,p_year,p_voyage,p_receipt_number,
    p_cost_name,p_amount_usd,coalesce(p_discount_applies,false));
  -- Older clients do not supply a delivery type when editing an existing cost.
  if p_delivery_type is not null then
    update public.receipt_extra_costs set delivery_type=p_delivery_type where id=v_id;
  end if;
  return v_id;
end $$;

revoke all on function public.list_receipt_extra_costs_v2(text,integer,text,text) from public,anon;
revoke all on function public.save_receipt_extra_cost_v2(bigint,text,integer,text,text,text,numeric,boolean,text) from public,anon;
grant execute on function public.list_receipt_extra_costs_v2(text,integer,text,text) to authenticated;
grant execute on function public.save_receipt_extra_cost_v2(bigint,text,integer,text,text,text,numeric,boolean,text) to authenticated;
