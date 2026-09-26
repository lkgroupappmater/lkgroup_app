-- Reviewed customer identity resolution. Historical cargo, prices and login roles stay intact.
alter table public.customer_registry add column merged_into uuid references public.customer_registry(id);
alter table public.customer_registry add constraint customer_registry_not_self check(merged_into is null or merged_into<>id);
alter table public.waybill_intake_batches add column fixed_link jsonb;
create table public.customer_registry_aliases(
 name_key text not null, phone_key text not null,
 customer_registry_id uuid not null references public.customer_registry(id),
 created_at timestamptz not null default now(), primary key(name_key,phone_key)
);
create index customer_registry_alias_target_idx on public.customer_registry_aliases(customer_registry_id);
alter table public.customer_registry_aliases enable row level security;
revoke all on public.customer_registry_aliases from public,anon,authenticated;
grant all on public.customer_registry_aliases to service_role;
insert into public.customer_registry_aliases(name_key,phone_key,customer_registry_id)
 select name_key,phone_key,id from public.customer_registry;

create view public.customer_registry_source_status with (security_invoker=true) as
with source as (
 select 'shipment'::text source_kind,s.id::text source_id,s.consignee_name name,coalesce(s.consignee_phone,'') phone,
 concat_ws(' · ',s.route,s.shipment_year,s.voyage,s.receipt_number,s.box_number) label
 from public.shipments s where s.deleted_at is null and s.deletion_requested_at is null
 union all
 select 'profile',p.id::text,p.name,coalesce(p.phone,''),p.role from public.profiles p
 where p.deleted_at is null and coalesce(p.deletion_status,'active')='active'
)
select l.source_kind,l.source_id,l.customer_registry_id,s.name,s.phone,s.label,
 not ((public.lk_registry_name(s.name)=r.name_key and public.lk_registry_phone(s.phone)=r.phone_key)
 or exists(select 1 from public.customer_registry_aliases a where a.customer_registry_id=r.id
 and a.name_key=public.lk_registry_name(s.name) and a.phone_key=public.lk_registry_phone(s.phone))) mismatch
from public.customer_registry_sources l join source s using(source_kind,source_id)
join public.customer_registry r on r.id=l.customer_registry_id;
revoke all on public.customer_registry_source_status from public,anon,authenticated;
grant select on public.customer_registry_source_status to service_role;

create index shipments_registry_name_idx on public.shipments(public.lk_registry_name(consignee_name)) where deleted_at is null and deletion_requested_at is null;
create index shipments_registry_phone_idx on public.shipments(public.lk_registry_phone(consignee_phone)) where deleted_at is null and deletion_requested_at is null;
create function public.waybill_recipient_candidates(p_name text,p_phone text) returns jsonb
language sql stable security invoker set search_path='' as $$
 with keys as (select public.lk_registry_name(p_name) n,public.lk_registry_phone(p_phone) p), matched as (
 select s.*,r.customer_no,k.n,k.p,public.lk_registry_name(s.consignee_name) nk,public.lk_registry_phone(s.consignee_phone) pk
 from public.shipments s cross join keys k
 left join public.customer_registry_sources l on l.source_kind='shipment' and l.source_id=s.id::text
 left join public.customer_registry r on r.id=l.customer_registry_id
 where s.deleted_at is null and s.deletion_requested_at is null
 and ((k.n<>'' and public.lk_registry_name(s.consignee_name)=k.n) or (length(k.p)>=8 and public.lk_registry_phone(s.consignee_phone)=k.p))
 ), grouped as (
 select distinct on (route,shipment_year,voyage,coalesce(nullif(receipt_number,''),id::text),nk,pk) * from matched
 order by route,shipment_year,voyage,coalesce(nullif(receipt_number,''),id::text),nk,pk,id
 ), output as (
 select jsonb_build_object('exact',n<>'' and p<>'' and n=nk and p=pk,'customer_no',customer_no,
 'receiver_name',consignee_name,'receiver_phone',consignee_phone,
 'link_scope',case when nullif(receipt_number,'') is null then 'cargo' else 'statement' end,
 'shipment_id',case when nullif(receipt_number,'') is null then id else null end,
 'statement',case when nullif(receipt_number,'') is not null then jsonb_build_object('route',route,'shipment_year',shipment_year,'voyage',voyage,'receipt_number',receipt_number) else null end,
 'label',concat_ws(' · ',case when customer_no is not null then lpad(customer_no::text,greatest(3,length(customer_no::text)),'0') end,consignee_name,consignee_phone,route,shipment_year,voyage,coalesce(nullif(receipt_number,''),box_number))) item
 from grouped order by (n<>'' and p<>'' and n=nk and p=pk) desc,shipment_year desc,voyage desc,id desc limit 100
 ) select coalesce(jsonb_agg(item),'[]'::jsonb) from output;
$$;
revoke all on function public.waybill_recipient_candidates(text,text) from public,anon,authenticated;
grant execute on function public.waybill_recipient_candidates(text,text) to service_role;

