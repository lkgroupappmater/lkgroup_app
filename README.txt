LKGroup local project cleanup tools

1) REPORT_PROJECT_SIZE.ps1
   - 삭제 없음
   - build/.dart_tool/.git 등 폴더 크기
   - 큰 파일 Top 40
   - Git에 추적 중인 과거 Patch / .bak 후보
   - 추적되지 않은 임시 Patch/ZIP 후보

2) CLEAN_SAFE_LOCAL.ps1
   자동 삭제 대상:
   - build/
   - .dart_tool/
   - .artifacts/
   - coverage/
   - .pub/
   - android/.gradle/
   - Git에 추적되지 않은 APPLY_*.ps1 / PATCH*.py / README_PATCH*.txt / ZIP

   절대 자동 삭제하지 않음:
   - lib/
   - assets/
   - android 실제 설정파일
   - supabase/
   - pubspec.yaml
   - pubspec.lock
   - .git/
   - Git tracked 파일

주의:
CLEAN_SAFE_LOCAL.ps1 후 .dart_tool이 없어지므로:
  flutter pub get
  flutter analyze
를 실행하세요.

Git에 이미 추적된 과거 Patch/.bak 파일은 이 도구가 자동 삭제하지 않습니다.
그건 repo 정리 Patch로 별도로 제거하는 것이 안전합니다.
