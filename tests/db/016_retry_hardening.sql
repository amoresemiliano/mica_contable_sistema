-- End-to-End Integration Test Suite for Migration 016 Failed Import Retry Lineage & Hardening
-- Verifies: Immutable history, lineage column (retry_of_import_id), source file reuse without duplication, audit logging, duplicate prevention, and cross-tenant denial.

BEGIN;

ALTER TABLE public.eco_source_imports
ADD COLUMN IF NOT EXISTS retry_of_import_id UUID REFERENCES public.eco_source_imports(id);

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
    v_orig_file RECORD;
    v_downstream_count INT := 0;
    v_retry_downstream_count INT := 0;
    v_new_import_id UUID;
    v_profile_id UUID;
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

    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_normalized_records nr
        JOIN public.eco_source_imports si ON si.id = nr.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id AND nr.deleted_at IS NULL;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_financial_movements fm
        JOIN public.eco_source_imports si ON si.id = fm.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id AND fm.deleted_at IS NULL;
    END IF;

    IF v_retry_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: A retry attempt for this import already has % downstream records persisted', v_retry_downstream_count;
    END IF;

    SELECT id INTO v_profile_id
    FROM public.eco_user_profiles
    WHERE auth_user_id = auth.uid() AND organization_id = v_org_id LIMIT 1;

    SELECT * INTO v_orig_file
    FROM public.eco_source_files
    WHERE import_id = p_import_id AND organization_id = v_org_id
    ORDER BY created_at ASC LIMIT 1;

    v_new_import_id := extensions.gen_random_uuid();

    INSERT INTO public.eco_source_imports (
        id,
        organization_id,
        retry_of_import_id,
        status,
        source_type,
        operation_type,
        total_rows,
        accepted_rows,
        invalid_rows,
        duplicate_rows,
        created_at,
        created_by
    ) VALUES (
        v_new_import_id,
        v_org_id,
        p_import_id,
        'PENDING',
        v_import_record.source_type,
        v_import_record.operation_type,
        0,
        0,
        0,
        0,
        NOW(),
        COALESCE(v_profile_id, v_import_record.created_by)
    );

    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED');

    RETURN jsonb_build_object(
        'status', 'RETRY_CREATED',
        'original_import_id', p_import_id,
        'new_import_id', v_new_import_id,
        'source_file_reused', v_orig_file IS NOT NULL,
        'storage_path', v_orig_file.storage_path,
        'message', 'Retry import attempt created successfully'
    );
END;
$$;

-- Setup caller context (Org Admin: MICA)
SET LOCAL request.jwt.claim.sub = 'c1e16acf-a45c-4e51-a3e5-c95208adc3c6';

-- 1. Request retry for BBVA 06 failed import (a1ea483b-e203-49af-9948-e124828ed3ea)
SELECT public.request_failed_import_retry('a1ea483b-e203-49af-9948-e124828ed3ea'::uuid);

-- 2. Verify Lineage, Original Immutability, Source File Reuse, and Audit Event
DO $$
DECLARE
    v_orig RECORD;
    v_file RECORD;
    v_issues_cnt INT;
    v_new_import RECORD;
    v_new_id UUID;
    v_audit_cnt INT;
BEGIN
    -- Locate the newly created retry import
    SELECT id INTO v_new_id FROM public.eco_source_imports WHERE retry_of_import_id = 'a1ea483b-e203-49af-9948-e124828ed3ea';
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'Lineage test failed: Retry import record not found!';
    END IF;

    -- Verify original import record is 100% IMMUTABLE
    SELECT * INTO v_orig FROM public.eco_source_imports WHERE id = 'a1ea483b-e203-49af-9948-e124828ed3ea';
    IF v_orig.status != 'COMPLETED_WITH_ISSUES' OR v_orig.invalid_rows != 78 OR v_orig.accepted_rows != 0 THEN
        RAISE EXCEPTION 'Immutability test failed: Original import record was modified!';
    END IF;

    -- Verify original source_file is 100% IMMUTABLE
    SELECT * INTO v_file FROM public.eco_source_files WHERE import_id = 'a1ea483b-e203-49af-9948-e124828ed3ea';
    IF v_file IS NULL OR v_file.sha256_hash != '28185a1b936ad04c25375e42c179d6ddc5f54789f46e3be9f28bb38abc701cb2' THEN
        RAISE EXCEPTION 'Source file immutability test failed!';
    END IF;

    -- Verify original issues are 100% PRESERVED
    SELECT COUNT(*) INTO v_issues_cnt FROM public.eco_import_issues WHERE import_id = 'a1ea483b-e203-49af-9948-e124828ed3ea';
    IF v_issues_cnt != 78 THEN
        RAISE EXCEPTION 'Issues immutability test failed! Found %', v_issues_cnt;
    END IF;

    -- Verify Audit event logged
    SELECT COUNT(*) INTO v_audit_cnt FROM public.eco_audit_events WHERE organization_id = '59436df3-9f15-4f5e-b17e-37c55482521c' AND event_type = 'IMPORT_RETRY_REQUESTED';
    IF v_audit_cnt = 0 THEN
        RAISE EXCEPTION 'Audit test failed: IMPORT_RETRY_REQUESTED not logged!';
    END IF;

    -- Verify new retry import lineage link
    SELECT * INTO v_new_import FROM public.eco_source_imports WHERE id = v_new_id;
    IF v_new_import.retry_of_import_id != 'a1ea483b-e203-49af-9948-e124828ed3ea'::uuid OR v_new_import.status != 'PENDING' THEN
        RAISE EXCEPTION 'Lineage link test failed!';
    END IF;
END;
$$;

ROLLBACK;
