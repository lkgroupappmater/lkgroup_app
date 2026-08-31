-- 078_fix_fast_normalize_zone_update_alias.sql
-- Patch138f
-- Patch138e의 fast normalize 마지막 Zone UPDATE에서
-- PostgreSQL UPDATE ... FROM JOIN 내부에서 target alias s를 JOIN ON에서 참조한 오류(42P01) 수정.
--
-- 잘못된 형태:
--   from _norm_batch b
--   join _receipt_qty rq on rq.receipt=btrim(s.receipt_number)
--
-- 수정:
--   from _norm_batch b, _receipt_qty rq
--   where s.id=b.id
--     and rq.receipt=btrim(s.receipt_number)

create or replace function public.normalize_shipment_batch_fast_impl(
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
    return;
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
$$;

revoke all on function public.normalize_shipment_batch_fast_impl(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch_fast_impl(text,integer,text)
  to authenticated, service_role;
