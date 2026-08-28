-- 016_exchange_rate_cron.sql
-- 라오스(Vientiane, UTC+7) 기준 매일 오전 09:00에 1회 실행.
-- pg_cron은 UTC 기준이므로 02:00 UTC입니다.
--
-- 실행 전에 Supabase Vault에 아래 2개 secret이 있어야 합니다.
--   project_url     = https://<PROJECT_REF>.supabase.co
--   anon_key        = 프로젝트의 legacy anon key
--
-- Supabase 공식 권장 방식대로 Vault 값으로 Edge Function을 호출합니다.

-- 같은 이름의 기존 job이 있으면 중복 생성 방지
select cron.unschedule(jobid)
from cron.job
where jobname = 'lkgroup-exchange-rate-sync';

select cron.schedule(
  'lkgroup-exchange-rate-sync',
  '0 2 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret
            from vault.decrypted_secrets
            where name = 'project_url'
            limit 1) || '/functions/v1/update-exchange-rates',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (select decrypted_secret
                 from vault.decrypted_secrets
                 where name = 'anon_key'
                 limit 1),
      'Authorization', 'Bearer ' || (select decrypted_secret
                                    from vault.decrypted_secrets
                                    where name = 'anon_key'
                                    limit 1)
    ),
    body := jsonb_build_object('trigger', 'cron', 'requested_at', now()),
    timeout_milliseconds := 15000
  ) as request_id;
  $$
);
