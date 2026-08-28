-- 019_special_quote_workflow.sql
-- 대량/특수 견적 요청, 회신 대화, 알림, 3일 삭제 대기, 30일 DB 보관.
-- 기존 일반 quote_requests 구조는 유지하고 quote_type='special'인 요청만 새 기능에서 사용합니다.

-- ---------------------------------------------------------------------------
-- 1. quote_requests 확장
-- ---------------------------------------------------------------------------
alter table public.quote_requests add column if not exists quote_type text not null default 'standard';
alter table public.quote_requests add column if not exists subject text not null default '';
alter table public.quote_requests add column if not exists content text not null default '';
alter table public.quote_requests add column if not exists other_contact text not null default '';
alter table public.quote_requests add column if not exists admin_viewed_at timestamptz;
alter table public.quote_requests add column if not exists deletion_requested_at timestamptz;
alter table public.quote_requests add column if not exists hidden_at timestamptz;
alter table public.quote_requests add column if not exists purge_after timestamptz;
alter table public.quote_requests add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create index if not exists quote_requests_special_requester_idx
  on public.quote_requests(quote_type, requested_by, created_at desc);
create index if not exists quote_requests_special_retention_idx
  on public.quote_requests(quote_type, deletion_requested_at, purge_after)
  where quote_type = 'special';

