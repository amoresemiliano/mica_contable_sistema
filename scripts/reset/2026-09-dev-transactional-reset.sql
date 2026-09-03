-- ONE-OFF DEV TRANSACTIONAL DATA RESET SCRIPT
-- Target: Erase ALL transactional and import data for the DEV organization (59436df3-9f15-4f5e-b17e-37c55482521c)
-- Goal: Clean slate allowing complete re-import of all source files from scratch.
-- Safety: Hardcoded DEV Organization Guard. Fails fast if run against any other organization or PROD.
-- Execution Mode: Ephemeral / Manual (REQUIRES HUMAN GATE APPROVAL PRIOR TO LIVE DEV EXECUTION).

BEGIN;

DO $$
DECLARE
    v_target_org_id CONSTANT UUID := '59436df3-9f15-4f5e-b17e-37c55482521c'::uuid;
    v_current_org_id UUID;
    
    -- Pre-reset counts
    v_pre_movements INT;
    v_pre_records INT;
    v_pre_rows INT;
    v_pre_issues INT;
    v_pre_files INT;
    v_pre_imports INT;
    v_pre_allocations INT;
    v_pre_review_actions INT;
    
    -- Config pre-counts (must be preserved)
    v_cfg_tax_cats INT;
    v_cfg_activities INT;
    v_cfg_iibb_rates INT;
    v_cfg_profiles INT;
    
    -- Post-reset counts
    v_post_movements INT;
    v_post_records INT;
    v_post_rows INT;
    v_post_issues INT;
    v_post_files INT;
    v_post_imports INT;
    v_post_allocations INT;
    v_post_review_actions INT;
    
    -- Post-config counts
    v_post_tax_cats INT;
    v_post_activities INT;
    v_post_iibb_rates INT;
    v_post_profiles INT;
