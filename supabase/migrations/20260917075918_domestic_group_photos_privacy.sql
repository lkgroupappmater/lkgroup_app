-- Extend the existing private delivery table; keep its grants and policies.
alter table public.domestic_parcels add column photo_paths text[] not null default '{}';
update public.domestic_parcels set photo_paths=array[photo_path] where photo_path is not null;
alter table public.domestic_parcels add constraint domestic_photo_count check (cardinality(photo_paths)<=10 and array_position(photo_paths,null) is null);

create function public.domestic_parcel_group_key(p public.domestic_parcels)
returns text language sql stable security invoker set search_path='' as $$
 select case
 when coalesce(p.link_receipt_number,p.statement_receipt,s.receipt_number) is not null then
  jsonb_build_array('statement',coalesce(p.link_route,p.statement_route,s.route),coalesce(p.link_year,p.statement_year,s.shipment_year),public.domestic_receipt_key(coalesce(p.link_voyage,p.statement_voyage,s.voyage)),public.domestic_receipt_key(coalesce(p.link_receipt_number,p.statement_receipt,s.receipt_number)))::text
 when p.reference_number is not null then jsonb_build_array('reference',p.reference_type,p.reference_number)::text
 when p.shipment_id is not null then jsonb_build_array('cargo',p.shipment_id)::text
 else jsonb_build_array('parcel',p.id)::text end
 from (values(1)) x(n) left join public.shipments s on s.id=p.shipment_id;
$$;
create function public.domestic_parcel_group_page(p_page integer default 0,p_size integer default 10)
returns table(group_key text,parcels jsonb) language sql stable security invoker set search_path='' as $$
 with keyed as (select public.domestic_parcel_group_key(p) as k,p.created_at,to_jsonb(p) as row from public.domestic_parcels p),
 groups as (select k,max(created_at) as latest from keyed group by k order by max(created_at) desc,k limit least(greatest(p_size,1),20)+1 offset greatest(p_page,0)*least(greatest(p_size,1),20))
 select g.k,jsonb_agg(k.row order by k.created_at,k.row->>'id') from groups g join keyed k on k.k=g.k group by g.k,g.latest order by g.latest desc,g.k;
$$;
revoke all on function public.domestic_parcel_group_key(public.domestic_parcels),public.domestic_parcel_group_page(integer,integer) from public,anon,authenticated;
grant execute on function public.domestic_parcel_group_key(public.domestic_parcels),public.domestic_parcel_group_page(integer,integer) to service_role;

create function public.lk_mask_recipient_name(p_value text) returns text
language sql immutable security invoker set search_path='' as $$
 select case when length(btrim(coalesce(p_value,'')))=0 then '' when length(btrim(p_value))=1 then '*'
 when length(btrim(p_value))=2 then left(btrim(p_value),1)||'*'
 else left(btrim(p_value),1)||repeat('*',length(btrim(p_value))-2)||right(btrim(p_value),1) end;
$$;
create function public.lk_mask_recipient_phone(p_value text) returns text
language plpgsql immutable security invoker set search_path='' as $$
declare v text:=coalesce(p_value,''); n integer:=0; i integer;
begin
 for i in reverse length(v)..1 loop
  if substr(v,i,1) ~ '[0-9]' then v:=overlay(v placing '*' from i for 1);n:=n+1;exit when n=4;end if;
 end loop;return v;
end;
$$;
revoke all on function public.lk_mask_recipient_name(text),public.lk_mask_recipient_phone(text) from public,anon,authenticated;
grant execute on function public.lk_mask_recipient_name(text),public.lk_mask_recipient_phone(text) to service_role;

