-- Staff and super administrators prepare quotations for requested customers.
create or replace function public.get_quote_workbook_context(p_route_key text) returns jsonb
 language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('footer_lines',q.footer_lines,'source_at',q.source_at,'synced_at',q.synced_at)
 from public.excel_quote_sources q join public.route_definitions r using(route_key)
 where auth.uid() is not null and public.current_role() in ('admin','staff')
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('admin','staff') and p.deleted_at is null)
 and q.route_key=p_route_key and r.status='active' and r.deleted_at is null and q.synced_at is not null),'{}'::jsonb);
$$;
revoke all on function public.get_quote_workbook_context(text) from public,anon;
grant execute on function public.get_quote_workbook_context(text) to authenticated;
