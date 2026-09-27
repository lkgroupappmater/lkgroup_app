-- Customer identity changes only. Shipment contents and delivery rules stay authoritative.
-- Soft-deleted merge history may share the representative's new combined contact.

create table public.customer_registry_separation_names (
 name_key text primary key,
 separation_key text not null,
 display_name text not null
);
alter table public.customer_registry_separation_names enable row level security;
revoke all on public.customer_registry_separation_names from public,anon,authenticated;
grant select,insert,update,delete on public.customer_registry_separation_names to service_role;

create function public.lk_registry_tokens(v text,is_phone boolean default false) returns text[]
language sql immutable security invoker set search_path='' as $$
 select coalesce(array_agg(distinct k order by k),'{}'::text[]) from (
 select case when is_phone then public.lk_registry_phone(t) else public.lk_registry_name(t) end k
 from regexp_split_to_table(coalesce(v,''),case when is_phone then E'[/,;\\n\\r]+' else '/' end) t
 ) s where k<>'';
$$;
create function public.lk_registry_union(values_ text[],is_phone boolean default false) returns text
language sql immutable security invoker set search_path='' as $$
 with parts as (
 select trim(t) value,i,j,case when is_phone then public.lk_registry_phone(t) else public.lk_registry_name(t) end k
 from unnest(values_) with ordinality a(v,i)
 cross join lateral regexp_split_to_table(coalesce(v,''),case when is_phone then E'[/,;\\n\\r]+' else '/' end) with ordinality b(t,j)
 ), kept as (select distinct on(k) * from parts where k<>'' order by k,i,j)
 select coalesce(string_agg(value,' / ' order by i,j),'') from kept;
$$;
create function public.lk_registry_auto_pair(a_name text,a_phone text,b_name text,b_phone text) returns boolean
language sql immutable security invoker set search_path='' as $$
 with x as (select public.lk_registry_tokens(a_name) an,public.lk_registry_tokens(b_name) bn,
 public.lk_registry_tokens(a_phone,true) ap,public.lk_registry_tokens(b_phone,true) bp)
 select cardinality(an)>0 and cardinality(bn)>0 and cardinality(ap)>0 and cardinality(bp)>0
 and not exists(select 1 from unnest(ap||bp) p where length(p) not between 8 and 15)
 and ((ap=bp and abs(cardinality(an)-cardinality(bn))<=1 and (an<@bn or bn<@an))
 or (an=bn and abs(cardinality(ap)-cardinality(bp))<=1 and (ap<@bp or bp<@ap))) from x;
$$;
create function public.lk_registry_protection(ids uuid[]) returns text[]
language sql stable security invoker set search_path='' as $$
 select coalesce(array_agg(distinct p.separation_key),'{}'::text[])
 from public.customer_registry_separation_names p
 where exists(select 1 from public.customer_registry r where r.id=any(ids) and r.name_key=p.name_key)
 or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=any(ids) and a.name_key=p.name_key);
$$;
create or replace function public.customer_registry_change(p_id uuid,p_owner uuid,p_number bigint,p_name text,p_phone text,p_reason text,p_expected timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare old public.customer_registry; changed public.customer_registry; other_id uuid;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into old from public.customer_registry where id=p_id for update;
 if old.id is null or old.updated_at is distinct from p_expected or old.merged_into is not null then raise exception 'RECORD_CHANGED'; end if;
 if old.customer_no in (1,2) and old.customer_no<>p_number then raise exception 'RESERVED_CUSTOMER_ID'; end if;
 if p_name ~ '수취인[[:space:]]*불명' then raise exception 'UNKNOWN_CUSTOMER_NAME'; end if;
 if p_number not between 1 and 999999999 or length(trim(coalesce(p_name,''))) not between 1 and 160 or length(coalesce(p_phone,''))>160 then raise exception 'INVALID_CUSTOMER_ID'; end if;
 select customer_registry_id into other_id from public.customer_registry_aliases where name_key=public.lk_registry_name(p_name) and phone_key=public.lk_registry_phone(p_phone);
 if other_id is not null and other_id<>p_id then raise exception 'DUPLICATE_RECORD'; end if;
 if (select count(distinct k) from unnest(public.lk_registry_protection(array[p_id]) || coalesce((select array_agg(separation_key) from public.customer_registry_separation_names where name_key=public.lk_registry_name(p_name)),'{}'::text[])) k)>1 then raise exception 'SEPARATE_CUSTOMER_IDS';end if;
 update public.customer_registry set customer_no=p_number,name=trim(p_name),phone=trim(coalesce(p_phone,'')),updated_at=clock_timestamp() where id=p_id returning * into changed;
 insert into public.customer_registry_aliases values(changed.name_key,changed.phone_key,p_id,now()) on conflict do nothing;
 perform setval('public.customer_registry_number_seq',greatest((select last_value from public.customer_registry_number_seq),p_number),true);
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason)
 values(p_id,p_owner,to_jsonb(old),to_jsonb(changed),coalesce(nullif(trim(p_reason),''),'Customer details updated'));
 return to_jsonb(changed);
end $$;


