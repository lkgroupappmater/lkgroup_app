create or replace function public.normalize_shipment_batch(p_route text,p_year integer,p_voyage text) returns void
language plpgsql security definer set search_path=public as $$
declare
 v_route_key text; v_receipt_prefix text;
 v_voyage text:=lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
 v_next integer:=1; r record; v_existing text; v_receipt text; v_count integer;
begin
 if coalesce(trim(p_route),'')='' or p_year is null or coalesce(trim(v_voyage),'')='' then return; end if;
 select rd.route_key,rd.receipt_prefix into v_route_key,v_receipt_prefix
 from public.route_definitions rd where rd.display_name=trim(p_route) or rd.route_key=trim(p_route)
 order by case when rd.display_name=trim(p_route) then 0 else 1 end limit 1;
 if coalesce(trim(v_receipt_prefix),'')='' then return; end if;

 select coalesce(max((m)[1]::integer),0)+1 into v_next
 from public.shipments s
 cross join lateral regexp_match(trim(coalesce(s.receipt_number,'')),'(\d+)\s*$') m
 where s.route=p_route and s.shipment_year=p_year
 and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage;
 if v_next is null or v_next<1 then v_next:=1; end if;

 for r in select s.id,lower(trim(coalesce(s.consignee_name,''))) customer_name,
 regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g') customer_phone
 from public.shipments s where s.route=p_route and s.shipment_year=p_year
 and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
 and coalesce(trim(s.receipt_number),'')='' and s.deletion_requested_at is null
 order by s.created_at nulls last,s.id loop
   if coalesce(r.customer_name,'')='' and coalesce(r.customer_phone,'')='' then continue; end if;
   select trim(s.receipt_number) into v_existing from public.shipments s
   where s.route=p_route and s.shipment_year=p_year
   and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
   and coalesce(trim(s.receipt_number),'')<>''
   and lower(trim(coalesce(s.consignee_name,'')))=r.customer_name
   and regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g')=r.customer_phone
   and s.deletion_requested_at is null order by s.id limit 1;
   if coalesce(v_existing,'')<>'' then v_receipt:=v_existing;
   else
     if v_route_key in ('kr_la_sea','kr_la_air') then v_receipt:=trim(v_receipt_prefix)||' '||lpad(v_next::text,2,'0');
     else v_receipt:=trim(v_receipt_prefix)||lpad(v_next::text,2,'0'); end if;
     v_next:=v_next+1;
   end if;
   update public.shipments set receipt_number=v_receipt where id=r.id;
 end loop;

 for r in select s.receipt_number,sum(greatest(coalesce(s.quantity,1),1))::integer qty
 from public.shipments s where s.route=p_route and s.shipment_year=p_year
 and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
 and coalesce(trim(s.receipt_number),'')<>'' and s.deletion_requested_at is null group by s.receipt_number loop
   v_count:=r.qty;
   update public.shipments s set unloading_zone=case when v_route_key='kr_la_air' then '102'
     when v_count>=20 then 'F' when v_count>=10 then 'C' when v_count>=5 then 'B' else 'A' end
   where s.route=p_route and s.shipment_year=p_year
   and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
   and s.receipt_number=r.receipt_number and s.deletion_requested_at is null;
 end loop;
end $$;
revoke all on function public.normalize_shipment_batch(text,integer,text) from public;
grant execute on function public.normalize_shipment_batch(text,integer,text) to authenticated,service_role;

create or replace function public.shipments_auto_normalize_trigger() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if pg_trigger_depth()>1 then return coalesce(new,old); end if;
 if tg_op='DELETE' then perform public.normalize_shipment_batch(old.route,old.shipment_year,old.voyage); return old; end if;
 perform public.normalize_shipment_batch(new.route,new.shipment_year,new.voyage);
 if tg_op='UPDATE' and (old.route is distinct from new.route or old.shipment_year is distinct from new.shipment_year
 or old.voyage is distinct from new.voyage or old.receipt_number is distinct from new.receipt_number
 or old.consignee_name is distinct from new.consignee_name or old.consignee_phone is distinct from new.consignee_phone) then
   perform public.normalize_shipment_batch(old.route,old.shipment_year,old.voyage);
 end if;
 return new;
end $$;

drop trigger if exists trg_shipments_auto_normalize on public.shipments;
create trigger trg_shipments_auto_normalize after insert or update of route,shipment_year,voyage,consignee_name,consignee_phone,receipt_number,quantity,deletion_requested_at or delete
on public.shipments for each row execute function public.shipments_auto_normalize_trigger();

do $$ declare b record; begin
 for b in select distinct route,shipment_year,voyage from public.shipments
 where coalesce(trim(route),'')<>'' and shipment_year is not null and coalesce(trim(voyage),'')<>'' loop
   perform public.normalize_shipment_batch(b.route,b.shipment_year,b.voyage);
 end loop;
end $$;
