-- 022_special_quote_privacy_admin_list_fix.sql
-- 1) 특수 견적은 요청 당사자와 총괄 관리자만 SELECT 가능
-- 2) list_admin_special_quotes()의 output-column/테이블-column 이름 충돌 제거
-- 기존 견적 데이터/화면 구조는 변경하지 않습니다.

-- quote_requests RLS를 명확하게 제한합니다.
drop policy if exists quotes_read_scoped on public.quote_requests;
create policy quotes_read_scoped on public.quote_requests
  for select
  using (
    requested_by = auth.uid()
    or public.current_role() in ('admin','staff')
  );

-- 특수 견적은 직원이 아니라 총괄 관리자만 전체 열람.
drop policy if exists special_quotes_read_scoped on public.quote_requests;
create policy special_quotes_read_scoped on public.quote_requests
  for select
  using (
    quote_type <> 'special'
    or requested_by = auth.uid()
    or public.current_role() = 'admin'
  );

-- 기존 quotes_read_scoped가 special까지 staff에게 허용하지 않도록 하나의 정책으로 다시 정리.
drop policy if exists quotes_read_scoped on public.quote_requests;
drop policy if exists special_quotes_read_scoped on public.quote_requests;
create policy quotes_read_scoped on public.quote_requests
  for select
  using (
    requested_by = auth.uid()
    or (
      quote_type = 'special'
      and public.current_role() = 'admin'
    )
    or (
      quote_type <> 'special'
      and public.current_role() in ('admin','staff')
    )
  );

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

  update public.quote_requests as qr
     set admin_viewed_at = coalesce(qr.admin_viewed_at, now()),
         updated_at = now()
   where qr.quote_type = 'special'
     and qr.hidden_at is null;

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

-- 요청자 목록 함수는 이미 requested_by = auth.uid()로 제한되어 있으므로 유지합니다.
-- quote_messages 역시 quote 요청자 또는 총괄 관리자만 보도록 강화합니다.
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
