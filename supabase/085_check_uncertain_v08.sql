-- 085_check_uncertain_v08.sql
-- A. 진짜 수취인 불명
select
  box_number,consignee_name,consignee_phone,receipt_number,unloading_zone,data_locked
from public.shipments
where route='한국->라오스 해상'
  and shipment_year=2026
  and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0')='08'
  and deletion_requested_at is null
  and public.lk_recipient_true_unknown(consignee_name,consignee_phone)
order by coalesce((regexp_match(coalesce(box_number,''),'(\d+)\s*$'))[1]::integer,2147483647);

-- B. 불확실 / 확인 필요: 앱 승인관리 화면에 올라와야 하는 행
select
  box_number,consignee_name,consignee_phone,receipt_number,unloading_zone,
  case
    when public.lk_recipient_name_uncertain(consignee_name)
     and not public.lk_recipient_phone_uncertain(consignee_phone) then '이름 확인 필요'
    when not public.lk_recipient_name_uncertain(consignee_name)
     and public.lk_recipient_phone_uncertain(consignee_phone) then '연락처 확인 필요'
    else '수취인 정보 확인 필요'
  end reason,
  data_locked
from public.shipments
where route='한국->라오스 해상'
  and shipment_year=2026
  and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0')='08'
  and deletion_requested_at is null
  and not coalesce(data_locked,false)
  and public.lk_recipient_needs_review(consignee_name,consignee_phone)
order by coalesce((regexp_match(coalesce(receipt_number,''),'(\d+)\s*$'))[1]::integer,2147483647),
         coalesce((regexp_match(coalesce(box_number,''),'(\d+)\s*$'))[1]::integer,2147483647);
