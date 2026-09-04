-- Verification script for Migration 017
BEGIN;

-- 1. Verificar existencia de las 3 organizaciones DEMO
SELECT id, name FROM public.eco_organizations WHERE name IN ('DEMO NORTE', 'DEMO SUR', 'DEMO OESTE');

-- 2. Verificar existencia de columna canonical auth_user_id y ausencia de legacy firebase_uid
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'eco_user_profiles' AND column_name = 'auth_user_id') THEN
    RAISE EXCEPTION 'Verification FAILED: auth_user_id column missing in eco_user_profiles';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'eco_user_profiles' AND column_name = 'firebase_uid') THEN
    RAISE EXCEPTION 'Verification FAILED: firebase_uid column present in eco_user_profiles';
  END IF;
END $$;

-- 3. Verificar que switch_superadmin_org_context existe y usa auth.uid() sin firebase_uid
DO $$
DECLARE
  v_procdef TEXT;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_procdef
  FROM pg_proc
  WHERE proname = 'switch_superadmin_org_context';

  IF v_procdef IS NULL THEN
    RAISE EXCEPTION 'Verification FAILED: switch_superadmin_org_context function missing';
  END IF;

  IF v_procdef LIKE '%firebase_uid%' OR v_procdef LIKE '%auth.jwt%' THEN
    RAISE EXCEPTION 'Verification FAILED: switch_superadmin_org_context contains legacy Firebase or auth.jwt references';
  END IF;

  IF v_procdef NOT LIKE '%auth_user_id = auth.uid()%' THEN
    RAISE EXCEPTION 'Verification FAILED: switch_superadmin_org_context does not use auth_user_id = auth.uid() contract';
  END IF;
END $$;

-- 4. Verificar funciones RPC actualizadas
SELECT proname, pg_get_function_identity_arguments(oid) AS args
FROM pg_proc
WHERE proname IN (
  'switch_superadmin_org_context',
  'assign_tax_category_to_org',
  'unassign_tax_category_from_org',
  'assign_economic_activity_to_org',
  'unassign_economic_activity_from_org'
);

-- 5. Verificar RLS activo en tablas multitenant
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('eco_org_tax_categories', 'eco_org_economic_activities', 'eco_org_activity_iibb_rates');

ROLLBACK;
