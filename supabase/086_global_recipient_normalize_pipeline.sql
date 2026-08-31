-- 086_global_recipient_normalize_pipeline.sql
-- Patch140: 전 노선 공통 수취인/영수번호/Zone 자동 normalize
--
-- 전제: Patch139(084) 함수가 설치되어 있어야 합니다.
--
-- 규칙
-- 1) 이름+전화 모두 불확실 => true unknown => [prefix]XX / F
-- 2) 한쪽만 불확실 => 이용 가능한 정보로 그룹핑 + 승인관리 대상
-- 3) 이름/전화 정상 => 정상 그룹
-- 4) 전화는 숫자 마지막 8자리로 020/공백/하이픈 표기 차이를 흡수
-- 5) 이름만 있는 행: 동일 이름에 유효전화 그룹이 정확히 1개면 그 그룹에 결합
-- 6) 같은 이름에 유효전화가 여러 개면 이름-only 행은 별도 확인 그룹
-- 7) data_locked=true 행은 값 변경 금지
-- 8) 기존 receipt가 한 identity에만 속한 경우 최대한 유지
-- 9) 오염 receipt(여러 identity 공유)는 unlocked 그룹에 재사용하지 않음
-- 10) KR-LA AIR Zone=102, 나머지 수량 1~4 A / 5~9 B / 10~19 C / 20+ F

