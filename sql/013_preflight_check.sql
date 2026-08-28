-- ============================================================
-- PREFLIGHT CHECK 013: FINANCIAL MOVEMENTS PIPELINE
-- ============================================================

-- READ-ONLY: Verificar estado de la BD antes de aplicar M013

-- 1. Verificar Constraints (Operation_Type)
SELECT
    conname,
    pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'eco_source_imports' AND conname = 'eco_source_imports_operation_type_check';

-- 2. Verificar si ya existe eco_financial_movements
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name = 'eco_financial_movements'
);

-- 3. Verificar Imports Pendientes
SELECT count(*) as pending_imports FROM public.eco_source_imports WHERE status = 'PENDING';

-- 4. Verificar funciones actuales
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name IN ('persist_financial_movements_batch', 'get_active_financial_movements');
