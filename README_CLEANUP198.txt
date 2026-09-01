Patch198 프로젝트 안전 대청소

삭제:
- build, .dart_tool, .artifacts, coverage, .pub, android/.gradle
- 과거 APPLY/PATCH/README_PATCH 스크립트
- *.bak_before_patch* 백업
- patch숫자 폴더
- scripts/apply_*.ps1 일회성 적용 스크립트

보존:
- lib, assets, base, BASE_EXCEL_TEMPLATES, QUOTATION_EXCEL_TEMPLATES
- supabase, android 실제 설정, pubspec.yaml, pubspec.lock, .git
- sample excel files.zip
- node_modules는 삭제 안 함 (.gitignore만 추가)

실행:
.\CLEAN_PROJECT_198.ps1
flutter pub get
flutter analyze
git status --short

삭제된 tracked 파일은 git status에서 D로 보이는 것이 정상이며, commit 전에는 복구 가능합니다.
