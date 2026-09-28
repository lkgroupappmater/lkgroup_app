-- Offline numbers are provisional, never reservations or customer mappings.
create or replace function public.lk_excel_identity_context(p_route_key text) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object(
 'unused_customer_numbers',(select coalesce(jsonb_agg(n order by n),'[]') from (select n from generate_series(3,9999) n where not exists(select 1 from public.customer_registry r where r.customer_no=n) order by n limit 1000) available),
 'customers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'customer_no',customer_no,'name',name,'phone',phone,'name_key',name_key,'phone_key',phone_key) order by customer_no),'[]') from public.customer_registry where merged_into is null and name !~ '수취인[[:space:]]*불명'),
 'sources',(select coalesce(jsonb_agg(jsonb_build_object('customer_no',m.customer_no,'source_name',m.source_name,'source_phone',m.source_phone)),'[]') from public.customer_registry_statement_mapping m join public.route_definitions rd on rd.display_name=m.route where rd.route_key=p_route_key and m.customer_no is not null),
 'aliases',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.customer_registry_aliases a join public.customer_registry r on r.id=a.customer_registry_id where r.merged_into is null and r.name !~ '수취인[[:space:]]*불명'),
 'deliveries',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('fingerprint',public.lk_delivery_match_fingerprint(d)) order by source_row,id),'[]') from public.local_delivery_profiles d where active and route_key=p_route_key),
 'reviews',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from public.excel_delivery_match_reviews r where route_key=p_route_key));
$$;
revoke all on function public.lk_excel_identity_context(text) from public,anon,authenticated;
grant execute on function public.lk_excel_identity_context(text) to service_role;

-- Register the validated customer name after removing an explicit statement prefix.
create or replace function public.admin_register_excel_customers(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item jsonb; n text; p text; target uuid; created integer:=0;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and deleted_at is null and coalesce(deletion_status,'active')='active' and coalesce(approval_status,'approved')='approved') then raise exception 'FORBIDDEN'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>5000 then raise exception 'INVALID_CUSTOMERS'; end if;
 perform pg_advisory_xact_lock(7092601);
 for item in select value from jsonb_array_elements(p_rows) loop
  n:=public.lk_customer_base_name(item->>'name');p:=coalesce(item->>'phone','');
  if n is null or length(n)>200 or length(p)>200 then continue; end if;
  target:=public.customer_registry_match(n,p,false);
  if target is null then
   insert into public.customer_registry(name,phone) values(n,p) returning id into target;
   insert into public.customer_registry_aliases values(public.lk_registry_name(n),public.lk_registry_phone(p),target,now()) on conflict do nothing;
   created:=created+1;
  end if;
 end loop;
 return jsonb_build_object('created',created);
end $$;
revoke all on function public.admin_register_excel_customers(jsonb) from public,anon;
grant execute on function public.admin_register_excel_customers(jsonb) to authenticated;

-- Older clients also must not request an offline number as a final bill edit.
CREATE OR REPLACE FUNCTION public.lk_excel_import_changes(p_item jsonb, p_existing shipments)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_changes jsonb:='{}'::jsonb;
  v_text text;
  v_number numeric;
  v_quantity integer;
  v_date date;
