-- 059_route_catalog_function_return_fix.sql
-- PostgreSQL에서는 RETURNS TABLE(...)의 OUT column 구성이 바뀌면
-- CREATE OR REPLACE FUNCTION으로 return type을 변경할 수 없습니다.
-- 기존 함수를 먼저 DROP 후 새 signature로 다시 생성합니다.

drop function if exists public.list_route_catalog_definitions();

create function public.list_route_catalog_definitions()
returns table(
  route_key text,
  display_name text,
  status text,
  base_route_key text,
  file_prefix text,
  box_prefix text,
  receipt_prefix text,
  document_title text,
  remark text
)
language sql
security definer
set search_path = public
as $$
  select
    r.route_key,
    r.display_name,
    r.status,
    coalesce(r.base_route_key, ''),
    r.file_prefix,
    r.box_prefix,
    r.receipt_prefix,
    r.document_title,
    r.remark
  from public.route_definitions r
  order by r.created_at, r.display_name
$$;

revoke all on function public.list_route_catalog_definitions() from public;
grant execute on function public.list_route_catalog_definitions()
  to anon, authenticated;
