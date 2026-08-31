-- 081_check_v08_receipt_groups.sql
-- Patch138g 결과 검증.
-- 1) receipt 하나에 여러 identity가 섞였는지 확인: 정상이라면 0 rows.
with x as (
  select
    receipt_number,
    lower(regexp_replace(btrim(coalesce(consignee_name,'')),'\s+',' ','g')) name_key,
    case
      when length(regexp_replace(coalesce(consignee_phone,''),'[^0-9]','','g'))>=7
      then right(regexp_replace(coalesce(consignee_phone,''),'[^0-9]','','g'),8)
      else ''
    end phone_key
  from public.shipments
  where route='한국->라오스 해상'
    and shipment_year=2026
    and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0')='08'
    and deletion_requested_at is null
    and recipient_unknown=false
)
select receipt_number,
       count(distinct name_key) different_names
from x
group by receipt_number
having count(distinct name_key)>1
order by receipt_number;

-- 2) 전체 결과 자연순.
select
  box_number,
  consignee_name,
  consignee_phone,
  receipt_number,
  unloading_zone,
  recipient_unknown,
  data_locked
from public.shipments
where route='한국->라오스 해상'
  and shipment_year=2026
  and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0')='08'
  and deletion_requested_at is null
order by
  coalesce((regexp_match(coalesce(receipt_number,''),'(\d+)\s*$'))[1]::integer,2147483647),
  coalesce((regexp_match(coalesce(box_number,''),'(\d+)\s*$'))[1]::integer,2147483647),
  id;
