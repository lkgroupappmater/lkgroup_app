-- Preserve canonical keys and distinguish later manual deletions on trash restore.
CREATE OR REPLACE FUNCTION public.manager_cancel_shipment_deletion(p_shipment_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row public.shipments%rowtype;
  v_prefix text;
  v_current_number integer;
  v_next_number integer;
  v_digits integer;
  v_new_box text;
  v_conflict boolean := false;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p where p.id=auth.uid()
      and coalesce(p.approval_status,'approved')='approved'
      and coalesce(p.deletion_status,'active')='active'
  ) or coalesce(public.current_role(), '') not in ('admin','staff','partner') then
    raise exception 'not authorized';
  end if;

  select *
  into v_row
  from public.shipments
  where id = p_shipment_id
    and deletion_requested_at is not null
  for update;

  if not found then
    raise exception 'pending shipment not found';
  end if;

  -- 원래 박스번호가 활성 화물에 이미 사용 중인지 확인합니다.
  select exists(
    select 1
    from public.shipments s
    where s.id <> v_row.id
      and s.route = v_row.route
      and s.shipment_year = v_row.shipment_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0')
          = lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0')
      and lower(trim(coalesce(s.box_number,'')))
          = lower(trim(coalesce(v_row.box_number,'')))
      and s.deletion_requested_at is null
  )
  into v_conflict;

  if v_conflict then
    -- 박스번호의 끝 숫자를 기준으로 prefix / 자릿수를 유지합니다.
    v_prefix := regexp_replace(coalesce(v_row.box_number,''), '[0-9]+$', '');
    v_digits := greatest(
      3,
      length(coalesce(substring(v_row.box_number from '([0-9]+)$'), ''))
    );

    select coalesce(max(
      nullif(
        substring(s.box_number from '([0-9]+)$'),
        ''
      )::integer
    ), 0)
    into v_current_number
    from public.shipments s
    where s.route = v_row.route
      and s.shipment_year = v_row.shipment_year
      and lpad(regexp_replace(coalesce(s.voyage,''), '[^0-9]', '', 'g'), 2, '0')
          = lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0')
      and s.deletion_requested_at is null
      and s.box_number like v_prefix || '%';

    v_next_number := v_current_number + 1;
    v_new_box := v_prefix || lpad(v_next_number::text, v_digits, '0');

    update public.shipments
    set box_number = v_new_box,
        import_key = trim(v_row.route) || '|' ||
                     coalesce(v_row.shipment_year::text, '') || '|' ||
                     lpad(regexp_replace(coalesce(v_row.voyage,''), '[^0-9]', '', 'g'), 2, '0') || '|' ||
                     v_new_box,
        deletion_requested_at = null,
        deletion_requested_by = null,
        excel_removed_at = null
    where id = p_shipment_id;
  else
    update public.shipments
    set import_key = concat(v_row.route,'|',v_row.shipment_year,'|',v_row.voyage,'|',v_row.box_number),
        deletion_requested_at = null,
        deletion_requested_by = null,
        excel_removed_at = null
    where id = p_shipment_id;
  end if;
