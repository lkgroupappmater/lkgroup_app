create or replace function public.customer_registry_auto_apply(p_owner uuid,p_groups jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare g jsonb; item jsonb; c public.customer_registry; target uuid; payload jsonb; snapshot jsonb; saved jsonb;
 total integer:=0; moved integer:=0; reach integer; count_ integer; all_ids uuid[];
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN';end if;
 if jsonb_typeof(p_groups) is distinct from 'array' or jsonb_array_length(p_groups) not between 1 and 100 then raise exception 'BULK_SELECTION_INVALID';end if;
 for g in select value from jsonb_array_elements(p_groups) loop
  if jsonb_typeof(g) is distinct from 'array' or jsonb_array_length(g) not between 2 and 100 then raise exception 'BULK_SELECTION_INVALID';end if;
 end loop;
 select array_agg((x->>'id')::uuid) into all_ids from jsonb_array_elements(p_groups) as groups_(value) cross join lateral jsonb_array_elements(groups_.value) x;
 if cardinality(all_ids)>1000 or cardinality(all_ids)<>(select count(distinct v) from unnest(all_ids) v) then raise exception 'BULK_SELECTION_INVALID';end if;
 for g in select value from jsonb_array_elements(p_groups) loop
  for item in select value from jsonb_array_elements(g) order by value->>'id' loop
   select * into c from public.customer_registry where id=(item->>'id')::uuid for update;
   if c.id is null or c.merged_into is not null or c.updated_at is distinct from (item->>'updated_at')::timestamptz then raise exception 'RECORD_CHANGED';end if;
   if c.customer_no in(1,2) or c.name ~ '수취인[[:space:]]*불명' then raise exception 'AUTO_SELECTION_INVALID';end if;
  end loop;
  select id into target from public.customer_registry where id in(select (x->>'id')::uuid from jsonb_array_elements(g) x) order by customer_no limit 1;
  with recursive members as(select r.* from public.customer_registry r where r.id in(select (x->>'id')::uuid from jsonb_array_elements(g) x)),
  reachable(id) as(select target union select b.id from reachable r join members a on a.id=r.id cross join members b where public.lk_registry_auto_pair(a.name,a.phone,b.name,b.phone))
  select count(*) into reach from reachable;
  if reach<>jsonb_array_length(g) then raise exception 'AUTO_SELECTION_INVALID';end if;
  if cardinality(public.lk_registry_protection(array(select (x->>'id')::uuid from jsonb_array_elements(g) x)))>1 then raise exception 'SEPARATE_CUSTOMER_IDS';end if;
  select jsonb_agg(to_jsonb(r)||jsonb_build_object('target_id',target) order by r.customer_no) into payload from public.customer_registry r where id in(select (x->>'id')::uuid from jsonb_array_elements(g) x);
  select jsonb_agg(jsonb_build_object('customer',to_jsonb(r),'sources',coalesce((select jsonb_agg(s) from public.customer_registry_sources s where customer_registry_id=r.id),'[]'::jsonb),'aliases',coalesce((select jsonb_agg(a) from public.customer_registry_aliases a where customer_registry_id=r.id),'[]'::jsonb))) into snapshot from public.customer_registry r where id in(select (x->>'id')::uuid from jsonb_array_elements(g) x);
  saved:=public.customer_registry_bulk_apply(p_owner,payload,'Reviewed automatic duplicate merge');
  total:=total+(saved->>'merged_count')::integer; moved:=moved+(saved->>'moved_sources')::integer;
  insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason) values(target,p_owner,jsonb_build_object('members',snapshot),saved,'Reviewed automatic duplicate merge | recoverable snapshot');
 end loop;
 return jsonb_build_object('merged_count',total,'moved_sources',moved,'group_count',jsonb_array_length(p_groups));
end $$;
