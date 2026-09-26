-- Phase 1. Review and apply manually; no change to can_org or catalog assignment authority.
BEGIN;

DO $preflight$
DECLARE
  v RECORD;
  v_rel REGCLASS;
  v_keys SMALLINT[];
BEGIN
  IF to_regprocedure('private.current_profile_id()') IS NULL
    OR to_regprocedure('private.active_org_id()') IS NULL
    OR to_regprocedure('private.can_platform(text)') IS NULL
    OR to_regprocedure('private.can_org(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '035: missing canonical authorization helpers';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('public.switch_superadmin_org_context(uuid)')
      AND prorettype = 'void'::regtype AND proargnames = ARRAY['p_org_id']::text[]
      AND prosecdef AND NOT proretset AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION '035: switch_superadmin_org_context signature differs from reviewed contract';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
    AND table_name = 'eco_organizations' AND column_name = 'is_active' AND data_type = 'boolean') THEN
    RAISE EXCEPTION '035: eco_organizations.is_active boolean required';
  END IF;
  -- 035 is a one-shot migration: never overwrite a baseline or preexisting RPC.
  IF to_regclass('private.migration_035_backup') IS NOT NULL THEN
    RAISE EXCEPTION '035: backup already exists; do not reapply';
  END IF;
  FOR v IN SELECT unnest(ARRAY[
    'public.list_operational_org_targets()', 'public.get_my_operational_context()',
    'public.get_operational_snapshot(uuid)',
    'public.get_operational_records_page(uuid,uuid,integer)',
    'public.get_operational_financials_page(uuid,uuid,integer)'
  ]) AS signature LOOP
    IF to_regprocedure(v.signature) IS NOT NULL THEN
      RAISE EXCEPTION '035: new RPC already exists: %', v.signature;
    END IF;
  END LOOP;
  FOR v IN SELECT * FROM (VALUES
    ('auth.uid()', 'uuid'), ('private.current_profile_id()', 'uuid'),
    ('private.active_org_id()', 'uuid'), ('private.can_platform(text)', 'boolean'),
    ('private.can_org(uuid,text)', 'boolean')
  ) AS required(signature, result_type) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure(v.signature)
      AND prorettype = to_regtype(v.result_type) AND NOT proretset) THEN
      RAISE EXCEPTION '035: helper contract differs: %', v.signature;
    END IF;
  END LOOP;
  -- Only columns consumed by the functions below (including filters and writes).
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_profiles','id','uuid'), ('eco_user_profiles','organization_id','uuid'),
    ('eco_organizations','id','uuid'), ('eco_organizations','name','text'), ('eco_organizations','is_active','boolean'),
    ('eco_user_active_context','user_profile_id','uuid'), ('eco_user_active_context','organization_id','uuid'),
    ('eco_user_active_context','updated_at','timestamp with time zone'),
    ('eco_platform_audit_events','actor_user_profile_id','uuid'), ('eco_platform_audit_events','event_type','text'),
    ('eco_platform_audit_events','metadata','jsonb'),
    ('eco_organization_members','user_profile_id','uuid'), ('eco_organization_members','organization_id','uuid'),
    ('eco_organization_members','role_template_id','uuid'), ('eco_organization_members','is_active','boolean'),
    ('eco_user_platform_role','user_profile_id','uuid'), ('eco_user_platform_role','role_template_id','uuid'),
    ('eco_user_platform_role','is_active','boolean'),
    ('eco_role_templates','id','uuid'), ('eco_role_templates','name','text'),
    ('eco_role_templates','scope','text'), ('eco_role_templates','is_active','boolean'),
    ('eco_tax_categories','id','uuid'), ('eco_tax_categories','name','text'),
    ('eco_tax_categories','description','text'), ('eco_tax_categories','category_type','text'),
    ('eco_org_tax_categories','id','uuid'), ('eco_org_tax_categories','organization_id','uuid'),
    ('eco_org_tax_categories','category_id','uuid'), ('eco_org_tax_categories','custom_name','text'),
    ('eco_org_tax_categories','is_active','boolean'), ('eco_org_tax_categories','is_assigned','boolean'),
    ('eco_economic_activities','id','uuid'), ('eco_economic_activities','name','text'),
    ('eco_economic_activities','arca_code','text'), ('eco_economic_activities','description','text'),
    ('eco_org_economic_activities','organization_id','uuid'), ('eco_org_economic_activities','activity_id','uuid'),
    ('eco_org_economic_activities','is_active','boolean'), ('eco_org_economic_activities','is_assigned','boolean'),
    ('eco_org_activity_iibb_rates','id','uuid'), ('eco_org_activity_iibb_rates','organization_id','uuid'),
    ('eco_org_activity_iibb_rates','activity_id','uuid'), ('eco_org_activity_iibb_rates','jurisdiction','text'),
    ('eco_org_activity_iibb_rates','rate','numeric'), ('eco_org_activity_iibb_rates','valid_from','date'),
    ('eco_org_activity_iibb_rates','valid_to','date'), ('eco_org_activity_iibb_rates','is_active','boolean'),
    ('eco_normalized_records','id','uuid'), ('eco_normalized_records','organization_id','uuid'),
    ('eco_normalized_records','record_type','text'), ('eco_normalized_records','tipo_operacion','text'),
    ('eco_normalized_records','fecha','date'), ('eco_normalized_records','cuit','text'),
    ('eco_normalized_records','razon_social','text'), ('eco_normalized_records','comprobante','text'),
    ('eco_normalized_records','total','numeric'), ('eco_normalized_records','categoria','text'),
    ('eco_normalized_records','confirmada','boolean'), ('eco_normalized_records','normalized_payload','jsonb'),
    ('eco_normalized_records','deleted_at','timestamp with time zone'),
    ('eco_financial_movements','id','uuid'), ('eco_financial_movements','organization_id','uuid'),
    ('eco_financial_movements','operation_type','text'), ('eco_financial_movements','fecha','date'),
    ('eco_financial_movements','periodo','text'), ('eco_financial_movements','normalized_payload','jsonb'),
    ('eco_financial_movements','deleted_at','timestamp with time zone')
  ) AS required(table_name, column_name, type_name) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      WHERE c.oid = to_regclass('public.' || v.table_name) AND c.relkind IN ('r','p')
        AND a.attname = v.column_name AND a.atttypid = to_regtype(v.type_name)
        AND a.attnum > 0 AND NOT a.attisdropped) THEN
      RAISE EXCEPTION '035: missing/incompatible %.% (%)', v.table_name, v.column_name, v.type_name;
    END IF;
  END LOOP;
  -- Exact unique keys used by ON CONFLICT, identity resolution, joins and page cursors.
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_active_context', ARRAY['user_profile_id']),
    ('eco_user_platform_role', ARRAY['user_profile_id']),
    ('eco_organization_members', ARRAY['organization_id','user_profile_id']),
    ('eco_user_profiles', ARRAY['id']), ('eco_organizations', ARRAY['id']),
    ('eco_role_templates', ARRAY['id']), ('eco_tax_categories', ARRAY['id']),
    ('eco_economic_activities', ARRAY['id']), ('eco_normalized_records', ARRAY['id']),
    ('eco_financial_movements', ARRAY['id'])
  ) AS required(table_name, columns) LOOP
    v_rel := to_regclass('public.' || v.table_name);
    SELECT array_agg(attnum ORDER BY attnum) INTO v_keys
      FROM pg_attribute WHERE attrelid = v_rel AND attname = ANY(v.columns);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = v_rel
      AND c.contype IN ('p','u') AND NOT c.condeferrable AND c.convalidated
      AND cardinality(c.conkey) = cardinality(v.columns) AND c.conkey @> v_keys) THEN
      RAISE EXCEPTION '035: non-deferrable unique key missing on % (%)', v.table_name, v.columns;
    END IF;
  END LOOP;
  -- Identity/assignment foreign keys required by context/profile resolution and catalog joins.
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_active_context','user_profile_id','eco_user_profiles','id'),
    ('eco_user_active_context','organization_id','eco_organizations','id'),
    ('eco_platform_audit_events','actor_user_profile_id','eco_user_profiles','id'),
    ('eco_organization_members','user_profile_id','eco_user_profiles','id'),
    ('eco_organization_members','organization_id','eco_organizations','id'),
    ('eco_organization_members','role_template_id','eco_role_templates','id'),
    ('eco_user_platform_role','user_profile_id','eco_user_profiles','id'),
    ('eco_user_platform_role','role_template_id','eco_role_templates','id'),
    ('eco_org_tax_categories','category_id','eco_tax_categories','id'),
    ('eco_org_economic_activities','activity_id','eco_economic_activities','id'),
    ('eco_org_activity_iibb_rates','activity_id','eco_economic_activities','id'),
    ('eco_normalized_records','organization_id','eco_organizations','id'),
    ('eco_financial_movements','organization_id','eco_organizations','id')
  ) AS required(source_table, source_column, target_table, target_column) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
      JOIN pg_attribute s ON s.attrelid = c.conrelid AND c.conkey = ARRAY[s.attnum]::smallint[]
      JOIN pg_attribute t ON t.attrelid = c.confrelid AND c.confkey = ARRAY[t.attnum]::smallint[]
      WHERE c.contype = 'f' AND c.convalidated
        AND c.conrelid = to_regclass('public.' || v.source_table) AND s.attname = v.source_column
        AND c.confrelid = to_regclass('public.' || v.target_table) AND t.attname = v.target_column) THEN
      RAISE EXCEPTION '035: required FK missing: %.% -> %.%',
        v.source_table, v.source_column, v.target_table, v.target_column;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.eco_platform_audit_events'::regclass
    AND t.tgname = 'enforce_append_only_platform_audit' AND t.tgenabled IN ('O','A')
    AND t.tgfoid = to_regprocedure('private.prevent_audit_mutation()')) THEN
    RAISE EXCEPTION '035: platform audit append-only trigger missing/disabled';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid IN
      ('public.eco_user_active_context'::regclass, 'public.eco_user_profiles'::regclass)
      AND attname = 'organization_id' AND attnotnull) THEN
    RAISE EXCEPTION '035: NULL platform context must be allowed';
  END IF;
  -- Audit/context inserts must not encounter an unknown required column without a default.
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_active_context', ARRAY['user_profile_id','organization_id','updated_at']),
    ('eco_platform_audit_events', ARRAY['actor_user_profile_id','event_type','metadata'])
  ) AS required(table_name, supplied) LOOP
    IF EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = to_regclass('public.' || v.table_name)
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attnotnull AND NOT a.atthasdef
      AND a.attidentity = '' AND a.attgenerated = '' AND NOT a.attname = ANY(v.supplied)) THEN
      RAISE EXCEPTION '035: unsupported required insert column on %', v.table_name;
    END IF;
  END LOOP;
