Patch174C

1) Excel 다운로드 화면 기능 분리
- Excel 파일 업로드: 항차 선택과 완전히 독립
- 업로드 진행현황: 기존 Queue progress 그대로 표시
- 운송경로/년도/항차 선택
- '선택 항차 재연산 및 Update' 별도 버튼
- 재연산 단계별 progress 표시
- Excel 다운로드 별도 버튼

2) 재연산 속도 개선
- Patch168에서 쓰던 lkgroup.bulk_import trigger guard를 재연산에도 사용
- finalizer 내부 UPDATE마다 불필요하게 normalize가 재귀 실행되는 것을 막음
- 실제 finalizer는 한 번만 명시 실행
- 이후 할인/운임 + snapshot만 갱신

3) 하역 PDF 저장 오류 수정
- 화면에서 발생한 FormatException 경로를 피하기 위해
  하역 PDF에서 NotoSansKR OTF 직접 파싱을 제거
- built-in Helvetica로 숫자/영문 화물번호/Zone PDF 생성
- 제목도 KR_LA_SEA 2026 V08 UNLOADING ZONE 형태로 출력
- **, ***, ??가 정상 이름과 함께 있어도 LKS XX로 강제하지 않음
  (현재 DB의 정상 영수번호를 그대로 사용)
- 다만 하역 자료에서는 노란색 경고
- data_locked=true면 확인 완료로 보고 노랑 제거

적용:
1. APPLY_PATCH_174C.ps1
2. flutter analyze
3. PATCH174C_fast_recalculate.sql 전체 실행
4. flutter run

Edge deploy 없음.
