-- Patch138b STEP 2
-- 현재 테스트 중인 한국→라오스 해상 2026년 08항차만 재정리합니다.
-- STEP 1 성공 후 실행하세요.

select public.normalize_shipment_batch(
  '한국→라오스 해상',
  2026,
  '08'
);
