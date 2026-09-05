# 프로젝트 검토 결과와 다음 단계

## 이번 전달본에서 처리한 항목

- Excel 업로드 파일명 유연화와 `.xlsm` 인식/보존
- Excel 다운로드 및 명세서 PDF 메모리 절감
- Excel과 앱의 영수번호/구획/할인/배송/선공유 규칙 통일
- 한국어/영어/라오어 주요 메뉴와 Phetsarath OT 적용
- 공지/일정 번역 저장 구조와 AI 상담 연결
- AI 상담 한국어/영어/라오어 실호출 검증
- 매일 라오스 시간 오전 9시 환율 자동 갱신 복구와 실저장 검증
- 기존 앱 계정·DB·RLS를 공유하는 비공개 그룹웨어 웹사이트 구축
- 관리 메뉴에 중복 표시되던 선적 일정/공지 메뉴 제거

## 시작 로고와 앱 아이콘

Android 기본 Flutter 런처 아이콘을 LK Group 로고로 교체했습니다.

- 일반 런처 아이콘 5개 밀도
- Android 8 이상 Adaptive Icon
- Android 12 이상 시스템 시작 화면
- Android 11 이하 시작 화면
- 앱 표시 이름 `LK Group Trading`

배경색은 기존 앱 시작 화면의 하늘색 `#DDF6FC`를 사용했습니다. 앱 아이콘은
현재 디자인을 유지하고, 시작 화면용 로고만 별도 안전 여백을 적용해 우측 상단이
잘리지 않도록 수정했습니다. 실제 기기에서 최종 여백을 한 번 확인해야 합니다.

## APK 빌드 전 필요한 것

1. Flutter SDK가 설치된 개발 PC에서 `flutter analyze`와 테스트 실행
2. Android applicationId, 표시 이름, 버전 확인
3. 실제 기기에서 LK 앱 아이콘/시작 화면 여백 확인
4. Android 서명 키 생성 및 안전한 별도 보관
5. `flutter build appbundle --release` 및 필요 시 `flutter build apk --release`
6. 실제 Android 기기에서 Excel 업로드/다운로드와 대량 명세서 출력 확인

## 저장소 정리 권장 사항

현재 저장소에는 `.gitignore`에 `node_modules/`가 있어도 과거에 추적된
`node_modules` 파일 759개와 Windows용 Supabase 실행 파일 약 138MB가 남아 있습니다.
또한 임시/백업 파일 4개와 같은 BASE Excel의 중복 디렉터리가 있습니다.

삭제는 커밋 기록과 배포 환경에 영향을 줄 수 있으므로 이번 전달본에서 임의 삭제하지
않았습니다. 별도 정리 커밋에서 다음 순서로 처리하는 것이 안전합니다.

```bash
git rm -r --cached node_modules
git rm PATCH199_STATEPROOF_service.tmp
git rm lib/screens/account_screen.dart.bak_email_verification_20260828
git rm lib/screens/cargo_management_screen.dart.bak_038
git rm lib/services/excel_import_service.dart.before_patch136b
flutter pub get
flutter analyze
flutter test
```

`base/`와 `BASE_EXCEL_TEMPLATES/` 중 어느 쪽이 운영 원본인지 확인하기 전에는 둘 중
하나를 삭제하면 안 됩니다.

## 웹사이트

첫 운영본을 비공개로 게시했습니다.

- 주소: https://lkgroup-trading-groupware.laoteonr-1911.chatgpt.site
- 앱과 동일한 Supabase Auth 계정으로 로그인
- 앱과 동일한 RLS 권한으로 화물·고객 그룹 ID·일정·공지·환율 조회
- 한국어/영어/라오어 및 Phetsarath OT 적용
- 브라우저에는 publishable key만 사용하고 service role/secret key는 포함하지 않음

도메인 `lkgroup.lktrading.com` 연결과 외부 사용자 공개 범위 변경은 DNS 및 접근 대상을
확정한 뒤 별도 단계로 진행하는 것이 안전합니다.

## 보안 점검

과거 테스트용 `allow_test_select/insert` 정책이 `shipments`, `notices`에 남아 있어
정상 역할별 RLS를 우회할 수 있었습니다. 테스트 정책만 제거했고 기존 관리자·직원·
협력사·회원별 운영 정책은 유지했습니다.