create or replace function public.customer_registry_merge(p_source uuid,p_target uuid,p_owner uuid,p_source_expected timestamptz,p_target_expected timestamptz,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare src public.customer_registry; dst public.customer_registry; changed public.customer_registry; original_dst public.customer_registry;
 moved integer; combined_name text; combined_phone text; snapshot jsonb;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into src from public.customer_registry where id=p_source for update;
 select * into dst from public.customer_registry where id=p_target for update;
 if p_source=p_target or src.id is null or dst.id is null or src.merged_into is not null or dst.merged_into is not null or src.updated_at is distinct from p_source_expected or dst.updated_at is distinct from p_target_expected then raise exception 'RECORD_CHANGED'; end if;
 if src.customer_no in (1,2) then raise exception 'RESERVED_CUSTOMER_ID'; end if;
 if src.customer_no<dst.customer_no then raise exception 'LOWEST_CUSTOMER_ID_REQUIRED';end if;
 if cardinality(public.lk_registry_protection(array[p_source,p_target]))>1 then raise exception 'SEPARATE_CUSTOMER_IDS';end if;
 combined_name:=public.lk_registry_union(array[dst.name,src.name]);
 combined_phone:=public.lk_registry_union(array[dst.phone,src.phone],true);
 if length(combined_name)>160 or length(combined_phone)>160 then raise exception 'COMBINED_CONTACT_TOO_LONG';end if;
 if exists(select 1 from public.customer_registry_aliases where name_key=public.lk_registry_name(combined_name) and phone_key=public.lk_registry_phone(combined_phone) and customer_registry_id not in(p_source,p_target)) then raise exception 'DUPLICATE_RECORD';end if;
 original_dst:=dst;
 select jsonb_build_object('customer',to_jsonb(src),'sources',coalesce((select jsonb_agg(s) from public.customer_registry_sources s where customer_registry_id=p_source),'[]'::jsonb),'aliases',coalesce((select jsonb_agg(a) from public.customer_registry_aliases a where customer_registry_id=p_source),'[]'::jsonb)) into snapshot;
 update public.customer_registry_sources set customer_registry_id=p_target where customer_registry_id=p_source;
 get diagnostics moved=row_count;
 update public.customer_registry_aliases set customer_registry_id=p_target where customer_registry_id=p_source;
 update public.customer_registry set merged_into=p_target,updated_at=clock_timestamp() where id=p_source returning * into changed;
 update public.customer_registry set name=combined_name,phone=combined_phone,updated_at=clock_timestamp() where id=p_target returning * into dst;
 insert into public.customer_registry_aliases values(dst.name_key,dst.phone_key,p_target,now()) on conflict do nothing;
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason) values
 (p_source,p_owner,snapshot,to_jsonb(changed)||jsonb_build_object('moved_sources',moved),coalesce(nullif(trim(p_reason),''),'Reviewed duplicate merge')),
 (p_target,p_owner,to_jsonb(original_dst),to_jsonb(dst),coalesce(nullif(trim(p_reason),''),'Reviewed duplicate merge'));
 return to_jsonb(dst)||jsonb_build_object('moved_sources',moved);
end $$;
-- One transaction for reviewed edits and multiple independent merge groups.
create or replace function public.customer_registry_bulk_apply(p_owner uuid,p_rows jsonb,p_reason text default '')
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
  if source_id=target_id and ((item->>'customer_no')::bigint is null or (item->>'customer_no')::bigint not between 1 and 999999999 or length(trim(coalesce(item->>'name',''))) not between 1 and 160 or length(coalesce(item->>'phone',''))>160) then raise exception 'INVALID_CUSTOMER_ID'; end if;
 end loop;
 -- Merging first allows the surviving ID to adopt a reviewed source's contact.
 for item in select value from jsonb_array_elements(p_rows) where value->>'id'<>value->>'target_id' order by (value->>'customer_no')::bigint loop
  select * into current_row from public.customer_registry where id=(item->>'id')::uuid;
  select * into target_row from public.customer_registry where id=(item->>'target_id')::uuid;
  result:=public.customer_registry_merge(current_row.id,target_row.id,p_owner,current_row.updated_at,target_row.updated_at,p_reason);
  merged:=merged+1; moved:=moved+(result->>'moved_sources')::integer;
 end loop;
 for item in select value from jsonb_array_elements(p_rows) where value->>'id'=value->>'target_id' order by value->>'id' loop
  select * into current_row from public.customer_registry where id=(item->>'id')::uuid;
  -- Retain every merged name/phone even when an older client submits the old representative fields.
  if exists(select 1 from jsonb_array_elements(p_rows) x where x->>'target_id'=item->>'id' and x->>'id'<>item->>'id') then
   item:=item||jsonb_build_object('name',public.lk_registry_union(array[current_row.name,item->>'name']),'phone',public.lk_registry_union(array[current_row.phone,item->>'phone'],true));
  end if;
  if current_row.customer_no is distinct from (item->>'customer_no')::bigint or current_row.name is distinct from trim(item->>'name') or current_row.phone is distinct from trim(coalesce(item->>'phone','')) then
   perform public.customer_registry_change(current_row.id,p_owner,(item->>'customer_no')::bigint,item->>'name',coalesce(item->>'phone',''),p_reason,current_row.updated_at);
   changed:=changed+1;
  end if;
 end loop;
 return jsonb_build_object('updated_count',changed,'merged_count',merged,'moved_sources',moved);
end $$;
revoke all on function public.customer_registry_bulk_apply(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.customer_registry_bulk_apply(uuid,jsonb,text) to service_role;

-- Every selected component is revalidated in the transaction, then merged to its minimum ID.
create function public.customer_registry_auto_apply(p_owner uuid,p_groups jsonb) returns jsonb
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
 select array_agg((x->>'id')::uuid) into all_ids from jsonb_array_elements(p_groups) g cross join lateral jsonb_array_elements(g) x;
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
revoke all on function public.lk_registry_tokens(text,boolean),public.lk_registry_union(text[],boolean),public.lk_registry_auto_pair(text,text,text,text),public.lk_registry_protection(uuid[]),public.customer_registry_auto_apply(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.lk_registry_tokens(text,boolean),public.lk_registry_union(text[],boolean),public.lk_registry_auto_pair(text,text,text,text),public.lk_registry_protection(uuid[]),public.customer_registry_auto_apply(uuid,jsonb) to service_role;