END;
$preflight$;

-- Capture the actual LIVE definition and ACL, not a reconstruction of migration 022.
CREATE TABLE private.migration_035_backup (
  signature TEXT PRIMARY KEY, definition TEXT NOT NULL, owner_name TEXT NOT NULL, acl JSONB NOT NULL
);
REVOKE ALL ON TABLE private.migration_035_backup FROM PUBLIC, anon, authenticated;
INSERT INTO private.migration_035_backup
SELECT 'public.switch_superadmin_org_context(uuid)', pg_get_functiondef(p.oid), pg_get_userbyid(p.proowner),
  COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'role', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
    'grantor', pg_get_userbyid(a.grantor), 'privilege', a.privilege_type, 'grantable', a.is_grantable))
    FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a), '[]'::jsonb)
FROM pg_proc p WHERE p.oid = 'public.switch_superadmin_org_context(uuid)'::regprocedure;

CREATE OR REPLACE FUNCTION public.list_operational_org_targets()
RETURNS TABLE(organization_id UUID, organization_name TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
    OR NOT COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'ACCESS_ANY_ORG required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT o.id, o.name::TEXT FROM public.eco_organizations o
    WHERE o.is_active IS TRUE ORDER BY o.name, o.id;
END;
$$;

-- Keep the existing UUID -> VOID signature. Context is subsequently read canonically.
CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context(p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_profile UUID := private.current_profile_id();
  v_previous UUID;
BEGIN
  IF auth.uid() IS NULL OR v_profile IS NULL
    OR NOT COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'ACCESS_ANY_ORG required' USING ERRCODE = '42501';
  END IF;
  -- Serialize context changes for this profile, including the initial context insert.
  PERFORM 1 FROM public.eco_user_profiles WHERE id = v_profile FOR UPDATE;
  IF p_org_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.eco_organizations WHERE id = p_org_id AND is_active IS TRUE
  ) THEN
    RAISE EXCEPTION 'Organization missing or inactive' USING ERRCODE = '22023';
  END IF;
  v_previous := private.active_org_id();
  UPDATE public.eco_user_profiles SET organization_id = p_org_id WHERE id = v_profile;
  INSERT INTO public.eco_user_active_context(user_profile_id, organization_id, updated_at)
  VALUES (v_profile, p_org_id, clock_timestamp())
  ON CONFLICT (user_profile_id) DO UPDATE
    SET organization_id = EXCLUDED.organization_id, updated_at = EXCLUDED.updated_at;
  INSERT INTO public.eco_platform_audit_events(actor_user_profile_id, event_type, metadata)
  VALUES (v_profile, 'SUPERADMIN_ORG_CONTEXT_SWITCHED',
    jsonb_build_object('previous_organization_id', v_previous, 'target_organization_id', p_org_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_operational_context()
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_profile UUID := private.current_profile_id();
  v_org UUID := private.active_org_id();
  v_name TEXT;
  v_preset TEXT;
  v_scope TEXT;
BEGIN
  IF auth.uid() IS NULL OR v_profile IS NULL THEN
    RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE = '42501';
  END IF;
  IF v_org IS NOT NULL THEN
    SELECT o.name INTO v_name FROM public.eco_organizations o WHERE o.id = v_org AND o.is_active IS TRUE;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Organization missing or inactive' USING ERRCODE = '42501'; END IF;
    IF NOT COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE)
      AND NOT EXISTS (SELECT 1 FROM public.eco_organization_members m
        WHERE m.user_profile_id = v_profile AND m.organization_id = v_org AND m.is_active IS TRUE) THEN
      RAISE EXCEPTION 'Active membership required' USING ERRCODE = '42501';
    END IF;
    SELECT t.name, t.scope INTO v_preset, v_scope
    FROM public.eco_organization_members m JOIN public.eco_role_templates t ON t.id = m.role_template_id
    WHERE m.user_profile_id = v_profile AND m.organization_id = v_org AND m.is_active IS TRUE
      AND t.is_active IS TRUE AND t.scope = 'ORGANIZATION';
  END IF;
  IF v_preset IS NULL THEN
    SELECT t.name, t.scope INTO v_preset, v_scope
    FROM public.eco_user_platform_role r JOIN public.eco_role_templates t ON t.id = r.role_template_id
    WHERE r.user_profile_id = v_profile AND r.is_active IS TRUE AND t.is_active IS TRUE AND t.scope = 'PLATFORM';
  END IF;
  RETURN jsonb_build_object('organization_id', v_org, 'organization_name', v_name,
    'profile_name', v_preset, 'profile_scope', v_scope);
END;
$$;

-- Explicit read-only owner access, scoped to the confirmed active organization.
-- Small configuration datasets only; historical rows use separate bounded readers.
-- Never grants mutation capabilities, membership, or catalog activation authority.
CREATE OR REPLACE FUNCTION public.get_operational_snapshot(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_owner BOOLEAN := COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE);
  v_catalog BOOLEAN;
  v_rates BOOLEAN;
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL OR p_org_id IS NULL
    OR p_org_id IS DISTINCT FROM private.active_org_id()
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id AND is_active IS TRUE) THEN
    RAISE EXCEPTION 'Invalid operational context' USING ERRCODE = '42501';
  END IF;
  v_catalog := v_owner OR COALESCE(private.can_org(p_org_id, 'ORG_VIEW'), FALSE);
  -- DEP-RLS-014: IIBB read authority is CATALOG_ORG_VIEW, not ORG_VIEW.
  v_rates := v_owner OR COALESCE(private.can_org(p_org_id, 'CATALOG_ORG_VIEW'), FALSE);
  RETURN jsonb_build_object(
    'organization_id', p_org_id,
    'categories', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'org_assignment_id', a.id,
      'organization_id', a.organization_id, 'name', COALESCE(a.custom_name, c.name), 'description', c.description,
      'category_type', c.category_type, 'is_active', a.is_active, 'is_assigned', a.is_assigned) ORDER BY c.name, c.id)
      FROM public.eco_org_tax_categories a JOIN public.eco_tax_categories c ON c.id = a.category_id
      WHERE v_catalog AND a.organization_id = p_org_id AND a.is_assigned IS TRUE), '[]'::jsonb),
    'activities', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', e.id, 'organization_id', a.organization_id,
      'name', e.name, 'arca_code', e.arca_code, 'description', e.description,
      'is_active', a.is_active, 'is_assigned', a.is_assigned) ORDER BY e.arca_code, e.id)
      FROM public.eco_org_economic_activities a JOIN public.eco_economic_activities e ON e.id = a.activity_id
      WHERE v_catalog AND a.organization_id = p_org_id AND a.is_assigned IS TRUE), '[]'::jsonb),
    'rates', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id', r.id, 'organization_id', r.organization_id, 'activity_id', r.activity_id,
      'jurisdiction', r.jurisdiction, 'rate', r.rate, 'valid_from', r.valid_from,
      'valid_to', r.valid_to, 'is_active', r.is_active) ORDER BY r.id)
      FROM public.eco_org_activity_iibb_rates r WHERE v_rates AND r.organization_id = p_org_id AND r.is_active IS TRUE), '[]'::jsonb)
  );
