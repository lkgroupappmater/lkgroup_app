-- 038_exchange_adjustment_edit_and_export.sql
grant select on table public.exchange_rate_settings to service_role;
grant select, insert, update on table public.exchange_rate_settings to authenticated;
