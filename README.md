# LK Group Trading 관리 앱

Flutter 기반의 LK Group Trading 화물·고객·운임·선적 일정 통합 관리 앱입니다.
모바일 앱과 웹 그룹웨어는 같은 Supabase 프로젝트의 계정, 권한, 고객 ID 및
화물 데이터를 사용합니다.

## 개발 실행

```powershell
flutter pub get
flutter analyze
flutter run
```

## 소규모 Android 테스트 배포

```powershell
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

대부분의 최신 Android 휴대폰에는 아래 파일을 전달합니다.

```text
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

설치 전 테스트 참여자는 Android 설정에서 해당 메신저·브라우저 또는 파일
관리자의 `알 수 없는 앱 설치`를 일시적으로 허용해야 합니다. 테스트가 끝나면
다시 꺼도 됩니다.

## 스토어 등록 기본 정보

- Android application ID: `com.lkgrouptrading.app`
- iOS bundle ID: `com.lkgrouptrading.app`
- 앱 표시 이름: `LK Group Trading`
- 개인정보처리방침: `https://lkgrouptrading.com/#privacy`
- 회원 탈퇴: 앱/uc6f9의 `내 정보` 안에서 본인 인증 후 처리

스토어 등록, 서명키, 테스트 배포 순서는
`docs/STORE_RELEASE_CHECKLIST.md`에 정리했습니다.

## 유지하는 보조 도구

- `scripts/rebuild_excel_printarea_assets.ps1`: `QUOTATION_EXCEL_TEMPLATES`에서 견적서 Excel 인쇄영역 자산 재생성
- `package.json`: Supabase CLI 버전 관리

`node_modules`, Flutter 빌드 캐시, 과거 패치·백업 파일은 저장소에 포함하지
않습니다. 런타임에 불필요한 중복 Excel 원본 폴더와 로고 중간 작업물도
제거했습니다. 필요할 때 `flutter pub get` 또는 `npm install`로 의존성을 다시 생성합니다.
