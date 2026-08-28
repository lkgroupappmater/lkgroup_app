-- 018_cargo_search_change_approval_notifications.sql
-- Cargo search rules, actual member change-request workflow, manager approval,
-- and user notifications. Safe to run after the previous migrations.

-- ---------------------------------------------------------------------------
-- 1. Change request metadata + notification table
-- ---------------------------------------------------------------------------
alter table public.shipment_change_requests
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists admin_changes jsonb not null default '{}'::jsonb,
  add column if not exists review_result text;

alter table public.shipment_change_requests
  drop constraint if exists shipment_change_requests_review_result_check;
alter table public.shipment_change_requests
  add constraint shipment_change_requests_review_result_check
  check (review_result is null or review_result in ('approved','modified_approved','rejected'));

create table if not exists public.user_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null default 'shipment_change',
  title text not null default '',
  message text not null default '',
  related_request_id bigint references public.shipment_change_requests(id) on delete set null,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists user_notifications_user_unread_idx
  on public.user_notifications(user_id, is_read, created_at desc);

alter table public.user_notifications enable row level security;
drop policy if exists user_notifications_read_own on public.user_notifications;
drop policy if exists user_notifications_update_own on public.user_notifications;
create policy user_notifications_read_own on public.user_notifications
  for select using (user_id = auth.uid());
create policy user_notifications_update_own on public.user_notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, update on public.user_notifications to authenticated;

-- Member may read their own requests; admin may read/manage all pending requests.
drop policy if exists member_reads_own_change_requests on public.shipment_change_requests;
create policy member_reads_own_change_requests on public.shipment_change_requests
  for select using (requested_by = auth.uid() or public.current_role() = 'admin');

-- ---------------------------------------------------------------------------
-- 2. Utility helpers
-- ---------------------------------------------------------------------------
create or replace function public.only_digits(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_value, ''), '[^0-9]', '', 'g');
$$;

-- ---------------------------------------------------------------------------
-- 3. Shipment search with role-specific matching rules
-- ---------------------------------------------------------------------------
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
  v_invoice text := trim(coalesce(p_invoice, ''));
  v_recipient text := trim(coalesce(p_recipient, ''));
  v_phone_digits text := public.only_digits(p_phone);
  v_box text := trim(coalesce(p_box_number, ''));
