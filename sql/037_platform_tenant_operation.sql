-- 037: prepare locally, apply manually. 036 is already LIVE validated.
-- Scope is not action authority. No membership or capability grants are seeded.
BEGIN;
DO $preflight$
DECLARE v RECORD;
BEGIN
  IF to_regprocedure('private.is_platform_owner()') IS NULL
    OR to_regclass('private.eco_platform_owner') IS NULL THEN RAISE EXCEPTION '037: applied 036 required'; END IF;
  IF to_regclass('private.eco_platform_org_scopes') IS NOT NULL
    OR to_regclass('private.eco_platform_org_overrides') IS NOT NULL
    OR to_regclass('private.migration_037_functions') IS NOT NULL THEN RAISE EXCEPTION '037: target objects exist'; END IF;
  FOR v IN SELECT unnest(ARRAY['private.mica_capability_allowed(text,text)', 'private.has_mica_platform_role()',
    'private.platform_org_in_scope(uuid)', 'private.can_operate_mica_org(uuid,text)',
    'private.guard_037_platform_override()', 'public.can_operate_mica_org(uuid,text)']) signature LOOP
    IF to_regprocedure(v.signature) IS NOT NULL THEN RAISE EXCEPTION '037: target function exists: %',v.signature; END IF;
  END LOOP;
  -- Only dependencies consumed by the new scope/action contract (existing 035 datasets unchanged).
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_profiles','id','uuid'),('eco_user_profiles','auth_user_id','uuid'),('eco_user_profiles','is_active','boolean'),
    ('eco_organizations','id','uuid'),('eco_organizations','is_active','boolean'),
    ('eco_capabilities','id','uuid'),('eco_capabilities','code','text'),('eco_capabilities','scope','text'),('eco_capabilities','is_active','boolean'),
    ('eco_role_templates','id','uuid'),('eco_role_templates','scope','text'),('eco_role_templates','is_active','boolean'),
    ('eco_user_platform_role','user_profile_id','uuid'),('eco_user_platform_role','role_template_id','uuid'),('eco_user_platform_role','is_active','boolean'),
    ('eco_platform_role_org_capabilities','role_template_id','uuid'),('eco_platform_role_org_capabilities','capability_id','uuid'),
    ('eco_organization_members','id','uuid'),('eco_organization_members','user_profile_id','uuid'),
    ('eco_organization_members','organization_id','uuid'),('eco_organization_members','is_active','boolean'),
    ('eco_membership_capability_overrides','membership_id','uuid'),('eco_membership_capability_overrides','capability_id','uuid'),
    ('eco_membership_capability_overrides','effect','text'),
    ('eco_user_active_context','user_profile_id','uuid'),('eco_user_active_context','organization_id','uuid')
  ) expected(table_name,column_name,type_name) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('public.'||v.table_name)
      AND attname=v.column_name AND atttypid=to_regtype(v.type_name) AND NOT attisdropped) THEN
      RAISE EXCEPTION '037: dependency column mismatch %.%',v.table_name,v.column_name; END IF;
  END LOOP;
  -- Exact reviewed function bodies. Drift must be reviewed, never overwritten silently.
  FOR v IN SELECT * FROM (VALUES
    ('public.list_operational_org_targets()','21ca0fd70a2156b423e2ad1d3c6f8e6a'),
    ('public.switch_superadmin_org_context(uuid)','7e62e451c05441a8a3d08babc0d5b93b'),
    ('public.get_my_operational_context()','1e8524864477fb894b63675e41b299a6'),
    ('public.get_operational_snapshot(uuid)','9bd321f3e25da50cc70db90011c862f4'),
    ('public.get_operational_records_page(uuid,uuid,integer)','ae29ebf59867886ccd8225ee898750ca'),
    ('public.get_operational_financials_page(uuid,uuid,integer)','746745eb623a171508627eb2ba468987'),
    ('public.get_my_effective_capabilities(uuid)','44aeed171597bf4bafe35796e5dfaacf'),
    ('private.catalog_activation_org(text)','126901e251ff20119641dbb0685252d6'),
    ('public.get_capability_delegation_contract()','b3e959fd24d5fdb8e31fb3e992784f54')
  ) expected(signature,body_hash) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v.signature) AND prosecdef
      AND pg_get_userbyid(proowner)=current_user AND proconfig @> ARRAY['search_path=""']
      AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v.body_hash) THEN
      RAISE EXCEPTION '037: reviewed function contract differs: %',v.signature; END IF;
    -- Preserve only a safe baseline; CREATE OR REPLACE inherits existing ACLs.
    IF v.signature LIKE 'public.%' THEN
      IF has_function_privilege('anon',v.signature,'EXECUTE')
        OR NOT has_function_privilege('authenticated',v.signature,'EXECUTE') THEN
        RAISE EXCEPTION '037: public RPC ACL differs: %',v.signature; END IF;
    ELSIF has_function_privilege('anon',v.signature,'EXECUTE')
      OR has_function_privilege('authenticated',v.signature,'EXECUTE') THEN
      RAISE EXCEPTION '037: private helper ACL differs: %',v.signature;
    END IF;
  END LOOP;
  -- Missing optional MICA codes are not created; existing codes must have the reviewed scope.
  IF EXISTS (SELECT 1 FROM (VALUES ('PLATFORM_MANAGE','PLATFORM'),
    ('GLOBAL_USER_MANAGE','PLATFORM'),
    ('PLAN_MANAGE','PLATFORM'),
    ('ACCESS_ANY_ORG','PLATFORM'),
    ('SUPPORT_IMPERSONATE','PLATFORM'),
    ('HARD_DELETE_EXCEPTIONAL','PLATFORM'),
    ('ORGANIZATION_CREATE','PLATFORM'),
    ('ORGANIZATION_UPDATE','PLATFORM'),
    ('ORGANIZATION_ARCHIVE','PLATFORM'),
    ('PLATFORM_MIGRATIONS_APPLY','PLATFORM'),
    ('PLATFORM_TENANTS_PROVISION','PLATFORM'),
    ('PLATFORM_SYSTEM_MONITOR','PLATFORM'),
    ('GLOBAL_CATALOG_VIEW','PLATFORM'),
    ('GLOBAL_CATALOG_MANAGE','PLATFORM'),
    ('CATALOG_ASSIGN_ANY_ORG','PLATFORM'),
    ('RATE_MANAGE_ANY_ORG','PLATFORM'),
    ('REPORT_COMPARE_SCOPED_ORGS','PLATFORM'),
    ('REPORT_CONSOLIDATED_SCOPED_ORGS','PLATFORM'),
    ('SAAS_ANALYTICS_VIEW','PLATFORM'),
    ('AUDIT_PLATFORM_VIEW','PLATFORM'),
    ('ORG_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_VIEW','ORGANIZATION'),
    ('ORG_MEMBER_INVITE','ORGANIZATION'),
    ('ORG_MEMBER_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_PERMISSION_MANAGE','ORGANIZATION'),
    ('IMPORT_VIEW','ORGANIZATION'),
    ('IMPORT_CREATE','ORGANIZATION'),
    ('IMPORT_RETRY','ORGANIZATION'),
    ('IMPORT_REVIEW','ORGANIZATION'),
    ('RECORD_VIEW','ORGANIZATION'),
    ('RECORD_CLASSIFY','ORGANIZATION'),
    ('RECORD_SOFT_DELETE','ORGANIZATION'),
    ('RECORD_RESTORE','ORGANIZATION'),
    ('PERCEPTION_IMPORT','ORGANIZATION'),
    ('BANK_IMPORT','ORGANIZATION'),
    ('PAYROLL_IMPORT','ORGANIZATION'),
    ('ISSUE_RESOLVE','ORGANIZATION'),
    ('CATALOG_ORG_VIEW','ORGANIZATION'),
    ('CATALOG_ACTIVITY_MANAGE','ORGANIZATION'),
    ('CATALOG_CATEGORY_MANAGE','ORGANIZATION'),
    ('REPORT_VIEW','ORGANIZATION'),
    ('REPORT_EXPORT','ORGANIZATION'),
    ('TICKET_CREATE','ORGANIZATION'),
    ('TICKET_VIEW_ORG','ORGANIZATION'),
    ('AUDIT_VIEW_ORG','ORGANIZATION'),
    ('FINANCIAL_ALLOCATION_EDIT','ORGANIZATION'),
    ('SENSITIVEDATA_BANKING_READ','ORGANIZATION'),
    ('SENSITIVEDATA_SALARIES_READ','ORGANIZATION'),
    ('DOCUMENTS_UPLOAD','ORGANIZATION'),
    ('DOCUMENTS_OCR_PROCESS','ORGANIZATION'),
    ('DOCUMENTS_OCR_VERIFY','ORGANIZATION')) expected(code,scope)
    JOIN public.eco_capabilities c ON c.code=expected.code WHERE c.scope IS DISTINCT FROM expected.scope) THEN
    RAISE EXCEPTION '037: MICA capability scope drift'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
    WHERE p.auth_user_id=o.auth_user_id AND p.is_active) THEN RAISE EXCEPTION '037: active coherent structural root required'; END IF;