BEGIN
    -- 1. DEV Organization Guard & Execution Safety
    v_current_org_id := private.org_id();
    IF v_current_org_id IS NULL THEN
        -- Allow fallback resolution only if target org exists in DB
        SELECT id INTO v_current_org_id FROM public.eco_organizations WHERE id = v_target_org_id;
    END IF;

    IF v_current_org_id IS NULL OR v_current_org_id != v_target_org_id THEN
        RAISE EXCEPTION 'RESET ABORTED: Target organization guard failed. Expected %, got %. Execution prohibited.', v_target_org_id, v_current_org_id;
    END IF;

    RAISE NOTICE 'DEV TRANSACTIONAL RESET STARTED FOR TENANT %', v_current_org_id;

    -- 2. Capture PRE-RESET Counts
    SELECT count(*) INTO v_pre_review_actions FROM public.eco_review_actions WHERE issue_id IN (SELECT id FROM public.eco_import_issues WHERE organization_id = v_current_org_id);
    SELECT count(*) INTO v_pre_allocations FROM public.eco_movement_allocations WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_movements FROM public.eco_financial_movements WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_issues FROM public.eco_import_issues WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_records FROM public.eco_normalized_records WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_rows FROM public.eco_import_rows WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_files FROM public.eco_source_files WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_pre_imports FROM public.eco_source_imports WHERE organization_id = v_current_org_id;

    -- Capture PRE-RESET Configuration Counts
    SELECT count(*) INTO v_cfg_tax_cats FROM public.eco_org_tax_categories WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_cfg_activities FROM public.eco_org_economic_activities WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_cfg_iibb_rates FROM public.eco_org_activity_iibb_rates WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_cfg_profiles FROM public.eco_user_profiles WHERE organization_id = v_current_org_id;

    RAISE NOTICE 'PRE-RESET TRANSACTIONAL COUNTS: Movements=%, Records=%, Rows=%, Issues=%, Files=%, Imports=%, Allocations=%, ReviewActions=%',
        v_pre_movements, v_pre_records, v_pre_rows, v_pre_issues, v_pre_files, v_pre_imports, v_pre_allocations, v_pre_review_actions;

    -- 3. Perform Physical Deletes in FK Dependency Order (Child First)

    -- A. Review actions (linked to import issues)
    DELETE FROM public.eco_review_actions 
    WHERE issue_id IN (SELECT id FROM public.eco_import_issues WHERE organization_id = v_current_org_id);

    -- B. Movement allocations
    DELETE FROM public.eco_movement_allocations 
    WHERE organization_id = v_current_org_id;

    -- C. Financial movements (extractos bancarios + sueldos)
    DELETE FROM public.eco_financial_movements 
    WHERE organization_id = v_current_org_id;

    -- D. Import issues
    DELETE FROM public.eco_import_issues 
    WHERE organization_id = v_current_org_id;

    -- E. Normalized records (comprobantes ARCA + percepciones)
    DELETE FROM public.eco_normalized_records 
    WHERE organization_id = v_current_org_id;

    -- F. Import rows
    DELETE FROM public.eco_import_rows 
    WHERE organization_id = v_current_org_id;

    -- G. Source files DB metadata
    DELETE FROM public.eco_source_files 
    WHERE organization_id = v_current_org_id;

    -- H. Break self-referencing FK retry_of_import_id in eco_source_imports before deleting
    UPDATE public.eco_source_imports 
    SET retry_of_import_id = NULL 
    WHERE organization_id = v_current_org_id;

    -- I. Source imports
    DELETE FROM public.eco_source_imports 
    WHERE organization_id = v_current_org_id;

    -- 4. Verify POST-RESET Transactional Counts (MUST ALL BE 0)
    SELECT count(*) INTO v_post_review_actions FROM public.eco_review_actions WHERE issue_id IN (SELECT id FROM public.eco_import_issues WHERE organization_id = v_current_org_id);
    SELECT count(*) INTO v_post_allocations FROM public.eco_movement_allocations WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_movements FROM public.eco_financial_movements WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_issues FROM public.eco_import_issues WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_records FROM public.eco_normalized_records WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_rows FROM public.eco_import_rows WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_files FROM public.eco_source_files WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_imports FROM public.eco_source_imports WHERE organization_id = v_current_org_id;

    IF v_post_movements != 0 OR v_post_records != 0 OR v_post_rows != 0 OR v_post_issues != 0 
       OR v_post_files != 0 OR v_post_imports != 0 OR v_post_allocations != 0 OR v_post_review_actions != 0 THEN
        RAISE EXCEPTION 'RESET ASSERTION FAILED: Transactional tables not completely cleared. Movements=%, Records=%, Rows=%, Issues=%, Files=%, Imports=%',
            v_post_movements, v_post_records, v_post_rows, v_post_issues, v_post_files, v_post_imports;
    END IF;

    -- 5. Verify Configuration Counts (MUST REMAIN 100% UNCHANGED)
    SELECT count(*) INTO v_post_tax_cats FROM public.eco_org_tax_categories WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_activities FROM public.eco_org_economic_activities WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_iibb_rates FROM public.eco_org_activity_iibb_rates WHERE organization_id = v_current_org_id;
    SELECT count(*) INTO v_post_profiles FROM public.eco_user_profiles WHERE organization_id = v_current_org_id;

    IF v_post_tax_cats != v_cfg_tax_cats OR v_post_activities != v_cfg_activities 
       OR v_post_iibb_rates != v_cfg_iibb_rates OR v_post_profiles != v_cfg_profiles THEN
        RAISE EXCEPTION 'RESET ASSERTION FAILED: Configuration tables were altered during reset! Aborting.';
    END IF;

    RAISE NOTICE 'DEV TRANSACTIONAL RESET SUCCESSFUL FOR TENANT %. ALL TRANSACTIONAL DATA CLEARED. CONFIG PRESERVED.', v_current_org_id;

END;
$$;

COMMIT;
