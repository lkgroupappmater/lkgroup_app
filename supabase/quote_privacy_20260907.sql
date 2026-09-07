begin;
-- Retain existing owner/manager policies; remove legacy unrestricted test access.
drop policy if exists allow_test_select on public.quote_requests;
drop policy if exists allow_test_insert on public.quote_requests;
commit;
