-- Patch169: Park reserved receipt/zone alias fix

-- Patch169 helper: 박성호 대표 호칭 변형까지 동일 인물로 인식.
-- 예: 박성호, 박성호 대표, 박성호대표님
create or replace function public.lk_is_park_seongho(p_name text)
returns boolean
language sql
immutable
as $$
  select
    public.normalize_person_name(coalesce(p_name,'')) like
      public.normalize_person_name('박성호') || '%'
    and public.normalize_person_name(coalesce(p_name,'')) not like
      public.normalize_person_name('박성호') || '%다른사람%'
$$;


-- Patch167C: NOT NULL-safe receipt resequencing
-- Purpose:
--   1) Keep shipments.receipt_number NOT NULL.
--   2) When p_resequence=true, use a unique temporary marker instead of NULL.
--   3) normalize_shipment_batch explicitly ignores those markers, then assigns
--      fresh delivery-priority receipt numbers.
--
-- Safe-update policy:
--   Every UPDATE retains an explicit WHERE clause.
--
-- Patch166C: Excel upload safe-update hotfix (self-contained)
-- Fixes BOTH no-WHERE UPDATE sites used during Excel upload.
-- 1) normalize_shipment_batch temp-table priority UPDATE now has WHERE true.
-- 2) final special_note refresh is limited to the uploaded route/year/voyage.


-- Patch171: phone match remains mandatory; name allows exact full-name or exact split-token match.
create or replace function public.lk_delivery_name_matches(p_profile_name text, p_shipment_name text)
returns boolean
language sql
immutable
as $$
  with atok as (
    select public.normalize_person_name(x) v
    from regexp_split_to_table(coalesce(p_profile_name,''), E'[/,;|()\\]+') x
    where btrim(x)<>''
  ), btok as (
    select public.normalize_person_name(x) v
    from regexp_split_to_table(coalesce(p_shipment_name,''), E'[/,;|()\\]+') x
    where btrim(x)<>''
  )
  select
    public.normalize_person_name(coalesce(p_profile_name,''))<>'' and
    public.normalize_person_name(coalesce(p_shipment_name,''))<>'' and (
      public.normalize_person_name(p_profile_name)=public.normalize_person_name(p_shipment_name)
      or exists(select 1 from atok join btok using(v) where v<>'')
    );
$$;

