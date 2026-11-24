-- Discount matching only. Keep the same registered row, full phone tokens,
-- member/company precedence, access controls, rates and delivery identities.
create or replace function public.lk_discount_rule_rank(
 p_name text,p_phone text,r_name text,r_company text,r_phone text
) returns integer language plpgsql immutable set search_path='' as $$
declare names text[]; phones text[]; registered text[]; recovered text;
begin
 if public.lk_excel_customer_key(p_name,p_phone) in ('','XX') then return 9999; end if;
 recovered:=coalesce(public.lk_excel_recovered_name(p_name,p_phone),p_name);
 select coalesce(array_agg(distinct v) filter(where v<>''),array[]::text[]) into names
 from unnest(public.lk_discount_name_parts(recovered)) n
 cross join lateral (values(n),(regexp_replace(n,'[0-9]+$',''))) variants(v);
 phones:=array_remove(public.lk_discount_phone_tokens(p_phone),'');
 registered:=array_remove(public.lk_discount_phone_tokens(r_phone),'');
 if cardinality(names)=0 or not (phones&&registered) then return 9999; end if;
 if public.lk_discount_name_parts(r_name)&&names then return 0; end if;
 if public.lk_discount_name_parts(r_company)&&names then return 1; end if;
 return 9999;
end $$;
