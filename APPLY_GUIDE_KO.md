# LKGroup 앱 Excel + 언어 + AI 업데이트

기준 저장소: `lkgroupappmater/lkgroup_app` / `master`

## 적용 방법

ZIP 안의 파일을 프로젝트 루트에 경로 그대로 덮어쓴 뒤 실행합니다.

```bash
flutter pub get
flutter test test/excel_automation_alignment_test.dart
flutter analyze
flutter run
```

이 작업 환경에는 Flutter SDK가 없어 위 Flutter 명령과 APK 빌드는 실행하지
못했습니다. `git diff --check`, Dart 파일 괄호/문자열 구조 검사, SQL 실제 적용,
Edge Function 실제 배포 검증은 완료했습니다.

## 현재 Supabase 적용 상태

- 프로젝트: `LKGroup LKTrading app`
- `excel_app_logic_complete_and_consistent` 적용 완료
- `content_ai_translations` 적용 완료
- `exchange_rate_service_role_write` 적용 완료
- `remove_test_rls_policies` 적용 완료
- `export-shipment-excel` 버전 51 배포 완료 (`ACTIVE`, JWT 검증 사용)
- `ai-assistant` 버전 2 배포 완료 (`ACTIVE`, JWT 검증 사용)
- 번역 저장 열 확인: 공지 4개, 선적 일정 10개

현재 연결 프로젝트에는 SQL과 Edge Function을 다시 실행할 필요가 없습니다.
다른 환경에 설치할 때만 아래 파일을 사용합니다.

- `supabase/099_excel_app_logic_complete_and_consistent.sql`
- `supabase/100_content_ai_translations.sql`
- `supabase/101_exchange_rate_service_role_write.sql`
- `supabase/102_remove_test_rls_policies.sql`
- `supabase/functions/export-shipment-excel/index.ts`
- `supabase/functions/ai-assistant/index.ts`

## Excel 업로드 파일명

파일명 전체를 고정하지 않습니다. 다음 정보가 있으면 설명용 접두/접미 문구가
있어도 인식합니다.

1. 경로: `LKS`, `LKA`, `KR_LA_SEA`, `KR_LA_AIR` 또는 해당 한글 노선명
2. 연도: 예) `2026`
3. 항차: 예) `V08` 또는 `08항차`

허용 확장자: `.xlsx`, `.xlsm`

예시:

- `KR_LA_SEA_2026_V08_SHIPMENTS.xlsx`
- `2026년 LKS 08항차 최종 수정본.xlsm`
- `한국-라오스 항공 LKA_2026_V12_확정.xlsx`
- `한국-라오스 해상 xx항차 거래명세서_2026xxxx.xlsm` → V00 BASE

노선·연도·항차 중 하나가 없으면 잘못된 항차에 들어가는 것을 막기 위해
접수하지 않습니다.

## Excel과 동일하게 맞춘 앱 업무 로직

- 선결제 배송: 공백을 제외한 풀네임이 정확히 일치할 때만 적용
- 일반 배송: 정확 이름+전화 → 정확 이름 → 분리 이름+전화 → 전화 → 분리 이름
- `이경희`와 `이경화/이경희`는 서로 다른 영수번호 유지
- `이경화 / 이경희`와 `이경화/이경희`는 같은 풀네임으로 인식
- `이우용 / 이*용`은 앞의 정상 이름으로 확인하며 정상 고객 후보가 하나일 때 연결
- 정상 이름 + 마스킹 전화번호(예: `황진수`, `***`)는 정상 고객 처리
- 이름이 `수취인 불명`, `???`, `***`, `미확인` 등으로 시작하면 LKS/LKA XX, Zone F
- 박성호 대표: 영수번호 100, Zone 102, 할인 100%
- 배송 고객: Zone F
- 일반 Zone: 1~4 A, 5~9 B, 10~19 C, 20+ F
- 고정 Zone, 할인, 명세서 선공유, 지방/시내배송 값을 DB에서 매번 조회
- 배송표는 업체 또는 주소 중 하나만 있어도 사용 가능
- 명세서 배송정보는 `No. 번호`, 수취인, 연락처, 업체, 주소를 제목 없이 줄바꿈
- 색상: 지방 주황 / 지방 선결제 하늘 / 시내 초록 / 시내 선결제 갈색

