# LK Group Trading 새 도메인·인증메일 설정

기준 도메인: `lkgrouptrading.com`

## 1. 웹사이트 연결 상태

`https://lkgrouptrading.com`과 `https://www.lkgrouptrading.com`은 Sites에
연결되어 있으며 도메인과 SSL 상태가 모두 활성화되어 있다. Cloudflare의
웹사이트용 A/CNAME/TXT 레코드는 삭제하거나 프록시 상태를 변경하지 않는다.

사이트가 특정 PC에서만 바로 열리지 않으면 Windows 명령 프롬프트에서
`ipconfig /flushdns`를 실행하고 새 시크릿 창 또는 휴대폰 모바일 데이터로
다시 확인한다.

## 2. 이메일 구성 구분

- 회원가입·암호 변경 인증번호: Supabase Auth가 SMTP로 발송
- 회원탈퇴 인증번호: Supabase Edge Function이 Resend API로 발송
- `info@lkgrouptrading.com` 같은 실제 수신함: 별도 메일 서비스 필요

도메인을 구입하거나 Resend에 등록한 것만으로 수신 가능한 메일함이 생기지는
않는다.

## 3. Resend에서 새 발신 도메인 인증

1. `https://resend.com/domains`에 로그인한다.
2. **Add Domain**을 누른다.
3. Domain에 `mail.lkgrouptrading.com`을 입력한다.
4. Region 선택이 나오면 화면에 표시되는 가까운 아시아 지역을 선택하고,
   없으면 기본값을 유지한다.
5. Resend가 보여 주는 DKIM/SPF/MX/CNAME/TXT 값을 복사한다.
6. Cloudflare에서 `lkgrouptrading.com`을 선택하고 **DNS → Records → Add record**로
   들어가 각 레코드를 그대로 추가한다.
7. Resend 화면으로 돌아와 **Verify DNS Records**를 누른다.
8. 모든 항목이 초록색이고 상태가 **Verified**인지 확인한다.

Resend 값은 계정과 지역에 따라 달라질 수 있으므로 임의 값을 입력하지 않는다.
Cloudflare가 `.lkgrouptrading.com`을 자동으로 붙이면 Name에는 짧은 이름만
입력한다. 예를 들어 Resend가 `resend._domainkey.mail.lkgrouptrading.com`을
보여 주면 Name은 `resend._domainkey.mail`이다. CNAME은 **DNS only**로 둔다.
MX/TXT에는 프록시 설정이 없다.

## 4. Resend API 키 만들기

1. `https://resend.com/api-keys`를 연다.
2. **Create API Key**를 누른다.
3. 이름은 `LKGroup Supabase`로 입력한다.
4. 생성된 `re_...` 값을 복사해 안전하게 보관한다.
5. 키는 채팅, GitHub, 앱 코드에 넣지 않는다.

## 5. Supabase Custom SMTP

직접 주소:
`https://supabase.com/dashboard/project/rkqwzxfcnciptnwesfbr/auth/smtp`

**Authentication → SMTP Settings**에서 Custom SMTP를 활성화하고 입력한다.

| 항목 | 값 |
|---|---|
| Sender email | `auth@mail.lkgrouptrading.com` |
| Sender name | `LK Group` |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | Resend의 `re_...` API 키 |

저장 후 **Authentication → Providers → Email**에서 Email Provider와
Confirm email이 켜져 있는지 확인한다.

## 6. Supabase 인증메일 템플릿

직접 주소:
`https://supabase.com/dashboard/project/rkqwzxfcnciptnwesfbr/auth/templates`

앱은 링크 클릭 방식이 아니라 숫자 OTP 입력 방식을 사용하므로 다음 두 템플릿에
반드시 `{{ .Token }}`이 있어야 한다.

- Confirm signup
- Reauthentication

프로젝트의 `supabase/email_templates/confirm_signup_otp.html`과
`supabase/email_templates/reauthentication_otp.html` 내용을 각각 복사해 저장한다.

## 7. Supabase URL Configuration

직접 주소:
`https://supabase.com/dashboard/project/rkqwzxfcnciptnwesfbr/auth/url-configuration`

Site URL:

`https://lkgrouptrading.com`

Redirect URLs:

- `https://lkgrouptrading.com/**`
- `https://www.lkgrouptrading.com/**`
- `https://lkgroup-trading-groupware.laoteonr-1911.chatgpt.site/**`

## 8. Edge Function 회원탈퇴 메일

새 Resend 도메인이 Verified 된 다음 진행한다.

직접 주소:
`https://supabase.com/dashboard/project/rkqwzxfcnciptnwesfbr/functions/secrets`

Secrets에 다음 값을 등록하거나 교체한다.

| Name | Value |
|---|---|
| `RESEND_API_KEY` | Resend에서 만든 `re_...` 키 |
| `RESEND_FROM_EMAIL` | `LK Group <auth@mail.lkgrouptrading.com>` |

그 다음 이 프로젝트의 `supabase/functions/member-account-delete/index.ts`를
배포한다. 새 도메인이 Verified 되기 전에는 운영 함수의 예전 발신주소를 먼저
바꾸지 않는다.

## 9. 최종 테스트 순서

1. Resend Domain이 Verified인지 확인
2. Supabase Custom SMTP 저장
3. 새 테스트 이메일로 회원가입 OTP 수신 확인
4. 인증번호 재발송 확인
5. 가입 완료 후 로그인 확인
6. 암호 변경용 Reauthentication OTP 수신 확인
7. 회원탈퇴 Edge Function을 새 버전으로 배포
8. 회원탈퇴 인증번호만 수신 확인하고 실제 탈퇴는 취소

`info@lkgrouptrading.com`으로 회신을 받고 싶다면 Google Workspace,
Microsoft 365 또는 Cloudflare Email Routing 같은 수신 서비스는 별도로
설정해야 한다.
