-- Production-safe regression: no fixtures or retained writes.
begin;
do $$
declare before_hash text; after_hash text; r record;
begin
 if public.lk_customer_display_code(68)<>'LK 0068'
 or public.lk_customer_statement_code(68,false)<>'0068'
 or public.lk_customer_statement_code(68,true)<>'9068'
 or public.lk_customer_statement_code(1234,true)<>'91234' then
   raise exception 'Customer ID display regression';
 end if;
 if public.lk_uses_customer_id_receipts('kr_la_sea',2026,'09')
 or not public.lk_uses_customer_id_receipts('kr_la_sea',2026,'10')
 or public.lk_uses_customer_id_receipts('kr_la_air',2026,'18')
 or not public.lk_uses_customer_id_receipts('kr_la_air',2026,'19')
 or public.lk_uses_customer_id_receipts('kr_la_sea',2025,'12')
 or not public.lk_uses_customer_id_receipts('kr_la_sea',2027,'01') then
   raise exception 'Issued/future voyage boundary regression';
 end if;
 select md5(jsonb_agg(to_jsonb(s) order by s.id)::text) into before_hash
 from public.shipments s where not public.lk_uses_customer_id_receipts(s.route,s.shipment_year,s.voyage);
 for r in select distinct route,shipment_year,voyage from public.shipments s
 where not public.lk_uses_customer_id_receipts(s.route,s.shipment_year,s.voyage) loop
   perform public.normalize_shipment_batch(r.route,r.shipment_year,r.voyage);
 end loop;
 select md5(jsonb_agg(to_jsonb(s) order by s.id)::text) into after_hash
 from public.shipments s where not public.lk_uses_customer_id_receipts(s.route,s.shipment_year,s.voyage);
 if before_hash is distinct from after_hash then raise exception 'Historical shipment changed'; end if;
end $$;
rollback;
