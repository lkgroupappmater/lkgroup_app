-- Deterministic city/province delivery identity matching.
--
-- Priority:
--   1) one exact full-name + phone match
--   2) one exact full-name match
--   3) one phone-only match
-- Ambiguous and partial-name matches are intentionally rejected.
-- `수취인 불명 / 이름` keeps its original shipment name/receipt; only the
-- trailing name is used while looking up a delivery profile.

begin;

create or replace function public.lk_delivery_match_name(p_name text)
returns text
language sql
immutable
set search_path=public
as $$
  select case
    when strpos(coalesce(p_name,''),'/')>0
      and lower(regexp_replace(
        btrim(split_part(coalesce(p_name,''),'/',1)),
        '[\s._-]+','','g'
      )) = any(array[
        '수취인불명','수신인불명','미확인','불확실',
        'unknown','unidentified'
      ]::text[])
      and btrim(substr(p_name,strpos(p_name,'/')+1))<>''
    then btrim(substr(p_name,strpos(p_name,'/')+1))
    else btrim(coalesce(p_name,''))
  end;
$$;

create or replace function public.lk_delivery_name_matches(
  p_profile_name text,
  p_shipment_name text
)
returns boolean
language sql
immutable
set search_path=public
as $$
  select public.lk_exact_full_name_matches(
    p_profile_name,
    public.lk_delivery_match_name(p_shipment_name)
  );
$$;

create or replace function public.lk_delivery_profile_name_matches(
  p_customer_name text,
  p_alternate_name text,
  p_company_name text,
  p_shipment_name text
)
returns boolean
language sql
immutable
set search_path=public
as $$
  select
    public.lk_delivery_name_matches(p_customer_name,p_shipment_name)
    or (
      coalesce(btrim(p_alternate_name),'')<>''
      and public.lk_delivery_name_matches(p_alternate_name,p_shipment_name)
    )
    or (
      coalesce(btrim(p_company_name),'')<>''
      and public.lk_delivery_name_matches(p_company_name,p_shipment_name)
    );
$$;

create or replace function public.lk_resolve_delivery_profile_id(
  p_route_key text,
  p_shipment_name text,
  p_shipment_phone text
)
returns bigint
language sql
stable
set search_path=public
as $$
  with candidates as (
    select
      d.id,
      public.lk_delivery_profile_name_matches(
        d.customer_name,d.alternate_name,d.company_name,p_shipment_name
      ) exact_name,
      public.phone_matches(d.phone,p_shipment_phone) phone_match
    from public.local_delivery_profiles d
    where d.active=true and d.route_key=p_route_key
  ), ranked as (
    select id,case
      when exact_name and phone_match then 1
      when exact_name then 2
      when phone_match then 3
      else 9999
    end priority
    from candidates
  ), best as (
    select min(priority) priority from ranked where priority<9999
  )
  select case when count(*)=1 then min(r.id) else null end
  from ranked r join best b using(priority);
$$;

-- This legacy per-row score is retained for older batch code. It now accepts
-- only a full-name+phone pair; unique single-identifier fallbacks are handled
-- by lk_resolve_delivery_profile_id(), which can see every profile at once.
create or replace function public.lk_delivery_candidate_rank(
  p_paid_by text,
  p_customer_name text,
  p_alternate_name text,
  p_company_name text,
  p_profile_phone text,
  p_shipment_name text,
  p_shipment_phone text
)
returns integer
language sql
immutable
set search_path=public
as $$
  select case
    when public.lk_delivery_profile_name_matches(
      p_customer_name,p_alternate_name,p_company_name,p_shipment_name
    ) and public.phone_matches(p_profile_phone,p_shipment_phone)
    then 10
    else 9999
  end;
$$;

create or replace function public.compute_shipment_special_note(
  p_route text,
  p_name text,
  p_phone text
)
returns text
language plpgsql
stable
set search_path=public
as $$
declare
  v_route_key text := public.route_base_key_for_label(p_route);
  v_group text := '';
  v_discount numeric := 0;
  v_discount_notes text := '';
  v_discount_text text := '';
  v_delivery_type text := '';
  v_paid_by text := '';
  v_delivery_text text := '';
  v_share_text text := '';
  v_delivery_id bigint;
