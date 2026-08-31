-- 080_rebuild_v08_receipt_groups.sql
-- Patch138g
-- KR->LA SEA 2026 V08의 잘못 공유된 기존 receipt를 보존하지 않고
-- 현재 수취인 identity 기준으로 영수번호/Zone을 재구축합니다.
--
-- 핵심:
-- * 이름 없음/명시적 unknown => LKS XX / F
-- * 이름 있음 => 정상 receipt 대상
-- * 전화번호가 없거나 ???/**** 등 불완전하면 "이름만"으로 그룹
-- * 전화번호가 충분하면 마지막 8자리 기준으로 표기 차이(020-, 공백, 하이픈)를 흡수
-- * 동일 이름에서 전화번호 없는 행이 있고, 그 이름에 유효 전화번호가 정확히 1개만 있으면 그 고객에 합침
-- * 같은 이름에 서로 다른 유효 전화번호가 2개 이상이면 전화번호 없는 행은 별도 확인 그룹으로 둠
-- * 기존 LKS 번호는 전부 재구축하므로 LKS 10처럼 서로 다른 고객이 섞인 상태를 제거
-- * 박스번호의 실제 입고 순서(min id) 기준으로 LKS 01,02,... 재배정
-- * receipt별 총 quantity로 A/B/C/F 재계산
--
-- 앱/DB 실제 route 문자열 기준.

begin;

-- 이 작업 중 shipments trigger의 재-normalize를 차단.
select set_config('lkgroup.normalizing_shipments','1',true);

create temporary table _v08_identity on commit drop as
with base as (
  select
    s.id,
    s.consignee_name,
    s.consignee_phone,
    greatest(coalesce(s.quantity,1),1)::integer qty,
    public.shipment_name_is_explicit_unknown(s.consignee_name) is_unknown,
    lower(regexp_replace(btrim(coalesce(s.consignee_name,'')),'\s+',' ','g')) name_key,
    regexp_replace(coalesce(s.consignee_phone,''),'[^0-9]','','g') digits
  from public.shipments s
  where s.route='한국->라오스 해상'
    and s.shipment_year=2026
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')='08'
    and s.deletion_requested_at is null
),
phones as (
  select *,
    case when length(digits)>=7 then right(digits,8) else '' end phone_key
  from base
),
name_phone_stats as (
  select
    name_key,
    count(distinct nullif(phone_key,'')) valid_phone_count,
    min(nullif(phone_key,'')) only_phone_key
  from phones
  where not is_unknown
  group by name_key
)
select
  p.id,
  p.qty,
  p.is_unknown,
  p.name_key,
  p.phone_key,
  case
    when p.is_unknown then '__UNKNOWN__'
    when p.phone_key<>'' then p.name_key||'|'||p.phone_key
    when coalesce(st.valid_phone_count,0)=1 then p.name_key||'|'||st.only_phone_key
    else p.name_key||'|NO_PHONE'
  end identity_key
from phones p
left join name_phone_stats st using(name_key);

create index on _v08_identity(id);
create index on _v08_identity(identity_key);

-- identity 그룹에 입고순서대로 새 receipt 번호를 부여.
create temporary table _v08_receipts on commit drop as
select
  identity_key,
  'LKS '||lpad(row_number() over(order by first_id)::text,2,'0') receipt_number
from (
  select identity_key,min(id) first_id
  from _v08_identity
  where not is_unknown
  group by identity_key
) g;

create unique index on _v08_receipts(identity_key);

-- 정상 수취인 receipt를 완전 재배정.
update public.shipments s
set
  recipient_unknown=false,
  receipt_number=r.receipt_number
from _v08_identity i
join _v08_receipts r using(identity_key)
where s.id=i.id
  and not i.is_unknown;

-- 진짜 unknown만 XX/F.
update public.shipments s
set
  recipient_unknown=true,
  receipt_number='LKS XX',
  unloading_zone='F'
from _v08_identity i
where s.id=i.id
  and i.is_unknown;

-- 정상 receipt별 총 수량 집계.
create temporary table _v08_qty on commit drop as
select
  r.receipt_number,
  sum(i.qty)::integer total_qty
from _v08_identity i
join _v08_receipts r using(identity_key)
where not i.is_unknown
group by r.receipt_number;

create unique index on _v08_qty(receipt_number);

-- Zone 일괄 재계산.
update public.shipments s
set unloading_zone=case
  when q.total_qty>=20 then 'F'
  when q.total_qty>=10 then 'C'
  when q.total_qty>=5 then 'B'
  else 'A'
end
from _v08_qty q
where s.route='한국->라오스 해상'
  and s.shipment_year=2026
  and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')='08'
  and s.deletion_requested_at is null
  and s.receipt_number=q.receipt_number
  and s.recipient_unknown=false;

-- unknown queue 상태 동기화.
insert into public.unmatched_recipient_review_queue(
  shipment_id,status,detected_name,detected_phone,detected_by
)
select s.id,'pending',coalesce(s.consignee_name,''),coalesce(s.consignee_phone,''),auth.uid()
from public.shipments s
join _v08_identity i on i.id=s.id
where i.is_unknown
on conflict (shipment_id) do update set
  status='pending',
  detected_name=excluded.detected_name,
  detected_phone=excluded.detected_phone,
  updated_at=now(),
  resolved_by=null,
  resolved_at=null;

update public.unmatched_recipient_review_queue q
set
  status='resolved',
  resolved_by=auth.uid(),
  resolved_at=coalesce(q.resolved_at,now()),
  updated_at=now()
from _v08_identity i
where q.shipment_id=i.id
  and not i.is_unknown
  and q.status='pending';

-- flag는 transaction 종료 시 자동 원복되지만 명시적으로 해제.
select set_config('lkgroup.normalizing_shipments','',true);

commit;
