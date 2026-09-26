begin;
do $$
declare actor uuid; member public.profiles; code text; expected bigint; actual bigint; mine text; other text;
begin
 select id into actor from public.profiles where role='admin' and deleted_at is null and approval_status='approved' limit 1;
 select * into member from public.profiles p where role='member' and deleted_at is null and approval_status='approved' and public.customer_registry_member_id(p.id)->>'customer_code' is not null limit 1;
 select customer_code into code from public.customer_registry_statement_mapping where customer_code is not null group by customer_code having count(*)<1000 order by count(*) desc limit 1;
 select count(*) into expected from public.customer_registry_statement_mapping where customer_code=code;
 select count(*) into actual from public.customer_registry_search_shipments(actor,code);
 if actual<>expected then raise exception 'ID filter was applied after the limit: % vs %',actual,expected; end if;
 mine:=public.customer_registry_member_id(member.id)->>'customer_code';
 select count(*) into actual from public.customer_registry_search_shipments(member.id,mine) s where not (s.customer_id=member.id or (lower(trim(s.consignee_name))=lower(trim(member.name)) and length(public.only_digits(member.phone))>=8 and right(public.only_digits(s.consignee_phone),8)=right(public.only_digits(member.phone),8)));
 if actual<>0 then raise exception 'Member ID search expanded cargo access'; end if;
 select customer_code into other from public.customer_registry_statement_mapping where customer_code is distinct from mine and customer_code is not null limit 1;
 select count(*) into actual from public.customer_registry_search_shipments(member.id,other) s where not (s.customer_id=member.id or (lower(trim(s.consignee_name))=lower(trim(member.name)) and length(public.only_digits(member.phone))>=8 and right(public.only_digits(s.consignee_phone),8)=right(public.only_digits(member.phone),8)));
 if actual<>0 then raise exception 'Other customer ID disclosed cargo'; end if;
 if has_function_privilege('authenticated','public.customer_registry_search_shipments(uuid,text,jsonb)','EXECUTE') or has_function_privilege('anon','public.customer_registry_search_shipments(uuid,text,jsonb)','EXECUTE') then raise exception 'Caller can forge the owner'; end if;
 perform set_config('lk.identity_actor',actor::text,true);perform set_config('lk.identity_code',code,true);
end $$;
set local role service_role;
select 'passed: ID before limit, member visibility, no caller-supplied owner RPC' result,count(*) matched_rows from public.customer_registry_search_shipments(current_setting('lk.identity_actor')::uuid,current_setting('lk.identity_code'));
rollback;
