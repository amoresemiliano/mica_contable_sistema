-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY; human application after 039c.
-- Changes only the retry envelope flag. No business rows or grants are changed.
BEGIN;
DO $preflight$
DECLARE p RECORD;
BEGIN
 IF to_regclass('private.migration_039c_functions') IS NULL THEN RAISE EXCEPTION '039c required'; END IF;
 IF to_regclass('private.migration_039d_retry') IS NOT NULL THEN RAISE EXCEPTION '039d already installed'; END IF;
 SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure('public.request_failed_import_retry(uuid)');
 IF NOT FOUND THEN RAISE EXCEPTION 'Retry function missing'; END IF;
 IF pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres' OR NOT p.prosecdef
  OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::TEXT[]
  OR p.prosrc IS DISTINCT FROM $expected039c$
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
        'source_file_reused', v_orig_file IS NOT NULL,
        'storage_path', v_orig_file.storage_path,
        'message', 'Retry import attempt created successfully'
    );
END;
$expected039c$ THEN
  RAISE EXCEPTION '039d preflight: expected exact 039c body, postgres owner, SECURITY DEFINER and empty search_path'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.migration_039c_functions
  WHERE signature='public.request_failed_import_retry(uuid)'
   AND installed_definition=pg_get_functiondef(p.oid)) THEN
  RAISE EXCEPTION '039d preflight: definition differs from installed 039c snapshot'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039d_retry (
 signature TEXT PRIMARY KEY, definition TEXT NOT NULL, installed_definition TEXT,
 owner_oid OID NOT NULL, acl ACLITEM[]
);
ALTER TABLE private.migration_039d_retry ENABLE ROW LEVEL SECURITY;
DO $backup_acl$
DECLARE a RECORD;
BEGIN
 FOR a IN SELECT DISTINCT x.grantee FROM pg_class c,
  LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) x
  WHERE c.oid='private.migration_039d_retry'::regclass AND x.grantee<>c.relowner LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.migration_039d_retry FROM %s',
   CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END);
 END LOOP;
END; $backup_acl$;
INSERT INTO private.migration_039d_retry(signature,definition,owner_oid,acl)
 SELECT 'public.request_failed_import_retry(uuid)',pg_get_functiondef(oid),proowner,proacl
 FROM pg_proc WHERE oid='public.request_failed_import_retry(uuid)'::regprocedure;
DO $patch$
DECLARE r RECORD; replacement TEXT;
BEGIN
 SELECT * INTO STRICT r FROM private.migration_039d_retry;
 replacement:=replace(r.definition,
  $old$'source_file_reused', v_orig_file IS NOT NULL$old$,
  $new$'source_file_reused', v_orig_file.id IS NOT NULL$new$);
 -- CREATE OR REPLACE preserves the existing owner and ACL, including grant options.
 EXECUTE replacement;
 IF pg_get_functiondef(to_regprocedure(r.signature)) IS DISTINCT FROM replacement
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature)
   AND (proowner IS DISTINCT FROM r.owner_oid OR proacl IS DISTINCT FROM r.acl)) THEN
  RAISE EXCEPTION '039d postflight: definition/owner/ACL mismatch'; END IF;
 UPDATE private.migration_039d_retry SET installed_definition=replacement;
END; $patch$;
COMMIT;
