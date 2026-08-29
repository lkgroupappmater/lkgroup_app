-- 048_unknown_recipient_visibility_aging_guide.sql
-- 수취인 불명 화물: 모든 로그인 가입자에게 노출 + 입력일(created_at) 제공
-- 본인 화물 확인/정정 요청 권한은 기존처럼 일반회원(member)만 유지.

drop function if exists public.list_unknown_recipient_cargo();

create function public.list_unknown_recipient_cargo()
returns table(
  id bigint,
  route text,
  shipment_year integer,
  voyage text,
  box_number text,
  invoice_number text,
  consignee_name text,
  consignee_phone text,
  claim_pending boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  return query
  select
    s.id,
    s.route,
    s.shipment_year,
    s.voyage,
    s.box_number,
    s.invoice_number,
    s.consignee_name,
    s.consignee_phone,
    exists (
      select 1
      from public.unknown_recipient_claims c
      where c.shipment_id = s.id
        and c.requester_id = auth.uid()
        and c.status = 'pending'
    ) as claim_pending,
    s.created_at
  from public.shipments s
  where s.recipient_unknown = true
    and s.recipient_unknown_confirmed_at is null
    and s.deletion_requested_at is null
  order by s.created_at asc, s.shipment_year desc, s.route, s.voyage, s.box_number;
end;
$$;

grant execute on function public.list_unknown_recipient_cargo() to authenticated;
