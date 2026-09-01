-- Patch177
create or replace function public.lk_name_tokens(p_value text)
returns text[]
language sql immutable
as $$
  select coalesce(array_agg(token order by token), array[]::text[])
  from (
    select distinct nullif(public.normalize_person_name(trim(x)), '') as token
    from regexp_split_to_table(
      regexp_replace(coalesce(p_value,''), '[?*]+', '/', 'g'),
      E'[/,;|()]+'
    ) as x
  ) q
  where token is not null;
$$;

create or replace function public.lk_name_match_rank(
  p_shipment_name text,
  p_candidate_name text
)
returns integer
language plpgsql immutable
as $$
declare
  a text[] := public.lk_name_tokens(p_shipment_name);
  b text[] := public.lk_name_tokens(p_candidate_name);
  ac integer := cardinality(a);
  bc integer := cardinality(b);
  ov integer := 0;
  a_in_b boolean := false;
  b_in_a boolean := false;
begin
  if ac=0 or bc=0 then return 9999; end if;
  select count(*) into ov from unnest(a) x where x=any(b);
  if ov=0 then return 9999; end if;
  a_in_b := not exists(select 1 from unnest(a) x where not(x=any(b)));
  b_in_a := not exists(select 1 from unnest(b) x where not(x=any(a)));
  if a_in_b and b_in_a then return 0; end if;
  if b_in_a then return 10 + (ac-bc); end if;
  if a_in_b then return 30 - least(bc,20); end if;
  return 50 - least(ov,20);
end;
$$;

create table if not exists public.receipt_discount_overrides (
  id bigserial primary key,
  route_key text not null,
  shipment_year integer not null,
  voyage text not null,
  receipt_number text not null,
  discount_name text not null default '특별할인',
  discount_percent numeric(8,6) not null default 0
    check(discount_percent>=0 and discount_percent<=1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(route_key,shipment_year,voyage,receipt_number)
);

grant select on table public.receipt_discount_overrides to authenticated,service_role;

create or replace function public.get_receipt_discount_override(
  p_route_key text,p_year integer,p_voyage text,p_receipt_number text
) returns jsonb
language sql security definer set search_path=public
as $$
  select to_jsonb(x)
  from (
    select id,route_key,shipment_year,voyage,receipt_number,
           discount_name,discount_percent
    from public.receipt_discount_overrides
    where route_key=btrim(p_route_key)
      and shipment_year=p_year
      and regexp_replace(coalesce(voyage,''),'[^0-9]','','g')
          =regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g')
      and btrim(receipt_number)=btrim(p_receipt_number)
    limit 1
  ) x;
$$;

create or replace function public.save_receipt_discount_override(
  p_route_key text,p_year integer,p_voyage text,p_receipt_number text,
  p_discount_name text,p_discount_percent numeric
) returns bigint
language plpgsql security definer set search_path=public
as $$
declare v_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.role in ('admin','staff')
  ) then raise exception '할인 수정 권한이 없습니다.'; end if;

  insert into public.receipt_discount_overrides(
    route_key,shipment_year,voyage,receipt_number,discount_name,discount_percent
  ) values(
    btrim(p_route_key),p_year,btrim(p_voyage),btrim(p_receipt_number),
    coalesce(nullif(btrim(p_discount_name),''),'특별할인'),
    greatest(0,least(1,coalesce(p_discount_percent,0)))
  )
  on conflict(route_key,shipment_year,voyage,receipt_number)
  do update set
    discount_name=excluded.discount_name,
    discount_percent=excluded.discount_percent,
    updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.delete_receipt_discount_override(
  p_route_key text,p_year integer,p_voyage text,p_receipt_number text
) returns void
language plpgsql security definer set search_path=public
as $$
begin
  if auth.uid() is null or not exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.role in ('admin','staff')
  ) then raise exception '할인 삭제 권한이 없습니다.'; end if;
  delete from public.receipt_discount_overrides
  where route_key=btrim(p_route_key)
    and shipment_year=p_year
    and regexp_replace(coalesce(voyage,''),'[^0-9]','','g')
        =regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g')
    and btrim(receipt_number)=btrim(p_receipt_number);
end $$;

revoke all on function public.get_receipt_discount_override(text,integer,text,text) from public;
revoke all on function public.save_receipt_discount_override(text,integer,text,text,text,numeric) from public;
revoke all on function public.delete_receipt_discount_override(text,integer,text,text) from public;
grant execute on function public.get_receipt_discount_override(text,integer,text,text) to authenticated,service_role;
grant execute on function public.save_receipt_discount_override(text,integer,text,text,text,numeric) to authenticated,service_role;
grant execute on function public.delete_receipt_discount_override(text,integer,text,text) to authenticated,service_role;
