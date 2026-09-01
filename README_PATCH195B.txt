Patch195B compile hotfix

원인:
- Patch195에서 quotation_preview_dialog.dart의 paint() 내부
  safeDiscountPercent 변수를 465행 부근에서 먼저 사용하고
  527행 부근에서 뒤늦게 선언함.
- Dart analyzer/build 오류:
  referenced_before_declaration
  read_potentially_unassigned_final

수정:
- safeDiscountPercent 선언을 paint() 시작부로 이동
- 뒤쪽 중복 선언 제거
- 할인 계산/하역 노란색/기타비용 할인 기능 자체는 변경하지 않음

적용:
1) APPLY_PATCH_195B.ps1
2) flutter analyze
3) flutter run

SQL / Edge / 재연산 / V00 없음.
