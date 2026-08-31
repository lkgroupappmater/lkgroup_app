-- 082_rebuild_v08_receipt_groups_single_statement.sql
-- Patch138h: temp table/session 문제 제거.
-- 전체 작업을 하나의 DO statement 안에서 수행합니다.

do $$
begin
  perform set_config('lkgroup.normalizing_shipments','1',true);

  drop table if exists pg_temp._v08_identity;
  drop table if exists pg_temp._v08_receipts;
  drop table if exists pg_temp._v08_qty;

  create temporary table _v08_identity on commit drop as
  with base as (
    select s.id,
           greatest(coalesce(s.quantity,1),1)::integer qty,
           public.shipment_name_is_explicit_unknown(s.consignee_name) is_unknown,
           lower(regexp_replace(btrim(coalesce(s.consignee_name,'')),'\s+',' ','g')) name_key,
           regexp_replace(coalesce(s.consignee_phone,''),'[^0-9]','','g') digits
    from public.shipments s
    where s.route='한국->라오스 해상'
      and s.shipment_year=2026
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')='08'
      and s.deletion_requested_at is null
  ),
  phones as (
    select *, case when length(digits)>=7 then right(digits,8) else '' end phone_key
    from base
  ),
  stats as (
    select name_key,
           count(distinct nullif(phone_key,'')) valid_phone_count,
           min(nullif(phone_key,'')) only_phone_key
    from phones
    where not is_unknown
    group by name_key
  )
  select p.id,p.qty,p.is_unknown,
         case
           when p.is_unknown then '__UNKNOWN__'
           when p.phone_key<>'' then p.name_key||'|'||p.phone_key
           when coalesce(st.valid_phone_count,0)=1 then p.name_key||'|'||st.only_phone_key
           else p.name_key||'|NO_PHONE'
         end identity_key
  from phones p
  left join stats st using(name_key);

  create temporary table _v08_receipts on commit drop as
  select identity_key,
         'LKS '||lpad(row_number() over(order by first_id)::text,2,'0') receipt_number
  from (
    select identity_key,min(id) first_id
    from _v08_identity
    where not is_unknown
    group by identity_key
  ) g;

  update public.shipments s
  set recipient_unknown=false, receipt_number=r.receipt_number
  from _v08_identity i, _v08_receipts r
  where s.id=i.id
    and not i.is_unknown
    and r.identity_key=i.identity_key;

  update public.shipments s
  set recipient_unknown=true, receipt_number='LKS XX', unloading_zone='F'
  from _v08_identity i
  where s.id=i.id and i.is_unknown;

  create temporary table _v08_qty on commit drop as
  select r.receipt_number,sum(i.qty)::integer total_qty
  from _v08_identity i, _v08_receipts r
  where not i.is_unknown and r.identity_key=i.identity_key
  group by r.receipt_number;

  update public.shipments s
  set unloading_zone=case
    when q.total_qty>=20 then 'F'
    when q.total_qty>=10 then 'C'
    when q.total_qty>=5 then 'B'
    else 'A'
  end
  from _v08_qty q
  where s.route='한국->라오스 해상'
    and s.shipment_year=2026
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')='08'
    and s.deletion_requested_at is null
    and s.recipient_unknown=false
    and s.receipt_number=q.receipt_number;

  perform set_config('lkgroup.normalizing_shipments','',true);
exception when others then
  perform set_config('lkgroup.normalizing_shipments','',true);
  raise;
end $$;
