-- 076_fix_fast_normalize_recursive_trigger.sql
-- Patch138e
-- Patch138d의 fast normalize 내부 UPDATE가 shipments AFTER trigger를 다시 호출하면서
-- normalize_shipment_batch()가 재진입한 문제 수정.
--
-- 해결:
-- 1) 현재 fast normalize 구현을 _impl 로 이름 변경
-- 2) public normalize wrapper가 세션-local re-entry flag를 켠 뒤 _impl 실행
-- 3) shipments_auto_normalize_trigger는 flag가 켜져 있으면 즉시 return
--
-- 따라서:
-- 외부 INSERT/UPDATE -> trigger -> normalize wrapper -> fast impl
-- fast impl 내부 UPDATE -> trigger -> flag 확인 후 skip
-- 으로 재귀가 끊깁니다.

do $$
begin
  if to_regprocedure('public.normalize_shipment_batch_fast_impl(text,integer,text)') is null
     and to_regprocedure('public.normalize_shipment_batch(text,integer,text)') is not null then
    alter function public.normalize_shipment_batch(text,integer,text)
      rename to normalize_shipment_batch_fast_impl;
  end if;
end;
$$;

create or replace function public.normalize_shipment_batch(
  p_route text,
  p_year integer,
  p_voyage text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_previous text;
begin
  v_previous := current_setting('lkgroup.normalizing_shipments', true);

  -- 이미 같은 normalize 실행 안에 있다면 다시 실행하지 않습니다.
  if coalesce(v_previous,'')='1' then
    return;
  end if;

  perform set_config('lkgroup.normalizing_shipments','1',true);

  begin
    perform public.normalize_shipment_batch_fast_impl(
      p_route,
      p_year,
      p_voyage
    );
  exception when others then
    perform set_config(
      'lkgroup.normalizing_shipments',
      coalesce(v_previous,''),
      true
    );
    raise;
  end;

  perform set_config(
    'lkgroup.normalizing_shipments',
    coalesce(v_previous,''),
    true
  );
end;
$$;

create or replace function public.shipments_auto_normalize_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  -- fast normalize 내부에서 shipments를 일괄 UPDATE할 때 발생하는 재귀 trigger 차단.
  if current_setting('lkgroup.normalizing_shipments', true)='1' then
    return coalesce(new,old);
  end if;

  -- 기존 안전장치도 유지.
  if pg_trigger_depth()>1 then
    return coalesce(new,old);
  end if;

  if tg_op='DELETE' then
    perform public.normalize_shipment_batch(
      old.route,
      old.shipment_year,
      old.voyage
    );
    return old;
  end if;

  perform public.normalize_shipment_batch(
    new.route,
    new.shipment_year,
    new.voyage
  );

  if tg_op='UPDATE'
     and (
       old.route is distinct from new.route
       or old.shipment_year is distinct from new.shipment_year
       or old.voyage is distinct from new.voyage
       or old.receipt_number is distinct from new.receipt_number
       or old.consignee_name is distinct from new.consignee_name
       or old.consignee_phone is distinct from new.consignee_phone
     ) then
    perform public.normalize_shipment_batch(
      old.route,
      old.shipment_year,
      old.voyage
    );
  end if;

  return new;
end;
$$;

revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text)
  to authenticated, service_role;
