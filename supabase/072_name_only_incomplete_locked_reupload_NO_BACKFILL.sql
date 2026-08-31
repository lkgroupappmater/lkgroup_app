-- 072_name_only_incomplete_locked_reupload.sql
-- Patch138
-- 1) 이름만 있고 전화번호가 없는 화물 = 일반 화물(영수번호/Zone 계산) + '확인 필요'
-- 2) 이름 자체가 없거나 명시적인 불명 표기만 XX/F
-- 3) 잠금된 화물은 재업로드로 덮어쓰지 않고 변경 승인 요청 생성
-- 4) 승인 전 검색/관리/Excel output은 기존 잠금값 유지
-- 5) 불완전 화물 잠금 시 확인 완료로 간주, 잠금 해제 시 다시 확인 목록 노출

create or replace function public.shipment_name_is_explicit_unknown(p_name text)
returns boolean
language sql
immutable
as $$
  select
    coalesce(btrim(p_name),'') = ''
    or lower(btrim(coalesce(p_name,''))) like '%수취인 불명%'
    or lower(btrim(coalesce(p_name,''))) like '%데이타 불문명%'
    or lower(btrim(coalesce(p_name,''))) like '%데이터 불문명%'
    or lower(btrim(coalesce(p_name,''))) like '%unknown%'
    or lower(btrim(coalesce(p_name,''))) like '%미상%'
$$;

create or replace function public.refresh_recipient_unknown_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recipient_unknown_confirmed_at is not null then
    new.recipient_unknown := false;
    return new;
  end if;

  -- Patch138: 전화번호 누락만으로는 수취인 불명으로 만들지 않습니다.
  new.recipient_unknown := public.shipment_name_is_explicit_unknown(new.consignee_name);
  return new;
end;
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
  v_receipt_prefix text;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_next integer := 1;
  r record;
  v_existing text;
  v_receipt text;
  v_count integer;
  v_unknown_receipt text;
  v_is_unknown boolean;
