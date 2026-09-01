Patch196 - Statement discount + unloading locked F/Y

1) 거래 명세서 할인 버그 수정
현재 증상:
- 화물 운임이 $0이고 기타비용만 있을 때,
  Remark/할인율은 20%로 보이지만 할인액은 -$0.00.
- 기타비용의 '할인 적용'을 체크해도 최종액이 줄지 않음.

원인:
- 명세서가 기타비용 할인율을
  freight.discountTotal / freight.grossTotal 로 계산.
- freight gross가 0이면 강제로 할인율 0이 되어버림.

수정:
- FreightService line의 실제 discountPercent를 우선 사용.
- 따라서 예: 운임 $0 + 할인대상 기타비용 $15 + 20%
  => 할인 $3 / 최종 $12.
- 기타비용 할인 체크 OFF면 기존대로 $15.
- 할인율은 하드코딩하지 않고 FreightService/DB 결과를 따름.

2) 하역 자료 잠금 물품 노란색 F/Y
- 하역 자료 관리 화면에 '잠금 물품 노란색 표시' 스위치 추가.
- 기본값 Y.
- Y: 잠금 화물도 노란색.
- F: 기존처럼 잠금 화물은 노란색 제외.
- manual_uncertain(?)도 계속 노란색.
- admin_excel_bulk_rows RPC가 manual_uncertain 컬럼을 반환하지 않아도
  shipments에서 수동 ? ID를 보강하여 PDF에 반영.

No SQL.
No Edge deploy.
No recalc.
No V00 upload.
