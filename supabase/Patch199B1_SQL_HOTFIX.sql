-- Patch199B1 SQL hotfix
-- Fix PostgreSQL GROUP BY error in lk_dedupe_remark().
-- Safe to run even though the previous Patch199B1 SQL failed.

create or replace function public.lk_dedupe_remark(p_text text)
returns text
language sql
immutable
as $$
  select coalesce(string_agg(q.token, ' / ' order by q.first_ord), '')
  from (
    select
      min(t.ord) as first_ord,
      min(btrim(t.token)) as token
    from unnest(regexp_split_to_array(coalesce(p_text,''), E'\\s*/\\s*'))
      with ordinality as t(token, ord)
    where btrim(t.token) <> ''
    group by lower(regexp_replace(btrim(t.token), E'\\s+', ' ', 'g'))
  ) q;
$$;

create or replace function public.admin_prepare_resolved_unknown_receipts(
  p_route text,
  p_year integer,
  p_voyage text
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer := 0;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
begin
  update public.shipments s
  set receipt_number = '',
      recipient_unknown = false
  where s.route = p_route
    and s.shipment_year = p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0') = v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and upper(btrim(coalesce(s.receipt_number,''))) like '%XX'
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.admin_cleanup_batch_remarks(
  p_route text,
  p_year integer,
  p_voyage text
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer := 0;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
begin
  update public.shipments s
  set special_note_auto = public.lk_dedupe_remark(s.special_note_auto)
  where s.route = p_route
    and s.shipment_year = p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0') = v_voyage
    and s.deletion_requested_at is null
    and coalesce(s.special_note_auto,'') <> public.lk_dedupe_remark(s.special_note_auto);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.admin_prepare_resolved_unknown_receipts(text,integer,text) from public;
revoke all on function public.admin_cleanup_batch_remarks(text,integer,text) from public;
grant execute on function public.admin_prepare_resolved_unknown_receipts(text,integer,text) to authenticated,service_role;
grant execute on function public.admin_cleanup_batch_remarks(text,integer,text) to authenticated,service_role;

alter table public.receipt_discount_overrides
  alter column discount_name set default '추가 할인';

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
  ) then raise exception '추가 할인 수정 권한이 없습니다.'; end if;

  insert into public.receipt_discount_overrides(
    route_key,shipment_year,voyage,receipt_number,discount_name,discount_percent
  ) values(
    btrim(p_route_key),p_year,btrim(p_voyage),btrim(p_receipt_number),
    coalesce(nullif(btrim(p_discount_name),''),'추가 할인'),
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

revoke all on function public.save_receipt_discount_override(text,integer,text,text,text,numeric) from public;
grant execute on function public.save_receipt_discount_override(text,integer,text,text,text,numeric)
  to authenticated,service_role;
