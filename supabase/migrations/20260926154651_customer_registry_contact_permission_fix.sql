-- customer_registry_change calls setval even for name/phone-only edits.
-- Keep execution restricted to the existing trusted server role.
grant update on sequence public.customer_registry_number_seq to service_role;
