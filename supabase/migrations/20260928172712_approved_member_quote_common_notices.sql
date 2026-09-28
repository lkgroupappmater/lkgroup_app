-- The owner approved common uploaded-workbook notices for ordinary members
-- on 2026-09-29 (Asia/Bangkok). Only the approved common notice lines are exposed.
create or replace function public.get_quote_workbook_context(p_route_key text) returns jsonb
 language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object(
   'footer_lines',q.footer_lines)
 from public.excel_quote_sources q join public.route_definitions r using(route_key)
 where auth.uid() is not null
 and exists(select 1 from public.profiles p where p.id=auth.uid()
   and p.role in ('admin','staff','member') and p.deleted_at is null)
 and q.route_key=p_route_key and r.status='active' and r.deleted_at is null
 and q.synced_at is not null),'{}'::jsonb);
$$;
revoke all on function public.get_quote_workbook_context(text) from public,anon;
grant execute on function public.get_quote_workbook_context(text) to authenticated;
