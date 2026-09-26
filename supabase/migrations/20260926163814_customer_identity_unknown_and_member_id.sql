-- Customer identity only: never renumber receipts or modify shipment/Excel data.
-- Existing registry rows, links and aliases are preserved. No historical merge or delete.

create function public.lk_customer_base_name(v text) returns text
language plpgsql immutable security invoker set search_path='' as $$
declare n text:=trim(coalesce(v,'')); tail text;
begin
 if n ~ '수취인[[:space:]]*불명' then
  tail:=substring(n from '수취인[[:space:]]*불명[[:space:]]*/[[:space:]]*(.*)$');
  if tail is null or tail ~ '[?*＊？]' then return null; end if;
  n:=trim(tail);
 end if;
 if n='' or public.lk_registry_name(n) in ('수취인불명','미상','unknown','불명') or n !~ '[[:alnum:]가-힣ກ-ໝ]' then return null; end if;
 return n;
end $$;

-- Display-only suffix for the future numbering change. Never an issued customer ID.
create function public.lk_customer_statement_code(p_number bigint,p_unknown boolean) returns text
language sql immutable security invoker set search_path='' as $$
 select case when p_number>0 then case when coalesce(p_unknown,false) then '9' else '' end||lpad(p_number::text,greatest(3,length(p_number::text)),'0') end;
$$;

create function public.customer_registry_match(p_name text,p_phone text,p_unknown boolean default false) returns uuid
language plpgsql stable security invoker set search_path='' as $$
declare n text:=public.lk_customer_base_name(p_name); nk text; pk text:=public.lk_registry_phone(p_phone); found uuid[]; first_name text;
begin
 if n is null then return null; end if; nk:=public.lk_registry_name(n);
 -- Exact name + full phone (or a reviewed alias) takes priority over namesakes.
 select array_agg(distinct r.id) into found from public.customer_registry r
 where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'
 and ((r.name_key=nk and r.phone_key=pk) or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=r.id and a.name_key=nk and a.phone_key=pk));
 if cardinality(found)=1 then return found[1]; elsif cardinality(found)>1 then return null; end if;
 if not p_unknown then return null; end if;
 -- Unknown-prefixed cargo follows a unique full suffix name. Phone differences remain reviewable.
 select array_agg(r.id) into found from public.customer_registry r where r.merged_into is null and r.name_key=nk and r.name !~ '수취인[[:space:]]*불명';
 if cardinality(found)=1 then return found[1]; elsif cardinality(found)>1 then return null; end if;
 -- A/B stays intact when registered as such. Otherwise the first explicit name
 -- after the prefix may match, but only with the same complete phone number.
 first_name:=public.lk_registry_name(split_part(n,'/',1));
 if first_name<>nk and length(pk)>=8 then
  select array_agg(distinct r.id) into found from public.customer_registry r where r.merged_into is null and r.name_key=first_name and r.phone_key=pk and r.name !~ '수취인[[:space:]]*불명';
  if cardinality(found)=1 then return found[1]; end if;
 end if;
 return null;
end $$;
revoke all on function public.customer_registry_match(text,text,boolean) from public,anon,authenticated;
grant execute on function public.customer_registry_match(text,text,boolean) to service_role;

create or replace function lk_private.register_shipment_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid; n text:=public.lk_customer_base_name(new.consignee_name); unknown_name boolean:=coalesce(new.consignee_name,'') ~ '수취인[[:space:]]*불명';
begin
 if new.deleted_at is not null or n is null or (coalesce(new.recipient_unknown,false) and not unknown_name) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 if exists(select 1 from public.customer_registry_sources where source_kind='shipment' and source_id=new.id::text) then return new; end if;
 target:=public.customer_registry_match(new.consignee_name,new.consignee_phone,unknown_name);
 if target is null then
  if unknown_name then return new; end if;
  insert into public.customer_registry(name,phone) values(n,coalesce(new.consignee_phone,'')) returning id into target;
 end if;
 if not unknown_name then
  insert into public.customer_registry_aliases values(public.lk_registry_name(n),public.lk_registry_phone(new.consignee_phone),target,now()) on conflict do nothing;
 end if;
 insert into public.customer_registry_sources values('shipment',new.id::text,target) on conflict do nothing;
 return new;
end $$;

