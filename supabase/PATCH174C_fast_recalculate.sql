-- Patch174C: 재연산 시 Patch168 bulk-import trigger guard 재사용
create or replace function public.admin_finalize_excel_batch_rules_fast(
  p_route text,
  p_year integer,
  p_voyage text,
  p_resequence boolean default true
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform set_config('lkgroup.bulk_import', '1', true);

  perform public.admin_finalize_excel_batch_rules(
    p_route,
    p_year,
    p_voyage,
    p_resequence
  );

  perform set_config('lkgroup.bulk_import', '0', true);
end;
$$;

grant execute on function public.admin_finalize_excel_batch_rules_fast(
  text, integer, text, boolean
) to authenticated;