## 언어팩과 AI

- 한국어/영어/라오어 선택 시 상단·하단 메뉴, 홈, 관리 메뉴, 조회/견적/계정의
  주요 고정 조작 문구와 운송 경로가 함께 변경됩니다.
- 화물 조회·화물 관리의 고정 번역은 `lib/core/cargo_ui_strings.dart`에서 직접
  수정할 수 있고, 나머지 공통 화면 번역은 `lib/core/app_language.dart`에서
  수정할 수 있습니다.
- 라오어 선택 시 `Phetsarath OT`가 적용됩니다.
- 공지와 선적 일정은 관리자가 작성/수정할 때 영어·라오어 번역본을 같이 저장합니다.
- 기존 공지/일정은 관리자 또는 직원이 새 앱으로 홈을 처음 열 때 누락 번역을
  1회 보완하고, 일반 사용자는 저장된 번역만 읽습니다.
- AI 상담은 로그인 사용자만 호출할 수 있으며 회사별 확정 운임·일정·통관 규칙을
  임의로 만들지 않도록 제한했습니다.
- Supabase Edge Function Secrets에 `OPENAI_API_KEY`가 있어야 실제 번역/상담이
  응답합니다. 선택적으로 `OPENAI_MODEL`을 지정할 수 있고 기본값은
  `gpt-5-mini`입니다.
- ChatGPT 구독/로그인 계정과 OpenAI API 사용료는 별도입니다.
- `OPENAI_API_KEY` 등록 후 한국어·영어·라오어 상담을 각각 실제 호출하여
  HTTP 200 응답을 확인했습니다.

## 환율 자동 갱신

- `ExchangeRate-API` 기준 USD→LAK/THB/KRW 값을 DB에 저장합니다.
- Cron은 `0 2 * * *` UTC, 즉 라오스 시간 매일 오전 9시에 실행됩니다.
- 외부 조회나 저장이 실패하면 마지막 정상 환율을 유지합니다.
- 2026-09-05 재검증 결과: LAK 22199.3179 / THB 32.9145 /
  KRW 1348.9904, 상태 `success`, 오류 없음입니다.

## 메모리 개선

- 모바일/웹 Excel 다운로드는 파일 전체를 앱 메모리에 올리지 않고 운영체제 또는
  브라우저 다운로드로 넘깁니다.
- 명세서 PDF는 고해상도 PNG 전체 묶음 대신 축소 JPEG를 한 장씩 PDF에 추가합니다.
- 렌더링 이미지 객체는 사용 직후 해제합니다.

## XLSM

- `.xlsm`은 일반 Excel처럼 열고 셀 입력/수식 계산을 할 수 있습니다.
- 앱은 VBA를 실행하지 않고 원본 템플릿의 매크로 프로젝트를 보존합니다.
- 매크로 버튼은 데스크톱 Microsoft Excel에서 사용하는 것이 가장 안정적입니다.
- Android/iOS Excel 및 Google Sheets에서는 VBA 버튼이 실행되지 않을 수 있습니다.

## 저장소

GitHub에는 자동 커밋하거나 푸시하지 않았습니다. ZIP 검토 후 사용자가 원할 때만
커밋/PR 작업을 진행합니다.

## Android 시작 화면

- 기본 Flutter 런처 아이콘을 LK Group 로고로 교체했습니다.
- Android 12 시스템 시작 화면과 이전 Android 시작 화면을 모두 설정했습니다.
- Android 12에서 별도 시작 로고를 사용하므로 앱 아이콘 디자인은 그대로 유지하며,
  시작 로고에는 안전 여백을 추가해 우측 잘림을 방지했습니다.
- 앱 표시 이름은 `LK Group Trading`으로 변경했습니다.

## 그룹웨어 웹사이트

- 운영본: https://lkgroup-trading-groupware.laoteonr-1911.chatgpt.site
- 우선 본인 전용 비공개 Site로 게시했습니다.
- 사이트 안에서는 모바일 앱과 같은 Supabase 계정으로 다시 로그인합니다.
- 화물, 고객 그룹 ID, 선적 일정, 공지, 환율을 같은 DB와 RLS 권한으로 조회합니다.
- 한국어/영어/라오어 화면 전환과 라오어용 Phetsarath OT를 적용했습니다.