create or replace function lk_private.register_profile_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid; n text:=public.lk_customer_base_name(new.name);
begin
 if new.deleted_at is not null or coalesce(new.deletion_status,'active')<>'active' or coalesce(new.approval_status,'approved')<>'approved' or new.role not in ('admin','staff','partner','member') or n is null then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 if new.role='member' and (length(public.lk_registry_phone(new.phone))<8 or coalesce(new.phone,'') ~ '[?*＊？]') then return new; end if;
 if exists(select 1 from public.customer_registry_sources where source_kind='profile' and source_id=new.id::text) then return new; end if;
 target:=public.customer_registry_match(new.name,new.phone,false);
 if target is null then
  if new.role='member' or new.name ~ '수취인[[:space:]]*불명' then return new; end if;
  insert into public.customer_registry(name,phone,category) values(n,coalesce(new.phone,''),new.role) returning id into target;
 end if;
 insert into public.customer_registry_aliases values(public.lk_registry_name(n),public.lk_registry_phone(new.phone),target,now()) on conflict do nothing;
 insert into public.customer_registry_sources values('profile',new.id::text,target) on conflict do nothing;
 return new;
end $$;

create or replace view public.customer_registry_source_status with (security_invoker=true) as
with source as (
 select 'shipment'::text source_kind,s.id::text source_id,s.consignee_name name,coalesce(s.consignee_phone,'') phone,concat_ws(' · ',s.route,s.shipment_year,s.voyage,s.receipt_number,s.box_number) label from public.shipments s where s.deleted_at is null and s.deletion_requested_at is null
 union all
 select 'profile',p.id::text,p.name,coalesce(p.phone,''),p.role from public.profiles p where p.deleted_at is null and coalesce(p.deletion_status,'active')='active'
)
select s.source_kind,s.source_id,r.id customer_registry_id,s.name,s.phone,s.label,
 not ((public.lk_registry_name(public.lk_customer_base_name(s.name))=r.name_key and public.lk_registry_phone(s.phone)=r.phone_key)
 or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=r.id and a.name_key in(public.lk_registry_name(s.name),public.lk_registry_name(public.lk_customer_base_name(s.name))) and a.phone_key=public.lk_registry_phone(s.phone))) mismatch,
 public.lk_customer_statement_code(r.customer_no,false) customer_code,
 public.lk_customer_statement_code(r.customer_no,s.name ~ '수취인[[:space:]]*불명') statement_customer_code,
 s.name ~ '수취인[[:space:]]*불명' is_unknown_name
from source s left join public.customer_registry_sources l using(source_kind,source_id)
join public.customer_registry r on r.id=case when s.source_kind='shipment' and s.name ~ '수취인[[:space:]]*불명' then public.customer_registry_match(s.name,s.phone,true) else l.customer_registry_id end
where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명';

create function public.customer_registry_member_id(p_owner uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare p public.profiles; target uuid; c public.customer_registry;
begin
 select * into p from public.profiles where id=p_owner and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved';
 if p.id is null then raise exception 'FORBIDDEN'; end if;
 select r.id into target from public.customer_registry_sources s join public.customer_registry r on r.id=s.customer_registry_id where s.source_kind='profile' and s.source_id=p_owner::text and r.merged_into is null and r.name !~ '수취인[[:space:]]*불명';
 if target is null then target:=public.customer_registry_match(p.name,p.phone,false); end if;
 if target is null then return jsonb_build_object('customer_code',null,'status','unmatched'); end if;
 select * into c from public.customer_registry where id=target;
 return jsonb_build_object('customer_code',public.lk_customer_statement_code(c.customer_no,false),'status',case when public.customer_registry_match(p.name,p.phone,false)=target then 'linked' else 'review_required' end);
end $$;
revoke all on function public.customer_registry_member_id(uuid) from public,anon,authenticated;
grant execute on function public.customer_registry_member_id(uuid) to service_role;

-- Shared, read-only source for the future Excel Customer ID sheet. Prefix and
-- group sorting remain the responsibility of the existing receipt generator.
create view public.customer_registry_statement_mapping with (security_invoker=true) as
select s.id shipment_id,s.route,s.shipment_year,s.voyage,s.receipt_number current_receipt_number,s.consignee_name source_name,s.consignee_phone source_phone,
 r.id customer_registry_id,r.customer_no,r.name customer_name,r.phone customer_phone,
 public.lk_customer_statement_code(r.customer_no,false) customer_code,
 s.consignee_name ~ '수취인[[:space:]]*불명' is_unknown_name,
 public.lk_customer_statement_code(r.customer_no,s.consignee_name ~ '수취인[[:space:]]*불명') statement_customer_code
from public.shipments s left join public.customer_registry_sources l on l.source_kind='shipment' and l.source_id=s.id::text
left join public.customer_registry r on r.id=case when s.consignee_name ~ '수취인[[:space:]]*불명' then public.customer_registry_match(s.consignee_name,s.consignee_phone,true) else l.customer_registry_id end and r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'
where s.deleted_at is null and s.deletion_requested_at is null;
revoke all on public.customer_registry_statement_mapping from public,anon,authenticated;
grant select on public.customer_registry_statement_mapping to service_role;

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
 if p_number not between 1 and 999999999 or length(trim(coalesce(p_name,''))) not between 1 and 160 or length(coalesce(p_phone,''))>40 then raise exception 'INVALID_CUSTOMER_ID'; end if;
 select customer_registry_id into other_id from public.customer_registry_aliases where name_key=public.lk_registry_name(p_name) and phone_key=public.lk_registry_phone(p_phone);
 if other_id is not null and other_id<>p_id then raise exception 'DUPLICATE_RECORD'; end if;
 update public.customer_registry set customer_no=p_number,name=trim(p_name),phone=trim(coalesce(p_phone,'')),updated_at=clock_timestamp() where id=p_id returning * into changed;
 insert into public.customer_registry_aliases values(changed.name_key,changed.phone_key,p_id,now()) on conflict do nothing;
 perform setval('public.customer_registry_number_seq',greatest((select last_value from public.customer_registry_number_seq),p_number),true);
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason)
 values(p_id,p_owner,to_jsonb(old),to_jsonb(changed),coalesce(nullif(trim(p_reason),''),'Customer details updated'));
 return to_jsonb(changed);
