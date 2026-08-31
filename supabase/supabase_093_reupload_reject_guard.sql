-- 093_reupload_reject_guard.sql
-- Patch161-B: 잠금 재업로드 변경요청 '거절' 안전장치
--
-- 원칙:
-- reject = 현재 shipments 데이터는 절대 수정하지 않음
-- approve / modified_approve 만 변경값을 shipments에 반영
--
-- 기존 review RPC를 갈아엎지 않고 DB 레벨 보호 trigger를 추가합니다.
-- 따라서 UI/기존 승인 함수가 실수로 reject 처리 중 shipments를 변경하려 해도
-- pending 요청의 원래 잠금 화물 snapshot과 비교하여 보호합니다.

create or replace function public.lk_guard_rejected_locked_reupload()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_pending boolean;
begin
  -- 잠금 화물만 보호 대상
  if coalesce(old.data_locked,false)=false then
    return new;
  end if;

  -- 해당 화물에 pending 재업로드/수정 요청이 있는 동안,
  -- 요청 자체를 reject 처리하는 트랜잭션에서 원본 핵심값 변경을 막습니다.
  select exists(
    select 1
    from public.shipment_change_requests r
    where r.shipment_id=old.id
      and r.status='pending'
  ) into v_pending;

  if not v_pending then
    return new;
  end if;

  -- 승인 RPC는 실제 변경 전에 request status를 approved 계열로 바꾸거나
  -- 승인 로직에서 변경을 수행하므로 pending 상태가 아닐 때 통과합니다.
  -- pending 상태에서 잠금 화물의 핵심 업무값을 덮어쓰는 것은 차단합니다.
  if
    new.invoice_number is distinct from old.invoice_number or
    new.sender_name is distinct from old.sender_name or
    new.consignee_name is distinct from old.consignee_name or
    new.consignee_phone is distinct from old.consignee_phone or
    new.contents is distinct from old.contents or
    new.package_type is distinct from old.package_type or
    new.quantity is distinct from old.quantity or
    new.weight_kg is distinct from old.weight_kg or
    new.length_cm is distinct from old.length_cm or
    new.width_cm is distinct from old.width_cm or
    new.height_cm is distinct from old.height_cm or
    new.notes is distinct from old.notes or
    new.received_at is distinct from old.received_at
  then
    raise exception
      '잠금 화물에 처리 대기 중인 변경 요청이 있습니다. 승인 전 현재 데이터는 변경할 수 없습니다.';
  end if;

  return new;
end
$$;

drop trigger if exists trg_guard_rejected_locked_reupload on public.shipments;
create trigger trg_guard_rejected_locked_reupload
before update on public.shipments
for each row
execute function public.lk_guard_rejected_locked_reupload();

-- 관리자 진단: pending 요청이 있는 잠금 화물 확인
create or replace function public.admin_pending_locked_reupload_count()
returns bigint
language sql
security definer
set search_path=public
as $$
  select count(distinct s.id)
  from public.shipments s
  join public.shipment_change_requests r on r.shipment_id=s.id
  where coalesce(s.data_locked,false)=true
    and r.status='pending'
$$;

revoke all on function public.admin_pending_locked_reupload_count() from public;
grant execute on function public.admin_pending_locked_reupload_count()
  to authenticated,service_role;
