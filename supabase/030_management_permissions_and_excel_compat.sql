-- 030_management_permissions_and_excel_compat.sql
-- 요청된 관리 메뉴 권한을 DB/Storage/RPC에도 동일하게 적용합니다.
-- 화면 배치/기능 구조는 변경하지 않습니다.

-- 1) Excel 원본 템플릿 메타데이터: admin/staff/partner
drop policy if exists "excel template managers read" on public.shipment_excel_templates;
create policy "excel template managers read"
on public.shipment_excel_templates for select
using (public.current_role() in ('admin','staff','partner'));

drop policy if exists "excel template managers insert" on public.shipment_excel_templates;
create policy "excel template managers insert"
on public.shipment_excel_templates for insert
with check (public.current_role() in ('admin','staff','partner'));

drop policy if exists "excel template managers update" on public.shipment_excel_templates;
create policy "excel template managers update"
on public.shipment_excel_templates for update
using (public.current_role() in ('admin','staff','partner'))
with check (public.current_role() in ('admin','staff','partner'));

-- 2) Excel Storage: admin/staff/partner
drop policy if exists "excel managers read template objects" on storage.objects;
create policy "excel managers read template objects"
on storage.objects for select
using (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff','partner')
);

drop policy if exists "excel managers upload template objects" on storage.objects;
create policy "excel managers upload template objects"
on storage.objects for insert
with check (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff','partner')
);

drop policy if exists "excel managers update template objects" on storage.objects;
create policy "excel managers update template objects"
on storage.objects for update
using (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff','partner')
)
with check (
  bucket_id = 'shipment-excel-templates'
  and public.current_role() in ('admin','staff','partner')
);

drop policy if exists "excel managers read export objects" on storage.objects;
create policy "excel managers read export objects"
on storage.objects for select
using (
  bucket_id = 'shipment-excel-exports'
  and public.current_role() in ('admin','staff','partner')
);

-- 3) Excel 업로드가 Row data 고객 할인규칙까지 포함하는 경우 partner도 저장 가능.
drop policy if exists customer_rules_staff_admin_write on public.customer_rate_overrides;
create policy customer_rules_staff_admin_write
on public.customer_rate_overrides
for all
using (public.current_role() in ('admin','staff','partner'))
with check (public.current_role() in ('admin','staff','partner'));

-- 4) 기준 환율 입력: admin/staff
drop policy if exists exchange_admin_write on public.exchange_rate_settings;
create policy exchange_admin_write
on public.exchange_rate_settings
for all
using (public.current_role() in ('admin','staff'))
with check (public.current_role() in ('admin','staff'));

-- 5) 특수 견적 관리: admin/staff
drop policy if exists quotes_read_scoped on public.quote_requests;
create policy quotes_read_scoped on public.quote_requests
for select
using (
  requested_by = auth.uid()
  or public.current_role() in ('admin','staff')
);

drop policy if exists quote_messages_read_scoped on public.quote_messages;
create policy quote_messages_read_scoped on public.quote_messages
for select
using (
  exists (
    select 1
    from public.quote_requests q
    where q.id = quote_messages.quote_id
      and (
        q.requested_by = auth.uid()
        or public.current_role() in ('admin','staff')
      )
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
  if public.current_role() not in ('admin','staff') then
    raise exception '관리자(총괄) 또는 관리자(직원) 권한이 필요합니다.';
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

  if v_role in ('admin','staff') then
    -- 기존 UI/DB 호환을 위해 관리측 메시지는 sender_role='admin'을 유지합니다.
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
  if public.current_role() not in ('admin','staff') then
    raise exception '관리자(총괄) 또는 관리자(직원) 권한이 필요합니다.';
  end if;
  if trim(coalesce(p_message,'')) = '' then raise exception '답신 내용을 입력해 주세요.'; end if;

  update public.quote_messages
     set message = trim(p_message), updated_at = now()
   where id = p_message_id
     and sender_role = 'admin'
     and viewed_at is null;
  if not found then raise exception '요청자가 확인한 답신은 수정할 수 없습니다.'; end if;
end;
$$;

create or replace function public.delete_special_quote_admin_reply(p_message_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote_id bigint;
begin
  if public.current_role() not in ('admin','staff') then
    raise exception '관리자(총괄) 또는 관리자(직원) 권한이 필요합니다.';
  end if;

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
    update public.quote_requests set status = 'pending', updated_at = now()
     where id = v_quote_id;
  end if;
end;
$$;

create or replace function public.request_special_quote_delete(p_quote_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quote public.quote_requests%rowtype;
  v_is_manager boolean := public.current_role() in ('admin','staff');
  v_has_admin_reply boolean;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;

  select * into v_quote from public.quote_requests
   where id = p_quote_id and quote_type = 'special' and hidden_at is null
   for update;
  if not found then raise exception '견적 요청을 찾을 수 없습니다.'; end if;
  if not v_is_manager and v_quote.requested_by <> auth.uid() then
    raise exception '삭제 권한이 없습니다.';
  end if;

  select exists(
    select 1 from public.quote_messages
     where quote_id = p_quote_id and sender_role = 'admin'
  ) into v_has_admin_reply;

  if not v_is_manager and v_quote.admin_viewed_at is null then
    update public.quote_requests
       set hidden_at = now(),
           deletion_requested_at = now(),
           purge_after = now() + interval '30 days',
           deleted_by = auth.uid(),
           updated_at = now()
     where id = p_quote_id;
    return;
  end if;

  if not v_is_manager and not v_has_admin_reply then
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
     and (
       q.requested_by = auth.uid()
       or public.current_role() in ('admin','staff')
     );
  if not found then raise exception '삭제 취소 가능한 요청을 찾을 수 없습니다.'; end if;
end;
$$;

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
     and (
       q.requested_by = auth.uid()
       or public.current_role() in ('admin','staff')
     );
  if not found then raise exception '바로 삭제 가능한 요청을 찾을 수 없습니다.'; end if;
end;
$$;

grant execute on function public.list_admin_special_quotes() to authenticated;
grant execute on function public.add_special_quote_message(bigint,text) to authenticated;
grant execute on function public.update_special_quote_admin_reply(bigint,text) to authenticated;
grant execute on function public.delete_special_quote_admin_reply(bigint) to authenticated;
grant execute on function public.request_special_quote_delete(bigint) to authenticated;
grant execute on function public.cancel_special_quote_delete(bigint) to authenticated;
grant execute on function public.hide_special_quote_now(bigint) to authenticated;

-- 선적 일정/공지 및 안내는 기존 public.is_content_manager()가 staff/admin만 허용하므로 유지.
-- 회원 종합 관리 / 화물 내용 변경 승인 관리는 기존 admin-only RPC/정책을 유지.