end $$;

create or replace function public.customer_registry_resolve_source(p_kind text,p_source text,p_from uuid,p_target uuid,p_name text,p_phone text,p_owner uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare current_name text; current_phone text; old_target uuid; other_id uuid;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select customer_registry_id into old_target from public.customer_registry_sources where source_kind=p_kind and source_id=p_source for update;
 if not exists(select 1 from public.customer_registry where id=p_target and merged_into is null and name !~ '수취인[[:space:]]*불명') then raise exception 'RECORD_CHANGED'; end if;
 if p_kind='shipment' then
 select consignee_name,coalesce(consignee_phone,'') into current_name,current_phone from public.shipments where id::text=p_source and deleted_at is null and deletion_requested_at is null for update;
 elsif p_kind='profile' then
 select name,coalesce(phone,'') into current_name,current_phone from public.profiles where id::text=p_source and deleted_at is null and coalesce(deletion_status,'active')='active' for update;
 else raise exception 'RECORD_CHANGED'; end if;
 if old_target is distinct from p_from and not (p_kind='shipment' and coalesce(current_name,'') ~ '수취인[[:space:]]*불명' and public.customer_registry_match(current_name,current_phone,true) is not distinct from p_from) then raise exception 'RECORD_CHANGED'; end if;
 if current_name is distinct from p_name or current_phone is distinct from p_phone then raise exception 'RECORD_CHANGED'; end if;
 select customer_registry_id into other_id from public.customer_registry_aliases where name_key=public.lk_registry_name(public.lk_customer_base_name(p_name)) and phone_key=public.lk_registry_phone(p_phone);
 if other_id is not null and other_id<>p_target then raise exception 'DUPLICATE_RECORD'; end if;
 insert into public.customer_registry_aliases values(public.lk_registry_name(public.lk_customer_base_name(p_name)),public.lk_registry_phone(p_phone),p_target,now()) on conflict do nothing;
 insert into public.customer_registry_sources values(p_kind,p_source,p_target) on conflict(source_kind,source_id) do update set customer_registry_id=excluded.customer_registry_id;
 update public.customer_registry set updated_at=clock_timestamp() where id in (p_from,p_target);
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason)
 values(p_target,p_owner,jsonb_build_object('source_kind',p_kind,'source_id',p_source,'customer_registry_id',old_target),jsonb_build_object('source_kind',p_kind,'source_id',p_source,'customer_registry_id',p_target,'name',p_name,'phone',p_phone),'Reviewed source identity');
 return true;
end $$;
revoke all on function public.customer_registry_resolve_source(text,text,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.customer_registry_resolve_source(text,text,uuid,uuid,text,text,uuid) to service_role;