begin
  if coalesce(trim(p_route),'')='' or p_year is null or coalesce(trim(v_voyage),'')='' then
    return;
  end if;

  select rd.route_key, rd.receipt_prefix
    into v_route_key, v_receipt_prefix
  from public.route_definitions rd
  where rd.display_name=trim(p_route) or rd.route_key=trim(p_route)
  order by case when rd.display_name=trim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(trim(v_receipt_prefix),'')='' then
    v_receipt_prefix := '';
  end if;

  v_unknown_receipt :=
    case
      when trim(v_receipt_prefix)='' then 'XX'
      when v_route_key in ('kr_la_sea','kr_la_air') then trim(v_receipt_prefix)||' XX'
      else trim(v_receipt_prefix)||'XX'
    end;

  for r in
    select s.id, s.consignee_name, s.consignee_phone, s.recipient_unknown_confirmed_at
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  loop
    -- 이름 자체가 없거나 명시적으로 '불명'인 경우만 XX/F.
    -- 이름이 있고 전화번호만 없는 경우는 정상 영수번호/Zone 계산 대상.
    v_is_unknown :=
      r.recipient_unknown_confirmed_at is null
      and public.shipment_name_is_explicit_unknown(r.consignee_name);

    update public.shipments
       set recipient_unknown=v_is_unknown,
           unloading_zone=case when v_is_unknown then 'F' else unloading_zone end,
           receipt_number=case
             when v_is_unknown then v_unknown_receipt
             when receipt_number=v_unknown_receipt then ''
             else receipt_number
           end
     where id=r.id;

    if v_is_unknown then
      insert into public.unmatched_recipient_review_queue(
        shipment_id,status,detected_name,detected_phone,detected_by
      )
      values(
        r.id,'pending',coalesce(r.consignee_name,''),coalesce(r.consignee_phone,''),auth.uid()
      )
      on conflict (shipment_id) do update set
        status='pending',
        detected_name=excluded.detected_name,
        detected_phone=excluded.detected_phone,
        detected_by=coalesce(excluded.detected_by, public.unmatched_recipient_review_queue.detected_by),
        updated_at=now(),
        resolved_by=null,
        resolved_at=null
      where public.unmatched_recipient_review_queue.status='resolved'
         or public.unmatched_recipient_review_queue.detected_name is distinct from excluded.detected_name
         or public.unmatched_recipient_review_queue.detected_phone is distinct from excluded.detected_phone;
    else
      update public.unmatched_recipient_review_queue
         set status='resolved',
             resolved_by=auth.uid(),
             resolved_at=coalesce(resolved_at,now()),
             updated_at=now()
       where shipment_id=r.id and status='pending';
    end if;
  end loop;

  select coalesce(max((m)[1]::integer),0)+1
    into v_next
  from public.shipments s
  cross join lateral regexp_match(trim(coalesce(s.receipt_number,'')),'(\d+)\s*$') m
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.recipient_unknown=false
    and s.deletion_requested_at is null;

  if v_next is null or v_next<1 then v_next:=1; end if;

  for r in
    select s.id,
           lower(trim(coalesce(s.consignee_name,''))) customer_name,
           regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g') customer_phone
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')=''
      and s.deletion_requested_at is null
    order by s.created_at nulls last,s.id
  loop
    select trim(s.receipt_number)
      into v_existing
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')<>''
      and s.receipt_number<>v_unknown_receipt
      and lower(trim(coalesce(s.consignee_name,'')))=r.customer_name
      and regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g')=r.customer_phone
      and s.deletion_requested_at is null
    order by s.id
    limit 1;

    if coalesce(v_existing,'')<>'' then
      v_receipt:=v_existing;
    else
      if trim(v_receipt_prefix)='' then
        v_receipt:='ID-'||lpad(v_next::text,2,'0');
      elsif v_route_key in ('kr_la_sea','kr_la_air') then
        v_receipt:=trim(v_receipt_prefix)||' '||lpad(v_next::text,2,'0');
      else
        v_receipt:=trim(v_receipt_prefix)||lpad(v_next::text,2,'0');
      end if;
      v_next:=v_next+1;
    end if;

    update public.shipments set receipt_number=v_receipt where id=r.id;
  end loop;

  for r in
    select s.receipt_number,sum(greatest(coalesce(s.quantity,1),1))::integer qty
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')<>''
      and s.deletion_requested_at is null
    group by s.receipt_number
  loop
    v_count:=r.qty;
    update public.shipments s
       set unloading_zone=case
         when v_route_key='kr_la_air' then '102'
         when v_count>=20 then 'F'
         when v_count>=10 then 'C'
         when v_count>=5 then 'B'
         else 'A'
       end
     where s.route=p_route
       and s.shipment_year=p_year
       and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
       and s.receipt_number=r.receipt_number
       and s.recipient_unknown=false
       and s.deletion_requested_at is null;
  end loop;

  update public.shipments s
     set unloading_zone='F', receipt_number=v_unknown_receipt
   where s.route=p_route
     and s.shipment_year=p_year
     and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
     and s.recipient_unknown=true
     and s.deletion_requested_at is null;
end;
$$;

-- 이름은 있으나 전화번호가 없는 '확인 필요' 목록.
create or replace function public.admin_list_incomplete_shipments()
returns setof public.shipments
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  return query
  select s.*
  from public.shipments s
  where s.deletion_requested_at is null
    and coalesce(s.data_locked,false)=false
    and public.shipment_name_is_explicit_unknown(s.consignee_name)=false
    and public.normalize_phone(s.consignee_phone)=''
  order by
    s.route,
    s.shipment_year desc,
    lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),6,'0'),
    coalesce((regexp_match(coalesce(s.receipt_number,''),'(\d+)\s*$'))[1]::integer, 2147483647),
    coalesce((regexp_match(coalesce(s.box_number,''),'(\d+)\s*$'))[1]::integer, 2147483647),
    s.id;
