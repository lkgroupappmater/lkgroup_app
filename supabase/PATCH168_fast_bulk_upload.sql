-- Patch168: fast Excel bulk upload
-- Root cause confirmed from current DB source:
-- trg_shipments_auto_normalize is FOR EACH ROW and calls normalize_shipment_batch().
-- During a 404-row Excel upload that means the whole voyage can be normalized
-- hundreds of times. This patch suppresses that trigger only inside the dedicated
-- Excel bulk RPC. Patch167 finalizer then normalizes the uploaded voyage once.

create or replace function public.shipments_auto_normalize_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  -- Existing recursion guard + Patch168 bulk-import guard.
  if current_setting('lkgroup.normalizing_shipments', true) = '1'
     or current_setting('lkgroup.bulk_import', true) = '1'
     or pg_trigger_depth() > 1
  then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    perform public.normalize_shipment_batch(
      old.route, old.shipment_year, old.voyage
    );
    return old;
  end if;

  perform public.normalize_shipment_batch(
    new.route, new.shipment_year, new.voyage
  );

  if tg_op = 'UPDATE'
     and (
       old.route is distinct from new.route
       or old.shipment_year is distinct from new.shipment_year
       or old.voyage is distinct from new.voyage
     )
  then
    perform public.normalize_shipment_batch(
      old.route, old.shipment_year, old.voyage
    );
  end if;

  return new;
end
$$;

-- Dedicated wrapper. It does NOT replace the existing manager RPC, so manual/other
-- callers keep the old automatic behavior. The setting is LOCAL to this transaction.
create or replace function public.manager_upsert_unlocked_shipments_bulk(
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception '화물 Excel 업로드 권한이 없습니다.';
  end if;

  perform set_config('lkgroup.bulk_import', '1', true);

  v_count := public.manager_upsert_unlocked_shipments(p_rows);

  -- Explicitly clear before returning. It is transaction-local regardless.
  perform set_config('lkgroup.bulk_import', '', true);

  return v_count;
exception when others then
  perform set_config('lkgroup.bulk_import', '', true);
  raise;
end
$$;

revoke all on function public.manager_upsert_unlocked_shipments_bulk(jsonb) from public;
grant execute on function public.manager_upsert_unlocked_shipments_bulk(jsonb)
  to authenticated, service_role;
