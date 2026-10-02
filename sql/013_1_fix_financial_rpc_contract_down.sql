BEGIN;

-- ============================================================
-- MIGRATION 013.1 DOWN
-- ============================================================
-- No restauramos deliberadamente la RPC 013.0 porque contenía un
-- contrato roto y referencias inexistentes (ej: import_id en eco_import_rows).
-- Si necesitas revertir por completo los movimientos financieros,
-- utiliza la migración DOWN 013 original (013_financial_movements_pipeline_down.sql)
-- que dropea la tabla y revoca los permisos, ya que no existe una 
-- versión de "persist_financial_movements_batch" funcional previa a 013.1.

DO $$
BEGIN
  RAISE WARNING 'Down migration para 013.1 ejecutada de forma segura: no se ha restaurado la RPC defectuosa 013.0.';
END $$;

COMMIT;
