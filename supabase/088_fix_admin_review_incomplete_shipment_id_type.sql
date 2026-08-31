-- 088_fix_admin_review_incomplete_shipment_id_type.sql
-- Screenshot error: "Bad state: 화물 ID가 올바르지 않습니다."
-- Root cause: Flutter service assumes shipment id is int, while DB/API may return UUID/text.
-- Fix: make RPC accept text and resolve shipments.id safely by text comparison.
-- No Flutter UI/layout changes.

drop function if exists public.admin_review_incomplete_shipment(integer,text,text,text,boolean);
drop function if exists public.admin_review_incomplete_shipment(bigint,text,text,text,boolean);
drop function if exists public.admin_review_incomplete_shipment(text,text,text,text,boolean);

create or replace function public.admin_review_incomplete_shipment(
  p_shipment_id text,
  p_consignee_name text,
  p_consignee_phone text,
  p_notes text,
  p_lock boolean
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text;
  v_route text;
  v_year integer;
  v_voyage text;
begin
  if coalesce(btrim(p_shipment_id),'')='' then
    raise exception '화물 ID가 비어 있습니다.';
  end if;

  select s.id::text,s.route,s.shipment_year,s.voyage
    into v_id,v_route,v_year,v_voyage
  from public.shipments s
  where s.id::text=btrim(p_shipment_id)
  limit 1;

  if v_id is null then
    raise exception '화물을 찾을 수 없습니다. id=%',p_shipment_id;
  end if;

  -- id의 실제 DB 타입(int/uuid)을 몰라도 안전하게 갱신
  update public.shipments s
  set consignee_name=btrim(coalesce(p_consignee_name,'')),
      consignee_phone=btrim(coalesce(p_consignee_phone,'')),
      notes=coalesce(p_notes,''),
      data_locked=coalesce(p_lock,false)
  where s.id::text=v_id;

  -- 잠금하지 않은 수정은 새 값 기준으로 receipt/zone 재정규화.
  -- 잠금인 경우에도 normalize 함수가 locked row를 보호하므로 호출 가능.
  perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
end $$;

revoke all on function public.admin_review_incomplete_shipment(text,text,text,text,boolean) from public;
grant execute on function public.admin_review_incomplete_shipment(text,text,text,text,boolean)
  to authenticated,service_role;
