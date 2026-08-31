-- 075_fast_normalize_v08_test.sql
-- 074 성공 후 실행.
-- 현재 V08만 고속 normalize + 결과 자연정렬 확인.

select public.normalize_shipment_batch('한국->라오스 해상',2026,'08');

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
