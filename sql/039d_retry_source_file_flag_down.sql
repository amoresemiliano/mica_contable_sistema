-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Restores the defective 039c flag.
-- Refuses later definition/owner/ACL drift. Does not run the 039c rollback.
BEGIN;
DO $restore$
DECLARE r RECORD; p RECORD;
BEGIN
 IF to_regclass('private.migration_039d_retry') IS NULL THEN RAISE EXCEPTION '039d not installed'; END IF;
 SELECT * INTO STRICT r FROM private.migration_039d_retry
  WHERE signature='public.request_failed_import_retry(uuid)';
 SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(r.signature);
 IF NOT FOUND THEN RAISE EXCEPTION 'Retry function missing'; END IF;
 IF pg_get_functiondef(p.oid) IS DISTINCT FROM r.installed_definition
  OR p.prosrc IS DISTINCT FROM $expected039d$
DECLARE
    v_org_id UUID;

    v_import_record RECORD;
    v_orig_file RECORD;
    v_downstream_count INT := 0;
    v_retry_downstream_count INT := 0;
    v_new_import_id UUID;
    v_profile_id UUID;
BEGIN
  PERFORM private.require_039_action('IMPORT_RETRY'); PERFORM private.require_039_batch(p_import_id,ARRAY['COMPRA','VENTA','PERCEPCION','BANCO','SUELDO']);
    -- Security check: tenant isolation & authorization
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
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

    -- Check downstream business rows for original import
    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_normalized_records nr
        JOIN public.eco_import_rows ir ON ir.id = nr.row_id
        JOIN public.eco_source_files sf ON sf.id = ir.file_id
        WHERE sf.import_id = p_import_id AND sf.organization_id = v_org_id;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_downstream_count
        FROM public.eco_financial_movements
        WHERE import_id = p_import_id AND organization_id = v_org_id;
    END IF;

    IF v_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: Original import has % downstream records persisted', v_downstream_count;
    END IF;

    -- Check if any existing retry attempt for this original import already has accepted or downstream rows
    IF v_import_record.operation_type IN ('COMPRA', 'VENTA', 'PERCEPCION') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_normalized_records nr
        JOIN public.eco_import_rows ir ON ir.id = nr.row_id
        JOIN public.eco_source_files sf ON sf.id = ir.file_id
        JOIN public.eco_source_imports si ON si.id = sf.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id;
    ELSIF v_import_record.operation_type IN ('BANCO', 'SUELDO') THEN
        SELECT COUNT(*) INTO v_retry_downstream_count
        FROM public.eco_financial_movements fm
        JOIN public.eco_source_imports si ON si.id = fm.import_id
        WHERE si.retry_of_import_id = p_import_id AND si.organization_id = v_org_id;
    END IF;

    IF v_retry_downstream_count > 0 THEN
        RAISE EXCEPTION 'CANNOT_REPROCESS: A retry attempt for this import already has % downstream records persisted', v_retry_downstream_count;
    END IF;

    SELECT id INTO v_profile_id
    FROM public.eco_user_profiles
    WHERE auth_user_id = auth.uid() AND is_active LIMIT 1;

    SELECT * INTO v_orig_file
    FROM public.eco_source_files
    WHERE import_id = p_import_id AND organization_id = v_org_id
    ORDER BY created_at ASC LIMIT 1;

    -- Generate new retry import attempt ID
    v_new_import_id := extensions.gen_random_uuid();

    -- Insert new retry import record (Original record & original file record remain 100% IMMUTABLE)
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
        v_profile_id
    );

    -- Log audit event
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'IMPORT_RETRY_REQUESTED');

    RETURN jsonb_build_object(
        'status', 'RETRY_CREATED',
        'original_import_id', p_import_id,
        'new_import_id', v_new_import_id,
        'import_id', v_new_import_id,
        'organization_id', v_org_id,
        'storage_prefix', v_org_id::text || '/' || v_new_import_id::text,
        'source_file_reused', v_orig_file.id IS NOT NULL,
        'storage_path', v_orig_file.storage_path,
        'message', 'Retry import attempt created successfully'
    );
END;
$expected039d$
  OR p.proowner IS DISTINCT FROM r.owner_oid OR p.proacl IS DISTINCT FROM r.acl THEN
  RAISE EXCEPTION '039d rollback: later definition/owner/ACL drift'; END IF;
 EXECUTE r.definition;
 IF pg_get_functiondef(p.oid) IS DISTINCT FROM r.definition
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid=p.oid
   AND (proowner IS DISTINCT FROM r.owner_oid OR proacl IS DISTINCT FROM r.acl)) THEN
  RAISE EXCEPTION '039d rollback: exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039d_retry;
COMMIT;
