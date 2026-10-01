-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; human execution after LIVE preflight.
BEGIN;
DO $preflight$
DECLARE v_spec RECORD;
BEGIN
  IF to_regclass('private.migration_039d_retry') IS NULL THEN RAISE EXCEPTION '039d required'; END IF;
  IF to_regclass('private.migration_039e_functions') IS NOT NULL THEN RAISE EXCEPTION '039e already present'; END IF;
  FOR v_spec IN SELECT * FROM (VALUES ('public.update_record_classification(uuid,uuid,uuid)','66643e9e4431cd8a4f27a2f689241165'),
('public.update_movement_classification(uuid,uuid,uuid)','21ffbb5e6ad06b08ed9c82a8334d7f6b'),
('public.get_operational_records_page(uuid,uuid,integer)','48bc90f7adce7a7732bc77790d896357'),
('public.get_operational_financials_page(uuid,uuid,integer)','79c6507e19bfd2f207ade00ec90a8779')) x(signature,hash) LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_spec.signature)
      AND pg_get_userbyid(proowner)='postgres' AND prosecdef AND proconfig=ARRAY['search_path=""']::TEXT[]
      AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v_spec.hash) THEN
      RAISE EXCEPTION '039e LIVE definition differs: %',v_spec.signature;
    END IF;
  END LOOP;
END; $preflight$;
CREATE TABLE private.migration_039e_functions(signature TEXT PRIMARY KEY, definition TEXT NOT NULL,
  installed_definition TEXT, owner_oid OID NOT NULL, acl ACLITEM[]);
ALTER TABLE private.migration_039e_functions ENABLE ROW LEVEL SECURITY;
DO $backup$
DECLARE v_grantee RECORD; v_who TEXT;
BEGIN
  FOR v_grantee IN SELECT DISTINCT a.grantee FROM pg_class c,
    LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE c.oid='private.migration_039e_functions'::regclass AND a.grantee<>c.relowner LOOP
    v_who:=CASE WHEN v_grantee.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(v_grantee.grantee)) END;
    EXECUTE format('REVOKE ALL ON TABLE private.migration_039e_functions FROM %s',v_who);
  END LOOP;
