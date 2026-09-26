-- All fixture changes are rolled back. No live identity is merged or deleted.
begin;
do $$
declare actor uuid; member uuid; nums bigint[]; a uuid; b uuid; n text:='Identity QA '||gen_random_uuid(); r text; shipment bigint; masked bigint; before_count bigint; value jsonb; blocked boolean:=false;
begin
 perform pg_advisory_xact_lock(7092601);
 select id into actor from public.profiles where role='admin' and deleted_at is null and approval_status='approved' limit 1;
 select p.id into member from public.profiles p where p.role='member' and p.deleted_at is null and p.approval_status='approved' and not exists(select 1 from public.customer_registry_sources s where s.source_kind='profile' and s.source_id=p.id::text) limit 1;
 select array_agg(x) into nums from (select x from generate_series(3,(select last_value from public.customer_registry_number_seq)) x where not exists(select 1 from public.customer_registry where customer_no=x) limit 2) unused;
 if actor is null or member is null or cardinality(nums)<>2 then raise exception 'Fixture unavailable'; end if;
 insert into public.customer_registry(customer_no,name,phone) values(nums[1],n,'02011112222') returning id into a;
 insert into public.customer_registry_aliases(name_key,phone_key,customer_registry_id) select name_key,phone_key,id from public.customer_registry where id=a;
 if public.lk_customer_base_name('히 수취인 불명 / '||n)<>n or public.lk_customer_base_name('수취인불명 / ???') is not null or public.lk_customer_base_name('수취인 불명 / 이*석') is not null then raise exception 'Prefix parsing failed'; end if;
 if public.lk_customer_statement_code(23,true)<>'9023' or public.lk_customer_statement_code(23,false)<>'023' or public.lk_customer_statement_code(1234,true)<>'91234' then raise exception 'Future suffix failed'; end if;
 if public.customer_registry_match('수취인 불명 / '||n,'020 1111 2222',true) is distinct from a or public.customer_registry_match('수취인 불명 / '||n||'/Other','02011112222',true) is distinct from a then raise exception 'Canonical match failed'; end if;
 if public.customer_registry_match('수취인 불명 / '||n,'02099990000',true) is distinct from a then raise exception 'Unique suffix not resolved'; end if;
 insert into public.customer_registry(customer_no,name,phone) values(nums[2],n,'02033334444') returning id into b;
 if public.customer_registry_match('수취인 불명 / '||n,'02099990000',true) is not null then raise exception 'Ambiguous name matched'; end if;
 if public.customer_registry_match('수취인 불명 / '||n,'02011112222',true) is distinct from a then raise exception 'Namesake phone priority failed'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 perform set_config('lkgroup.bulk_import','1',true);
 select display_name into r from public.route_definitions where route_key='kr_la_sea';
 select count(*) into before_count from public.customer_registry;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number)
 values(r,2099,'96','QA-ID-'||gen_random_uuid(),'수취인 불명 / '||n,'02011112222','LKS XX') returning id into shipment;
 insert into public.shipments(route,shipment_year,voyage,box_number,consignee_name,consignee_phone,receipt_number)
 values(r,2099,'96','QA-ID-'||gen_random_uuid(),'수취인 불명 / ????','????','LKS XX') returning id into masked;
 if (select count(*) from public.customer_registry)<>before_count then raise exception 'Unknown row issued a new customer ID'; end if;
 if (select customer_registry_id from public.customer_registry_statement_mapping where shipment_id=shipment) is distinct from a or (select customer_no from public.customer_registry_statement_mapping where shipment_id=masked) is not null then raise exception 'Read-only mapping failed'; end if;
 update public.profiles set name=n,phone='02011112222' where id=member;
 value:=public.customer_registry_member_id(member);
 if value->>'customer_code'<>public.lk_customer_statement_code(nums[1],false) or value->>'status'<>'linked' then raise exception 'Member join did not match ID'; end if;
 if (select customer_registry_id from public.customer_registry_sources where source_kind='profile' and source_id=member::text) is distinct from a then raise exception 'Member trigger missing'; end if;
 begin perform public.customer_registry_member_id(gen_random_uuid()); exception when others then if sqlerrm='FORBIDDEN' then blocked:=true; else raise; end if; end;
 if not blocked or has_function_privilege('authenticated','public.customer_registry_member_id(uuid)','EXECUTE') or has_table_privilege('anon','public.customer_registry_statement_mapping','SELECT') then raise exception 'Identity RPC boundary failed'; end if;
 perform set_config('lk.identity_member',member::text,true);
 perform set_config('lk.identity_test','passed: suffix parsing, full phone priority, ambiguity, 9-prefixed display, no unknown ID allocation, member matching, private access',true);
end $$;
set local role service_role;
select current_setting('lk.identity_test') as result,public.customer_registry_member_id(current_setting('lk.identity_member')::uuid) as service_role_identity;
rollback;
