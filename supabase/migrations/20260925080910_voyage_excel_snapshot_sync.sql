-- A complete, validated voyage workbook is authoritative for administrator imports.
-- The transaction never physically deletes cargo; the existing 30-day bin is used.
alter table public.shipments add column if not exists excel_removed_at timestamptz;

create table public.shipment_excel_sync_runs (
  preview_token text primary key,
  actor_id uuid not null,
  input_hash text not null,
  route text not null,
  shipment_year integer not null,
  voyage text not null,
  created_at timestamptz not null default now(),
  summary jsonb not null
);
create table public.shipment_excel_sync_changes (
  preview_token text not null references public.shipment_excel_sync_runs(preview_token),
  shipment_id bigint not null,
  action text not null check(action in ('new','update','restore','remove')),
  before_values jsonb,
  after_values jsonb not null,
  primary key(preview_token,shipment_id)
);
alter table public.shipment_excel_sync_runs enable row level security;
alter table public.shipment_excel_sync_changes enable row level security;
revoke all on public.shipment_excel_sync_runs,public.shipment_excel_sync_changes from public,anon,authenticated;
grant select on public.shipment_excel_sync_runs,public.shipment_excel_sync_changes to authenticated;
create policy excel_sync_admin_read on public.shipment_excel_sync_runs for select to authenticated
using (public.current_role()='admin' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved' and p.deletion_status='active'));
create policy excel_sync_admin_read on public.shipment_excel_sync_changes for select to authenticated
using (public.current_role()='admin' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.approval_status='approved' and p.deletion_status='active'));

create function public.admin_preview_shipment_excel_sync(p_rows jsonb)
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
      if exists(select 1 from jsonb_array_elements(existing) e where lower(btrim(e->>'box_number'))=lower(item->>'box_number') and (e->>'deleted_at' is not null or e->>'deletion_requested_at' is not null) and e->>'excel_removed_at' is null) then
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

create function public.admin_apply_shipment_excel_sync(p_rows jsonb,p_preview_token text)
returns jsonb language plpgsql security definer set search_path='' set statement_timeout='45s'
as $$
declare
  plan jsonb; item jsonb; payload jsonb; before_row jsonb; result jsonb;
  old_row public.shipments%rowtype; new_row public.shipments%rowtype;
  r text; y integer; v text; prior_flag text:=current_setting('lkgroup.bulk_import',true);
begin
  -- The preview performs the same active administrator check; check before replay too.
  if auth.uid() is null or coalesce(public.current_role(),'')<>'admin' or not exists(select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.approval_status,'approved')='approved' and coalesce(p.deletion_status,'active')='active') then raise exception '총괄 관리자 권한이 필요합니다.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('excel-sync:'||coalesce(p_rows->0->>'route','')||'|'||coalesce(p_rows->0->>'shipment_year','')||'|'||coalesce(p_rows->0->>'voyage',''),0));
  select summary into result from public.shipment_excel_sync_runs where preview_token=p_preview_token and actor_id=auth.uid() and input_hash=md5(p_rows::text);
  if found then return result; end if;
  r:=p_rows->0->>'route'; y:=(p_rows->0->>'shipment_year')::integer; v:=p_rows->0->>'voyage';
  perform 1 from public.shipments s where s.route=r and s.shipment_year=y and s.voyage=v order by s.id for update;
  plan:=public.admin_preview_shipment_excel_sync(p_rows);
  if p_preview_token is null or plan->>'preview_token'<>p_preview_token then raise exception '비교 이후 항차 데이터가 변경되었습니다. 미리보기를 다시 확인해 주세요.'; end if;
  result:=plan-'items';
  insert into public.shipment_excel_sync_runs(preview_token,actor_id,input_hash,route,shipment_year,voyage,summary) values(p_preview_token,auth.uid(),md5(p_rows::text),r,y,v,result);
  perform set_config('lkgroup.bulk_import','1',true);
  -- Free keys before number swaps; rollback restores all keys if any step fails.
  update public.shipments s set import_key=null where s.id in (select (x->>'shipment_id')::bigint from jsonb_array_elements(plan->'items') x where x->>'status' in ('update','restore','remove'));
  for item in select value from jsonb_array_elements(plan->'items') where value->>'status'<>'unchanged' loop
    before_row:=nullif(item->'current_values','{}'::jsonb);
    if item->>'status'<>'new' then
      -- Old Excel review requests are superseded by the administrator's new snapshot.
      update public.shipment_change_requests set status='rejected',review_result='rejected',reviewed_by=auth.uid(),reviewed_at=now()
        where shipment_id=(item->>'shipment_id')::bigint and status='pending' and request_source='excel_import';
    end if;
    if item->>'status'='remove' then
      update public.shipments set deletion_requested_at=now(),deletion_requested_by=auth.uid(),excel_removed_at=now(),updated_at=now()
        where id=(item->>'shipment_id')::bigint returning * into new_row;
    else
      payload:=item->'_data';
      if item->>'status'='new' then
        select * into new_row from jsonb_populate_record(null::public.shipments,payload);
        insert into public.shipments(box_number,invoice_number,route,shipment_year,voyage,import_key,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,received_at,status)
        values(new_row.box_number,coalesce(new_row.invoice_number,''),r,y,v,r||'|'||y||'|'||v||'|'||new_row.box_number,coalesce(new_row.sender_name,''),new_row.consignee_name,new_row.consignee_phone,coalesce(new_row.contents,''),coalesce(new_row.package_type,''),coalesce(new_row.quantity,1),new_row.weight_kg,new_row.length_cm,new_row.width_cm,new_row.height_cm,coalesce(new_row.receipt_number,''),coalesce(new_row.unloading_zone,''),coalesce(new_row.notes,''),new_row.received_at,'registered') returning * into new_row;
      else
        select * into old_row from public.shipments where id=(item->>'shipment_id')::bigint;
        select * into new_row from jsonb_populate_record(old_row,item->'changes');
        update public.shipments set box_number=new_row.box_number,import_key=r||'|'||y||'|'||v||'|'||new_row.box_number,
          invoice_number=new_row.invoice_number,sender_name=new_row.sender_name,consignee_name=new_row.consignee_name,consignee_phone=new_row.consignee_phone,
          contents=new_row.contents,package_type=new_row.package_type,quantity=new_row.quantity,weight_kg=new_row.weight_kg,length_cm=new_row.length_cm,width_cm=new_row.width_cm,height_cm=new_row.height_cm,
          receipt_number=new_row.receipt_number,unloading_zone=new_row.unloading_zone,notes=new_row.notes,received_at=new_row.received_at,
          deletion_requested_at=null,deletion_requested_by=null,excel_removed_at=null,updated_at=now()
          where id=old_row.id returning * into new_row;
      end if;
    end if;
    insert into public.shipment_excel_sync_changes(preview_token,shipment_id,action,before_values,after_values)
      values(p_preview_token,new_row.id,item->>'status',before_row,to_jsonb(new_row));
  end loop;
  perform set_config('lkgroup.bulk_import',coalesce(prior_flag,''),true);
  return result;
end $$;
revoke all on function public.admin_preview_shipment_excel_sync(jsonb),public.admin_apply_shipment_excel_sync(jsonb,text) from public,anon;
grant execute on function public.admin_preview_shipment_excel_sync(jsonb),public.admin_apply_shipment_excel_sync(jsonb,text) to authenticated;
notify pgrst,'reload schema';
