-- ============================================================
-- MIGRATION 028: FIX SOURCE FILE REUSE & ENHANCE RETRY FLOW
-- ============================================================
-- 1. Updates check_file_importable to return explicit retry candidate info
--    (retry_available, retry_candidate_import_id, existing_file_id) when
--    a failed import exists with accepted_rows = 0.
-- 2. Updates persist_financial_movements_batch with defensive fallback to
--    reuse existing source_file by (organization_id, sha256_hash) if not
--    found by direct import lineage.
-- 3. Guarantees that idx_source_files_org_hash is never violated.
-- ============================================================

BEGIN;

-- 1. UPDATE check_file_importable
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
  v_existing_successful_file_id UUID;
  v_retry_candidate_import_id UUID;
  v_existing_file_id UUID;
BEGIN
  v_org_id := private.org_id();

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Invalid organization';
  END IF;

  IF p_sha256_hash IS NULL OR NOT (p_sha256_hash ~* '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Invalid SHA-256 hash format';
  END IF;

  -- 1. Block file re-upload ONLY IF a previous import produced a successful business result (accepted_rows > 0)
  SELECT sf.id INTO v_existing_successful_file_id
  FROM public.eco_source_files sf
  JOIN public.eco_source_imports si ON si.id = sf.import_id
  WHERE sf.organization_id = v_org_id 
    AND sf.sha256_hash = p_sha256_hash
    AND COALESCE(si.accepted_rows, 0) > 0
  LIMIT 1;

  IF v_existing_successful_file_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'importable', false,
      'reason', 'FILE_ALREADY_EXISTS',
      'existing_file_id', v_existing_successful_file_id
    );
  END IF;

  -- 2. Check if there is an existing source file and failed import candidate for retry (accepted_rows = 0)
  SELECT sf.id, sf.import_id INTO v_existing_file_id, v_retry_candidate_import_id
  FROM public.eco_source_files sf
  JOIN public.eco_source_imports si ON si.id = sf.import_id
  WHERE sf.organization_id = v_org_id
    AND sf.sha256_hash = p_sha256_hash
    AND COALESCE(si.accepted_rows, 0) = 0
  ORDER BY sf.created_at ASC
  LIMIT 1;

  IF v_existing_file_id IS NOT NULL AND v_retry_candidate_import_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'importable', true,
      'retry_available', true,
      'retry_candidate_import_id', v_retry_candidate_import_id,
      'existing_file_id', v_existing_file_id
    );
  END IF;

  -- 3. Brand new file
  RETURN jsonb_build_object(
    'importable', true,
    'retry_available', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.check_file_importable(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_file_importable(TEXT) TO authenticated;


-- 2. UPDATE persist_financial_movements_batch
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
    v_invalid_reason TEXT;
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
    v_row_id UUID;
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

    IF v_import_record.status NOT IN ('PENDING', 'PROCESSING', 'COMPLETED_WITH_ISSUES') THEN
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

    -- 1. Fetch existing file_id linked to current import_id OR retry_of_import_id
    SELECT id INTO v_file_id
    FROM public.eco_source_files
    WHERE (import_id = p_import_id OR (v_import_record.retry_of_import_id IS NOT NULL AND import_id = v_import_record.retry_of_import_id))
      AND organization_id = v_org_id 
    ORDER BY created_at ASC LIMIT 1;

    -- 2. Defensive fallback: If not found by direct lineage, search by (org_id, sha256_hash)
    IF v_file_id IS NULL THEN
        SELECT sf.id INTO v_file_id
        FROM public.eco_source_files sf
        WHERE sf.organization_id = v_org_id
          AND sf.sha256_hash = v_hash
        ORDER BY sf.created_at ASC LIMIT 1;
    END IF;

    -- 3. Only insert if truly no source_file exists for this (organization_id, sha256_hash)
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
        v_invalid_reason := 'Fila inválida o incompleta';
        v_row_status := 'ACCEPTED';
        v_row_id := NULL;

        v_total_cnt := v_total_cnt + 1;
        v_norm := v_row->'normalizedData';

        IF v_norm IS NULL OR jsonb_typeof(v_norm) = 'null' THEN
            v_is_invalid := TRUE;
            v_invalid_reason := 'Fila sin datos normalizados';
        ELSIF v_row->'errors' IS NOT NULL AND jsonb_array_length(v_row->'errors') > 0 THEN
            v_is_invalid := TRUE;
            v_invalid_reason := TRIM(BOTH '"' FROM (v_row->'errors'->0)::text);
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
                        v_invalid_reason := 'Formato de periodo inválido: ' || COALESCE(v_periodo, 'NULL');
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
                        v_invalid_reason := 'Formato de fecha inválido o no reconocido: ' || COALESCE(v_fecha_raw, 'NULL');
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
                        v_invalid_reason := 'Importe vacío o inválido';
                    END IF;

                    v_tipo := v_norm->>'tipo';
                    v_account_id := COALESCE(v_norm->>'accountIdentifier', '');
                    v_descripcion := TRIM(COALESCE(v_norm->>'descripcion', ''));

                    IF NOT v_is_invalid THEN
                        IF v_referencia != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), v_referencia, v_monto, v_tipo)::text;
                        ELSIF v_saldo IS NOT NULL THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REFERENCE', v_saldo, v_monto, v_tipo)::text;
                        ELSIF v_descripcion != '' THEN
                            v_computed_identity_key := jsonb_build_array('BANK_STATEMENT_BBVA', v_account_id, TO_CHAR(v_fecha, 'YYYY-MM-DD'), 'NO_REF_NO_SALDO', v_descripcion, v_monto, v_tipo)::text;
                        ELSE
                            v_is_invalid := TRUE;
                            v_invalid_reason := 'Fila sin referencia, saldo ni descripción para identificación';
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
                v_invalid_reason := 'Error de procesamiento: ' || SQLERRM;
            END;
        END IF;

        IF v_is_invalid THEN
            v_row_status := 'INVALID';
        END IF;

        -- 1. Insert row log entry FIRST to satisfy fk_fm_row NOT NULL constraint
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
        ) RETURNING id INTO v_row_id;

        IF v_is_invalid THEN
            v_invalid_cnt := v_invalid_cnt + 1;
            
            INSERT INTO public.eco_import_issues (
                organization_id,
                import_id,
                row_id,
                issue_type,
                message,
                details,
                status
            ) VALUES (
                v_org_id,
                p_import_id,
                v_row_id,
                'PARSE_ERROR',
                'Fila inválida o incompleta',
                jsonb_build_object('technical_error', v_invalid_reason),
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
                UPDATE public.eco_import_rows SET parse_status = 'DUPLICATE' WHERE id = v_row_id;
            ELSE
                INSERT INTO public.eco_financial_movements (
                    organization_id,
                    import_id,
                    row_id,
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
                    v_row_id,
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
    END LOOP;

    -- Update final import attempt status
    UPDATE public.eco_source_imports
    SET status = CASE WHEN v_invalid_cnt > 0 THEN 'COMPLETED_WITH_ISSUES' ELSE 'COMPLETED' END,
        total_rows = v_total_cnt,
        accepted_rows = v_accepted_cnt,
        invalid_rows = v_invalid_cnt,
        duplicate_rows = v_duplicate_cnt,
        completed_at = now()
    WHERE id = p_import_id;

    RETURN jsonb_build_object(
        'import_id', p_import_id,
        'file_id', v_file_id,
        'total_rows', v_total_cnt,
        'accepted_rows', v_accepted_cnt,
        'invalid_rows', v_invalid_cnt,
        'duplicate_rows', v_duplicate_cnt
    );
END;
$$;

REVOKE ALL ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.persist_financial_movements_batch(UUID, JSONB, JSONB) TO authenticated;

COMMIT;
