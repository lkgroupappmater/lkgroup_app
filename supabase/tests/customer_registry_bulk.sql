-- Integration check: fixtures, audit rows and all business changes are rolled back.
begin;
set local role service_role;
do $$
declare actor uuid; nums bigint[]; ids uuid[]:=array[]::uuid[]; n bigint; row_id uuid;
 payload jsonb; bad jsonb; result jsonb; before_phone text; rejected boolean; audit_count bigint;
begin
 perform pg_advisory_xact_lock(7092601);
 select id into actor from public.profiles where role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved' limit 1;
 select array_agg(x) into nums from (select x from generate_series(3,(select last_value from public.customer_registry_number_seq)) x where not exists(select 1 from public.customer_registry where customer_no=x) limit 4) unused;
 if actor is null or array_length(nums,1)<>4 then raise exception 'Test fixtures unavailable'; end if;
 foreach n in array nums loop
  insert into public.customer_registry(customer_no,name,phone) values(n,'Bulk QA '||gen_random_uuid(),'02088880000') returning id into row_id;
  ids:=array_append(ids,row_id);
  insert into public.customer_registry_aliases(name_key,phone_key,customer_registry_id) select name_key,phone_key,id from public.customer_registry where id=row_id;
  insert into public.customer_registry_sources values('shipment','bulk-qa-'||row_id,row_id);
 end loop;
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('target_id',c.id,'phone','02011110000 / 02011110001')) into payload from public.customer_registry c where id=any(ids);
 result:=public.customer_registry_bulk_apply(actor,payload,'');
 if (result->>'updated_count')::int<>4 or exists(select 1 from public.customer_registry where id=any(ids) and phone<>'02011110000 / 02011110001') then raise exception 'Contact batch failed'; end if;
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('target_id',c.id,'phone','02022220000')) into payload from public.customer_registry c where id=any(ids);
 bad:=jsonb_set(payload,'{3,updated_at}','"2000-01-01T00:00:00Z"');rejected:=false;
 begin perform public.customer_registry_bulk_apply(actor,bad,''); exception when others then if sqlerrm<>'RECORD_CHANGED' then raise; end if; rejected:=true; end;
 if not rejected or exists(select 1 from public.customer_registry where id=any(ids) and phone='02022220000') then raise exception 'Stale version was partially saved'; end if;
 -- A late constraint failure must roll back preceding edits and their audits.
 select count(*) into audit_count from public.customer_registry_audit where customer_registry_id=any(ids);
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('target_id',c.id,'customer_no',nums[1],'phone','02033330000') order by c.id) into bad from public.customer_registry c where id=any(ids);
 rejected:=false;
 begin perform public.customer_registry_bulk_apply(actor,bad,''); exception when unique_violation then rejected:=true; end;
 if not rejected or exists(select 1 from public.customer_registry where id=any(ids) and phone='02033330000') or audit_count<>(select count(*) from public.customer_registry_audit where customer_registry_id=any(ids)) then raise exception 'Constraint failure was partially saved'; end if;
 -- Two independent groups, one source each; update both surviving contacts.
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('target_id',case when c.id=ids[1] then ids[2] when c.id=ids[3] then ids[4] else c.id end,'phone','02044440000')) into payload from public.customer_registry c where id=any(ids);
 result:=public.customer_registry_bulk_apply(actor,payload,'');
 if (result->>'merged_count')::int<>2 or (result->>'updated_count')::int<>2 or (result->>'moved_sources')::int<>2 then raise exception 'Merge result incorrect: %',result; end if;
 if (select merged_into from public.customer_registry where id=ids[1])<>ids[2] or (select merged_into from public.customer_registry where id=ids[3])<>ids[4] then raise exception 'Merge groups crossed'; end if;
 if (select customer_registry_id from public.customer_registry_sources where source_id='bulk-qa-'||ids[1])<>ids[2] or (select customer_registry_id from public.customer_registry_aliases where name_key=(select name_key from public.customer_registry where id=ids[3]) and phone_key=public.lk_registry_phone('02088880000'))<>ids[4] then raise exception 'Links or aliases not transferred'; end if;
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('target_id',case when c.id=ids[2] then ids[4] else ids[2] end)) into bad from public.customer_registry c where id in(ids[2],ids[4]);rejected:=false;
 begin perform public.customer_registry_bulk_apply(actor,bad,''); exception when others then if sqlerrm<>'BULK_SELECTION_INVALID' then raise; end if; rejected:=true; end;
 if not rejected then raise exception 'Cycle accepted'; end if;
 if has_function_privilege('authenticated','public.customer_registry_bulk_apply(uuid,jsonb,text)','EXECUTE') or has_function_privilege('anon','public.customer_registry_bulk_apply(uuid,jsonb,text)','EXECUTE') then raise exception 'Untrusted RPC access'; end if;
 perform set_config('lk.bulk_test','passed: contact batch, stale guard, atomic rollback, independent merges, links, aliases, cycle rejection, RPC privileges',true);
end $$;
select current_setting('lk.bulk_test') as result;
rollback;
