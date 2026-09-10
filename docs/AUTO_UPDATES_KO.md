# 앱 자동 업데이트

이번 소스 버전은 `1.0.1+2`입니다. 기존에 설치한 `1.0.0+1` 앱에는 이 코드가
들어 있지 않으므로 새 설치본을 한 번 배포해야 합니다. GitHub에 소스를 올리거나
`git pull`하는 것만으로 이미 설치된 앱의 실행 파일이 바뀌지는 않습니다.

## 운영 자료

- 홈 공지·일정, 공지/일정 상세 목록, 조회를 완료한 화물 검색·관리 목록을
  서버 변경 신호에 따라 자동으로 다시 읽습니다. 모든 운송 경로가 같은 코드를 사용합니다.
- 실시간 신호는 1초 단위로 모아서 처리합니다. 신호를 놓치거나 연결이 복구된 경우를
  위해 화면을 보고 있는 동안 30초 주기로도 확인하고, 앱/화면 복귀 시 다시 읽습니다.
- 숨긴 탭, 다른 화면/대화상자가 열린 상태, 입력 중, 화물을 선택한 상태,
  저장 작업 중에는 목록 자동 갱신을 미룹니다. 필터·선택·입력 컨트롤러를 초기화하지 않습니다.
- 제출하지 않은 검색 조건을 자동으로 실행하지 않습니다. 네트워크 오류 때는 기존 표시를 유지합니다.
- 공통 명세서 번호·지방배송·할인 계산은 앞서 반영한 서버 RPC를 그대로 사용합니다.
  자동 갱신이 계산이나 재번호 부여를 실행하지 않습니다. 새 명세서/PDF를 만들 때 서버를 다시 조회합니다.
- 이미 열린 PDF/견적 미리보기나 편집 화면을 강제로 교체하지 않습니다. 해당 작업을 닫고
  다시 열면 최신 자료를 조회합니다. 오프라인에서 다른 기기의 변경을 실시간으로 볼 수는 없습니다.

서버 파일: `supabase/migrations/20260910000100_app_data_revisions.sql`.
`app_data_revisions`에는 공지/화물의 변경 번호만 저장합니다. 공개 이용자는 공지 신호만,
로그인한 이용자는 두 신호를 읽을 수 있습니다. 원본 화물·고객 데이터의 접근 권한은 바꾸지 않습니다.

## Google Play 설치본

Android 앱이 시작되거나 다시 열릴 때 업데이트를 확인하고, 이후 사용 중에는
최대 30분 간격으로 확인합니다. 새 버전이 있으면 홈 상단에 업데이트 버튼이 나타납니다.
사용자가 누르면 Google Play의 동의를 거쳐 백그라운드에서 다운로드합니다.
완료 후 저장 안내와 재시작 확인을 거쳐 설치합니다. 강제 재시작은 없습니다.

이 기능은 Google Play에서 설치한 앱에 적용됩니다. 직접 설치한 APK에는 Play 업데이트가
제공되지 않을 수 있습니다. Play 내부 테스트에서 동일한 앱 ID/서명과 더 높은 versionCode의
릴리스를 사용하여 실제 단말에서 확인해야 합니다. iOS 스토어 자동 업데이트는 기기 설정을 따릅니다.

## 코드 패치(Shorebird): 최초 1회 연결 필요

현재 저장소에는 실제 Shorebird 앱 ID/계정 연결이 없습니다. 따라서 아래 초기 설정과
최초 배포를 마치기 전에는 OTA 코드 패치가 활성화되지 않습니다. 임의 앱 ID나
자격 증명을 넣어 두지 않았습니다.

1. 공식 Shorebird CLI와 Python 3.9 이상을 설치합니다.
2. 프로젝트 폴더에서 `git pull origin master` 후 `python tool/ota.py init`을 실행합니다.
   본인 계정으로 로그인하면 공식 CLI가 실제 `shorebird.yaml`을 만들고 `pubspec.yaml`에 등록합니다.
   이미 설정이 있으면 재등록하거나 앱 ID를 덮어쓰지 않습니다.
