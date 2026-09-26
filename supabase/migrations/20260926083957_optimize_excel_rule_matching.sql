-- The inlined SQL CASE expressions recalculated name/customer keys for each
-- comparison in every discount and statement rule. Keep the existing ranking
-- exactly, but normalize each input once per call. No timeout/approval change.
create or replace function public.lk_excel_match_name(p_name text,p_phone text)
returns text language plpgsql immutable set search_path to 'public' as $function$
declare recovered text; identity_key text;
begin
 recovered:=public.lk_excel_recovered_name(p_name,p_phone);
 if recovered is not null then return public.lk_excel_name(recovered); end if;
 identity_key:=public.lk_excel_customer_key(p_name,p_phone);
 return case when left(identity_key,2)='N|' then substring(identity_key from 3) else '' end;
end $function$;

create or replace function public.lk_excel_rule_rank(p_name text,p_phone text,r_name text,r_phone text)
returns integer language plpgsql immutable set search_path to 'public' as $function$
declare identity_key text; recovered text; n text; p text; rn text; rp text;
begin
 identity_key:=public.lk_excel_customer_key(p_name,p_phone);
 if identity_key in ('','XX') then return 9999; end if;
 recovered:=public.lk_excel_recovered_name(p_name,p_phone);
 n:=case when recovered is not null then public.lk_excel_name(recovered)
   when left(identity_key,2)='N|' then substring(identity_key from 3) else '' end;
 p:=public.lk_excel_phone(p_phone);
 rn:=public.lk_excel_name(r_name);
 rp:=public.lk_excel_phone(r_phone);
 return case when n<>'' and n=rn and p<>'' and p=rp then 0
  when n<>'' and n=rn then 1
  when p<>'' and p=rp then 2
  when n<>'' and rn<>'' and (position(n in rn)>0 or position(rn in n)>0) then 3
  else 9999 end;
end $function$;
notify pgrst,'reload schema';
