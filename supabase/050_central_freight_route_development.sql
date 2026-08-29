-- 050_central_freight_route_development.sql
create table if not exists public.route_definitions(
 route_key text primary key, display_name text not null unique, status text not null default 'active' check(status in('draft','active','disabled')),
 base_route_key text, company_name text not null default '', phone text not null default '', address text not null default '',
 box_prefix text not null default '', receipt_prefix text not null default '', volumetric_factor numeric not null default 0.00022,
 minimum_charge numeric not null default 0, created_by uuid references auth.users(id), updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.route_definition_audit(
 id bigint generated always as identity primary key, route_key text not null, action text not null,
 snapshot jsonb not null default '{}'::jsonb, changed_by uuid references auth.users(id), changed_at timestamptz not null default now()
);
alter table public.route_definitions enable row level security;
alter table public.route_definition_audit enable row level security;
revoke all on public.route_definitions,public.route_definition_audit from anon,authenticated;

insert into public.route_definitions(route_key,display_name,box_prefix,receipt_prefix,volumetric_factor,minimum_charge)
select x.k,x.n,x.b,x.r,coalesce((select volumetric_factor from public.freight_rate_tiers f where f.route_key=x.k order by min_weight_kg limit 1),.00022),
coalesce((select minimum_charge from public.freight_rate_tiers f where f.route_key=x.k order by min_weight_kg limit 1),0)
from (values
('kr_la_sea','한국->라오스 해상','S','LKS'),('kr_la_air','한국->라오스 항공','A','LKA'),
('la_kr_air_exp','라오스->한국 항공 특송','B','LKB'),('la_th_land','라오스->태국 육로','LT','LKLT'),
('th_la_land','태국->라오스 육로','TL','LKTL'),('la_vn_land','라오스->베트남 육로','LV','LKLV'),
('vn_la_land','베트남->라오스 육로','VL','LKVL'),('la_ch_land','라오스->중국 육로','LC','LC'),
('ch_la_land','중국->라오스 육로','CL','LKCL'),('la_kh_land','라오스->캄보디아 육로','LCB','LKLCB'),
('kh_la_land','캄보디아->라오스 육로','CBL','LKCBL')) x(k,n,b,r)
on conflict(route_key) do nothing;

create or replace function public.admin_route_definitions()
returns setof public.route_definitions language plpgsql security definer set search_path=public as $$
begin if public.current_role()<>'admin' then raise exception '총괄 관리자 전용입니다.'; end if;
return query select * from public.route_definitions order by status,display_name; end $$;

create or replace function public.admin_save_route_definition(
 p_route_key text,p_label text,p_company_name text,p_phone text,p_address text,p_box_prefix text,p_receipt_prefix text,
 p_volumetric_factor numeric,p_minimum_charge numeric,p_tiers jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare t jsonb;
begin
 if public.current_role()<>'admin' then raise exception '총괄 관리자 전용입니다.'; end if;
 update public.route_definitions set display_name=p_label,company_name=p_company_name,phone=p_phone,address=p_address,
 box_prefix=p_box_prefix,receipt_prefix=p_receipt_prefix,volumetric_factor=p_volumetric_factor,minimum_charge=p_minimum_charge,
 updated_by=auth.uid(),updated_at=now() where route_key=p_route_key;
 update public.freight_rate_tiers set active=false,updated_at=now() where route_key=p_route_key;
 for t in select * from jsonb_array_elements(p_tiers) loop
   insert into public.freight_rate_tiers(route_key,min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note,active)
   values(p_route_key,(t->>'min_weight_kg')::numeric,(t->>'rate_per_kg')::numeric,p_minimum_charge,p_volumetric_factor,'DB 중앙 운임 정책',true)
   on conflict(route_key,min_weight_kg) do update set rate_per_kg=excluded.rate_per_kg,minimum_charge=excluded.minimum_charge,
   volumetric_factor=excluded.volumetric_factor,source_note=excluded.source_note,active=true,updated_at=now();
 end loop;
 insert into public.route_definition_audit(route_key,action,snapshot,changed_by)
 select p_route_key,'update',to_jsonb(r),auth.uid() from public.route_definitions r where route_key=p_route_key;
end $$;

create or replace function public.admin_create_route_draft(
 p_label text,p_base_route_key text,p_company_name text,p_phone text,p_address text,p_box_prefix text,p_receipt_prefix text,
 p_volumetric_factor numeric,p_minimum_charge numeric,p_tiers jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare k text; t jsonb;
begin
 if public.current_role()<>'admin' then raise exception '총괄 관리자 전용입니다.'; end if;
 k:=lower(regexp_replace(trim(p_label),'[^a-zA-Z0-9가-힣]+','_','g'))||'_'||substr(md5(clock_timestamp()::text),1,6);
 insert into public.route_definitions(route_key,display_name,status,base_route_key,company_name,phone,address,box_prefix,receipt_prefix,volumetric_factor,minimum_charge,created_by,updated_by)
 values(k,p_label,'draft',p_base_route_key,p_company_name,p_phone,p_address,p_box_prefix,p_receipt_prefix,p_volumetric_factor,p_minimum_charge,auth.uid(),auth.uid());
 for t in select * from jsonb_array_elements(p_tiers) loop
  insert into public.freight_rate_tiers(route_key,min_weight_kg,rate_per_kg,minimum_charge,volumetric_factor,source_note,active)
  values(k,(t->>'min_weight_kg')::numeric,(t->>'rate_per_kg')::numeric,p_minimum_charge,p_volumetric_factor,'신규 경로 draft',false);
 end loop;
 return k;
end $$;

create or replace function public.admin_apply_route_draft(p_route_key text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if public.current_role()<>'admin' then raise exception '총괄 관리자 전용입니다.'; end if;
 if not exists(select 1 from public.route_definitions where route_key=p_route_key and status='draft') then raise exception '적용 가능한 draft가 없습니다.'; end if;
 update public.route_definitions set status='active',updated_by=auth.uid(),updated_at=now() where route_key=p_route_key;
 update public.freight_rate_tiers set active=true,source_note='DB 중앙 운임 정책',updated_at=now() where route_key=p_route_key;
 insert into public.route_definition_audit(route_key,action,snapshot,changed_by)
 select p_route_key,'activate',to_jsonb(r),auth.uid() from public.route_definitions r where route_key=p_route_key;
end $$;
grant execute on function public.admin_route_definitions() to authenticated;
grant execute on function public.admin_save_route_definition(text,text,text,text,text,text,text,numeric,numeric,jsonb) to authenticated;
grant execute on function public.admin_create_route_draft(text,text,text,text,text,text,text,numeric,numeric,jsonb) to authenticated;
grant execute on function public.admin_apply_route_draft(text) to authenticated;
