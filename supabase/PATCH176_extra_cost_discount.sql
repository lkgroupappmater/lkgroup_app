-- Patch176
-- 기타 비용별 "할인 적용" 선택 + 명세서 최종 금액 계산 지원.
-- 기본값 false: 기존 기타 비용은 자동으로 할인되지 않습니다.

alter table public.receipt_extra_costs
  add column if not exists discount_applies boolean not null default false;

drop function if exists public.list_receipt_extra_costs(text,integer,text,text);
create function public.list_receipt_extra_costs(
  p_route text,p_year integer,p_voyage text,p_receipt_number text
) returns table(
  id bigint,
  cost_name text,
  amount_usd numeric,
  discount_applies boolean
)
language sql
security definer
set search_path=public
as $$
  select e.id,e.cost_name,e.amount_usd,e.discount_applies
  from public.receipt_extra_costs e
  where e.route=btrim(p_route)
    and e.shipment_year=p_year
    and regexp_replace(coalesce(e.voyage,''),'[^0-9]','','g')
        = regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g')
    and btrim(e.receipt_number)=btrim(p_receipt_number)
  order by e.id;
$$;

drop function if exists public.save_receipt_extra_cost(
  bigint,text,integer,text,text,text,numeric
);

create function public.save_receipt_extra_cost(
  p_id bigint,
  p_route text,
  p_year integer,
  p_voyage text,
  p_receipt_number text,
  p_cost_name text,
  p_amount_usd numeric,
  p_discount_applies boolean default false
) returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null or not exists(
    select 1
    from public.profiles p
    where p.id=auth.uid()
      and p.role in ('admin','staff')
  ) then
    raise exception '기타 비용 수정 권한이 없습니다.';
  end if;

  if coalesce(btrim(p_cost_name),'')='' then
    raise exception '비용 이름을 입력해 주세요.';
  end if;
  if coalesce(p_amount_usd,0)<0 then
    raise exception '금액을 확인해 주세요.';
  end if;

  if p_id is null then
    insert into public.receipt_extra_costs(
      route,shipment_year,voyage,receipt_number,
      cost_name,amount_usd,discount_applies
    ) values(
      btrim(p_route),p_year,btrim(p_voyage),btrim(p_receipt_number),
      btrim(p_cost_name),p_amount_usd,coalesce(p_discount_applies,false)
    )
    returning id into v_id;
  else
    update public.receipt_extra_costs
    set cost_name=btrim(p_cost_name),
        amount_usd=p_amount_usd,
        discount_applies=coalesce(p_discount_applies,false),
        updated_at=now()
    where id=p_id
    returning id into v_id;

    if v_id is null then
      raise exception '기타 비용 항목을 찾을 수 없습니다.';
    end if;
  end if;

  return v_id;
end
$$;

revoke all on function public.list_receipt_extra_costs(text,integer,text,text)
  from public;
revoke all on function public.save_receipt_extra_cost(
  bigint,text,integer,text,text,text,numeric,boolean
) from public;

grant execute on function public.list_receipt_extra_costs(
  text,integer,text,text
) to authenticated,service_role;
grant execute on function public.save_receipt_extra_cost(
  bigint,text,integer,text,text,text,numeric,boolean
) to authenticated,service_role;
