-- Patch194: 관리자 수동 불확실 표시
-- 기존 recipient_unknown / 자동 불확실 판정과 분리된 운영용 플래그입니다.
alter table public.shipments
  add column if not exists manual_uncertain boolean not null default false;

comment on column public.shipments.manual_uncertain is
  '관리자가 화물관리 ? 버튼으로 수동 지정한 현지 확인 필요 플래그. 일반 불명/불확실 조회에는 사용하지 않고 변경 승인 관리에서만 별도 확인한다.';

create index if not exists idx_shipments_manual_uncertain
  on public.shipments (manual_uncertain)
  where manual_uncertain = true;