begin
  if public.lk_is_park_seongho(p_name) then
    v_group := '대표 고정 할인';
    v_discount := 1;
  else
    select coalesce(r.group_name,''),coalesce(r.discount_percent,0),coalesce(r.notes,'')
      into v_group,v_discount,v_discount_notes
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=v_route_key or r.route_key='all')
      and (
        (
          public.phone_matches(r.phone,p_phone)
          and least(
            public.lk_name_match_rank(p_name,r.customer_name),
            case when coalesce(btrim(r.company_name),'')=''
              then 9999 else public.lk_name_match_rank(p_name,r.company_name) end
          )<9999
        )
        or (
          public.lk_recipient_phone_uncertain(p_phone)
          and (
            public.lk_exact_full_name_matches(
              public.lk_receipt_name_key(p_name),r.customer_name
            )
            or public.lk_exact_full_name_matches(
              public.lk_receipt_name_key(p_name),r.company_name
            )
          )
        )
      )
    order by
      case when r.route_key=v_route_key then 0 else 1 end,
      case when public.lk_exact_full_name_matches(p_name,r.customer_name)
              or public.lk_exact_full_name_matches(p_name,r.company_name)
           then 0 else 1 end,
      r.id
    limit 1;
  end if;

  v_delivery_id := public.lk_resolve_delivery_profile_id(
    v_route_key,p_name,p_phone
  );
  if v_delivery_id is not null then
    select coalesce(d.delivery_type,''),coalesce(d.paid_by,'')
      into v_delivery_type,v_paid_by
    from public.local_delivery_profiles d
    where d.id=v_delivery_id;
  end if;

  select coalesce(s.content,'') into v_share_text
  from public.customer_statement_share_rules s
  where s.active=true
    and s.route_key=v_route_key
    and (
      (
        public.phone_matches(s.phone,p_phone)
        and public.lk_name_match_rank(p_name,s.customer_name)<9999
      )
      or (
        public.lk_recipient_phone_uncertain(p_phone)
        and public.lk_exact_full_name_matches(
          public.lk_receipt_name_key(p_name),s.customer_name
        )
      )
    )
  order by
    case when public.lk_exact_full_name_matches(p_name,s.customer_name)
         then 0 else 1 end,
    s.source_no,s.id
  limit 1;

  if coalesce(v_delivery_type,'')<>'' then
    if coalesce(v_share_text,'')='' then
      v_share_text := case
        when public.lk_delivery_is_prepaid(v_paid_by)
          then '한국 카톡 명세서 선공유 및 온라인 결제'
        else '카톡 명세서 선공유'
      end;
    end if;
    v_delivery_text :=
      case when v_delivery_type='city' then '시내배송' else '지방배송' end
      || case when public.lk_delivery_is_prepaid(v_paid_by)
              then '(선결제)' else '' end;
  end if;

  if coalesce(v_discount,0)>0 then
    v_discount_text :=
      case
        when btrim(coalesce(v_group,''))='' then '할인'
        when btrim(v_group) like '%할인%' then btrim(v_group)
        else btrim(v_group)||' 할인'
      end
      || ' ' || trim(to_char(v_discount*100,'FM999990.##')) || '% 적용';
  end if;

  return concat_ws(
    ' / ',
    nullif(btrim(v_share_text),''),
    nullif(btrim(v_discount_text),''),
    nullif(btrim(v_discount_notes),''),
    nullif(btrim(v_delivery_text),'')
  );
end;
$$;

-- Keep the existing batch normalization intact, then add the unique fallback
-- pass. Renaming once avoids copying/replacing the long proven batch routine.
do $$
begin
  if to_regprocedure(
    'public.lk_apply_excel_logic_parity_legacy_v103(text,integer,text)'
  ) is null then
    alter function public.lk_apply_excel_logic_parity(text,integer,text)
      rename to lk_apply_excel_logic_parity_legacy_v103;
  end if;
end;
$$;

create or replace function public.lk_apply_excel_logic_parity(
  p_route text,
  p_year integer,
  p_voyage text
)
returns void
language plpgsql
set search_path=public
as $$
declare
  v_route_key text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'
  );
begin
  perform public.lk_apply_excel_logic_parity_legacy_v103(
    p_route,p_year,p_voyage
  );

  select rd.route_key into v_route_key
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(v_route_key,'')='' then return; end if;

  update public.shipments s
  set unloading_zone='F',
      special_note_auto=public.compute_shipment_special_note(
        s.route,s.consignee_name,s.consignee_phone
      )
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_resolve_delivery_profile_id(
      v_route_key,s.consignee_name,s.consignee_phone
    ) is not null;
end;
$$;

revoke all on function public.lk_delivery_match_name(text) from public,anon;
revoke all on function public.lk_delivery_name_matches(text,text) from public,anon;
revoke all on function public.lk_delivery_profile_name_matches(text,text,text,text) from public,anon;
revoke all on function public.lk_resolve_delivery_profile_id(text,text,text) from public,anon;
revoke all on function public.lk_delivery_candidate_rank(text,text,text,text,text,text,text) from public,anon;
revoke all on function public.compute_shipment_special_note(text,text,text) from public,anon;
revoke all on function public.lk_apply_excel_logic_parity(text,integer,text) from public,anon;

grant execute on function public.lk_delivery_match_name(text) to authenticated,service_role;
grant execute on function public.lk_delivery_name_matches(text,text) to authenticated,service_role;
grant execute on function public.lk_delivery_profile_name_matches(text,text,text,text) to authenticated,service_role;
grant execute on function public.lk_resolve_delivery_profile_id(text,text,text) to authenticated,service_role;
grant execute on function public.lk_delivery_candidate_rank(text,text,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.compute_shipment_special_note(text,text,text) to authenticated,service_role;
grant execute on function public.lk_apply_excel_logic_parity(text,integer,text) to authenticated,service_role;

commit;
