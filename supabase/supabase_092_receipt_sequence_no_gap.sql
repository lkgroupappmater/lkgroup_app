-- 092_receipt_sequence_no_gap.sql
-- Patch160
-- 목적:
-- 1) 자동 생성 영수번호가 MAX+1로만 뛰지 않고, 현재 사용 가능한 가장 작은 번호부터 사용
-- 2) 기존 잠금/수동 영수번호는 건드리지 않음
-- 3) 새 화물/수취인 정상화/재업로드/관리자 수정 등 normalize를 타는 모든 경로에 공통 적용
--
-- 중요:
-- 기존에 이미 부여된 영수번호를 강제로 재번호하지 않습니다.
-- 즉, 잠금/수동 분리 영수번호의 의도를 보존하면서 "앞으로 생성되는 자동 번호"가 빈 번호를 먼저 채웁니다.

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
  v_prefix text;
  v_voyage text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_next integer;
  r record;
  v_receipt text;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or coalesce(v_voyage,'')='' then
    return;
  end if;
  if current_setting('lkgroup.normalizing_shipments',true)='1' then
    return;
  end if;
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
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  ), p as (
    select *,
      case
        when not phone_bad and length(digits)>=7 then right(digits,8)
        else ''
      end phone_key
    from b
  ), st as (
    select
      name_key,
      count(distinct nullif(phone_key,'')) phone_count,
      min(nullif(phone_key,'')) only_phone
    from p
    where not is_unknown and not name_bad
    group by name_key
  )
  select p.*,
    case
      when is_unknown then '__UNKNOWN__:'||id::text
      when not phone_bad and phone_key<>'' then
        case
          when name_bad then 'PHONE|'||phone_key
          else 'NAMEPHONE|'||name_key||'|'||phone_key
        end
      when not name_bad and coalesce(st.phone_count,0)=1
        then 'NAMEPHONE|'||name_key||'|'||st.only_phone
      when not name_bad then 'NAME|'||name_key
      else '__UNKNOWN__:'||id::text
    end identity_key
  from p
  left join st using(name_key);

  -- true unknown: 잠금 데이터는 보호, unlocked만 XX/F
  update public.shipments s
  set recipient_unknown=true,
      receipt_number=case
        when v_route_key in ('kr_la_sea','kr_la_air')
          then btrim(v_prefix)||' XX'
        else btrim(v_prefix)||'XX'
      end,
      unloading_zone='F'
  from _ng g
  where s.id=g.id
    and g.is_unknown
    and not coalesce(g.data_locked,false);

  -- 정상/불확실(한쪽 정보 있음)은 unknown 아님
  update public.shipments s
  set recipient_unknown=false
  from _ng g
  where s.id=g.id
    and not g.is_unknown
    and not coalesce(g.data_locked,false);

  create temporary table _nr(
    identity_key text primary key,
    receipt_number text
  ) on commit drop;

  -- 잠금 행은 확정 anchor
  insert into _nr(identity_key,receipt_number)
  select identity_key,min(btrim(receipt_number))
  from _ng
  where not is_unknown
    and coalesce(data_locked,false)
    and coalesce(btrim(receipt_number),'')<>''
  group by identity_key
  on conflict(identity_key) do nothing;

  -- 기존 receipt가 한 identity에만 사용된 경우 최대한 유지
  insert into _nr(identity_key,receipt_number)
  select g.identity_key,min(btrim(g.receipt_number))
  from _ng g
  join (
    select btrim(receipt_number) receipt,count(distinct identity_key) n
    from _ng
    where not is_unknown
      and coalesce(btrim(receipt_number),'')<>''
    group by btrim(receipt_number)
    having count(distinct identity_key)=1
  ) u on u.receipt=btrim(g.receipt_number)
  where not g.is_unknown
    and not coalesce(g.data_locked,false)
    and not exists(
      select 1 from _nr x where x.identity_key=g.identity_key
    )
  group by g.identity_key
  on conflict(identity_key) do nothing;

  -- Patch160 핵심:
  -- MAX(receipt)+1이 아니라 1부터 시작해 "현재 비어 있는 가장 작은 번호"를 찾습니다.
  -- 기존/잠금/수동 영수번호는 그대로 두고 신규 자동 그룹에만 적용됩니다.
  v_next:=1;

  for r in
    select identity_key,min(id) first_id
    from _ng g
    where not is_unknown
      and not exists(
        select 1 from _nr x where x.identity_key=g.identity_key
      )
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

      exit when
        not exists(
          select 1
          from public.shipments s
          where s.route=p_route
            and s.shipment_year=p_year
            and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
            and s.deletion_requested_at is null
            and btrim(coalesce(s.receipt_number,''))=v_receipt
        )
        and not exists(
          select 1
          from _nr n
          where btrim(coalesce(n.receipt_number,''))=v_receipt
        );
    end loop;

    insert into _nr(identity_key,receipt_number)
    values(r.identity_key,v_receipt);
  end loop;

  update public.shipments s
  set receipt_number=n.receipt_number
  from _ng g
  join _nr n using(identity_key)
  where s.id=g.id
    and not g.is_unknown
    and not coalesce(g.data_locked,false);

  create temporary table _nq on commit drop as
  select
    btrim(s.receipt_number) receipt,
    sum(g.qty)::integer total_qty
  from _ng g
  join public.shipments s on s.id=g.id
  where not g.is_unknown
    and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  -- 잠금 행 Zone 보호, unlocked만 최종 그룹 총수량으로 갱신
  update public.shipments s
  set unloading_zone=case
    when v_route_key='kr_la_air' then '102'
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from _ng g,_nq q
  where s.id=g.id
    and not g.is_unknown
    and not coalesce(g.data_locked,false)
    and q.receipt=btrim(s.receipt_number);

  perform set_config('lkgroup.normalizing_shipments','',true);

exception when others then
  perform set_config('lkgroup.normalizing_shipments','',true);
  raise;
end
$$;

revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text)
  to authenticated,service_role;


-- 관리자 확인용: 특정 항차에서 실제로 비어 있는 영수번호 숫자를 확인할 수 있습니다.
-- 데이터는 수정하지 않습니다.
create or replace function public.admin_receipt_number_gaps(
  p_route text,
  p_year integer,
  p_voyage text
)
returns table(missing_number integer)
language sql
security definer
set search_path=public
as $$
  with nums as (
    select distinct
      ((regexp_match(btrim(coalesce(s.receipt_number,'')),'(\d+)\s*$'))[1])::integer n
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')
          =lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0')
      and s.deletion_requested_at is null
      and coalesce(s.recipient_unknown,false)=false
      and btrim(coalesce(s.receipt_number,''))<>''
  ),
  mx as (
    select coalesce(max(n),0) max_n from nums
  )
  select g
  from mx
  cross join lateral generate_series(1,mx.max_n) g
  where not exists(select 1 from nums where nums.n=g)
  order by g
$$;

revoke all on function public.admin_receipt_number_gaps(text,integer,text) from public;
grant execute on function public.admin_receipt_number_gaps(text,integer,text)
  to authenticated,service_role;
