-- One transaction for reviewed edits and multiple independent merge groups.
create function public.customer_registry_bulk_apply(p_owner uuid,p_rows jsonb,p_reason text default '')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare item jsonb; current_row public.customer_registry; target_row public.customer_registry;
 source_id uuid; target_id uuid; changed integer:=0; merged integer:=0; moved integer:=0; result jsonb;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'BULK_SELECTION_INVALID'; end if;
 if jsonb_array_length(p_rows) not between 1 and 100 or length(coalesce(p_reason,''))>500 then raise exception 'BULK_SELECTION_INVALID'; end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_rows) x)<>jsonb_array_length(p_rows) then raise exception 'BULK_SELECTION_INVALID'; end if;
 -- Validate every selected version before moving any source or changing a field.
 for item in select value from jsonb_array_elements(p_rows) order by value->>'id' loop
  source_id:=(item->>'id')::uuid; target_id:=(item->>'target_id')::uuid;
  if source_id is null or target_id is null or not exists(select 1 from jsonb_array_elements(p_rows) x where x->>'id'=target_id::text and x->>'target_id'=target_id::text) then raise exception 'BULK_SELECTION_INVALID'; end if;
  select * into current_row from public.customer_registry where id=source_id for update;
  if current_row.id is null or current_row.merged_into is not null or current_row.updated_at is distinct from (item->>'updated_at')::timestamptz then raise exception 'RECORD_CHANGED'; end if;
  if current_row.customer_no in (1,2) and source_id<>target_id then raise exception 'RESERVED_CUSTOMER_ID'; end if;
  if source_id=target_id and ((item->>'customer_no')::bigint is null or (item->>'customer_no')::bigint not between 1 and 999999999 or length(trim(coalesce(item->>'name',''))) not between 1 and 160 or length(coalesce(item->>'phone',''))>40) then raise exception 'INVALID_CUSTOMER_ID'; end if;
 end loop;
 -- Merging first allows the surviving ID to adopt a reviewed source's contact.
 for item in select value from jsonb_array_elements(p_rows) where value->>'id'<>value->>'target_id' order by value->>'id' loop
  select * into current_row from public.customer_registry where id=(item->>'id')::uuid;
  select * into target_row from public.customer_registry where id=(item->>'target_id')::uuid;
  result:=public.customer_registry_merge(current_row.id,target_row.id,p_owner,current_row.updated_at,target_row.updated_at,p_reason);
  merged:=merged+1; moved:=moved+(result->>'moved_sources')::integer;
 end loop;
 for item in select value from jsonb_array_elements(p_rows) where value->>'id'=value->>'target_id' order by value->>'id' loop
  select * into current_row from public.customer_registry where id=(item->>'id')::uuid;
  if current_row.customer_no is distinct from (item->>'customer_no')::bigint or current_row.name is distinct from trim(item->>'name') or current_row.phone is distinct from trim(coalesce(item->>'phone','')) then
   perform public.customer_registry_change(current_row.id,p_owner,(item->>'customer_no')::bigint,item->>'name',coalesce(item->>'phone',''),p_reason,current_row.updated_at);
   changed:=changed+1;
  end if;
 end loop;
 return jsonb_build_object('updated_count',changed,'merged_count',merged,'moved_sources',moved);
end $$;
revoke all on function public.customer_registry_bulk_apply(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.customer_registry_bulk_apply(uuid,jsonb,text) to service_role;
