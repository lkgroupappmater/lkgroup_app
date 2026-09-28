-- Uploaded common document copy is separate from quotation-only Remarks.
create table public.excel_quote_sources (
 route_key text primary key references public.route_definitions(route_key),
 storage_path text not null, source_at timestamptz not null, synced_at timestamptz,
 footer_lines jsonb, last_error text, attempted_at timestamptz
);
alter table public.excel_quote_sources enable row level security;
revoke all on public.excel_quote_sources from public,anon,authenticated;
grant all on public.excel_quote_sources to service_role;
grant select on public.excel_quote_sources to authenticated;
create policy excel_quote_sources_admin_read on public.excel_quote_sources for select to authenticated
 using(public.current_role()='admin');
create function public.lk_queue_excel_quote_source() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='shipment_excel_base_templates' then
  if not new.active or new.policy_summary ? 'validated_source_revision' then return new; end if;
 end if;
 insert into public.excel_quote_sources(route_key,storage_path,source_at)
 values(new.route_key,new.storage_path,clock_timestamp())
 on conflict(route_key) do update set storage_path=excluded.storage_path,source_at=excluded.source_at,
 synced_at=null,last_error=null,attempted_at=null;
 return new;
end $$;
revoke all on function public.lk_queue_excel_quote_source() from public,anon,authenticated;
create trigger excel_quote_base_uploaded after insert or update of storage_path on public.shipment_excel_base_templates
 for each row execute function public.lk_queue_excel_quote_source();
create trigger excel_quote_voyage_uploaded after insert or update of storage_path on public.shipment_excel_templates
 for each row execute function public.lk_queue_excel_quote_source();
-- Existing uploaded BASEs already contain the current common document text.
insert into public.excel_quote_sources(route_key,storage_path,source_at)
 select b.route_key,b.storage_path,b.updated_at from public.shipment_excel_base_templates b
 join public.route_definitions r using(route_key) where b.active and r.deleted_at is null
 on conflict do nothing;
create function public.lk_commit_excel_quote_context(p_route_key text,p_path text,p_source_at timestamptz,p_footer_lines jsonb)
 returns boolean language plpgsql security definer set search_path='' as $$
begin
 if jsonb_typeof(p_footer_lines)<>'array' or jsonb_array_length(p_footer_lines)>30 or length(p_footer_lines::text)>30000
 or exists(select 1 from jsonb_array_elements(p_footer_lines) e where jsonb_typeof(e)<>'string') then raise exception 'INVALID_DOCUMENT_COPY'; end if;
 update public.excel_quote_sources set footer_lines=p_footer_lines,synced_at=now(),attempted_at=now(),last_error=null
 where route_key=p_route_key and storage_path=p_path and source_at=p_source_at;
 return found;
end $$;
revoke all on function public.lk_commit_excel_quote_context(text,text,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function public.lk_commit_excel_quote_context(text,text,timestamptz,jsonb) to service_role;
create function public.get_quote_workbook_context(p_route_key text) returns jsonb
 language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('footer_lines',q.footer_lines,'source_at',q.source_at,'synced_at',q.synced_at)
 from public.excel_quote_sources q join public.route_definitions r using(route_key)
 where auth.uid() is not null and public.current_role()='admin'
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.deleted_at is null)
 and q.route_key=p_route_key and r.status='active' and r.deleted_at is null and q.synced_at is not null),'{}'::jsonb);
$$;
revoke all on function public.get_quote_workbook_context(text) from public,anon;
grant execute on function public.get_quote_workbook_context(text) to authenticated;
