-- Final Excel/app logic parity for LKS and LKA.
-- Apply after the existing BASE/discount/delivery/share-rule migrations.
-- Manual values protected with shipments.data_locked=true are not overwritten.

create or replace function public.lk_exact_full_name_matches(a text,b text)
returns boolean
language sql
immutable
as $$
  select regexp_replace(lower(btrim(coalesce(a,''))), '\s+', '', 'g') <> ''
     and regexp_replace(lower(btrim(coalesce(a,''))), '\s+', '', 'g')
       = regexp_replace(lower(btrim(coalesce(b,''))), '\s+', '', 'g');
$$;

-- Names separated by /, comma, etc. may be used for ordinary delivery and
-- benefit lookups. A masked token is ignored instead of becoming a fuzzy key.
create or replace function public.lk_name_tokens(p_value text)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(token order by token), array[]::text[])
  from (
    select distinct
      nullif(public.normalize_person_name(btrim(part)), '') token
    from regexp_split_to_table(coalesce(p_value,''), E'[/,;|()]+') part
    where btrim(part) <> ''
      and part !~ '[*?#＊？]'
  ) q
  where token is not null;
$$;

create or replace function public.lk_name_match_rank(
  p_shipment_name text,
  p_candidate_name text
)
returns integer
language plpgsql
immutable
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

-- Receipt identity deliberately uses the first slash token only for the
-- special masked-name recovery pass. Full normal names remain separate, so
-- "이경희" and "이경화/이경희" never collapse into one receipt.
create or replace function public.lk_receipt_name_key(p_name text)
returns text
language sql
immutable
as $$
  select public.normalize_person_name(
    btrim(split_part(coalesce(p_name,''),'/',1))
  );
$$;

create or replace function public.lk_recipient_name_uncertain(p_name text)
returns boolean
language sql
immutable
as $$
  with v as (
    select lower(btrim(split_part(coalesce(p_name,''),'/',1))) first_name
  )
  select first_name=''
    or first_name ~ '[*?#＊？]'
    or first_name ~ '^(수취인[ ]*불명|수신인[ ]*불명|불확실한[ ]*물품|불확실|미확인|기호포함[ ]*이름|unknown|unidentified|n/a|na|none)'
  from v;
$$;

create or replace function public.lk_recipient_true_unknown(
  p_name text,
  p_phone text
)
returns boolean
language sql
immutable
as $$
  select case
    -- 이우용/이*용: normal; 수취인 불명/확인된 이름: LKS/LKA XX.
    -- A normal written name stays normal even when the phone contains ***.
    when coalesce(btrim(p_name),'')<>''
      then public.lk_recipient_name_uncertain(p_name)
    else public.lk_recipient_phone_uncertain(p_phone)
  end;
$$;

create or replace function public.refresh_recipient_unknown_flag()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.recipient_unknown_confirmed_at is not null then
    new.recipient_unknown := false;
    return new;
  end if;
  new.recipient_unknown := public.lk_recipient_true_unknown(
    new.consignee_name,new.consignee_phone
  );
  return new;
end;
$$;

create or replace function public.lk_delivery_is_prepaid(p_paid_by text)
returns boolean
language sql
immutable
as $$
  select lower(regexp_replace(coalesce(p_paid_by,''), '[\s_-]+', '', 'g'))
    ~ '(선결제|선결재|선불|prepaid|payinadvance)';
$$;

-- Prepaid: exact full name only. Ordinary: exact name+phone, exact name,
-- split-name+phone, phone-only recovery (Vang Vieng), then split-name only.
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
language plpgsql
immutable
as $$
declare
  v_exact boolean :=
    public.lk_exact_full_name_matches(p_shipment_name,p_customer_name)
    or public.lk_exact_full_name_matches(p_shipment_name,p_alternate_name)
    or public.lk_exact_full_name_matches(p_shipment_name,p_company_name);
  v_partial integer := least(
    public.lk_name_match_rank(p_shipment_name,p_customer_name),
    case when coalesce(btrim(p_alternate_name),'')=''
      then 9999 else public.lk_name_match_rank(p_shipment_name,p_alternate_name) end,
    case when coalesce(btrim(p_company_name),'')=''
      then 9999 else public.lk_name_match_rank(p_shipment_name,p_company_name) end
  );
  v_phone boolean := public.phone_matches(p_profile_phone,p_shipment_phone);
begin
  if public.lk_delivery_is_prepaid(p_paid_by) then
    return case when v_exact then 0 else 9999 end;
  end if;
  if v_exact and v_phone then return 10; end if;
  if v_exact then return 20; end if;
  if v_partial<9999 and v_phone then return 30+v_partial; end if;
  if v_phone then return 100; end if;
  if v_partial<9999 then return 200+v_partial; end if;
  return 9999;
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

  select coalesce(d.delivery_type,''),coalesce(d.paid_by,'')
    into v_delivery_type,v_paid_by
  from public.local_delivery_profiles d
  where d.active=true
    and d.route_key=v_route_key
    and public.lk_delivery_candidate_rank(
      d.paid_by,d.customer_name,d.alternate_name,d.company_name,d.phone,
      p_name,p_phone
    )<9999
  order by
    public.lk_delivery_candidate_rank(
      d.paid_by,d.customer_name,d.alternate_name,d.company_name,d.phone,
      p_name,p_phone
    ),
    d.preferred desc,
    case when coalesce(d.destination_address,'')<>'' then 0 else 1 end,
    d.source_no nulls last,d.id
  limit 1;

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
  v_prefix text;
  v_voyage text := lpad(
    regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0'
  );
