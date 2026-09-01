Patch197B compile hotfix

원인:
- Patch197에서 _DigitalStatementPainter에 voyage를 required로 추가했지만
  화면용 painter에는 전달하고 batch renderer의 두 번째 painter 생성부에는 누락.
- analyzer:
  missing_required_argument at statement_preview_dialog.dart around line 1145

수정:
- batch renderer에도 voyage: request.voyage 전달.
- 항차 제목 기능 외 다른 로직 변경 없음.

No SQL / Edge / recalc / V00.
