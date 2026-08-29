-- 046_unknown_recipient_claims.sql
-- 수취인 불명 화물 공개(제한 필드) + 본인 화물 확인/정정 요청 + 관리자 승인

alter table public.shipments
  add column if not exists recipient_unknown boolean not null default false;
alter table public.shipments
  add column if not exists recipient_unknown_confirmed_at timestamptz;
alter table public.shipments
  add column if not exists recipient_unknown_confirmed_by uuid references auth.users(id);

create index if not exists shipments_recipient_unknown_idx
  on public.shipments(recipient_unknown)
  where recipient_unknown = true;

-- "수취인 불명 / 고객명"으로 최종 확인된 건은 다시 unknown 처리하지 않습니다.
create or replace function public.refresh_recipient_unknown_flag()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  n text := lower(btrim(coalesce(new.consignee_name, '')));
  p text := regexp_replace(coalesce(new.consignee_phone, ''), '[^0-9]', '', 'g');
begin
  if new.recipient_unknown_confirmed_at is not null then
    new.recipient_unknown := false;
    return new;
  end if;

  new.recipient_unknown :=
    n = ''
    or n like '%수취인 불명%'
    or n like '%데이타 불문명%'
    or n like '%데이터 불문명%'
    or n like '%불명%'
    or (p = '' and (
      n = ''
      or n like '%unknown%'
      or n like '%미상%'
    ));

  return new;
end;
$$;

drop trigger if exists shipments_refresh_recipient_unknown on public.shipments;
create trigger shipments_refresh_recipient_unknown
before insert or update of consignee_name, consignee_phone,
  recipient_unknown_confirmed_at
on public.shipments
for each row execute function public.refresh_recipient_unknown_flag();

-- 기존 자료 보수적 backfill: 이름 자체가 수취인불명/불명/미상 계열인 것만.
update public.shipments
set recipient_unknown = true
where recipient_unknown_confirmed_at is null
  and (
    btrim(coalesce(consignee_name, '')) = ''
    or lower(consignee_name) like '%수취인 불명%'
    or lower(consignee_name) like '%데이타 불문명%'
    or lower(consignee_name) like '%데이터 불문명%'
    or lower(consignee_name) like '%unknown%'
    or lower(consignee_name) like '%미상%'
  );

