-- ============================================================
-- DOWN MIGRATION 013: PERSISTENT FINANCIAL MOVEMENTS PIPELINE
-- ============================================================

-- IMPORTANTE: Este rollback debe ejecutarse SOLO si la migración
-- no tiene datos productivos críticos. No borrar infraestructura fiscal existente.

DROP FUNCTION IF EXISTS public.get_active_financial_movements();
DROP FUNCTION IF EXISTS public.persist_financial_movements_batch(UUID, JSONB, JSONB);

DROP TABLE IF EXISTS public.eco_financial_movements CASCADE;
