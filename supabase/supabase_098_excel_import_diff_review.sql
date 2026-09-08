-- Excel re-import safety: compare every existing cargo row before writing.
-- New rows are inserted. Existing differences become review requests.
-- Identical rows, already-pending identical requests, deleted rows, and rows
-- absent from the workbook are never rewritten by this import path.

alter table public.shipment_change_requests
  add column if not exists request_source text not null default 'member';

alter table public.shipment_change_requests
  drop constraint if exists shipment_change_requests_request_source_check;
alter table public.shipment_change_requests
  add constraint shipment_change_requests_request_source_check
  check (request_source in ('member','excel_import'));

create index if not exists shipment_change_requests_pending_shipment_idx
  on public.shipment_change_requests(shipment_id,created_at,id)
  where status='pending';

create or replace function public.lk_excel_import_changes(
  p_item jsonb,
  p_existing public.shipments
)
returns jsonb
language plpgsql
stable
security invoker
set search_path=public
as $$
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
    v_text:=btrim(coalesce(p_item->>'unloading_zone',''));
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

  return v_changes;
end;
$$;

revoke all on function public.lk_excel_import_changes(jsonb,public.shipments)
  from public,anon,authenticated;

create or replace function public.manager_preview_shipment_import(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  item jsonb;
  first_item jsonb;
  existing_row public.shipments%rowtype;
  v_changes jsonb;
  current_values jsonb;
  item_status text;
  field_name text;
  items jsonb:='[]'::jsonb;
  new_rows integer:=0;
  unchanged integer:=0;
  change_rows integer:=0;
  already_pending integer:=0;
  protected_rows integer:=0;
  database_only integer:=0;
  k text;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception '화물 Excel 비교 권한이 없습니다.';
  end if;
  if jsonb_typeof(p_rows)<>'array' then
    raise exception '화물 데이터 형식이 올바르지 않습니다.';
  end if;

  select value into first_item from jsonb_array_elements(p_rows) limit 1;
  if first_item is not null and exists(
    select 1 from jsonb_array_elements(p_rows) row_item
    where coalesce(row_item->>'route','')<>coalesce(first_item->>'route','')
       or coalesce(row_item->>'shipment_year','')<>coalesce(first_item->>'shipment_year','')
       or coalesce(row_item->>'voyage','')<>coalesce(first_item->>'voyage','')
  ) then
    raise exception '한 번의 비교에는 하나의 경로·연도·항차만 사용할 수 있습니다.';
  end if;

  for item in select value from jsonb_array_elements(p_rows)
  loop
    k:=coalesce(item->>'import_key','');
    if k='' then continue; end if;
    select * into existing_row from public.shipments where import_key=k;

    if not found then
      new_rows:=new_rows+1;
      items:=items||jsonb_build_array(jsonb_build_object(
        'excel_row',item->'_row','box_number',item->>'box_number',
        'status','new','changes','{}'::jsonb,'current_values','{}'::jsonb
      ));
      continue;
    end if;

    if existing_row.deleted_at is not null or existing_row.deletion_requested_at is not null then
      protected_rows:=protected_rows+1;
      items:=items||jsonb_build_array(jsonb_build_object(
        'excel_row',item->'_row','box_number',item->>'box_number',
        'shipment_id',existing_row.id,'status','protected',
        'changes','{}'::jsonb,'current_values','{}'::jsonb
      ));
      continue;
    end if;

    v_changes:=public.lk_excel_import_changes(item,existing_row);
    if v_changes='{}'::jsonb then
      unchanged:=unchanged+1;
      continue;
    end if;

    current_values:='{}'::jsonb;
    for field_name in select jsonb_object_keys(v_changes)
    loop
      current_values:=current_values||jsonb_build_object(
        field_name,to_jsonb(existing_row)->field_name
      );
    end loop;

    if exists(
      select 1 from public.shipment_change_requests r
      where r.shipment_id=existing_row.id and r.status='pending'
        and r.changes=v_changes and r.request_source='excel_import'
    ) then
      item_status:='pending';
      already_pending:=already_pending+1;
    else
      item_status:='change';
      change_rows:=change_rows+1;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object(
      'excel_row',item->'_row','box_number',item->>'box_number',
      'shipment_id',existing_row.id,'status',item_status,
      'changes',v_changes,'current_values',current_values,
      'locked',coalesce(existing_row.data_locked,false)
    ));
  end loop;

  if first_item is not null then
    select count(*)::integer into database_only
    from public.shipments s
    where s.route=first_item->>'route'
      and s.shipment_year=nullif(first_item->>'shipment_year','')::integer
      and s.voyage=first_item->>'voyage'
      and s.deleted_at is null
      and s.deletion_requested_at is null
      and not exists(
        select 1 from jsonb_array_elements(p_rows) row_item
        where row_item->>'import_key'=s.import_key
      );
  end if;

  return jsonb_build_object(
    'new_rows',new_rows,
    'unchanged',unchanged,
    'change_requests',change_rows,
    'already_pending',already_pending,
    'protected_rows',protected_rows,
    'database_only',database_only,
    'existing_rows',unchanged+change_rows+already_pending+protected_rows,
    'items',items
  );
