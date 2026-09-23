-- MIGRATION 030: Separate MICA assignment from tenant activation.
-- Adding the column with DEFAULT TRUE backfills every existing row.
-- No existing is_active value is changed.
BEGIN;

-- Capture the actual pre-030 metadata, not assumptions about applied migrations.
-- This private backup is deliberately retained after rollback. Run once only.
CREATE TABLE private.migration_030_backup (
  seq BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind TEXT NOT NULL,
  object_name TEXT NOT NULL,
  definition TEXT,
  owner_name TEXT,
  acl JSONB
);
REVOKE ALL ON TABLE private.migration_030_backup FROM PUBLIC, anon, authenticated;
DO $backup$
DECLARE
  v_signature TEXT;
  v_oid OID;
  v_policy RECORD;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.assign_economic_activity_to_org(UUID, UUID)',
    'public.unassign_economic_activity_from_org(UUID, UUID)',
    'public.activate_economic_activity(UUID)',
    'public.deactivate_economic_activity(UUID)',
    'public.assign_tax_category_to_org(UUID, TEXT, UUID)',
    'public.unassign_tax_category_from_org(UUID, UUID)',
    'public.activate_tax_category(UUID)',
    'public.deactivate_tax_category(UUID)',
    'public.create_global_tax_category(TEXT, TEXT, TEXT)',
    'public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN)',
    'public.create_global_economic_activity(TEXT, TEXT, TEXT)',
    'public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN)',
    'public.upsert_arca_activity_catalog(JSONB)',
    'public.get_my_catalog_capabilities()',
    'public.update_record_classification(UUID, UUID, UUID)',
    'public.update_movement_classification(UUID, UUID, UUID)',
    'public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID)',
    'public.create_org_activity_iibb_rate(UUID, TEXT, NUMERIC, DATE, DATE)',
    'private.catalog_assignment_target(UUID)',
    'private.catalog_activation_org()',
    'private.require_global_catalog_manager()'
  ] LOOP
    v_oid := to_regprocedure(v_signature);
    IF v_oid IS NULL THEN
      INSERT INTO private.migration_030_backup(kind, object_name)
      VALUES ('function', v_signature);
    ELSE
      INSERT INTO private.migration_030_backup(kind, object_name, definition, owner_name, acl)
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
    INSERT INTO private.migration_030_backup(kind, object_name, definition)
    SELECT 'policy', format('%I ON %s', v_policy.policy_name, v_policy.table_name),
      (SELECT format('CREATE POLICY %I ON %s AS %s FOR SELECT TO %s USING (%s)',
        p.polname, v_policy.table_name, CASE WHEN p.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
        (SELECT string_agg(CASE WHEN r = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(r)) END, ', ')
         FROM unnest(p.polroles) r), pg_get_expr(p.polqual, p.polrelid))
       FROM pg_policy p WHERE p.polrelid = v_policy.table_name::regclass AND p.polname = v_policy.policy_name);
  END LOOP;
  FOREACH v_signature IN ARRAY ARRAY['public.eco_org_economic_activities', 'public.eco_org_tax_categories'] LOOP
    INSERT INTO private.migration_030_backup(kind, object_name, acl)
    SELECT 'table', v_signature,
      (SELECT jsonb_agg(jsonb_build_object('role', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
        'privilege', a.privilege_type, 'grantable', a.is_grantable))
       FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a)
    FROM pg_class c WHERE c.oid = v_signature::regclass;
  END LOOP;
END;
$backup$;


ALTER TABLE public.eco_org_economic_activities
  ADD COLUMN is_assigned BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.eco_org_tax_categories
  ADD COLUMN is_assigned BOOLEAN NOT NULL DEFAULT TRUE;

-- All mutations go through the checked RPCs, not direct table writes.
REVOKE INSERT, UPDATE, DELETE ON public.eco_org_economic_activities,
  public.eco_org_tax_categories FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.catalog_assignment_target(p_target_org_id UUID)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := COALESCE(p_target_org_id, private.org_id());
