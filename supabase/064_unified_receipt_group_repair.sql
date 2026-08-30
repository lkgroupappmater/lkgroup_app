-- 064_unified_receipt_group_repair.sql
-- 요청 범위:
-- 같은 운송경로 + 같은 년도 + 같은 항차 + 같은 수령인 이름 + 같은 전화번호
-- => 입력 경로(Excel/수동/추가입력/수정)와 무관하게 반드시 동일 영수증으로 통합
-- => 통합된 영수증의 총 화물 수량으로 Zone 재계산
--
-- 기존 061의 문제:
-- receipt_number가 빈 행만 처리하여, Excel 등에 서로 다른 영수번호가 이미 들어온 경우
-- 같은 고객이어도 다시 하나로 묶지 못했습니다.
--
-- 이 파일은 화면/권한/운임/기타 DB 구조를 변경하지 않고 normalize 함수만 교체합니다.

create or replace function public.normalize_shipment_batch(
  p_route text,
  p_year integer,
  p_voyage text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_route_key text;
  v_receipt_prefix text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'),
    2,
    '0'
  );
  v_next integer := 1;
  r record;
  v_receipt text;
  v_count integer;
begin
  if coalesce(trim(p_route),'') = ''
     or p_year is null
     or coalesce(trim(v_voyage),'') = '' then
    return;
  end if;

  select rd.route_key, rd.receipt_prefix
    into v_route_key, v_receipt_prefix
  from public.route_definitions rd
  where rd.display_name = trim(p_route)
     or rd.route_key = trim(p_route)
  order by case when rd.display_name = trim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(trim(v_receipt_prefix),'') = '' then
    return;
  end if;

  -- 현재 항차에서 사용한 가장 큰 번호 다음부터 신규 번호 발급
  select coalesce(max((m)[1]::integer),0) + 1
    into v_next
  from public.shipments s
  cross join lateral regexp_match(
    trim(coalesce(s.receipt_number,'')),
    '(\d+)\s*$'
  ) m
  where s.route = p_route
    and s.shipment_year = p_year
    and lpad(
      regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
      2,
      '0'
    ) = v_voyage
    and s.deletion_requested_at is null;

  if v_next is null or v_next < 1 then
    v_next := 1;
  end if;

  -- 고객 단위로 한 번만 순회.
  -- 이름과 전화번호가 둘 다 동일한 경우만 같은 고객으로 판단합니다.
  for r in
    select
      lower(trim(coalesce(s.consignee_name,''))) as customer_name,
      regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g') as customer_phone,
      min(s.id) as first_id
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and lpad(
        regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
        2,
        '0'
      ) = v_voyage
      and s.deletion_requested_at is null
      and coalesce(trim(s.consignee_name),'') <> ''
      and regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g') <> ''
    group by
      lower(trim(coalesce(s.consignee_name,''))),
      regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g')
    order by min(s.created_at) nulls last, min(s.id)
  loop
    -- 같은 고객에게 이미 여러 영수번호가 있더라도 가장 먼저 생성된 행의
    -- 기존 영수번호 하나를 대표번호로 선택합니다.
    select nullif(trim(s.receipt_number),'')
      into v_receipt
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and lpad(
        regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
        2,
        '0'
      ) = v_voyage
      and s.deletion_requested_at is null
      and lower(trim(coalesce(s.consignee_name,''))) = r.customer_name
      and regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g') = r.customer_phone
      and coalesce(trim(s.receipt_number),'') <> ''
    order by s.created_at nulls last, s.id
    limit 1;

    if coalesce(v_receipt,'') = '' then
      if v_route_key in ('kr_la_sea','kr_la_air') then
        v_receipt := trim(v_receipt_prefix) || ' ' || lpad(v_next::text, 2, '0');
      else
        v_receipt := trim(v_receipt_prefix) || lpad(v_next::text, 2, '0');
      end if;
      v_next := v_next + 1;
    end if;

    -- 핵심: 빈 영수번호뿐 아니라 같은 고객의 서로 다른 기존 영수번호도 모두 통합
    update public.shipments s
       set receipt_number = v_receipt
     where s.route = p_route
       and s.shipment_year = p_year
       and lpad(
         regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
         2,
         '0'
       ) = v_voyage
       and s.deletion_requested_at is null
       and lower(trim(coalesce(s.consignee_name,''))) = r.customer_name
       and regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g') = r.customer_phone
       and s.receipt_number is distinct from v_receipt;
  end loop;

  -- 영수증별 총 수량으로 Zone 통일
  for r in
    select
      s.receipt_number,
      sum(greatest(coalesce(s.quantity,1),1))::integer as qty
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and lpad(
        regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
        2,
        '0'
      ) = v_voyage
      and coalesce(trim(s.receipt_number),'') <> ''
      and s.deletion_requested_at is null
    group by s.receipt_number
  loop
    v_count := r.qty;

    update public.shipments s
       set unloading_zone = case
         when v_route_key = 'kr_la_air' then '102'
         when v_count >= 20 then 'F'
         when v_count >= 10 then 'C'
         when v_count >= 5 then 'B'
         else 'A'
       end
     where s.route = p_route
       and s.shipment_year = p_year
       and lpad(
         regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'),
         2,
         '0'
       ) = v_voyage
       and s.receipt_number = r.receipt_number
       and s.deletion_requested_at is null;
  end loop;
end;
$$;

revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text)
  to authenticated, service_role;

-- 기존 trigger는 이미 normalize_shipment_batch를 호출하므로 trigger 구조는 변경하지 않습니다.
-- 현재 DB에 이미 서로 다른 영수번호로 갈라진 데이터도 즉시 복구합니다.
do $$
declare
  b record;
begin
  for b in
    select distinct route, shipment_year, voyage
    from public.shipments
    where coalesce(trim(route),'') <> ''
      and shipment_year is not null
      and coalesce(trim(voyage),'') <> ''
      and deletion_requested_at is null
  loop
    perform public.normalize_shipment_batch(
      b.route,
      b.shipment_year,
      b.voyage
    );
  end loop;
end;
$$;