create or replace function public.customer_registry_change(p_id uuid,p_owner uuid,p_number bigint,p_name text,p_phone text,p_reason text,p_expected timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare old public.customer_registry; changed public.customer_registry; other_id uuid;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into old from public.customer_registry where id=p_id for update;
 if old.id is null or old.updated_at is distinct from p_expected or old.merged_into is not null then raise exception 'RECORD_CHANGED'; end if;
 if old.customer_no in (1,2) and old.customer_no<>p_number then raise exception 'RESERVED_CUSTOMER_ID'; end if;
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

create function public.customer_registry_merge(p_source uuid,p_target uuid,p_owner uuid,p_source_expected timestamptz,p_target_expected timestamptz,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare src public.customer_registry; dst public.customer_registry; changed public.customer_registry; moved integer;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into src from public.customer_registry where id=p_source for update;
 select * into dst from public.customer_registry where id=p_target for update;
 if p_source=p_target or src.id is null or dst.id is null or src.merged_into is not null or dst.merged_into is not null or src.updated_at is distinct from p_source_expected or dst.updated_at is distinct from p_target_expected then raise exception 'RECORD_CHANGED'; end if;
 if src.customer_no in (1,2) then raise exception 'RESERVED_CUSTOMER_ID'; end if;
 update public.customer_registry_sources set customer_registry_id=p_target where customer_registry_id=p_source;
 get diagnostics moved=row_count;
 update public.customer_registry_aliases set customer_registry_id=p_target where customer_registry_id=p_source;
 update public.customer_registry set merged_into=p_target,updated_at=clock_timestamp() where id=p_source returning * into changed;
 update public.customer_registry set updated_at=clock_timestamp() where id=p_target returning * into dst;
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason) values
 (p_source,p_owner,to_jsonb(src),to_jsonb(changed)||jsonb_build_object('moved_sources',moved),coalesce(nullif(trim(p_reason),''),'Reviewed duplicate merge')),
 (p_target,p_owner,jsonb_build_object('merged_from',p_source),to_jsonb(dst),coalesce(nullif(trim(p_reason),''),'Reviewed duplicate merge'));
 return to_jsonb(dst)||jsonb_build_object('moved_sources',moved);
end $$;
revoke all on function public.customer_registry_merge(uuid,uuid,uuid,timestamptz,timestamptz,text) from public,anon,authenticated;
grant execute on function public.customer_registry_merge(uuid,uuid,uuid,timestamptz,timestamptz,text) to service_role;

create function public.customer_registry_resolve_source(p_kind text,p_source text,p_from uuid,p_target uuid,p_name text,p_phone text,p_owner uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare current_name text; current_phone text; old_target uuid; other_id uuid;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select customer_registry_id into old_target from public.customer_registry_sources where source_kind=p_kind and source_id=p_source for update;
 if old_target is distinct from p_from or not exists(select 1 from public.customer_registry where id=p_target and merged_into is null) then raise exception 'RECORD_CHANGED'; end if;
 if p_kind='shipment' then
 select consignee_name,coalesce(consignee_phone,'') into current_name,current_phone from public.shipments where id::text=p_source and deleted_at is null and deletion_requested_at is null for update;
 elsif p_kind='profile' then
 select name,coalesce(phone,'') into current_name,current_phone from public.profiles where id::text=p_source and deleted_at is null and coalesce(deletion_status,'active')='active' for update;
 else raise exception 'RECORD_CHANGED'; end if;
 if current_name is distinct from p_name or current_phone is distinct from p_phone then raise exception 'RECORD_CHANGED'; end if;
 select customer_registry_id into other_id from public.customer_registry_aliases where name_key=public.lk_registry_name(p_name) and phone_key=public.lk_registry_phone(p_phone);
 if other_id is not null and other_id<>p_target then raise exception 'DUPLICATE_RECORD'; end if;
 insert into public.customer_registry_aliases values(public.lk_registry_name(p_name),public.lk_registry_phone(p_phone),p_target,now()) on conflict do nothing;
 update public.customer_registry_sources set customer_registry_id=p_target where source_kind=p_kind and source_id=p_source;
 update public.customer_registry set updated_at=clock_timestamp() where id in (p_from,p_target);
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason)
 values(p_target,p_owner,jsonb_build_object('source_kind',p_kind,'source_id',p_source,'customer_registry_id',old_target),jsonb_build_object('source_kind',p_kind,'source_id',p_source,'customer_registry_id',p_target,'name',p_name,'phone',p_phone),'Reviewed source identity');
 return true;
end $$;
revoke all on function public.customer_registry_resolve_source(text,text,uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.customer_registry_resolve_source(text,text,uuid,uuid,text,text,uuid) to service_role;

-- Reuse reviewed aliases for future imports; no fuzzy automatic assignment.
create or replace function lk_private.register_shipment_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if new.deleted_at is not null or coalesce(new.recipient_unknown,false) or nullif(trim(new.consignee_name),'') is null
 or public.lk_registry_name(new.consignee_name) in ('수취인불명','미상','unknown','불명') then return new; end if;
 if exists(select 1 from public.customer_registry_sources where source_kind='shipment' and source_id=new.id::text) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 select customer_registry_id into target from public.customer_registry_aliases where name_key=public.lk_registry_name(new.consignee_name) and phone_key=public.lk_registry_phone(new.consignee_phone);
 if target is null then
 select id into target from public.customer_registry where name_key=public.lk_registry_name(new.consignee_name) and phone_key=public.lk_registry_phone(new.consignee_phone) and merged_into is null;
 end if;
 if target is null then insert into public.customer_registry(name,phone) values(trim(new.consignee_name),coalesce(new.consignee_phone,'')) returning id into target; end if;
 insert into public.customer_registry_aliases values(public.lk_registry_name(new.consignee_name),public.lk_registry_phone(new.consignee_phone),target,now()) on conflict do nothing;
 insert into public.customer_registry_sources values('shipment',new.id::text,target) on conflict do nothing;
 return new;
end $$;
create or replace function lk_private.register_profile_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if new.deleted_at is not null or coalesce(new.deletion_status,'active')<>'active' or coalesce(new.approval_status,'approved')<>'approved'
 or new.role not in ('admin','staff','partner') or nullif(trim(new.name),'') is null then return new; end if;
 if exists(select 1 from public.customer_registry_sources where source_kind='profile' and source_id=new.id::text) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 select customer_registry_id into target from public.customer_registry_aliases where name_key=public.lk_registry_name(new.name) and phone_key=public.lk_registry_phone(new.phone);
 if target is null then select id into target from public.customer_registry where name_key=public.lk_registry_name(new.name) and phone_key=public.lk_registry_phone(new.phone) and merged_into is null; end if;
 if target is null then insert into public.customer_registry(name,phone,category) values(trim(new.name),coalesce(new.phone,''),new.role) returning id into target; end if;
 insert into public.customer_registry_aliases values(public.lk_registry_name(new.name),public.lk_registry_phone(new.phone),target,now()) on conflict do nothing;
 insert into public.customer_registry_sources values('profile',new.id::text,target) on conflict do nothing;
 return new;
end $$;

-- Reference photos are explicit photo-only entries, with no invented tracking number.
alter table public.domestic_parcels add column is_reference_photo boolean not null default false;
alter table public.domestic_parcels alter column carrier drop not null;
alter table public.domestic_parcels alter column tracking_number drop not null;
alter table public.domestic_parcels add constraint domestic_reference_photo_identity check(
 (is_reference_photo and carrier is null and tracking_number is null and cardinality(photo_paths)>0 and link_scope in ('statement','cargo','reference'))
 or (not is_reference_photo and carrier is not null and tracking_number is not null)
);
create function public.commit_reference_photos(p_batch uuid,p_owner uuid,p_value jsonb) returns uuid[]
language plpgsql security invoker set search_path='' as $$
declare b public.waybill_intake_batches; r public.domestic_parcels; new_id uuid;
begin
 select * into b from public.waybill_intake_batches where id=p_batch and owner_id=p_owner for update;
 if b.id is null then raise exception 'FORBIDDEN'; end if;
 if b.status='committed' then return b.result_ids; end if;
 if b.purpose not in ('photos','waybill') then raise exception 'INVALID_BATCH'; end if;
 select * into r from jsonb_populate_record(null::public.domestic_parcels,p_value);
 if cardinality(r.photo_paths) not between 1 and 50 or r.link_scope not in ('statement','cargo','reference') then raise exception 'INVALID_BATCH'; end if;
 if exists(select 1 from unnest(r.photo_paths) p where not exists(select 1 from public.waybill_intake_files f where f.batch_id=b.id and f.path=p and f.verified_at is not null)) then raise exception 'INVALID_IMAGE'; end if;
 new_id:=gen_random_uuid();
 insert into public.domestic_parcels(id,is_reference_photo,carrier,tracking_number,shipment_id,link_scope,link_route,link_year,link_voyage,link_receipt_number,
 statement_route,statement_year,statement_voyage,statement_receipt,reference_type,reference_number,delivery_kind,service_kind,receiver_name,receiver_phone,photo_path,photo_paths,created_by,updated_by)
 values(new_id,true,null,null,r.shipment_id,r.link_scope,r.link_route,r.link_year,r.link_voyage,r.link_receipt_number,
 r.statement_route,r.statement_year,r.statement_voyage,r.statement_receipt,r.reference_type,r.reference_number,r.delivery_kind,r.service_kind,r.receiver_name,r.receiver_phone,r.photo_paths[1],r.photo_paths,p_owner,p_owner);
 update public.waybill_intake_batches set status='committed',result_ids=array[new_id],committed_at=now() where id=b.id;
 return array[new_id];
end $$;
revoke all on function public.commit_reference_photos(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.commit_reference_photos(uuid,uuid,jsonb) to service_role;
