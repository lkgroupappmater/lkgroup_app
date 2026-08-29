-- 041_shipment_delete_pending.sql
-- 화물 삭제는 먼저 삭제 대기로 이동하고, 삭제 취소 또는 바로 삭제할 수 있습니다.
-- 대상 권한: admin / staff / partner

alter table public.shipments
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deletion_requested_by uuid references auth.users(id);

create index if not exists idx_shipments_deletion_requested_at
  on public.shipments(deletion_requested_at)
  where deletion_requested_at is not null;

create or replace function public.manager_request_shipment_deletion(
  p_shipment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  update public.shipments
  set deletion_requested_at = now(),
      deletion_requested_by = auth.uid()
  where id = p_shipment_id;

  if not found then
    raise exception 'shipment not found';
  end if;
end;
$$;

create or replace function public.manager_list_pending_shipment_deletions()
returns table(
  id bigint,
  box_number text,
  route text,
  shipment_year integer,
  voyage text,
  invoice_number text,
  consignee_name text,
  deletion_requested_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    s.id,
    s.box_number,
    s.route,
    s.shipment_year,
    s.voyage,
    s.invoice_number,
    s.consignee_name,
    s.deletion_requested_at
  from public.shipments s
  where public.current_role() in ('admin','staff','partner')
    and s.deletion_requested_at is not null
  order by s.deletion_requested_at desc, s.id desc;
$$;

create or replace function public.manager_cancel_shipment_deletion(
  p_shipment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  update public.shipments
  set deletion_requested_at = null,
      deletion_requested_by = null
  where id = p_shipment_id
    and deletion_requested_at is not null;

  if not found then
    raise exception 'pending shipment not found';
  end if;
end;
$$;

create or replace function public.manager_delete_shipment_now(
  p_shipment_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  delete from public.shipments
  where id = p_shipment_id
    and deletion_requested_at is not null;

  if not found then
    raise exception 'pending shipment not found';
  end if;
end;
$$;

grant execute on function public.manager_request_shipment_deletion(bigint)
to authenticated;

grant execute on function public.manager_list_pending_shipment_deletions()
to authenticated;

grant execute on function public.manager_cancel_shipment_deletion(bigint)
to authenticated;

grant execute on function public.manager_delete_shipment_now(bigint)
to authenticated;

-- 기존 검색/Excel export 등에서는 삭제 대기 화물을 제외하는 것이 안전합니다.
-- 현재 검색 RPC 자체는 프로젝트별 구현이므로, 우선 직접 조회/API에서 사용할 수 있도록
-- 상태 플래그를 shipments에 보관합니다.
