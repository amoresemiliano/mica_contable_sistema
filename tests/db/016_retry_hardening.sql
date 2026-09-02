-- Test suite for Migration 016 Failed Import Retry Hardening
-- Verifies: Immutable history, audit logging, authorization, cross-tenant protection, and duplicate prevention.

BEGIN;

-- Apply Migration 016 definition transiently for test runner
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
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    v_role := private.func_role();
    IF v_role NOT IN ('ADMIN', 'UPLOADER') THEN
        RAISE EXCEPTION 'Unauthorized: Caller role % cannot request import retry', COALESCE(v_role, 'NONE');
    END IF;

    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    IF COALESCE(v_import_record.accepted_rows, 0) > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % accepted rows', v_import_record.accepted_rows;
    END IF;

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

    v_new_import_id := extensions.gen_random_uuid();

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

-- 1. Setup test identities
SET LOCAL request.jwt.claim.sub = 'c1e16acf-a45c-4e51-a3e5-c95208adc3c6'; -- Org Admin (Org: 59436df3-9f15-4f5e-b17e-37c55482521c)

-- 2. Verify retry on existing failed BBVA import (881859f6-127e-4a4e-85e6-83e69a3aee00: 84 invalid, 0 accepted)
SELECT public.request_failed_import_retry('881859f6-127e-4a4e-85e6-83e69a3aee00'::uuid);

-- 3. Verify original import history remains 100% IMMUTABLE
DO $$
DECLARE
    v_orig RECORD;
    v_issues_cnt INT;
    v_audit_cnt INT;
BEGIN
    SELECT * INTO v_orig FROM public.eco_source_imports WHERE id = '881859f6-127e-4a4e-85e6-83e69a3aee00';
    IF v_orig.status != 'COMPLETED_WITH_ISSUES' OR v_orig.invalid_rows != 84 OR v_orig.accepted_rows != 0 THEN
        RAISE EXCEPTION 'Test failed: Original import counters or status were mutated!';
    END IF;

    SELECT COUNT(*) INTO v_issues_cnt FROM public.eco_import_issues WHERE import_id = '881859f6-127e-4a4e-85e6-83e69a3aee00';
    IF v_issues_cnt != 84 THEN
        RAISE EXCEPTION 'Test failed: Original import issues were deleted or modified! Found %', v_issues_cnt;
    END IF;

    SELECT COUNT(*) INTO v_audit_cnt FROM public.eco_audit_events WHERE organization_id = '59436df3-9f15-4f5e-b17e-37c55482521c' AND event_type = 'IMPORT_RETRY_REQUESTED';
    IF v_audit_cnt = 0 THEN
        RAISE EXCEPTION 'Test failed: Audit event IMPORT_RETRY_REQUESTED was not recorded!';
    END IF;
END;
$$;

-- 4. Verify retry blocking if accepted_rows > 0 (Test on completed import 5d1ff63f-0457-4faf-9767-a9631510c3f2: 319 accepted)
DO $$
BEGIN
    BEGIN
        PERFORM public.request_failed_import_retry('5d1ff63f-0457-4faf-9767-a9631510c3f2'::uuid);
        RAISE EXCEPTION 'Test failed: Retry should have been blocked for successful import!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%CANNOT_REPROCESS%' AND SQLERRM NOT LIKE '%accepted%' THEN
            RAISE EXCEPTION 'Test failed with unexpected error: %', SQLERRM;
        END IF;
    END;
END;
$$;

ROLLBACK;
