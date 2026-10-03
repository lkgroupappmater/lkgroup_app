-- Shared app/web consultation inbox. Listing is read-only; opening one request
-- acknowledges its notifications for the management team, starting the 24h clock.
alter table public.quote_requests add column if not exists request_kind text not null default 'quote' check (request_kind in ('quote','consultation'));
alter table public.quote_requests add column if not exists client_request_id uuid;
alter table public.quote_requests add column if not exists admin_viewed_by uuid references auth.users(id) on delete set null;
create unique index if not exists quote_requests_client_key on public.quote_requests(requested_by,client_request_id) where client_request_id is not null;
alter table public.quote_messages add column if not exists attachments jsonb not null default '[]'::jsonb;
alter table public.quote_messages add column if not exists reply_contact text not null default '';
alter table public.quote_messages add column if not exists client_message_id uuid;
create unique index if not exists quote_messages_client_key on public.quote_messages(quote_id,sender_id,client_message_id) where client_message_id is not null;
create index if not exists notifications_unread_owner on public.user_notifications(user_id,created_at desc) where not is_read;
create index if not exists notifications_read_owner on public.user_notifications(user_id,read_at desc) where is_read;

create or replace function public.lk_notify_support_team(p_quote_id bigint,p_message_id bigint default null)
returns void language sql security definer set search_path=public as $$
 insert into public.user_notifications(user_id,notification_type,title,message,related_quote_id,related_quote_message_id)
 select p.id,case when p_message_id is null then 'support_request' else 'support_followup' end,
   case when q.request_kind='consultation' then '1:1 상담 요청' else '견적 요청' end,
   coalesce(nullif(q.customer_name,''),'고객') || ' · ' || coalesce(nullif(q.subject,''),q.route,'') || case when p_message_id is null then '' else ' · 추가 메시지' end,q.id,p_message_id
 from public.profiles p cross join public.quote_requests q
 where q.id=p_quote_id and q.hidden_at is null and p.role in ('admin','staff') and p.deleted_at is null
   and coalesce(p.approval_status,'approved')='approved';
$$;
revoke all on function public.lk_notify_support_team(bigint,bigint) from public,anon,authenticated;

create or replace function public.lk_support_request_notification()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 perform public.lk_notify_support_team(new.id);
 return new;
end $$;
revoke all on function public.lk_support_request_notification() from public,anon,authenticated;
create trigger quote_request_team_notification after insert on public.quote_requests for each row execute function public.lk_support_request_notification();

create or replace function public.lk_support_message_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare q public.quote_requests%rowtype;
begin
 select * into q from public.quote_requests where id=new.quote_id;
 if new.sender_role='member' then
   perform public.lk_notify_support_team(new.quote_id,new.id);
 elsif q.requested_by is not null then
   insert into public.user_notifications(user_id,notification_type,title,message,related_quote_id,related_quote_message_id)
   values(q.requested_by,'special_quote_reply',case when q.request_kind='consultation' then '상담 회신' else '견적 요청 회신' end,
      coalesce(nullif(q.subject,''),'요청하신 내용') || ' · 관리자 회신이 도착했습니다.',q.id,new.id);
 end if;
 return new;
end $$;
revoke all on function public.lk_support_message_notification() from public,anon,authenticated;
create trigger quote_message_notification after insert on public.quote_messages for each row execute function public.lk_support_message_notification();

