BEGIN;

-- ============================================================
-- MIGRATION 013.2 DOWN
-- ============================================================
-- No restauramos deliberadamente la RPC defectuosa.
-- Si necesitas revertir por completo los movimientos financieros,
-- utiliza la migración DOWN 013 original (013_financial_movements_pipeline_down.sql)

DO $$
BEGIN
  RAISE WARNING 'Down migration para 013.2 ejecutada de forma segura: no se ha restaurado la RPC anterior.';
END $$;

COMMIT;
