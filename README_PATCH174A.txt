Patch174A
- 메뉴/타이틀: 화물 데이타 엑셀 업로드 및 Update
- 업로드 화면 하단: 현재 DB 운송경로/년도/항차 선택 + 재연산 및 Update
  * admin_finalize_excel_batch_rules 재실행
  * 영수번호/Zone/자동 특이사항 재정리
  * ReceiptSettlementService + voyage settlement snapshot 재계산
- 관리자(직원)/관리자(총괄): 하역 자료 관리
  * 운송경로/년도/항차 선택
  * DB 화물번호 + 최종 Zone PDF
  * 위->아래, 다음 오른쪽 열 / 페이지당 5열 x 16행
  * 불확실/???/****/LKS XX 노랑
  * data_locked=true는 확인 완료로 보고 노랑 제외
  * 데이터 있는 페이지까지만 생성
- SQL 없음
- Edge deploy 없음
- Patch168/Patch173 구조 미변경