create or replace function public.list_support_requests(p_manager boolean default false,p_search text default '',p_kind text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if auth.uid() is null or (p_manager and coalesce(public.current_role(),'') not in ('admin','staff')) then raise exception '조회 권한이 없습니다.'; end if;
 select coalesce(jsonb_agg(to_jsonb(q) - 'requested_by' - 'client_request_id'),'[]'::jsonb) into result from (
   select q.id,q.route,q.quote_type,q.request_kind,q.subject,left(coalesce(nullif(q.content,''),q.note,''),240) as content,
     q.customer_name,q.contact_phone,q.contact_email,q.status,q.admin_viewed_at,q.deletion_requested_at,q.created_at,q.updated_at,
     exists(select 1 from public.user_notifications n where n.related_quote_id=q.id and n.user_id=auth.uid() and not n.is_read) as unread
   from public.quote_requests q where q.hidden_at is null and (p_manager or q.requested_by=auth.uid())
     and (coalesce(p_kind,'')='' or q.request_kind=p_kind)
     and (coalesce(trim(p_search),'')='' or concat_ws(' ',q.id::text,q.customer_name,q.contact_phone,q.contact_email,q.subject,q.content,q.route) ilike '%'||left(trim(p_search),120)||'%')
   order by q.updated_at desc,q.id desc offset greatest(0,least(coalesce(p_offset,0),100000)) limit 51
 ) q;
 return jsonb_build_object('rows',case when jsonb_array_length(result)>50 then result - 50 else result end,'has_more',jsonb_array_length(result)>50);
end $$;

create or replace function public.open_support_request(p_quote_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare q public.quote_requests%rowtype; manager boolean:=coalesce(public.current_role(),'') in ('admin','staff'); result jsonb;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 select * into q from public.quote_requests where id=p_quote_id and hidden_at is null for update;
 if not found or not (manager or q.requested_by=auth.uid()) then raise exception '요청을 찾을 수 없거나 조회 권한이 없습니다.'; end if;
 if manager then
   update public.quote_requests set admin_viewed_at=coalesce(admin_viewed_at,now()),admin_viewed_by=coalesce(admin_viewed_by,auth.uid()) where id=q.id returning * into q;
   update public.user_notifications n set is_read=true,read_at=now()
     where n.related_quote_id=q.id and not n.is_read and n.notification_type in ('support_request','support_followup');
   update public.quote_messages set viewed_at=coalesce(viewed_at,now()) where quote_id=q.id and sender_role='member' and viewed_at is null;
 end if;
 if q.requested_by=auth.uid() then
   update public.quote_messages set viewed_at=coalesce(viewed_at,now()) where quote_id=q.id and sender_role='admin' and viewed_at is null;
   update public.user_notifications set is_read=true,read_at=now() where related_quote_id=q.id and user_id=auth.uid() and not is_read;
 end if;
 result:=to_jsonb(q)-'client_request_id';
 if not manager then result:=result-'admin_note'-'admin_viewed_by'-'deleted_by'; end if;
 return result || jsonb_build_object('messages',coalesce((select jsonb_agg(to_jsonb(m)-'client_message_id' order by m.created_at,m.id) from public.quote_messages m where m.quote_id=q.id),'[]'::jsonb));
end $$;

create or replace function public.support_file_access(p_path text,p_upload boolean default false)
returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and exists(
   select 1 from public.quote_requests q where q.id::text=split_part(p_path,'/',1) and q.hidden_at is null
    and (q.requested_by=auth.uid() or coalesce(public.current_role(),'') in ('admin','staff'))
    and case when p_upload then q.deletion_requested_at is null and split_part(p_path,'/',2)=auth.uid()::text and p_path ~ '^[0-9]+/[0-9a-f-]+/[0-9a-f-]+\.[a-z0-9]+$'
     else split_part(p_path,'/',2)=auth.uid()::text or exists(select 1 from public.quote_messages m where m.quote_id=q.id and m.attachments @> jsonb_build_array(jsonb_build_object('path',p_path))) end
 );
$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('quote-attachments','quote-attachments',false,10485760,array['image/jpeg','image/png','image/webp','image/heic','application/pdf','application/zip','application/octet-stream','text/plain','text/csv','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.ms-excel.sheet.macroEnabled.12','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation']) on conflict(id) do nothing;
create policy quote_attachment_read on storage.objects for select to authenticated using(bucket_id='quote-attachments' and public.support_file_access(name,false));
create policy quote_attachment_upload on storage.objects for insert to authenticated with check(bucket_id='quote-attachments' and public.support_file_access(name,true));
-- An unsent upload can be removed by its uploader. Sent files remain part of the thread.
create policy quote_attachment_remove_unsent on storage.objects for delete to authenticated using(bucket_id='quote-attachments' and split_part(name,'/',2)=auth.uid()::text and public.support_file_access(name,true) and not exists(select 1 from public.quote_messages m where m.attachments @> jsonb_build_array(jsonb_build_object('path',name))));

create or replace function public.send_support_reply(p_quote_id bigint,p_message text,p_contact text default '',p_attachments jsonb default '[]'::jsonb,p_client_id uuid default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare q public.quote_requests%rowtype; manager boolean:=coalesce(public.current_role(),'') in ('admin','staff'); v_id bigint; a jsonb; clean jsonb:='[]'; v_meta jsonb;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 select * into q from public.quote_requests where id=p_quote_id and hidden_at is null for update;
 if not found or not (manager or q.requested_by=auth.uid()) then raise exception '회신 권한이 없습니다.'; end if;
 if q.deletion_requested_at is not null then raise exception '삭제 대기 중인 요청에는 회신할 수 없습니다.'; end if;
 if p_client_id is not null then select id into v_id from public.quote_messages where quote_id=q.id and sender_id=auth.uid() and client_message_id=p_client_id; if found then return v_id; end if; end if;
 if length(trim(coalesce(p_message,'')))=0 or length(p_message)>10000 or length(coalesce(p_contact,''))>500 then raise exception '회신 내용과 연락처를 확인해 주세요.'; end if;
 if p_attachments is null or jsonb_typeof(p_attachments)<>'array' or jsonb_array_length(p_attachments)>5 then raise exception '첨부파일은 최대 5개입니다.'; end if;
 for a in select value from jsonb_array_elements(p_attachments) loop
   if split_part(a->>'path','/',1)<>q.id::text or not coalesce(public.support_file_access(a->>'path',true),false) or length(coalesce(a->>'name','')) not between 1 and 180 then raise exception '첨부파일을 확인해 주세요.'; end if;
   select metadata into v_meta from storage.objects where bucket_id='quote-attachments' and name=a->>'path';
   if not found or coalesce((v_meta->>'size')::bigint,0)>10485760 then raise exception '첨부파일 업로드를 확인해 주세요.'; end if;
   clean:=clean||jsonb_build_array(jsonb_build_object('path',a->>'path','name',a->>'name','size',coalesce((v_meta->>'size')::bigint,0)));
 end loop;
 if manager then perform public.open_support_request(q.id); end if;
 insert into public.quote_messages(quote_id,sender_id,sender_role,message,reply_contact,attachments,client_message_id)
 values(q.id,auth.uid(),case when manager then 'admin' else 'member' end,trim(p_message),trim(coalesce(p_contact,'')),clean,p_client_id) returning id into v_id;
 update public.quote_requests set status=case when manager then 'replied' else 'pending' end,updated_at=now() where id=q.id;
 return v_id;
end $$;

-- Existing clients use this entry point too; notifications are emitted once by the trigger.
create or replace function public.add_special_quote_message(p_quote_id bigint,p_message text)
returns bigint language sql security definer set search_path=public as $$ select public.send_support_reply(p_quote_id,p_message); $$;

create or replace function public.start_staff_consultation(p_content text,p_route text default '',p_quote_id bigint default null,p_client_id uuid default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare p public.profiles%rowtype; v_id bigint;
begin
 if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
 if length(trim(coalesce(p_content,'')))=0 or length(p_content)>10000 then raise exception '상담 내용을 입력해 주세요.'; end if;
 if p_quote_id is not null then
   if not exists(select 1 from public.quote_requests where id=p_quote_id and requested_by=auth.uid() and hidden_at is null) then raise exception '요청을 찾을 수 없습니다.'; end if;
   perform public.send_support_reply(p_quote_id,'1:1 담당자 상담 요청' || E'\n' || trim(p_content),'','[]'::jsonb,p_client_id);
   return p_quote_id;
 end if;
 select * into p from public.profiles where id=auth.uid();
 if not found then raise exception '회원 정보를 확인해 주세요.'; end if;
 insert into public.quote_requests(requested_by,customer_name,contact_phone,contact_email,route,quote_type,request_kind,subject,content,status,client_request_id)
 values(p.id,coalesce(p.name,''),coalesce(p.phone,''),coalesce(p.email,''),left(trim(coalesce(p_route,'')),150),'special','consultation','1:1 담당자 상담',trim(p_content),'pending',p_client_id)
 on conflict(requested_by,client_request_id) where client_request_id is not null do update set client_request_id=excluded.client_request_id returning id into v_id;
 return v_id;
end $$;

create or replace function public.list_my_notification_feed(p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('unread_count',(select count(*) from public.user_notifications where user_id=auth.uid() and not is_read),
 'rows',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc,n.id desc) from (
   select id,title,message,notification_type,related_quote_id,related_quote_message_id,related_request_id,is_read,read_at,created_at
   from public.user_notifications where user_id=auth.uid() and (not is_read or read_at>=now()-interval '24 hours')
   order by created_at desc,id desc offset greatest(0,least(coalesce(p_offset,0),100000)) limit 50
 ) n),'[]'::jsonb));
$$;
create or replace function public.read_my_notification(p_notification_id bigint)
returns void language plpgsql security definer set search_path=public as $$
declare n public.user_notifications%rowtype;
begin
 select * into n from public.user_notifications where id=p_notification_id and user_id=auth.uid();
 if not found then raise exception '알림을 찾을 수 없습니다.'; end if;
 if n.related_quote_id is not null and exists(select 1 from public.quote_requests where id=n.related_quote_id and hidden_at is null) then perform public.open_support_request(n.related_quote_id);
 else update public.user_notifications set is_read=true,read_at=coalesce(read_at,now()) where id=n.id and not is_read; end if;
end $$;

-- Prevent old bulk-read screens from acknowledging unopened support requests.
drop policy if exists user_notifications_update_own on public.user_notifications;
create policy user_notifications_update_own on public.user_notifications for update to authenticated
 using(user_id=auth.uid() and related_quote_id is null) with check(user_id=auth.uid() and related_quote_id is null);
revoke update on public.user_notifications from authenticated;
grant update(is_read,read_at) on public.user_notifications to authenticated;

revoke all on function public.list_support_requests(boolean,text,text,integer),public.open_support_request(bigint),public.support_file_access(text,boolean),public.send_support_reply(bigint,text,text,jsonb,uuid),public.add_special_quote_message(bigint,text),public.start_staff_consultation(text,text,bigint,uuid),public.list_my_notification_feed(integer),public.read_my_notification(bigint) from public,anon;
grant execute on function public.list_support_requests(boolean,text,text,integer),public.open_support_request(bigint),public.support_file_access(text,boolean),public.send_support_reply(bigint,text,text,jsonb,uuid),public.add_special_quote_message(bigint,text),public.start_staff_consultation(text,text,bigint,uuid),public.list_my_notification_feed(integer),public.read_my_notification(bigint) to authenticated;