begin
  select rd.route_key,rd.receipt_prefix into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;
  if coalesce(v_route_key,'')='' then return; end if;

  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' XX'
        else btrim(v_prefix)||'XX'
      end,
      unloading_zone='F'
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  update public.shipments s
  set recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone);

  -- Merge only whitespace variants of the same complete name and phone.
  with grouped as (
    select
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g') full_name_key,
      right(public.normalize_phone(s.consignee_phone),8) phone_key,
      coalesce(
        min(btrim(s.receipt_number)) filter(where coalesce(s.data_locked,false)),
        min(btrim(s.receipt_number))
      ) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and btrim(coalesce(s.receipt_number,''))<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by
      regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g'),
      right(public.normalize_phone(s.consignee_phone),8)
  )
  update public.shipments s
  set receipt_number=g.receipt_number,recipient_unknown=false
  from grouped g
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and regexp_replace(lower(btrim(s.consignee_name)),'\s+','','g')=g.full_name_key
    and right(public.normalize_phone(s.consignee_phone),8)=g.phone_key;

  -- 이우용/이*용 follows a single confirmed 이우용 receipt.
  with known as (
    select public.lk_receipt_name_key(s.consignee_name) name_key,
           min(btrim(s.receipt_number)) receipt_number
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
      and public.lk_receipt_name_key(s.consignee_name)<>''
      and not public.lk_recipient_phone_uncertain(s.consignee_phone)
      and coalesce(btrim(s.receipt_number),'')<>''
      and btrim(s.receipt_number)!~* 'XX$'
    group by public.lk_receipt_name_key(s.consignee_name)
    having count(distinct right(public.normalize_phone(s.consignee_phone),8))=1
       and count(distinct btrim(s.receipt_number))=1
  )
  update public.shipments s
  set receipt_number=k.receipt_number,recipient_unknown=false
  from known k
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
    and public.lk_recipient_phone_uncertain(s.consignee_phone)
    and public.lk_receipt_name_key(s.consignee_name)=k.name_key;

  update public.shipments s
  set receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' 100'
        else btrim(v_prefix)||'100'
      end,
      unloading_zone='102',recipient_unknown=false
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and public.lk_is_park_seongho(s.consignee_name);

  with qty as (
    select btrim(s.receipt_number) receipt,
           sum(greatest(coalesce(s.quantity,1),1))::integer total_qty
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
    group by btrim(s.receipt_number)
  )
  update public.shipments s
  set unloading_zone=case
    when public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      then 'F'
    when public.lk_is_park_seongho(s.consignee_name) then '102'
    when exists(
      select 1 from public.customer_zone_overrides z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
    ) then coalesce((
      select z.zone from public.customer_zone_overrides z
      where z.active=true
        and (z.route_key=v_route_key or z.route_key='all')
        and public.lk_name_match_rank(s.consignee_name,z.customer_name)<9999
      order by
        public.lk_name_match_rank(s.consignee_name,z.customer_name),
        case when z.route_key=v_route_key then 0 else 1 end,z.id
      limit 1
    ),'102')
    when public.lk_receipt_name_key(s.consignee_name)
           =public.normalize_person_name('김요셉')
      or lower(coalesce(s.consignee_name,'')) like '%beauty panda%'
      or coalesce(s.consignee_name,'') like '%뷰티판다%' then 'F'
    when exists(
      select 1 from public.local_delivery_profiles d
      where d.active=true and d.route_key=v_route_key
        and public.lk_delivery_candidate_rank(
          d.paid_by,d.customer_name,d.alternate_name,d.company_name,d.phone,
          s.consignee_name,s.consignee_phone
        )<9999
    ) then 'F'
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from qty q
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null
    and not coalesce(s.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  update public.shipments s
  set special_note_auto=public.compute_shipment_special_note(
    s.route,s.consignee_name,s.consignee_phone
  )
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;
end;
$$;

create or replace function public.admin_finalize_excel_batch_rules_fast(
  p_route text,
  p_year integer,
  p_voyage text,
  p_resequence boolean default true
)
returns void
language plpgsql
set search_path=public
as $$
begin
  perform set_config('lkgroup.bulk_import','1',true);
  perform public.admin_finalize_excel_batch_rules(
    p_route,p_year,p_voyage,p_resequence
  );
  perform public.lk_apply_excel_logic_parity(p_route,p_year,p_voyage);
  perform set_config('lkgroup.bulk_import','0',true);
exception when others then
  perform set_config('lkgroup.bulk_import','0',true);
  raise;
end;
$$;

revoke all on function public.lk_apply_excel_logic_parity(text,integer,text) from public;
revoke all on function public.admin_finalize_excel_batch_rules_fast(text,integer,text,boolean) from public;
grant execute on function public.lk_exact_full_name_matches(text,text) to authenticated,service_role;
grant execute on function public.lk_name_tokens(text) to authenticated,service_role;
grant execute on function public.lk_name_match_rank(text,text) to authenticated,service_role;
grant execute on function public.lk_receipt_name_key(text) to authenticated,service_role;
grant execute on function public.lk_recipient_name_uncertain(text) to authenticated,service_role;
grant execute on function public.lk_recipient_true_unknown(text,text) to authenticated,service_role;
grant execute on function public.lk_delivery_is_prepaid(text) to authenticated,service_role;
grant execute on function public.lk_delivery_candidate_rank(text,text,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.lk_apply_excel_logic_parity(text,integer,text) to authenticated,service_role;
grant execute on function public.admin_finalize_excel_batch_rules_fast(text,integer,text,boolean) to authenticated,service_role;