-- ---------------------------------------------------------------------------
-- 2. 견적 요청 대화
-- ---------------------------------------------------------------------------
create table if not exists public.quote_messages (
  id bigint generated always as identity primary key,
  quote_id bigint not null references public.quote_requests(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  sender_role text not null check (sender_role in ('member','admin')),
  message text not null,
  viewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists quote_messages_quote_idx
  on public.quote_messages(quote_id, created_at, id);

alter table public.quote_messages enable row level security;
drop policy if exists quote_messages_read_scoped on public.quote_messages;
create policy quote_messages_read_scoped on public.quote_messages
  for select using (
    exists (
      select 1
      from public.quote_requests q
      where q.id = quote_messages.quote_id
        and (q.requested_by = auth.uid() or public.current_role() = 'admin')
    )
  );

grant select on public.quote_messages to authenticated;

-- 기존 018 알림 테이블에 견적 요청 연결 컬럼만 추가.
alter table public.user_notifications
  add column if not exists related_quote_id bigint references public.quote_requests(id) on delete set null;
alter table public.user_notifications
  add column if not exists related_quote_message_id bigint references public.quote_messages(id) on delete set null;
create index if not exists user_notifications_quote_idx
  on public.user_notifications(user_id, related_quote_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 3. 요청 생성
-- ---------------------------------------------------------------------------
create or replace function public.create_special_quote_request(
  p_route text,
  p_subject text,
  p_content text,
  p_other_contact text default ''
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_id bigint;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if trim(coalesce(p_route, '')) = '' then
    raise exception '운송 경로를 선택해 주세요.';
  end if;
  if trim(coalesce(p_subject, '')) = '' or trim(coalesce(p_content, '')) = '' then
    raise exception '제목과 내용을 입력해 주세요.';
  end if;

  select * into v_profile from public.profiles where id = v_uid;

  insert into public.quote_requests(
    requested_by, customer_name, contact_phone, contact_email,
    route, quote_type, subject, content, other_contact,
    boxes, status, created_at, updated_at
  ) values (
    v_uid,
    coalesce(v_profile.name, ''),
    coalesce(v_profile.phone, ''),
    coalesce(v_profile.email, ''),
    trim(p_route), 'special', trim(p_subject), trim(p_content), trim(coalesce(p_other_contact, '')),
    '[]'::jsonb, 'pending', now(), now()
  ) returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_special_quote_request(text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. 요청자 목록. 이 화면을 열면 도착한 관리자 답신을 '읽음' 처리합니다.
-- ---------------------------------------------------------------------------
create or replace function public.list_my_special_quotes()
returns table(
  id bigint,
  route text,
  subject text,
  content text,
  other_contact text,
  customer_name text,
  contact_phone text,
  contact_email text,
  status text,
  admin_viewed_at timestamptz,
  deletion_requested_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  messages jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;

  update public.quote_messages m
     set viewed_at = coalesce(m.viewed_at, now())
    from public.quote_requests q
   where q.id = m.quote_id
     and q.requested_by = v_uid
     and q.quote_type = 'special'
     and q.hidden_at is null
     and m.sender_role = 'admin'
     and m.viewed_at is null;

  update public.user_notifications n
     set is_read = true,
         read_at = coalesce(n.read_at, now())
   where n.user_id = v_uid
     and n.related_quote_id is not null
     and n.notification_type = 'special_quote_reply'
     and n.is_read = false;

  return query
  select q.id, q.route, q.subject, q.content, q.other_contact,
         q.customer_name, q.contact_phone, q.contact_email,
         q.status, q.admin_viewed_at, q.deletion_requested_at,
         q.created_at, q.updated_at,
         coalesce((
           select jsonb_agg(
             jsonb_build_object(
               'id', m.id,
               'quote_id', m.quote_id,
               'sender_role', m.sender_role,
               'message', m.message,
               'viewed_at', m.viewed_at,
               'created_at', m.created_at,
               'updated_at', m.updated_at
             ) order by m.created_at, m.id
           )
           from public.quote_messages m
           where m.quote_id = q.id
         ), '[]'::jsonb) as messages
    from public.quote_requests q
   where q.quote_type = 'special'
     and q.requested_by = v_uid
     and q.hidden_at is null
   order by q.created_at desc, q.id desc;
end;
$$;

grant execute on function public.list_my_special_quotes() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. 총괄 관리자 목록. 목록을 열면 요청 내용은 관리자 열람으로 간주합니다.
-- ---------------------------------------------------------------------------
create or replace function public.list_admin_special_quotes()
returns table(
  id bigint,
  route text,
  subject text,
  content text,
  other_contact text,
  customer_name text,
  contact_phone text,
  contact_email text,
  status text,
  admin_viewed_at timestamptz,
  deletion_requested_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  messages jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  update public.quote_requests
     set admin_viewed_at = coalesce(admin_viewed_at, now()),
         updated_at = now()
   where quote_type = 'special'
     and hidden_at is null;

  return query
  select q.id, q.route, q.subject, q.content, q.other_contact,
         q.customer_name, q.contact_phone, q.contact_email,
         q.status, q.admin_viewed_at, q.deletion_requested_at,
         q.created_at, q.updated_at,
         coalesce((
           select jsonb_agg(
             jsonb_build_object(
               'id', m.id,
               'quote_id', m.quote_id,
               'sender_role', m.sender_role,
               'message', m.message,
               'viewed_at', m.viewed_at,
               'created_at', m.created_at,
               'updated_at', m.updated_at
             ) order by m.created_at, m.id
           )
           from public.quote_messages m
           where m.quote_id = q.id
         ), '[]'::jsonb) as messages
    from public.quote_requests q
   where q.quote_type = 'special'
     and q.hidden_at is null
   order by q.created_at desc, q.id desc;
end;
$$;

grant execute on function public.list_admin_special_quotes() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. 요청자 수정: 관리자 열람 전까지만 허용
-- ---------------------------------------------------------------------------
create or replace function public.update_special_quote_request(
  p_quote_id bigint,
  p_route text,
  p_subject text,
  p_content text,
  p_other_contact text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if trim(coalesce(p_subject,'')) = '' or trim(coalesce(p_content,'')) = '' then
    raise exception '제목과 내용을 입력해 주세요.';
  end if;

  update public.quote_requests
     set route = trim(p_route),
         subject = trim(p_subject),
         content = trim(p_content),
         other_contact = trim(coalesce(p_other_contact,'')),
         updated_at = now()
   where id = p_quote_id
     and quote_type = 'special'
     and requested_by = auth.uid()
     and hidden_at is null
     and deletion_requested_at is null
     and admin_viewed_at is null;

  if not found then
    raise exception '관리자가 확인한 견적 요청은 수정할 수 없습니다.';
  end if;
end;
$$;

grant execute on function public.update_special_quote_request(bigint,text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. 추가 대화 / 관리자 답변
-- ---------------------------------------------------------------------------
create or replace function public.add_special_quote_message(
  p_quote_id bigint,
  p_message text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quote_requests%rowtype;
  v_role text := public.current_role();
  v_sender_role text;
  v_id bigint;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if trim(coalesce(p_message,'')) = '' then raise exception '내용을 입력해 주세요.'; end if;

  select * into v_quote
    from public.quote_requests
   where id = p_quote_id and quote_type = 'special' and hidden_at is null
   for update;
  if not found then raise exception '견적 요청을 찾을 수 없습니다.'; end if;
  if v_quote.deletion_requested_at is not null then
    raise exception '삭제 대기 중인 견적 요청에는 회신할 수 없습니다.';
  end if;

  if v_role = 'admin' then
    v_sender_role := 'admin';
    update public.quote_requests
       set admin_viewed_at = coalesce(admin_viewed_at, now()),
           status = 'replied', updated_at = now()
     where id = p_quote_id;
  elsif v_quote.requested_by = auth.uid() then
    if not exists (
      select 1 from public.quote_messages
       where quote_id = p_quote_id and sender_role = 'admin'
    ) then
      raise exception '관리자 회신을 받은 후 추가 회신을 보낼 수 있습니다.';
    end if;
    v_sender_role := 'member';
    update public.quote_requests set status = 'replied', updated_at = now()
     where id = p_quote_id;
  else
    raise exception '견적 요청에 회신할 권한이 없습니다.';
  end if;

  insert into public.quote_messages(quote_id, sender_id, sender_role, message)
  values (p_quote_id, auth.uid(), v_sender_role, trim(p_message))
  returning id into v_id;

  if v_sender_role = 'admin' and v_quote.requested_by is not null then
    insert into public.user_notifications(
      user_id, notification_type, title, message, related_quote_id, related_quote_message_id
    ) values (
      v_quote.requested_by,
      'special_quote_reply',
      '견적 요청 회신',
      '요청하신 견적 요청 관련하여 회신을 받았습니다.',
      p_quote_id,
      v_id
    );
  end if;

  return v_id;
end;
$$;

grant execute on function public.add_special_quote_message(bigint,text) to authenticated;

-- 요청자가 읽기 전 관리자 답신만 수정 가능
create or replace function public.update_special_quote_admin_reply(
  p_message_id bigint,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'admin' then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if trim(coalesce(p_message,'')) = '' then raise exception '답신 내용을 입력해 주세요.'; end if;

  update public.quote_messages
     set message = trim(p_message), updated_at = now()
   where id = p_message_id
     and sender_role = 'admin'
     and viewed_at is null;
  if not found then raise exception '요청자가 확인한 답신은 수정할 수 없습니다.'; end if;
end;
$$;

grant execute on function public.update_special_quote_admin_reply(bigint,text) to authenticated;

create or replace function public.delete_special_quote_admin_reply(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote_id bigint;
begin
  if public.current_role() <> 'admin' then raise exception '총괄 관리자 권한이 필요합니다.'; end if;

  select quote_id into v_quote_id
    from public.quote_messages
   where id = p_message_id and sender_role = 'admin' and viewed_at is null
   for update;
  if v_quote_id is null then raise exception '요청자가 확인한 답신은 삭제할 수 없습니다.'; end if;

  delete from public.user_notifications
   where related_quote_message_id = p_message_id
     and is_read = false;

  delete from public.quote_messages where id = p_message_id;

  if not exists (
    select 1 from public.quote_messages where quote_id = v_quote_id and sender_role = 'admin'
  ) then
    update public.quote_requests set status = 'pending', updated_at = now() where id = v_quote_id;
  end if;
end;
$$;

grant execute on function public.delete_special_quote_admin_reply(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. 삭제 정책
-- 요청자: 관리자 열람 전에는 즉시 앱에서 숨기고 30일 보관.
--          관리자 열람 후 회신을 받은 건은 3일 삭제 대기 후 숨김.
-- 총괄: 항상 3일 삭제 대기, 삭제 취소/바로 삭제 가능.
-- ---------------------------------------------------------------------------
create or replace function public.request_special_quote_delete(p_quote_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quote_requests%rowtype;
  v_is_admin boolean := public.current_role() = 'admin';
  v_has_admin_reply boolean;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;

  select * into v_quote from public.quote_requests
   where id = p_quote_id and quote_type = 'special' and hidden_at is null
   for update;
  if not found then raise exception '견적 요청을 찾을 수 없습니다.'; end if;
  if not v_is_admin and v_quote.requested_by <> auth.uid() then
    raise exception '삭제 권한이 없습니다.';
  end if;

  select exists(
    select 1 from public.quote_messages where quote_id = p_quote_id and sender_role = 'admin'
  ) into v_has_admin_reply;

  if not v_is_admin and v_quote.admin_viewed_at is null then
    update public.quote_requests
       set hidden_at = now(),
           deletion_requested_at = now(),
           purge_after = now() + interval '30 days',
           deleted_by = auth.uid(),
           updated_at = now()
     where id = p_quote_id;
    return;
  end if;

  if not v_is_admin and not v_has_admin_reply then
    raise exception '관리자가 확인한 요청은 회신 전까지 삭제할 수 없습니다.';
  end if;

  update public.quote_requests
     set deletion_requested_at = coalesce(deletion_requested_at, now()),
         purge_after = coalesce(purge_after, now() + interval '30 days'),
         deleted_by = auth.uid(),
         updated_at = now()
   where id = p_quote_id;
end;
$$;

grant execute on function public.request_special_quote_delete(bigint) to authenticated;

create or replace function public.cancel_special_quote_delete(p_quote_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.quote_requests q
     set deletion_requested_at = null,
         purge_after = null,
         deleted_by = null,
         updated_at = now()
   where q.id = p_quote_id
     and q.quote_type = 'special'
     and q.hidden_at is null
     and q.deletion_requested_at is not null
     and (q.requested_by = auth.uid() or public.current_role() = 'admin');
  if not found then raise exception '삭제 취소 가능한 요청을 찾을 수 없습니다.'; end if;
end;
$$;

grant execute on function public.cancel_special_quote_delete(bigint) to authenticated;

create or replace function public.hide_special_quote_now(p_quote_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.quote_requests q
     set hidden_at = now(),
         purge_after = coalesce(q.purge_after, now() + interval '30 days'),
         deleted_by = coalesce(q.deleted_by, auth.uid()),
         updated_at = now()
   where q.id = p_quote_id
     and q.quote_type = 'special'
     and q.hidden_at is null
     and q.deletion_requested_at is not null
     and (q.requested_by = auth.uid() or public.current_role() = 'admin');
  if not found then raise exception '바로 삭제 가능한 요청을 찾을 수 없습니다.'; end if;
end;
$$;

grant execute on function public.hide_special_quote_now(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. 3일 후 앱에서 숨김 / 30일 후 DB 완전삭제
-- ---------------------------------------------------------------------------
create or replace function public.process_special_quote_retention()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.quote_requests
     set hidden_at = now(), updated_at = now()
   where quote_type = 'special'
     and hidden_at is null
     and deletion_requested_at is not null
     and deletion_requested_at <= now() - interval '3 days';

  delete from public.quote_requests
   where quote_type = 'special'
     and purge_after is not null
     and purge_after <= now();
end;
$$;

-- pg_cron이 이미 활성화된 프로젝트 기준. 1시간 간격으로 보관기한을 정리합니다.
do $$
declare
  v_jobid bigint;
begin
  if to_regclass('cron.job') is not null then
    for v_jobid in select jobid from cron.job where jobname = 'lkgroup-special-quote-retention'
    loop
      perform cron.unschedule(v_jobid);
    end loop;

    perform cron.schedule(
      'lkgroup-special-quote-retention',
      '17 * * * *',
      'select public.process_special_quote_retention();'
    );
  end if;
end $$;