END;
$preflight$;

CREATE TABLE private.migration_037_functions (
  signature TEXT PRIMARY KEY, definition TEXT NOT NULL, owner_name TEXT NOT NULL,
  acl ACLITEM[], installed_definition TEXT
);
INSERT INTO private.migration_037_functions(signature,definition,owner_name,acl)
SELECT oid::regprocedure::TEXT,pg_get_functiondef(oid),pg_get_userbyid(proowner),proacl FROM pg_proc
WHERE oid IN ('public.list_operational_org_targets()'::regprocedure,
    'public.switch_superadmin_org_context(uuid)'::regprocedure,
    'public.get_my_operational_context()'::regprocedure,
    'public.get_operational_snapshot(uuid)'::regprocedure,
    'public.get_operational_records_page(uuid,uuid,integer)'::regprocedure,
    'public.get_operational_financials_page(uuid,uuid,integer)'::regprocedure,
    'public.get_my_effective_capabilities(uuid)'::regprocedure,
    'private.catalog_activation_org(text)'::regprocedure,
    'public.get_capability_delegation_contract()'::regprocedure);

CREATE TABLE private.eco_platform_org_scopes (
  user_profile_id UUID NOT NULL REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT,
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_profile_id,organization_id)
);
CREATE TABLE private.eco_platform_org_overrides (
  user_profile_id UUID NOT NULL REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT,
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id) ON DELETE RESTRICT,
  capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE RESTRICT,
  effect TEXT NOT NULL CHECK(effect IN ('ALLOW','DENY')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(user_profile_id,organization_id,capability_id)
);
ALTER TABLE private.eco_platform_org_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_platform_org_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.migration_037_functions ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION private.mica_capability_allowed(p_code TEXT,p_scope TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM (VALUES
    ('PLATFORM_MANAGE','PLATFORM'),
    ('GLOBAL_USER_MANAGE','PLATFORM'),
    ('PLAN_MANAGE','PLATFORM'),
    ('ACCESS_ANY_ORG','PLATFORM'),
    ('SUPPORT_IMPERSONATE','PLATFORM'),
    ('HARD_DELETE_EXCEPTIONAL','PLATFORM'),
    ('ORGANIZATION_CREATE','PLATFORM'),
    ('ORGANIZATION_UPDATE','PLATFORM'),
    ('ORGANIZATION_ARCHIVE','PLATFORM'),
    ('PLATFORM_MIGRATIONS_APPLY','PLATFORM'),
    ('PLATFORM_TENANTS_PROVISION','PLATFORM'),
    ('PLATFORM_SYSTEM_MONITOR','PLATFORM'),
    ('GLOBAL_CATALOG_VIEW','PLATFORM'),
    ('GLOBAL_CATALOG_MANAGE','PLATFORM'),
    ('CATALOG_ASSIGN_ANY_ORG','PLATFORM'),
    ('RATE_MANAGE_ANY_ORG','PLATFORM'),
    ('REPORT_COMPARE_SCOPED_ORGS','PLATFORM'),
    ('REPORT_CONSOLIDATED_SCOPED_ORGS','PLATFORM'),
    ('SAAS_ANALYTICS_VIEW','PLATFORM'),
    ('AUDIT_PLATFORM_VIEW','PLATFORM'),
    ('ORG_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_VIEW','ORGANIZATION'),
    ('ORG_MEMBER_INVITE','ORGANIZATION'),
    ('ORG_MEMBER_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_PERMISSION_MANAGE','ORGANIZATION'),
    ('IMPORT_VIEW','ORGANIZATION'),
    ('IMPORT_CREATE','ORGANIZATION'),
    ('IMPORT_RETRY','ORGANIZATION'),
    ('IMPORT_REVIEW','ORGANIZATION'),
    ('RECORD_VIEW','ORGANIZATION'),
    ('RECORD_CLASSIFY','ORGANIZATION'),
    ('RECORD_SOFT_DELETE','ORGANIZATION'),
    ('RECORD_RESTORE','ORGANIZATION'),
    ('PERCEPTION_IMPORT','ORGANIZATION'),
    ('BANK_IMPORT','ORGANIZATION'),
    ('PAYROLL_IMPORT','ORGANIZATION'),
    ('ISSUE_RESOLVE','ORGANIZATION'),
    ('CATALOG_ORG_VIEW','ORGANIZATION'),
    ('CATALOG_ACTIVITY_MANAGE','ORGANIZATION'),
    ('CATALOG_CATEGORY_MANAGE','ORGANIZATION'),
    ('REPORT_VIEW','ORGANIZATION'),
    ('REPORT_EXPORT','ORGANIZATION'),
    ('TICKET_CREATE','ORGANIZATION'),
    ('TICKET_VIEW_ORG','ORGANIZATION'),
    ('AUDIT_VIEW_ORG','ORGANIZATION'),
    ('FINANCIAL_ALLOCATION_EDIT','ORGANIZATION'),
    ('SENSITIVEDATA_BANKING_READ','ORGANIZATION'),
    ('SENSITIVEDATA_SALARIES_READ','ORGANIZATION'),
    ('DOCUMENTS_UPLOAD','ORGANIZATION'),
    ('DOCUMENTS_OCR_PROCESS','ORGANIZATION'),
    ('DOCUMENTS_OCR_VERIFY','ORGANIZATION')
  ) allowed(code,scope) WHERE code=p_code AND scope=p_scope);
