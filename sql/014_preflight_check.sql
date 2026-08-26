-- 014 PREFLIGHT CHECK

DO $$
BEGIN
  -- Verify eco_user_profiles and private.org_id exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'private' AND p.proname = 'org_id'
  ) THEN
    RAISE EXCEPTION 'private.org_id() not found';
  END IF;

  -- Verify base tables exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'eco_normalized_records'
  ) THEN
    RAISE EXCEPTION 'Table public.eco_normalized_records does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'eco_financial_movements'
  ) THEN
    RAISE EXCEPTION 'Table public.eco_financial_movements does not exist';
  END IF;

  RAISE NOTICE 'Preflight 014 completed successfully.';
END
$$;
