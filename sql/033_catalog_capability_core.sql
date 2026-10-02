-- Independent capability core. Does not redefine can_platform/can_org.
-- Catalog authority is capability-based; organization operational RLS is unchanged.
BEGIN;
CREATE TABLE private.migration_033_backup (
  seq BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind TEXT NOT NULL,
  object_name TEXT NOT NULL,
  definition TEXT,
  owner_name TEXT,
  acl JSONB
);
REVOKE ALL ON TABLE private.migration_033_backup FROM PUBLIC, anon, authenticated;
DO $backup$
DECLARE
  v_signature TEXT;
  v_oid OID;
  v_policy RECORD;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.list_catalog_assignment_targets()',
    'public.list_catalog_assignment_state(TEXT)',
    'private.catalog_assignment_target(UUID)',
    'private.require_global_catalog_manager()',
    'private.catalog_activation_org(TEXT)',
    'public.get_my_effective_capabilities(UUID)',
    'public.activate_economic_activity(UUID)',
    'public.deactivate_economic_activity(UUID)',
    'public.activate_tax_category(UUID)',
    'public.deactivate_tax_category(UUID)'
  ] LOOP
    v_oid := to_regprocedure(v_signature);
    IF v_oid IS NULL THEN
      INSERT INTO private.migration_033_backup(kind, object_name)
      VALUES ('function', v_signature);
    ELSE
      INSERT INTO private.migration_033_backup(kind, object_name, definition, owner_name, acl)
      SELECT 'function', v_signature, pg_get_functiondef(p.oid), pg_get_userbyid(p.proowner),
        (SELECT jsonb_agg(jsonb_build_object('role', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
          'privilege', a.privilege_type, 'grantable', a.is_grantable))
         FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a)
      FROM pg_proc p WHERE p.oid = v_oid;
    END IF;
  END LOOP;
  FOR v_policy IN SELECT * FROM (VALUES
    ('public.eco_org_economic_activities', 'Org activities viewable by org'),
    ('public.eco_org_tax_categories', 'Org categories viewable by org')
  ) AS targets(table_name, policy_name) LOOP
    INSERT INTO private.migration_033_backup(kind, object_name, definition)
    SELECT 'policy', format('%I ON %s', v_policy.policy_name, v_policy.table_name),
      (SELECT format('CREATE POLICY %I ON %s AS %s FOR SELECT TO %s USING (%s)',
        p.polname, v_policy.table_name, CASE WHEN p.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
        (SELECT string_agg(CASE WHEN r = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(r)) END, ', ')
         FROM unnest(p.polroles) r), pg_get_expr(p.polqual, p.polrelid))
       FROM pg_policy p WHERE p.polrelid = v_policy.table_name::regclass AND p.polname = v_policy.policy_name);
  END LOOP;
END;
$backup$;

-- Record only capabilities actually inserted by this migration, never preexisting IDs.
CREATE TABLE private.migration_033_created_capabilities (
  capability_id UUID PRIMARY KEY,
  code TEXT NOT NULL UNIQUE
);
REVOKE ALL ON TABLE private.migration_033_created_capabilities FROM PUBLIC, anon, authenticated;
WITH inserted AS (
  INSERT INTO public.eco_capabilities(code, scope, description, is_active) VALUES
    ('CATALOG_ACTIVITY_MANAGE', 'ORGANIZATION', 'Activate or deactivate assigned economic activities', TRUE),
    ('CATALOG_CATEGORY_MANAGE', 'ORGANIZATION', 'Activate or deactivate assigned tax categories', TRUE)
  ON CONFLICT (code) DO NOTHING
  RETURNING id, code
)
INSERT INTO private.migration_033_created_capabilities(capability_id, code)
SELECT id, code FROM inserted;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.eco_capabilities WHERE code IN
 ('CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE') AND scope = 'ORGANIZATION' AND is_active) <> 2 THEN
 RAISE EXCEPTION 'Existing activation capabilities must be active ORGANIZATION capabilities'; END IF;
END;
$$;


CREATE TABLE private.migration_033_default_grants (
  role_template_id UUID NOT NULL,
  capability_id UUID NOT NULL,
  existed_before BOOLEAN NOT NULL,
  PRIMARY KEY (role_template_id, capability_id)
);
REVOKE ALL ON TABLE private.migration_033_default_grants FROM PUBLIC, anon, authenticated;
INSERT INTO private.migration_033_default_grants(role_template_id, capability_id, existed_before)
SELECT t.id, c.id, EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
  WHERE g.role_template_id = t.id AND g.capability_id = c.id)
FROM public.eco_role_templates t CROSS JOIN public.eco_capabilities c
WHERE t.code IN ('CONSULTANT', 'TENANT_ADMIN') AND t.scope = 'ORGANIZATION' AND t.is_active IS TRUE
  AND c.code IN ('CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE');
