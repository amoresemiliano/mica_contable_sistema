-- Migration 016: Immutable Failed Import Retry Support
-- Purpose: Provide server-supported transactional retry for failed import attempts without modifying Migration 014.
-- Ensures original import, file, issues, and audit history remain 100% IMMUTABLE.
-- SAFE FOR HUMAN GATE (DO NOT APPLY AUTOMATICALLY TO LIVE SUPABASE).

BEGIN;

-- 1. Function: request_failed_import_retry(UUID)
CREATE OR REPLACE FUNCTION public.request_failed_import_retry(
    p_import_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_org_id UUID;
    v_role TEXT;
    v_import_record RECORD;
    v_downstream_count INT := 0;
    v_new_import_id UUID;
BEGIN
    -- Security check: tenant isolation & authorization
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    v_role := private.func_role();
    IF v_role NOT IN ('ADMIN', 'UPLOADER') THEN
        RAISE EXCEPTION 'Unauthorized: Caller role % cannot request import retry', COALESCE(v_role, 'NONE');
    END IF;

    -- Lock original import record for inspection
    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    -- Invariant: Retry allowed ONLY if original accepted_rows = 0 (or null)
    IF COALESCE(v_import_record.accepted_rows, 0) > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % accepted rows', v_import_record.accepted_rows;
    END IF;

    -- Check downstream business rows
    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_normalized_records
        WHERE import_id = p_import_id AND organization_id = v_org_id AND deleted_at IS NULL;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_financial_movements
        WHERE import_id = p_import_id AND organization_id = v_org_id AND deleted_at IS NULL;
    END IF;

    IF v_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % downstream records persisted', v_downstream_count;
    END IF;

    -- Generate new retry import attempt ID
    v_new_import_id := extensions.gen_random_uuid();

    -- Insert new retry import record (Original record remains 100% IMMUTABLE)
    INSERT INTO public.eco_source_imports (
        id,
        organization_id,
        status,
        source_type,
        operation_type,
        total_rows,
        accepted_rows,
        invalid_rows,
        duplicate_rows,
        created_at
    ) VALUES (
        v_new_import_id,
        v_org_id,
        'PENDING',
        v_import_record.source_type,
        v_import_record.operation_type,
        0,
        0,
        0,
        0,
        NOW()
    );

    -- Log audit event using established eco_audit_events schema
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED');

    RETURN jsonb_build_object(
        'status', 'RETRY_CREATED',
        'original_import_id', p_import_id,
        'new_import_id', v_new_import_id,
        'message', 'Retry import attempt created successfully'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.request_failed_import_retry(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_failed_import_retry(UUID) TO authenticated;

COMMIT;
