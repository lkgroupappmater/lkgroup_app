-- Additive shared App/Web features. Existing shipment customer_id, discounts and
-- statement identity groups are deliberately not rewritten.
alter table public.domestic_parcels drop constraint domestic_photo_count;
alter table public.domestic_parcels add constraint domestic_photo_count
 check(cardinality(photo_paths)<=50 and array_position(photo_paths,null) is null);
create schema if not exists lk_private;
revoke all on schema lk_private from public,anon,authenticated;

create function public.lk_registry_name(v text) returns text language sql immutable set search_path='' as $$
 select lower(regexp_replace(normalize(coalesce(v,''),NFC),'[[:space:]]','','g'));
$$;
create function public.lk_registry_phone(v text) returns text language sql immutable set search_path='' as $$
 with p as (select regexp_replace(coalesce(v,''),'[^0-9]','','g') d)
 select case when d ~ '^00856[0-9]{8,10}$' then '0'||substr(d,6)
 when d ~ '^856[0-9]{8,10}$' then '0'||substr(d,4)
 when d ~ '^0082[0-9]{8,11}$' then '0'||substr(d,5)
 when d ~ '^82[0-9]{8,11}$' then '0'||substr(d,3) else d end from p;
$$;
create sequence public.customer_registry_number_seq start 1;
create table public.customer_registry (
 id uuid primary key default gen_random_uuid(),
 customer_no bigint not null default nextval('public.customer_registry_number_seq') unique check(customer_no>0),
 name text not null check(length(name) between 1 and 160), phone text not null default '',
 name_key text generated always as (public.lk_registry_name(name)) stored,
 phone_key text generated always as (public.lk_registry_phone(phone)) stored,
 category text not null default 'customer' check(category in ('admin','staff','partner','customer')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(name_key,phone_key)
);
create index customer_registry_phone_idx on public.customer_registry(phone_key);
create table public.customer_registry_sources (
 source_kind text not null check(source_kind in ('profile','shipment')),
 source_id text not null, customer_registry_id uuid not null references public.customer_registry(id),
 primary key(source_kind,source_id)
);
create index customer_registry_sources_customer_idx on public.customer_registry_sources(customer_registry_id);
create table public.customer_registry_audit (
 id bigint generated always as identity primary key,
 customer_registry_id uuid not null references public.customer_registry(id),
 actor_id uuid not null references public.profiles(id), before_value jsonb not null,
 after_value jsonb not null, reason text not null,created_at timestamptz not null default now()
);
alter table public.customer_registry enable row level security;
alter table public.customer_registry_sources enable row level security;
alter table public.customer_registry_audit enable row level security;
revoke all on public.customer_registry,public.customer_registry_sources,public.customer_registry_audit from anon,authenticated;
grant all on public.customer_registry,public.customer_registry_sources,public.customer_registry_audit to service_role;
grant usage,select on sequence public.customer_registry_number_seq,public.customer_registry_audit_id_seq to service_role;

-- Verify both requested reserved identities against existing approved accounts.
do $$
begin
 if (select count(*) from public.profiles where name='박성호' and role='admin' and deleted_at is null)<>1
 or (select count(*) from public.profiles where name='정석진 법인장' and role='admin' and deleted_at is null)<>1 then
  raise exception 'RESERVED_CUSTOMER_IDENTITY_AMBIGUOUS';
 end if;
end $$;
insert into public.customer_registry(customer_no,name,phone,category)
 select case name when '박성호' then 1 else 2 end,name,coalesce(phone,''),'admin'
 from public.profiles where name in ('박성호','정석진 법인장') and role='admin' and deleted_at is null;
select setval('public.customer_registry_number_seq',2,true);
with source as (
 select name,coalesce(phone,'') phone,role category,case role when 'admin' then 0 when 'staff' then 1 else 2 end priority
 from public.profiles where role in ('admin','staff','partner') and deleted_at is null
 and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved'
 union all
 select consignee_name,coalesce(consignee_phone,''),'customer',3 from public.shipments
 where deleted_at is null and nullif(trim(consignee_name),'') is not null
 and not coalesce(recipient_unknown,false) and public.lk_registry_name(consignee_name) not in ('수취인불명','미상','unknown','불명')
), dedup as (
 select distinct on (public.lk_registry_name(name),public.lk_registry_phone(phone)) * from source
 order by public.lk_registry_name(name),public.lk_registry_phone(phone),priority,name,phone
)
insert into public.customer_registry(name,phone,category)
 select name,phone,category from dedup d
 where not exists(select 1 from public.customer_registry r where r.name_key=public.lk_registry_name(d.name) and r.phone_key=public.lk_registry_phone(d.phone))
 order by priority,case when trim(name) ~ '^[가-힣ㄱ-ㅎㅏ-ㅣ]' then 0 when trim(name) ~ '^[A-Za-z]' then 1 else 2 end,
 name collate "ko-KR-x-icu",phone;
insert into public.customer_registry_sources
 select 'shipment',s.id::text,r.id from public.shipments s join public.customer_registry r
 on r.name_key=public.lk_registry_name(s.consignee_name) and r.phone_key=public.lk_registry_phone(s.consignee_phone)
 where s.deleted_at is null;
insert into public.customer_registry_sources
 select 'profile',p.id::text,r.id from public.profiles p join public.customer_registry r
 on r.name_key=public.lk_registry_name(p.name) and r.phone_key=public.lk_registry_phone(p.phone)
 where p.deleted_at is null;

create function lk_private.register_shipment_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if new.deleted_at is not null or coalesce(new.recipient_unknown,false) or nullif(trim(new.consignee_name),'') is null
 or public.lk_registry_name(new.consignee_name) in ('수취인불명','미상','unknown','불명') then return new; end if;
 -- An existing source keeps its fixed ID even when shipment details are corrected.
 if exists(select 1 from public.customer_registry_sources where source_kind='shipment' and source_id=new.id::text) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 select id into target from public.customer_registry where name_key=public.lk_registry_name(new.consignee_name) and phone_key=public.lk_registry_phone(new.consignee_phone);
 if target is null then
  insert into public.customer_registry(name,phone) values(trim(new.consignee_name),coalesce(new.consignee_phone,'')) returning id into target;
 end if;
 insert into public.customer_registry_sources values('shipment',new.id::text,target) on conflict do nothing;
 return new;
end $$;
revoke all on function lk_private.register_shipment_customer() from public;
create trigger register_shipment_customer after insert or update of consignee_name,consignee_phone,recipient_unknown on public.shipments
 for each row execute function lk_private.register_shipment_customer();

create function lk_private.register_profile_customer() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if new.deleted_at is not null or coalesce(new.deletion_status,'active')<>'active'
 or coalesce(new.approval_status,'approved')<>'approved' or new.role not in ('admin','staff','partner')
 or nullif(trim(new.name),'') is null then return new; end if;
 if exists(select 1 from public.customer_registry_sources where source_kind='profile' and source_id=new.id::text) then return new; end if;
 perform pg_advisory_xact_lock(7092601);
 select id into target from public.customer_registry where name_key=public.lk_registry_name(new.name) and phone_key=public.lk_registry_phone(new.phone);
 if target is null then
  insert into public.customer_registry(name,phone,category) values(trim(new.name),coalesce(new.phone,''),new.role) returning id into target;
 end if;
 insert into public.customer_registry_sources values('profile',new.id::text,target) on conflict do nothing;
 return new;
end $$;
revoke all on function lk_private.register_profile_customer() from public;
create trigger register_profile_customer after insert or update of name,phone,role,approval_status on public.profiles
 for each row execute function lk_private.register_profile_customer();

create table public.waybill_intake_batches (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.profiles(id),
 purpose text not null check(purpose in ('waybill','photos','unknown')),
 shipment_id bigint references public.shipments(id),
 status text not null default 'draft' check(status in ('draft','committed')),
 result_ids uuid[], created_at timestamptz not null default now(),committed_at timestamptz
);
create index waybill_intake_owner_idx on public.waybill_intake_batches(owner_id,created_at);
create table public.waybill_intake_files (
 id uuid primary key default gen_random_uuid(),batch_id uuid not null references public.waybill_intake_batches(id),
 name text not null,path text not null unique,size_bytes integer not null check(size_bytes between 13 and 5242880),
 verified_at timestamptz,extracted jsonb,scan_attempts integer not null default 0,
 scan_started_at timestamptz,scan_error text,created_at timestamptz not null default now()
);
create index waybill_intake_files_batch_idx on public.waybill_intake_files(batch_id);
create table public.unknown_cargo_photos (
 id uuid primary key default gen_random_uuid(),shipment_id bigint not null references public.shipments(id),
 path text not null unique,kind text not null check(kind in ('waybill','box')),
 uploaded_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
create index unknown_cargo_photos_shipment_idx on public.unknown_cargo_photos(shipment_id);
alter table public.waybill_intake_batches enable row level security;
alter table public.waybill_intake_files enable row level security;
alter table public.unknown_cargo_photos enable row level security;
revoke all on public.waybill_intake_batches,public.waybill_intake_files,public.unknown_cargo_photos from anon,authenticated;
grant all on public.waybill_intake_batches,public.waybill_intake_files,public.unknown_cargo_photos to service_role;

-- Atomic commit; service-only, validated values come from the shared Edge Function.
create function public.commit_waybill_intake(p_batch uuid,p_owner uuid,p_values jsonb) returns uuid[]
language plpgsql security invoker set search_path='' as $$
declare b public.waybill_intake_batches; ids uuid[]; item jsonb; new_id uuid;
begin
 select * into b from public.waybill_intake_batches where id=p_batch and owner_id=p_owner for update;
 if b.id is null then raise exception 'FORBIDDEN'; end if;
 if b.status='committed' then return b.result_ids; end if;
 if b.purpose<>'waybill' or jsonb_array_length(p_values) not between 1 and 50 then raise exception 'INVALID_BATCH'; end if;
 for item in select value from jsonb_array_elements(p_values) loop
  new_id:=gen_random_uuid();
  insert into public.domestic_parcels(id,carrier,tracking_number,shipment_id,link_scope,link_route,link_year,link_voyage,link_receipt_number,
   statement_route,statement_year,statement_voyage,statement_receipt,reference_type,reference_number,delivery_kind,service_kind,
   receiver_name,receiver_phone,photo_path,photo_paths,created_by,updated_by)
  select new_id,r.carrier,r.tracking_number,r.shipment_id,r.link_scope,r.link_route,r.link_year,r.link_voyage,r.link_receipt_number,
   r.statement_route,r.statement_year,r.statement_voyage,r.statement_receipt,r.reference_type,r.reference_number,r.delivery_kind,r.service_kind,
   r.receiver_name,r.receiver_phone,r.photo_path,r.photo_paths,p_owner,p_owner
  from jsonb_populate_record(null::public.domestic_parcels,item) r;
  ids:=array_append(ids,new_id);
 end loop;
 update public.waybill_intake_batches set status='committed',result_ids=ids,committed_at=now() where id=p_batch;
 return ids;
end $$;
revoke all on function public.commit_waybill_intake(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.commit_waybill_intake(uuid,uuid,jsonb) to service_role;

create function public.commit_unknown_cargo_photos(p_batch uuid,p_owner uuid,p_invoice text,p_expected_invoice text,p_photos jsonb) returns boolean
language plpgsql security invoker set search_path='' as $$
declare b public.waybill_intake_batches; s public.shipments;
begin
 select * into b from public.waybill_intake_batches where id=p_batch and owner_id=p_owner for update;
 if b.id is null or b.purpose<>'unknown' then raise exception 'FORBIDDEN'; end if;
 if b.status='committed' then return true; end if;
 select * into s from public.shipments where id=b.shipment_id for update;
 if s.id is null or not public.lk_cargo_needs_owner_check(s) then raise exception 'RECORD_CHANGED'; end if;
 if coalesce(s.invoice_number,'')<>coalesce(p_expected_invoice,'') then raise exception 'RECORD_CHANGED'; end if;
 if length(trim(p_invoice)) not between 1 and 160 then raise exception 'INVALID_TRACKING'; end if;
 insert into public.unknown_cargo_photos(shipment_id,path,kind,uploaded_by)
 select b.shipment_id,value->>'path',value->>'kind',p_owner from jsonb_array_elements(p_photos);
 update public.shipments set invoice_number=trim(p_invoice),updated_at=now() where id=b.shipment_id;
 update public.waybill_intake_batches set status='committed',committed_at=now() where id=b.id;
 return true;
end $$;
revoke all on function public.commit_unknown_cargo_photos(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.commit_unknown_cargo_photos(uuid,uuid,text,text,jsonb) to service_role;

create function public.customer_registry_change(p_id uuid,p_owner uuid,p_number bigint,p_name text,p_phone text,p_reason text,p_expected timestamptz)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare old public.customer_registry; changed public.customer_registry;
begin
 perform pg_advisory_xact_lock(7092601);
 if not exists(select 1 from public.profiles where id=p_owner and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 select * into old from public.customer_registry where id=p_id for update;
 if old.id is null or old.updated_at<>p_expected then raise exception 'RECORD_CHANGED'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'REASON_REQUIRED'; end if;
 update public.customer_registry set customer_no=p_number,name=trim(p_name),phone=trim(p_phone),updated_at=clock_timestamp() where id=p_id returning * into changed;
 perform setval('public.customer_registry_number_seq',greatest((select last_value from public.customer_registry_number_seq),p_number),true);
 insert into public.customer_registry_audit(customer_registry_id,actor_id,before_value,after_value,reason)
 values(p_id,p_owner,to_jsonb(old),to_jsonb(changed),trim(p_reason));
 return to_jsonb(changed);
end $$;
revoke all on function public.customer_registry_change(uuid,uuid,bigint,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.customer_registry_change(uuid,uuid,bigint,text,text,text,timestamptz) to service_role;