END; $backup$;
INSERT INTO private.migration_039e_functions(signature,definition,owner_oid,acl)
SELECT x.signature,pg_get_functiondef(p.oid),p.proowner,p.proacl
FROM (VALUES ('public.update_record_classification(uuid,uuid,uuid)','66643e9e4431cd8a4f27a2f689241165'),
('public.update_movement_classification(uuid,uuid,uuid)','21ffbb5e6ad06b08ed9c82a8334d7f6b'),
('public.get_operational_records_page(uuid,uuid,integer)','48bc90f7adce7a7732bc77790d896357'),
('public.get_operational_financials_page(uuid,uuid,integer)','79c6507e19bfd2f207ade00ec90a8779')) x(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(x.signature);

CREATE OR REPLACE FUNCTION public.update_record_classification(
  p_record_id UUID,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_CLASSIFY');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  -- Validar que la categorÃ­a pertenezca a la org y estÃ© activa
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE;

    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  -- Validar que la actividad pertenezca a la org y estÃ© activa
  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE;

    IF v_valid_activity IS NOT TRUE THEN
      RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET category_id = p_category_id,
      activity_id = p_activity_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Classification target unavailable in the active organization' USING ERRCODE='42501';
  END IF;
  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_movement_classification(
  p_movement_id UUID,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;

  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  PERFORM private.require_039_action('RECORD_VIEW'); PERFORM private.require_039_action('RECORD_CLASSIFY');
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;


  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE;
    IF v_valid_category IS NOT TRUE THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE;
    IF v_valid_activity IS NOT TRUE THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET category_id = p_category_id,
      activity_id = p_activity_id,
      updated_at = now(),
      updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Classification target unavailable in the active organization' USING ERRCODE='42501';
  END IF;
  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_operational_records_page(p_org_id UUID, p_after_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 500)
RETURNS SETOF JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL OR p_org_id IS NULL
    OR p_org_id IS DISTINCT FROM private.active_org_id()
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id AND is_active IS TRUE) THEN
    RAISE EXCEPTION 'Invalid operational context' USING ERRCODE = '42501';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'Page size must be between 1 and 500' USING ERRCODE = '22023';
  END IF;
  IF NOT private.can_operate_mica_org(p_org_id, 'RECORD_VIEW') THEN RETURN; END IF;
  RETURN QUERY SELECT jsonb_build_object(
    'id', r.id, 'organization_id', r.organization_id, 'record_type', r.record_type,
    'tipo_operacion', r.tipo_operacion, 'fecha', r.fecha, 'cuit', r.cuit,
    'razon_social', r.razon_social, 'comprobante', r.comprobante, 'total', r.total,
    'category_id', r.category_id, 'activity_id', r.activity_id,
    'updated_at', r.updated_at, 'updated_by', r.updated_by,
    'confirmada', (r.category_id IS NOT NULL),
    'normalized_payload', jsonb_strip_nulls(jsonb_build_object(
      'fecha', r.normalized_payload->'fecha', 'cuit', r.normalized_payload->'cuit',
      'razonSocial', r.normalized_payload->'razonSocial', 'tipo_cbte', r.normalized_payload->'tipo_cbte',
      'pdv', r.normalized_payload->'pdv', 'nroDesde', r.normalized_payload->'nroDesde',
      'nroHasta', r.normalized_payload->'nroHasta', 'moneda', r.normalized_payload->'moneda',
      'tipoCambio', r.normalized_payload->'tipoCambio', 'total', r.normalized_payload->'total',
      'totalIva', r.normalized_payload->'totalIva', 'otrosTributos', r.normalized_payload->'otrosTributos',
      'exento', r.normalized_payload->'exento', 'netoNoGravado', r.normalized_payload->'netoNoGravado',
      'netoGravado', r.normalized_payload->'netoGravado', 'alicuotas', r.normalized_payload->'alicuotas',
      'period', r.normalized_payload->'period', 'periodo', r.normalized_payload->'periodo',
      'regimen', r.normalized_payload->'regimen', 'sucursal', r.normalized_payload->'sucursal',
      'comprobante', r.normalized_payload->'comprobante', 'monto', r.normalized_payload->'monto',
      'amount', r.normalized_payload->'amount', 'jurisdiction', r.normalized_payload->'jurisdiction',
      'fuente', r.normalized_payload->'fuente')))
  FROM public.eco_normalized_records r
  WHERE r.organization_id = p_org_id AND r.deleted_at IS NULL
    AND (p_after_id IS NULL OR r.id > p_after_id)
  ORDER BY r.id LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_operational_financials_page(p_org_id UUID, p_after_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 500)
RETURNS SETOF JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL OR p_org_id IS NULL
    OR p_org_id IS DISTINCT FROM private.active_org_id()
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id AND is_active IS TRUE) THEN
    RAISE EXCEPTION 'Invalid operational context' USING ERRCODE = '42501';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'Page size must be between 1 and 500' USING ERRCODE = '22023';
  END IF;
  -- Financial SELECT maps to RECORD_VIEW (DEP-RLS-009). BANK_IMPORT/PAYROLL_IMPORT are writes.
  IF NOT private.can_operate_mica_org(p_org_id, 'RECORD_VIEW') THEN RETURN; END IF;
  RETURN QUERY SELECT jsonb_build_object(
    'id', f.id, 'organization_id', f.organization_id, 'operation_type', f.operation_type,
    'fecha', f.fecha, 'periodo', f.periodo,
    'category_id', f.category_id, 'activity_id', f.activity_id,
    'updated_at', f.updated_at, 'updated_by', f.updated_by,
    'confirmada', (f.category_id IS NOT NULL),
    'normalized_payload', jsonb_strip_nulls(jsonb_build_object(
      'fecha', f.normalized_payload->'fecha', 'fechaValor', f.normalized_payload->'fechaValor',
      'periodo', f.normalized_payload->'periodo', 'descripcion', f.normalized_payload->'descripcion',
      'tipo', f.normalized_payload->'tipo', 'monto', f.normalized_payload->'monto',
      'cuentaSugerida', f.normalized_payload->'cuentaSugerida', 'confirmada', f.normalized_payload->'confirmada',
      'sueldoBruto', f.normalized_payload->'sueldoBruto', 'sueldoBrutoCalculado', f.normalized_payload->'sueldoBrutoCalculado',
      'remunerativo', f.normalized_payload->'remunerativo', 'noRemunerativo', f.normalized_payload->'noRemunerativo',
      'anticipos', f.normalized_payload->'anticipos', 'anticipoSueldo', f.normalized_payload->'anticipoSueldo',
      'sindicatoAporte', f.normalized_payload->'sindicatoAporte', 'aporteSindicalCalculado', f.normalized_payload->'aporteSindicalCalculado',
      'aporteSindicalObligatorio', f.normalized_payload->'aporteSindicalObligatorio', 'sueldoNeto', f.normalized_payload->'sueldoNeto',
      'sacProporcional', f.normalized_payload->'sacProporcional', 'faecys', f.normalized_payload->'faecys',
      'costoLaboralReal', f.normalized_payload->'costoLaboralReal',
      'concepto', f.normalized_payload->'concepto', 'amount', f.normalized_payload->'amount',
      'categoria', f.normalized_payload->'categoria', 'category_id', f.normalized_payload->'category_id')))
  FROM public.eco_financial_movements f
  WHERE f.organization_id = p_org_id AND f.deleted_at IS NULL
    AND (p_after_id IS NULL OR f.id > p_after_id)
  ORDER BY f.id LIMIT p_limit;
END;
$$;

DO $verify$
DECLARE v_saved RECORD;
BEGIN
  FOR v_saved IN SELECT * FROM private.migration_039e_functions LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_saved.signature)
      AND proowner=v_saved.owner_oid AND proacl IS NOT DISTINCT FROM v_saved.acl) THEN
      RAISE EXCEPTION '039e owner/ACL changed: %',v_saved.signature;
    END IF;
  END LOOP;
  UPDATE private.migration_039e_functions SET installed_definition=pg_get_functiondef(to_regprocedure(signature));
END; $verify$;
COMMIT;
