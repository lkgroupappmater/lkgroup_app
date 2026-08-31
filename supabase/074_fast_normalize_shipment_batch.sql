-- 074_fast_normalize_shipment_batch.sql
-- Patch138d
-- normalize_shipment_batch 고속화:
-- 기존 shipment별 PL/pgSQL loop / 반복 full scan 제거.
-- 이름이 있는 화물은 전화번호가 없거나 ????여도 정상 receipt/zone 대상.
-- 이름 없음/명시적 unknown만 XX/F.
--
-- 기존 정상 receipt 번호는 보존하고, XX/빈 receipt만 새 번호 배정.
-- 동일 고객 key = normalized name + normalized phone.
-- 전화번호가 숫자 없는 문자열이면 빈 전화번호로 취급되므로 이름 기준 그룹화.

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
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_xx text;
  v_start integer;
begin
  if coalesce(btrim(p_route),'')='' or p_year is null or v_voyage='' then
    return;
  end if;

  select rd.route_key, coalesce(btrim(rd.receipt_prefix),'')
    into v_route_key, v_prefix
  from public.route_definitions rd
  where rd.display_name=btrim(p_route) or rd.route_key=btrim(p_route)
  order by case when rd.display_name=btrim(p_route) then 0 else 1 end
  limit 1;

  -- route_definitions에 display_name 표기가 달라도 현재 KR routes는 prefix를 안전하게 보완.
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

  -- 대상 batch를 한번 materialize. 이후 반복 full scan을 피합니다.
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

  if not exists(select 1 from _norm_batch) then return; end if;

  create index if not exists _norm_batch_customer_idx on _norm_batch(customer_key);
  create index if not exists _norm_batch_receipt_idx on _norm_batch(old_receipt);

  -- 1) 진짜 unknown만 XX/F. 이름 있는 행은 즉시 recipient_unknown=false.
  update public.shipments s
     set recipient_unknown=b.is_unknown,
         receipt_number=case when b.is_unknown then v_xx else
           case when b.old_receipt=v_xx then '' else b.old_receipt end
         end,
         unloading_zone=case when b.is_unknown then 'F' else s.unloading_zone end
  from _norm_batch b
  where s.id=b.id
    and (
      s.recipient_unknown is distinct from b.is_unknown
      or (b.is_unknown and coalesce(s.receipt_number,'') is distinct from v_xx)
      or (not b.is_unknown and b.old_receipt=v_xx)
      or (b.is_unknown and coalesce(s.unloading_zone,'') is distinct from 'F')
    );

  -- 2) unknown review queue도 set-based.
  insert into public.unmatched_recipient_review_queue(
    shipment_id,status,detected_name,detected_phone,detected_by
  )
  select s.id,'pending',coalesce(s.consignee_name,''),coalesce(s.consignee_phone,''),auth.uid()
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where b.is_unknown
  on conflict (shipment_id) do update set
    status='pending',
    detected_name=excluded.detected_name,
    detected_phone=excluded.detected_phone,
    detected_by=coalesce(excluded.detected_by,public.unmatched_recipient_review_queue.detected_by),
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
  where q.shipment_id=b.id and not b.is_unknown and q.status='pending';

  -- materialized batch의 receipt 상태 갱신.
  update _norm_batch b
     set old_receipt=btrim(coalesce(s.receipt_number,''))
  from public.shipments s
  where s.id=b.id;

  -- 3) 이미 정상 receipt를 가진 동일 고객은 그 receipt를 재사용.
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
          coalesce((regexp_match(b.old_receipt,'(\d+)\s*$'))[1]::integer,2147483647),
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

  -- 4) 새 receipt가 필요한 고객 그룹을 한번에 번호 배정.
  select coalesce(max((regexp_match(btrim(coalesce(s.receipt_number,'')),'(\d+)\s*$'))[1]::integer),0)+1
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
  select customer_key,
    case
      when coalesce(v_prefix,'')='' then 'ID-'||lpad((v_start+rn-1)::text,2,'0')
      when v_route_key in ('kr_la_sea','kr_la_air') then v_prefix||' '||lpad((v_start+rn-1)::text,2,'0')
      else v_prefix||lpad((v_start+rn-1)::text,2,'0')
    end
  from (
    select customer_key,row_number() over(order by min(id))::integer rn
    from _norm_batch b
    where not b.is_unknown
      and not exists(select 1 from _customer_receipt cr where cr.customer_key=b.customer_key)
    group by customer_key
  ) g;

  update public.shipments s
     set receipt_number=nr.receipt
  from _norm_batch b
  join _new_receipts nr on nr.customer_key=b.customer_key
  where s.id=b.id
    and not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')='';

  -- 5) receipt별 총 quantity를 한번 집계해서 Zone 일괄 반영.
  create temporary table if not exists _receipt_qty (
    receipt text primary key,
    qty integer not null
  ) on commit drop;
  truncate _receipt_qty;

  insert into _receipt_qty(receipt,qty)
  select btrim(s.receipt_number),sum(greatest(coalesce(s.quantity,1),1))::integer
  from public.shipments s
  join _norm_batch b on b.id=s.id
  where not b.is_unknown
    and coalesce(btrim(s.receipt_number),'')<>''
  group by btrim(s.receipt_number);

  update public.shipments s
     set unloading_zone=case
       when v_route_key='kr_la_air' then '102'
       when rq.qty>=20 then 'F'
       when rq.qty>=10 then 'C'
       when rq.qty>=5 then 'B'
       else 'A'
     end
  from _norm_batch b
  join _receipt_qty rq on rq.receipt=btrim(s.receipt_number)
  where s.id=b.id
    and not b.is_unknown;

end;
$$;

grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated;
