BEGIN;

-- ============================================================
-- 1. MODELO DE CATEGORIZACIÓN (CATÁLOGO + ASIGNACIÓN)
-- ============================================================

-- A. Tax Categories (Global Catalog)
CREATE TABLE IF NOT EXISTS public.eco_tax_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  category_type TEXT NOT NULL CHECK (category_type IN ('INCOME', 'EXPENSE')),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- B. Tax Categories (Organization Assignments)
CREATE TABLE IF NOT EXISTS public.eco_org_tax_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
  category_id UUID NOT NULL REFERENCES public.eco_tax_categories(id),
  custom_name TEXT, 
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(organization_id, category_id)
);

-- C. Economic Activities (Global Catalog)
CREATE TABLE IF NOT EXISTS public.eco_economic_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  arca_code TEXT,
  description TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- D. Economic Activities (Organization Assignments)
CREATE TABLE IF NOT EXISTS public.eco_org_economic_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
  activity_id UUID NOT NULL REFERENCES public.eco_economic_activities(id),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(organization_id, activity_id)
);

-- E. Activity IIBB Rates Configuration (Organization specific)
CREATE TABLE IF NOT EXISTS public.eco_org_activity_iibb_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
  activity_id UUID NOT NULL REFERENCES public.eco_economic_activities(id),
  jurisdiction TEXT NOT NULL,
  rate NUMERIC(5,2) NOT NULL,
  valid_from DATE,
  valid_to DATE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE public.eco_tax_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Global categories viewable by all authenticated" ON public.eco_tax_categories;
CREATE POLICY "Global categories viewable by all authenticated" ON public.eco_tax_categories FOR SELECT TO authenticated USING (TRUE);

ALTER TABLE public.eco_economic_activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Global activities viewable by all authenticated" ON public.eco_economic_activities;
CREATE POLICY "Global activities viewable by all authenticated" ON public.eco_economic_activities FOR SELECT TO authenticated USING (TRUE);

ALTER TABLE public.eco_org_tax_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org categories viewable by org" ON public.eco_org_tax_categories;
CREATE POLICY "Org categories viewable by org" ON public.eco_org_tax_categories FOR SELECT TO authenticated USING (organization_id = private.org_id());

ALTER TABLE public.eco_org_economic_activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org activities viewable by org" ON public.eco_org_economic_activities;
CREATE POLICY "Org activities viewable by org" ON public.eco_org_economic_activities FOR SELECT TO authenticated USING (organization_id = private.org_id());

ALTER TABLE public.eco_org_activity_iibb_rates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates;
CREATE POLICY "Org IIBB rates viewable by org" ON public.eco_org_activity_iibb_rates FOR SELECT TO authenticated USING (organization_id = private.org_id());


-- ============================================================
-- 2. MODIFICACIONES A TABLAS EXISTENTES Y SOFT DELETE
-- ============================================================

-- Agregar campos nuevos a eco_normalized_records manteniendo retrocompatibilidad
ALTER TABLE public.eco_normalized_records
  ADD COLUMN IF NOT EXISTS legacy_categoria_text TEXT,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.eco_tax_categories(id),
  ADD COLUMN IF NOT EXISTS activity_id UUID REFERENCES public.eco_economic_activities(id);

-- Copiar el campo categoria original al legacy_categoria_text si está vacío
UPDATE public.eco_normalized_records 
SET legacy_categoria_text = categoria 
WHERE legacy_categoria_text IS NULL AND categoria IS NOT NULL;

-- No eliminamos 'categoria' todavía para no romper el frontend
-- ALTER TABLE public.eco_normalized_records DROP COLUMN categoria;

ALTER TABLE public.eco_financial_movements
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.eco_tax_categories(id),
  ADD COLUMN IF NOT EXISTS activity_id UUID REFERENCES public.eco_economic_activities(id);


-- ============================================================
-- 3. AJUSTAR LECTURA DE REGISTROS (EXCLUIR BORRADOS)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_active_normalized_records()
RETURNS SETOF public.eco_normalized_records
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_normalized_records
  WHERE organization_id = private.org_id()
    AND deleted_at IS NULL
  ORDER BY fecha DESC, created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_active_normalized_records() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_normalized_records() TO authenticated;


CREATE OR REPLACE FUNCTION public.get_active_financial_movements()
RETURNS SETOF public.eco_financial_movements
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_financial_movements
  WHERE organization_id = private.org_id()
    AND deleted_at IS NULL
  ORDER BY fecha DESC, created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_active_financial_movements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_financial_movements() TO authenticated;