3. 생성된 `shorebird.yaml`과 변경된 `pubspec.yaml`을 GitHub에 커밋합니다.
4. 현재 앱에서 사용하는 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY`(또는 `SUPABASE_ANON_KEY`)
   값을 로컬 JSON 파일에 저장합니다. 아래 `C:/LK/app-config.json`은 **로컬 파일 경로 예시**입니다.
   릴리스와 패치에 반드시 같은 설정을 사용합니다. 서버 비밀 키나 service_role은 넣지 않습니다.
5. 기존 Android 서명 키를 유지한 상태에서 첫 설치본을 만듭니다.

```powershell
python tool/ota.py release --defines C:/LK/app-config.json
```

공식 CLI가 알려주는 산출물을 배포합니다. Play에는 기존 업로드 키로 서명한 AAB를 사용합니다.
직접 APK를 배포하는 경우에도 기존 설치본과 같은 서명 키/앱 ID를 유지합니다.
Shorebird CLI의 Android APK 배포 옵션은 공식 릴리스 문서를 참고하세요.
`flutter build`로 만든 일반 설치본은 OTA 엔진이 포함되지 않습니다.

이후 Dart 코드 수정은 동일 릴리스 소스에서 검증 후 다음과 같이 배포합니다.

```powershell
python tool/ota.py patch --defines C:/LK/app-config.json --release-version 1.0.1+2 --dry-run
python tool/ota.py patch --defines C:/LK/app-config.json --release-version 1.0.1+2 --track stable
```

`--release-version`에는 실제 배포한 버전을 씁니다. 도구는 `latest`나 pubspec과 다른 버전을
허용하지 않습니다. 기본 track은 테스트용 `staging`이며, 사용자 배포에는 `--track stable`을
명시합니다. 앱 시작 시 패치를 내려받고 다음 실행 시 적용하는 Shorebird 기본 동작을 사용합니다.
앱 실행 중인 코드를 즉시 교체하지 않으며, 앱 사용자가 소스를 pull할 필요는 없습니다.

이미지·폰트·네이티브 코드·권한 변경에는 새 설치본이 필요합니다. 이 도구는 Shorebird의
네이티브/자산 차이 검사 우회 옵션을 제공하지 않습니다. iOS 패치는 스토어 정책 범위 안에서
운영하며 첫 iOS 릴리스에는 macOS와 기존 Apple 서명 설정이 필요합니다(`--platform ios`).

GitHub 검증 워크플로는 분석·회귀 테스트·Android 디버그 빌드만 수행합니다. 사용자에게
소스를 올릴 때마다 검증하지 않은 패치나 설치본을 자동 배포하지 않습니다.

공식 자료:
- https://docs.shorebird.dev/code-push/initialize/
- https://docs.shorebird.dev/code-push/release/
- https://docs.shorebird.dev/code-push/patch/
- https://developer.android.com/guide/playcore/in-app-updates/kotlin-java

## 확인

```powershell
python -m unittest discover -s tool -p test_ota.py
flutter test test/auto_refresh_state_test.dart test/app_update_service_test.dart test/document_form_layout_test.dart
flutter build apk --debug
```

실제 단말에서는 앱을 켠 채 웹에서 공지/화물을 수정했을 때의 갱신, 입력·선택 중 갱신 보류,
오프라인 후 복귀, Play 다운로드 취소·재시도·재시작, Shorebird 최초 릴리스의 패치 수신을 확인합니다.

## 이번 업로드 보완

웹·앱 업로드는 기본 20행씩 처리하며 DB 시간초과일 때 최대 1행까지 나눕니다.
공통 업로드 RPC만 45초 제한을 적용했습니다. 신규/동일/변경 승인 판정과 배송·할인 계산은 유지합니다.
운송 경로 선택은 한국→라오스 해상·항공, 라오스→한국 특송, 라오스↔태국, 라오스↔베트남,
라오스↔중국, 라오스↔캄보디아 순서로 통일했습니다.