INSERT INTO public.eco_role_template_capabilities(role_template_id, capability_id)
SELECT role_template_id, capability_id FROM private.migration_033_default_grants
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION private.catalog_assignment_target(p_target_org_id UUID)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
    OR NOT COALESCE(private.can_platform('CATALOG_ASSIGN_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'Catalog assignment capability required' USING ERRCODE = '42501';
  END IF;
  IF p_target_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.eco_organizations o WHERE o.id = p_target_org_id AND o.is_active IS TRUE
  ) THEN
    RAISE EXCEPTION 'Active target organization required' USING ERRCODE = '42501';
  END IF;
  RETURN p_target_org_id;
END;
$$;
REVOKE ALL ON FUNCTION private.catalog_assignment_target(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.list_catalog_assignment_targets()
RETURNS TABLE(organization_id UUID, organization_name TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
    OR NOT COALESCE(private.can_platform('CATALOG_ASSIGN_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'Catalog assignment capability required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT o.id, o.name::TEXT FROM public.eco_organizations o
    WHERE o.is_active IS TRUE ORDER BY o.name, o.id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.list_catalog_assignment_targets() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_catalog_assignment_targets() TO authenticated;

-- Minimal catalog-only status, for the targets the same capability authorizes.
-- No organization details or operational data; no cross-tenant table SELECT grant.
CREATE OR REPLACE FUNCTION public.list_catalog_assignment_state(p_catalog_type TEXT)
RETURNS TABLE(organization_id UUID, item_id UUID, is_assigned BOOLEAN, is_active BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
    OR NOT COALESCE(private.can_platform('CATALOG_ASSIGN_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'Catalog assignment capability required' USING ERRCODE = '42501';
  END IF;
  IF p_catalog_type = 'activity' THEN
    RETURN QUERY SELECT a.organization_id, a.activity_id, a.is_assigned, a.is_active
      FROM public.eco_org_economic_activities a JOIN public.eco_organizations o ON o.id = a.organization_id
      WHERE o.is_active IS TRUE ORDER BY a.organization_id, a.activity_id;
  ELSIF p_catalog_type = 'category' THEN
    RETURN QUERY SELECT a.organization_id, a.category_id, a.is_assigned, a.is_active
      FROM public.eco_org_tax_categories a JOIN public.eco_organizations o ON o.id = a.organization_id
      WHERE o.is_active IS TRUE ORDER BY a.organization_id, a.category_id;
  ELSE
    RAISE EXCEPTION 'Invalid catalog type' USING ERRCODE = '22023';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.list_catalog_assignment_state(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_catalog_assignment_state(TEXT) TO authenticated;

DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities
FOR SELECT TO authenticated USING (
  organization_id = private.org_id() AND is_assigned IS TRUE
  AND private.can_org(organization_id, 'ORG_VIEW')
);
DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories
FOR SELECT TO authenticated USING (
  organization_id = private.org_id() AND is_assigned IS TRUE
  AND private.can_org(organization_id, 'ORG_VIEW')
);

CREATE OR REPLACE FUNCTION private.require_global_catalog_manager()
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
 IF auth.uid() IS NULL OR private.current_profile_id() IS NULL
 OR NOT COALESCE(private.can_platform('GLOBAL_CATALOG_MANAGE'), FALSE) THEN
 RAISE EXCEPTION 'Global catalog management capability required' USING ERRCODE = '42501'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.require_global_catalog_manager() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.catalog_activation_org(p_capability TEXT)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_org UUID := private.org_id();
BEGIN
 IF auth.uid() IS NULL OR private.current_profile_id() IS NULL OR v_org IS NULL
 OR NOT EXISTS (SELECT 1 FROM public.eco_organizations o WHERE o.id = v_org AND o.is_active IS TRUE)
 OR NOT EXISTS (SELECT 1 FROM public.eco_organization_members m
   WHERE m.organization_id = v_org AND m.user_profile_id = private.current_profile_id() AND m.is_active IS TRUE)
 OR NOT COALESCE(private.can_org(v_org, p_capability), FALSE) THEN
 RAISE EXCEPTION 'Organization catalog activation capability required' USING ERRCODE = '42501'; END IF;
 RETURN v_org;
END;
$$;
REVOKE ALL ON FUNCTION private.catalog_activation_org(TEXT) FROM PUBLIC, anon, authenticated;

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
 WHERE c.is_active AND c.scope = 'PLATFORM' AND private.can_platform(c.code)
 UNION ALL
 SELECT c.code, c.scope, p_org_id FROM public.eco_capabilities c
 WHERE c.is_active AND c.scope = 'ORGANIZATION' AND p_org_id IS NOT NULL
 AND EXISTS (SELECT 1 FROM public.eco_organizations o WHERE o.id = p_org_id AND o.is_active IS TRUE)
 AND private.can_org(p_org_id, c.code);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_effective_capabilities(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_effective_capabilities(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.activate_economic_activity(p_activity_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org('CATALOG_ACTIVITY_MANAGE');
BEGIN
  UPDATE public.eco_org_economic_activities
  SET is_active = TRUE, updated_at = now()
  WHERE organization_id = v_org_id AND activity_id = p_activity_id
    AND is_assigned = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Element is not assigned to the active organization' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_ACTIVATED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.activate_economic_activity(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_economic_activity(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_economic_activity(p_activity_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org('CATALOG_ACTIVITY_MANAGE');
BEGIN
  UPDATE public.eco_org_economic_activities
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND activity_id = p_activity_id
    AND is_assigned = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Element is not assigned to the active organization' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_DEACTIVATED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.deactivate_economic_activity(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deactivate_economic_activity(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.activate_tax_category(p_category_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org('CATALOG_CATEGORY_MANAGE');
BEGIN
  UPDATE public.eco_org_tax_categories
  SET is_active = TRUE, updated_at = now()
  WHERE organization_id = v_org_id AND category_id = p_category_id
    AND is_assigned = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Element is not assigned to the active organization' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_ACTIVATED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.activate_tax_category(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_tax_category(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.deactivate_tax_category(p_category_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org('CATALOG_CATEGORY_MANAGE');
BEGIN
  UPDATE public.eco_org_tax_categories
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND category_id = p_category_id
    AND is_assigned = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Element is not assigned to the active organization' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_DEACTIVATED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.deactivate_tax_category(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deactivate_tax_category(UUID) TO authenticated;
COMMIT;
