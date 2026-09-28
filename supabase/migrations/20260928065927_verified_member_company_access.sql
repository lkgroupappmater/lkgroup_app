-- Company ownership is reviewed in the database and shared by every client.
create table public.member_company_requests (
 id bigint generated always as identity primary key,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 member_name text not null, member_phone text not null, company text not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','revoked','superseded')),
 requested_at timestamptz not null default now(), reviewed_at timestamptz,
 reviewed_by uuid references public.profiles(id) on delete set null
);
create unique index member_company_current_request on public.member_company_requests(profile_id) where status<>'superseded';
alter table public.member_company_requests enable row level security;
revoke all on public.member_company_requests from public,anon,authenticated;
grant select on public.member_company_requests to authenticated;
grant all on public.member_company_requests to service_role;
create policy member_company_read on public.member_company_requests for select to authenticated
 using(profile_id=(select auth.uid()) or (select public.is_admin()));

create function lk_private.company_tokens(p_value text) returns text[]
language sql immutable set search_path='' as $$
 select coalesce(array_agg(distinct token order by token),array[]::text[]) from (
  select lower(regexp_replace(value,'[[:space:]]+','','g')) token
  from regexp_split_to_table(coalesce(p_value,''),E'[/／|;；\n\r]+') value
  union all select lower(regexp_replace(coalesce(p_value,''),'[[:space:]]+','','g'))
 ) t where length(token) between 2 and 200;
$$;
revoke all on function lk_private.company_tokens(text) from public,anon;
grant execute on function lk_private.company_tokens(text) to authenticated,service_role;

create function lk_private.queue_member_company_review() returns trigger
language plpgsql security definer set search_path='' as $$
declare prior public.member_company_requests;
begin
 select * into prior from public.member_company_requests where profile_id=new.id and status<>'superseded';
 if new.role='member' and coalesce(new.deletion_status,'active')='active' and new.deleted_at is null
   and cardinality(lk_private.company_tokens(new.company))>0 then
  if prior.id is not null and prior.member_name=coalesce(new.name,'') and prior.member_phone=coalesce(new.phone,'')
    and prior.company=coalesce(new.company,'') then return new; end if;
  update public.member_company_requests set status='superseded' where profile_id=new.id and status<>'superseded';
  insert into public.member_company_requests(profile_id,member_name,member_phone,company)
   values(new.id,coalesce(new.name,''),coalesce(new.phone,''),new.company);
 else
  update public.member_company_requests set status='superseded' where profile_id=new.id and status<>'superseded';
 end if;
 return new;
end; $$;
revoke all on function lk_private.queue_member_company_review() from public,anon,authenticated;
create trigger review_member_company after insert or update of name,phone,company,role,deletion_status,deleted_at
 on public.profiles for each row execute function lk_private.queue_member_company_review();
insert into public.member_company_requests(profile_id,member_name,member_phone,company)
 select id,coalesce(name,''),coalesce(phone,''),company from public.profiles
 where role='member' and coalesce(deletion_status,'active')='active' and deleted_at is null
 and cardinality(lk_private.company_tokens(company))>0;

create function lk_private.approved_member_company_aliases(p_owner uuid) returns text[]
language sql stable security definer set search_path='' as $$
 select coalesce((select lk_private.company_tokens(p.company)
 from public.profiles p join public.member_company_requests r on r.profile_id=p.id
 where p.id=p_owner and (p_owner=auth.uid() or auth.role()='service_role') and p.role='member' and p.approval_status='approved'
 and coalesce(p.deletion_status,'active')='active' and p.deleted_at is null
 and r.status='approved' and r.company=coalesce(p.company,'')
 and r.member_name=coalesce(p.name,'') and r.member_phone=coalesce(p.phone,'')),array[]::text[]);
$$;
revoke all on function lk_private.approved_member_company_aliases(uuid) from public,anon;
grant execute on function lk_private.approved_member_company_aliases(uuid) to authenticated,service_role;
grant usage on schema lk_private to authenticated,service_role;
create policy shipments_approved_company_read on public.shipments for select to authenticated
 using(deleted_at is null and deletion_requested_at is null and
 lk_private.company_tokens(consignee_name) && (select lk_private.approved_member_company_aliases(auth.uid())));

create function public.my_company_verification() returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce((select to_jsonb(r) from public.member_company_requests r
 where profile_id=auth.uid() and status<>'superseded'),jsonb_build_object('status','none'));
$$;
revoke all on function public.my_company_verification() from public,anon;
grant execute on function public.my_company_verification() to authenticated;

