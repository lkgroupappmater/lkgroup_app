-- Keep the feed read-only. Detail data is scoped by the notification recipient.
create or replace function public.get_my_notification_request(p_notification_id bigint)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',r.id,'shipment_id',r.shipment_id,'status',r.status,
   'changes',r.changes,'admin_changes',r.admin_changes,'before_values',r.excel_before_values,
   'review_result',r.review_result,'receipt_number',s.receipt_number,
   'invoice_number',s.invoice_number,'consignee_name',s.consignee_name)
 from public.user_notifications n
 join public.shipment_change_requests r on r.id=n.related_request_id
 left join public.shipments s on s.id=r.shipment_id
 where n.id=p_notification_id and n.user_id=auth.uid()
$$;
create or replace function public.list_my_notification_feed(p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
 'unread_count',(select count(*) from public.user_notifications where user_id=auth.uid() and not is_read),
 'read_through_id',(select coalesce(max(id),0) from public.user_notifications where user_id=auth.uid()),
 'read_through_at',statement_timestamp(),
 'rows',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc,n.id desc) from (
  select n.id,n.title,n.message,n.notification_type,n.related_quote_id,n.related_quote_message_id,
   n.related_request_id,n.is_read,n.read_at,n.created_at,
   public.get_my_notification_request(n.id) as request_details,
   case when q.id is not null then jsonb_build_object('subject',q.subject,'customer_name',q.customer_name,
    'content',coalesce(nullif(m.message,''),nullif(q.content,''),q.note),
    'contact',coalesce(nullif(m.reply_contact,''),nullif(q.contact_phone,''),q.contact),'route',q.route) end as quote_details
  from (select * from public.user_notifications where user_id=auth.uid()
   and (not is_read or read_at>=now()-interval '24 hours')
   order by created_at desc,id desc offset greatest(0,least(coalesce(p_offset,0),100000)) limit 50) n
  left join public.quote_requests q on q.id=n.related_quote_id and q.hidden_at is null
   and (q.requested_by=auth.uid() or coalesce(public.current_role(),'') in ('admin','staff'))
  left join public.quote_messages m on m.id=n.related_quote_message_id and m.quote_id=q.id
 ) n),'[]'::jsonb))
$$;
-- Explicit review of the feed snapshot, never approval of a shipment change.
create or replace function public.read_my_notifications(p_through_id bigint,p_through_at timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid:=auth.uid(); manager boolean:=coalesce(public.current_role(),'') in ('admin','staff');
 n record; q public.quote_requests%rowtype; marked integer:=0; changed integer;
begin
 if uid is null then raise exception '로그인이 필요합니다.'; end if;
 if p_through_id is null or p_through_at is null then raise exception '알림 목록을 새로고침해 주세요.'; end if;
 -- Iterate in deterministic order. Each event only acknowledges its matching team event.
 for n in select * from public.user_notifications where user_id=uid and not is_read
   and id<=p_through_id and created_at<=p_through_at order by id
 loop
  if n.related_quote_id is not null then
   select * into q from public.quote_requests where id=n.related_quote_id and hidden_at is null for update;
   if found and (manager or q.requested_by=uid) then
    if manager and n.notification_type in ('support_request','support_followup') then
     update public.quote_requests set admin_viewed_at=coalesce(admin_viewed_at,now()),
      admin_viewed_by=coalesce(admin_viewed_by,uid) where id=q.id;
     update public.user_notifications peer set is_read=true,read_at=now()
      where peer.related_quote_id=q.id and not peer.is_read and peer.id<>n.id
      and peer.notification_type=n.notification_type and peer.created_at<=p_through_at
      and peer.related_quote_message_id is not distinct from n.related_quote_message_id;
    end if;
    update public.quote_messages set viewed_at=coalesce(viewed_at,now())
     where id=n.related_quote_message_id and quote_id=q.id and created_at<=p_through_at
      and ((manager and sender_role='member') or (q.requested_by=uid and sender_role='admin'));
   end if;
  end if;
  update public.user_notifications set is_read=true,read_at=now() where id=n.id and user_id=uid and not is_read;
  get diagnostics changed=row_count; marked:=marked+changed;
 end loop;
 return jsonb_build_object('marked_count',marked,'unread_count',
  (select count(*) from public.user_notifications where user_id=uid and not is_read));
end $$;
revoke all on function public.get_my_notification_request(bigint) from public,anon;
revoke all on function public.list_my_notification_feed(integer) from public,anon;
revoke all on function public.read_my_notifications(bigint,timestamptz) from public,anon;
grant execute on function public.get_my_notification_request(bigint) to authenticated;
grant execute on function public.list_my_notification_feed(integer) to authenticated;
grant execute on function public.read_my_notifications(bigint,timestamptz) to authenticated;