BEGIN
  IF auth.uid() IS NULL
     OR private.func_role() IS DISTINCT FROM 'SUPERADMIN'
     OR NOT COALESCE(private.can_platform('CATALOG_ASSIGN_ANY_ORG'), FALSE) THEN
    RAISE EXCEPTION 'Unauthorized: SUPERADMIN catalog assignment permission required' USING ERRCODE = '42501';
  END IF;
  IF v_org_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.eco_organizations WHERE id = v_org_id
  ) THEN
    RAISE EXCEPTION 'Invalid target organization' USING ERRCODE = '22023';
  END IF;
  IF NOT (COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE)
          OR COALESCE(private.can_org(v_org_id, 'ORG_VIEW'), FALSE)) THEN
    RAISE EXCEPTION 'Unauthorized target organization' USING ERRCODE = '42501';
  END IF;
  RETURN v_org_id;
END;
$$;
REVOKE ALL ON FUNCTION private.catalog_assignment_target(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.catalog_activation_org()
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.org_id();
BEGIN
  IF auth.uid() IS NULL
     OR private.func_role() IS DISTINCT FROM 'ADMIN'
     OR v_org_id IS NULL
     OR NOT COALESCE(private.can_org(v_org_id, 'ORG_VIEW'), FALSE) THEN
    RAISE EXCEPTION 'Unauthorized: ADMIN in an authorized active organization required' USING ERRCODE = '42501';
  END IF;
  RETURN v_org_id;
END;
$$;
REVOKE ALL ON FUNCTION private.catalog_activation_org() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.assign_economic_activity_to_org(p_activity_id UUID, p_target_org_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_assignment_target(p_target_org_id);
BEGIN
  INSERT INTO public.eco_org_economic_activities
    (organization_id, activity_id, is_assigned, is_active)
  VALUES (v_org_id, p_activity_id, TRUE, TRUE)
  ON CONFLICT (organization_id, activity_id) DO UPDATE
    SET is_assigned = TRUE, updated_at = now();
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_ASSIGNED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.assign_economic_activity_to_org(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_economic_activity_to_org(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.unassign_economic_activity_from_org(p_activity_id UUID, p_target_org_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_assignment_target(p_target_org_id);
BEGIN
  UPDATE public.eco_org_economic_activities
  SET is_assigned = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND activity_id = p_activity_id;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_UNASSIGNED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.unassign_economic_activity_from_org(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unassign_economic_activity_from_org(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.activate_economic_activity(p_activity_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org();
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
  v_org_id UUID := private.catalog_activation_org();
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

CREATE OR REPLACE FUNCTION public.assign_tax_category_to_org(p_category_id UUID, p_custom_name TEXT DEFAULT NULL, p_target_org_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_assignment_target(p_target_org_id);
BEGIN
  INSERT INTO public.eco_org_tax_categories
    (organization_id, category_id, custom_name, is_assigned, is_active)
  VALUES (v_org_id, p_category_id, p_custom_name, TRUE, TRUE)
  ON CONFLICT (organization_id, category_id) DO UPDATE
    SET is_assigned = TRUE, custom_name = COALESCE(EXCLUDED.custom_name, eco_org_tax_categories.custom_name), updated_at = now();
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_ASSIGNED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.unassign_tax_category_from_org(p_category_id UUID, p_target_org_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_assignment_target(p_target_org_id);
BEGIN
  UPDATE public.eco_org_tax_categories
  SET is_assigned = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND category_id = p_category_id;
  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_UNASSIGNED');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.unassign_tax_category_from_org(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unassign_tax_category_from_org(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.activate_tax_category(p_category_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_org_id UUID := private.catalog_activation_org();
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
  v_org_id UUID := private.catalog_activation_org();
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

-- Narrow existing SELECT policies: inactive assignments remain visible;
-- unassigned assignment rows are not visible to the tenant.
DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities
FOR SELECT TO authenticated USING (
  private.func_role() = 'SUPERADMIN'
  OR (organization_id = private.org_id() AND is_assigned = TRUE)
);
-- Keep the existing eco_economic_activities SELECT policy for historical name resolution.

DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories
FOR SELECT TO authenticated USING (
  private.func_role() = 'SUPERADMIN'
  OR (organization_id = private.org_id() AND is_assigned = TRUE)
);
-- Keep the existing eco_tax_categories SELECT policy for historical name resolution.

-- Global catalog maintenance is exclusively a MICA/SUPERADMIN operation.
CREATE OR REPLACE FUNCTION private.require_global_catalog_manager()
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL
     OR private.func_role() IS DISTINCT FROM 'SUPERADMIN'
     OR NOT COALESCE(private.can_platform('GLOBAL_CATALOG_MANAGE'), FALSE) THEN
    RAISE EXCEPTION 'Unauthorized: SUPERADMIN global catalog management permission required' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.require_global_catalog_manager() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_global_tax_category(
  p_name TEXT,
  p_description TEXT,
  p_category_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_new_id UUID;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();

  PERFORM private.require_global_catalog_manager();

  INSERT INTO public.eco_tax_categories (name, description, category_type, is_active)
  VALUES (p_name, p_description, p_category_type, TRUE)
  RETURNING id INTO v_new_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CATEGORY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_global_tax_category(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_global_tax_category(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_global_tax_category(
  p_category_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  PERFORM private.require_global_catalog_manager();

  UPDATE public.eco_tax_categories
  SET name = p_name, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_category_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CATEGORY_UPDATED');
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_global_economic_activity(
  p_name TEXT,
  p_afip_code TEXT,
  p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_new_id UUID;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  PERFORM private.require_global_catalog_manager();

  INSERT INTO public.eco_economic_activities (name, arca_code, description, is_active)
  VALUES (p_name, p_afip_code, p_description, TRUE)
  RETURNING id INTO v_new_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_global_economic_activity(TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_global_economic_activity(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_global_economic_activity(
  p_activity_id UUID,
  p_name TEXT,
  p_afip_code TEXT,
  p_description TEXT,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_org_id UUID;
BEGIN
  v_caller_role := private.func_role();
  v_org_id := private.org_id();
  PERFORM private.require_global_catalog_manager();

  UPDATE public.eco_economic_activities
  SET name = p_name, arca_code = p_afip_code, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_activity_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_UPDATED');
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_arca_activity_catalog(
  p_activities JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_act JSONB;
  v_count INTEGER := 0;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  PERFORM private.require_global_catalog_manager();
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: Must be authenticated'; END IF;

  FOR v_act IN SELECT * FROM jsonb_array_elements(p_activities)
  LOOP
    IF v_act->>'arca_code' IS NULL OR v_act->>'name' IS NULL THEN
      RAISE EXCEPTION 'Invalid activity format: arca_code and name are required';
    END IF;

    INSERT INTO public.eco_economic_activities (name, arca_code, description, is_active)
    VALUES (
      v_act->>'name',
      v_act->>'arca_code',
      v_act->>'description',
      COALESCE((v_act->>'is_active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (arca_code) DO UPDATE
    SET name = EXCLUDED.name,
        description = EXCLUDED.description,
        is_active = EXCLUDED.is_active,
        updated_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.upsert_arca_activity_catalog(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_arca_activity_catalog(JSONB) TO authenticated;

-- Operational RPCs must reject withdrawn assignments even if historically active.
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
  v_caller_role TEXT;
  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER, ADMIN, or SUPERADMIN role'; END IF;

  -- Validar que la categoría pertenezca a la org y esté activa
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE;

    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  -- Validar que la actividad pertenezca a la org y esté activa
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

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_record_classification(UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_record_classification(UUID, UUID, UUID) TO authenticated;

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
  v_caller_role TEXT;
  v_valid_category BOOLEAN := FALSE;
  v_valid_activity BOOLEAN := FALSE;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER, ADMIN, or SUPERADMIN role'; END IF;

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

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CLASSIFICATION_UPDATED');
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.bulk_update_record_classification(
  p_cuit TEXT,
  p_date_from DATE,
  p_date_to DATE,
  p_category_id UUID,
  p_activity_id UUID
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_caller_id UUID;
  v_rows_affected INT := 0;
  v_valid BOOLEAN;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER, ADMIN, or SUPERADMIN role'; END IF;

  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF p_category_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_tax_categories WHERE organization_id = v_org_id AND category_id = p_category_id AND is_assigned = TRUE AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_economic_activities WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  WITH updated AS (
    UPDATE public.eco_normalized_records
    SET category_id = p_category_id,
        activity_id = p_activity_id,
        updated_at = now(),
        updated_by = v_caller_id
    WHERE organization_id = v_org_id
      AND deleted_at IS NULL
      AND (normalized_payload->>'cuitEmisor' = p_cuit OR normalized_payload->>'cuitReceptor' = p_cuit)
      AND fecha >= p_date_from
      AND fecha <= p_date_to
    RETURNING id
  )
  SELECT COUNT(*) INTO v_rows_affected FROM updated;

  IF v_rows_affected > 0 THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type, details)
    VALUES (v_org_id, 'BULK_UPDATE_RECORDS_CLASSIFICATION', jsonb_build_object('cuit', p_cuit, 'date_from', p_date_from, 'date_to', p_date_to, 'rows_affected', v_rows_affected));
  END IF;

  RETURN v_rows_affected;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_org_activity_iibb_rate(
  p_activity_id UUID,
  p_jurisdiction TEXT,
  p_rate NUMERIC(5,2),
  p_valid_from DATE DEFAULT NULL,
  p_valid_to DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_rate_id UUID;
  v_valid BOOLEAN;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;

  IF p_rate < 0 THEN RAISE EXCEPTION 'Rate must be >= 0'; END IF;

  p_jurisdiction := TRIM(p_jurisdiction);
  IF p_jurisdiction = '' THEN RAISE EXCEPTION 'Jurisdiction cannot be empty'; END IF;

  IF p_valid_from IS NOT NULL AND p_valid_to IS NOT NULL AND p_valid_from > p_valid_to THEN
    RAISE EXCEPTION 'valid_from must be <= valid_to';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_assigned = TRUE AND is_active = TRUE
  ) INTO v_valid;
  IF NOT v_valid THEN RAISE EXCEPTION 'Activity ID is not assigned to this organization or is inactive'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.eco_org_activity_iibb_rates
    WHERE organization_id = v_org_id
      AND activity_id = p_activity_id
      AND jurisdiction = p_jurisdiction
      AND is_active = TRUE
      AND COALESCE(p_valid_from, '-infinity'::date) <= COALESCE(valid_to, 'infinity'::date)
      AND COALESCE(p_valid_to, 'infinity'::date) >= COALESCE(valid_from, '-infinity'::date)
  ) INTO v_valid;
  IF v_valid THEN RAISE EXCEPTION 'Conflicting active period for the same organization, activity, and jurisdiction'; END IF;

  INSERT INTO public.eco_org_activity_iibb_rates (
    organization_id, activity_id, jurisdiction, rate, valid_from, valid_to
  ) VALUES (
    v_org_id, p_activity_id, p_jurisdiction, p_rate, p_valid_from, p_valid_to
  ) RETURNING id INTO v_rate_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type, details)
  VALUES (v_org_id, 'IIBB_RATE_CREATED', jsonb_build_object('rate_id', v_rate_id, 'activity_id', p_activity_id, 'jurisdiction', p_jurisdiction));

  RETURN v_rate_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.create_org_activity_iibb_rate(UUID, TEXT, NUMERIC, DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_org_activity_iibb_rate(UUID, TEXT, NUMERIC, DATE, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_catalog_capabilities()
RETURNS TABLE (global_catalog_manage BOOLEAN, catalog_assign_any_org BOOLEAN, access_any_org BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT
    COALESCE(private.can_platform('GLOBAL_CATALOG_MANAGE'), FALSE),
    COALESCE(private.can_platform('CATALOG_ASSIGN_ANY_ORG'), FALSE),
    COALESCE(private.can_platform('ACCESS_ANY_ORG'), FALSE);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_catalog_capabilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_catalog_capabilities() TO authenticated;

COMMIT;
