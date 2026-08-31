-- 091_admin_resolve_unknown_from_search.sql
-- 관리자도 화물 조회 화면의 수취인 불명 카드를 눌러 직접 정상화할 수 있게 함.

create or replace function public.admin_resolve_unknown_recipient_from_search(
  p_shipment_id bigint,
  p_consignee_name text,
  p_consignee_phone text,
  p_notes text default ''
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_route text;
  v_year integer;
  v_voyage text;
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자 권한이 필요합니다.';
  end if;

  if coalesce(btrim(p_consignee_name),'') = ''
     and coalesce(btrim(p_consignee_phone),'') = '' then
    raise exception '이름 또는 연락처 중 하나 이상 입력해 주세요.';
  end if;

  select s.route,s.shipment_year,s.voyage
    into v_route,v_year,v_voyage
  from public.shipments s
  where s.id=p_shipment_id
  limit 1;

  if v_route is null then
    raise exception '화물을 찾을 수 없습니다.';
  end if;

  update public.shipments
  set consignee_name=btrim(coalesce(p_consignee_name,'')),
      consignee_phone=btrim(coalesce(p_consignee_phone,'')),
      notes=coalesce(p_notes,''),
      recipient_unknown=false,
      updated_at=now()
  where id=p_shipment_id;

  -- 기존 중앙 정규화 로직을 그대로 사용합니다.
  perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
end;
$$;

revoke all on function public.admin_resolve_unknown_recipient_from_search(
  bigint,text,text,text
) from public;
grant execute on function public.admin_resolve_unknown_recipient_from_search(
  bigint,text,text,text
) to authenticated,service_role;
