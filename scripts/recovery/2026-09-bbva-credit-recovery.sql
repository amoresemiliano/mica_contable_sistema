-- ONE-OFF RECOVERY SCRIPT FOR HISTORICAL BBVA CREDIT MOVEMENTS
-- Target: Recover 9 missing May 2026 credit movements and 15 missing June 2026 credit movements
-- Strategy: Create distinct recovery import attempts linked via retry_of_import_id
-- Invariance: Original & Retry Import records, Source Files, Issues, and existing 130 movements remain 100% IMMUTABLE.
-- Execution Mode: One-Off application (REQUIRES MANUAL HUMAN GATE APPROVAL PRIOR TO RUNNING ON LIVE DB).

BEGIN;

DO $$
DECLARE
    v_org_id UUID;
    v_cnt_may_debit INT;
    v_cnt_june_debit INT;
    v_cnt_total_bbva INT;
    v_may_retry_id UUID := '8a6ca4d8-a31f-4a1b-b145-85336958c843'::uuid;
    v_june_retry_id UUID := 'b6024ac0-afb9-4da1-a984-4fcbfbd7eedc'::uuid;
    v_may_recovery_import_id UUID;
    v_june_recovery_import_id UUID;
    v_may_file_id UUID;
    v_june_file_id UUID;
    v_inserted_may INT := 0;
    v_inserted_june INT := 0;
    v_final_may INT;
    v_final_june INT;
    v_final_total INT;
    v_user_profile_id UUID;
    
    v_r RECORD;
    v_identity_key TEXT;
    v_fingerprint TEXT;
    v_row_id UUID;
    v_existing_id UUID;
