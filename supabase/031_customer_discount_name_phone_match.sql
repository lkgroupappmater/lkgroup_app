-- 031_customer_discount_name_phone_match.sql
-- 고객 할인규칙을 이름+전화번호+운송구간 기준으로 안전하게 적용합니다.

-- 기존 전화번호는 비교 일관성을 위해 숫자만 남깁니다.
update public.customer_rate_overrides
set phone = public.normalize_phone(phone)
where phone <> public.normalize_phone(phone);

-- 전화번호가 없는 기존 규칙은 보존하되 자동 적용하지 않습니다.
-- 차후 Excel Row data에 전화번호를 입력하고 다시 업로드하면 활성 규칙으로 upsert됩니다.
update public.customer_rate_overrides
set active = false,
    updated_at = now()
where public.normalize_phone(phone) = '';

-- 동명이인을 구분할 수 있도록 기존 (customer_name, route_key) unique를 제거합니다.
alter table public.customer_rate_overrides
drop constraint if exists customer_rate_overrides_customer_name_route_key_key;

-- 이름+전화번호+구간이 같은 규칙만 같은 고객 규칙으로 봅니다.
alter table public.customer_rate_overrides
add constraint customer_rate_overrides_customer_name_phone_route_key_key
unique (customer_name, phone, route_key);

comment on column public.customer_rate_overrides.phone is
'고객 할인 오적용 방지용 전화번호. 숫자만 저장하며, 이름+전화번호가 모두 일치할 때만 할인 적용.';