$$;

CREATE FUNCTION private.has_mica_platform_role()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.eco_user_platform_role r JOIN public.eco_role_templates t ON t.id=r.role_template_id
    WHERE r.user_profile_id=private.current_profile_id() AND r.is_active AND t.is_active AND t.scope='PLATFORM');
$$;

CREATE FUNCTION private.platform_org_in_scope(p_org_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_org_id IS NOT NULL AND private.has_mica_platform_role()
    AND EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org_id AND is_active)
    AND ((private.is_platform_owner() AND COALESCE(private.can_platform('ACCESS_ANY_ORG'),FALSE))
      OR EXISTS (SELECT 1 FROM private.eco_platform_org_scopes s
        WHERE s.user_profile_id=private.current_profile_id() AND s.organization_id=p_org_id AND s.is_active));
$$;

CREATE FUNCTION private.can_operate_mica_org(p_org_id UUID,p_capability_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_profile UUID := private.current_profile_id();
  v_cap UUID;
  v_membership UUID;
  v_platform_scope BOOLEAN;
  v_override TEXT;
BEGIN
  IF auth.uid() IS NULL OR v_profile IS NULL OR p_org_id IS NULL
    OR NOT private.mica_capability_allowed(p_capability_code,'ORGANIZATION')
    OR NOT EXISTS (SELECT 1 FROM public.eco_user_active_context
      WHERE user_profile_id=v_profile AND organization_id=p_org_id)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org_id AND is_active) THEN RETURN FALSE; END IF;
  SELECT id INTO v_cap FROM public.eco_capabilities WHERE code=p_capability_code AND scope='ORGANIZATION' AND is_active;
  IF v_cap IS NULL THEN RETURN FALSE; END IF;
  SELECT id INTO v_membership FROM public.eco_organization_members
    WHERE user_profile_id=v_profile AND organization_id=p_org_id AND is_active;
  v_platform_scope := private.platform_org_in_scope(p_org_id);
  IF v_membership IS NULL AND NOT v_platform_scope THEN RETURN FALSE; END IF;
  -- DENY wins across applicable membership and platform paths; no OR bypass.
  IF EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides
    WHERE membership_id=v_membership AND capability_id=v_cap AND effect='DENY') THEN RETURN FALSE; END IF;
  IF private.has_mica_platform_role() THEN
    SELECT effect INTO v_override FROM private.eco_platform_org_overrides
      WHERE user_profile_id=v_profile AND organization_id=p_org_id AND capability_id=v_cap;
    IF v_override='DENY' THEN RETURN FALSE; END IF;
  END IF;
  IF v_membership IS NOT NULL AND COALESCE(private.can_org(p_org_id,p_capability_code),FALSE) THEN RETURN TRUE; END IF;
  IF NOT v_platform_scope THEN RETURN FALSE; END IF;
  IF v_override='ALLOW' THEN RETURN TRUE; END IF;
  RETURN EXISTS (SELECT 1 FROM public.eco_user_platform_role r
    JOIN public.eco_role_templates t ON t.id=r.role_template_id
    JOIN public.eco_platform_role_org_capabilities g ON g.role_template_id=t.id
    WHERE r.user_profile_id=v_profile AND r.is_active AND t.is_active AND t.scope='PLATFORM' AND g.capability_id=v_cap);
