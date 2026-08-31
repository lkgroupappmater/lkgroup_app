-- Patch172A: Excel export Edge Function uses service_role to read extra costs.
-- This is server-only access. No authenticated/anon direct table grant is added.
grant select on table public.receipt_extra_costs to service_role;