begin
  select role into v_role from public.profiles where id = auth.uid();
  if v_role is null then
    return;
  end if;

  if v_role = 'member' then
    -- At least one strong identity criterion is required for member search.
    if length(v_invoice) < 4 and v_recipient = '' and length(v_phone_digits) < 8 then
      return;
    end if;

    return query
    select s.*
      from public.shipments s
     where (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (
         (length(v_invoice) >= 4 and lower(coalesce(s.invoice_number, '')) like '%' || lower(v_invoice))
         or (v_recipient <> '' and lower(trim(coalesce(s.consignee_name, ''))) = lower(v_recipient))
         or (length(v_phone_digits) >= 8 and right(public.only_digits(s.consignee_phone), 8) = right(v_phone_digits, 8))
       )
     order by s.received_at desc nulls last, s.id desc
     limit 300;
    return;
  end if;

  if v_role in ('admin','staff','partner') then
    -- Manager/partner search is intentionally permissive for correcting imported data.
    if v_invoice <> '' and length(v_invoice) < 4 then return; end if;
    if v_phone_digits <> '' and length(v_phone_digits) < 4 then return; end if;

    return query
    select s.*
      from public.shipments s
     where (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (v_box = '' or lower(coalesce(s.box_number, '')) like '%' || lower(v_box) || '%')
       and (v_invoice = '' or lower(coalesce(s.invoice_number, '')) like '%' || lower(v_invoice))
       and (v_recipient = '' or lower(coalesce(s.consignee_name, '')) like '%' || lower(v_recipient) || '%')
       and (v_phone_digits = '' or right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits)
     order by s.received_at desc nulls last, s.id desc
     limit 500;
  end if;
end;
$$;

grant execute on function public.search_shipments_for_current_user(text,integer,text,text,text,text,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Member creates actual change requests for selected cargo rows
-- ---------------------------------------------------------------------------
create or replace function public.create_shipment_change_requests(
  p_shipment_ids bigint[],
  p_changes jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_id bigint;
  v_shipment public.shipments%rowtype;
  v_count integer := 0;
  v_allowed jsonb;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  select * into v_profile from public.profiles where id = v_uid;
  if v_profile.role <> 'member' then
    raise exception '일반 회원의 수정 요청 전용 기능입니다.';
  end if;

  v_allowed := jsonb_strip_nulls(jsonb_build_object(
    'consignee_name', p_changes->'consignee_name',
    'consignee_phone', p_changes->'consignee_phone',
    'notes', p_changes->'notes'
  ));
  if v_allowed = '{}'::jsonb then raise exception '수정할 내용이 없습니다.'; end if;

  foreach v_id in array p_shipment_ids loop
    select * into v_shipment from public.shipments where id = v_id;
    if not found then continue; end if;

    -- Prevent a user from submitting a request for unrelated cargo even if an ID is guessed.
    if not (
      v_shipment.customer_id = v_uid
      or lower(trim(v_shipment.consignee_name)) = lower(trim(v_profile.name))
      or (
        length(public.only_digits(v_profile.phone)) >= 8
        and right(public.only_digits(v_shipment.consignee_phone), 8)
            = right(public.only_digits(v_profile.phone), 8)
      )
    ) then
      continue;
    end if;

    insert into public.shipment_change_requests(shipment_id, requested_by, changes, status)
    values (v_id, v_uid, v_allowed, 'pending');
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception '수정 요청 가능한 본인 화물을 확인할 수 없습니다.';
  end if;
  return v_count;
end;
$$;

grant execute on function public.create_shipment_change_requests(bigint[],jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Admin request list. Return current cargo values + requested changes.
-- ---------------------------------------------------------------------------
create or replace function public.get_pending_shipment_change_requests()
returns table(
  request_id bigint,
  shipment_id bigint,
  requester_id uuid,
  requester_name text,
  requester_email text,
  requested_changes jsonb,
  created_at timestamptz,
  box_number text,
  invoice_number text,
  route text,
  shipment_year integer,
  voyage text,
  consignee_name text,
  consignee_phone text,
  notes text,
  weight_kg numeric,
  length_cm numeric,
  width_cm numeric,
  height_cm numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  return query
  select r.id, r.shipment_id, r.requested_by,
         coalesce(p.name, ''), coalesce(p.email, ''), r.changes, r.created_at,
         s.box_number, s.invoice_number, s.route, s.shipment_year, s.voyage,
         s.consignee_name, s.consignee_phone, s.notes,
         s.weight_kg, s.length_cm, s.width_cm, s.height_cm
    from public.shipment_change_requests r
    join public.shipments s on s.id = r.shipment_id
    left join public.profiles p on p.id = r.requested_by
   where r.status = 'pending'
   order by r.created_at asc, r.id asc;
end;
$$;

grant execute on function public.get_pending_shipment_change_requests() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Admin approve / modify-and-approve / reject + notification creation
-- ---------------------------------------------------------------------------
create or replace function public.review_shipment_change_request(
  p_request_id bigint,
  p_action text,
  p_admin_changes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.shipment_change_requests%rowtype;
  v_final jsonb;
  v_message text;
  v_result text;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  select * into v_req
    from public.shipment_change_requests
   where id = p_request_id and status = 'pending'
   for update;
  if not found then raise exception '처리 가능한 요청을 찾을 수 없습니다.'; end if;

  if p_action = 'reject' then
    update public.shipment_change_requests
       set status = 'rejected', review_result = 'rejected',
           admin_changes = '{}'::jsonb, reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_request_id;
    v_message := '수정 요청이 거절 되었습니다.';
    v_result := 'rejected';
  elsif p_action in ('approve','modified_approve') then
    v_final := coalesce(v_req.changes, '{}'::jsonb) || coalesce(p_admin_changes, '{}'::jsonb);

    update public.shipments
       set invoice_number = case when v_final ? 'invoice_number' then coalesce(v_final->>'invoice_number','') else invoice_number end,
           consignee_name = case when v_final ? 'consignee_name' then coalesce(v_final->>'consignee_name','') else consignee_name end,
           consignee_phone = case when v_final ? 'consignee_phone' then coalesce(v_final->>'consignee_phone','') else consignee_phone end,
           notes = case when v_final ? 'notes' then coalesce(v_final->>'notes','') else notes end,
           weight_kg = case when v_final ? 'weight_kg' then nullif(v_final->>'weight_kg','')::numeric else weight_kg end,
           length_cm = case when v_final ? 'length_cm' then nullif(v_final->>'length_cm','')::numeric else length_cm end,
           width_cm = case when v_final ? 'width_cm' then nullif(v_final->>'width_cm','')::numeric else width_cm end,
           height_cm = case when v_final ? 'height_cm' then nullif(v_final->>'height_cm','')::numeric else height_cm end,
           updated_at = now()
     where id = v_req.shipment_id;

    if p_action = 'modified_approve' and coalesce(p_admin_changes, '{}'::jsonb) <> '{}'::jsonb then
      v_result := 'modified_approved';
      v_message := '관리자의 추가 수정 후 승인 되었습니다.';
    else
      v_result := 'approved';
      v_message := '승인 되었습니다.';
    end if;

    update public.shipment_change_requests
       set status = 'approved', review_result = v_result,
           admin_changes = coalesce(p_admin_changes, '{}'::jsonb),
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_request_id;
  else
    raise exception '지원하지 않는 처리 방식입니다.';
  end if;

  if v_req.requested_by is not null then
    insert into public.user_notifications(
      user_id, notification_type, title, message, related_request_id
    ) values (
      v_req.requested_by,
      'shipment_change',
      '화물 정보 수정 요청',
      v_message,
      p_request_id
    );
  end if;
end;
$$;

grant execute on function public.review_shipment_change_request(bigint,text,jsonb)
  to authenticated;
