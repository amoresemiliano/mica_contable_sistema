BEGIN;

-- ============================================================
-- 1. CREACIÓN IDEMPOTENTE DE ORGANIZACIONES DEV
-- ============================================================

INSERT INTO public.eco_organizations (name)
SELECT 'DEMO NORTE'
WHERE NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE name = 'DEMO NORTE');

INSERT INTO public.eco_organizations (name)
SELECT 'DEMO SUR'
WHERE NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE name = 'DEMO SUR');

INSERT INTO public.eco_organizations (name)
SELECT 'DEMO OESTE'
WHERE NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE name = 'DEMO OESTE');


-- ============================================================
-- 2. POLÍTICAS RLS ACTUALIZADAS PARA SUPERADMIN Y MULTITENANCY
-- ============================================================

-- A. eco_org_tax_categories: SUPERADMIN puede consultar todas las asignaciones o filtrar por org activa
ALTER TABLE public.eco_org_tax_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories 
FOR SELECT TO authenticated 
USING (
  organization_id = private.org_id() OR private.func_role() = 'SUPERADMIN'
);

-- B. eco_org_economic_activities: SUPERADMIN puede consultar todas las asignaciones de actividades
ALTER TABLE public.eco_org_economic_activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities 
FOR SELECT TO authenticated 
USING (
  organization_id = private.org_id() OR private.func_role() = 'SUPERADMIN'
);

-- C. eco_org_activity_iibb_rates: SUPERADMIN puede consultar tasas IIBB por organización
ALTER TABLE public.eco_org_activity_iibb_rates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates;
CREATE POLICY "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates 
FOR SELECT TO authenticated 
USING (
  organization_id = private.org_id() OR private.func_role() = 'SUPERADMIN'
);


-- ============================================================
-- 3. FUNCTION RPC: CAMBIO DE CONTEXTO ORGANIZACIONAL SUPERADMIN
-- ============================================================

CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context(
  p_org_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_caller_role TEXT;
  v_caller_id UUID;
BEGIN
  v_caller_role := private.func_role();
  IF v_caller_role != 'SUPERADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: Only SUPERADMIN can switch organization context';
  END IF;

  IF p_org_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id = p_org_id) THEN
      RAISE EXCEPTION 'Invalid organization ID';
    END IF;
  END IF;

  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found or inactive';
  END IF;

  UPDATE public.eco_user_profiles
  SET organization_id = p_org_id
  WHERE id = v_caller_id;

  -- Note: eco_audit_events.organization_id is NOT NULL. When switching to global mode (p_org_id IS NULL),
  -- no tenant-scoped audit record is written to avoid attributing global system events to a fake tenant organization.
  IF p_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (p_org_id, 'SUPERADMIN_ORG_CONTEXT_SWITCHED');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.switch_superadmin_org_context(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.switch_superadmin_org_context(UUID) TO authenticated;


-- ============================================================
-- 4. RPCS DE ASIGNACIÓN/DESASIGNACIÓN CON CONTEXTO TARGET ORGANIZACIÓN
-- ============================================================

DROP FUNCTION IF EXISTS public.assign_tax_category_to_org(UUID, TEXT);
DROP FUNCTION IF EXISTS public.unassign_tax_category_from_org(UUID);
DROP FUNCTION IF EXISTS public.assign_economic_activity_to_org(UUID);
DROP FUNCTION IF EXISTS public.unassign_economic_activity_from_org(UUID);

CREATE OR REPLACE FUNCTION public.assign_tax_category_to_org(
  p_category_id UUID,
  p_custom_name TEXT DEFAULT NULL,
  p_target_org_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
BEGIN
  v_caller_role := private.func_role();

  IF p_target_org_id IS NOT NULL THEN
    IF v_caller_role != 'SUPERADMIN' THEN
      RAISE EXCEPTION 'Unauthorized: Target org assignment requires SUPERADMIN role';
    END IF;
    v_org_id := p_target_org_id;
  ELSE
    v_org_id := private.org_id();
  END IF;

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization context'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;

  INSERT INTO public.eco_org_tax_categories (organization_id, category_id, custom_name, is_active)
  VALUES (v_org_id, p_category_id, p_custom_name, TRUE)
  ON CONFLICT (organization_id, category_id) DO UPDATE 
  SET is_active = TRUE, custom_name = EXCLUDED.custom_name, updated_at = now();

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_ASSIGNED');
END;
$$;

REVOKE ALL ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.unassign_tax_category_from_org(
  p_category_id UUID,
  p_target_org_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
BEGIN
  v_caller_role := private.func_role();

  IF p_target_org_id IS NOT NULL THEN
    IF v_caller_role != 'SUPERADMIN' THEN
      RAISE EXCEPTION 'Unauthorized: Target org unassignment requires SUPERADMIN role';
    END IF;
    v_org_id := p_target_org_id;
  ELSE
    v_org_id := private.org_id();
  END IF;

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization context'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;

  UPDATE public.eco_org_tax_categories
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND category_id = p_category_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_UNASSIGNED');
END;
$$;

REVOKE ALL ON FUNCTION public.unassign_tax_category_from_org(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unassign_tax_category_from_org(UUID, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.assign_economic_activity_to_org(
  p_activity_id UUID,
  p_target_org_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
BEGIN
  v_caller_role := private.func_role();

  IF p_target_org_id IS NOT NULL THEN
    IF v_caller_role != 'SUPERADMIN' THEN
      RAISE EXCEPTION 'Unauthorized: Target org assignment requires SUPERADMIN role';
    END IF;
    v_org_id := p_target_org_id;
  ELSE
    v_org_id := private.org_id();
  END IF;

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization context'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;

  INSERT INTO public.eco_org_economic_activities (organization_id, activity_id, is_active)
  VALUES (v_org_id, p_activity_id, TRUE)
  ON CONFLICT (organization_id, activity_id) DO UPDATE 
  SET is_active = TRUE, updated_at = now();

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_ASSIGNED');
END;
$$;

REVOKE ALL ON FUNCTION public.assign_economic_activity_to_org(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_economic_activity_to_org(UUID, UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.unassign_economic_activity_from_org(
  p_activity_id UUID,
  p_target_org_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
BEGIN
  v_caller_role := private.func_role();

  IF p_target_org_id IS NOT NULL THEN
    IF v_caller_role != 'SUPERADMIN' THEN
      RAISE EXCEPTION 'Unauthorized: Target org unassignment requires SUPERADMIN role';
    END IF;
    v_org_id := p_target_org_id;
  ELSE
    v_org_id := private.org_id();
  END IF;

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization context'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;

  UPDATE public.eco_org_economic_activities
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND activity_id = p_activity_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_UNASSIGNED');
END;
$$;

REVOKE ALL ON FUNCTION public.unassign_economic_activity_from_org(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unassign_economic_activity_from_org(UUID, UUID) TO authenticated;

COMMIT;
