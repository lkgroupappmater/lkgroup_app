Patch176
1. Remark
- 내용 중앙정렬 + 굵게
- FreightService의 할인 group_name이 있으면 generic '할인 20% 적용'을
  '라선협 할인 20% 적용' 같은 형식으로 보강
- DB special_note_auto의 선공유/기타/배송 문구는 그대로 유지

2. 우측 할인 패널
- '할인 20%' 또는 '특별할인 20%'로 할인율 표시
- 할인 금액을 오른쪽에 -$XX.XX 표시
- 화물표의 청구중량 운임은 할인 전 gross 금액 표시
- 최종 USD = 할인 전 운임 + 기타비용 - 운임할인 - 할인체크 기타비용 할인
- 환산 KIP/THB/KRW도 같은 최종 USD 기준

3. 기타 비용
- '할인 적용' 체크박스 추가
- 기본 OFF
- ON일 때만 해당 고객 할인율을 기타 비용에도 적용
- 예: 지방배송비 $10, 할인 20%, 체크 ON -> $2 할인 / 최종 +$8
- 체크 OFF -> $10 그대로 추가

4. 하역 자료
- 5열 x 27행 -> 6열 x 34행
- 셀/여백/글자 약간 축소
- 404건 기준 3페이지 -> 2페이지

5. Excel exporter
- discount_applies까지 읽음
- 자동화 helper의 최종 금액에도 할인 체크 기타 비용 반영

적용 순서
A) APPLY_PATCH_176.ps1
B) flutter analyze
C) PATCH176_extra_cost_discount.sql 전체 실행
D) npx supabase functions deploy export-shipment-excel
E) flutter run
