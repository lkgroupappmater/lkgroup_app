create or replace function public.commit_waybill_intake(p_batch uuid,p_owner uuid,p_values jsonb) returns uuid[]
language plpgsql security invoker set search_path='' as $$
declare b public.waybill_intake_batches; ids uuid[]; item jsonb; new_id uuid;
begin
 select * into b from public.waybill_intake_batches where id=p_batch and owner_id=p_owner for update;
 if b.id is null then raise exception 'FORBIDDEN'; end if;
 if b.status='committed' then return b.result_ids; end if;
 if b.purpose<>'waybill' or jsonb_array_length(p_values) not between 1 and 50 then raise exception 'INVALID_BATCH'; end if;
 for item in select value from jsonb_array_elements(p_values) loop
  if jsonb_array_length(item->'photo_paths') not between 1 and 50 or exists(
   select 1 from jsonb_array_elements_text(item->'photo_paths') p where not exists(
    select 1 from public.waybill_intake_files f where f.batch_id=b.id and f.path=p and f.verified_at is not null)) then raise exception 'INVALID_IMAGE'; end if;
  new_id:=gen_random_uuid();
  insert into public.domestic_parcels(id,is_reference_photo,carrier,tracking_number,shipment_id,link_scope,link_route,link_year,link_voyage,link_receipt_number,
   statement_route,statement_year,statement_voyage,statement_receipt,reference_type,reference_number,delivery_kind,service_kind,
   receiver_name,receiver_phone,photo_path,photo_paths,created_by,updated_by)
  select new_id,coalesce(r.is_reference_photo,false),r.carrier,r.tracking_number,r.shipment_id,r.link_scope,r.link_route,r.link_year,r.link_voyage,r.link_receipt_number,
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

-- Append only photos; never overwrite a concurrent edit to a waybill or its recipient.
create function public.attach_domestic_reference_photos(p_batch uuid,p_owner uuid,p_parcel uuid) returns uuid[]
language plpgsql security invoker set search_path='' as $$
declare b public.waybill_intake_batches; r public.domestic_parcels; actor public.profiles; paths text[];
begin
 select * into actor from public.profiles where id=p_owner;
 if actor.id is null or actor.role not in ('admin','staff','partner') or actor.deleted_at is not null
  or coalesce(actor.deletion_status,'active')<>'active' or coalesce(actor.approval_status,'approved')<>'approved' then raise exception 'FORBIDDEN'; end if;
 select * into b from public.waybill_intake_batches where id=p_batch and owner_id=p_owner for update;
 if b.id is null then raise exception 'FORBIDDEN'; end if;
 select * into r from public.domestic_parcels where id=p_parcel for update;
 if r.id is null or (actor.role='partner' and r.created_by is distinct from p_owner) then raise exception 'FORBIDDEN'; end if;
 if b.status='committed' then
  if b.result_ids is distinct from array[p_parcel] then raise exception 'BATCH_COMMITTED'; end if;
  return b.result_ids;
 end if;
 if b.purpose<>'photos' or b.created_at<now()-interval '24 hours' then raise exception 'INVALID_BATCH'; end if;
 if not exists(select 1 from public.waybill_intake_files where batch_id=b.id) or exists(
  select 1 from public.waybill_intake_files where batch_id=b.id and verified_at is null) then raise exception 'INVALID_IMAGE'; end if;
 select array_agg(path order by n) into paths from (
  select path,min(n) n from unnest(coalesce(r.photo_paths,'{}') || case when r.photo_path is null then '{}'::text[] else array[r.photo_path] end ||
   array(select f.path from public.waybill_intake_files f where f.batch_id=b.id order by f.created_at,f.id)) with ordinality a(path,n)
  group by path) ordered_paths;
 if cardinality(paths)>50 then raise exception 'TOO_MANY_PHOTOS'; end if;
 update public.domestic_parcels set photo_paths=paths,photo_path=paths[1],updated_by=p_owner where id=p_parcel;
 update public.waybill_intake_batches set status='committed',result_ids=array[p_parcel],committed_at=now() where id=b.id;
 return array[p_parcel];
end $$;
revoke all on function public.attach_domestic_reference_photos(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.attach_domestic_reference_photos(uuid,uuid,uuid) to service_role;
