-- 062_shipment_search_own_history_permissions.sql
-- 관리자/직원: 전체 경로/년도/항차 검색 허용
-- 일반 회원: 별도 검색키 없이도 본인 화물 이력 전체 조회 허용
-- 파트너: 기존 관리자성 검색 규칙 유지

create or replace function public.search_shipments_for_current_user(
  p_route text default '',
  p_year integer default null,
  p_voyage text default '',
  p_box_number text default '',
  p_invoice text default '',
  p_recipient text default '',
  p_phone text default ''
)
returns setof public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_profile public.profiles%rowtype;
  v_invoice text := trim(coalesce(p_invoice, ''));
  v_recipient text := trim(coalesce(p_recipient, ''));
  v_phone_digits text := public.only_digits(p_phone);
  v_box text := trim(coalesce(p_box_number, ''));
begin
  select * into v_profile from public.profiles where id = auth.uid();
  v_role := v_profile.role;
  if v_role is null then return; end if;

  if v_role = 'member' then
    return query
    select s.*
      from public.shipments s
     where (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or
            ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (
            s.customer_id = auth.uid()
         or (
              coalesce(trim(v_profile.name),'') <> ''
              and lower(trim(coalesce(s.consignee_name,''))) =
                  lower(trim(v_profile.name))
            )
         or (
              length(public.only_digits(v_profile.phone)) >= 8
              and right(public.only_digits(s.consignee_phone), 8) =
                  right(public.only_digits(v_profile.phone), 8)
            )
       )
       and (v_invoice = '' or
            lower(coalesce(s.invoice_number,'')) like '%' || lower(v_invoice) || '%')
       and (v_recipient = '' or
            lower(coalesce(s.consignee_name,'')) like '%' || lower(v_recipient) || '%')
       and (v_phone_digits = '' or
            right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits)
     order by s.route, s.shipment_year desc, s.voyage desc,
              s.received_at desc nulls last, s.id desc
     limit 500;
    return;
  end if;

  if v_role in ('admin','staff','partner') then
    if v_invoice <> '' and length(v_invoice) < 4 then return; end if;
    if v_phone_digits <> '' and length(v_phone_digits) < 4 then return; end if;

    return query
    select s.*
      from public.shipments s
     where (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or
            ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (v_box = '' or lower(coalesce(s.box_number, '')) like '%' || lower(v_box) || '%')
       and (v_invoice = '' or lower(coalesce(s.invoice_number, '')) like '%' || lower(v_invoice) || '%')
       and (v_recipient = '' or lower(coalesce(s.consignee_name, '')) like '%' || lower(v_recipient) || '%')
       and (v_phone_digits = '' or right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits)
     order by s.route, s.shipment_year desc, s.voyage desc,
              s.received_at desc nulls last, s.id desc
     limit 1000;
  end if;
end;
$$;

grant execute on function public.search_shipments_for_current_user(
  text,integer,text,text,text,text,text
) to authenticated;
