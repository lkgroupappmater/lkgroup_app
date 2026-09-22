-- Historical repair. Dry-run by default; already repaired rows will fail the 43-row guard.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated')::text,true)
from public.profiles where role='admin' and approval_status='approved'
  and coalesce(deletion_status,'active')='active' limit 1;
create temporary table _zone_repair_targets on commit drop as
select s.id, a.id approved_request_id, a.zone
from public.shipments s
cross join lateral (
  select q.id, btrim((coalesce(q.changes,'{}')||coalesce(q.admin_changes,'{}'))->>'unloading_zone') zone
  from public.shipment_change_requests q
  where q.shipment_id=s.id and q.status='approved'
    and (coalesce(q.changes,'{}')||coalesce(q.admin_changes,'{}'))?'unloading_zone'
  order by q.reviewed_at desc nulls last,q.id desc limit 1
) a
where s.route='한국->라오스 해상' and s.shipment_year=2026 and s.voyage='09'
  and s.consignee_name='뷰티판다' and s.deleted_at is null and s.deletion_requested_at is null
  and not s.data_locked and s.unloading_zone='F' and a.zone='ST';

do $guard$
begin
 if (select count(*) from _zone_repair_targets)<>43 then raise exception 'Expected exactly 43 already-approved Zone repairs; review concurrent changes'; end if;
 perform 1 from public.shipments s join _zone_repair_targets t on t.id=s.id for update of s;
end $guard$;
create temporary table _zone_repair_before on commit drop as
select s.id, to_jsonb(s) original from public.shipments s
where s.route='한국->라오스 해상' and s.shipment_year=2026 and s.voyage='09';
create temporary table _zone_money_before on commit drop as
select md5(coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.customer_rate_overrides t),'[]')||
  coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.receipt_discount_overrides t),'[]')||
  coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.receipt_extra_costs t),'[]')) fingerprint;
select set_config('lkgroup.bulk_import','1',true);
update public.shipments s
set unloading_zone=t.zone, unloading_zone_override=t.zone, updated_at=now()
from _zone_repair_targets t where s.id=t.id and s.unloading_zone='F';
select set_config('lkgroup.bulk_import','',true);
select public.admin_finalize_excel_batch_rules_fast('한국->라오스 해상',2026,'09');
select public.admin_finalize_excel_import_preserve_layout('한국->라오스 해상',2026,'09');
do $verify$
declare money_after text;
begin
 if (select count(*) from public.shipments s join _zone_repair_targets t on t.id=s.id
   where s.unloading_zone='ST' and s.unloading_zone_override='ST')<>43 then raise exception 'Recalculation lost restored ST'; end if;
 if exists(select 1 from public.shipments s join _zone_repair_before b on b.id=s.id
   where not exists(select 1 from _zone_repair_targets t where t.id=s.id) and to_jsonb(s) is distinct from b.original) then
   raise exception 'Unrelated voyage rows changed'; end if;
 if exists(select 1 from public.shipments s join _zone_repair_before b on b.id=s.id
   join _zone_repair_targets t on t.id=s.id
   where (to_jsonb(s)-array['unloading_zone','unloading_zone_override','updated_at']) is distinct from
     (b.original-array['unloading_zone','unloading_zone_override','updated_at'])) then
   raise exception 'Target invoice, receipt, notes, quantity, weights or other fields changed'; end if;
 select md5(coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.customer_rate_overrides t),'[]')||
  coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.receipt_discount_overrides t),'[]')||
  coalesce((select jsonb_agg(to_jsonb(t) order by t.id)::text from public.receipt_extra_costs t),'[]')) into money_after;
 if money_after is distinct from (select fingerprint from _zone_money_before) then raise exception 'Discount or charge data changed'; end if;
end $verify$;

rollback;
