-- ============================================================
-- Migration 024: Operational Read/Write Consistency Restoration
-- Project: MICA
-- Work Package: WP-FUNC-1
-- ============================================================

BEGIN;

-- 1. UPDATE check_file_importable
-- Invariant: An import attempt that failed or resulted in 0 accepted rows
-- must NOT permanently block file re-upload via SHA256 deduplication.
DROP FUNCTION IF EXISTS public.check_file_importable(TEXT);

CREATE OR REPLACE FUNCTION public.check_file_importable(p_sha256_hash TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_existing_file_id UUID;
BEGIN
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF p_sha256_hash IS NULL OR NOT (p_sha256_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid SHA-256 hash format';
  END IF;

  SELECT sf.id INTO v_existing_file_id
  FROM public.eco_source_files sf
  JOIN public.eco_source_imports si ON si.id = sf.import_id
  WHERE sf.organization_id = v_org_id 
    AND sf.sha256_hash = p_sha256_hash
    AND COALESCE(si.accepted_rows, 0) > 0;

  IF v_existing_file_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'importable', false,
      'reason', 'FILE_ALREADY_EXISTS',
      'existing_file_id', v_existing_file_id
    );
  END IF;

  RETURN jsonb_build_object(
    'importable', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_file_importable(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_file_importable(TEXT) TO authenticated;


-- 2. UPDATE persist_financial_movements_batch
-- Fix column names: movement_type (not tipo), financial_fingerprint (not fingerprint)
CREATE OR REPLACE FUNCTION public.persist_financial_movements_batch(
    p_import_id UUID,
    p_file_info JSONB,
    p_staged_rows JSONB
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
    v_existing_successful_cnt INT := 0;
    v_file_id UUID;
    v_hash TEXT;
    v_filename TEXT;
    v_size BIGINT;
    v_mime TEXT;
    v_storage_path TEXT;
    v_row JSONB;
    v_norm JSONB;
    v_is_invalid BOOLEAN;
    v_total_cnt INT := 0;
    v_accepted_cnt INT := 0;
    v_invalid_cnt INT := 0;
    v_duplicate_cnt INT := 0;
    v_fecha DATE;
    v_fecha_valor DATE;
    v_referencia TEXT;
    v_saldo NUMERIC(15,2);
    v_monto NUMERIC(15,2);
    v_tipo TEXT;
    v_account_id TEXT;
    v_descripcion TEXT;
    v_periodo TEXT;
    v_computed_identity_key TEXT;
    v_computed_fingerprint TEXT;
    v_existing_mvmt_id UUID;
    v_row_status TEXT;
    v_neto NUMERIC(15,2);
    v_fecha_raw TEXT;
    v_fecha_valor_raw TEXT;
BEGIN
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'No active organization found for caller';
    END IF;

    v_role := private.func_role();
    IF v_role NOT IN ('ADMIN', 'UPLOADER', 'SUPERADMIN') THEN
        RAISE EXCEPTION 'Unauthorized: Caller role % cannot persist financial movements', COALESCE(v_role, 'NONE');
    END IF;

    SELECT * INTO v_import_record
    FROM public.eco_source_imports
    WHERE id = p_import_id AND organization_id = v_org_id FOR UPDATE;

    IF v_import_record IS NULL THEN
        RAISE EXCEPTION 'Import record not found or access denied';
    END IF;

    IF v_import_record.status NOT IN ('PENDING', 'PROCESSING', 'COMPLETED_WITH_ISSUES', 'FAILED') THEN
        RAISE EXCEPTION 'Import no está en estado válido para procesamiento';
    END IF;

    IF jsonb_array_length(p_staged_rows) > 500 THEN
        RAISE EXCEPTION 'Batch size exceeds 500 rows limit';
    END IF;

    v_hash := p_file_info->>'sha256_hash';
    IF v_hash IS NULL OR NOT (v_hash ~* '^[0-9a-f]{64}$') THEN
        RAISE EXCEPTION 'Invalid or missing SHA-256 hash';
    END IF;

    v_filename := TRIM(COALESCE(p_file_info->>'original_name', ''));
    v_size := (p_file_info->>'size_bytes')::BIGINT;
    v_mime := p_file_info->>'mime_type';
    v_storage_path := p_file_info->>'storage_path';

    -- Check existing file for sha256 duplicate: Only block if duplicate belongs to an import with accepted business rows
    SELECT COUNT(*) INTO v_existing_successful_cnt
    FROM public.eco_source_files sf
    JOIN public.eco_source_imports si ON si.id = sf.import_id
    WHERE sf.organization_id = v_org_id 
      AND sf.sha256_hash = v_hash 
      AND sf.import_id != p_import_id
      AND si.id != COALESCE(v_import_record.retry_of_import_id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND COALESCE(si.accepted_rows, 0) > 0;

    IF v_existing_successful_cnt > 0 THEN
        RAISE EXCEPTION 'FILE_ALREADY_EXISTS: File with hash % already successfully imported', v_hash;
    END IF;

    -- Fetch existing file_id linked to current import_id OR retry_of_import_id
    SELECT id INTO v_file_id
    FROM public.eco_source_files
    WHERE (import_id = p_import_id OR (v_import_record.retry_of_import_id IS NOT NULL AND import_id = v_import_record.retry_of_import_id))
      AND organization_id = v_org_id 
    ORDER BY created_at ASC LIMIT 1;

    IF v_file_id IS NULL THEN
        INSERT INTO public.eco_source_files (
            import_id,
            organization_id,
            original_name,
            storage_path,
            mime_type,
            size_bytes,
            sha256_hash,
            source_type
        ) VALUES (
            p_import_id,
            v_org_id,
            v_filename,
            v_storage_path,
            v_mime,
            v_size,
            v_hash,
            v_import_record.source_type
        ) RETURNING id INTO v_file_id;
    END IF;

    UPDATE public.eco_source_imports SET status = 'PROCESSING' WHERE id = p_import_id;

    -- Row processing loop
    FOR v_row IN SELECT * FROM jsonb_array_elements(p_staged_rows)
    LOOP
        v_fecha := NULL;
        v_fecha_valor := NULL;
        v_referencia := NULL;
        v_saldo := NULL;
        v_monto := NULL;
        v_tipo := NULL;
        v_account_id := NULL;
        v_descripcion := NULL;
        v_periodo := NULL;
        v_computed_identity_key := NULL;
        v_computed_fingerprint := NULL;
        v_is_invalid := FALSE;
        v_row_status := 'ACCEPTED';

        v_total_cnt := v_total_cnt + 1;
        v_norm := v_row->'normalizedData';

        IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' OR (v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0) THEN
            v_is_invalid := TRUE;
        END IF;

        IF NOT v_is_invalid THEN
            BEGIN
                IF v_import_record.source_type = 'PAYROLL_ACONPY' THEN
                    v_periodo := TRIM(COALESCE(v_norm->>'periodo', ''));
                    IF v_periodo ~ '^(0[1-9]|1[0-2])/\d{4}$' THEN
                        v_periodo := RIGHT(v_periodo, 4) || '-' || LEFT(v_periodo, 2);
                    ELSIF v_periodo ~ '^\d{4}-(0[1-9]|1[0-2])$' THEN
                        -- YYYY-MM
                    ELSE
                        v_is_invalid := TRUE;
                    END IF;

                    IF NOT v_is_invalid THEN
                        v_computed_identity_key := jsonb_build_array('PAYROLL_ACONPY', v_periodo)::text;
                        v_neto := ROUND(COALESCE(NULLIF(v_norm->>'sueldoNeto', ''), '0')::numeric, 2);
                        v_computed_fingerprint := ENCODE(extensions.digest(
                            TO_CHAR(v_neto, 'FM999999999999990.00'), 'sha256'
                        ), 'hex');
                    END IF;

                ELSIF v_import_record.source_type = 'BANK_STATEMENT_BBVA' THEN
                    v_fecha_raw := TRIM(COALESCE(v_norm->>'fecha', ''));
                    IF v_fecha_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN 
                        v_fecha := v_fecha_raw::DATE;
                    ELSIF v_fecha_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN 
                        v_fecha := TO_DATE(v_fecha_raw, 'DD/MM/YYYY');
                    ELSIF v_fecha_raw ~ '^\d{2}-\d{2}-\d{4}$' THEN 
                        v_fecha := TO_DATE(v_fecha_raw, 'DD-MM-YYYY');
                    ELSE 
                        v_is_invalid := TRUE; 
                    END IF;

                    v_fecha_valor_raw := TRIM(COALESCE(v_norm->>'fechaValor', ''));
                    IF v_fecha_valor_raw = '' THEN 
                        v_fecha_valor := v_fecha;
                    ELSIF v_fecha_valor_raw ~ '^\d{4}-\d{2}-\d{2}$' THEN 
                        v_fecha_valor := v_fecha_valor_raw::DATE;
                    ELSIF v_fecha_valor_raw ~ '^\d{2}/\d{2}/\d{4}$' THEN 
                        v_fecha_valor := TO_DATE(v_fecha_valor_raw, 'DD/MM/YYYY');
                    ELSIF v_fecha_valor_raw ~ '^\d{2}-\d{2}-\d{4}$' THEN 
                        v_fecha_valor := TO_DATE(v_fecha_valor_raw, 'DD-MM-YYYY');
                    ELSE 
                        v_fecha_valor := v_fecha; 
                    END IF;

                    v_referencia := TRIM(COALESCE(v_norm->>'referencia', ''));
                    
                    IF NULLIF(TRIM(v_norm->>'saldo'), '') IS NOT NULL THEN
                        v_saldo := ROUND((v_norm->>'saldo')::numeric, 2);
                    END IF;
                    
                    IF NULLIF(TRIM(v_norm->>'monto'), '') IS NOT NULL THEN
                        v_monto := ROUND((v_norm->>'monto')::numeric, 2);
                    ELSE
                        v_is_invalid := TRUE;
                    END IF;

                    v_tipo := v_norm->>'tipo';
                    v_account_id := COALESCE(v_norm->>'accountIdentifier', '');
                    v_descripcion := TRIM(COALESCE(v_norm->>'descripcion', ''));

                    IF NOT v_is_invalid THEN
                        IF v_referencia != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), v_referencia, v_monto, v_tipo)::text;
                        ELSIF v_saldo IS NOT NULL THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REFERENCE', v_saldo, v_monto, v_tipo)::text;
                        ELSE
                            v_is_invalid := TRUE;
                        END IF;
                    END IF;

                    IF NOT v_is_invalid THEN
                        v_computed_fingerprint := ENCODE(extensions.digest(
                            v_descripcion || '|' || TO_CHAR(v_fecha_valor, 'YYYY-MM-DD'), 'sha256'
                        ), 'hex');
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_is_invalid := TRUE;
            END;
        END IF;

        IF v_is_invalid THEN
            v_invalid_cnt := v_invalid_cnt + 1;
            v_row_status := 'INVALID';
            
            INSERT INTO public.eco_import_issues (
                organization_id,
                import_id,
                issue_type,
                message,
                status
            ) VALUES (
                v_org_id,
                p_import_id,
                'PARSE_ERROR',
                'Fila inválida o incompleta',
                'OPEN'
            );
        ELSE
            -- Check row duplication
            SELECT id INTO v_existing_mvmt_id
            FROM public.eco_financial_movements
            WHERE organization_id = v_org_id 
              AND identity_key = v_computed_identity_key
              AND deleted_at IS NULL LIMIT 1;

            IF v_existing_mvmt_id IS NOT NULL THEN
                v_duplicate_cnt := v_duplicate_cnt + 1;
                v_row_status := 'DUPLICATE';
            ELSE
                INSERT INTO public.eco_financial_movements (
                    organization_id,
                    import_id,
                    operation_type,
                    source_type,
                    fecha,
                    fecha_valor,
                    periodo,
                    descripcion,
                    referencia,
                    monto,
                    movement_type,
                    saldo,
                    identity_key,
                    financial_fingerprint,
                    normalized_payload
                ) VALUES (
                    v_org_id,
                    p_import_id,
                    v_import_record.operation_type,
                    v_import_record.source_type,
                    v_fecha,
                    v_fecha_valor,
                    v_periodo,
                    v_descripcion,
                    v_referencia,
                    v_monto,
                    v_tipo,
                    v_saldo,
                    v_computed_identity_key,
                    v_computed_fingerprint,
                    v_norm
                );
                v_accepted_cnt := v_accepted_cnt + 1;
            END IF;
        END IF;

        -- Record import row log
        INSERT INTO public.eco_import_rows (
            file_id,
            organization_id,
            source_row_number,
            raw_payload,
            parse_status
        ) VALUES (
            v_file_id,
            v_org_id,
            (v_row->>'sourceRowNumber')::INT,
            v_row->'rawRow',
            v_row_status
        );
    END LOOP;

    -- Update final import attempt status
    UPDATE public.eco_source_imports
    SET status = CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
        total_rows = v_total_cnt,
        accepted_rows = v_accepted_cnt,
        invalid_rows = v_invalid_cnt,
        duplicate_rows = v_duplicate_cnt,
        completed_at = NOW()
    WHERE id = p_import_id;

    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'FINANCIAL_MOVEMENTS_PERSISTED');

    RETURN jsonb_build_object(
        'import_id', p_import_id,
        'total_rows', v_total_cnt,
        'accepted_rows', v_accepted_cnt,
        'invalid_rows', v_invalid_cnt,
        'duplicate_rows', v_duplicate_cnt,
        'status', CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) TO authenticated;


-- 3. UPDATE upsert_arca_activity_catalog
-- Return INTEGER count of upserted activities instead of VOID.
DROP FUNCTION IF EXISTS public.upsert_arca_activity_catalog(JSONB);

CREATE OR REPLACE FUNCTION public.upsert_arca_activity_catalog(
  p_activities JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_org_id UUID;
  v_caller_role TEXT;
  v_act JSONB;
  v_count INTEGER := 0;
BEGIN
  v_org_id := private.org_id();
  v_caller_role := private.func_role();
  
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'Unauthorized: Invalid organization'; END IF;
  IF v_caller_role NOT IN ('ADMIN', 'SUPERADMIN') THEN RAISE EXCEPTION 'Unauthorized: ADMIN or SUPERADMIN role required'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized: Must be authenticated'; END IF;

  FOR v_act IN SELECT * FROM jsonb_array_elements(p_activities)
  LOOP
    IF v_act->>'arca_code' IS NULL OR v_act->>'name' IS NULL THEN
      RAISE EXCEPTION 'Invalid activity format: arca_code and name are required';
    END IF;

    INSERT INTO public.eco_economic_activities (name, arca_code, description, is_active)
    VALUES (
      v_act->>'name', 
      v_act->>'arca_code', 
      v_act->>'description', 
      COALESCE((v_act->>'is_active')::BOOLEAN, TRUE)
    )
    ON CONFLICT (arca_code) DO UPDATE
    SET name = EXCLUDED.name,
        description = EXCLUDED.description,
        is_active = EXCLUDED.is_active,
        updated_at = now();

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_arca_activity_catalog(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_arca_activity_catalog(JSONB) TO authenticated;

COMMIT;
