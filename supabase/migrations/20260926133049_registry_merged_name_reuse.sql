-- A reviewed merge retains the retired record for audit but frees its canonical
-- name/phone for the surviving customer. Reviewed aliases remain globally unique.
alter table public.customer_registry drop constraint customer_registry_name_key_phone_key_key;
create unique index customer_registry_active_name_phone_key
 on public.customer_registry(name_key,phone_key) where merged_into is null;