create function public.admin_list_company_verifications(p_status text default 'pending') returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin'
  and approval_status='approved' and coalesce(deletion_status,'active')='active' and deleted_at is null) then
  raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(item order by requested_at,id) from (
 select r.id,r.requested_at,to_jsonb(r)||jsonb_build_object('email',p.email,
  'match_count',(select count(*) from public.shipments s where s.deleted_at is null and s.deletion_requested_at is null
   and lk_private.company_tokens(s.consignee_name)&&lk_private.company_tokens(r.company)),
  'matches',coalesce((select jsonb_agg(to_jsonb(m)) from (
   select s.consignee_name,s.consignee_phone,count(*) cargo_count,
    array_agg(distinct m.customer_code) filter(where m.customer_code is not null) customer_codes
   from public.shipments s left join public.customer_registry_statement_mapping m on m.shipment_id=s.id
   where s.deleted_at is null and s.deletion_requested_at is null and lk_private.company_tokens(s.consignee_name)&&lk_private.company_tokens(r.company)
   group by s.consignee_name,s.consignee_phone order by count(*) desc limit 20
  ) m),'[]'::jsonb)) item
 from public.member_company_requests r join public.profiles p on p.id=r.profile_id
 where r.status<>'superseded' and (p_status='all' or r.status=p_status)
 and p.role='member' and coalesce(p.deletion_status,'active')='active' and p.deleted_at is null
 ) q),'[]'::jsonb);
end; $$;
revoke all on function public.admin_list_company_verifications(text) from public,anon;
grant execute on function public.admin_list_company_verifications(text) to authenticated;

create function public.admin_review_company_verification(p_request_id bigint,p_action text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r public.member_company_requests; p public.profiles; owner_id uuid; next_status text;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin'
  and approval_status='approved' and coalesce(deletion_status,'active')='active' and deleted_at is null) then
  raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select profile_id into owner_id from public.member_company_requests where id=p_request_id;
 select * into p from public.profiles where id=owner_id for update;
 select * into r from public.member_company_requests where id=p_request_id for update;
 if r.id is null or r.status='superseded' or p.role<>'member' or p.deleted_at is not null or coalesce(p.deletion_status,'active')<>'active'
  or r.company<>coalesce(p.company,'') or r.member_name<>coalesce(p.name,'') or r.member_phone<>coalesce(p.phone,'') then
  raise exception 'PROFILE_CHANGED_REFRESH_REQUIRED'; end if;
 next_status:=case p_action when 'approve' then 'approved' when 'reject' then 'rejected' when 'revoke' then 'revoked' end;
 if next_status is null or (p_action='revoke' and r.status<>'approved') then raise exception 'INVALID_ACTION'; end if;
 update public.member_company_requests set status=next_status,reviewed_at=now(),reviewed_by=auth.uid()
  where id=r.id returning * into r;
 return to_jsonb(r);
end; $$;
revoke all on function public.admin_review_company_verification(bigint,text) from public,anon;
grant execute on function public.admin_review_company_verification(bigint,text) to authenticated;

-- Used only by authenticated server functions after resolving the requesting user.
create function public.member_company_shipment_ids(p_owner uuid,p_ids bigint[]) returns bigint[]
language sql stable security invoker set search_path='' as $$
 select coalesce(array_agg(id),array[]::bigint[]) from public.shipments
 where id=any(p_ids) and deleted_at is null and deletion_requested_at is null
 and lk_private.company_tokens(consignee_name)&&lk_private.approved_member_company_aliases(p_owner);
$$;
revoke all on function public.member_company_shipment_ids(uuid,bigint[]) from public,anon,authenticated;
grant execute on function public.member_company_shipment_ids(uuid,bigint[]) to service_role;
CREATE OR REPLACE FUNCTION public.search_shipments_for_current_user(p_route text DEFAULT ''::text, p_year integer DEFAULT NULL::integer, p_voyage text DEFAULT ''::text, p_box_number text DEFAULT ''::text, p_invoice text DEFAULT ''::text, p_recipient text DEFAULT ''::text, p_phone text DEFAULT ''::text)
 RETURNS SETOF shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_company_aliases text[] := lk_private.approved_member_company_aliases(auth.uid());
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
         or lk_private.company_tokens(s.consignee_name) && v_company_aliases
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
            lower(coalesce(s.consignee_name,'')) like '%' || lower(v_recipient) || '%'
            or (lk_private.company_tokens(s.consignee_name) && v_company_aliases and
              (public.normalize_person_name(v_recipient)=public.normalize_person_name(v_profile.name)
               or lk_private.company_tokens(v_recipient) && v_company_aliases)))
       and (v_phone_digits = '' or
            right(public.only_digits(s.consignee_phone), length(v_phone_digits)) = v_phone_digits
            or (lk_private.company_tokens(s.consignee_name) && v_company_aliases and v_phone_digits=public.only_digits(v_profile.phone)))
       and (v_box='' or strpos(lower(coalesce(s.box_number,'')),lower(v_box))>0)
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
$function$;

CREATE OR REPLACE FUNCTION public.statement_rows_for_receipt(p_route text, p_year integer, p_voyage text, p_receipt_number text)
 RETURNS SETOF shipments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  role_name text := public.current_role();
  my_name text;
  my_phone text;
