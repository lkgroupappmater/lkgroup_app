-- Keep a private snapshot before removing a waybill or detaching its photos.
-- Storage objects may be shared by other waybills and are never purged here.
create table public.domestic_parcel_removals (
 id uuid primary key default gen_random_uuid(),
 parcel_id uuid not null,
 operation text not null check(operation in ('delete','remove_photo')),
 actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 photo_paths text[] not null,
 snapshot jsonb not null
);
create index domestic_parcel_removals_photos_idx on public.domestic_parcel_removals using gin(photo_paths);
alter table public.domestic_parcel_removals enable row level security;
revoke all on public.domestic_parcel_removals from public,anon,authenticated;
grant select,insert on public.domestic_parcel_removals to service_role;

create function public.manage_domestic_parcels(p_owner uuid,p_action text,p_parcels jsonb,p_photo_path text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor public.profiles; r public.domestic_parcels; item jsonb; paths text[]; remaining text[];
 deleted_ids uuid[]:='{}'; updated_rows jsonb:='[]';
begin
 select * into actor from public.profiles where id=p_owner;
 if actor.id is null or actor.role not in ('admin','staff','partner') or actor.deleted_at is not null
  or coalesce(actor.deletion_status,'active')<>'active' or coalesce(actor.approval_status,'approved')<>'approved' then raise exception 'FORBIDDEN'; end if;
 if p_action is null or p_action not in ('delete','remove_photo') or jsonb_typeof(p_parcels) is distinct from 'array'
  or jsonb_array_length(p_parcels) not between 1 and 1000 then raise exception 'INVALID_REQUEST'; end if;
 if p_action='delete' and jsonb_array_length(p_parcels)<>1 then raise exception 'INVALID_REQUEST'; end if;
 if (select count(distinct value->>'id') from jsonb_array_elements(p_parcels))<>jsonb_array_length(p_parcels) then raise exception 'INVALID_REQUEST'; end if;
 -- Stable lock order and optimistic concurrency: all selected links change or none do.
 for item in select value from jsonb_array_elements(p_parcels) order by value->>'id' loop
  select * into r from public.domestic_parcels where id=(item->>'id')::uuid for update;
  if r.id is null then raise exception 'NOT_FOUND'; end if;
  if actor.role='partner' and r.created_by is distinct from p_owner then raise exception 'FORBIDDEN'; end if;
  if r.updated_at is distinct from (item->>'updated_at')::timestamptz then raise exception 'RECORD_CHANGED'; end if;
  select coalesce(array_agg(path order by n),'{}') into paths from (
   select path,min(n) n from unnest(coalesce(r.photo_paths,'{}') || case when r.photo_path is null then '{}'::text[] else array[r.photo_path] end) with ordinality a(path,n) group by path
  ) ordered_paths;
  if p_action='remove_photo' and (p_photo_path is null or not p_photo_path=any(paths)) then raise exception 'PHOTO_NOT_FOUND'; end if;
  insert into public.domestic_parcel_removals(parcel_id,operation,actor_id,photo_paths,snapshot) values(r.id,p_action,p_owner,paths,to_jsonb(r));
  remaining:=array_remove(paths,p_photo_path);
  if p_action='delete' or (r.is_reference_photo and cardinality(remaining)=0) then
   delete from public.domestic_parcels where id=r.id;
   deleted_ids:=array_append(deleted_ids,r.id);
  else
   update public.domestic_parcels set photo_paths=remaining,photo_path=remaining[1],updated_by=p_owner,updated_at=clock_timestamp() where id=r.id returning * into r;
   updated_rows:=updated_rows||jsonb_build_array(to_jsonb(r));
  end if;
 end loop;
 return jsonb_build_object('deleted_ids',deleted_ids,'parcels',updated_rows);
end $$;
revoke all on function public.manage_domestic_parcels(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.manage_domestic_parcels(uuid,text,jsonb,text) to service_role;
