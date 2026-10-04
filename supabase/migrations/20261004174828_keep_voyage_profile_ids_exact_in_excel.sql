-- Excel stores only 15 significant decimal digits in numeric cells.
-- Keep deterministic scoped IDs exact through a workbook save/reupload.
create or replace function public.lk_excel_effective_policy(p_route_key text,p_year integer,p_voyage text) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb:=public.lk_excel_base_policy(p_route_key); overrides jsonb; kind text; rows_by_key jsonb; r jsonb; pair record; output jsonb; ordinal bigint;
begin
 if coalesce(p_voyage,'') !~ '^[0-9]{1,3}$' or p_voyage::int=0 then return result; end if;
 select changes into overrides from public.excel_workbook_policies
 where route_key=p_route_key and shipment_year=p_year and voyage=lpad((p_voyage::int)::text,greatest(2,length((p_voyage::int)::text)),'0');
 if overrides is null then return result; end if;
 foreach kind in array array['deliveries','discounts','shares','zones'] loop
  if not (overrides ? kind) then continue; end if;
  rows_by_key:='{}';
  for r in select value from jsonb_array_elements(result->kind) loop if kind='discounts' then r:=r||public.lk_excel_policy_fields(kind,r,r); end if; rows_by_key:=rows_by_key||jsonb_build_object(public.lk_excel_policy_key(kind,r),r); end loop;
  for pair in select * from jsonb_each(overrides->kind) loop
   if pair.value->>'deleted'='true' then rows_by_key:=rows_by_key-pair.key;
   else rows_by_key:=rows_by_key||jsonb_build_object(pair.key,coalesce(rows_by_key->pair.key,jsonb_strip_nulls(pair.value->'identity'))||(pair.value->'patch')||jsonb_build_object('route_key',p_route_key)); end if;
  end loop;
  output:='[]';ordinal:=0;
  for pair in select * from jsonb_each(rows_by_key) order by key loop
   ordinal:=ordinal+1;r:=pair.value;
   if r->>'id' is null then r:=r||jsonb_build_object('id',-(abs(hashtextextended(kind||':'||pair.key,0)%900000000000000)+1)); end if;
   if kind='discounts' then r:=r||jsonb_build_object('discount_percent',coalesce((r->>'regular_discount_percent')::numeric,greatest(0,coalesce((r->>'discount_percent')::numeric,0)-coalesce((r->>'special_discount_percent')::numeric,0)))+coalesce((r->>'special_discount_percent')::numeric,0)); end if;
   output:=output||jsonb_build_array(r);
  end loop;
  result:=jsonb_set(result,array[kind],output);
 end loop;
 result:=jsonb_set(result,'{appearance}',coalesce(result->'appearance','{}')||coalesce(overrides->'appearance','{}'));
 if overrides?'reviews' then result:=jsonb_set(result,'{reviews}',(overrides->'reviews')||coalesce((select jsonb_agg(b) from jsonb_array_elements(result->'reviews') b where not exists(select 1 from jsonb_array_elements(overrides->'reviews') o where o->>'name_key'=b->>'name_key' and o->>'phone_key'=b->>'phone_key')),'[]')); end if;
 return result;
end $$;
