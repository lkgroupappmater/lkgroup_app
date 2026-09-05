-- Remove temporary test policies that bypass the production role model.
-- Normal member/staff/partner/admin policies remain unchanged.
drop policy if exists allow_test_select on public.shipments;
drop policy if exists allow_test_insert on public.shipments;
drop policy if exists allow_test_select on public.notices;
drop policy if exists allow_test_insert on public.notices;