create or replace function public.normalize_shipment_batch(
  p_route text,
  p_year integer,
  p_voyage text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_route_key text;
  v_prefix text;
  v_voyage text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_next integer;
  r record;
  v_receipt text;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or coalesce(v_voyage,'')='' then
    return;
  end if;
  if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
  perform set_config('lkgroup.normalizing_shipments','1',true);

  select rd.route_key,rd.receipt_prefix
    into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(btrim(v_prefix),'')='' then
    perform set_config('lkgroup.normalizing_shipments','',true);
    return;
  end if;

  drop table if exists pg_temp._ng;
  drop table if exists pg_temp._nr;
  drop table if exists pg_temp._nq;

  create temporary table _ng on commit drop as
  with b as (
    select
      s.id,s.data_locked,s.receipt_number,
      s.consignee_name,s.consignee_phone,
      greatest(coalesce(s.quantity,1),1)::integer qty,
      lower(regexp_replace(btrim(coalesce(s.consignee_name,'')),'\s+',' ','g')) name_key,
      regexp_replace(coalesce(s.consignee_phone,''),'[^0-9]','','g') digits,
      public.lk_recipient_name_uncertain(s.consignee_name) name_bad,
      public.lk_recipient_phone_uncertain(s.consignee_phone) phone_bad,
      public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone) is_unknown
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  ), p as (
    select *,case when not phone_bad and length(digits)>=7 then right(digits,8) else '' end phone_key
    from b
  ), st as (
    select name_key,count(distinct nullif(phone_key,'')) phone_count,min(nullif(phone_key,'')) only_phone
    from p where not is_unknown and not name_bad group by name_key
  )
  select p.*,
    case
      when is_unknown then '__UNKNOWN__:'||id::text
      when not phone_bad and phone_key<>'' then
        case when name_bad then 'PHONE|'||phone_key else 'NAMEPHONE|'||name_key||'|'||phone_key end
      when not name_bad and coalesce(st.phone_count,0)=1 then 'NAMEPHONE|'||name_key||'|'||st.only_phone
      when not name_bad then 'NAME|'||name_key
      else '__UNKNOWN__:'||id::text
    end identity_key,
    2::integer receipt_priority
  from p left join st using(name_key);

  update _ng g
  set receipt_priority=case
    when public.lk_is_park_seongho(g.consignee_name) then 8
    else coalesce((
      select case when d.delivery_type='province' then 0 else 1 end
      from public.local_delivery_profiles d
      where d.active=true and d.route_key=v_route_key
        and public.phone_matches(d.phone,g.consignee_phone)
        and (
          public.lk_delivery_name_matches(d.customer_name,g.consignee_name)
          or (coalesce(d.alternate_name,'')<>'' and public.lk_delivery_name_matches(d.alternate_name,g.consignee_name))
          or (coalesce(d.company_name,'')<>'' and public.lk_delivery_name_matches(d.company_name,g.consignee_name))
        )
      order by d.preferred desc,d.source_no nulls last,d.id
      limit 1
    ),2)
  end
  where true;

  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case when v_route_key in ('kr_la_sea','kr_la_air') then btrim(v_prefix)||' XX' else btrim(v_prefix)||'XX' end,
      unloading_zone='F'
  from _ng g
  where s.id=g.id and g.is_unknown and not coalesce(g.data_locked,false);

  update public.shipments s
  set recipient_unknown=false
  from _ng g
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false);

  -- Park Seongho representative is the reserved 100 receipt for every route prefix.
  update public.shipments s
  set receipt_number=case when v_route_key in ('kr_la_sea','kr_la_air') then btrim(v_prefix)||' 100' else btrim(v_prefix)||'100' end
  from _ng g
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false)
    and public.lk_is_park_seongho(g.consignee_name);

  create temporary table _nr(identity_key text primary key,receipt_number text) on commit drop;

  insert into _nr(identity_key,receipt_number)
  select identity_key,min(btrim(receipt_number))
  from _ng
  where not is_unknown
    and coalesce(data_locked,false)
    and coalesce(btrim(receipt_number),'')<>''
    and btrim(receipt_number) not like '__LK_RESEQ__%'
  group by identity_key on conflict(identity_key) do nothing;

  insert into _nr(identity_key,receipt_number)
  select g.identity_key,min(btrim(s.receipt_number))
  from _ng g
  join public.shipments s on s.id=g.id
  join (
    select btrim(s2.receipt_number) receipt,count(distinct g2.identity_key) n
    from _ng g2 join public.shipments s2 on s2.id=g2.id
    where not g2.is_unknown
      and coalesce(btrim(s2.receipt_number),'')<>''
      and btrim(s2.receipt_number) not like '__LK_RESEQ__%'
    group by btrim(s2.receipt_number)
    having count(distinct g2.identity_key)=1
  ) u on u.receipt=btrim(s.receipt_number)
  where not g.is_unknown and not coalesce(g.data_locked,false)
    and not exists(select 1 from _nr x where x.identity_key=g.identity_key)
  group by g.identity_key
  on conflict(identity_key) do nothing;

  v_next:=1;
  for r in
    select identity_key,min(receipt_priority) priority,min(name_key) sort_name,min(id) first_id
    from _ng g
    where not is_unknown
      and not exists(select 1 from _nr x where x.identity_key=g.identity_key)
    group by identity_key
    order by min(receipt_priority),min(name_key),min(id)
  loop
    loop
      if v_next=100 then v_next:=101; end if;
      if v_route_key in ('kr_la_sea','kr_la_air') then
        v_receipt:=btrim(v_prefix)||' '||lpad(v_next::text,2,'0');
      else
        v_receipt:=btrim(v_prefix)||lpad(v_next::text,2,'0');
      end if;
      v_next:=v_next+1;
      exit when not exists(
        select 1 from public.shipments s
        where s.route=p_route and s.shipment_year=p_year
          and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
          and s.deletion_requested_at is null and btrim(coalesce(s.receipt_number,''))=v_receipt
      ) and not exists(select 1 from _nr n where btrim(coalesce(n.receipt_number,''))=v_receipt);
    end loop;
    insert into _nr(identity_key,receipt_number) values(r.identity_key,v_receipt);
  end loop;

  update public.shipments s
  set receipt_number=n.receipt_number
  from _ng g join _nr n using(identity_key)
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false);

  create temporary table _nq on commit drop as
  select btrim(s.receipt_number) receipt,sum(g.qty)::integer total_qty
  from _ng g join public.shipments s on s.id=g.id
  where not g.is_unknown and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  update public.shipments s
  set unloading_zone=case
    -- Patch169: 박성호 대표는 호칭 표기와 무관하게 항상 고정 Zone 102.
    when public.lk_is_park_seongho(g.consignee_name) then '102'
    -- BASE Excel fixed classification is the highest priority.
    when exists(
      select 1 from public.customer_zone_overrides z
      where z.active=true and (z.route_key=v_route_key or z.route_key='all') and z.zone='102'
        and public.normalize_person_name(z.customer_name)=public.normalize_person_name(g.consignee_name)
    ) then '102'
    -- Kim Yosep / Beauty Panda and every city/province delivery are forced to F.
    when public.normalize_person_name(g.consignee_name) like '%'||public.normalize_person_name('김요셉')||'%'
      or lower(coalesce(g.consignee_name,'')) like '%beauty panda%'
      or coalesce(g.consignee_name,'') like '%뷰티판다%'
      or exists(
        select 1 from public.local_delivery_profiles d
        where d.active=true and d.route_key=v_route_key
          and public.phone_matches(d.phone,g.consignee_phone)
          and (
            public.lk_delivery_name_matches(d.customer_name,g.consignee_name)
            or (coalesce(d.alternate_name,'')<>'' and public.lk_delivery_name_matches(d.alternate_name,g.consignee_name))
            or (coalesce(d.company_name,'')<>'' and public.lk_delivery_name_matches(d.company_name,g.consignee_name))
          )
      ) then 'F'
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from _ng g,_nq q
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
  perform set_config('lkgroup.normalizing_shipments','',true);
  raise;
