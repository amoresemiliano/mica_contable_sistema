BEGIN;

-- 1. Restablecer políticas RLS a la versión 014
DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories FOR SELECT TO authenticated USING (organization_id = private.org_id());

DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities FOR SELECT TO authenticated USING (organization_id = private.org_id());

DROP POLICY IF EXISTS "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates;
CREATE POLICY "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates FOR SELECT TO authenticated USING (organization_id = private.org_id());

-- 2. Eliminar función de cambio de contexto SUPERADMIN
DROP FUNCTION IF EXISTS public.switch_superadmin_org_context(UUID);

-- 3. Eliminar firmas M017 de asignación/desasignación y restaurar contratos M014
DROP FUNCTION IF EXISTS public.assign_tax_category_to_org(UUID, TEXT, UUID);
CREATE OR REPLACE FUNCTION public.assign_tax_category_to_org(
  p_category_id UUID,
  p_custom_name TEXT DEFAULT NULL
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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  INSERT INTO public.eco_org_tax_categories (organization_id, category_id, custom_name, is_active)
  VALUES (v_org_id, p_category_id, p_custom_name, TRUE)
  ON CONFLICT (organization_id, category_id) DO UPDATE 
  SET is_active = TRUE, custom_name = EXCLUDED.custom_name, updated_at = now();

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_ASSIGNED');
END;
$$;
REVOKE ALL ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_tax_category_to_org(UUID, TEXT) TO authenticated;


DROP FUNCTION IF EXISTS public.unassign_tax_category_from_org(UUID, UUID);
CREATE OR REPLACE FUNCTION public.unassign_tax_category_from_org(
  p_category_id UUID
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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_org_tax_categories
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND category_id = p_category_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'CATEGORY_UNASSIGNED');
END;
$$;
REVOKE ALL ON FUNCTION public.unassign_tax_category_from_org(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unassign_tax_category_from_org(UUID) TO authenticated;


DROP FUNCTION IF EXISTS public.assign_economic_activity_to_org(UUID, UUID);
CREATE OR REPLACE FUNCTION public.assign_economic_activity_to_org(
  p_activity_id UUID
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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  INSERT INTO public.eco_org_economic_activities (organization_id, activity_id, is_active)
  VALUES (v_org_id, p_activity_id, TRUE)
  ON CONFLICT (organization_id, activity_id) DO UPDATE 
  SET is_active = TRUE, updated_at = now();

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_ASSIGNED');
END;
$$;
REVOKE ALL ON FUNCTION public.assign_economic_activity_to_org(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_economic_activity_to_org(UUID) TO authenticated;


DROP FUNCTION IF EXISTS public.unassign_economic_activity_from_org(UUID, UUID);
CREATE OR REPLACE FUNCTION public.unassign_economic_activity_from_org(
  p_activity_id UUID
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
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_org_economic_activities
  SET is_active = FALSE, updated_at = now()
  WHERE organization_id = v_org_id AND activity_id = p_activity_id;

  INSERT INTO public.eco_audit_events (organization_id, event_type)
  VALUES (v_org_id, 'ACTIVITY_UNASSIGNED');
END;
$$;
REVOKE ALL ON FUNCTION public.unassign_economic_activity_from_org(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unassign_economic_activity_from_org(UUID) TO authenticated;

COMMIT;