end;
$function$
;
create or replace function public.admin_preview_shipment_excel_sync(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='45s'
as $$
declare
  r text; y integer; v text; item jsonb; matched jsonb; changes jsonb;
  old_row public.shipments%rowtype; empty_row public.shipments%rowtype;
  incoming jsonb:='[]'; existing jsonb; items jsonb:='[]'; used bigint[]:='{}';
  chosen bigint; n integer; token text; field text; val numeric; kind text;
begin
  if auth.uid() is null or coalesce(public.current_role(),'')<>'admin'
    or not exists(select 1 from public.profiles p where p.id=auth.uid()
      and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active')
    then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Excel 행 형식이 올바르지 않습니다.'; end if;
  if jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)>10000 then
    raise exception '화물 행이 없거나 너무 많습니다. 빈 파일로 항차 전체를 삭제할 수 없습니다.';
  end if;
  r:=btrim(p_rows->0->>'route'); y:=(p_rows->0->>'shipment_year')::integer; v:=p_rows->0->>'voyage';
  if coalesce(r,'')='' or y is null or y not between 1900 and 2099 or coalesce(v,'')!~'^[0-9]{2,3}$' or v::integer=0 then
    raise exception '운송 경로·년도·항차를 확인해 주세요. BASE는 화물 동기화 대상이 아닙니다.';
  end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(item)<>'object' or item->>'route' is distinct from r
      or (item->>'shipment_year')::integer is distinct from y or item->>'voyage' is distinct from v
      or btrim(coalesce(item->>'box_number',''))='' then raise exception '동일 항차의 전체 화물 목록과 화물번호가 필요합니다.'; end if;
    if not (item ?& array['invoice_number','consignee_name','consignee_phone','quantity']) then
      raise exception '화물 필수 열이 누락되었습니다.';
    end if;
    for field in select unnest(array['quantity','weight_kg','length_cm','width_cm','height_cm']) loop
      val:=nullif(replace(item->>field,',',''),'')::numeric;
      if val<0 or val::text in ('NaN','Infinity','-Infinity') or (field='quantity' and (val<1 or val>999999 or trunc(val)<>val)) then
        raise exception '화물 %의 % 값을 확인해 주세요.', item->>'box_number',field;
      end if;
      if item ? field then item:=jsonb_set(item,array[field],coalesce(to_jsonb(val),case when field='quantity' then '1'::jsonb else 'null'::jsonb end)); end if;
    end loop;
    item:=item||jsonb_build_object('box_number',btrim(item->>'box_number'),'invoice_number',btrim(coalesce(item->>'invoice_number','')));
    -- Reuse the existing typed comparison to validate dates and normalize cells.
    changes:=public.lk_excel_import_changes(item,empty_row);
    incoming:=incoming||jsonb_build_array(item||changes);
  end loop;
  if exists(select 1 from jsonb_array_elements(incoming) x group by lower(x->>'box_number') having count(*)>1) then
    raise exception '중복 화물번호를 수정한 뒤 다시 업로드해 주세요.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.id),'[]') into existing from public.shipments s
    where s.route=r and s.shipment_year=y and s.voyage=v;

  -- First use a unique invoice to preserve IDs when box numbers change or swap.
  -- Otherwise use the box number. A row can never be matched twice.
  for item in select value from jsonb_array_elements(incoming) loop
    chosen:=null;
    if item->>'invoice_number'<>'' and (select count(*) from jsonb_array_elements(incoming) a where a->>'invoice_number'=item->>'invoice_number')=1 then
      select count(*),min((e->>'id')::bigint) into n,chosen from jsonb_array_elements(existing) e
        where btrim(e->>'invoice_number')=item->>'invoice_number' and e->>'deleted_at' is null
        and (e->>'deletion_requested_at' is null or e->>'deletion_requested_at'=e->>'excel_removed_at');
      if n<>1 then chosen:=null; end if;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object('_data',item,'shipment_id',chosen));
  end loop;
  for item in select value from jsonb_array_elements(items) where value->>'shipment_id' is not null loop
    used:=array_append(used,(item->>'shipment_id')::bigint);
  end loop;
  incoming:=items; items:='[]';
  for matched in select value from jsonb_array_elements(incoming) loop
    item:=matched->'_data'; chosen:=(matched->>'shipment_id')::bigint;
    if chosen is null then
      select count(*),min((e->>'id')::bigint) into n,chosen from jsonb_array_elements(existing) e
        where lower(btrim(e->>'box_number'))=lower(item->>'box_number') and not (e->>'id')::bigint=any(used)
        and e->>'deleted_at' is null and (e->>'deletion_requested_at' is null or e->>'deletion_requested_at'=e->>'excel_removed_at');
      if n>1 then raise exception '화물번호 %의 기존 화물이 여러 건입니다.',item->>'box_number'; end if;
      if n=0 then chosen:=null; end if;
      if chosen is not null then used:=array_append(used,chosen); end if;
    end if;
    if chosen is null then
      if exists(select 1 from jsonb_array_elements(existing) e where lower(btrim(e->>'box_number'))=lower(item->>'box_number') and (e->>'deleted_at' is not null or (e->>'deletion_requested_at' is not null and (e->>'excel_removed_at' is null or e->>'deletion_requested_at' is distinct from e->>'excel_removed_at')))) then
        raise exception '화물번호 %는 삭제함에 있습니다. 먼저 삭제 취소 여부를 확인해 주세요.',item->>'box_number';
      end if;
      kind:='new'; changes:='{}';
    else
      select * into old_row from jsonb_populate_record(null::public.shipments,(select e from jsonb_array_elements(existing) e where (e->>'id')::bigint=chosen));
      changes:=public.lk_excel_import_changes(item,old_row);
      if item->>'box_number' is distinct from old_row.box_number then changes:=changes||jsonb_build_object('box_number',item->>'box_number'); end if;
      kind:=case when old_row.deletion_requested_at is not null then 'restore' when changes<>'{}' then 'update' else 'unchanged' end;
      if kind<>'unchanged' and old_row.data_locked and exists(select 1 from public.shipment_change_requests q where q.shipment_id=chosen and q.status='pending' and q.request_source<>'excel_import') then
        raise exception '잠금 화물 %의 회원 변경 요청을 먼저 처리해 주세요.',old_row.box_number;
      end if;
    end if;
    items:=items||jsonb_build_array(jsonb_build_object('shipment_id',chosen,'status',kind,'box_number',item->>'box_number','excel_row',item->'_row','changes',changes,'current_values',case when chosen is not null then to_jsonb(old_row) else '{}'::jsonb end,'_data',item));
  end loop;
  for item in select e from jsonb_array_elements(existing) e where not (e->>'id')::bigint=any(used) and e->>'deleted_at' is null and e->>'deletion_requested_at' is null loop
    items:=items||jsonb_build_array(jsonb_build_object('shipment_id',item->'id','status','remove','box_number',item->>'box_number','current_values',item));
  end loop;
  token:=md5(auth.uid()::text||p_rows::text||existing::text);
  return jsonb_build_object('preview_token',token,'route',r,'shipment_year',y,'voyage',v,
    'new_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='new'),
    'updated_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='update'),
    'restored_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='restore'),
    'removed_rows',(select count(*) from jsonb_array_elements(items) x where x->>'status'='remove'),
    'unchanged',(select count(*) from jsonb_array_elements(items) x where x->>'status'='unchanged'),
    'items',items);
end $$;


notify pgrst,'reload schema';

