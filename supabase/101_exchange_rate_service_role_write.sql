-- update-exchange-rates Edge Function은 service role로 기준환율을 저장합니다.
-- RLS 우회 여부와 별개로 테이블 INSERT/UPDATE 권한이 필요합니다.
grant select, insert, update
on table public.exchange_rate_settings
to service_role;

