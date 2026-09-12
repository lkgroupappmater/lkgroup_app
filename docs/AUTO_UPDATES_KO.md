# 앱 자동 업데이트

현재 master 소스는 **`1.0.4+5`**입니다. 새 LK GROUP 시작 화면, 실제 자동 패치 상태와
앱 알림/팝업 안내가 포함됩니다. 네이티브 시작 설정과 이미지, 앱 버전 조회 플러그인이
변경되므로 이 버전의 Shorebird APK/AAB를 한 번 새로 설치해야 합니다.

- 첫 화면은 사용자가 제공한 `assets/images/lk_group_logo.png` 원본입니다. 이미지를 변형하지
  않고 Flutter에서 원본 비율 전체를 표시합니다. Android 12 이상에서는 원본 픽셀을 네이티브
  벡터 경로로 옮기고 전체 그림을 원형 마스크의 안전 영역 안에 배치합니다. 이전 Android와 iOS는
  원본 PNG를 비율에 맞춰 표시합니다. 로고 아래에는 LK GROUP만 있으며 Trading 문구는 없습니다.
- OS 준비 단계에도 LK GROUP 로고가 표시됩니다. Flutter 이미지 해독이 끝날 때까지 OS 화면을
  유지하고 실제 첫 프레임이 그려진 뒤 1.2초간 그룹 로고를 표시합니다. 다음은 기존 Trading
  환영/로딩 화면, 마지막은 홈입니다. 서버 초기화는 첫 프레임 뒤 시작하며, 연결이 끝나기
  전에는 홈을 열지 않습니다. 실패하면 연결 실패 안내를 표시합니다.
  Android 12(API 31)는 IDE/ADB 실행에서 OS 시작 아이콘을 생략할 수 있으므로 실제 설치 동작은
  휴대폰 앱 아이콘으로 확인합니다. 이 경우에도 Flutter 준비 후 그룹 로고는 1.2초간 표시합니다.
  관련 플랫폼 동작은 [flutter_native_splash 공식 설명](https://github.com/jonbhanson/flutter_native_splash#android-12-and-later)에 정리되어 있습니다.
- 홈페이지 알림 종에서 현재 실제 설치 버전, 적용된 패치, 업데이트 상태/최근 확인 시간과
  수동 확인 버튼을 볼 수 있습니다. 비회원도 기기 업데이트를 볼 수 있지만 계정 알림은
  로그인한 경우에만 조회합니다. 기기 업데이트 알림은 DB에 생성하지 않습니다.
- Shorebird SDK로 stable 패치를 확인하고 새 패치가 있으면 내려받습니다. 앱 실행/복귀와
  기존 자동 갱신 흐름에서 확인하며 일반 확인은 30분 간격, 실패 재시도는 1분 간격으로 제한합니다.
  수동 확인 버튼은 제한을 건너뜁니다. 서버 확인이 시작 화면이나 사용자 작업을 막지 않습니다.
- 다운로드가 확인되면 알림 배지·홈 안내·팝업으로 저장 후 앱을 완전히 종료하고 재실행하라고
  안내합니다. 같은 버전/패치 팝업을 확인한 기록은 기기에 저장하여 재실행 후에도 반복하지 않습니다.
  기존 알림 팝업, 다른 화면, 입력 중에는 새 팝업을 미룹니다. 앱을 강제 종료하거나 재시작하지 않습니다.
- 실제 실행 모드(debug/profile/release/web)를 알림 상세에 표시합니다. IDE의 실행 버튼이나
  `flutter run`으로 만든 개발용 실행은 OTA 확인이 불가능한 이유와 Shorebird APK 설치 방법을
  안내하며, 개발용 제한만으로 새 업데이트 팝업을 띄우지 않습니다. release 모드여도 OTA 엔진이
  없으면 지원되지 않는 설치본이라고 안내합니다. `flutter run --release`도 Shorebird 빌드가 아닙니다.
  인터넷/다운로드 오류를 '최신 상태'로 표시하지 않습니다. 새 설치 파일 버전과 현재 버전용 코드 패치는
  서로 다르므로 `현재 설치 버전의 최신 패치`는 새로운 APK가 전혀 없다는 뜻이 아닙니다.
- 업데이트 상세의 현재 버전 개선 내용은 배포 코드와 함께 관리합니다. 다음 패치 내용이 확인되지
  않았을 때는 추측한 변경 목록을 표시하지 않고 준비된 패치 번호와 재실행 안내를 표시합니다.

이전 `1.0.1+2`에는 [Patch 2 배포](https://github.com/lkgroupappmater/lkgroup_app/actions/runs/34675919747)가
성공했습니다. 이전 커밋으로 생성한 `1.0.2+3` 설치본에는 이번 첫 화면/업데이트 알림 수정이 없습니다.
`1.0.3+4` 릴리스 작업이 시작된 후 네이티브 로고를 추가 수정하여 새 버전은 `1.0.4+5`입니다.
`git pull --ff-only origin master` 후 GitHub Actions의 `App update checks`에서
Branch `master`, `ota_action=release`로 **`1.0.4+5`** 설치본을 생성합니다.
릴리스 생성 전에는 이 새 버전의 자동 패치가 보류되는 것이 정상입니다.

Actions 화면에서 `Android release status: missing`, `Requested action: release`,
`Deployment ready: true`가 함께 표시되면 **새 설치본을 만들 준비가 된 정상 상태**입니다.
`validate`와 `native-startup`이 성공하면 `shorebird-deploy`가 실행됩니다. 전체 성공 후 같은 실행의
Artifacts에서 `lkgroup-shorebird-android-1.0.4+5`를 열고 APK를 휴대폰에 설치합니다.
AAB는 Play 업로드용입니다. `lkgroup-native-test-apk`는 CI 검증용 개발 APK이므로 OTA 설치용이 아닙니다.
설치 후 IDE 실행 버튼을 누르지 말고 **휴대폰 앱 아이콘**으로 실행합니다. 알림 상세의 실행 모드가
release이고 업데이트 확인이 정상인지 확인합니다. `git pull`과 Actions release만으로 이미 설치된
휴대폰 앱이 Shorebird 설치본으로 교체되지는 않습니다. 같은 버전의 release를 반복 실행할 필요는 없습니다.

 기존 설치본과 같은 서명을
유지해야 합니다. 실제 Play 게시 시 versionCode `5` 사용 이력도 확인합니다.

배송 색상은 지방 노랑 `#FFC000`, 시내 초록 `#92D050`, 지방 선결제 파랑 `#5B9BD5`,
시내 선결제 연갈색 `#D6B18A`를 유지합니다. 운임/환율/할인 계산은 변경하지 않습니다.

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

## 코드 패치(Shorebird): 연결 완료, 새 자산은 새 설치본 필요

`LK Group Trading`의 실제 앱 ID는 `b64e00d6-2682-4ff0-8519-c8701ce795af`이며
`shorebird.yaml`과 `pubspec.yaml`에 등록되어 있습니다. 같은 앱을 다시 init하거나
`--force`로 새 앱 ID를 만들지 않습니다. 최초 Shorebird 설치본을 배포하기 전에는
기존 일반 Flutter 설치본이 OTA 코드 패치를 받을 수 없습니다.

1. 로컬 빌드에는 공식 Shorebird CLI와 Python 3.9 이상이 필요합니다.
2. 프로젝트 폴더에서 `git pull --ff-only origin master` 후 `shorebird login`으로
   이 앱에 접근할 수 있는 본인 계정을 인증합니다.
3. 기존 등록 파일을 그대로 사용합니다. `python tool/ota.py init`은 등록 상태를 검사할 수 있습니다.
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
python tool/ota.py patch --defines C:/LK/app-config.json --release-version 1.0.4+5 --dry-run
python tool/ota.py patch --defines C:/LK/app-config.json --release-version 1.0.4+5 --track stable
```

`--release-version`에는 실제 배포한 버전을 씁니다. 도구는 `latest`나 pubspec과 다른 버전을
허용하지 않습니다. 기본 track은 테스트용 `staging`이며, 사용자 배포에는 `--track stable`을
명시합니다. 앱 시작 시 패치를 내려받고 다음 실행 시 적용하는 Shorebird 기본 동작을 사용합니다.
앱 실행 중인 코드를 즉시 교체하지 않으며, 앱 사용자가 소스를 pull할 필요는 없습니다.

이미지·폰트·네이티브 코드·권한 변경에는 새 설치본이 필요합니다. 이 도구는 Shorebird의
네이티브/자산 차이 검사 우회 옵션을 제공하지 않습니다. iOS 패치는 스토어 정책 범위 안에서
운영하며 첫 iOS 릴리스에는 macOS와 기존 Apple 서명 설정이 필요합니다(`--platform ios`).

## GitHub에서 Android 자동 배포

`App update checks` 워크플로는 다음 순서로 동작합니다.

1. master push 시 Shorebird API 키와 해당 앱 접근 권한을 읽기 전용으로 확인합니다.
2. pubspec의 정확한 버전에 active Android 릴리스가 있는지와 빌드 비밀 설정의 존재를 확인합니다.
3. Python 회귀 테스트, Flutter 분석·테스트, Android 디버그 빌드와 Android 12 실제 시작 화면
   검사(밝은/어두운 모드에서 원본 로고 형태 비교)를 모두 통과한 경우에만
   같은 커밋의 stable 패치를 배포합니다. PR에서는 비밀 설정을 사용하거나 배포하지 않습니다.
4. 최초 릴리스나 필요한 비밀 설정이 없으면 패치 작업을 보류하고 실행 Summary에 이유를 표시합니다.
   인증 자체가 거절되면 해당 작업은 실패로 표시됩니다. 키 값은 출력하지 않습니다.
5. 네이티브·이미지·폰트 변경은 Shorebird의 기본 검사에서 중단됩니다. 검사 우회 옵션은 사용하지 않습니다.

GitHub 저장소의 Settings → Secrets and variables → Actions → New repository secret에
다음 이름으로 저장합니다. 키/비밀번호를 채팅·소스 코드·일반 Actions Variables에 넣지 않습니다.

| Secret 이름 | 값 |
|---|---|
| `SHOREBIRD_TOKEN` | Shorebird Account → API Keys에서 생성한 키 |
| `APP_DART_DEFINES` | 현재 앱과 같은 서버 URL 및 publishable/anon 키가 담긴 JSON 전체 |
| `ANDROID_KEYSTORE_BASE64` | 기존 앱 서명용 JKS/keystore 파일을 Base64로 변환한 값 |
| `ANDROID_KEYSTORE_PASSWORD` | 기존 `android/key.properties`의 `storePassword` 값 |
| `ANDROID_KEY_ALIAS` | 기존 `android/key.properties`의 `keyAlias` 값 |
| `ANDROID_KEY_PASSWORD` | 기존 `android/key.properties`의 `keyPassword` 값 |

`APP_DART_DEFINES`는 아래 구조입니다. 예시 문구를 실제 앱의 기존 공개 연결 설정으로 바꿉니다.
`SUPABASE_ANON_KEY`를 사용하던 경우 `SUPABASE_PUBLISHABLE_KEY` 대신 그 이름을 사용할 수 있습니다.

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "YOUR_EXISTING_PUBLIC_CLIENT_KEY"
}
```

`service_role`, `sb_secret_` 등 서버 전용 키는 사용할 수 없습니다. 릴리스와 패치에 같은 값을
유지합니다. 다른 서버로 바꾸거나 서명 키를 교체하려면 기존 배포본과의 호환성을 먼저 확인합니다.

기존 keystore 파일을 복사할 때는 PowerShell에서 실제 경로를 넣어 아래 명령을 실행한 뒤
GitHub의 `ANDROID_KEYSTORE_BASE64` Secret 칸에 붙여넣습니다. 명령은 원본 파일을 변경하지 않습니다.

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\실제경로\upload-keystore.jks")) | Set-Clipboard
```

새 키를 임의로 생성하지 않습니다. 기존 직접 설치 APK와 서명이 다르면 덮어쓰기 업데이트가
되지 않습니다. 기존 Play 업로드 키도 그대로 유지해야 합니다. GitHub 빌드에서는 설정이
없을 때 임시 debug 서명으로 대체하지 않고 배포를 보류합니다.

### 최초 설치본 만들기

1. GitHub → Actions → `App update checks` → Run workflow를 엽니다.
2. Branch `master`, `ota_action`은 `release`로 선택해 실행합니다.
3. 모든 검증과 Shorebird 릴리스 생성이 성공하면 Artifacts의
   `lkgroup-shorebird-android-버전`을 다운로드합니다. APK/AAB가 포함됩니다(보관 30일).
4. AAB는 Play Console에 업로드하고, 직접 배포하는 기존 직원용 앱은 같은 서명의 APK로 업데이트합니다.
   이 워크플로가 Play Store 공개 게시를 수행하는 것은 아닙니다.
5. 이후 같은 pubspec 버전의 Dart 수정은 master push → 검증 통과 → stable 패치로 자동 전달됩니다.
   폰에서 패치를 다운로드한 뒤 앱을 완전히 종료하고 다시 실행해 반영 여부를 확인합니다.

`ota_action=check`는 설정/인증 확인만 수행합니다. `patch`는 현재 pubspec 버전의 패치를
수동 재시도할 때 사용합니다. 릴리스가 active이면 같은 버전으로 release를 다시 만들지 않습니다.
이미 일반 AAB로 Play에 사용한 versionCode라면 최초 Shorebird AAB에는 더 높은 versionCode가
필요합니다. 현재 새 설치본 소스는 `1.0.4+5`이며 Play에 게시하기 전에 실제 Play 등록 이력을 확인합니다.

Shorebird 기본 Flutter로 첫 릴리스를 만들고, 패치에는 Shorebird가 해당 릴리스의 Flutter를
선택합니다. 워크플로가 실행 중에 master가 더 진행된 경우 오래된 커밋은 배포 시작 전에
건너뜁니다. 패치 게시 작업을 새 push 때문에 중간 취소하지 않습니다.

iOS는 macOS 실행 환경 및 기존 Apple 인증서/프로비저닝 설정이 별도로 필요합니다.
이번 자동 배포 워크플로는 Android 대상이며, iOS 로컬 명령은 위 설명을 따릅니다.

공식 자료:
- https://docs.shorebird.dev/code-push/initialize/
- https://docs.shorebird.dev/code-push/release/
- https://docs.shorebird.dev/code-push/patch/
- https://developer.android.com/guide/playcore/in-app-updates/kotlin-java

## 확인

```powershell
python -m unittest discover -s tool -p 'test_*.py'
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
