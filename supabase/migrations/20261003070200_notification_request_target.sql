create or replace function public.get_my_notification_request(p_notification_id bigint)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',r.id,'shipment_id',r.shipment_id,'status',r.status,'changes',r.changes,'admin_changes',r.admin_changes,
   'receipt_number',s.receipt_number,'invoice_number',s.invoice_number,'consignee_name',s.consignee_name)
 from public.user_notifications n join public.shipment_change_requests r on r.id=n.related_request_id
 left join public.shipments s on s.id=r.shipment_id where n.id=p_notification_id and n.user_id=auth.uid();
$$;
revoke all on function public.get_my_notification_request(bigint) from public,anon;
grant execute on function public.get_my_notification_request(bigint) to authenticated;
