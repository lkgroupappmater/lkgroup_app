-- Zone is a physical location, independent of recovered customer identity.
create or replace function public.lk_unknown_prefix_zone(p_name text)
returns boolean language sql immutable set search_path=public
as $$ select regexp_replace(coalesce(p_name,''),'[[:space:]　]','','g') ~ '^수취인불명([/／]|$)' $$;


CREATE OR REPLACE FUNCTION public.capture_shipment_zone_override()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if public.lk_unknown_prefix_zone(new.consignee_name) then
    new.unloading_zone := 'F';
    return new;
  end if;
  if current_setting('lkgroup.normalizing_shipments',true)='1'
     or current_setting('lkgroup.calculating_zone',true)='1' then
    if tg_op='UPDATE' then
      new.unloading_zone := coalesce(nullif(btrim(old.unloading_zone_override),''),
        case when btrim(old.unloading_zone) not in ('','A','B','C','F','102')
          then btrim(old.unloading_zone) end, new.unloading_zone);
    end if;
    return new;
  end if;

  new.unloading_zone := btrim(coalesce(new.unloading_zone,''));
  if tg_op='INSERT' then
    -- Excel clients send cached A/B/C/F/102 defaults. Keep those automatic.
    -- New custom locations have no built-in formula and are always explicit.
    if new.unloading_zone not in ('','A','B','C','F','102') then
      new.unloading_zone_override := new.unloading_zone;
    end if;
  elsif new.unloading_zone is distinct from btrim(old.unloading_zone) then
    new.unloading_zone_override := nullif(new.unloading_zone,'');
  end if;
  return new;
end $function$;



drop trigger shipments_capture_zone_override on public.shipments;
create trigger shipments_capture_zone_override before insert or update of unloading_zone,consignee_name,unloading_zone_override on public.shipments for each row execute function public.capture_shipment_zone_override();