begin
  if jsonb_typeof(p_item)<>'object' then
    raise exception '화물 데이터 행 형식이 올바르지 않습니다.';
  end if;

  if p_item?'invoice_number' then
    v_text:=btrim(coalesce(p_item->>'invoice_number',''));
    if v_text is distinct from btrim(coalesce(p_existing.invoice_number,'')) then
      v_changes:=v_changes||jsonb_build_object('invoice_number',v_text);
    end if;
  end if;
  if p_item?'sender_name' then
    v_text:=btrim(coalesce(p_item->>'sender_name',''));
    if v_text is distinct from btrim(coalesce(p_existing.sender_name,'')) then
      v_changes:=v_changes||jsonb_build_object('sender_name',v_text);
    end if;
  end if;
  if p_item?'consignee_name' then
    v_text:=btrim(coalesce(p_item->>'consignee_name',''));
    if v_text is distinct from btrim(coalesce(p_existing.consignee_name,'')) then
      v_changes:=v_changes||jsonb_build_object('consignee_name',v_text);
    end if;
  end if;
  if p_item?'consignee_phone' then
    v_text:=btrim(coalesce(p_item->>'consignee_phone',''));
    if v_text is distinct from btrim(coalesce(p_existing.consignee_phone,'')) then
      v_changes:=v_changes||jsonb_build_object('consignee_phone',v_text);
    end if;
  end if;
  if p_item?'contents' then
    v_text:=btrim(coalesce(p_item->>'contents',''));
    if v_text is distinct from btrim(coalesce(p_existing.contents,'')) then
      v_changes:=v_changes||jsonb_build_object('contents',v_text);
    end if;
  end if;
  if p_item?'package_type' then
    v_text:=btrim(coalesce(p_item->>'package_type',''));
    if v_text is distinct from btrim(coalesce(p_existing.package_type,'')) then
      v_changes:=v_changes||jsonb_build_object('package_type',v_text);
    end if;
  end if;
  if p_item?'quantity' then
    v_quantity:=coalesce(nullif(replace(p_item->>'quantity',',',''),'')::integer,1);
    if v_quantity is distinct from coalesce(p_existing.quantity,1) then
      v_changes:=v_changes||jsonb_build_object('quantity',v_quantity);
    end if;
  end if;
  if p_item?'weight_kg' then
    v_number:=nullif(replace(p_item->>'weight_kg',',',''),'')::numeric;
    if v_number is distinct from p_existing.weight_kg then
      v_changes:=v_changes||jsonb_build_object('weight_kg',v_number);
    end if;
  end if;
  if p_item?'length_cm' then
    v_number:=nullif(replace(p_item->>'length_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.length_cm then
      v_changes:=v_changes||jsonb_build_object('length_cm',v_number);
    end if;
  end if;
  if p_item?'width_cm' then
    v_number:=nullif(replace(p_item->>'width_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.width_cm then
      v_changes:=v_changes||jsonb_build_object('width_cm',v_number);
    end if;
  end if;
  if p_item?'height_cm' then
    v_number:=nullif(replace(p_item->>'height_cm',',',''),'')::numeric;
    if v_number is distinct from p_existing.height_cm then
      v_changes:=v_changes||jsonb_build_object('height_cm',v_number);
    end if;
  end if;
  if p_item?'receipt_number' and coalesce(p_item->>'receipt_number','') !~ '^[A-Z]+[[:space:]]+[0-9]{4,5}[[:space:]]+\(임시\)$' then
    v_text:=btrim(coalesce(p_item->>'receipt_number',''));
    if v_text is distinct from btrim(coalesce(p_existing.receipt_number,'')) then
      v_changes:=v_changes||jsonb_build_object('receipt_number',v_text);
    end if;
  end if;
  if p_item?'unloading_zone' then
    v_text:=case when public.lk_unknown_prefix_zone(case when p_item?'consignee_name' then p_item->>'consignee_name' else p_existing.consignee_name end) then 'F' else btrim(coalesce(p_item->>'unloading_zone','')) end;
    if v_text is distinct from btrim(coalesce(p_existing.unloading_zone,'')) then
      v_changes:=v_changes||jsonb_build_object('unloading_zone',v_text);
    end if;
  end if;
  if p_item?'notes' then
    v_text:=btrim(coalesce(p_item->>'notes',''));
    if v_text is distinct from btrim(coalesce(p_existing.notes,'')) then
      v_changes:=v_changes||jsonb_build_object('notes',v_text);
    end if;
  end if;
  if p_item?'received_at' then
    v_date:=nullif(p_item->>'received_at','')::date;
    if v_date is distinct from p_existing.received_at then
      v_changes:=v_changes||jsonb_build_object('received_at',v_date);
    end if;
  end if;

  if p_item?'box_number' and btrim(coalesce(p_item->>'box_number','')) is distinct from btrim(coalesce(p_existing.box_number,'')) then
    v_changes:=v_changes||jsonb_build_object('box_number',btrim(p_item->>'box_number'));
  end if;
  if p_item->>'_excel_action'='삭제함 이동' and p_existing.deletion_requested_at is null then
    v_changes:=v_changes||jsonb_build_object('_excel_action','삭제함 이동');
  elsif p_item->>'_excel_action'='복원' and p_existing.deletion_requested_at is not null then
    v_changes:=v_changes||jsonb_build_object('_excel_action','복원');
  end if;
  return v_changes;
end;
$function$;

create or replace function lk_private.discard_provisional_statement_number() returns trigger
language plpgsql set search_path='' as $$
begin
 if coalesce(new.receipt_number,'') ~ '^[A-Z]+[[:space:]]+[0-9]{4,5}[[:space:]]+\(임시\)$' then
  new.receipt_number:=case when tg_op='UPDATE' then old.receipt_number else '' end;
 end if;
 if coalesce(new.receipt_number_override,'') ~ '^[A-Z]+[[:space:]]+[0-9]{4,5}[[:space:]]+\(임시\)$' then
  new.receipt_number_override:=case when tg_op='UPDATE' then old.receipt_number_override else null end;
 end if;
 return new;
end $$;
revoke all on function lk_private.discard_provisional_statement_number() from public,anon,authenticated;
create trigger discard_provisional_statement_number before insert or update of receipt_number,receipt_number_override
 on public.shipments for each row execute function lk_private.discard_provisional_statement_number();