end;
$$;

revoke all on function public.manager_preview_shipment_import(jsonb)
  from public,anon;
grant execute on function public.manager_preview_shipment_import(jsonb)
  to authenticated;

create or replace function public.manager_import_shipment_differences_bulk(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  item jsonb;
  existing_row public.shipments%rowtype;
  v_changes jsonb;
  inserted_count integer;
  new_rows integer:=0;
  unchanged integer:=0;
  change_requests integer:=0;
  already_pending integer:=0;
  protected_rows integer:=0;
  k text;
begin
  if public.current_role() not in ('admin','staff','partner') then
    raise exception '화물 Excel 업로드 권한이 없습니다.';
  end if;
  if jsonb_typeof(p_rows)<>'array' then
    raise exception '화물 데이터 형식이 올바르지 않습니다.';
  end if;

  perform set_config('lkgroup.bulk_import','1',true);

  for item in select value from jsonb_array_elements(p_rows)
  loop
    k:=coalesce(item->>'import_key','');
    if k='' then continue; end if;

    select * into existing_row
    from public.shipments where import_key=k for update;

    if found then
      if existing_row.deleted_at is not null or existing_row.deletion_requested_at is not null then
        protected_rows:=protected_rows+1;
        continue;
      end if;

      v_changes:=public.lk_excel_import_changes(item,existing_row);
      if v_changes='{}'::jsonb then
        unchanged:=unchanged+1;
      elsif exists(
        select 1 from public.shipment_change_requests r
        where r.shipment_id=existing_row.id and r.status='pending'
          and r.changes=v_changes and r.request_source='excel_import'
      ) then
        already_pending:=already_pending+1;
      else
        insert into public.shipment_change_requests(
          shipment_id,requested_by,changes,status,request_source
        ) values(
          existing_row.id,auth.uid(),v_changes,'pending','excel_import'
        );
        change_requests:=change_requests+1;
      end if;
      continue;
    end if;

    insert into public.shipments(
      box_number,invoice_number,route,shipment_year,voyage,import_key,
      sender_name,consignee_name,consignee_phone,contents,package_type,
      quantity,weight_kg,length_cm,width_cm,height_cm,
      receipt_number,unloading_zone,notes,received_at,status
    ) values(
      btrim(coalesce(item->>'box_number','')),
      btrim(coalesce(item->>'invoice_number','')),
      btrim(coalesce(item->>'route','')),
      nullif(item->>'shipment_year','')::integer,
      btrim(coalesce(item->>'voyage','')),
      k,
      btrim(coalesce(item->>'sender_name','')),
      btrim(coalesce(item->>'consignee_name','')),
      btrim(coalesce(item->>'consignee_phone','')),
      btrim(coalesce(item->>'contents','')),
      btrim(coalesce(item->>'package_type','')),
      coalesce(nullif(replace(item->>'quantity',',',''),'')::integer,1),
      nullif(replace(item->>'weight_kg',',',''),'')::numeric,
      nullif(replace(item->>'length_cm',',',''),'')::numeric,
      nullif(replace(item->>'width_cm',',',''),'')::numeric,
      nullif(replace(item->>'height_cm',',',''),'')::numeric,
      btrim(coalesce(item->>'receipt_number','')),
      btrim(coalesce(item->>'unloading_zone','')),
      btrim(coalesce(item->>'notes','')),
      nullif(item->>'received_at','')::date,
      coalesce(nullif(btrim(item->>'status'),''),'registered')
    )
    on conflict (import_key)
      where import_key is not null and import_key<>''
    do nothing;
    get diagnostics inserted_count=row_count;
    new_rows:=new_rows+inserted_count;
  end loop;

  perform set_config('lkgroup.bulk_import','',true);
  return jsonb_build_object(
    'new_rows',new_rows,
    'unchanged',unchanged,
    'change_requests',change_requests,
    'already_pending',already_pending,
    'protected_rows',protected_rows
  );
exception when others then
  perform set_config('lkgroup.bulk_import','',true);
  raise;
end;
$$;

revoke all on function public.manager_import_shipment_differences_bulk(jsonb)
  from public,anon;
grant execute on function public.manager_import_shipment_differences_bulk(jsonb)
  to authenticated,service_role;

-- Preserve the old RPC names for installed app versions, but make them safe:
-- they now insert new rows and queue existing differences instead of overwriting.
create or replace function public.manager_upsert_unlocked_shipments(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  result jsonb;
begin
  result:=public.manager_import_shipment_differences_bulk(p_rows);
  return coalesce((result->>'new_rows')::integer,0)
       + coalesce((result->>'change_requests')::integer,0);
end;
$$;

create or replace function public.manager_upsert_unlocked_shipments_bulk(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  result jsonb;
begin
  result:=public.manager_import_shipment_differences_bulk(p_rows);
  return coalesce((result->>'new_rows')::integer,0)
       + coalesce((result->>'change_requests')::integer,0);
end;
$$;

revoke all on function public.manager_upsert_unlocked_shipments(jsonb)
  from public,anon;
revoke all on function public.manager_upsert_unlocked_shipments_bulk(jsonb)
  from public,anon;
grant execute on function public.manager_upsert_unlocked_shipments(jsonb)
  to authenticated,service_role;
grant execute on function public.manager_upsert_unlocked_shipments_bulk(jsonb)
  to authenticated,service_role;

-- Excel-origin requests may include the workbook's receipt and zone. They are
-- applied only after approval, without immediately re-running automatic receipt
-- resequencing over the whole voyage.
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
  if public.current_role()<>'admin' then
    raise exception '총괄 관리자 권한이 필요합니다.';
  end if;

  select * into v_req from public.shipment_change_requests
  where id=p_request_id and status='pending' for update;
  if not found then raise exception '처리 가능한 요청을 찾을 수 없습니다.'; end if;

  if p_action='reject' then
    update public.shipment_change_requests
    set status='rejected',review_result='rejected',admin_changes='{}'::jsonb,
        reviewed_by=auth.uid(),reviewed_at=now()
    where id=p_request_id;
    v_message:='수정 요청이 거절 되었습니다.';
    v_result:='rejected';
  elsif p_action in ('approve','modified_approve') then
    v_final:=coalesce(v_req.changes,'{}'::jsonb)||coalesce(p_admin_changes,'{}'::jsonb);
    select route,shipment_year,voyage into v_route,v_year,v_voyage
    from public.shipments where id=v_req.shipment_id;

    if v_req.request_source='excel_import' then
      perform set_config('lkgroup.bulk_import','1',true);
    end if;
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
        receipt_number=case when v_final?'receipt_number' then coalesce(v_final->>'receipt_number','') else receipt_number end,
        unloading_zone=case when v_final?'unloading_zone' then coalesce(v_final->>'unloading_zone','') else unloading_zone end,
        notes=case when v_final?'notes' then coalesce(v_final->>'notes','') else notes end,
        received_at=case when v_final?'received_at' then nullif(v_final->>'received_at','')::date else received_at end,
        updated_at=now()
    where id=v_req.shipment_id;
    if v_req.request_source='excel_import' then
      update public.shipments
      set recipient_unknown=public.lk_recipient_true_unknown(consignee_name,consignee_phone),
          special_note_auto=public.compute_shipment_special_note(route,consignee_name,consignee_phone)
      where id=v_req.shipment_id;
      perform set_config('lkgroup.bulk_import','',true);
    else
      perform public.normalize_shipment_batch(v_route,v_year,v_voyage);
    end if;

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
  else
    raise exception '지원하지 않는 처리 방식입니다.';
  end if;

  if v_req.requested_by is not null then
    insert into public.user_notifications(
      user_id,notification_type,title,message,related_request_id
    ) values(
      v_req.requested_by,'shipment_change','화물 정보 수정 요청',v_message,p_request_id
    );
  end if;
exception when others then
  perform set_config('lkgroup.bulk_import','',true);
  raise;
end;
$$;

revoke all on function public.review_shipment_change_request(bigint,text,jsonb)
  from public,anon;
grant execute on function public.review_shipment_change_request(bigint,text,jsonb)
  to authenticated;
