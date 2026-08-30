-- 067_unmatched_recipient_queue_and_admin_menu_badges.sql
-- 신규 Excel 업로드 수취인 자동 매칭/불명 분리 + 관리자 작업개수/New/Update 표시

-- ---------------------------------------------------------------------------
-- 1) 신규 업로드 수취인 불명 검토 큐
-- ---------------------------------------------------------------------------
create table if not exists public.unmatched_recipient_review_queue (
  id bigint generated always as identity primary key,
  shipment_id bigint not null unique references public.shipments(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','resolved','kept_unknown')),
  detected_name text not null default '',
  detected_phone text not null default '',
  detected_company text not null default '',
  detected_by uuid references auth.users(id) on delete set null,
  first_detected_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz
);

alter table public.unmatched_recipient_review_queue enable row level security;
drop policy if exists unmatched_review_admin_read on public.unmatched_recipient_review_queue;
drop policy if exists unmatched_review_admin_write on public.unmatched_recipient_review_queue;
create policy unmatched_review_admin_read on public.unmatched_recipient_review_queue
  for select using (public.current_role()='admin');
create policy unmatched_review_admin_write on public.unmatched_recipient_review_queue
  for all using (public.current_role()='admin')
  with check (public.current_role()='admin');

grant select, insert, update on public.unmatched_recipient_review_queue to authenticated;
grant usage, select on sequence public.unmatched_recipient_review_queue_id_seq to authenticated;

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
  select exists (
    select 1
    from public.profiles p
    where coalesce(p.deletion_status,'active')='active'
      and public.phone_matches(p.phone, p_phone)
      and (
        public.normalize_person_name(p.name)=public.normalize_person_name(p_name)
        or (
          coalesce(btrim(p.company),'')<>'' and
          public.normalize_person_name(p.company)=public.normalize_person_name(p_name)
        )
      )
  )
$$;

-- 기존 "수취인 불명" 판정도 등록 고객 이름/회사명 + 전화번호 기준으로 강화.
create or replace function public.refresh_recipient_unknown_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n text := btrim(coalesce(new.consignee_name, ''));
  p text := public.normalize_phone(new.consignee_phone);
  explicit_unknown boolean;
begin
  if new.recipient_unknown_confirmed_at is not null then
    new.recipient_unknown := false;
    return new;
  end if;

  explicit_unknown :=
    n = ''
    or lower(n) like '%수취인 불명%'
    or lower(n) like '%데이타 불문명%'
    or lower(n) like '%데이터 불문명%'
    or lower(n) like '%unknown%'
    or lower(n) like '%미상%';

  new.recipient_unknown :=
    explicit_unknown
    or p = ''
    or not public.shipment_matches_registered_customer(n, new.consignee_phone);

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) 항차 자동 정상화
--    - 등록 고객: 기존 로직대로 영수번호/Zone
--    - 미등록/불일치: 같은 항차의 맨 뒤 "XX" 영수번호로 묶고 Zone F
-- ---------------------------------------------------------------------------
create or replace function public.normalize_shipment_batch(
  p_route text,
  p_year integer,
  p_voyage text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_route_key text;
  v_receipt_prefix text;
  v_voyage text := lpad(regexp_replace(coalesce(p_voyage,''),'[^0-9]','','g'),2,'0');
  v_next integer := 1;
  r record;
  v_existing text;
  v_receipt text;
  v_count integer;
  v_unknown_receipt text;
  v_is_unknown boolean;
begin
  if coalesce(trim(p_route),'')='' or p_year is null or coalesce(trim(v_voyage),'')='' then
    return;
  end if;

  select rd.route_key, rd.receipt_prefix
    into v_route_key, v_receipt_prefix
  from public.route_definitions rd
  where rd.display_name=trim(p_route) or rd.route_key=trim(p_route)
  order by case when rd.display_name=trim(p_route) then 0 else 1 end
  limit 1;

  if coalesce(trim(v_receipt_prefix),'')='' then
    v_receipt_prefix := '';
  end if;

  v_unknown_receipt :=
    case
      when trim(v_receipt_prefix)='' then 'XX'
      when v_route_key in ('kr_la_sea','kr_la_air') then trim(v_receipt_prefix)||' XX'
      else trim(v_receipt_prefix)||'XX'
    end;

  -- 먼저 현재 고객정보 기준으로 known/unknown 재판정.
  for r in
    select s.id, s.consignee_name, s.consignee_phone, s.recipient_unknown_confirmed_at
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.deletion_requested_at is null
  loop
    v_is_unknown :=
      r.recipient_unknown_confirmed_at is null
      and (
        coalesce(btrim(r.consignee_name),'')=''
        or public.normalize_phone(r.consignee_phone)=''
        or not public.shipment_matches_registered_customer(r.consignee_name, r.consignee_phone)
      );

    update public.shipments
       set recipient_unknown=v_is_unknown,
           unloading_zone=case when v_is_unknown then 'F' else unloading_zone end,
           receipt_number=case
             when v_is_unknown then v_unknown_receipt
             when receipt_number=v_unknown_receipt then ''
             else receipt_number
           end
     where id=r.id;

    if v_is_unknown then
      insert into public.unmatched_recipient_review_queue(
        shipment_id,status,detected_name,detected_phone,detected_by
      )
      values(
        r.id,'pending',coalesce(r.consignee_name,''),coalesce(r.consignee_phone,''),auth.uid()
      )
      on conflict (shipment_id) do update set
        status='pending',
        detected_name=excluded.detected_name,
        detected_phone=excluded.detected_phone,
        detected_by=coalesce(excluded.detected_by, public.unmatched_recipient_review_queue.detected_by),
        updated_at=now(),
        resolved_by=null,
        resolved_at=null
      where public.unmatched_recipient_review_queue.status='resolved'
         or public.unmatched_recipient_review_queue.detected_name is distinct from excluded.detected_name
         or public.unmatched_recipient_review_queue.detected_phone is distinct from excluded.detected_phone;
    else
      update public.unmatched_recipient_review_queue
         set status='resolved',
             resolved_by=auth.uid(),
             resolved_at=coalesce(resolved_at,now()),
             updated_at=now()
       where shipment_id=r.id and status='pending';
    end if;
  end loop;

  -- 숫자 영수번호는 known cargo만 기준으로 이어감. XX는 번호 계산에서 제외.
  select coalesce(max((m)[1]::integer),0)+1
    into v_next
  from public.shipments s
  cross join lateral regexp_match(trim(coalesce(s.receipt_number,'')),'(\d+)\s*$') m
  where s.route=p_route
    and s.shipment_year=p_year
    and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
    and s.recipient_unknown=false
    and s.deletion_requested_at is null;

  if v_next is null or v_next<1 then v_next:=1; end if;

  for r in
    select s.id,
           lower(trim(coalesce(s.consignee_name,''))) customer_name,
           regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g') customer_phone
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')=''
      and s.deletion_requested_at is null
    order by s.created_at nulls last,s.id
  loop
    select trim(s.receipt_number)
      into v_existing
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')<>''
      and s.receipt_number<>v_unknown_receipt
      and lower(trim(coalesce(s.consignee_name,'')))=r.customer_name
      and regexp_replace(coalesce(s.consignee_phone,''),'[^0-9+]','','g')=r.customer_phone
      and s.deletion_requested_at is null
    order by s.id
    limit 1;

    if coalesce(v_existing,'')<>'' then
      v_receipt:=v_existing;
    else
      if trim(v_receipt_prefix)='' then
        v_receipt:='ID-'||lpad(v_next::text,2,'0');
      elsif v_route_key in ('kr_la_sea','kr_la_air') then
        v_receipt:=trim(v_receipt_prefix)||' '||lpad(v_next::text,2,'0');
      else
        v_receipt:=trim(v_receipt_prefix)||lpad(v_next::text,2,'0');
      end if;
      v_next:=v_next+1;
    end if;

    update public.shipments set receipt_number=v_receipt where id=r.id;
  end loop;

  -- known cargo Zone 재계산. unknown은 항상 F 유지.
  for r in
    select s.receipt_number,sum(greatest(coalesce(s.quantity,1),1))::integer qty
    from public.shipments s
    where s.route=p_route
      and s.shipment_year=p_year
      and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
      and s.recipient_unknown=false
      and coalesce(trim(s.receipt_number),'')<>''
      and s.deletion_requested_at is null
    group by s.receipt_number
  loop
    v_count:=r.qty;
    update public.shipments s
       set unloading_zone=case
         when v_route_key='kr_la_air' then '102'
         when v_count>=20 then 'F'
         when v_count>=10 then 'C'
         when v_count>=5 then 'B'
         else 'A'
       end
     where s.route=p_route
       and s.shipment_year=p_year
       and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
       and s.receipt_number=r.receipt_number
       and s.recipient_unknown=false
       and s.deletion_requested_at is null;
  end loop;

  update public.shipments s
     set unloading_zone='F', receipt_number=v_unknown_receipt
   where s.route=p_route
     and s.shipment_year=p_year
     and lpad(regexp_replace(coalesce(s.voyage,''),'[^0-9]','','g'),2,'0')=v_voyage
     and s.recipient_unknown=true
     and s.deletion_requested_at is null;
end;
$$;

-- 기존 항차 전체 backfill은 하지 않습니다. 신규 업로드/수정되는 화물부터 자동 분류합니다.\n\n-- 관리자 자동 불명 큐 목록
create or replace function public.admin_list_auto_unmatched_recipients()
returns table(
  queue_id bigint,
  shipment_id bigint,
  route text,
  shipment_year integer,
  voyage text,
  box_number text,
  invoice_number text,
  consignee_name text,
  consignee_phone text,
  receipt_number text,
  unloading_zone text,
  notes text,
  data_locked boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_role()<>'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  return query
  select q.id,q.shipment_id,s.route,s.shipment_year,s.voyage,
         s.box_number,s.invoice_number,s.consignee_name,s.consignee_phone,
         s.receipt_number,s.unloading_zone,s.notes,s.data_locked,
         q.first_detected_at
  from public.unmatched_recipient_review_queue q
  join public.shipments s on s.id=q.shipment_id
  where q.status='pending'
    and s.deletion_requested_at is null
  order by q.first_detected_at,q.id;
end;
$$;

create or replace function public.admin_resolve_auto_unmatched_recipient(
  p_queue_id bigint,
  p_consignee_name text,
  p_consignee_phone text,
  p_invoice_number text,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  q public.unmatched_recipient_review_queue%rowtype;
  s public.shipments%rowtype;
begin
  if public.current_role()<>'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;

  select * into q from public.unmatched_recipient_review_queue
  where id=p_queue_id and status='pending' for update;
  if not found then raise exception '대기 중인 수취인 불명 항목을 찾을 수 없습니다.'; end if;

  select * into s from public.shipments where id=q.shipment_id for update;
  if not found then raise exception '화물 데이터를 찾을 수 없습니다.'; end if;

  if nullif(btrim(p_consignee_name),'') is null then
    raise exception '정상화할 수취인 이름/회사명을 입력해 주세요.';
  end if;

  update public.shipments
     set consignee_name=btrim(p_consignee_name),
         consignee_phone=coalesce(p_consignee_phone,''),
         invoice_number=coalesce(p_invoice_number,''),
         notes=coalesce(p_notes,''),
         recipient_unknown=false,
         recipient_unknown_confirmed_at=now(),
         recipient_unknown_confirmed_by=auth.uid(),
         receipt_number='',
         updated_at=now()
   where id=q.shipment_id;

  update public.unmatched_recipient_review_queue
     set status='resolved',resolved_by=auth.uid(),resolved_at=now(),updated_at=now()
   where id=p_queue_id;

  perform public.normalize_shipment_batch(s.route,s.shipment_year,s.voyage);
end;
$$;

create or replace function public.admin_keep_auto_unmatched_recipient(p_queue_id bigint)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  q public.unmatched_recipient_review_queue%rowtype;
begin
  if public.current_role()<>'admin' then
    raise exception '관리자(총괄) 권한이 필요합니다.';
  end if;
  select * into q from public.unmatched_recipient_review_queue
  where id=p_queue_id and status='pending' for update;
  if not found then raise exception '대기 항목을 찾을 수 없습니다.'; end if;

  update public.unmatched_recipient_review_queue
     set status='kept_unknown',resolved_by=auth.uid(),resolved_at=now(),updated_at=now()
   where id=p_queue_id;

  -- 화물은 그대로 XX / Zone F / recipient_unknown=true 유지
end;
$$;

grant execute on function public.admin_list_auto_unmatched_recipients() to authenticated;
grant execute on function public.admin_resolve_auto_unmatched_recipient(bigint,text,text,text,text) to authenticated;
grant execute on function public.admin_keep_auto_unmatched_recipient(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) 관리자 메뉴 작업 개수 + 다른 관리자/직원의 New / Update
-- ---------------------------------------------------------------------------
create table if not exists public.admin_menu_activity (
  id bigint generated always as identity primary key,
  menu_key text not null,
  activity_type text not null check(activity_type in ('new','update')),
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists admin_menu_activity_key_time_idx
  on public.admin_menu_activity(menu_key,created_at desc);

create table if not exists public.admin_menu_seen (
  user_id uuid not null references auth.users(id) on delete cascade,
  menu_key text not null,
  seen_at timestamptz not null default now(),
  primary key(user_id,menu_key)
);

alter table public.admin_menu_activity enable row level security;
alter table public.admin_menu_seen enable row level security;

drop policy if exists admin_menu_activity_admin_read on public.admin_menu_activity;
drop policy if exists admin_menu_seen_own on public.admin_menu_seen;
create policy admin_menu_activity_admin_read on public.admin_menu_activity
  for select using (public.current_role()='admin');
create policy admin_menu_seen_own on public.admin_menu_seen
  for all using (user_id=auth.uid()) with check (user_id=auth.uid());

grant select on public.admin_menu_activity to authenticated;
grant select,insert,update on public.admin_menu_seen to authenticated;

create or replace function public.log_admin_menu_activity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.admin_menu_activity(menu_key,activity_type,actor_id)
  values(TG_ARGV[0], case when TG_OP='INSERT' then 'new' else 'update' end, auth.uid());
  return coalesce(new,old);
end;
$$;

-- 반복 실행 안전
drop trigger if exists trg_unmatched_menu_activity on public.unmatched_recipient_review_queue;
create trigger trg_unmatched_menu_activity
after insert or update on public.unmatched_recipient_review_queue
for each row execute function public.log_admin_menu_activity('change_approval');

drop trigger if exists trg_change_request_menu_activity on public.shipment_change_requests;
create trigger trg_change_request_menu_activity
after insert or update on public.shipment_change_requests
for each row execute function public.log_admin_menu_activity('change_approval');

drop trigger if exists trg_unknown_claim_menu_activity on public.unknown_recipient_claims;
create trigger trg_unknown_claim_menu_activity
after insert or update on public.unknown_recipient_claims
for each row execute function public.log_admin_menu_activity('change_approval');

drop trigger if exists trg_quote_menu_activity on public.quote_requests;
create trigger trg_quote_menu_activity
after insert or update on public.quote_requests
for each row execute function public.log_admin_menu_activity('quote_requests');

drop trigger if exists trg_discount_menu_activity on public.customer_rate_overrides;
create trigger trg_discount_menu_activity
after insert or update on public.customer_rate_overrides
for each row execute function public.log_admin_menu_activity('discount_management');

drop trigger if exists trg_delivery_menu_activity on public.local_delivery_profiles;
create trigger trg_delivery_menu_activity
after insert or update on public.local_delivery_profiles
for each row execute function public.log_admin_menu_activity('local_delivery_management');

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
      (select count(*)::integer from public.quote_requests where status='pending')
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
end;
$$;

create or replace function public.admin_mark_management_menu_seen(p_menu_key text)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_role()<>'admin' then return; end if;
  insert into public.admin_menu_seen(user_id,menu_key,seen_at)
  values(auth.uid(),p_menu_key,now())
  on conflict(user_id,menu_key) do update set seen_at=excluded.seen_at;
end;
$$;

grant execute on function public.admin_management_menu_status() to authenticated;
grant execute on function public.admin_mark_management_menu_seen(text) to authenticated;
