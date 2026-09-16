-- Access is mediated by domestic-tracking Edge Function with a validated user JWT.
create table public.domestic_parcels (
  id uuid primary key default gen_random_uuid(),
  carrier text not null check (carrier in ('HAL','ANS','MIXAY','JT','LAOPOST')),
  tracking_number text not null check (tracking_number ~ '^[A-Z0-9][A-Z0-9-]{5,39}$'),
  shipment_id bigint references public.shipments(id),
  delivery_kind text not null default 'province' check (delivery_kind in ('city','province')),
  service_kind text not null default 'domestic' check (service_kind in ('domestic','inbound','outbound','ecommerce','express')),
  receiver_name text not null default '' check (length(receiver_name)<=160),
  receiver_phone text not null default '' check (length(receiver_phone)<=40),
  origin text not null default '', destination text not null default '',
  photo_path text,
  status text not null default 'registered' check (status in ('registered','accepted','in_transit','ready_for_pickup','out_for_delivery','delivered','returned','exception','unknown')),
  events jsonb not null default '[]'::jsonb check (jsonb_typeof(events)='array'),
  sync_state text not null default 'never',
  sync_error text,
  checked_at timestamptz, synced_at timestamptz,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (carrier,tracking_number)
);
create index domestic_parcels_shipment_idx on public.domestic_parcels(shipment_id);
create index domestic_parcels_created_idx on public.domestic_parcels(created_at desc,id);
create index domestic_parcels_created_by_idx on public.domestic_parcels(created_by);
create index domestic_parcels_updated_by_idx on public.domestic_parcels(updated_by);
alter table public.domestic_parcels enable row level security;
revoke all on public.domestic_parcels from public,anon,authenticated;
grant all on public.domestic_parcels to service_role;

create table public.domestic_tracking_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  hits integer not null default 0
);
alter table public.domestic_tracking_limits enable row level security;
revoke all on public.domestic_tracking_limits from public,anon,authenticated;
grant all on public.domestic_tracking_limits to service_role;
create function public.consume_domestic_tracking_limit(p_user_id uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
declare allowed boolean;
begin
 insert into public.domestic_tracking_limits(user_id,window_start,hits) values(p_user_id,now(),1)
 on conflict(user_id) do update set
 hits=case when domestic_tracking_limits.window_start < now()-interval '1 minute' then 1 else domestic_tracking_limits.hits+1 end,
 window_start=case when domestic_tracking_limits.window_start < now()-interval '1 minute' then now() else domestic_tracking_limits.window_start end
 returning hits<=30 into allowed;
 return allowed;
end $$;
revoke all on function public.consume_domestic_tracking_limit(uuid) from public,anon,authenticated;
grant execute on function public.consume_domestic_tracking_limit(uuid) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('domestic-waybills','domestic-waybills',false,5242880,array['image/jpeg','image/png','image/webp']);
-- No direct storage client policies: upload and short-lived signed URLs require server authorization.
