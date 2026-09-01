Patch194C robust hotfix

원인:
- Patch194B는 특정 줄바꿈/공백 형태를 정확히 찾는 방식이라
  사용자의 실제 로컬 파일 형태와 달라 'Patch194 load anchor missing' 발생.

수정:
- change_approval_screen.dart의 listIncompleteForAdmin() 호출을
  줄바꿈/공백과 무관하게 찾아 growable List로 변환.
- 이미 수정된 상태면 안전하게 통과.
- DB/SQL/Edge/재연산 변경 없음.

적용:
1. APPLY_PATCH_194C.ps1
2. flutter analyze
3. flutter run

Patch194 SQL은 다시 실행할 필요 없음.
