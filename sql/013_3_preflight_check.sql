BEGIN;

-- Check if persist_financial_movements_batch exists
DO $$
DECLARE
  v_func_exists BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' 
      AND p.proname = 'persist_financial_movements_batch'
  ) INTO v_func_exists;

  IF NOT v_func_exists THEN
    RAISE EXCEPTION 'Preflight failed: Function public.persist_financial_movements_batch does not exist. Cannot apply 013.3.';
  END IF;
END $$;

ROLLBACK;
