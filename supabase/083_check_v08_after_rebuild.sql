-- 083_check_v08_after_rebuild.sql
select receipt_number,
       count(*) boxes,
       sum(greatest(coalesce(quantity,1),1)) total_qty,
       min(unloading_zone) zone,
       string_agg(distinct consignee_name,' / ' order by consignee_name) names
from public.shipments
where route='한국->라오스 해상'
  and shipment_year=2026
  and lpad(regexp_replace(coalesce(voyage,''),'[^0-9]','','g'),2,'0')='08'
  and deletion_requested_at is null
group by receipt_number
order by coalesce((regexp_match(receipt_number,'(\d+)\s*$'))[1]::integer,2147483647),receipt_number;