create table if not exists public.unknown_recipient_claims (
  id bigint generated always as identity primary key,
  shipment_id bigint not null references public.shipments(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  claimant_name text not null,
  claimant_phone text not null,
  note text not null default '',
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(shipment_id, requester_id, status)
);

alter table public.unknown_recipient_claims enable row level security;

-- 직접 table 접근은 차단하고 RPC만 사용.
revoke all on public.unknown_recipient_claims from anon, authenticated;

-- 가입 일반회원에게 공개되는 필드는 아래 7개 + id만.
-- 정상 고객 화물은 recipient_unknown=true가 아니면 절대 반환하지 않음.
create or replace function public.list_unknown_recipient_cargo()
returns table(
  id bigint,
  route text,
  shipment_year integer,
  voyage text,
  box_number text,
  invoice_number text,
  consignee_name text,
  consignee_phone text,
  claim_pending boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다.';
  end if;

  if public.current_role() <> 'member' then
    return;
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
    ) as claim_pending
  from public.shipments s
  where s.recipient_unknown = true
    and s.recipient_unknown_confirmed_at is null
    and s.deletion_requested_at is null
  order by s.shipment_year desc, s.route, s.voyage, s.box_number;
end;
$$;

create or replace function public.create_unknown_recipient_claim(
  p_shipment_id bigint,
  p_claimant_name text,
  p_claimant_phone text,
  p_note text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  claim_id bigint;
  profile_name text;
  profile_phone text;
begin
  if public.current_role() <> 'member' then
    raise exception '일반 회원만 본인 화물 확인 요청을 할 수 있습니다.';
  end if;

  if nullif(btrim(p_claimant_name), '') is null
     or nullif(btrim(p_claimant_phone), '') is null then
    raise exception '본인 이름과 연락처를 모두 입력해 주세요.';
  end if;

  if not exists (
    select 1 from public.shipments
    where id = p_shipment_id
      and recipient_unknown = true
      and recipient_unknown_confirmed_at is null
      and deletion_requested_at is null
  ) then
    raise exception '현재 수취인 불명 상태의 화물이 아닙니다.';
  end if;

  if exists (
    select 1 from public.unknown_recipient_claims
    where shipment_id = p_shipment_id
      and requester_id = auth.uid()
      and status = 'pending'
  ) then
    raise exception '이미 확인 대기 중인 요청이 있습니다.';
  end if;

  insert into public.unknown_recipient_claims(
    shipment_id, requester_id, claimant_name, claimant_phone, note
  )
  values(
    p_shipment_id,
    auth.uid(),
    btrim(p_claimant_name),
    btrim(p_claimant_phone),
    coalesce(p_note, '')
  )
  returning id into claim_id;

  return claim_id;
end;
$$;

create or replace function public.admin_list_unknown_recipient_claims()
returns table(
  claim_id bigint,
  shipment_id bigint,
  route text,
  shipment_year integer,
  voyage text,
  box_number text,
  invoice_number text,
  current_unknown_name text,
  current_unknown_phone text,
  claimant_name text,
  claimant_phone text,
  requester_email text,
  note text,
  data_locked boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  return query
  select
    c.id,
    c.shipment_id,
    s.route,
    s.shipment_year,
    s.voyage,
    s.box_number,
    s.invoice_number,
    s.consignee_name,
    s.consignee_phone,
    c.claimant_name,
    c.claimant_phone,
    coalesce(p.email, ''),
    c.note,
    s.data_locked,
    c.created_at
  from public.unknown_recipient_claims c
  join public.shipments s on s.id = c.shipment_id
  left join public.profiles p on p.id = c.requester_id
  where c.status = 'pending'
  order by c.created_at;
end;
$$;

-- 현재 항차의 마지막 영수번호 뒷자리 숫자를 이어서 생성.
-- 특정 노선 포맷을 임의로 새로 만들지 않고, 실제 존재하는 마지막 영수번호 포맷을 복제.
-- 기존 영수번호가 하나도 없으면 임시 식별용 ID-01 사용.
create or replace function public.next_receipt_after_last(
  p_route text,
  p_year integer,
  p_voyage text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  last_receipt text;
  prefix text;
  digits text;
  next_no integer;
begin
  select s.receipt_number
    into last_receipt
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and s.voyage = p_voyage
    and nullif(btrim(s.receipt_number), '') is not null
    and s.deletion_requested_at is null
  order by
    coalesce(
      nullif((regexp_match(s.receipt_number, '([0-9]+)$'))[1], '')::integer,
      -1
    ) desc,
    s.id desc
  limit 1;

  if last_receipt is null then
    return 'ID-01';
  end if;

  digits := (regexp_match(last_receipt, '([0-9]+)$'))[1];
  if digits is null then
    return last_receipt || '-01';
  end if;

  prefix := left(last_receipt, length(last_receipt) - length(digits));
  next_no := digits::integer + 1;

  return prefix || lpad(next_no::text, greatest(length(digits), 2), '0');
end;
$$;

create or replace function public.admin_review_unknown_recipient_claim(
  p_claim_id bigint,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.unknown_recipient_claims%rowtype;
  s public.shipments%rowtype;
  next_receipt text;
begin
  if public.current_role() <> 'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  if p_action not in ('approve','reject') then
    raise exception '처리 방식이 올바르지 않습니다.';
  end if;

  select * into c
  from public.unknown_recipient_claims
  where id = p_claim_id
    and status = 'pending'
  for update;

  if not found then
    raise exception '대기 중인 요청을 찾을 수 없습니다.';
  end if;

  select * into s from public.shipments where id = c.shipment_id for update;
  if not found then
    raise exception '화물을 찾을 수 없습니다.';
  end if;

  if p_action = 'reject' then
    update public.unknown_recipient_claims
    set status='rejected', reviewed_by=auth.uid(), reviewed_at=now()
    where id=p_claim_id;
    return;
  end if;

  next_receipt := public.next_receipt_after_last(
    s.route, s.shipment_year, s.voyage
  );

  update public.shipments
  set
    consignee_name = '수취인 불명 / ' || btrim(c.claimant_name),
    consignee_phone = btrim(c.claimant_phone),
    receipt_number = next_receipt,
    recipient_unknown = false,
    recipient_unknown_confirmed_at = now(),
    recipient_unknown_confirmed_by = auth.uid()
  where id = c.shipment_id;

  update public.unknown_recipient_claims
  set status='approved', reviewed_by=auth.uid(), reviewed_at=now()
  where id=p_claim_id;

  -- 같은 화물에 다른 회원이 올린 중복 대기 요청은 자동 거절.
  update public.unknown_recipient_claims
  set status='rejected', reviewed_by=auth.uid(), reviewed_at=now()
  where shipment_id = c.shipment_id
    and id <> p_claim_id
    and status='pending';
end;
$$;

grant execute on function public.list_unknown_recipient_cargo() to authenticated;
grant execute on function public.create_unknown_recipient_claim(bigint,text,text,text) to authenticated;
grant execute on function public.admin_list_unknown_recipient_claims() to authenticated;
grant execute on function public.admin_review_unknown_recipient_claim(bigint,text) to authenticated;
