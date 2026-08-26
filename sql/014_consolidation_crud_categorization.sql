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
  afip_code TEXT,
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


-- ============================================================
-- 2. SOFT DELETE Y RELACIONES
-- ============================================================

-- Renombrar el campo viejo 'categoria' para mantener retrocompatibilidad de datos
ALTER TABLE public.eco_normalized_records 
  RENAME COLUMN categoria TO legacy_categoria_text;

ALTER TABLE public.eco_normalized_records
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.eco_tax_categories(id),
  ADD COLUMN IF NOT EXISTS activity_id UUID REFERENCES public.eco_economic_activities(id);

ALTER TABLE public.eco_financial_movements
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES public.eco_user_profiles(id),
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.eco_tax_categories(id),
  ADD COLUMN IF NOT EXISTS activity_id UUID REFERENCES public.eco_economic_activities(id);

-- ============================================================
-- 3. AJUSTAR LECTURA DE REGISTROS NORMALIZADOS (EXCLUIR BORRADOS)
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
-- 4. SOFT DELETE ACTIONS (RPC)
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = now(), deleted_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET deleted_at = NULL, deleted_by = NULL, updated_at = now(), updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.restore_financial_movement(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restore_financial_movement(UUID) TO authenticated;


-- ============================================================
-- 5. ASIGNAR CATEGORÍA A REGISTROS
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_normalized_records
  SET category_id = p_category_id, 
      activity_id = p_activity_id,
      updated_at = now(), 
      updated_by = v_caller_id
  WHERE id = p_record_id AND organization_id = v_org_id AND deleted_at IS NULL;
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
BEGIN
  v_org_id := private.org_id();
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  
  SELECT id INTO v_caller_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = auth.uid() AND is_active = TRUE;

  UPDATE public.eco_financial_movements
  SET category_id = p_category_id, 
      activity_id = p_activity_id,
      updated_at = now(), 
      updated_by = v_caller_id
  WHERE id = p_movement_id AND organization_id = v_org_id AND deleted_at IS NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_movement_classification(UUID, UUID, UUID) TO authenticated;

COMMIT;
