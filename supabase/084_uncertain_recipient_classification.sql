-- 084_uncertain_recipient_classification.sql
-- Patch139
-- "불확실 고객"과 "진짜 수취인 불명"을 분리합니다.
--
-- 진짜 unknown:
--   이름도 신뢰 불가/없음 AND 전화번호도 신뢰 불가/없음
-- 불확실:
--   이름 또는 전화번호 중 하나라도 신뢰 가능하지만 다른 한쪽이 불완전
--   또는 이름에 * 마스킹이 포함됨.
-- 확정/잠금(data_locked=true)은 불확실 목록에서 제외.

create or replace function public.lk_recipient_name_uncertain(p_name text)
returns boolean
language sql immutable
as $$
  select
    coalesce(btrim(p_name),'')=''
    or lower(btrim(coalesce(p_name,''))) in
       ('unknown','unidentified','n/a','na','none','수취인불명','수신인불명','수취인 불명','수신인 불명')
    or coalesce(p_name,'') ~ '[*?]';
$$;

create or replace function public.lk_recipient_phone_uncertain(p_phone text)
returns boolean
language sql immutable
as $$
  select
    coalesce(btrim(p_phone),'')=''
    or coalesce(p_phone,'') ~ '[*?]'
    or length(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g')) < 7;
$$;

create or replace function public.lk_recipient_true_unknown(p_name text,p_phone text)
returns boolean
language sql immutable
as $$
  select public.lk_recipient_name_uncertain(p_name)
     and public.lk_recipient_phone_uncertain(p_phone);
$$;

create or replace function public.lk_recipient_needs_review(p_name text,p_phone text)
returns boolean
language sql immutable
as $$
  select
    not public.lk_recipient_true_unknown(p_name,p_phone)
    and (
      public.lk_recipient_name_uncertain(p_name)
      or public.lk_recipient_phone_uncertain(p_phone)
    );
$$;

-- 기존 normalize가 호출하는 함수도 새 기준으로 통일.
create or replace function public.shipment_name_is_explicit_unknown(p_name text)
returns boolean
language sql immutable
as $$
  select
    coalesce(btrim(p_name),'')=''
    or lower(btrim(coalesce(p_name,''))) in
       ('unknown','unidentified','n/a','na','none','수취인불명','수신인불명','수취인 불명','수신인 불명');
$$;

-- 승인관리 화면의 "불확실 / 확인 필요 데이터" RPC.
drop function if exists public.admin_list_incomplete_shipments();

create function public.admin_list_incomplete_shipments()
returns table(
  shipment_id bigint,
  route text,
  shipment_year integer,
  voyage text,
  box_number text,
  invoice_number text,
  consignee_name text,
  consignee_phone text,
  receipt_number text,
  unloading_zone text,
  notes text,
  data_locked boolean,
  uncertainty_reason text
)
language sql
security definer
set search_path=public
as $$
  select
    s.id,
    s.route,
    s.shipment_year,
    s.voyage,
    coalesce(s.box_number,''),
    coalesce(s.invoice_number,''),
    coalesce(s.consignee_name,''),
    coalesce(s.consignee_phone,''),
    coalesce(s.receipt_number,''),
    coalesce(s.unloading_zone,''),
    coalesce(s.notes,''),
    coalesce(s.data_locked,false),
    case
      when public.lk_recipient_name_uncertain(s.consignee_name)
       and not public.lk_recipient_phone_uncertain(s.consignee_phone)
        then '이름 확인 필요'
      when not public.lk_recipient_name_uncertain(s.consignee_name)
       and public.lk_recipient_phone_uncertain(s.consignee_phone)
        then '연락처 확인 필요'
      else '수취인 정보 확인 필요'
    end
  from public.shipments s
  where s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_recipient_needs_review(s.consignee_name,s.consignee_phone)
  order by
    s.shipment_year desc,
    coalesce(nullif(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),''),'0')::integer desc,
    coalesce((regexp_match(coalesce(s.receipt_number,''),'(\d+)\s*$'))[1]::integer,2147483647),
    coalesce((regexp_match(coalesce(s.box_number,''),'(\d+)\s*$'))[1]::integer,2147483647),
    s.id;
$$;

grant execute on function public.lk_recipient_name_uncertain(text) to authenticated,service_role;
grant execute on function public.lk_recipient_phone_uncertain(text) to authenticated,service_role;
grant execute on function public.lk_recipient_true_unknown(text,text) to authenticated,service_role;
grant execute on function public.lk_recipient_needs_review(text,text) to authenticated,service_role;
grant execute on function public.admin_list_incomplete_shipments() to authenticated,service_role;

-- V08의 recipient_unknown만 새 "둘 다 불확실" 기준으로 바로 정정.
-- receipt/zone은 Patch138h에서 만든 값을 유지하되, 진짜 unknown은 LKS XX/F.
select set_config('lkgroup.normalizing_shipments','1',true);

update public.shipments s
set recipient_unknown=public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone),
    receipt_number=case
      when public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
        then 'LKS XX'
      else s.receipt_number
    end,
    unloading_zone=case
      when public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
        then 'F'
      else s.unloading_zone
    end
where s.route='한국->라오스 해상'
  and s.shipment_year=2026
  and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')='08'
  and s.deletion_requested_at is null;

select set_config('lkgroup.normalizing_shipments','',true);