END;
$$;

-- Minimal explicit historical readers. UUID keyset traversal uses the existing PK;
-- every call checks the expected confirmed org, including empty/unauthorized pages.
CREATE FUNCTION public.get_operational_records_page(p_org_id UUID, p_after_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 500)
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
  IF NOT (COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE)
    OR COALESCE(private.can_org(p_org_id, 'RECORD_VIEW'), FALSE)) THEN RETURN; END IF;
  RETURN QUERY SELECT jsonb_build_object(
    'id', r.id, 'organization_id', r.organization_id, 'record_type', r.record_type,
    'tipo_operacion', r.tipo_operacion, 'fecha', r.fecha, 'cuit', r.cuit,
    'razon_social', r.razon_social, 'comprobante', r.comprobante, 'total', r.total,
    'categoria', r.categoria, 'confirmada', r.confirmada,
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

CREATE FUNCTION public.get_operational_financials_page(p_org_id UUID, p_after_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 500)
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
  IF NOT (COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE)
    OR COALESCE(private.can_org(p_org_id, 'RECORD_VIEW'), FALSE)) THEN RETURN; END IF;
  RETURN QUERY SELECT jsonb_build_object(
    'id', f.id, 'organization_id', f.organization_id, 'operation_type', f.operation_type,
    'fecha', f.fecha, 'periodo', f.periodo,
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

REVOKE ALL ON FUNCTION public.get_operational_records_page(UUID, UUID, INTEGER) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_operational_financials_page(UUID, UUID, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_operational_records_page(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_operational_financials_page(UUID, UUID, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION public.list_operational_org_targets() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.switch_superadmin_org_context(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_my_operational_context() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_operational_snapshot(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_operational_org_targets() TO authenticated;
GRANT EXECUTE ON FUNCTION public.switch_superadmin_org_context(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_operational_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_operational_snapshot(UUID) TO authenticated;
COMMIT;
