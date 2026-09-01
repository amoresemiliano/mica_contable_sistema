-- Migration 016: Operational Read Contracts & Failed Import Retry Support
-- Purpose: Add missing read RPC contracts for tax categories and economic activities,
-- and provide server-supported failed import reprocessing without modifying Migration 014.
-- SAFE FOR HUMAN GATE (DO NOT APPLY AUTOMATICALLY TO LIVE SUPABASE).

BEGIN;

-- 1. Function: get_active_tax_categories()
CREATE OR REPLACE FUNCTION public.get_active_tax_categories()
RETURNS TABLE (
    id UUID,
    organization_id UUID,
    name VARCHAR(100),
    description TEXT,
    category_type VARCHAR(20),
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
BEGIN
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    RETURN QUERY
    SELECT 
        tc.id,
        otc.organization_id,
        tc.name,
        tc.description,
        tc.category_type,
        otc.is_active,
        otc.created_at,
        otc.updated_at
    FROM public.eco_org_tax_categories otc
    JOIN public.eco_tax_categories tc ON tc.id = otc.category_id
    WHERE otc.organization_id = v_org_id
      AND otc.is_active = TRUE
      AND tc.is_active = TRUE
    ORDER BY tc.name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_tax_categories() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_tax_categories() TO authenticated;


-- 2. Function: get_active_economic_activities()
CREATE OR REPLACE FUNCTION public.get_active_economic_activities()
RETURNS TABLE (
    id UUID,
    organization_id UUID,
    arca_code VARCHAR(20),
    name VARCHAR(255),
    description TEXT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
BEGIN
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    RETURN QUERY
    SELECT 
        ea.id,
        oea.organization_id,
        ea.arca_code,
        ea.name,
        ea.description,
        oea.is_active,
        oea.created_at
    FROM public.eco_org_economic_activities oea
    JOIN public.eco_economic_activities ea ON ea.id = oea.activity_id
    WHERE oea.organization_id = v_org_id
      AND oea.is_active = TRUE
      AND ea.is_active = TRUE
    ORDER BY ea.arca_code ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_economic_activities() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_economic_activities() TO authenticated;


-- 3. Function: reprocess_failed_import(UUID)
-- Safe server-supported retry when previous import accepted_rows = 0 and 0 downstream business rows exist.
CREATE OR REPLACE FUNCTION public.reprocess_failed_import(
    p_import_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_org_id UUID;
    v_import_record RECORD;
    v_downstream_count INT;
BEGIN
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    IF v_import_record.accepted_rows > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Import has % accepted rows', v_import_record.accepted_rows;
    END IF;

    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_normalized_records
        WHERE import_id = p_import_id AND organization_id = v_org_id;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_financial_movements
        WHERE import_id = p_import_id AND organization_id = v_org_id;
    ELSE
        v_downstream_count := 0;
    END IF;

    IF v_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Import has % downstream records persisted', v_downstream_count;
    END IF;

    -- Reset status to PENDING for controlled re-batch persistence
    UPDATE public.eco_source_imports
    SET status = 'PENDING',
        total_rows = 0,
        accepted_rows = 0,
        invalid_rows = 0,
        duplicate_rows = 0
    WHERE id = p_import_id;

    -- Delete associated source_files entry so new hash validation can complete without duplicate constraint error
    DELETE FROM public.eco_source_files
    WHERE import_id = p_import_id AND organization_id = v_org_id;

    -- Clear old issues for a clean retry attempt
    DELETE FROM public.eco_import_issues
    WHERE import_id = p_import_id AND organization_id = v_org_id;

    RETURN jsonb_build_object(
        'status', 'RESET_SUCCESSFUL',
        'import_id', p_import_id,
        'message', 'Import status reset to PENDING for safe reprocessing'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.reprocess_failed_import(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reprocess_failed_import(UUID) TO authenticated;

COMMIT;
