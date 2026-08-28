-- Preflight Check for Migration 013.1
DO $$
BEGIN
  -- Verify eco_financial_movements exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'eco_financial_movements'
  ) THEN
    RAISE EXCEPTION 'Preflight failed: table public.eco_financial_movements does not exist (Migration 013 not applied)';
  END IF;

  -- Verify persist_financial_movements_batch exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name = 'persist_financial_movements_batch'
  ) THEN
    RAISE EXCEPTION 'Preflight failed: function public.persist_financial_movements_batch does not exist';
  END IF;

  RAISE NOTICE 'Preflight check passed: Migration 013.1 can be safely applied.';
END $$;