end;
$$;

create or replace function public.admin_review_incomplete_shipment(
  p_shipment_id bigint,
  p_consignee_name text,
  p_consignee_phone text,
  p_notes text,
  p_lock boolean default false
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_row public.shipments%rowtype;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  select * into v_row from public.shipments where id=p_shipment_id for update;
  if not found then raise exception '화물을 찾을 수 없습니다.'; end if;

  update public.shipments
     set consignee_name=coalesce(p_consignee_name,''),
         consignee_phone=coalesce(p_consignee_phone,''),
         notes=coalesce(p_notes,''),
         data_locked=case when p_lock then true else data_locked end,
         data_locked_at=case when p_lock then now() else data_locked_at end,
         data_locked_by=case when p_lock then auth.uid() else data_locked_by end,
         updated_at=now()
   where id=p_shipment_id;

  perform public.normalize_shipment_batch(v_row.route,v_row.shipment_year,v_row.voyage);
end;
$$;

-- 잠금된 동일 import_key 재업로드:
-- 현재 shipments 값은 유지하고, 차이가 있으면 기존 변경승인 큐에 요청만 생성.
create or replace function public.manager_upsert_unlocked_shipments(
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  item jsonb;
  affected integer := 0;
  changed integer;
  k text;
  existing_row public.shipments%rowtype;
  proposed jsonb;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception '화물 Excel 업로드 권한이 없습니다.';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception '화물 데이터 형식이 올바르지 않습니다.';
  end if;

  for item in select value from jsonb_array_elements(p_rows)
  loop
    k := coalesce(item->>'import_key','');
    if k='' then continue; end if;

    select * into existing_row
      from public.shipments
     where import_key=k
     for update;

    if found and coalesce(existing_row.data_locked,false)=true then
      proposed := jsonb_strip_nulls(jsonb_build_object(
        'invoice_number', item->'invoice_number',
        'sender_name', item->'sender_name',
        'consignee_name', item->'consignee_name',
        'consignee_phone', item->'consignee_phone',
        'contents', item->'contents',
        'package_type', item->'package_type',
        'quantity', item->'quantity',
        'weight_kg', item->'weight_kg',
        'length_cm', item->'length_cm',
        'width_cm', item->'width_cm',
        'height_cm', item->'height_cm',
        'notes', item->'notes',
        'received_at', item->'received_at',
        'status', item->'status'
      ));

      -- 실제 현재값과 같은 필드는 제거.
      if coalesce(proposed->>'invoice_number','') = coalesce(existing_row.invoice_number,'') then proposed:=proposed-'invoice_number'; end if;
      if coalesce(proposed->>'sender_name','') = coalesce(existing_row.sender_name,'') then proposed:=proposed-'sender_name'; end if;
      if coalesce(proposed->>'consignee_name','') = coalesce(existing_row.consignee_name,'') then proposed:=proposed-'consignee_name'; end if;
      if coalesce(proposed->>'consignee_phone','') = coalesce(existing_row.consignee_phone,'') then proposed:=proposed-'consignee_phone'; end if;
      if coalesce(proposed->>'contents','') = coalesce(existing_row.contents,'') then proposed:=proposed-'contents'; end if;
      if coalesce(proposed->>'package_type','') = coalesce(existing_row.package_type,'') then proposed:=proposed-'package_type'; end if;
      if coalesce(proposed->>'quantity','1') = coalesce(existing_row.quantity,1)::text then proposed:=proposed-'quantity'; end if;
      if coalesce(proposed->>'weight_kg','') = coalesce(existing_row.weight_kg::text,'') then proposed:=proposed-'weight_kg'; end if;
      if coalesce(proposed->>'length_cm','') = coalesce(existing_row.length_cm::text,'') then proposed:=proposed-'length_cm'; end if;
      if coalesce(proposed->>'width_cm','') = coalesce(existing_row.width_cm::text,'') then proposed:=proposed-'width_cm'; end if;
      if coalesce(proposed->>'height_cm','') = coalesce(existing_row.height_cm::text,'') then proposed:=proposed-'height_cm'; end if;
      if coalesce(proposed->>'notes','') = coalesce(existing_row.notes,'') then proposed:=proposed-'notes'; end if;
      if coalesce(proposed->>'status','registered') = coalesce(existing_row.status,'registered') then proposed:=proposed-'status'; end if;
      if coalesce(proposed->>'received_at','') = coalesce(existing_row.received_at::text,'') then proposed:=proposed-'received_at'; end if;

      if proposed <> '{}'::jsonb and not exists (
        select 1 from public.shipment_change_requests r
        where r.shipment_id=existing_row.id
          and r.status='pending'
          and r.changes=proposed
      ) then
        insert into public.shipment_change_requests(shipment_id,requested_by,changes,status)
        values(existing_row.id,auth.uid(),proposed,'pending');
      end if;
      continue;
    end if;

    insert into public.shipments (
      box_number, invoice_number, route, shipment_year, voyage, import_key,
      sender_name, consignee_name, consignee_phone, contents, package_type,
      quantity, weight_kg, length_cm, width_cm, height_cm,
      receipt_number, unloading_zone, notes, received_at, status
    )
    values (
      coalesce(item->>'box_number',''),
      coalesce(item->>'invoice_number',''),
      coalesce(item->>'route',''),
      nullif(item->>'shipment_year','')::integer,
      coalesce(item->>'voyage',''),
      k,
      coalesce(item->>'sender_name',''),
      coalesce(item->>'consignee_name',''),
      coalesce(item->>'consignee_phone',''),
      coalesce(item->>'contents',''),
      coalesce(item->>'package_type',''),
      coalesce(nullif(item->>'quantity','')::integer,1),
      nullif(item->>'weight_kg','')::numeric,
      nullif(item->>'length_cm','')::numeric,
      nullif(item->>'width_cm','')::numeric,
      nullif(item->>'height_cm','')::numeric,
      coalesce(item->>'receipt_number',''),
      coalesce(item->>'unloading_zone',''),
      coalesce(item->>'notes',''),
      nullif(item->>'received_at','')::timestamptz,
      coalesce(nullif(item->>'status',''),'registered')
    )
    on conflict (import_key)
      where import_key is not null and import_key <> ''
    do update set
      box_number = excluded.box_number,
      invoice_number = excluded.invoice_number,
      sender_name = excluded.sender_name,
      consignee_name = excluded.consignee_name,
      consignee_phone = excluded.consignee_phone,
      contents = excluded.contents,
      package_type = excluded.package_type,
      quantity = excluded.quantity,
      weight_kg = excluded.weight_kg,
      length_cm = excluded.length_cm,
      width_cm = excluded.width_cm,
      height_cm = excluded.height_cm,
      receipt_number = excluded.receipt_number,
      unloading_zone = excluded.unloading_zone,
      notes = excluded.notes,
      received_at = excluded.received_at,
      status = excluded.status
    where public.shipments.data_locked=false;

    get diagnostics changed=row_count;
    affected:=affected+changed;
  end loop;

  return affected;
end;
$$;

-- 승인 시 Excel 재업로드 요청의 전체 화물 필드도 반영.
create or replace function public.review_shipment_change_request(
  p_request_id bigint,
  p_action text,
  p_admin_changes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_req public.shipment_change_requests%rowtype;
  v_final jsonb;
  v_message text;
  v_result text;
  v_route text;
  v_year integer;
  v_voyage text;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  select * into v_req
    from public.shipment_change_requests
   where id=p_request_id and status='pending'
   for update;
  if not found then raise exception '처리 가능한 요청을 찾을 수 없습니다.'; end if;

  if p_action='reject' then
    update public.shipment_change_requests
       set status='rejected',review_result='rejected',
           admin_changes='{}'::jsonb,reviewed_by=auth.uid(),reviewed_at=now()
     where id=p_request_id;
    v_message:='수정 요청이 거절 되었습니다.';
    v_result:='rejected';
  elsif p_action in ('approve','modified_approve') then
    v_final:=coalesce(v_req.changes,'{}'::jsonb)||coalesce(p_admin_changes,'{}'::jsonb);

    select route,shipment_year,voyage into v_route,v_year,v_voyage
      from public.shipments where id=v_req.shipment_id;

    update public.shipments
       set invoice_number=case when v_final?'invoice_number' then coalesce(v_final->>'invoice_number','') else invoice_number end,
           sender_name=case when v_final?'sender_name' then coalesce(v_final->>'sender_name','') else sender_name end,
           consignee_name=case when v_final?'consignee_name' then coalesce(v_final->>'consignee_name','') else consignee_name end,
           consignee_phone=case when v_final?'consignee_phone' then coalesce(v_final->>'consignee_phone','') else consignee_phone end,
           contents=case when v_final?'contents' then coalesce(v_final->>'contents','') else contents end,
           package_type=case when v_final?'package_type' then coalesce(v_final->>'package_type','') else package_type end,
           quantity=case when v_final?'quantity' then coalesce(nullif(v_final->>'quantity','')::integer,1) else quantity end,
           weight_kg=case when v_final?'weight_kg' then nullif(v_final->>'weight_kg','')::numeric else weight_kg end,
           length_cm=case when v_final?'length_cm' then nullif(v_final->>'length_cm','')::numeric else length_cm end,
           width_cm=case when v_final?'width_cm' then nullif(v_final->>'width_cm','')::numeric else width_cm end,
           height_cm=case when v_final?'height_cm' then nullif(v_final->>'height_cm','')::numeric else height_cm end,
           notes=case when v_final?'notes' then coalesce(v_final->>'notes','') else notes end,
           received_at=case when v_final?'received_at' then nullif(v_final->>'received_at','')::timestamptz else received_at end,
           status=case when v_final?'status' then coalesce(nullif(v_final->>'status',''),'registered') else status end,
           updated_at=now()
     where id=v_req.shipment_id;

    if p_action='modified_approve' and coalesce(p_admin_changes,'{}'::jsonb)<>'{}'::jsonb then
      v_result:='modified_approved';
      v_message:='관리자의 추가 수정 후 승인 되었습니다.';
    else
      v_result:='approved';
      v_message:='승인 되었습니다.';
    end if;

    update public.shipment_change_requests
       set status='approved',review_result=v_result,
           admin_changes=coalesce(p_admin_changes,'{}'::jsonb),
           reviewed_by=auth.uid(),reviewed_at=now()
     where id=p_request_id;

    perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
  else
    raise exception '지원하지 않는 처리 방식입니다.';
  end if;

  if v_req.requested_by is not null then
    insert into public.user_notifications(
      user_id,notification_type,title,message,related_request_id
    ) values (
      v_req.requested_by,'shipment_change','화물 정보 수정 요청',v_message,p_request_id
    );
  end if;
end;
$$;

-- Patch138b: 대량 기존 데이터 자동 재정리 DO 블록은 timeout 방지를 위해 제거했습니다.
-- 기존 데이터 재정리는 별도 SQL에서 항차 단위로 실행합니다.

grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated;
grant execute on function public.admin_list_incomplete_shipments() to authenticated;
grant execute on function public.admin_review_incomplete_shipment(bigint,text,text,text,boolean) to authenticated;
grant execute on function public.manager_upsert_unlocked_shipments(jsonb) to authenticated;
grant execute on function public.review_shipment_change_request(bigint,text,jsonb) to authenticated;