begin
  if role_name = 'partner' then
    raise exception '협력/파트너 계정은 명세서를 조회할 수 없습니다.';
  end if;

  if role_name in ('admin','staff') then
    return query
    select s.*
    from public.shipments s
    where s.route = p_route
      and s.shipment_year = p_year
      and regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g')
          = regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g')
      and btrim(coalesce(s.receipt_number,'')) = btrim(p_receipt_number)
      and s.deletion_requested_at is null
    order by s.box_number, s.id;
    return;
  end if;

  if role_name <> 'member' then
    raise exception '명세서 조회 권한이 없습니다.';
  end if;

  select coalesce(p.name,''), coalesce(p.phone,'')
  into my_name, my_phone
  from public.profiles p
  where p.id = auth.uid();

  return query
  select s.*
  from public.shipments s
  where s.route = p_route
    and s.shipment_year = p_year
    and regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g')
        = regexp_replace(coalesce(p_voyage,''), '[^0-9]', '', 'g')
    and btrim(coalesce(s.receipt_number,'')) = btrim(p_receipt_number)
    and s.deletion_requested_at is null
    and (
      (s.deleted_at is null and lk_private.company_tokens(s.consignee_name) && lk_private.approved_member_company_aliases(auth.uid()))
      or (
        regexp_replace(coalesce(my_phone,''), '[^0-9]', '', 'g') <> ''
        and regexp_replace(coalesce(s.consignee_phone,''), '[^0-9]', '', 'g')
            = regexp_replace(my_phone, '[^0-9]', '', 'g')
      )
      or (
        btrim(my_name) <> ''
        and lower(btrim(coalesce(s.consignee_name,''))) = lower(btrim(my_name))
      )
    )
  order by s.box_number, s.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_registry_search_shipments(p_owner uuid, p_code text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS SETOF shipments
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare p public.profiles; code text; invoice text:=trim(coalesce(p_filters->>'invoice','')); phone text:=public.only_digits(p_filters->>'phone'); box text:=trim(coalesce(p_filters->>'box_number',''));
begin
 select * into p from public.profiles where id=p_owner and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved';
 if p.id is null or p.role not in ('admin','staff','partner','member') then raise exception 'FORBIDDEN'; end if;
 if p_code !~ '^[0-9]{1,9}$' or p_code::bigint<1 then raise exception 'INVALID_CUSTOMER_ID'; end if;
 code:=public.lk_customer_statement_code(p_code::bigint,false);
 if p.role<>'member' and ((invoice<>'' and length(invoice)<4) or (phone<>'' and length(phone)<4)) then return; end if;
 return query select s.* from public.shipments s
 join public.customer_registry_statement_mapping m on m.shipment_id=s.id and m.customer_code=code
 where s.deleted_at is null and s.deletion_requested_at is null
 and (p.role in ('admin','staff','partner') or s.customer_id=p_owner or lk_private.company_tokens(s.consignee_name)&&lk_private.approved_member_company_aliases(p_owner) or (
  coalesce(trim(p.name),'')<>'' and lower(trim(coalesce(s.consignee_name,'')))=lower(trim(p.name))
  and length(public.only_digits(p.phone))>=8 and right(public.only_digits(s.consignee_phone),8)=right(public.only_digits(p.phone),8)
 ))
 and (coalesce(p_filters->>'route','')='' or s.route=p_filters->>'route')
 and (nullif(p_filters->>'year','') is null or s.shipment_year=(p_filters->>'year')::integer)
 and (coalesce(p_filters->>'voyage','')='' or ltrim(coalesce(s.voyage,''),'0')=ltrim(p_filters->>'voyage','0'))
 and (p.role='member' or box='' or lower(coalesce(s.box_number,'')) like '%'||lower(box)||'%')
 and (invoice='' or lower(coalesce(s.invoice_number,'')) like '%'||lower(invoice)||'%')
 and (phone='' or right(public.only_digits(s.consignee_phone),length(phone))=phone or (phone=public.only_digits(p.phone) and lk_private.company_tokens(s.consignee_name)&&lk_private.approved_member_company_aliases(p_owner)))
 order by s.route,s.shipment_year desc,s.voyage desc,s.received_at desc nulls last,s.id desc
 limit case when p.role='member' then 500 else 1000 end;
end; $function$;


-- Return complete authorized shipment rows, including freight inputs and receipts.
-- Old clients also render these as normal results because no masked flag is set.
drop function public.search_shipments_by_registered_company(text,integer,text,text,text,text,text);
create function public.search_shipments_by_registered_company(p_route text default '',p_year integer default null,p_voyage text default '',p_box_number text default '',p_invoice text default '',p_recipient text default '',p_phone text default '')
returns setof public.shipments language sql stable security invoker set search_path='' as $$
 select s.* from public.search_shipments_for_current_user(p_route,p_year,p_voyage,p_box_number,p_invoice,p_recipient,p_phone) s
 where lk_private.company_tokens(s.consignee_name)&&lk_private.approved_member_company_aliases(auth.uid());
$$;
revoke all on function public.search_shipments_by_registered_company(text,integer,text,text,text,text,text) from public,anon;
grant execute on function public.search_shipments_by_registered_company(text,integer,text,text,text,text,text) to authenticated,service_role;
notify pgrst,'reload schema';

