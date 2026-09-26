-- Shared document tax rule. This calculation exposes no customer records.
create or replace function public.document_vat_context(p_route_key text,p_remark text)
returns jsonb language sql immutable security invoker set search_path='' as $body$
 with normalized as (
  select regexp_replace(coalesce(p_remark,''),'[[:space:]' || chr(160) || chr(12288) || ']','','g') as note
 ), flags as (
  select note like '%세금계산서%' as invoice,
   note like '%영세율%' as zero_rate,
   coalesce(p_route_key in ('kr_la_sea','kr_la_air'),false) as supported
  from normalized
 )
 select jsonb_build_object(
  'tax_invoice',invoice,'vat_applicable',invoice and supported,
  'zero_rated',invoice and zero_rate,
  'vat_rate',case when supported and invoice and not zero_rate then 0.1 else 0 end,
  'tax_remark',case when not invoice then '' when zero_rate then '영세율 세금 계산서' else '세금 계산서' end
 ) from flags;
$body$;
revoke all on function public.document_vat_context(text,text) from public;
grant execute on function public.document_vat_context(text,text) to anon,authenticated,service_role;

-- Quotes have no receipt yet. Resolve only the signed-in customer's existing
-- Remark rules, using the same name/company/phone matching as cargo imports.
-- Anonymous quotes keep their existing untaxed behavior.
create or replace function public.my_freight_tax_context(p_route_key text)
returns jsonb language plpgsql stable security definer set search_path='' as $body$
declare profile public.profiles%rowtype; note text := ''; route_label text;
begin
 if auth.uid() is not null then
  select * into profile from public.profiles where id=auth.uid()
   and approval_status='approved' and deletion_status='active';
  if found then
   select display_name into route_label from public.route_definitions where route_key=p_route_key;
   if route_label is not null then
    note:=public.compute_shipment_special_note(route_label,profile.name,profile.phone);
    if nullif(btrim(profile.company),'') is not null then
     note:=concat_ws(' / ',note,public.compute_shipment_special_note(route_label,profile.company,profile.phone));
    end if;
   end if;
  end if;
 end if;
 return public.document_vat_context(p_route_key,note);
end;
$body$;
revoke all on function public.my_freight_tax_context(text) from public;
grant execute on function public.my_freight_tax_context(text) to anon,authenticated,service_role;
notify pgrst,'reload schema';
