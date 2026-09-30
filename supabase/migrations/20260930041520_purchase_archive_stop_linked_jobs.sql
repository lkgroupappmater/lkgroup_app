-- Explicit opt-in allows archiving an order to stop its linked automation atomically.
-- Old two-argument callers retain their original active-job guard. No issued copies or shop carts are deleted.
CREATE OR REPLACE FUNCTION purchase_private.manage_orders(p_action text, p_orders jsonb, p_cancel_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target record; r public.purchase_orders; result jsonb:='[]'; count_ids integer;
begin
 if not purchase_private.allowed() then raise exception 'purchase:forbidden' using errcode='42501';end if;
 if p_action is null or p_action not in ('trash','restore','test','live') or jsonb_typeof(p_orders) is distinct from 'array' then raise exception 'purchase:selection';end if;
 if jsonb_array_length(p_orders) not between 1 and 200 then raise exception 'purchase:selection';end if;
 select count(distinct x->>'id') into count_ids from jsonb_array_elements(p_orders) x;
 if count_ids<>jsonb_array_length(p_orders) then raise exception 'purchase:selection';end if;
 -- Lock linked jobs before orders, matching worker result/apply order.
 perform 1 from purchase_private.shop_jobs j
 where j.order_id in (select (x->>'id')::uuid from jsonb_array_elements(p_orders) x)
 order by j.id for update;
 -- Lock in stable order; every selected revision must match or the whole operation rolls back.
 for target in select (x->>'id')::uuid id,(x->>'version')::integer version from jsonb_array_elements(p_orders) x order by 1 loop
  select * into r from public.purchase_orders where id=target.id for update;
  if not found or r.version is distinct from target.version then raise exception 'purchase:conflict' using errcode='40001';end if;
  if exists(select 1 from purchase_private.shop_jobs where order_id=r.id and state in ('queued','running','paused')) then
   if p_action='trash' and p_cancel_active is true then
    update purchase_private.shop_jobs set state='cancelled',reason='order_archived',updated_at=now()
    where order_id=r.id and state in ('queued','running','paused');
   else raise exception 'purchase:cart_active';end if;
  end if;
  if p_action='trash' and r.deleted_at is null then
   update public.purchase_orders set deleted_at=now(),deleted_by=auth.uid() where id=r.id returning * into r;
  elsif p_action='restore' and r.deleted_at is not null then
   update public.purchase_orders set deleted_at=null,deleted_by=null where id=r.id returning * into r;
  elsif p_action in ('test','live') then
   if r.deleted_at is not null then raise exception 'purchase:deleted';end if;
   if coalesce(r.payload->'is_test','false'::jsonb) is distinct from to_jsonb(p_action='test') then
    update public.purchase_orders set payload=jsonb_set(payload,'{is_test}',to_jsonb(p_action='test')) where id=r.id returning * into r;
   end if;
  end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',r.id,'version',r.version,'deleted_at',r.deleted_at,'is_test',coalesce(r.payload->'is_test','false'::jsonb)));
 end loop;
 return result;
end $function$
;
revoke all on function purchase_private.manage_orders(text,jsonb,boolean) from public, anon;
grant execute on function purchase_private.manage_orders(text,jsonb,boolean) to authenticated;
create or replace function public.manage_purchase_orders(p_action text,p_orders jsonb,p_cancel_active boolean)
returns jsonb language sql security invoker set search_path=''
as $function$ select purchase_private.manage_orders(p_action,p_orders,p_cancel_active); $function$;
revoke all on function public.manage_purchase_orders(text,jsonb,boolean) from public, anon;
grant execute on function public.manage_purchase_orders(text,jsonb,boolean) to authenticated;
notify pgrst, 'reload schema';
