-- Read-only ID search. Apply the ID before the existing per-role row limit.
-- Only the verified Edge Function may supply p_owner; no authenticated RPC grant.
create function public.customer_registry_search_shipments(p_owner uuid,p_code text,p_filters jsonb default '{}'::jsonb)
returns setof public.shipments language plpgsql stable security invoker set search_path='' as $$
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
 and (p.role in ('admin','staff','partner') or s.customer_id=p_owner or (
  coalesce(trim(p.name),'')<>'' and lower(trim(coalesce(s.consignee_name,'')))=lower(trim(p.name))
  and length(public.only_digits(p.phone))>=8 and right(public.only_digits(s.consignee_phone),8)=right(public.only_digits(p.phone),8)
 ))
 and (coalesce(p_filters->>'route','')='' or s.route=p_filters->>'route')
 and (nullif(p_filters->>'year','') is null or s.shipment_year=(p_filters->>'year')::integer)
 and (coalesce(p_filters->>'voyage','')='' or ltrim(coalesce(s.voyage,''),'0')=ltrim(p_filters->>'voyage','0'))
 and (p.role='member' or box='' or lower(coalesce(s.box_number,'')) like '%'||lower(box)||'%')
 and (invoice='' or lower(coalesce(s.invoice_number,'')) like '%'||lower(invoice)||'%')
 and (phone='' or right(public.only_digits(s.consignee_phone),length(phone))=phone)
 order by s.route,s.shipment_year desc,s.voyage desc,s.received_at desc nulls last,s.id desc
 limit case when p.role='member' then 500 else 1000 end;
end $$;
revoke all on function public.customer_registry_search_shipments(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.customer_registry_search_shipments(uuid,text,jsonb) to service_role;
