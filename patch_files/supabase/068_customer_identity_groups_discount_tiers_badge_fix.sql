-- 068_customer_identity_groups_discount_tiers_badge_fix.sql
-- 개인 이름 + 회사명 고객 묶음, 합산 물량 할인 tier, 명세서 통합/분리 기반,
-- 견적요청 메뉴 badge 실제 화면 기준 보정.
--
-- 고객 ID 포맷은 차후 결정하므로 여기서는 ID 번호 체계를 만들지 않습니다.

-- ============================================================
-- 1. Customer identity group
-- ============================================================
create table if not exists public.customer_identity_groups (
  id bigint generated always as identity primary key,
  profile_id uuid unique references public.profiles(id) on delete set null,
  primary_name text not null default '',
  company_name text not null default '',
  phone text not null default '',
  statement_mode text not null default 'separate'
    check (statement_mode in ('combined','separate')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_identity_aliases (
  id bigint generated always as identity primary key,
  group_id bigint not null references public.customer_identity_groups(id) on delete cascade,
  alias_name text not null,
  alias_type text not null default 'other'
    check (alias_type in ('personal','company','other')),
  created_at timestamptz not null default now(),
  unique(group_id, alias_name)
);

create index if not exists customer_identity_groups_phone_idx
  on public.customer_identity_groups(phone);
create index if not exists customer_identity_aliases_group_idx
  on public.customer_identity_aliases(group_id);
create index if not exists customer_identity_aliases_name_idx
  on public.customer_identity_aliases(lower(alias_name));

alter table public.customer_identity_groups enable row level security;
alter table public.customer_identity_aliases enable row level security;

drop policy if exists customer_identity_groups_read_authenticated
  on public.customer_identity_groups;
drop policy if exists customer_identity_groups_admin_write
  on public.customer_identity_groups;
drop policy if exists customer_identity_aliases_read_authenticated
  on public.customer_identity_aliases;
drop policy if exists customer_identity_aliases_admin_write
  on public.customer_identity_aliases;

create policy customer_identity_groups_read_authenticated
  on public.customer_identity_groups
  for select using (auth.uid() is not null and public.is_approved_user());

create policy customer_identity_groups_admin_write
  on public.customer_identity_groups
  for all using (public.current_role()='admin')
  with check (public.current_role()='admin');

create policy customer_identity_aliases_read_authenticated
  on public.customer_identity_aliases
  for select using (auth.uid() is not null and public.is_approved_user());

create policy customer_identity_aliases_admin_write
  on public.customer_identity_aliases
  for all using (public.current_role()='admin')
  with check (public.current_role()='admin');

grant select on public.customer_identity_groups, public.customer_identity_aliases
  to authenticated;
grant insert, update, delete on public.customer_identity_groups, public.customer_identity_aliases
  to authenticated;
grant usage, select on sequence public.customer_identity_groups_id_seq,
  public.customer_identity_aliases_id_seq to authenticated;

-- 정확한 이름/회사명 alias + 전화번호가 유일하게 일치할 때만 group 확정.
create or replace function public.resolve_customer_identity_group(
  p_name text,
  p_phone text
)
returns bigint
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_group_id bigint;
  v_count integer;
begin
  if public.normalize_person_name(p_name)=''
     or public.normalize_phone(p_phone)='' then
    return null;
  end if;

  select min(g.id), count(distinct g.id)
    into v_group_id, v_count
  from public.customer_identity_groups g
  join public.customer_identity_aliases a on a.group_id=g.id
  where g.active=true
    and public.phone_matches(g.phone,p_phone)
    and public.normalize_person_name(a.alias_name)
        = public.normalize_person_name(p_name);

  if v_count=1 then return v_group_id; end if;
  return null;
end
$$;

create or replace function public.sync_profile_customer_identity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_group_id bigint;
begin
  if coalesce(new.deletion_status,'active') <> 'active' then
    update public.customer_identity_groups
       set active=false, updated_at=now()
     where profile_id=new.id;
    return new;
  end if;

  insert into public.customer_identity_groups(
    profile_id, primary_name, company_name, phone, active, updated_at
  ) values (
    new.id,
    coalesce(btrim(new.name),''),
    coalesce(btrim(new.company),''),
    public.normalize_phone(new.phone),
    true,
    now()
  )
  on conflict(profile_id) do update set
    primary_name=excluded.primary_name,
    company_name=excluded.company_name,
    phone=excluded.phone,
    active=true,
    updated_at=now()
  returning id into v_group_id;

  delete from public.customer_identity_aliases
   where group_id=v_group_id
     and alias_type in ('personal','company');

  if nullif(btrim(new.name),'') is not null then
    insert into public.customer_identity_aliases(group_id,alias_name,alias_type)
    values(v_group_id,btrim(new.name),'personal')
    on conflict(group_id,alias_name) do update set alias_type='personal';
  end if;

  if nullif(btrim(new.company),'') is not null then
    insert into public.customer_identity_aliases(group_id,alias_name,alias_type)
    values(v_group_id,btrim(new.company),'company')
    on conflict(group_id,alias_name) do update set alias_type='company';
  end if;

  return new;
end
$$;

drop trigger if exists trg_profiles_customer_identity on public.profiles;
create trigger trg_profiles_customer_identity
after insert or update of name,company,phone,deletion_status
on public.profiles
for each row execute function public.sync_profile_customer_identity();

-- 기존 회원을 한 번만 안전하게 group/alias로 backfill.
do $$
declare r public.profiles%rowtype;
begin
  for r in
    select * from public.profiles
    where coalesce(deletion_status,'active')='active'
  loop
    insert into public.customer_identity_groups(
      profile_id,primary_name,company_name,phone,active,updated_at
    ) values (
      r.id,coalesce(btrim(r.name),''),coalesce(btrim(r.company),''),
      public.normalize_phone(r.phone),true,now()
    )
    on conflict(profile_id) do update set
      primary_name=excluded.primary_name,
      company_name=excluded.company_name,
      phone=excluded.phone,
      active=true,
      updated_at=now();

    insert into public.customer_identity_aliases(group_id,alias_name,alias_type)
    select g.id,btrim(r.name),'personal'
    from public.customer_identity_groups g
    where g.profile_id=r.id and nullif(btrim(r.name),'') is not null
    on conflict(group_id,alias_name) do update set alias_type='personal';

    insert into public.customer_identity_aliases(group_id,alias_name,alias_type)
    select g.id,btrim(r.company),'company'
    from public.customer_identity_groups g
    where g.profile_id=r.id and nullif(btrim(r.company),'') is not null
    on conflict(group_id,alias_name) do update set alias_type='company';
  end loop;
end $$;

-- ============================================================
-- 2. Shipment identity group auto classification
-- ============================================================
alter table public.shipments
  add column if not exists customer_identity_group_id bigint
    references public.customer_identity_groups(id) on delete set null;

create index if not exists shipments_customer_identity_group_idx
  on public.shipments(customer_identity_group_id);

create or replace function public.shipments_identity_group_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  new.customer_identity_group_id :=
    public.resolve_customer_identity_group(
      new.consignee_name,
      new.consignee_phone
    );
  return new;
end
$$;

drop trigger if exists trg_shipments_identity_group on public.shipments;
create trigger trg_shipments_identity_group
before insert or update of consignee_name,consignee_phone
on public.shipments
for each row execute function public.shipments_identity_group_trigger();

-- 기존 cargo는 "정확히 유일 매칭"되는 건만 group id를 채움.
update public.shipments s
set customer_identity_group_id =
  public.resolve_customer_identity_group(s.consignee_name,s.consignee_phone)
where s.customer_identity_group_id is null
  and public.resolve_customer_identity_group(s.consignee_name,s.consignee_phone)
      is not null;

-- Patch122 수취인 불명 판단도 profile raw 비교가 아니라 identity alias 사용.
create or replace function public.shipment_matches_registered_customer(
  p_name text,
  p_phone text
)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select public.resolve_customer_identity_group(p_name,p_phone) is not null
$$;

-- ============================================================
-- 3. Discount tier + identity group
-- ============================================================
alter table public.customer_rate_overrides
  add column if not exists customer_group_id bigint
    references public.customer_identity_groups(id) on delete set null,
  add column if not exists bulk_threshold integer,
  add column if not exists bulk_discount_percent numeric,
  add column if not exists statement_mode text not null default 'separate';

alter table public.customer_rate_overrides
  drop constraint if exists customer_rate_overrides_bulk_threshold_check;
alter table public.customer_rate_overrides
  add constraint customer_rate_overrides_bulk_threshold_check
  check (bulk_threshold is null or bulk_threshold > 0);

alter table public.customer_rate_overrides
  drop constraint if exists customer_rate_overrides_bulk_discount_check;
alter table public.customer_rate_overrides
  add constraint customer_rate_overrides_bulk_discount_check
  check (
    bulk_discount_percent is null
    or (bulk_discount_percent >= 0 and bulk_discount_percent <= 1)
  );

alter table public.customer_rate_overrides
  drop constraint if exists customer_rate_overrides_statement_mode_check;
alter table public.customer_rate_overrides
  add constraint customer_rate_overrides_statement_mode_check
  check (statement_mode in ('combined','separate'));

create or replace function public.customer_rate_override_identity_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_gid bigint;
begin
  v_gid := public.resolve_customer_identity_group(
    coalesce(nullif(btrim(new.customer_name),''),new.company_name),
    new.phone
  );

  if v_gid is null and nullif(btrim(new.company_name),'') is not null then
    v_gid := public.resolve_customer_identity_group(new.company_name,new.phone);
  end if;

  new.customer_group_id := v_gid;

  if v_gid is not null then
    update public.customer_identity_groups
       set statement_mode=new.statement_mode, updated_at=now()
     where id=v_gid;
  end if;

  return new;
end
$$;

drop trigger if exists trg_customer_rate_override_identity
  on public.customer_rate_overrides;
create trigger trg_customer_rate_override_identity
before insert or update of customer_name,company_name,phone,statement_mode
on public.customer_rate_overrides
for each row execute function public.customer_rate_override_identity_trigger();

-- 기존 할인 규칙도 가능한 것만 group 연결.
update public.customer_rate_overrides r
set customer_group_id = coalesce(
  public.resolve_customer_identity_group(r.customer_name,r.phone),
  public.resolve_customer_identity_group(r.company_name,r.phone)
)
where customer_group_id is null
  and (
    public.resolve_customer_identity_group(r.customer_name,r.phone) is not null
    or public.resolve_customer_identity_group(r.company_name,r.phone) is not null
  );

-- 관리화면용: identity group의 statement_mode까지 같이 반환.
create or replace function public.admin_list_discount_rules_with_identity()
returns setof jsonb
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_role()<>'admin' then
    raise exception '관리자 권한이 필요합니다.';
  end if;

  return query
  select to_jsonb(r) ||
         jsonb_build_object(
           'statement_mode',
           coalesce(g.statement_mode,r.statement_mode,'separate')
         )
  from public.customer_rate_overrides r
  left join public.customer_identity_groups g on g.id=r.customer_group_id
  order by r.route_key,r.group_name,r.customer_name,r.id;
end
$$;

grant execute on function public.admin_list_discount_rules_with_identity()
  to authenticated;

-- 특정 고객/회사에 기존 회원 group이 있다면 statement_mode 저장.
create or replace function public.admin_set_customer_statement_mode(
  p_name text,
  p_company text,
  p_phone text,
  p_mode text
)
returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare
  v_gid bigint;
begin
  if public.current_role()<>'admin' then
    raise exception '관리자 권한이 필요합니다.';
  end if;
  if p_mode not in ('combined','separate') then
    raise exception '명세서 방식이 올바르지 않습니다.';
  end if;

  v_gid := coalesce(
    public.resolve_customer_identity_group(p_name,p_phone),
    public.resolve_customer_identity_group(p_company,p_phone)
  );

  if v_gid is not null then
    update public.customer_identity_groups
       set statement_mode=p_mode,updated_at=now()
     where id=v_gid;
  end if;

  return v_gid;
end
$$;

grant execute on function public.admin_set_customer_statement_mode(
  text,text,text,text
) to authenticated;

-- 항차 내 개인명 + 회사명 전체 물량을 합산한 effective discount.
create or replace function public.resolve_customer_discount_context(
  p_route_key text,
  p_year integer,
  p_voyage text,
  p_name text,
  p_phone text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_gid bigint;
  v_qty integer := 0;
  v_rule public.customer_rate_overrides%rowtype;
  v_effective numeric := 0;
  v_statement_mode text := 'separate';
begin
  if public.normalize_person_name(p_name)=''
     or public.normalize_phone(p_phone)='' then
    return '{}'::jsonb;
  end if;

  v_gid := public.resolve_customer_identity_group(p_name,p_phone);

  if v_gid is not null then
    select coalesce(sum(greatest(coalesce(s.quantity,1),1)),0)::integer
      into v_qty
    from public.shipments s
    where s.customer_identity_group_id=v_gid
      and public.route_base_key_for_label(s.route)=p_route_key
      and (p_year is null or s.shipment_year=p_year)
      and (
        coalesce(btrim(p_voyage),'')=''
        or lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')
           = lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0')
      )
      and s.deletion_requested_at is null;

    select *
      into v_rule
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=p_route_key or r.route_key='all')
      and (
        r.customer_group_id=v_gid
        or (
          public.phone_matches(r.phone,p_phone)
          and (
            public.normalize_person_name(r.customer_name)
                = public.normalize_person_name(p_name)
            or public.normalize_person_name(r.company_name)
                = public.normalize_person_name(p_name)
          )
        )
      )
    order by
      case when r.route_key=p_route_key then 0 else 1 end,
      case when r.customer_group_id=v_gid then 0 else 1 end,
      r.id
    limit 1;

    select coalesce(statement_mode,'separate')
      into v_statement_mode
    from public.customer_identity_groups
    where id=v_gid;
  else
    -- 아직 회원 group으로 확정되지 않은 기존 할인 고객은 기존 안전 매칭 유지.
    select *
      into v_rule
    from public.customer_rate_overrides r
    where r.active=true
      and (r.route_key=p_route_key or r.route_key='all')
      and public.phone_matches(r.phone,p_phone)
      and (
        public.normalize_person_name(r.customer_name)
          = public.normalize_person_name(p_name)
        or public.normalize_person_name(r.company_name)
          = public.normalize_person_name(p_name)
      )
    order by case when r.route_key=p_route_key then 0 else 1 end,r.id
    limit 1;

    v_qty := 0;
  end if;

  if v_rule.id is null then
    return jsonb_build_object(
      'customer_group_id',v_gid,
      'combined_quantity',v_qty,
      'statement_mode',v_statement_mode
    );
  end if;

  v_effective := coalesce(v_rule.discount_percent,0);

  if v_rule.bulk_threshold is not null
     and v_rule.bulk_discount_percent is not null
     and v_qty >= v_rule.bulk_threshold then
    v_effective := v_rule.bulk_discount_percent;
  end if;

  return jsonb_build_object(
    'id',v_rule.id,
    'customer_name',v_rule.customer_name,
    'company_name',v_rule.company_name,
    'group_name',v_rule.group_name,
    'rate_override',v_rule.rate_override,
    'discount_percent',v_effective,
    'base_discount_percent',coalesce(v_rule.discount_percent,0),
    'bulk_threshold',v_rule.bulk_threshold,
    'bulk_discount_percent',v_rule.bulk_discount_percent,
    'combined_quantity',v_qty,
    'customer_group_id',v_gid,
    'statement_mode',v_statement_mode
  );
end
$$;

grant execute on function public.resolve_customer_discount_context(
  text,integer,text,text,text
) to authenticated;

-- ============================================================
-- 4. 견적 요청 badge = 실제 관리화면 RPC 결과 개수
-- ============================================================
create or replace function public.admin_management_menu_status()
returns table(
  menu_key text,
  pending_count integer,
  activity_type text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_uid uuid:=auth.uid();
begin
  if public.current_role()<>'admin' then return; end if;

  return query
  with keys(menu_key) as (
    values
      ('change_approval'::text),
      ('quote_requests'::text),
      ('member_management'::text),
      ('cargo_management'::text),
      ('discount_management'::text),
      ('local_delivery_management'::text)
  ),
  counts as (
    select 'change_approval'::text k,
      (
        (select count(*) from public.shipment_change_requests where status='pending')
        +(select count(*) from public.unknown_recipient_claims where status='pending')
        +(select count(*) from public.unmatched_recipient_review_queue where status='pending')
      )::integer c

    union all
    select 'quote_requests',
      (select count(*)::integer from public.list_admin_special_quotes())

    union all
    select 'member_management',
      (select count(*)::integer from public.profiles
       where coalesce(deletion_status,'active')='active'
         and requested_role in ('admin','partner')
         and requested_role is distinct from role)

    union all
    select 'cargo_management',
      (select count(*)::integer from public.shipments
       where deletion_requested_at is not null)

    union all select 'discount_management',0
    union all select 'local_delivery_management',0
  )
  select k.menu_key,
         coalesce(c.c,0),
         (
           select a.activity_type
           from public.admin_menu_activity a
           left join public.admin_menu_seen s
             on s.user_id=v_uid and s.menu_key=a.menu_key
           where a.menu_key=k.menu_key
             and a.actor_id is distinct from v_uid
             and a.created_at>coalesce(s.seen_at,'epoch'::timestamptz)
           order by a.created_at desc,a.id desc
           limit 1
         )
  from keys k
  left join counts c on c.k=k.menu_key;
end
$$;

grant execute on function public.admin_management_menu_status()
  to authenticated;

comment on table public.customer_identity_groups is
'회원 개인 이름+회사명을 하나의 고객 identity group으로 묶는 기반. 실제 고객 ID 포맷은 차후 추가.';
comment on column public.customer_identity_groups.statement_mode is
'combined=개인/회사 화물 명세서 통합, separate=개인/회사 명세서 분리. 할인 물량 합산과는 별개.';
comment on column public.customer_rate_overrides.bulk_threshold is
'개인 이름+회사명 identity group 합산 수량이 이 값 이상이면 bulk_discount_percent 적용.';
