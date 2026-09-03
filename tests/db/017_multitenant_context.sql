-- Verification script for Migration 017
BEGIN;

-- 1. Verificar existencia de las 3 organizaciones DEMO
SELECT id, name FROM public.eco_organizations WHERE name IN ('DEMO NORTE', 'DEMO SUR', 'DEMO OESTE');

-- 2. Verificar funciones RPC
SELECT proname FROM pg_proc WHERE proname IN ('switch_superadmin_org_context', 'assign_tax_category_to_org', 'unassign_tax_category_from_org');

ROLLBACK;
