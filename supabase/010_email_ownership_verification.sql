-- 010_email_ownership_verification.sql
-- 관리자 임의 생성 계정과 사용자가 직접 이메일 OTP를 완료한 계정을
-- 구분하기 위한 업무용 확인 시각입니다.
--
-- Supabase Auth의 email_confirmed_at과 별개입니다.
-- 관리자 생성 계정은 로그인 가능하도록 Auth에서는 confirmed 처리하지만,
-- 실제 이메일 소유 확인은 사용자가 암호 변경 시 이메일 OTP를 통과했을 때
-- 이 컬럼에 기록됩니다.

alter table public.profiles
  add column if not exists email_ownership_verified_at timestamptz;

comment on column public.profiles.email_ownership_verified_at is
  'LKGroup app email ownership verification timestamp. Set after signup OTP or password-change reauthentication OTP.';

grant select, update on table public.profiles to authenticated;
