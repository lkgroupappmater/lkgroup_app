-- Receipt access is shared by the app and website.
-- Keep customer registry tables private; expose only authorized receipt data.
CREATE OR REPLACE FUNCTION lk_private.statement_rows_for_receipt(
  p_route text, p_year integer, p_voyage text, p_receipt_number text
)
RETURNS SETOF public.shipments
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  viewer public.profiles%rowtype;
  company_aliases text[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO viewer FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND OR viewer.approval_status IS DISTINCT FROM 'approved'
     OR viewer.deleted_at IS NOT NULL
     OR coalesce(viewer.deletion_status, 'active') <> 'active' THEN
    RAISE EXCEPTION '승인된 회원만 명세서를 조회할 수 있습니다.' USING ERRCODE = '42501';
  END IF;
  IF viewer.role = 'partner' THEN
    RAISE EXCEPTION '협력/파트너 계정은 명세서를 조회할 수 없습니다.' USING ERRCODE = '42501';
  END IF;
  IF coalesce(viewer.role, '') NOT IN ('admin', 'staff', 'member') THEN
    RAISE EXCEPTION '명세서 조회 권한이 없습니다.' USING ERRCODE = '42501';
  END IF;
  IF viewer.role = 'member' THEN
    company_aliases := lk_private.approved_member_company_aliases(auth.uid());
  END IF;
  RETURN QUERY
  SELECT s.* FROM public.shipments s
  WHERE s.route = btrim(p_route)
    AND s.shipment_year = p_year
    AND ltrim(regexp_replace(coalesce(s.voyage, ''), '[^0-9]', '', 'g'), '0')
      = ltrim(regexp_replace(coalesce(p_voyage, ''), '[^0-9]', '', 'g'), '0')
    AND btrim(coalesce(s.receipt_number, '')) = btrim(p_receipt_number)
    AND s.deleted_at IS NULL AND s.deletion_requested_at IS NULL
    AND (
      viewer.role IN ('admin', 'staff')
      OR s.customer_id = auth.uid()
      OR lk_private.company_tokens(s.consignee_name) && company_aliases
      OR (
        btrim(coalesce(viewer.name, '')) <> ''
        AND lower(btrim(coalesce(s.consignee_name, ''))) = lower(btrim(viewer.name))
        AND length(public.only_digits(viewer.phone)) >= 8
        AND right(public.only_digits(s.consignee_phone), 8) = right(public.only_digits(viewer.phone), 8)
      )
    )
  ORDER BY s.box_number, s.id;
END;
$function$;

REVOKE ALL ON FUNCTION lk_private.statement_rows_for_receipt(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lk_private.statement_rows_for_receipt(text, integer, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.statement_rows_for_receipt(
  p_route text, p_year integer, p_voyage text, p_receipt_number text
)
RETURNS SETOF public.shipments
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT * FROM lk_private.statement_rows_for_receipt(p_route, p_year, p_voyage, p_receipt_number);
$function$;

REVOKE ALL ON FUNCTION public.statement_rows_for_receipt(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.statement_rows_for_receipt(text, integer, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION lk_private.statement_delivery_context(
  p_route text, p_year integer, p_voyage text, p_receipt_number text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  customers jsonb;
  matched jsonb;
  policy jsonb;
  route_key text;
  deliveries jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.' USING ERRCODE = '42501';
  END IF;
  -- Derive identities on the server from authorized rows, never from client input.
  SELECT coalesce(jsonb_agg(DISTINCT jsonb_build_object(
    'name', coalesce(s.consignee_name, ''), 'phone', coalesce(s.consignee_phone, '')
  )), '[]'::jsonb)
  INTO customers
  FROM lk_private.statement_rows_for_receipt(p_route, p_year, p_voyage, p_receipt_number) s;

  IF jsonb_array_length(customers) = 0 THEN
    RETURN jsonb_build_object('matches', '[]'::jsonb, 'deliveries', '[]'::jsonb, 'appearance', '{}'::jsonb);
  END IF;
  route_key := public.route_base_key_for_label(btrim(p_route));
  matched := public.lk_excel_delivery_matches_scoped(route_key, p_year, p_voyage, customers);
  policy := public.lk_excel_effective_policy(route_key, p_year, p_voyage);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id', d->'id', 'active', d->'active',
    'source_no', d->'source_no', 'original_source_no', d->'original_source_no',
    'customer_name', d->'customer_name', 'alternate_name', d->'alternate_name',
    'company_name', d->'company_name', 'phone', d->'phone', 'phone_display', d->'phone_display',
    'local_company', d->'local_company', 'destination_address', d->'destination_address',
    'delivery_type', d->'delivery_type', 'paid_by', d->'paid_by'
  )), '[]'::jsonb)
  INTO deliveries
  FROM jsonb_array_elements(coalesce(policy->'deliveries', '[]'::jsonb)) d
  WHERE (d->>'active')::boolean
    AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(coalesce(matched, '[]'::jsonb)) m
      WHERE m->>'id' = d->>'id'
    );
  RETURN jsonb_build_object(
    'matches', coalesce(matched, '[]'::jsonb),
    'deliveries', deliveries,
    'appearance', coalesce(policy->'appearance', '{}'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION lk_private.statement_delivery_context(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lk_private.statement_delivery_context(text, integer, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.statement_delivery_context(
  p_route text, p_year integer, p_voyage text, p_receipt_number text
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT lk_private.statement_delivery_context(p_route, p_year, p_voyage, p_receipt_number);
$function$;

REVOKE ALL ON FUNCTION public.statement_delivery_context(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.statement_delivery_context(text, integer, text, text) TO authenticated, service_role;
