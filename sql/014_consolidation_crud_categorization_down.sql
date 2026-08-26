BEGIN;

DROP FUNCTION IF EXISTS public.update_movement_classification(UUID, UUID, UUID);
DROP FUNCTION IF EXISTS public.update_record_classification(UUID, UUID, UUID);

DROP FUNCTION IF EXISTS public.restore_financial_movement(UUID);
DROP FUNCTION IF EXISTS public.soft_delete_financial_movement(UUID);
DROP FUNCTION IF EXISTS public.restore_normalized_record(UUID);
DROP FUNCTION IF EXISTS public.soft_delete_normalized_record(UUID);

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
  ORDER BY fecha DESC, created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_active_financial_movements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_financial_movements() TO authenticated;

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
  ORDER BY fecha DESC, created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_active_normalized_records() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_normalized_records() TO authenticated;

ALTER TABLE public.eco_financial_movements
  DROP COLUMN IF EXISTS category_id,
  DROP COLUMN IF EXISTS activity_id,
  DROP COLUMN IF EXISTS updated_by,
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS deleted_by,
  DROP COLUMN IF EXISTS deleted_at;

ALTER TABLE public.eco_normalized_records
  DROP COLUMN IF EXISTS category_id,
  DROP COLUMN IF EXISTS activity_id,
  DROP COLUMN IF EXISTS updated_by,
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS deleted_by,
  DROP COLUMN IF EXISTS deleted_at;

ALTER TABLE public.eco_normalized_records 
  RENAME COLUMN legacy_categoria_text TO categoria;

DROP TABLE IF EXISTS public.eco_org_tax_categories;
DROP TABLE IF EXISTS public.eco_org_economic_activities;
DROP TABLE IF EXISTS public.eco_tax_categories;
DROP TABLE IF EXISTS public.eco_economic_activities;

COMMIT;
