-- 015_exchange_rate_auto_sync.sql
-- 기존 exchange_rate_settings 테이블의 화면/기존 컬럼은 그대로 유지하고
-- 자동 환율 수집용 상태 컬럼만 추가합니다.

alter table public.exchange_rate_settings
  add column if not exists rate_source text,
  add column if not exists auto_sync_enabled boolean not null default true,
  add column if not exists last_fetch_at timestamptz,
  add column if not exists source_updated_at timestamptz,
  add column if not exists fetch_status text,
  add column if not exists last_fetch_error text;

update public.exchange_rate_settings
set
  rate_source = coalesce(rate_source, 'manual'),
  fetch_status = coalesce(fetch_status, 'not_fetched')
where id = 1;

comment on column public.exchange_rate_settings.rate_source is '기준환율 원본 출처';
comment on column public.exchange_rate_settings.auto_sync_enabled is '자동 환율 동기화 사용 여부';
comment on column public.exchange_rate_settings.last_fetch_at is '외부 환율 API 마지막 호출 시각';
comment on column public.exchange_rate_settings.source_updated_at is '외부 환율 제공처의 데이터 갱신 시각';
comment on column public.exchange_rate_settings.fetch_status is '마지막 자동 환율 호출 상태';
comment on column public.exchange_rate_settings.last_fetch_error is '마지막 자동 환율 호출 오류';

-- Cron/pg_net 사용 준비. 이미 활성화되어 있으면 그대로 유지됩니다.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