-- Keep recovery search scope, rate limit and correction workflow; redact at source.
CREATE OR REPLACE FUNCTION public.search_shipments_by_invoice_suffix(p_invoice_suffix text)
 RETURNS TABLE(id bigint, route text, shipment_year integer, voyage text, box_number text, invoice_number text, consignee_name text, consignee_phone text, quantity integer, weight_kg numeric, length_cm numeric, width_cm numeric, height_cm numeric, received_at date, status text, recipient_unknown boolean, invoice_suffix_match boolean, correction_pending boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_suffix text := regexp_replace(lower(coalesce(p_invoice_suffix, '')), '[^a-z0-9]', '', 'g');
  v_recent_count integer;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다.';
  end if;
  if public.current_role() <> 'member' then
    raise exception '일반 회원의 송장번호 복구 검색 전용 기능입니다.';
  end if;
  if length(v_suffix) < 4 then
    raise exception '송장번호 뒤 4자리 이상을 입력해 주세요.';
  end if;
  if length(v_suffix) > 32 then
    raise exception '송장번호가 너무 깁니다.';
  end if;

  select count(*) into v_recent_count
  from public.invoice_suffix_search_audit a
  where a.requester_id = v_uid
    and a.queried_at >= now() - interval '1 hour';

  if v_recent_count >= 30 then
    raise exception '송장번호 검색 횟수를 초과했습니다. 잠시 후 다시 시도해 주세요.';
  end if;

  insert into public.invoice_suffix_search_audit(requester_id) values (v_uid);

  return query
  select
    s.id,
    s.route,
    s.shipment_year,
    s.voyage,
    s.box_number,
    '••••' || right(regexp_replace(lower(coalesce(s.invoice_number, '')), '[^a-z0-9]', '', 'g'), length(v_suffix)),
    case when s.recipient_unknown then '수취인 불명' else public.lk_mask_recipient_name(s.consignee_name) end,
    public.lk_mask_recipient_phone(s.consignee_phone),
    s.quantity,
    s.weight_kg,
    s.length_cm,
    s.width_cm,
    s.height_cm,
    s.received_at,
    s.status,
    s.recipient_unknown,
    true,
    exists (
      select 1 from public.invoice_correction_requests r
      where r.shipment_id = s.id
        and r.requester_id = v_uid
        and r.status = 'pending'
    )
  from public.shipments s
  where s.deleted_at is null
    and s.deletion_requested_at is null
    and right(
      regexp_replace(lower(coalesce(s.invoice_number, '')), '[^a-z0-9]', '', 'g'),
      length(v_suffix)
    ) = v_suffix
  order by s.shipment_year desc nulls last, s.received_at desc nulls last, s.id desc
  limit 20;
end;
$function$

;

-- Full records require an assigned owner or both recipient name and phone.
CREATE OR REPLACE FUNCTION public.search_shipments_for_current_user(p_route text DEFAULT ''::text, p_year integer DEFAULT NULL::integer, p_voyage text DEFAULT ''::text, p_box_number text DEFAULT ''::text, p_invoice text DEFAULT ''::text, p_recipient text DEFAULT ''::text, p_phone text DEFAULT ''::text)
 RETURNS SETOF shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_profile public.profiles%rowtype;
  v_invoice text := trim(coalesce(p_invoice, ''));
  v_recipient text := trim(coalesce(p_recipient, ''));
  v_phone_digits text := public.only_digits(p_phone);
  v_box text := trim(coalesce(p_box_number, ''));
begin
  select * into v_profile from public.profiles where id = auth.uid();
  v_role := v_profile.role;
  if v_role is null then return; end if;

  if v_role = 'member' then
    return query
    select s.*
      from public.shipments s
     where s.deleted_at is null and s.deletion_requested_at is null
       and (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or
            ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (
            s.customer_id = auth.uid()
         or (
              coalesce(trim(v_profile.name),'') <> ''
              and lower(trim(coalesce(s.consignee_name,''))) = lower(trim(v_profile.name))
              and length(public.only_digits(v_profile.phone)) >= 8
              and right(public.only_digits(s.consignee_phone), 8) = right(public.only_digits(v_profile.phone), 8)
            )
       )
       and (v_invoice = '' or
            lower(coalesce(s.invoice_number,'')) like '%' || lower(v_invoice) || '%')
       and (v_recipient = '' or
            lower(coalesce(s.consignee_name,'')) like '%' || lower(v_recipient) || '%')
       and (v_phone_digits = '' or
            right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits)
     order by s.route, s.shipment_year desc, s.voyage desc,
              s.received_at desc nulls last, s.id desc
     limit 500;
    return;
  end if;

  if v_role in ('admin','staff','partner') then
    if v_invoice <> '' and length(v_invoice) < 4 then return; end if;
    if v_phone_digits <> '' and length(v_phone_digits) < 4 then return; end if;

    return query
    select s.*
      from public.shipments s
     where s.deleted_at is null and s.deletion_requested_at is null
       and (coalesce(p_route, '') = '' or s.route = p_route)
       and (p_year is null or s.shipment_year = p_year)
       and (coalesce(p_voyage, '') = '' or
            ltrim(coalesce(s.voyage, ''), '0') = ltrim(p_voyage, '0'))
       and (v_box = '' or lower(coalesce(s.box_number, '')) like '%' || lower(v_box) || '%')
       and (v_invoice = '' or lower(coalesce(s.invoice_number, '')) like '%' || lower(v_invoice) || '%')
       and (v_recipient = '' or lower(coalesce(s.consignee_name, '')) like '%' || lower(v_recipient) || '%')
       and (v_phone_digits = '' or right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits)
     order by s.route, s.shipment_year desc, s.voyage desc,
              s.received_at desc nulls last, s.id desc
     limit 1000;
  end if;
end;
$function$

;