-- ============================================================
-- 4. TRASH READ CONTRACT
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_deleted_normalized_records()
RETURNS SETOF public.eco_normalized_records
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_normalized_records
  WHERE organization_id = private.org_id()
    AND deleted_at IS NOT NULL
  ORDER BY deleted_at DESC, fecha DESC;
$$;
REVOKE ALL ON FUNCTION public.get_deleted_normalized_records() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_deleted_normalized_records() TO authenticated;


CREATE OR REPLACE FUNCTION public.get_deleted_financial_movements()
RETURNS SETOF public.eco_financial_movements
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT *
  FROM public.eco_financial_movements
  WHERE organization_id = private.org_id()
    AND deleted_at IS NOT NULL
  ORDER BY deleted_at DESC, fecha DESC;
$$;
REVOKE ALL ON FUNCTION public.get_deleted_financial_movements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_deleted_financial_movements() TO authenticated;


-- ============================================================
-- 5. SOFT DELETE / RESTORE ACTIONS (RPC)
-- ============================================================

CREATE OR REPLACE FUNCTION public.soft_delete_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;
  
  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'SOFT_DELETE_RECORD');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.soft_delete_normalized_record(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_normalized_record(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.restore_normalized_record(p_record_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'RESTORE_RECORD');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.restore_normalized_record(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_normalized_record(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.soft_delete_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'SOFT_DELETE_MOVEMENT');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.soft_delete_financial_movement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_financial_movement(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.restore_financial_movement(p_movement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();

  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;

  IF FOUND THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'RESTORE_MOVEMENT');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.restore_financial_movement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_financial_movement(UUID) TO authenticated;


-- ============================================================
-- 6. ASIGNAR CATEGORÍA/ACTIVIDAD A REGISTROS (CON VALIDACIÓN)
-- ============================================================

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
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  -- Validar que la categoría pertenezca a la org y esté activa
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE;
    
    IF v_valid_category IS NOT TRUE THEN
      RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive';
    END IF;
  END IF;

  -- Validar que la actividad pertenezca a la org y esté activa
  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE;
    
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
REVOKE ALL ON FUNCTION public.update_record_classification(UUID, UUID, UUID) FROM PUBLIC;
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
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_category
    FROM public.eco_org_tax_categories
    WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE;
    IF v_valid_category IS NOT TRUE THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT TRUE INTO v_valid_activity
    FROM public.eco_org_economic_activities
    WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE;
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
REVOKE ALL ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) TO authenticated;


-- ============================================================
-- 7. CATEGORY CRUD Y ORG ASSIGNMENT
-- ============================================================

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
  
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

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
REVOKE ALL ON FUNCTION public.create_global_tax_category(TEXT, TEXT, TEXT) FROM PUBLIC;
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
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_tax_categories
  SET name = p_name, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_category_id;
  
  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'CATEGORY_UPDATED');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_global_tax_category(UUID, TEXT, TEXT, BOOLEAN) TO authenticated;


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


-- ============================================================
-- 8. ACTIVITY CRUD Y ORG ASSIGNMENT
-- ============================================================

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
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  INSERT INTO public.eco_economic_activities (name, afip_code, description, is_active)
  VALUES (p_name, p_afip_code, p_description, TRUE)
  RETURNING id INTO v_new_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_CREATED');
  END IF;

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_global_economic_activity(TEXT, TEXT, TEXT) FROM PUBLIC;
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
  IF v_caller_role != 'ADMIN' THEN RAISE EXCEPTION 'Unauthorized: ADMIN role required'; END IF;

  UPDATE public.eco_economic_activities
  SET name = p_name, afip_code = p_afip_code, description = p_description, is_active = p_is_active, updated_at = now()
  WHERE id = p_activity_id;

  IF v_org_id IS NOT NULL THEN
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ACTIVITY_UPDATED');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_global_economic_activity(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;


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
  IF v_caller_role NOT IN ('REVIEWER', 'ADMIN') THEN RAISE EXCEPTION 'Unauthorized: Requires REVIEWER or ADMIN role'; END IF;
  
  SELECT id INTO v_caller_id FROM public.eco_user_profiles WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  IF p_category_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_tax_categories WHERE organization_id = v_org_id AND category_id = p_category_id AND is_active = TRUE
    ) INTO v_valid;
    IF NOT v_valid THEN RAISE EXCEPTION 'Category ID is not assigned to this organization or is inactive'; END IF;
  END IF;

  IF p_activity_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM public.eco_org_economic_activities WHERE organization_id = v_org_id AND activity_id = p_activity_id AND is_active = TRUE
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
REVOKE ALL ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_update_record_classification(TEXT, DATE, DATE, UUID, UUID) TO authenticated;

COMMIT;