END;
$$;

CREATE FUNCTION private.guard_037_platform_override()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.eco_capabilities c WHERE c.id=NEW.capability_id
    AND c.scope='ORGANIZATION' AND c.is_active AND private.mica_capability_allowed(c.code,c.scope)) THEN
    RAISE EXCEPTION '037: override requires active approved MICA organization capability' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER guard_037_platform_override BEFORE INSERT OR UPDATE ON private.eco_platform_org_overrides
FOR EACH ROW EXECUTE FUNCTION private.guard_037_platform_override();

CREATE FUNCTION public.can_operate_mica_org(p_org_id UUID,p_capability_code TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.can_operate_mica_org(p_org_id,p_capability_code);
$$;

CREATE OR REPLACE FUNCTION public.list_operational_org_targets()
RETURNS TABLE(organization_id UUID, organization_name TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
    OR NOT private.has_mica_platform_role() THEN
    RAISE EXCEPTION 'Active platform role required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT o.id, o.name::TEXT FROM public.eco_organizations o
    WHERE private.platform_org_in_scope(o.id) ORDER BY o.name, o.id;
END;
$$;
CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context(p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_profile UUID := private.current_profile_id();
  v_previous UUID;
BEGIN
  IF auth.uid() IS NULL OR v_profile IS NULL
    OR NOT private.has_mica_platform_role() THEN
    RAISE EXCEPTION 'Active platform role required' USING ERRCODE = '42501';
  END IF;
  -- Serialize context changes for this profile, including the initial context insert.
  PERFORM 1 FROM public.eco_user_profiles WHERE id = v_profile FOR UPDATE;
  IF p_org_id IS NOT NULL AND NOT private.platform_org_in_scope(p_org_id) THEN
    RAISE EXCEPTION 'Organization missing, inactive or outside platform scope' USING ERRCODE = '22023';
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
    IF NOT private.platform_org_in_scope(v_org)
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
    'profile_name', v_preset, 'profile_scope', v_scope,
    'can_switch_platform_context', private.has_mica_platform_role());
END;
$$;
CREATE OR REPLACE FUNCTION public.get_my_effective_capabilities(p_org_id UUID DEFAULT NULL)
RETURNS TABLE(code TEXT, scope TEXT, organization_id UUID)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_profile UUID := private.current_profile_id();
BEGIN
 IF auth.uid() IS NULL OR v_profile IS NULL THEN
 RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE = '42501'; END IF;
 -- Only caller permissions. Helpers remain the authority for each scope.
 RETURN QUERY
 SELECT c.code, c.scope, NULL::UUID FROM public.eco_capabilities c
 WHERE c.is_active AND c.scope = 'PLATFORM' AND private.mica_capability_allowed(c.code,c.scope) AND private.can_platform(c.code)
 UNION ALL
 SELECT c.code, c.scope, p_org_id FROM public.eco_capabilities c
 WHERE c.is_active AND c.scope = 'ORGANIZATION' AND p_org_id IS NOT NULL
 AND EXISTS (SELECT 1 FROM public.eco_organizations o WHERE o.id = p_org_id AND o.is_active IS TRUE)
 AND private.can_operate_mica_org(p_org_id, c.code);
END;
$$;
CREATE OR REPLACE FUNCTION public.get_operational_snapshot(p_org_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_catalog BOOLEAN;
  v_rates BOOLEAN;
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL OR p_org_id IS NULL
    OR p_org_id IS DISTINCT FROM private.active_org_id()
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id AND is_active IS TRUE) THEN
    RAISE EXCEPTION 'Invalid operational context' USING ERRCODE = '42501';
  END IF;
  v_catalog := private.can_operate_mica_org(p_org_id, 'ORG_VIEW');
  -- DEP-RLS-014: IIBB read authority is CATALOG_ORG_VIEW, not ORG_VIEW.
  v_rates := private.can_operate_mica_org(p_org_id, 'CATALOG_ORG_VIEW');
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

CREATE OR REPLACE FUNCTION private.catalog_activation_org(p_capability TEXT)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_org UUID := private.active_org_id();
BEGIN
  IF NOT private.can_operate_mica_org(v_org,p_capability) THEN
    RAISE EXCEPTION 'Confirmed tenant action capability required' USING ERRCODE='42501'; END IF;
  RETURN v_org;
END;
$$;
CREATE OR REPLACE FUNCTION public.get_capability_delegation_contract()
RETURNS TABLE(code TEXT, scope TEXT, delegation_class TEXT, is_delegable BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL THEN
    RAISE EXCEPTION 'Active profile required' USING ERRCODE='42501'; END IF;
  RETURN QUERY SELECT c.code,c.scope,c.delegation_class,c.delegation_class<>'OWNER_RESERVED'
    FROM public.eco_capabilities c WHERE c.is_active IS TRUE AND private.mica_capability_allowed(c.code,c.scope)
      AND (c.delegation_class<>'OWNER_RESERVED' OR private.is_platform_owner()) ORDER BY c.code;
END; $$;

-- Strip inherited default ACL on NEW objects. Existing function owner/ACL stay exact.
DO $acl$
DECLARE v RECORD; a RECORD; grantee TEXT;
BEGIN
  FOR v IN SELECT oid::regprocedure AS signature,proowner,proacl FROM pg_proc WHERE oid IN (
    'private.mica_capability_allowed(text,text)'::regprocedure,'private.has_mica_platform_role()'::regprocedure,
    'private.platform_org_in_scope(uuid)'::regprocedure,'private.can_operate_mica_org(uuid,text)'::regprocedure,
    'private.guard_037_platform_override()'::regprocedure,'public.can_operate_mica_org(uuid,text)'::regprocedure) LOOP
    FOR a IN SELECT DISTINCT x.grantee FROM aclexplode(COALESCE(v.proacl,acldefault('f',v.proowner))) x WHERE x.grantee<>v.proowner LOOP
      grantee := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',v.signature,grantee);
    END LOOP;
  END LOOP;
  FOR v IN SELECT oid::regclass AS relation,relowner,relacl FROM pg_class WHERE oid IN (
    'private.eco_platform_org_scopes'::regclass,'private.eco_platform_org_overrides'::regclass,'private.migration_037_functions'::regclass) LOOP
    FOR a IN SELECT DISTINCT x.grantee FROM aclexplode(COALESCE(v.relacl,acldefault('r',v.relowner))) x WHERE x.grantee<>v.relowner LOOP
      grantee := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON TABLE %s FROM %s',v.relation,grantee);
    END LOOP;
  END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.can_operate_mica_org(UUID,TEXT) TO authenticated;
UPDATE private.migration_037_functions b SET installed_definition=pg_get_functiondef(to_regprocedure(b.signature));
COMMIT;