CREATE OR REPLACE FUNCTION public.normalize_shipment_batch_fast_impl(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
  declare
  v_route_key text;
  v_prefix text;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_xx text;
  v_start integer;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or v_voyage='' then
    perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return;
  end if;

  select rd.route_key, coalesce(btrim(rd.receipt_prefix),'')
    into v_route_key, v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(v_route_key,'')='' then
    if p_route in ('한국->라오스 해상','한국→라오스 해상') then
      v_route_key:='kr_la_sea'; v_prefix:='LKS';
    elsif p_route in ('한국->라오스 항공','한국→라오스 항공') then
      v_route_key:='kr_la_air'; v_prefix:='LKA';
    end if;
  end if;

  v_xx := case
    when coalesce(v_prefix,'')='' then 'XX'
    when v_route_key in ('kr_la_sea','kr_la_air') then v_prefix||' XX'
    else v_prefix||'XX'
  end;

  create temporary table if not exists _norm_batch (
    id bigint primary key,
    customer_key text not null,
    is_unknown boolean not null,
    old_receipt text,
    qty integer not null
  ) on commit drop;
  truncate _norm_batch;

  insert into _norm_batch(id,customer_key,is_unknown,old_receipt,qty)
  select
    s.id,
    lower(btrim(coalesce(s.consignee_name,''))) || '|' ||
      regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g'),
    public.shipment_name_is_explicit_unknown(s.consignee_name),
    btrim(coalesce(s.receipt_number,'')),
    greatest(coalesce(s.quantity,1),1)
  from public.shipments s
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.deletion_requested_at is null;

  if not exists(select 1 from _norm_batch) then
    perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return;
  end if;

  create index if not exists _norm_batch_customer_idx on _norm_batch(customer_key);
  create index if not exists _norm_batch_receipt_idx on _norm_batch(old_receipt);

  update public.shipments s
     set recipient_unknown=b.is_unknown,
         receipt_number=case
           when b.is_unknown then v_xx
           when b.old_receipt=v_xx then ''
           else b.old_receipt
         end,
         unloading_zone=case
           when b.is_unknown then 'F'
           else s.unloading_zone
         end
  from _norm_batch b
  where s.id=b.id
    and (
      s.recipient_unknown is distinct from b.is_unknown
      or (b.is_unknown and coalesce(s.receipt_number,'') is distinct from v_xx)
      or (not b.is_unknown and b.old_receipt=v_xx)
      or (b.is_unknown and coalesce(s.unloading_zone,'') is distinct from 'F')
    );

  insert into public.unmatched_recipient_review_queue(
    shipment_id,status,detected_name,detected_phone,detected_by
  )
  select
    s.id,
    'pending',
    coalesce(s.consignee_name,''),
    coalesce(s.consignee_phone,''),
    auth.uid()
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where b.is_unknown
  on conflict (shipment_id) do update set
    status='pending',
    detected_name=excluded.detected_name,
    detected_phone=excluded.detected_phone,
    detected_by=coalesce(
      excluded.detected_by,
      public.unmatched_recipient_review_queue.detected_by
    ),
    updated_at=now(),
    resolved_by=null,
    resolved_at=null
  where public.unmatched_recipient_review_queue.status is distinct from 'pending'
     or public.unmatched_recipient_review_queue.detected_name is distinct from excluded.detected_name
     or public.unmatched_recipient_review_queue.detected_phone is distinct from excluded.detected_phone;

  update public.unmatched_recipient_review_queue q
     set status='resolved',
         resolved_by=auth.uid(),
         resolved_at=coalesce(q.resolved_at,now()),
         updated_at=now()
  from _norm_batch b
  where q.shipment_id=b.id
    and not b.is_unknown
    and q.status='pending';

  update _norm_batch b
     set old_receipt=btrim(coalesce(s.receipt_number,''))
  from public.shipments s
  where s.id=b.id;

  create temporary table if not exists _customer_receipt (
    customer_key text primary key,
    receipt text
  ) on commit drop;
  truncate _customer_receipt;

  insert into _customer_receipt(customer_key,receipt)
  select customer_key, receipt
  from (
    select
      b.customer_key,
      b.old_receipt receipt,
      row_number() over (
        partition by b.customer_key
        order by
          coalesce(
            (regexp_match(b.old_receipt,'(\d+)\s*$'))[1]::integer,
            2147483647
          ),
          b.id
      ) rn
    from _norm_batch b
    where not b.is_unknown
      and b.old_receipt<>''
      and b.old_receipt<>v_xx
  ) x
  where rn=1;

  update public.shipments s
     set receipt_number=cr.receipt
  from _norm_batch b
  join _customer_receipt cr on cr.customer_key=b.customer_key
  where s.id=b.id
    and not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')='';

  select
    coalesce(
      max(
        (regexp_match(
          btrim(coalesce(s.receipt_number,'')),
          '(\d+)\s*$'
        ))[1]::integer
      ),
      0
    ) + 1
  into v_start
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where not b.is_unknown
    and btrim(coalesce(s.receipt_number,''))<>''
    and btrim(coalesce(s.receipt_number,''))<>v_xx;

  v_start:=coalesce(v_start,1);

  create temporary table if not exists _new_receipts (
    customer_key text primary key,
    receipt text not null
  ) on commit drop;
  truncate _new_receipts;

  insert into _new_receipts(customer_key,receipt)
  select
    customer_key,
    case
      when coalesce(v_prefix,'')='' then
        'ID-'||lpad((v_start+rn-1)::text,2,'0')
      when v_route_key in ('kr_la_sea','kr_la_air') then
        v_prefix||' '||lpad((v_start+rn-1)::text,2,'0')
      else
        v_prefix||lpad((v_start+rn-1)::text,2,'0')
    end
  from (
    select
      customer_key,
      row_number() over(order by min(id))::integer rn
    from _norm_batch b
    where not b.is_unknown
      and not exists(
        select 1
        from _customer_receipt cr
        where cr.customer_key=b.customer_key
      )
    group by customer_key
  ) g;

  update public.shipments s
     set receipt_number=nr.receipt
  from _norm_batch b
  join _new_receipts nr on nr.customer_key=b.customer_key
  where s.id=b.id
    and not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')='';

  create temporary table if not exists _receipt_qty (
    receipt text primary key,
    qty integer not null
  ) on commit drop;
  truncate _receipt_qty;

  insert into _receipt_qty(receipt,qty)
  select
    btrim(s.receipt_number),
    sum(greatest(coalesce(s.quantity,1),1))::integer
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  -- PATCH138F: target table alias s는 FROM의 JOIN ON 안에서 참조하지 않음.
  update public.shipments s
     set unloading_zone=case
      when public.lk_unknown_prefix_zone(s.consignee_name) then 'F'
       when v_route_key='kr_la_air' then '102'
       when rq.qty>=20 then 'F'
       when rq.qty>=10 then 'C'
       when rq.qty>=5 then 'B'
       else 'A'
     end
  from _norm_batch b, _receipt_qty rq
  where s.id=b.id
    and not b.is_unknown
    and rq.receipt=btrim(s.receipt_number);

end;
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$;



CREATE OR REPLACE FUNCTION public.lk_apply_excel_logic_parity_legacy_v103(p_route text, p_year integer, p_voyage text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_previous_zone_setting text := coalesce(current_setting('lkgroup.calculating_zone',true),'');
begin
  perform set_config('lkgroup.calculating_zone','1',true);
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
  if coalesce(v_route_key,'')='' then perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true); return; end if;

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
    when public.lk_unknown_prefix_zone(s.consignee_name) then 'F'
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
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
exception when others then
  perform set_config('lkgroup.calculating_zone',v_previous_zone_setting,true);
  raise;
end;
$function$;



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
  if p_item?'receipt_number' then
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



-- Update only physical zones; skip automatic bill allocation for this correction.
do $$ begin
  perform set_config('lkgroup.normalizing_shipments','1',true);
  update public.shipments set unloading_zone='F'
    where public.lk_unknown_prefix_zone(consignee_name) and unloading_zone is distinct from 'F';
  perform set_config('lkgroup.normalizing_shipments','0',true);
end $$;

CREATE OR REPLACE FUNCTION public.web_import_excel_rules(p_route_key text, p_deliveries jsonb DEFAULT NULL::jsonb, p_discounts jsonb DEFAULT '[]'::jsonb, p_shares jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_saved_percent numeric;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and coalesce(approval_status,'approved')='approved' and coalesce(deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if not exists(select 1 from public.route_definitions where route_key=p_route_key and deleted_at is null) then raise exception '운송 경로를 확인하세요.'; end if;
  if jsonb_typeof(p_discounts)<>'array' or (p_deliveries is not null and jsonb_typeof(p_deliveries)<>'array') or (p_shares is not null and jsonb_typeof(p_shares)<>'array') then raise exception 'Invalid rule arrays'; end if;
  if p_deliveries is not null and jsonb_array_length(p_deliveries)>0 then
    delete from public.local_delivery_profiles where route_key=p_route_key;
    for r in select value from jsonb_array_elements(p_deliveries) loop
      insert into public.local_delivery_profiles(route_key,source_no,original_source_no,source_sheet,source_row,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred,active)
      values(p_route_key,(r->>'source_no')::integer,(r->>'original_source_no')::integer,r->>'source_sheet',(r->>'source_row')::integer,r->>'customer_name',r->>'alternate_name',r->>'company_name',r->>'phone',r->>'phone_display',r->>'delivery_type',r->>'local_company',r->>'destination_address',r->>'paid_by',r->>'notes',coalesce((r->>'preferred')::boolean,false),coalesce((r->>'active')::boolean,false));
    end loop;
  end if;
  for r in select value from jsonb_array_elements(p_discounts) loop
    if (r->>'discount_percent') is null or (r->>'discount_percent')::numeric not between 0 and 1 or coalesce((r->>'special_discount_percent')::numeric,0) not between 0 and (r->>'discount_percent')::numeric then raise exception '할인율 범위를 확인하세요.'; end if;
    insert into public.customer_rate_overrides(customer_name,phone,route_key,discount_percent,group_name,source_detail,active,excel_source_row,special_discount_percent)
    values(r->>'customer_name',r->>'phone',p_route_key,(r->>'discount_percent')::numeric,coalesce(r->>'group_name',''),coalesce(r->>'source_detail',''),coalesce((r->>'active')::boolean,false),(r->>'excel_source_row')::integer,(r->>'special_discount_percent')::numeric)
    on conflict(customer_name,phone,route_key) do update set discount_percent=(case when r->>'regular_discount_present'='false' then greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end)) else greatest(0,excluded.discount_percent-coalesce(excluded.special_discount_percent,0)) end)+(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),special_discount_percent=(case when r->>'special_discount_present'='false' then coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end,0) else coalesce(excluded.special_discount_percent,0) end),group_name=case when r->>'regular_discount_present'='false' and greatest(0,coalesce(customer_rate_overrides.discount_percent,0)-coalesce(customer_rate_overrides.special_discount_percent,case when regexp_replace(customer_rate_overrides.group_name,'\s','','g')='특별할인' then customer_rate_overrides.discount_percent else 0 end))>0 then customer_rate_overrides.group_name else excluded.group_name end,source_detail=excluded.source_detail,active=excluded.active,excel_source_row=excluded.excel_source_row,updated_at=now() returning discount_percent into v_saved_percent;
    if v_saved_percent not between 0 and 1 then raise exception '일반 할인과 특별할인의 합계는 100%%를 초과할 수 없습니다.'; end if;
  end loop;
  if p_shares is not null then
    delete from public.customer_statement_share_rules where route_key=p_route_key;
    for r in select value from jsonb_array_elements(p_shares) loop
      insert into public.customer_statement_share_rules(route_key,source_no,customer_name,phone,phone_display,content,active)
      values(p_route_key,(r->>'source_no')::integer,r->>'customer_name',r->>'phone',r->>'phone_display',r->>'content',true);
    end loop;
  end if;
