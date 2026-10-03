CREATE OR REPLACE FUNCTION public.list_admin_special_quotes()
 RETURNS TABLE(id bigint, route text, subject text, content text, other_contact text, customer_name text, contact_phone text, contact_email text, status text, admin_viewed_at timestamp with time zone, deletion_requested_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, messages jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public.current_role() not in ('admin','staff') then
    raise exception '관리자(총괄) 또는 관리자(직원) 권한이 필요합니다.';
  end if;


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
$function$
;

CREATE OR REPLACE FUNCTION public.list_my_special_quotes()
 RETURNS TABLE(id bigint, route text, subject text, content text, other_contact text, customer_name text, contact_phone text, contact_email text, status text, admin_viewed_at timestamp with time zone, deletion_requested_at timestamp with time zone, created_at timestamp with time zone, updated_at timestamp with time zone, messages jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;



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
$function$
;
