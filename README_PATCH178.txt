Patch178 - V00 BASE UPDATE MODE

핵심:
- V00는 실제 00항차가 아닙니다.
- V00 업로드 시 shipments INSERT/UPDATE를 절대 하지 않습니다.
- 따라서 V08, V07 등 실제 항차 화물 원본 행을 V00가 덮어쓰거나 삭제하지 않습니다.

V00 업로드 시:
1. 운송경로 판별
2. 시내/지방배송 BASE 갱신
3. 할인 고객/할인명/할인율 BASE 갱신
4. 명세서 선공유 고객/Content 갱신
5. 해당 경로에 DB로 존재하는 실제 항차 목록 조회
6. 각 항차에 admin_finalize_excel_batch_rules_fast 재실행
   - 배송/Zone/영수번호/Remark 재정비
   - 잠금 화물 보호는 기존 finalizer 규칙 그대로
7. 완료

ON CONFLICT 21000 FIX:
- 할인 규칙 bulk upsert -> 1 row씩 upsert
- Excel 문자열은 달라도 DB unique normalization 후 동일 row가 되는 경우
  한 SQL statement가 같은 target row를 두 번 UPDATE하는 오류를 방지합니다.

진행률:
- V00 역시 기존 upload Queue progress를 그대로 사용합니다.
- 기존 항차 재정비는 (1/N), (2/N) 식으로 안내합니다.
- 화면에서 뒤로 가도 앱 프로세스가 살아 있으면 Queue는 계속 진행합니다.

주의:
- V00 파일명은 그대로 V00로 유지하세요.
- V08로 이름 변경 금지.
- V00는 실제 화물 0건 변경이 정상입니다.

SQL 1회 필요 / Edge deploy 없음.
