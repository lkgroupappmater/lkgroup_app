-- Registered company names are discovery aliases, not proof of cargo ownership.
-- Keep the existing full-record RPC/RLS unchanged and return a fixed masked shape.
create function public.search_shipments_by_registered_company(
  p_route text default '', p_year integer default null, p_voyage text default '',
  p_box_number text default '', p_invoice text default '',
  p_recipient text default '', p_phone text default ''
)
returns table(
  id bigint, route text, shipment_year integer, voyage text, box_number text,
  invoice_number text, consignee_name text, consignee_phone text,
  quantity integer, weight_kg numeric, length_cm numeric, width_cm numeric,
  height_cm numeric, received_at date, status text, recipient_unknown boolean,
  company_match boolean
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_aliases text[];
  v_recipient text := lower(regexp_replace(coalesce(p_recipient,''),'[[:space:]]+','','g'));
  v_phone text := public.only_digits(p_phone);
  v_invoice text := lower(btrim(coalesce(p_invoice,'')));
begin
  if auth.uid() is null then return; end if;
  select * into v_profile from public.profiles where profiles.id=auth.uid();
  if not found or v_profile.role <> 'member'
    or coalesce(v_profile.approval_status,'') <> 'approved'
    or coalesce(v_profile.deletion_status,'active') <> 'active' then return; end if;

  select array_agg(distinct alias) into v_aliases from (
    select lower(regexp_replace(value,'[[:space:]]+','','g')) as alias
    from regexp_split_to_table(coalesce(v_profile.company,''), E'[/／|;；\\n\\r]+') as value
    union all
    select lower(regexp_replace(coalesce(v_profile.company,''),'[[:space:]]+','','g'))
  ) names where length(alias) between 2 and 200;
  if coalesce(cardinality(v_aliases),0)=0 then return; end if;
  if v_invoice<>'' and length(regexp_replace(v_invoice,'[^a-z0-9]','','g'))<4 then return; end if;
  if v_phone<>'' and length(v_phone)<4 then return; end if;

  return query
  select s.id,s.route,s.shipment_year,s.voyage,s.box_number,
    case when coalesce(s.invoice_number,'')='' then '' else
      '••••'||right(regexp_replace(lower(s.invoice_number),'[^a-z0-9]','','g'),4) end,
    public.lk_mask_recipient_name(s.consignee_name),
    public.lk_mask_recipient_phone(s.consignee_phone),
    s.quantity,s.weight_kg,s.length_cm,s.width_cm,s.height_cm,s.received_at,
    s.status,s.recipient_unknown,true
  from public.shipments s
  where s.deleted_at is null and s.deletion_requested_at is null
    and (coalesce(p_route,'')='' or s.route=p_route)
    and (p_year is null or s.shipment_year=p_year)
    and (coalesce(p_voyage,'')='' or ltrim(coalesce(s.voyage,''),'0')=ltrim(p_voyage,'0'))
    and (coalesce(p_box_number,'')='' or strpos(lower(coalesce(s.box_number,'')),lower(btrim(p_box_number)))>0)
    and exists (
      select 1 from regexp_split_to_table(coalesce(s.consignee_name,''), E'[/／|;；\\n\\r]+') as value
      where lower(regexp_replace(value,'[[:space:]]+','','g'))=any(v_aliases)
    )
    -- Initial profile name/phone must not hide a company's office-address cargo.
    and (v_recipient='' or v_recipient=lower(regexp_replace(coalesce(v_profile.name,''),'[[:space:]]+','','g'))
      or v_recipient=any(v_aliases)
      or strpos(lower(regexp_replace(coalesce(s.consignee_name,''),'[[:space:]]+','','g')),v_recipient)>0)
    and (v_phone='' or v_phone=public.only_digits(v_profile.phone)
      or right(public.only_digits(s.consignee_phone),length(v_phone))=v_phone)
    and (v_invoice='' or strpos(lower(coalesce(s.invoice_number,'')),v_invoice)>0)
  order by s.route,s.shipment_year desc,s.voyage desc,s.received_at desc nulls last,s.id desc
  limit 500;
end;
$$;
revoke all on function public.search_shipments_by_registered_company(text,integer,text,text,text,text,text) from public,anon;
grant execute on function public.search_shipments_by_registered_company(text,integer,text,text,text,text,text) to authenticated,service_role;
