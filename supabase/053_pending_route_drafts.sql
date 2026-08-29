-- 053_pending_route_drafts.sql

create or replace function public.admin_update_route_draft(
  p_route_key text,
  p_label text,
  p_company_name text,
  p_phone text,
  p_address text,
  p_box_prefix text,
  p_receipt_prefix text,
  p_minimum_charge numeric,
  p_tiers jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t jsonb;
  v_factor numeric;
begin
  if public.current_role() <> 'admin' then
    raise exception '총괄 관리자 전용입니다.';
  end if;

  if not exists (
    select 1
    from public.route_definitions
    where route_key = p_route_key
      and status = 'draft'
  ) then
    raise exception '적용 대기 중인 신규 경로를 찾을 수 없습니다.';
  end if;

  select coalesce(volumetric_factor, 0.00022)
  into v_factor
  from public.route_definitions
  where route_key = p_route_key;

  update public.route_definitions
  set
    display_name = btrim(p_label),
    company_name = coalesce(p_company_name, ''),
    phone = coalesce(p_phone, ''),
    address = coalesce(p_address, ''),
    box_prefix = coalesce(p_box_prefix, ''),
    receipt_prefix = coalesce(p_receipt_prefix, ''),
    minimum_charge = coalesce(p_minimum_charge, 0),
    updated_by = auth.uid(),
    updated_at = now()
  where route_key = p_route_key
    and status = 'draft';

  delete from public.freight_rate_tiers
  where route_key = p_route_key;

  for t in
    select * from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb))
  loop
    insert into public.freight_rate_tiers(
      route_key,
      min_weight_kg,
      rate_per_kg,
      minimum_charge,
      volumetric_factor,
      source_note,
      active
    )
    values(
      p_route_key,
      (t->>'min_weight_kg')::numeric,
      (t->>'rate_per_kg')::numeric,
      coalesce(p_minimum_charge, 0),
      v_factor,
      '신규 경로 draft',
      false
    );
  end loop;

  insert into public.route_definition_audit(
    route_key, action, snapshot, changed_by
  )
  select
    p_route_key,
    'draft_update',
    to_jsonb(r),
    auth.uid()
  from public.route_definitions r
  where r.route_key = p_route_key;
end
$$;

grant execute on function public.admin_update_route_draft(
  text,text,text,text,text,text,text,numeric,jsonb
) to authenticated;
