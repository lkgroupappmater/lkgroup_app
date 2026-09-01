PATCH199 STATEPROOF

목적:
Flutter 내부 화면 이동은 Dart Future를 취소하지 않습니다.
따라서 '화면 나가면 죽음'처럼 보이는 경우를 확실히 구분하도록
재연산 작업을 앱 전역 서비스가 강하게 소유하고 단계/오류를 영구 상태로 유지합니다.

변경:
- RecalculationJobService가 active Future를 직접 보관
- 작업 단계별 message/step 저장
- Supabase RPC는 일시적 연결 오류에 한 번 재시도
- 화면 전환 중 GlobalNotice 실패가 재연산 자체를 실패 처리하지 않음
- catch에서 오류 + stacktrace를 콘솔에 출력
- 화면 재진입 시 서비스의 현재/최종 message를 그대로 표시
- 계산 공식/DB SQL/Edge/Excel 출력 로직 변경 없음

중요:
이 패치는 PATCH199 FINAL 이후 상태를 전제로 합니다.
오래된 A2/A3 화면-owned Future가 남아 있으면 STOP하고 파일을 건드리지 않습니다.

실행:
.\APPLY_PATCH_199_STATEPROOF.ps1