end $function$;


-- Persist confirmation order independently from the customer ID or bill number.
alter table public.shipments add column if not exists recipient_recovered_order bigint;
create sequence if not exists public.recipient_recovered_order_seq;
grant usage on sequence public.recipient_recovered_order_seq to authenticated,service_role;
-- Historic rows have no reliable edit timestamp. Keep their already-issued bill
-- order as the baseline instead of guessing or renumbering old statements.
do $$ declare s record; begin
 for s in select id from public.shipments where public.lk_unknown_prefix_zone(consignee_name)
   and public.lk_excel_recovered_name(consignee_name,consignee_phone) is not null
   and recipient_recovered_order is null
   order by route,shipment_year,voyage,coalesce((regexp_match(receipt_number,'([0-9]+)$'))[1]::bigint,9223372036854775807),id
 loop update public.shipments set recipient_recovered_order=nextval('public.recipient_recovered_order_seq') where id=s.id; end loop;
end $$;
create or replace function public.capture_recipient_recovered_order()
returns trigger language plpgsql set search_path=public as $$
begin
 if tg_op='UPDATE' and old.recipient_recovered_order is not null then
   new.recipient_recovered_order:=old.recipient_recovered_order;
 elsif public.lk_unknown_prefix_zone(new.consignee_name)
   and public.lk_excel_recovered_name(new.consignee_name,new.consignee_phone) is not null then
   select min(s.recipient_recovered_order) into new.recipient_recovered_order
     from public.shipments s where s.route=new.route and s.shipment_year=new.shipment_year and s.voyage=new.voyage
       and public.lk_excel_customer_key(s.consignee_name,s.consignee_phone)=public.lk_excel_customer_key(new.consignee_name,new.consignee_phone)
       and s.deleted_at is null and s.deletion_requested_at is null;
   new.recipient_recovered_order:=coalesce(new.recipient_recovered_order,nextval('public.recipient_recovered_order_seq'));
 else new.recipient_recovered_order:=null;
 end if;
 return new;
end $$;
create trigger shipments_capture_recovered_order before insert or update of consignee_name,consignee_phone,recipient_recovered_order
 on public.shipments for each row execute function public.capture_recipient_recovered_order();
