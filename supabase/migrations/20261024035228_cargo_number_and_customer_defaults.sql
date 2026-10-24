-- Keep existing access checks; split-box suffixes do not advance the parent counter.
CREATE OR REPLACE FUNCTION public.admin_next_box_number(p_route text, p_year integer, p_voyage text, p_prefix text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_next integer;
  v_voyage text := lpad(nullif(regexp_replace(coalesce(p_voyage, ''), '[^0-9]', '', 'g'), ''), 2, '0');
begin
  if auth.uid() is null or not exists (select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') or coalesce(public.current_role(), '') <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;
  if trim(coalesce(p_prefix, '')) = '' then
    raise exception '박스번호 접두어가 필요합니다.';
  end if;

  select coalesce(max(
    nullif(substring(substring(s.box_number from length(p_prefix) + 1) from '^[0-9]+'), '')::integer
  ), 0) + 1
    into v_next
    from public.shipments s
   where s.route = p_route
     and s.shipment_year = p_year
     and lpad(regexp_replace(coalesce(s.voyage, ''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
     and s.box_number like p_prefix || '%';

  return p_prefix || lpad(v_next::text, greatest(3,length(v_next::text)), '0');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.manager_next_box_number(p_route text, p_year integer, p_voyage text, p_prefix text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g'), 2, '0');
  v_max integer := 0;
begin
  if auth.uid() is null or not exists (select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') or coalesce(public.current_role(), '') not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  select coalesce(max(
    nullif(
      substring(substring(s.box_number from char_length(p_prefix) + 1) from '^[0-9]+'),
      ''
    )::integer
  ), 0)
  into v_max
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0') = v_voyage
    and s.box_number like p_prefix || '%';

  return p_prefix || lpad((v_max + 1)::text, greatest(3,length((v_max + 1)::text)), '0');
end;
$function$
;

-- Same-voyage defaults require the complete name and a full normalized phone.
create or replace function public.manager_shipment_customer_defaults(
  p_route text, p_year integer, p_voyage text, p_name text, p_phone text
) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_values jsonb; v_count integer; v_variants integer;
begin
  if auth.uid() is null or coalesce(public.current_role(),'') not in ('admin','staff','partner')
    or not exists(select 1 from public.profiles where id=auth.uid() and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active')
  then raise exception 'not authorized'; end if;
  if btrim(coalesce(p_name,''))='' or cardinality(public.lk_delivery_phone_tokens(p_phone))=0 then
    return jsonb_build_object('status','incomplete');
  end if;
  with matches as (
    select jsonb_build_object('unloading_zone',coalesce(s.unloading_zone,''),
      'notes',coalesce(nullif(s.notes,''),s.special_note_auto,'')) value
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0')
      and s.deleted_at is null and s.deletion_requested_at is null
      and lower(regexp_replace(coalesce(s.consignee_name,''),'[[:space:]]','','g'))=lower(regexp_replace(p_name,'[[:space:]]','','g'))
      and public.lk_delivery_phone_tokens(s.consignee_phone) && public.lk_delivery_phone_tokens(p_phone)
  ) select count(*),count(distinct value),(jsonb_agg(value)->0) into v_count,v_variants,v_values from matches;
  if v_count=0 then return jsonb_build_object('status','no_match'); end if;
  if v_variants<>1 then return jsonb_build_object('status','ambiguous','matched_count',v_count); end if;
  return jsonb_build_object('status','matched','matched_count',v_count,'values',v_values);
end $$;
revoke all on function public.manager_shipment_customer_defaults(text,integer,text,text,text) from public,anon;
grant execute on function public.manager_shipment_customer_defaults(text,integer,text,text,text) to authenticated;

-- Preserve the existing manager creation authorization; serialize numbering in this voyage.
create or replace function public.manager_create_shipment(
  p_route text,p_year integer,p_voyage text,p_box_number text default null,
  p_invoice_number text default '',p_consignee_name text default '',p_consignee_phone text default '',
  p_notes text default '',p_unloading_zone text default '',p_quantity integer default 1,
  p_received_at timestamptz default null,p_weight_kg numeric default null,p_length_cm numeric default null,
  p_width_cm numeric default null,p_height_cm numeric default null
) returns public.shipments language plpgsql security definer set search_path=public,pg_temp as $$
declare v_prefix text; v_box text; v_voyage text; v_created jsonb; v_row public.shipments%rowtype; attempt integer;
begin
  if auth.uid() is null or coalesce(public.current_role(),'') not in ('admin','staff','partner')
    or not exists(select 1 from public.profiles where id=auth.uid() and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active')
  then raise exception 'not authorized'; end if;
  if p_year is null or p_year not between 1000 and 9999 or coalesce(p_voyage,'') !~ '^[0-9]{1,2}$' or p_voyage::integer=0 then
    raise exception 'invalid route/year/voyage'; end if;
  if num_nonnulls(p_weight_kg,p_length_cm,p_width_cm,p_height_cm) not in (0,4)
    or p_weight_kg<0 or p_length_cm<0 or p_width_cm<0 or p_height_cm<0 then raise exception 'invalid measurements'; end if;
  if p_box_number is not null and (btrim(p_box_number)='' or length(p_box_number)>80 or p_box_number ~ '[[:cntrl:]]') then
    raise exception 'box number required'; end if;
  select nullif(btrim(box_prefix),'') into v_prefix from public.route_definitions
    where display_name=p_route and deleted_at is null and status<>'deleted' limit 1;
  if v_prefix is null then raise exception 'invalid route'; end if;
  v_voyage:=lpad(p_voyage,2,'0');
  perform pg_advisory_xact_lock(hashtextextended(p_route||'|'||p_year::text||'|'||v_voyage,0));
  for attempt in 1..3 loop
    v_box:=case when p_box_number is null then public.manager_next_box_number(p_route,p_year,v_voyage,v_prefix) else btrim(p_box_number) end;
    begin
      v_created:=public.manager_add_manual_shipment(p_route=>p_route,p_year=>p_year,p_voyage=>v_voyage,
        p_box_number=>v_box,p_invoice_number=>p_invoice_number,p_consignee_name=>p_consignee_name,
        p_consignee_phone=>p_consignee_phone,p_received_at=>coalesce(p_received_at,now()),p_notes=>p_notes,
        p_quantity=>p_quantity,p_weight_kg=>p_weight_kg,p_length_cm=>p_length_cm,p_width_cm=>p_width_cm,p_height_cm=>p_height_cm);
      update public.shipments set unloading_zone=btrim(coalesce(p_unloading_zone,'')),
        unloading_zone_override=nullif(btrim(p_unloading_zone),''),updated_at=now()
        where id=(v_created->>'id')::bigint returning * into v_row;
      return v_row;
    exception when unique_violation then if p_box_number is not null then raise exception 'duplicate box number'; end if;
      when raise_exception then if p_box_number is not null or sqlerrm<>'duplicate box number' then raise; end if;
    end;
  end loop;
  raise exception 'box number changed; retry';
end $$;
revoke all on function public.manager_create_shipment(text,integer,text,text,text,text,text,text,text,integer,timestamptz,numeric,numeric,numeric,numeric) from public,anon;
grant execute on function public.manager_create_shipment(text,integer,text,text,text,text,text,text,text,integer,timestamptz,numeric,numeric,numeric,numeric) to authenticated;
