-- Patch175A
create table if not exists public.customer_statement_share_rules (
  id bigserial primary key,
  route_key text not null,
  source_no integer not null,
  customer_name text not null default '',
  phone text not null default '',
  phone_display text not null default '',
  content text not null default '',
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(route_key, source_no)
);

grant select, insert, update, delete on table public.customer_statement_share_rules to authenticated;
grant usage, select on sequence public.customer_statement_share_rules_id_seq to authenticated;
grant select on table public.customer_statement_share_rules to service_role;

create or replace function public.lk_name_tokens_match(a text, b text)
returns boolean
language sql
immutable
as $$
  with aa as (
    select nullif(public.normalize_person_name(trim(x)), '') as token
    from regexp_split_to_table(
      regexp_replace(coalesce(a,''), '[?*]+', '/', 'g'),
      E'[/,;|()]+'
    ) as x
  ),
  bb as (
    select nullif(public.normalize_person_name(trim(x)), '') as token
    from regexp_split_to_table(
      regexp_replace(coalesce(b,''), '[?*]+', '/', 'g'),
      E'[/,;|()]+'
    ) as x
  )
  select exists (
    select 1 from aa join bb using(token)
    where aa.token is not null
  );
$$;

create or replace function public.compute_shipment_special_note(
  p_route text,
  p_name text,
  p_phone text
)
returns text
language plpgsql
stable
security definer
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
  v_prepaid boolean := false;
begin
  if public.normalize_phone(p_phone) <> ''
     and public.normalize_person_name(p_name) <> '' then

    select coalesce(r.group_name,''), coalesce(r.discount_percent,0), coalesce(r.notes,'')
    into v_group, v_discount, v_discount_notes
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=v_route_key or r.route_key='all')
      and public.phone_matches(r.phone,p_phone)
      and (
        public.normalize_person_name(r.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(r.company_name,'')<>'' and public.normalize_person_name(r.company_name)=public.normalize_person_name(p_name))
        or public.lk_name_tokens_match(p_name,r.customer_name)
        or (coalesce(r.company_name,'')<>'' and public.lk_name_tokens_match(p_name,r.company_name))
      )
    order by
      case when r.route_key=v_route_key then 0 else 1 end,
      case when public.normalize_person_name(r.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(r.company_name,'')<>'' and public.normalize_person_name(r.company_name)=public.normalize_person_name(p_name))
        then 0 else 1 end,
      r.id
    limit 1;

    select coalesce(d.delivery_type,''), coalesce(d.paid_by,'')
    into v_delivery_type, v_paid_by
    from public.local_delivery_profiles d
    where d.active=true
      and d.route_key=v_route_key
      and public.phone_matches(d.phone,p_phone)
      and (
        public.normalize_person_name(d.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(d.alternate_name,'')<>'' and public.normalize_person_name(d.alternate_name)=public.normalize_person_name(p_name))
        or (coalesce(d.company_name,'')<>'' and public.normalize_person_name(d.company_name)=public.normalize_person_name(p_name))
        or public.lk_name_tokens_match(p_name,d.customer_name)
        or (coalesce(d.alternate_name,'')<>'' and public.lk_name_tokens_match(p_name,d.alternate_name))
        or (coalesce(d.company_name,'')<>'' and public.lk_name_tokens_match(p_name,d.company_name))
      )
    order by
      case when public.normalize_person_name(d.customer_name)=public.normalize_person_name(p_name)
        or (coalesce(d.alternate_name,'')<>'' and public.normalize_person_name(d.alternate_name)=public.normalize_person_name(p_name))
        or (coalesce(d.company_name,'')<>'' and public.normalize_person_name(d.company_name)=public.normalize_person_name(p_name))
        then 0 else 1 end,
      d.preferred desc,
      d.source_no nulls last,
      d.id
    limit 1;

    select coalesce(s.content,'')
    into v_share_text
    from public.customer_statement_share_rules s
    where s.active=true
      and s.route_key=v_route_key
      and public.phone_matches(s.phone,p_phone)
      and (
        public.normalize_person_name(s.customer_name)=public.normalize_person_name(p_name)
        or public.lk_name_tokens_match(p_name,s.customer_name)
      )
    order by
      case when public.normalize_person_name(s.customer_name)=public.normalize_person_name(p_name)
        then 0 else 1 end,
      s.source_no,
      s.id
    limit 1;
  end if;

  v_prepaid :=
    lower(coalesce(v_paid_by,'')) like '%prepaid%'
    or lower(coalesce(v_paid_by,'')) like '%pay in advance%'
    or coalesce(v_paid_by,'') like '%선결제%'
    or coalesce(v_paid_by,'') like '%선결재%';

  if coalesce(v_delivery_type,'') <> '' then
    if coalesce(v_share_text,'') = '' then
      v_share_text := case
        when v_prepaid then '한국 카톡 명세서 선공유 및 온라인 결제'
        else '카톡 명세서 선공유'
      end;
    end if;
    v_delivery_text :=
      case when v_delivery_type='city' then '시내배송' else '지방배송' end
      || case when v_prepaid then '(선결제)' else '' end;
  end if;

  if coalesce(v_discount,0) > 0 then
    v_discount_text :=
      case
        when trim(coalesce(v_group,'')) = '' then '할인'
        when trim(v_group) like '%할인%' then trim(v_group)
        else trim(v_group) || ' 할인'
      end
      || ' '
      || trim(to_char(v_discount*100,'FM999990.##'))
      || '% 적용';
  end if;

  return concat_ws(
    ' / ',
    nullif(trim(v_share_text),''),
    nullif(trim(v_discount_text),''),
    nullif(trim(v_discount_notes),''),
    nullif(trim(v_delivery_text),'')
  );
end
$$;

create or replace function public.admin_refresh_shipment_special_notes_batch(
  p_route text,
  p_year integer,
  p_voyage text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.shipments s
  set special_note_auto=public.compute_shipment_special_note(
    s.route,s.consignee_name,s.consignee_phone
  )
  where s.route=p_route
    and s.shipment_year=p_year
    and s.voyage=p_voyage;
end
$$;

grant execute on function public.admin_refresh_shipment_special_notes_batch(
  text, integer, text
) to authenticated;

create or replace function public.admin_finalize_excel_batch_rules_fast(
  p_route text,
  p_year integer,
  p_voyage text,
  p_resequence boolean default true
)
returns void
language plpgsql
security invoker
set search_path=public
as $$
begin
  perform set_config('lkgroup.bulk_import','1',true);

  perform public.admin_finalize_excel_batch_rules(
    p_route,p_year,p_voyage,p_resequence
  );

  perform public.admin_refresh_shipment_special_notes_batch(
    p_route,p_year,p_voyage
  );

  perform set_config('lkgroup.bulk_import','0',true);
end;
$$;

grant execute on function public.admin_finalize_excel_batch_rules_fast(
  text, integer, text, boolean
) to authenticated;