create or replace function public.normalize_shipment_batch(p_route text,p_year integer,p_voyage text)
returns void
language plpgsql security definer set search_path=public as $$
declare
  v_route_key text;
  v_prefix text;
  v_voyage text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_next integer;
  r record;
  v_receipt text;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or coalesce(v_voyage,'')='' then return; end if;
  if current_setting('lkgroup.normalizing_shipments',true)='1' then return; end if;
  perform set_config('lkgroup.normalizing_shipments','1',true);

  select rd.route_key,rd.receipt_prefix
  into v_route_key,v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(btrim(v_prefix),'')='' then
    perform set_config('lkgroup.normalizing_shipments','',true);
    return;
  end if;

  drop table if exists pg_temp._ng;
  drop table if exists pg_temp._nr;
  drop table if exists pg_temp._nq;

  create temporary table _ng on commit drop as
  with b as (
    select
      s.id,s.data_locked,s.receipt_number,
      greatest(coalesce(s.quantity,1),1)::integer qty,
      lower(regexp_replace(btrim(coalesce(s.consignee_name,'')),'\s+',' ','g')) name_key,
      regexp_replace(coalesce(s.consignee_phone,''),'[^0-9]','','g') digits,
      public.lk_recipient_name_uncertain(s.consignee_name) name_bad,
      public.lk_recipient_phone_uncertain(s.consignee_phone) phone_bad,
      public.lk_recipient_true_unknown(s.consignee_name,s.consignee_phone) is_unknown
    from public.shipments s
    where s.route=p_route and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  ), p as (
    select *,case when not phone_bad and length(digits)>=7 then right(digits,8) else '' end phone_key
    from b
  ), st as (
    select name_key,count(distinct nullif(phone_key,'')) phone_count,min(nullif(phone_key,'')) only_phone
    from p where not is_unknown and not name_bad group by name_key
  )
  select p.*,
    case
      when is_unknown then '__UNKNOWN__:'||id::text
      when not phone_bad and phone_key<>'' then
        case when name_bad then 'PHONE|'||phone_key else 'NAMEPHONE|'||name_key||'|'||phone_key end
      when not name_bad and coalesce(st.phone_count,0)=1 then 'NAMEPHONE|'||name_key||'|'||st.only_phone
      when not name_bad then 'NAME|'||name_key
      else '__UNKNOWN__:'||id::text
    end identity_key
  from p left join st using(name_key);

  -- true unknown: locked는 보호, unlocked만 XX/F
  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case when v_route_key in ('kr_la_sea','kr_la_air')
                          then btrim(v_prefix)||' XX' else btrim(v_prefix)||'XX' end,
      unloading_zone='F'
  from _ng g
  where s.id=g.id and g.is_unknown and not coalesce(g.data_locked,false);

  -- 정상/불확실(한쪽 정보 있음)은 unknown 아님
  update public.shipments s set recipient_unknown=false
  from _ng g
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false);

  create temporary table _nr(identity_key text primary key,receipt_number text);

  -- locked 행은 확정 anchor. 같은 identity의 unlocked 행도 여기에 붙인다.
  insert into _nr(identity_key,receipt_number)
  select identity_key,min(btrim(receipt_number))
  from _ng
  where not is_unknown and coalesce(data_locked,false)
    and coalesce(btrim(receipt_number),'')<>''
  group by identity_key
  on conflict(identity_key) do nothing;

  -- 기존 receipt가 오직 한 identity에서만 사용된 경우에만 보존.
  insert into _nr(identity_key,receipt_number)
  select g.identity_key,min(btrim(g.receipt_number))
  from _ng g
  join (
    select btrim(receipt_number) receipt,count(distinct identity_key) n
    from _ng
    where not is_unknown and coalesce(btrim(receipt_number),'')<>''
    group by btrim(receipt_number)
    having count(distinct identity_key)=1
  ) u on u.receipt=btrim(g.receipt_number)
  where not g.is_unknown and not coalesce(g.data_locked,false)
    and not exists(select 1 from _nr x where x.identity_key=g.identity_key)
  group by g.identity_key
  on conflict(identity_key) do nothing;

  select coalesce(max((m)[1]::integer),0)+1 into v_next
  from public.shipments s
  cross join lateral regexp_match(btrim(coalesce(s.receipt_number,'')),'(\d+)\s*$') m
  where s.route=p_route and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage;
  v_next:=greatest(coalesce(v_next,1),1);

  -- receipt가 없는 identity만 신규 번호. 기존/locked 번호와 충돌하지 않게 증가.
  for r in
    select identity_key,min(id) first_id
    from _ng g
    where not is_unknown
      and not exists(select 1 from _nr x where x.identity_key=g.identity_key)
    group by identity_key
    order by min(id)
  loop
    loop
      if v_route_key in ('kr_la_sea','kr_la_air') then
        v_receipt:=btrim(v_prefix)||' '||lpad(v_next::text,2,'0');
      else
        v_receipt:=btrim(v_prefix)||lpad(v_next::text,2,'0');
      end if;
      v_next:=v_next+1;
      exit when not exists(
        select 1 from public.shipments s
        where s.route=p_route and s.shipment_year=p_year
          and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
          and btrim(coalesce(s.receipt_number,''))=v_receipt
      );
    end loop;
    insert into _nr values(r.identity_key,v_receipt);
  end loop;

  update public.shipments s
  set receipt_number=n.receipt_number
  from _ng g join _nr n using(identity_key)
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false);

  create temporary table _nq on commit drop as
  select btrim(s.receipt_number) receipt,sum(g.qty)::integer total_qty
  from _ng g join public.shipments s on s.id=g.id
  where not g.is_unknown and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  -- locked 행의 Zone은 보호. unlocked만 최종 그룹 총수량으로 Zone 갱신.
  update public.shipments s
  set unloading_zone=case
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A' end
  from _ng g,_nq q
  where s.id=g.id and not g.is_unknown and not coalesce(g.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
  perform set_config('lkgroup.normalizing_shipments','',true);
  raise;
end $$;

revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated,service_role;

-- trigger도 공통 normalize를 사용. 내부 normalize UPDATE 재귀 차단.
create or replace function public.shipments_auto_normalize_trigger()
returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if current_setting('lkgroup.normalizing_shipments',true)='1' or pg_trigger_depth()>1
    then return coalesce(new,old); end if;
  if tg_op='DELETE' then
    perform public.normalize_shipment_batch(old.route,old.shipment_year,old.voyage);
    return old;
  end if;
  perform public.normalize_shipment_batch(new.route,new.shipment_year,new.voyage);
  if tg_op='UPDATE' and (
    old.route is distinct from new.route or old.shipment_year is distinct from new.shipment_year
    or old.voyage is distinct from new.voyage
  ) then
    perform public.normalize_shipment_batch(old.route,old.shipment_year,old.voyage);
  end if;
  return new;
end $$;

drop trigger if exists trg_shipments_auto_normalize on public.shipments;
create trigger trg_shipments_auto_normalize
after insert or update of route,shipment_year,voyage,consignee_name,consignee_phone,receipt_number,quantity,deletion_requested_at,data_locked or delete
on public.shipments for each row execute function public.shipments_auto_normalize_trigger();
