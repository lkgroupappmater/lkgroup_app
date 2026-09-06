# LK Group Trading 스토어·테스트 배포 체크리스트

## 서비스 식별자

- 앱 이름: `LK Group Trading`
- Android application ID: `com.lkgrouptrading.app`
- iOS bundle ID: `com.lkgrouptrading.app`
- 버전: `pubspec.yaml`의 `version: 1.0.0+1`
- 웹사이트: `https://lkgrouptrading.com`
- 개인정보처리방침: `https://lkgrouptrading.com/#privacy`
- 지원 이메일: `auth@mail.lkgrouptrading.com`

application ID/bundle ID는 첫 스토어 출시 후 변경하지 않는다.

## Android 지인 테스트

Windows PowerShell에서:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

최근 Android 휴대폰 테스트용으로 보통 아래 파일만 전달한다.

```text
build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

테스터는 파일을 다운로드한 메신저/브라우저에 `알 수 없는 앱 설치`를 일시 허용해야 할 수 있다.

## Google Play Console

1. Play Console 개발자 계정과 사업자 인증을 완료한다.
2. `LK Group Trading`앱을 생성하고 기본 언어를 선택한다.
3. 업로드 키를 한 번만 생성한다.

   ```powershell
   keytool -genkeypair -v -keystore android\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

4. `android/key.properties.example`을 `android/key.properties`로 복사하고 실제 비밀번호를 입력한다. `.jks`와 `key.properties`는 외부 공유하지 않는다.
5. AAB를 빌드한다.

   ```powershell
   flutter build appbundle --release
   ```

6. `build\app\outputs\bundle\release\app-release.aab`를 내부 테스트 트랙에 먼저 업로드한다.
7. 앱 액세스 설명에 테스트 계정을 입력하고, 데이터 보안 문진에 이메일·이름·전화·화물 정보 사용을 정확히 신고한다.
8. 개인정보처리방침 URL을 입력하고 광고 없음을 선택한다.

## iPhone 지인 테스트 / App Store

iOS 빌드와 서명은 macOS의 Xcode가 필요하다.

1. Apple Developer Program에 가입하고 App Store Connect에서 앱을 생성한다.
2. Xcode에서 `ios/Runner.xcworkspace`를 열고 Runner 타겟의 Team을 선택한다.
3. Bundle ID가 `com.lkgrouptrading.app`인지 확인한다.
4. 실기기에서 카메라·사진 선택, 회원가입 OTP, 화물 조회, 상담 링크를 테스트한다.
5. Xcode `Product → Archive → Distribute App → App Store Connect`로 업로드한다.
6. 지인 테스트는 TestFlight의 Internal Testing에 이메일을 초대하는 방식이 가장 안전하다.

## 출시 전 필수 실기기 테스트

- 한국어·영어·라오어 전환 후 홈 카드, 공지, 일정, 운송 경로, 년도·항차 레이아웃
- 회원가입 → 이메일 OTP → 로그인 → 비밀번호 변경
- 송장번호 뒷 4자리 조회의 마스킹 표시와 관리자 정정 승인
- 일반 회원·파트너·직원·총괄 권한별 메뉴 및 RLS
- 대량 Excel/PDF 작업 중 메모리 사용과 다운로드
- 계정 탈퇴 인증코드, 탈퇴 후 로그인 차단
- Android/iOS에서 모든 외부 상담 링크 열기

## 스토어 자료

- 1024×1024 앱 아이콘: iOS asset에 준비됨. 투명도 없음.
- Android adaptive icon: 흰색 배경과 안전영역 적용.
- 휴대폰 스크린샷: 실제 최종 빌드에서 준비.
- 앱 소개 문구: `docs/STORE_LISTING.md` 사용.
