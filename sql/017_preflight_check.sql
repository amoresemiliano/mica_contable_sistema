-- Preflight check para Migración 017
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_organizations') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_organizations does not exist.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'eco_org_tax_categories') THEN
    RAISE EXCEPTION 'Preflight check FAILED: Table public.eco_org_tax_categories does not exist.';
  END IF;

  RAISE NOTICE 'Preflight check PASSED for Migration 017.';
END $$;
