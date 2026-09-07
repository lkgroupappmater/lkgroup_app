-- Shared app/web attachments and account-owned AI history. No cargo changes.
begin;
alter table public.notices add column if not exists attachments jsonb not null default '[]'::jsonb;
alter table public.shipping_schedules add column if not exists attachments jsonb not null default '[]'::jsonb;
alter table public.notices add constraint notices_attachments_array check(jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=12);
alter table public.shipping_schedules add constraint schedules_attachments_array check(jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=12);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('content-media','content-media',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy content_media_manager_read on storage.objects for select to authenticated using(
 bucket_id='content-media' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('admin','staff') and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active'));
create policy content_media_manager_upload on storage.objects for insert to authenticated with check(
 bucket_id='content-media' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role in ('admin','staff') and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active'));
create policy content_media_published_read on storage.objects for select to anon,authenticated using(bucket_id='content-media' and (
 exists(select 1 from public.notices n where n.deleted_at is null and n.deletion_status='active' and (n.published_at is null or n.published_at<=now()) and exists(select 1 from jsonb_array_elements(n.attachments) a where a->>'path'=objects.name))
 or exists(select 1 from public.shipping_schedules s where s.is_visible=true and s.deleted_at is null and s.deletion_status='active' and exists(select 1 from jsonb_array_elements(s.attachments) a where a->>'path'=objects.name))));

create table public.ai_consultations(
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 question text not null check(length(question) between 1 and 4000), answer text not null default '',
 language text not null check(language in ('ko','en','lo')),
 sources jsonb not null default '[]'::jsonb check(jsonb_typeof(sources)='array'),
 status text not null default 'pending' check(status in ('pending','completed','failed')),
 created_at timestamptz not null default now(), completed_at timestamptz
);
create index ai_consultations_user_created on public.ai_consultations(user_id,created_at desc);
alter table public.ai_consultations enable row level security;
revoke all on public.ai_consultations from public,anon,authenticated;
grant select on public.ai_consultations to authenticated;
grant select,insert,update,delete on public.ai_consultations to service_role;
create policy ai_consultations_owner_read on public.ai_consultations for select to authenticated using(user_id=(select auth.uid()) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active'));

create function public.reserve_ai_consultation(p_id uuid,p_user_id uuid,p_question text,p_language text)
returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare existing public.ai_consultations;
begin
 perform pg_advisory_xact_lock(hashtextextended('ai-consult:'||p_user_id::text,0));
 select * into existing from public.ai_consultations where id=p_id;
 if found then
   if existing.user_id<>p_user_id or existing.question<>p_question or existing.language<>p_language then raise exception 'Request conflict'; end if;
   return jsonb_build_object('created',false,'record',to_jsonb(existing));
 end if;
 if (select count(*) from public.ai_consultations where user_id=p_user_id and created_at>now()-interval '1 hour')>=30 then raise exception 'Consultation limit reached. Please try again later.'; end if;
 if exists(select 1 from public.ai_consultations where user_id=p_user_id and status='pending' and created_at>now()-interval '2 minutes') then raise exception 'A consultation is still being processed.'; end if;
 insert into public.ai_consultations(id,user_id,question,language) values(p_id,p_user_id,p_question,p_language) returning * into existing;
 return jsonb_build_object('created',true,'record',to_jsonb(existing));
end $$;
revoke all on function public.reserve_ai_consultation(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.reserve_ai_consultation(uuid,uuid,text,text) to service_role;
commit;
