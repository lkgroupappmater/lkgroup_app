-- 071_fix_normal_cargo_receipt_zone_auto_assignment.sql
-- Patch131: 정상 이름+전화번호 화물이 회원 미등록이라는 이유만으로 XX/F가 되는 문제 수정.
-- 운임/할인/문서/화면 디자인은 변경하지 않습니다.


create or replace function public.refresh_recipient_unknown_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n text := btrim(coalesce(new.consignee_name, ''));
  p text := public.normalize_phone(new.consignee_phone);
  explicit_unknown boolean;
begin
  if new.recipient_unknown_confirmed_at is not null then
    new.recipient_unknown := false;
    return new;
  end if;

  explicit_unknown :=
    n = ''
    or lower(n) like '%수취인 불명%'
    or lower(n) like '%데이타 불문명%'
    or lower(n) like '%데이터 불문명%'
    or lower(n) like '%unknown%'
    or lower(n) like '%미상%';

  -- Patch131: 회원등록/identity 매칭 실패 자체를 불명 사유로 사용하지 않음.
  new.recipient_unknown := explicit_unknown or p = '';
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

  -- 먼저 현재 고객정보 기준으로 known/unknown 재판정.
  for r in
    select s.id, s.consignee_name, s.consignee_phone, s.recipient_unknown_confirmed_at
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  loop
    -- Patch131:
    -- 앱 회원/identity 등록 여부는 '수취인 불명' 판정 조건이 아닙니다.
    -- 정상 이름 + 전화번호가 있으면 일반 화물로 보고 영수번호/구획을 자동 계산합니다.
    -- 명시적인 불명 표기 또는 이름/전화번호 누락만 XX / F로 유지합니다.
    v_is_unknown :=
      r.recipient_unknown_confirmed_at is null
      and (
        coalesce(btrim(r.consignee_name),'')=''
        or public.normalize_phone(r.consignee_phone)=''
        or lower(btrim(coalesce(r.consignee_name,''))) like '%수취인 불명%'
        or lower(btrim(coalesce(r.consignee_name,''))) like '%데이타 불문명%'
        or lower(btrim(coalesce(r.consignee_name,''))) like '%데이터 불문명%'
        or lower(btrim(coalesce(r.consignee_name,''))) like '%unknown%'
        or lower(btrim(coalesce(r.consignee_name,''))) like '%미상%'
      );

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

  -- 숫자 영수번호는 known cargo만 기준으로 이어감. XX는 번호 계산에서 제외.
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

  -- known cargo Zone 재계산. unknown은 항상 F 유지.
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


-- 현재 이미 XX / F로 잘못 들어간 정상 이름+전화번호 화물도 즉시 재정리합니다.
do $$
declare
  r record;
begin
  for r in
    select distinct s.route, s.shipment_year, s.voyage
    from public.shipments s
    where s.deletion_requested_at is null
      and coalesce(btrim(s.consignee_name),'') <> ''
      and public.normalize_phone(s.consignee_phone) <> ''
      and lower(btrim(coalesce(s.consignee_name,''))) not like '%수취인 불명%'
      and lower(btrim(coalesce(s.consignee_name,''))) not like '%데이타 불문명%'
      and lower(btrim(coalesce(s.consignee_name,''))) not like '%데이터 불문명%'
      and lower(btrim(coalesce(s.consignee_name,''))) not like '%unknown%'
      and lower(btrim(coalesce(s.consignee_name,''))) not like '%미상%'
      and coalesce(s.recipient_unknown,false) = true
  loop
    perform public.normalize_shipment_batch(r.route, r.shipment_year, r.voyage);
  end loop;
end;
$$;

grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated;
