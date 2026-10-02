-- ============================================================
-- POSTCHECK FOR MIGRATION 021 (WP-A3.2.0)
-- ============================================================
-- Verifies indexes, function signatures, attributes, and permissions.
-- ============================================================

DO $$
DECLARE
    v_missing_indexes TEXT[] := ARRAY[]::TEXT[];
    v_idx_name TEXT;
    v_fn_found BOOLEAN;
    v_fn_volatility CHAR;
    v_fn_secdef BOOLEAN;
    v_fn_search_path TEXT;
BEGIN
    RAISE NOTICE 'Starting Migration 021 Postcheck Validation...';

    -- 1. Check covering indexes
    FOREACH v_idx_name IN ARRAY ARRAY[
        'idx_eco_org_members_covering',
        'idx_eco_user_platform_role_covering'
    ]
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes 
            WHERE schemaname = 'public' AND indexname = v_idx_name
        ) THEN
            v_missing_indexes := array_append(v_missing_indexes, v_idx_name);
        END IF;
    END LOOP;

    IF array_length(v_missing_indexes, 1) > 0 THEN
        RAISE EXCEPTION 'Postcheck FAILED: Expected indexes missing: %', array_to_string(v_missing_indexes, ', ');
    END IF;

    -- 2. Verify private.authorized_orgs_for_capability attributes
    SELECT 
        TRUE, p.provolatile, p.prosecdef,
        coalesce((SELECT array_to_string(p.proconfig, ', ') FROM pg_proc WHERE oid = p.oid), '')
    INTO v_fn_found, v_fn_volatility, v_fn_secdef, v_fn_search_path
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'private' AND p.proname = 'authorized_orgs_for_capability';

    IF v_fn_found IS NULL OR NOT v_fn_found THEN
        RAISE EXCEPTION 'Postcheck FAILED: private.authorized_orgs_for_capability function not found.';
    END IF;

    IF v_fn_volatility <> 's' THEN
        RAISE EXCEPTION 'Postcheck FAILED: authorized_orgs_for_capability is not STABLE (provolatile: %)', v_fn_volatility;
    END IF;

    IF NOT v_fn_secdef THEN
        RAISE EXCEPTION 'Postcheck FAILED: authorized_orgs_for_capability is not SECURITY DEFINER.';
    END IF;

    IF v_fn_search_path NOT LIKE '%search_path=%' THEN
        RAISE EXCEPTION 'Postcheck FAILED: authorized_orgs_for_capability search_path is not explicitly configured.';
    END IF;

    RAISE NOTICE 'Migration 021 Postcheck Passed: All indexes and functions verified.';
END $$;
