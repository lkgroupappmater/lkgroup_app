Patch194 combined

1) 고객 리스트 최종
- Patch193D의 큰 글씨에서 약 20% 축소
- 박스번호도 약 20% 축소
- 박스번호 칸을 넓혀 ... 생략을 최대한 방지
- 기존 10개/줄, 필요 시 고객 행만 자동 확장 유지
- 박성호 대표/LKS100은 인쇄물에서 박스번호와 수량을 표시하지 않음
- 2페이지 이후 상단 여백은 첫 페이지 타이틀 위 여백 수준 유지

2) 화물관리
- 편집/잠금 옆 관리자용 ? 불확실 토글
- OFF: 흰색/흑백
- ON: 노란색
- 수동 불확실은 recipient_unknown/일반 불확실 조회 로직에 섞지 않음

3) 화물내용 변경 승인 관리
- 수동 ? 지정 화물만 이 승인 화면의 불확실 목록에 추가
- 확인/수정, 확정/잠금 버튼을 카드 오른쪽 한 줄 배치
- 처리 후 manual_uncertain 자동 OFF

4) 운임/할인
- 현재 cargo_management_screen의 고객/영수증 액션에는 기존 ReceiptDiscountService 기반 % 버튼이 이미 존재하므로 중복 생성하지 않음.
- 만약 사용자가 말한 '운임 확인'이 별도 화면이면 그 화면 캡처/로컬 코드 기준으로 다음 번 정확히 붙일 것.

적용 순서:
1. APPLY_PATCH_194.ps1
2. Supabase SQL Editor에서 Patch194_manual_uncertain.sql 실행
3. flutter analyze
4. flutter run

Edge deploy / 재연산 / V00 재업로드 없음.
