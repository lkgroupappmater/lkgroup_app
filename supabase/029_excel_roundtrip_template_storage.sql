-- 029_excel_roundtrip_template_storage.sql
-- Excel 왕복 1차: 업로드한 원본 XLSX를 비공개 템플릿으로 보존하고
-- 앱/웹 공통 Export Edge Function이 같은 템플릿을 사용하도록 합니다.

create table if not exists public.shipment_excel_templates (
  id bigint generated always as identity primary key,
  route_key text not null,
  route_label text not null default '',
  shipment_year integer not null,
  voyage text not null,
  file_name text not null,
  storage_path text not null,
  uploaded_by uuid references auth.users(id) default auth.uid(),
  uploaded_at timestamptz not null default now(),
  unique(route_key, shipment_year, voyage)
);

alter table public.shipment_excel_templates enable row level security;

drop policy if exists "excel template managers read" on public.shipment_excel_templates;
create policy "excel template managers read"
on public.shipment_excel_templates for select
using (public.current_role() in ('admin','staff'));

drop policy if exists "excel template managers insert" on public.shipment_excel_templates;
create policy "excel template managers insert"
on public.shipment_excel_templates for insert
with check (public.current_role() in ('admin','staff'));

drop policy if exists "excel template managers update" on public.shipment_excel_templates;
create policy "excel template managers update"
on public.shipment_excel_templates for update
using (public.current_role() in ('admin','staff'))
with check (public.current_role() in ('admin','staff'));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'shipment-excel-templates',
  'shipment-excel-templates',
  false,
  20971520,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'shipment-excel-exports',
  'shipment-excel-exports',
  false,
  20971520,
  array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "excel managers read template objects" on storage.objects;
create policy "excel managers read template objects"
on storage.objects for select
using (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff')
);

drop policy if exists "excel managers upload template objects" on storage.objects;
create policy "excel managers upload template objects"
on storage.objects for insert
with check (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff')
);

drop policy if exists "excel managers update template objects" on storage.objects;
create policy "excel managers update template objects"
on storage.objects for update
using (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff')
)
with check (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff')
);

drop policy if exists "excel managers read export objects" on storage.objects;
create policy "excel managers read export objects"
on storage.objects for select
using (
  bucket_id = 'shipment-excel-exports'
  and public.current_role() in ('admin','staff')
);

grant select, insert, update on public.shipment_excel_templates to authenticated;