BEGIN
    -- 1. Resolve Organization Scope (Tenant Isolation)
    v_org_id := private.org_id();
    IF v_org_id IS NULL THEN
        SELECT organization_id INTO v_org_id 
        FROM public.eco_source_imports 
        WHERE id = v_may_retry_id LIMIT 1;
    END IF;

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION FAILED: Cannot resolve target organization_id.';
    END IF;

    SELECT id INTO v_user_profile_id
    FROM public.eco_user_profiles
    WHERE organization_id = v_org_id LIMIT 1;

    -- 2. Precondition Verification: Tenant-scoped active BBVA counts prior to recovery MUST be May=71, June=59, Total=130
    SELECT count(*) INTO v_cnt_may_debit 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND import_id = v_may_retry_id AND deleted_at IS NULL;

    SELECT count(*) INTO v_cnt_june_debit 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND import_id = v_june_retry_id AND deleted_at IS NULL;

    SELECT count(*) INTO v_cnt_total_bbva 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND source_type = 'BANK_STATEMENT_BBVA' AND deleted_at IS NULL;

    RAISE NOTICE 'PRECONDITION CHECK (Tenant-scoped %): Active May=% (expected 71), Active June=% (expected 59), Total BBVA=% (expected 130)', 
        v_org_id, v_cnt_may_debit, v_cnt_june_debit, v_cnt_total_bbva;

    IF v_cnt_may_debit != 71 OR v_cnt_june_debit != 59 OR v_cnt_total_bbva != 130 THEN
        RAISE EXCEPTION 'PRECONDITION FAILED: Pre-recovery active BBVA movement counts do not match expected baseline (May=71, June=59, Total=130). Aborting.';
    END IF;

    -- Fetch source file IDs (tenant-scoped)
    SELECT id INTO v_may_file_id 
    FROM public.eco_source_files WHERE organization_id = v_org_id AND import_id = '881859f6-127e-4a4e-85e6-83e69a3aee00' LIMIT 1;

    SELECT id INTO v_june_file_id 
    FROM public.eco_source_files WHERE organization_id = v_org_id AND import_id = 'a1ea483b-e203-49af-9948-e124828ed3ea' LIMIT 1;

    -- 3. Create NEW Recovery Import Attempts for May and June
    v_may_recovery_import_id := extensions.gen_random_uuid();
    v_june_recovery_import_id := extensions.gen_random_uuid();

    INSERT INTO public.eco_source_imports (
        id, organization_id, retry_of_import_id, status, source_type, operation_type,
        total_rows, accepted_rows, invalid_rows, duplicate_rows, created_at, created_by, completed_at
    ) VALUES (
        v_may_recovery_import_id, v_org_id, v_may_retry_id, 'COMPLETED', 'BANK_STATEMENT_BBVA', 'BANCO',
        9, 9, 0, 0, NOW(), v_user_profile_id, NOW()
    );

    INSERT INTO public.eco_source_imports (
        id, organization_id, retry_of_import_id, status, source_type, operation_type,
        total_rows, accepted_rows, invalid_rows, duplicate_rows, created_at, created_by, completed_at
    ) VALUES (
        v_june_recovery_import_id, v_org_id, v_june_retry_id, 'COMPLETED', 'BANK_STATEMENT_BBVA', 'BANCO',
        15, 15, 0, 0, NOW(), v_user_profile_id, NOW()
    );

    -- 4. Recovery of the 9 May 2026 Credit Movements
    FOR v_r IN SELECT * FROM (VALUES
        (39, '2026-05-21'::date, '2026-05-21'::date, 'TRANSF.BANEL 30715507419', 'CTE 30715507419 136 733 - N/A', 347000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-21", "CTE 30715507419 136 733 - N/A", 347000.00, "credit"]'),
        (40, '2026-05-21'::date, '2026-05-21'::date, 'DEPOS.CHQ.48 C.F.U.13340600', 'CTE 000013385554 082 133 - PARQUE INDUSTRIAL PILAR', 970000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-21", "CTE 000013385554 082 133 - PARQUE INDUSTRIAL PILAR", 970000.00, "credit"]'),
        (42, '2026-05-20'::date, '2026-05-20'::date, 'DNET CREDITO NE4023944', 'CTE 023944          - 983 587 - DATANET', 1300000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-20", "CTE 023944          - 983 587 - DATANET", 1300000.00, "credit"]'),
        (49, '2026-05-18'::date, '2026-05-18'::date, 'DEPOS.CHQ.48 CFU. E13384094', 'CTE 000013384094 082 133 - PARQUE INDUSTRIAL PILAR', 1033107.25, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-18", "CTE 000013384094 082 133 - PARQUE INDUSTRIAL PILAR", 1033107.25, "credit"]'),
        (51, '2026-05-15'::date, '2026-05-15'::date, 'DNET CREDITO NE4085090', 'CTE 085090       072-00000946135        JOB TRAINING SRL 983 587 - DATANET', 60000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-15", "CTE 085090       072-00000946135        JOB TRAINING SRL 983 587 - DATANET", 60000.00, "credit"]'),
        (62, '2026-05-13'::date, '2026-05-13'::date, 'LR-ACREDITAC 01332300710669', '902 133 - PARQUE INDUSTRIAL PILAR', 222882.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-13", "902 133 - PARQUE INDUSTRIAL PILAR", 222882.00, "credit"]'),
        (63, '2026-05-13'::date, '2026-05-13'::date, 'TRANSF.BANEL 30689920779', 'CTE 30689920779 136 733 - N/A', 200000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-13", "CTE 30689920779 136 733 - N/A", 200000.00, "credit"]'),
        (64, '2026-05-13'::date, '2026-05-13'::date, 'TRF  IN COEL 20417272608', 'CTE 000011110008 129 100 - BANCA ONLINE', 300000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-13", "CTE 000011110008 129 100 - BANCA ONLINE", 300000.00, "credit"]'),
        (72, '2026-05-11'::date, '2026-05-11'::date, 'DNET CREDITO NE4071651', 'CTE 071651       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET', 42900.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-05-11", "CTE 071651       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET", 42900.00, "credit"]')
    ) AS t(src_row, fecha, fecha_valor, descr, ref, monto, tipo, saldo, ident_key)
    LOOP
        v_identity_key := v_r.ident_key;
        
        -- Tenant-scoped Deduplication Check
        SELECT id INTO v_existing_id 
        FROM public.eco_financial_movements 
        WHERE organization_id = v_org_id AND identity_key = v_identity_key AND deleted_at IS NULL LIMIT 1;

        IF v_existing_id IS NULL THEN
            v_fingerprint := ENCODE(extensions.digest(v_r.descr || '|' || TO_CHAR(v_r.fecha_valor, 'YYYY-MM-DD'), 'sha256'), 'hex');

            INSERT INTO public.eco_import_rows (file_id, organization_id, source_row_number, raw_payload, parse_status)
            VALUES (v_may_file_id, v_org_id, v_r.src_row, jsonb_build_array(TO_CHAR(v_r.fecha, 'DD-MM-YYYY'), TO_CHAR(v_r.fecha_valor, 'DD-MM-YYYY'), v_r.descr, '', '', '', v_r.monto::text, '', v_r.ref, ''), 'ACCEPTED')
            RETURNING id INTO v_row_id;

            INSERT INTO public.eco_financial_movements (
                organization_id, import_id, row_id, operation_type, source_type,
                fecha, fecha_valor, descripcion, referencia, monto, movement_type,
                saldo, identity_key, financial_fingerprint, normalized_payload, created_by
            ) VALUES (
                v_org_id, v_may_recovery_import_id, v_row_id, 'BANCO', 'BANK_STATEMENT_BBVA',
                v_r.fecha, v_r.fecha_valor, v_r.descr, v_r.ref, v_r.monto, v_r.tipo,
                v_r.saldo, v_identity_key, v_fingerprint,
                jsonb_build_object('fecha', TO_CHAR(v_r.fecha, 'DD-MM-YYYY'), 'fechaValor', TO_CHAR(v_r.fecha_valor, 'DD-MM-YYYY'), 'descripcion', v_r.descr, 'referencia', v_r.ref, 'monto', v_r.monto, 'tipo', v_r.tipo),
                v_user_profile_id
            );

            v_inserted_may := v_inserted_may + 1;
        END IF;
    END LOOP;

    -- 5. Recovery of the 15 June 2026 Credit Movements
    FOR v_r IN SELECT * FROM (VALUES
        (17, '2026-06-30'::date, '2026-06-30'::date, 'DNET CREDITO NE7269730', 'CTE 269730          - 983 587 - DATANET', 2385085.50, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-30", "CTE 269730          - 983 587 - DATANET", 2385085.50, "credit"]'),
        (20, '2026-06-29'::date, '2026-06-29'::date, 'DEPOSITO AUT BUZON/02/14:12', 'CTE 000008364002 341 357 - ALVAREZ TOMAS', 740000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-29", "CTE 000008364002 341 357 - ALVAREZ TOMAS", 740000.00, "credit"]'),
        (21, '2026-06-29'::date, '2026-06-29'::date, 'DEPOSITO BAN SIN TARJ OP1155', '452 357 - ALVAREZ TOMAS', 20000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-29", "452 357 - ALVAREZ TOMAS", 20000.00, "credit"]'),
        (22, '2026-06-29'::date, '2026-06-29'::date, 'DNET CREDITO NE4196020', 'CTE 196020       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET', 46100.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-29", "CTE 196020       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET", 46100.00, "credit"]'),
        (33, '2026-06-25'::date, '2026-06-25'::date, 'DNET CREDITO NE4212550', 'CTE 212550       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET', 46100.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-25", "CTE 212550       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET", 46100.00, "credit"]'),
        (37, '2026-06-23'::date, '2026-06-23'::date, 'DNET CREDITO NE4226160', 'CTE 226160       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET', 45000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-23", "CTE 226160       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET", 45000.00, "credit"]'),
        (47, '2026-06-18'::date, '2026-06-18'::date, 'DEPOSITO AUT BUZON/02/16:21', 'CTE 000008359002 341 357 - ALVAREZ TOMAS', 420000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-18", "CTE 000008359002 341 357 - ALVAREZ TOMAS", 420000.00, "credit"]'),
        (51, '2026-06-16'::date, '2026-06-16'::date, 'DNET CREDITO NE4238710', 'CTE 238710       072-00000946135        JOB TRAINING SRL 983 587 - DATANET', 60000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-16", "CTE 238710       072-00000946135        JOB TRAINING SRL 983 587 - DATANET", 60000.00, "credit"]'),
        (53, '2026-06-12'::date, '2026-06-12'::date, 'DEPOS.CHQ.48 CFU. E13384915', 'CTE 000013384915 082 133 - PARQUE INDUSTRIAL PILAR', 416568.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-12", "CTE 000013384915 082 133 - PARQUE INDUSTRIAL PILAR", 416568.00, "credit"]'),
        (59, '2026-06-10'::date, '2026-06-10'::date, 'DNET CREDITO NE4248550', 'CTE 248550       072-00000946135        JOB TRAINING SRL 983 587 - DATANET', 60000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-10", "CTE 248550       072-00000946135        JOB TRAINING SRL 983 587 - DATANET", 60000.00, "credit"]'),
        (65, '2026-06-08'::date, '2026-06-08'::date, 'DNET CREDITO NE4254240', 'CTE 254240       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET', 45000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-08", "CTE 254240       072-00000946135        CLUB DE CAMPO SA 983 587 - DATANET", 45000.00, "credit"]'),
        (72, '2026-06-03'::date, '2026-06-03'::date, 'DNET CREDITO NE7267139', 'CTE 267139          - 983 587 - DATANET', 2000000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-03", "CTE 267139          - 983 587 - DATANET", 2000000.00, "credit"]'),
        (73, '2026-06-03'::date, '2026-06-03'::date, 'TRF  IN COEL 20417272608', 'CTE 000011110008 129 100 - BANCA ONLINE', 500000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-03", "CTE 000011110008 129 100 - BANCA ONLINE", 500000.00, "credit"]'),
        (76, '2026-06-02'::date, '2026-06-02'::date, 'DEPOS.CHQ.48 C.F.U.13340600', 'CTE 000013385554 082 133 - PARQUE INDUSTRIAL PILAR', 970000.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-02", "CTE 000013385554 082 133 - PARQUE INDUSTRIAL PILAR", 970000.00, "credit"]'),
        (84, '2026-06-01'::date, '2026-06-01'::date, 'DNET CREDITO NE4260980', 'CTE 260980          - 983 587 - DATANET', 171400.00, 'credit', NULL::numeric, '["BANK_STATEMENT_BBVA", "", "2026-06-01", "CTE 260980          - 983 587 - DATANET", 171400.00, "credit"]')
    ) AS t(src_row, fecha, fecha_valor, descr, ref, monto, tipo, saldo, ident_key)
    LOOP
        v_identity_key := v_r.ident_key;
        
        -- Tenant-scoped Deduplication Check
        SELECT id INTO v_existing_id 
        FROM public.eco_financial_movements 
        WHERE organization_id = v_org_id AND identity_key = v_identity_key AND deleted_at IS NULL LIMIT 1;

        IF v_existing_id IS NULL THEN
            v_fingerprint := ENCODE(extensions.digest(v_r.descr || '|' || TO_CHAR(v_r.fecha_valor, 'YYYY-MM-DD'), 'sha256'), 'hex');

            INSERT INTO public.eco_import_rows (file_id, organization_id, source_row_number, raw_payload, parse_status)
            VALUES (v_june_file_id, v_org_id, v_r.src_row, jsonb_build_array(TO_CHAR(v_r.fecha, 'DD-MM-YYYY'), TO_CHAR(v_r.fecha_valor, 'DD-MM-YYYY'), v_r.descr, '', '', '', v_r.monto::text, '', v_r.ref, ''), 'ACCEPTED')
            RETURNING id INTO v_row_id;

            INSERT INTO public.eco_financial_movements (
                organization_id, import_id, row_id, operation_type, source_type,
                fecha, fecha_valor, descripcion, referencia, monto, movement_type,
                saldo, identity_key, financial_fingerprint, normalized_payload, created_by
            ) VALUES (
                v_org_id, v_june_recovery_import_id, v_row_id, 'BANCO', 'BANK_STATEMENT_BBVA',
                v_r.fecha, v_r.fecha_valor, v_r.descr, v_r.ref, v_r.monto, v_r.tipo,
                v_r.saldo, v_identity_key, v_fingerprint,
                jsonb_build_object('fecha', TO_CHAR(v_r.fecha, 'DD-MM-YYYY'), 'fechaValor', TO_CHAR(v_r.fecha_valor, 'DD-MM-YYYY'), 'descripcion', v_r.descr, 'referencia', v_r.ref, 'monto', v_r.monto, 'tipo', v_r.tipo),
                v_user_profile_id
            );

            v_inserted_june := v_inserted_june + 1;
        END IF;
    END LOOP;

    -- 6. Final Assertions Verification (Tenant-Scoped)
    SELECT count(*) INTO v_final_may 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND fecha >= '2026-05-01' AND fecha <= '2026-05-31' AND deleted_at IS NULL;

    SELECT count(*) INTO v_final_june 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND fecha >= '2026-06-01' AND fecha <= '2026-06-30' AND deleted_at IS NULL;

    SELECT count(*) INTO v_final_total 
    FROM public.eco_financial_movements 
    WHERE organization_id = v_org_id AND source_type = 'BANK_STATEMENT_BBVA' AND deleted_at IS NULL;

    RAISE NOTICE 'POST-RECOVERY ASSERTION: Inserted May=%, Inserted June=%. Final May=% (expected 80), Final June=% (expected 74), Final Total=% (expected 154)',
        v_inserted_may, v_inserted_june, v_final_may, v_final_june, v_final_total;

    IF v_final_may != 80 OR v_final_june != 74 OR v_final_total != 154 THEN
        RAISE EXCEPTION 'POST-RECOVERY ASSERTION FAILED: Final counts (May=%, June=%, Total=%) do not match required contract (80/74/154). Aborting transaction.',
            v_final_may, v_final_june, v_final_total;
    END IF;

    -- Audit Event (Tenant-Scoped)
    INSERT INTO public.eco_audit_events (organization_id, event_type)
    VALUES (v_org_id, 'ONE_OFF_BBVA_CREDIT_RECOVERY_COMPLETED');

END;
$$;

COMMIT;
