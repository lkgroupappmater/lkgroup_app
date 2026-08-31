-- 073b_normalize_kr_la_sea_2026_v08_actual_route.sql
-- Patch138c
-- 현재 DB/앱에서 실제 사용하는 운송경로 문자열 "한국->라오스 해상" 기준으로
-- 2026년 08항차만 재정리합니다.
--
-- 이름이 정상이고 전화번호가 비어있거나 ????처럼 숫자가 없어도:
-- - 수취인 불명으로 보지 않음
-- - 기존 LKS XX 제거
-- - 정상 영수번호 자동 배정
-- - 수량 기준 Zone 재계산
-- - 단, data_locked=false인 경우 확인 필요 목록에는 계속 표시

select public.normalize_shipment_batch(
  '한국->라오스 해상',
  2026,
  '08'
);

-- 결과 확인용
select
  box_number,
  consignee_name,
  consignee_phone,
  receipt_number,
  unloading_zone,
  recipient_unknown,
  data_locked
from public.shipments
where route = '한국->라오스 해상'
  and shipment_year = 2026
  and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0') = '08'
  and deletion_requested_at is null
order by
  coalesce((regexp_match(coalesce(receipt_number,''),'(\d+)\s*$'))[1]::integer, 2147483647),
  coalesce((regexp_match(coalesce(box_number,''),'(\d+)\s*$'))[1]::integer, 2147483647),
  id;