end
$$;

revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated,service_role;

create or replace function public.admin_finalize_excel_batch_rules(
  p_route text,
  p_year integer,
  p_voyage text,
  p_resequence boolean default false
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_route_key text;
  v_prefix text;
  v_voyage text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
begin
  select rd.route_key,rd.receipt_prefix into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end limit 1;

  if coalesce(v_route_key,'')='' then return; end if;

  if coalesce(p_resequence,false) then
    perform set_config('lkgroup.normalizing_shipments','1',true);
    update public.shipments s
    set receipt_number='__LK_RESEQ__'||s.id::text
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null and not coalesce(s.data_locked,false)
      and not public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone)
      and not public.lk_is_park_seongho(s.consignee_name);

    update public.shipments s
    set receipt_number=case when v_route_key in ('kr_la_sea','kr_la_air') then btrim(v_prefix)||' 100' else btrim(v_prefix)||'100' end
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null and not coalesce(s.data_locked,false)
      and public.lk_is_park_seongho(s.consignee_name);
    perform set_config('lkgroup.normalizing_shipments','',true);
  end if;

  perform public.normalize_shipment_batch(p_route,p_year,p_voyage);

  -- IMPORTANT: do not call the global admin_refresh_shipment_special_notes() here.
  -- Supabase safe-update rejects its full-table UPDATE. Refresh only this batch.
  update public.shipments s
  set special_note_auto=public.compute_shipment_special_note(
        s.route,
        s.consignee_name,
        s.consignee_phone
      )
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;

exception when others then
  perform set_config('lkgroup.normalizing_shipments','',true);
  raise;
end
$$;

revoke all on function public.admin_finalize_excel_batch_rules(text,integer,text,boolean) from public;
grant execute on function public.admin_finalize_excel_batch_rules(text,integer,text,boolean) to authenticated,service_role;
