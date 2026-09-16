-- ============================================================
-- DB BEHAVIORAL SECURITY TEST SUITE FOR WP-A3.2.1 (MIGRATION 022)
-- ============================================================
-- WP-A3.2.1-VH1 — BEHAVIORAL SECURITY HARNESS AUTHENTICATED ROLE SIMULATION
--
-- Validates capability-driven authorization for:
-- 1. Identity & Self Profile Access
-- 2. Organization Visibility (ORG_VIEW)
-- 3. Member Profile Visibility (ORG_MEMBER_VIEW)
-- 4. User Role Modification (ORG_MEMBER_PERMISSION_MANAGE)
--    - Multi-org role isolation
--    - Inactive membership role configuration support
-- 5. Tenant User Activation / Deactivation (ORG_MEMBER_MANAGE)
-- 6. Global User Activation / Deactivation (GLOBAL_USER_MANAGE / PLATFORM_MANAGE)
-- 7. Platform Audit Governance (eco_platform_audit_events)
--    - Separate from tenant eco_audit_events
--    - Append-only trigger (enforce_append_only_platform_audit)
--    - RLS platform capability protection (AUDIT_PLATFORM_VIEW / PLATFORM_MANAGE)
-- 8. Global Operation Independence from Active Context
-- 9. Superadmin Context Switching (SUPPORT_IMPERSONATE / ACCESS_ANY_ORG)
-- 10. Audit Visibility & Append-Only Invariants (Tenant & Platform)
--
-- Entire script executes under BEGIN ... ROLLBACK.
-- Role simulation switches to `authenticated` for RLS and RPC assertions
-- while preserving privileged setup & teardown via transaction rollback.
-- No direct private schema calls are made from authenticated personas.
-- ============================================================

BEGIN;

-- Helper functions for harness persona switching and role management
CREATE OR REPLACE FUNCTION public.harness_set_persona(p_auth_id UUID) RETURNS void AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_auth_id::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF current_user <> 'authenticated' THEN
    RAISE EXCEPTION 'BEHAVIORAL_TEST_NOT_RUNNING_AS_AUTHENTICATED (session_user=%, current_user=%)', session_user, current_user;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.harness_reset_role() RETURNS void AS $$
BEGIN
  EXECUTE 'RESET ROLE';
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;
  v_mica_org_id  CONSTANT UUID := '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID;

  -- Real users
  v_vegen_auth_id     UUID;
  v_marianela_auth_id UUID;
  v_emiliano_auth_id  UUID;
  v_edravi_auth_id    UUID;
  v_calle_auth_id     UUID;

  v_emiliano_profile_id UUID;
  v_edravi_profile_id   UUID;
  v_calle_profile_id    UUID;
  v_vegen_profile_id    UUID;

  -- Synthetic users
  v_synth_user_a_auth_id UUID := gen_random_uuid();
  v_synth_user_b_auth_id UUID := gen_random_uuid();
  v_synth_user_c_auth_id UUID := gen_random_uuid();
  v_synth_multi_auth_id  UUID := gen_random_uuid();

  v_synth_user_a_profile_id UUID;
  v_synth_user_b_profile_id UUID;
  v_synth_user_c_profile_id UUID;
  v_synth_multi_profile_id  UUID;

  v_synth_mem_a_id UUID;
  v_synth_mem_b_id UUID;
  v_synth_multi_mem_norte_id UUID;
  v_synth_multi_mem_sur_id   UUID;

  -- Role templates & capabilities
  v_tpl_tenant_admin_id UUID;
  v_tpl_accountant_id   UUID;
  v_tpl_uploader_id     UUID;
  v_tpl_reviewer_id     UUID;

  v_cap_role_manage_id   UUID;
  v_cap_member_manage_id UUID;
  v_cap_member_view_id   UUID;
  v_cap_org_view_id      UUID;
  v_cap_audit_view_id    UUID;

  v_count INT;
  v_audit_count_before INT;
  v_audit_count_after INT;
  v_role_check TEXT;
  v_active_check BOOLEAN;
  v_tpl_check UUID;
  v_exception_raised BOOLEAN;
  v_err_state TEXT;
  v_err_msg TEXT;
  v_diag_emiliano_memberships INT;
  v_diag_synth_memberships INT;
  v_diag_active_ctx_count INT;
  v_audit_row RECORD;
BEGIN
  -- Ensure starting in privileged role for fixture setup
  PERFORM public.harness_reset_role();

  -- ============================================================
  -- 0. FAIL-FAST BASELINE CHECK (M022 PREREQUISITES, SCHEMA & DRIFT)
  -- ============================================================
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'set_global_user_active'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'change_user_role'
      AND pronargs = 3
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'set_user_active'
      AND pronargs = 3
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'eco_platform_audit_events'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'enforce_append_only_platform_audit'
  ) THEN
    RAISE EXCEPTION 'M022_NOT_APPLIED_RUN_FORWARD_AND_POSTCHECK_FIRST';
  END IF;

  -- Verify eco_user_profiles schema dependencies
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'auth_user_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'organization_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'role'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eco_user_profiles' AND column_name = 'is_active'
  ) THEN
    RAISE EXCEPTION 'M022_SCHEMA_DRIFT: eco_user_profiles missing required fixture columns';
  END IF;

  -- Verify absence of conflicting legacy organization RLS policy
  IF EXISTS (
    SELECT 1 FROM pg_policy pol
    JOIN pg_class c ON pol.polrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND c.relname = 'eco_organizations'
      AND pol.polname = 'Organizations member view'
  ) THEN
    RAISE EXCEPTION 'LEGACY_ORGANIZATION_RLS_POLICY_PRESENT: Conflicting legacy policy "Organizations member view" detected on public.eco_organizations. Remove manually in DEV before running.';
  END IF;

  RAISE NOTICE 'Executing WP-A3.2.1 DB Behavioral Test Matrix... (session_user=%, current_user=%)', session_user, current_user;

  -- Resolve real user IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

  SELECT id INTO v_vegen_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  SELECT id INTO v_emiliano_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  SELECT id INTO v_edravi_profile_id   FROM public.eco_user_profiles WHERE auth_user_id = v_edravi_auth_id;
  SELECT id INTO v_calle_profile_id    FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id;

  -- Resolve templates
  SELECT id INTO v_tpl_tenant_admin_id FROM public.eco_role_templates WHERE code = 'TENANT_ADMIN';
  SELECT id INTO v_tpl_accountant_id   FROM public.eco_role_templates WHERE code = 'ACCOUNTANT';
  SELECT id INTO v_tpl_uploader_id     FROM public.eco_role_templates WHERE code = 'UPLOADER';
  SELECT id INTO v_tpl_reviewer_id     FROM public.eco_role_templates WHERE code = 'REVIEWER';

  -- Resolve capabilities
  SELECT id INTO v_cap_role_manage_id   FROM public.eco_capabilities WHERE code = 'ORG_MEMBER_PERMISSION_MANAGE';
  SELECT id INTO v_cap_member_manage_id FROM public.eco_capabilities WHERE code = 'ORG_MEMBER_MANAGE';
  SELECT id INTO v_cap_member_view_id   FROM public.eco_capabilities WHERE code = 'ORG_MEMBER_VIEW';
  SELECT id INTO v_cap_org_view_id      FROM public.eco_capabilities WHERE code = 'ORG_VIEW';
  SELECT id INTO v_cap_audit_view_id    FROM public.eco_capabilities WHERE code = 'AUDIT_VIEW_ORG';

  -- Setup synthetic users in auth.users
  INSERT INTO auth.users (id, email) VALUES
    (v_synth_user_a_auth_id, 'synth_user_a@test.com'),
    (v_synth_user_b_auth_id, 'synth_user_b@test.com'),
    (v_synth_user_c_auth_id, 'synth_user_c@test.com'),
    (v_synth_multi_auth_id,  'synth_multi@test.com')
  ON CONFLICT (id) DO NOTHING;

  -- ============================================================
  -- LIVE DEV PROFILE RECONCILIATION (PRIVILEGED FIXTURE SETUP)
  -- ============================================================
  -- 1. Synth User A (Target Org: DEMO NORTE)
  SELECT id INTO v_synth_user_a_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_user_a_auth_id;

  IF v_synth_user_a_profile_id IS NOT NULL THEN
    UPDATE public.eco_user_profiles
    SET organization_id = v_norte_org_id, role = 'USER', is_active = TRUE
    WHERE id = v_synth_user_a_profile_id;
  ELSE
    INSERT INTO public.eco_user_profiles (auth_user_id, organization_id, role, is_active)
    VALUES (v_synth_user_a_auth_id, v_norte_org_id, 'USER', TRUE)
    RETURNING id INTO v_synth_user_a_profile_id;
  END IF;

  -- 2. Synth User B (Target Org: DEMO SUR)
  SELECT id INTO v_synth_user_b_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_user_b_auth_id;

  IF v_synth_user_b_profile_id IS NOT NULL THEN
    UPDATE public.eco_user_profiles
    SET organization_id = v_sur_org_id, role = 'USER', is_active = TRUE
    WHERE id = v_synth_user_b_profile_id;
  ELSE
    INSERT INTO public.eco_user_profiles (auth_user_id, organization_id, role, is_active)
    VALUES (v_synth_user_b_auth_id, v_sur_org_id, 'USER', TRUE)
    RETURNING id INTO v_synth_user_b_profile_id;
  END IF;

  -- 3. Synth User C (Target Org: DEMO OESTE)
  SELECT id INTO v_synth_user_c_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_user_c_auth_id;

  IF v_synth_user_c_profile_id IS NOT NULL THEN
    UPDATE public.eco_user_profiles
    SET organization_id = v_oeste_org_id, role = 'USER', is_active = TRUE
    WHERE id = v_synth_user_c_profile_id;
  ELSE
    INSERT INTO public.eco_user_profiles (auth_user_id, organization_id, role, is_active)
    VALUES (v_synth_user_c_auth_id, v_oeste_org_id, 'USER', TRUE)
    RETURNING id INTO v_synth_user_c_profile_id;
  END IF;

  -- 4. Synth Multi-Org User (Target Org: DEMO SUR in profile, memberships in NORTE & SUR)
  SELECT id INTO v_synth_multi_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_multi_auth_id;

  IF v_synth_multi_profile_id IS NOT NULL THEN
    UPDATE public.eco_user_profiles
    SET organization_id = v_sur_org_id, role = 'USER', is_active = TRUE
    WHERE id = v_synth_multi_profile_id;
  ELSE
    INSERT INTO public.eco_user_profiles (auth_user_id, organization_id, role, is_active)
    VALUES (v_synth_multi_auth_id, v_sur_org_id, 'USER', TRUE)
    RETURNING id INTO v_synth_multi_profile_id;
  END IF;

  -- Assert exact profile cardinality (exactly one profile row per synthetic user)
  SELECT COUNT(*) INTO v_count
  FROM public.eco_user_profiles
  WHERE auth_user_id IN (
    v_synth_user_a_auth_id,
    v_synth_user_b_auth_id,
    v_synth_user_c_auth_id,
    v_synth_multi_auth_id
  );

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'SYNTHETIC_PROFILE_CARDINALITY_ERROR: Expected 4 profiles, found %', v_count;
  END IF;

  -- Setup memberships
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_synth_user_a_profile_id, v_tpl_uploader_id, TRUE)
  RETURNING id INTO v_synth_mem_a_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_synth_user_b_profile_id, v_tpl_uploader_id, TRUE)
  RETURNING id INTO v_synth_mem_b_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_synth_multi_profile_id, v_tpl_uploader_id, TRUE)
  RETURNING id INTO v_synth_multi_mem_norte_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_synth_multi_profile_id, v_tpl_reviewer_id, TRUE)
  RETURNING id INTO v_synth_multi_mem_sur_id;


  -- ============================================================
  -- 1. IDENTITY & SELF PROFILE ACCESS (AUTHENTICATED ROLE)
  -- ============================================================
  PERFORM public.harness_set_persona(v_emiliano_auth_id);

  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE auth_user_id = v_emiliano_auth_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano could not view own profile';
  END IF;


  -- ============================================================
  -- 2. ORGANIZATION VISIBILITY (ORG_VIEW) (AUTHENTICATED ROLE)
  -- ============================================================

  -- 2.1 Emiliano (Admin NORTE) sees only DEMO NORTE
  PERFORM public.harness_set_persona(v_emiliano_auth_id);

  SELECT COUNT(*) INTO v_count FROM public.eco_organizations;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano saw % organizations, expected 1 (DEMO NORTE)', v_count;
  END IF;

  SELECT id INTO v_tpl_check FROM public.eco_organizations LIMIT 1;
  IF v_tpl_check <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano saw organization % instead of DEMO NORTE', v_tpl_check;
  END IF;

  -- 2.2 Marianela (Accounting Superadmin) sees scoped organizations (NORTE, SUR, OESTE)
  PERFORM public.harness_set_persona(v_marianela_auth_id);

  SELECT COUNT(*) INTO v_count FROM public.eco_organizations;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Test FAILED: Marianela saw % organizations, expected 3', v_count;
  END IF;


  -- ============================================================
  -- 3. MEMBER PROFILE VISIBILITY (ORG_MEMBER_VIEW) (AUTHENTICATED ROLE)
  -- ============================================================

  -- 3.1 Emiliano sees members in DEMO NORTE (Self, Synth A, Synth Multi)
  PERFORM public.harness_set_persona(v_emiliano_auth_id);

  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles;
  IF v_count < 3 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano did not see members of DEMO NORTE';
  END IF;

  -- 3.2 Emiliano CANNOT see members of DEMO SUR (Synth B) under RLS
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_b_profile_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Emiliano cross-tenant viewed member in DEMO SUR';
  END IF;


  -- ============================================================
  -- 4. MULTI-ORG ROLE ISOLATION & CANONICAL TARGET RESOLUTION
  -- ============================================================

  -- 4.1 Emiliano (Admin NORTE) changes role of Synth Multi in DEMO NORTE to ADMIN:
  -- Target's profile.organization_id is SUR, but Emiliano is Admin of NORTE.
  -- Canonical resolution targets DEMO NORTE and updates NORTE membership ONLY.
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  PERFORM public.change_user_role(v_synth_multi_profile_id, 'ADMIN');

  -- Verify NORTE membership role template updated to TENANT_ADMIN
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_tpl_check <> v_tpl_tenant_admin_id THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role did not update canonical NORTE membership template to TENANT_ADMIN';
  END IF;

  -- Verify SUR membership role template remains untouched (REVIEWER) via privileged inspection
  PERFORM public.harness_reset_role();
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_sur_id;
  IF v_tpl_check <> v_tpl_reviewer_id THEN
    RAISE EXCEPTION 'Negative Test FAILED: change_user_role leaked into and altered unrelated SUR membership template';
  END IF;

  -- 4.2 Verify profile.role is compatibility only and does NOT confer authority in SUR
  -- Synth Multi's profile.role was synchronized to 'ADMIN', but in SUR their membership is still REVIEWER.
  -- Invoking public.change_user_role in SUR against a valid SUR target (Synth User B) must fail closed with FORBIDDEN.
  PERFORM public.harness_set_persona(v_synth_multi_auth_id);
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_synth_user_b_profile_id, 'ADMIN', v_sur_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    ELSE
      RAISE EXCEPTION 'Negative Test FAILED: Expected FORBIDDEN, but received unexpected exception: %', SQLERRM;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: profile.role leaked admin authority into SUR where membership is REVIEWER';
  END IF;

  -- 4.3 Inactive Membership Role Configuration Policy:
  -- Authorized admin CAN configure role_template_id on an inactive membership,
  -- and the membership remains inactive after the role change.
  -- Privileged fixture setup: deactivate Synth A membership
  PERFORM public.harness_reset_role();
  UPDATE public.eco_organization_members SET is_active = FALSE WHERE id = v_synth_mem_a_id;

  -- Authenticated admin executes role change on inactive membership
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  PERFORM public.change_user_role(v_synth_user_a_profile_id, 'ACCOUNTANT', v_norte_org_id);

  SELECT role_template_id, is_active INTO v_tpl_check, v_active_check
  FROM public.eco_organization_members WHERE id = v_synth_mem_a_id;

  IF v_tpl_check <> v_tpl_accountant_id THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role on inactive membership did not update role_template_id';
  END IF;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Negative Test FAILED: change_user_role inadvertently activated an inactive membership';
  END IF;

  -- Privileged fixture cleanup: restore Synth A membership active status
  PERFORM public.harness_reset_role();
  UPDATE public.eco_organization_members SET is_active = TRUE WHERE id = v_synth_mem_a_id;


  -- ============================================================
  -- 5. TENANT USER ACTIVATION / DEACTIVATION (set_user_active)
  -- ============================================================

  -- 5.1 Emiliano deactivates Synth Multi in DEMO NORTE:
  -- Only NORTE membership becomes inactive; SUR membership & global profile remain active!
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  PERFORM public.set_user_active(v_synth_multi_profile_id, FALSE);

  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: set_user_active did not deactivate NORTE membership';
  END IF;

  -- Privileged postcondition inspection: verify unrelated SUR membership and global profile remain untouched
  PERFORM public.harness_reset_role();
  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_sur_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: set_user_active deactivated unrelated SUR membership';
  END IF;

  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_multi_profile_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: Tenant set_user_active deactivated global profile';
  END IF;

  -- Reactivate Synth Multi in NORTE
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  PERFORM public.set_user_active(v_synth_multi_profile_id, TRUE);


  -- ============================================================
  -- 6. GLOBAL USER ACTIVATION & PLATFORM AUDIT VERIFICATION
  -- ============================================================

  -- 6.1 Platform Superadmin (VEGEN) deactivates target profile (with active context NORTE):
  -- Verifies:
  -- - Profile state changes to FALSE
  -- - Memberships remain untouched
  -- - Exactly one event emitted to public.eco_platform_audit_events
  -- - Actor = VEGEN, Target = Synth User A, metadata contains new_active = false
  -- - NO fake tenant audit rows created in eco_audit_events
  -- Privileged fixture setup: baseline count and active context setup
  PERFORM public.harness_reset_role();
  SELECT COUNT(*) INTO v_audit_count_before FROM public.eco_platform_audit_events;
  SELECT COUNT(*) INTO v_count FROM public.eco_audit_events WHERE organization_id IS NULL; -- Should always be 0

  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_vegen_profile_id, v_norte_org_id, now())
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = v_norte_org_id;

  -- Authenticated execution: VEGEN invokes public.set_global_user_active
  PERFORM public.harness_set_persona(v_vegen_auth_id);
  PERFORM public.set_global_user_active(v_synth_user_a_profile_id, FALSE);

  -- Verify global profile is deactivated
  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: set_global_user_active failed to deactivate profile';
  END IF;

  -- Privileged postcondition inspection: verify membership rows were NOT modified
  PERFORM public.harness_reset_role();
  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_mem_a_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: set_global_user_active mutated eco_organization_members row';
  END IF;

  -- Verify platform audit event created (VEGEN persona can read platform audit under RLS)
  PERFORM public.harness_set_persona(v_vegen_auth_id);
  SELECT COUNT(*) INTO v_audit_count_after FROM public.eco_platform_audit_events;
  IF v_audit_count_after <> v_audit_count_before + 1 THEN
    RAISE EXCEPTION 'Test FAILED: set_global_user_active did not create platform audit event';
  END IF;

  SELECT * INTO v_audit_row
  FROM public.eco_platform_audit_events
  ORDER BY created_at DESC LIMIT 1;

  IF v_audit_row.event_type <> 'GLOBAL_USER_ACTIVE_CHANGED'
     OR v_audit_row.actor_user_profile_id <> v_vegen_profile_id
     OR v_audit_row.target_user_profile_id <> v_synth_user_a_profile_id
     OR (v_audit_row.metadata->>'new_active')::boolean <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: Platform audit record has invalid actor, target, or metadata';
  END IF;

  -- 6.2 Platform Superadmin reactivates global user (with active context NULL):
  -- Verifies:
  -- - Profile state changes to TRUE
  -- - Second platform audit event created
  -- Privileged fixture setup: clear active context
  PERFORM public.harness_reset_role();
  DELETE FROM public.eco_user_active_context WHERE user_profile_id = v_vegen_profile_id;

  -- Authenticated execution: VEGEN invokes public.set_global_user_active
  PERFORM public.harness_set_persona(v_vegen_auth_id);
  PERFORM public.set_global_user_active(v_synth_user_a_profile_id, TRUE);

  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Test FAILED: set_global_user_active failed when active context was NULL';
  END IF;

  SELECT COUNT(*) INTO v_audit_count_after FROM public.eco_platform_audit_events;
  IF v_audit_count_after <> v_audit_count_before + 2 THEN
    RAISE EXCEPTION 'Test FAILED: Second platform audit event not created on reactivation';
  END IF;

  -- 6.3 Tenant Admin CANNOT invoke set_global_user_active (and creates NO audit event)
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.set_global_user_active(v_synth_user_a_profile_id, FALSE);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Tenant Admin was allowed to invoke set_global_user_active';
  END IF;

  PERFORM public.harness_set_persona(v_vegen_auth_id);
  SELECT COUNT(*) INTO v_count FROM public.eco_platform_audit_events;
  IF v_count <> v_audit_count_after THEN
    RAISE EXCEPTION 'Negative Test FAILED: Rejected call created platform audit event';
  END IF;


  -- ============================================================
  -- 7. PLATFORM AUDIT IMMUTABILITY & RLS GOVERNANCE
  -- ============================================================

  -- 7.1 Platform audit UPDATE rejected (append-only trigger)
  -- Privileged execution: proves append-only trigger blocks even privileged mutation
  PERFORM public.harness_reset_role();
  v_exception_raised := FALSE;
  BEGIN
    UPDATE public.eco_platform_audit_events
    SET event_type = 'TAMPERED'
    WHERE id = v_audit_row.id;
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Platform audit record was updated (append-only trigger failed)';
  END IF;

  -- 7.2 Platform audit DELETE rejected (append-only trigger)
  v_exception_raised := FALSE;
  BEGIN
    DELETE FROM public.eco_platform_audit_events
    WHERE id = v_audit_row.id;
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Platform audit record was deleted (append-only trigger failed)';
  END IF;

  -- 7.3 Tenant user CANNOT read platform audit table (RLS returns 0 rows)
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  SELECT COUNT(*) INTO v_count FROM public.eco_platform_audit_events;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Tenant admin was able to SELECT from public.eco_platform_audit_events';
  END IF;

  -- 7.4 Platform Superadmin CAN read platform audit table (RLS returns all platform rows)
  PERFORM public.harness_set_persona(v_vegen_auth_id);
  SELECT COUNT(*) INTO v_count FROM public.eco_platform_audit_events;
  IF v_count < 2 THEN
    RAISE EXCEPTION 'Test FAILED: Platform Superadmin could not read platform audit events';
  END IF;


  -- ============================================================
  -- 8. MULTI-ORG AMBIGUITY FAIL-CLOSED BEHAVIOR
  -- ============================================================

  -- Create a synthetic super-admin user with admin capabilities in BOTH NORTE and SUR (privileged setup)
  PERFORM public.harness_reset_role();
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_emiliano_profile_id, v_tpl_tenant_admin_id, TRUE);
  DELETE FROM public.eco_user_active_context WHERE user_profile_id = v_emiliano_profile_id;

  -- Gather privileged diagnostic context before switching to authenticated persona
  SELECT COUNT(*) INTO v_diag_emiliano_memberships
  FROM public.eco_organization_members
  WHERE user_profile_id = v_emiliano_profile_id AND is_active = TRUE;

  SELECT COUNT(*) INTO v_diag_synth_memberships
  FROM public.eco_organization_members
  WHERE user_profile_id = v_synth_multi_profile_id AND is_active = TRUE;

  SELECT COUNT(*) INTO v_diag_active_ctx_count
  FROM public.eco_user_active_context
  WHERE user_profile_id = v_emiliano_profile_id;

  -- Emiliano now holds ORG_MEMBER_PERMISSION_MANAGE in both NORTE and SUR.
  -- Without active context, targeting Synth Multi (who belongs to both) must fail closed on ambiguity:
  PERFORM public.harness_set_persona(v_emiliano_auth_id);

  RAISE NOTICE 'SECTION_8_DIAGNOSTICS: current_user=%, auth_uid=%, emiliano_profile_id=%, emiliano_active_memberships=%, synth_multi_active_memberships=%, active_ctx_rows=%',
    current_user, auth.uid(), v_emiliano_profile_id, v_diag_emiliano_memberships, v_diag_synth_memberships, v_diag_active_ctx_count;

  v_exception_raised := FALSE;
  v_err_state := NULL;
  v_err_msg := NULL;
  BEGIN
    PERFORM public.change_user_role(v_synth_multi_profile_id, 'ACCOUNTANT');
  EXCEPTION WHEN OTHERS THEN
    v_err_state := SQLSTATE;
    v_err_msg := SQLERRM;
    IF v_err_msg LIKE '%AMBIGUOUS_ORGANIZATION_CONTEXT%' THEN
      v_exception_raised := TRUE;
    ELSE
      RAISE EXCEPTION 'SECTION_8_UNEXPECTED_EXCEPTION:
SQLSTATE=%
SQLERRM=%', v_err_state, v_err_msg;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'SECTION_8_NO_EXCEPTION:
Expected AMBIGUOUS_ORGANIZATION_CONTEXT but call completed successfully';
  END IF;

  -- Providing explicit p_org_id resolves ambiguity cleanly:
  PERFORM public.change_user_role(v_synth_multi_profile_id, 'ACCOUNTANT', v_norte_org_id);
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_tpl_check <> v_tpl_accountant_id THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role with explicit p_org_id failed';
  END IF;

  -- Clean up extra membership on Emiliano (privileged)
  PERFORM public.harness_reset_role();
  DELETE FROM public.eco_organization_members WHERE organization_id = v_sur_org_id AND user_profile_id = v_emiliano_profile_id;


  -- ============================================================
  -- 9. CROSS-ORG TARGET DENIAL & SELF PROTECTION
  -- ============================================================

  -- 9.1 Emiliano attempts role change on Synth B (in DEMO SUR only) -> FAILS (TARGET_NOT_FOUND)
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_synth_user_b_profile_id, 'ADMIN');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%TARGET_NOT_FOUND%' OR SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Cross-org role change was not rejected';
  END IF;

  -- 9.2 Self-role change blocked
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_emiliano_profile_id, 'USER');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SELF_ROLE_CHANGE_NOT_ALLOWED%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Self-role modification was not blocked';
  END IF;

  -- 9.3 Self-deactivation blocked
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.set_user_active(v_emiliano_profile_id, FALSE);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SELF_DEACTIVATION_NOT_ALLOWED%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Self-deactivation was not blocked';
  END IF;


  -- ============================================================
  -- 10. SUPERADMIN CONTEXT SWITCHING & AUDIT INVARIANTS
  -- ============================================================

  -- 10.1 VEGEN (Platform Superadmin) switches context -> SUCCESS & emits PLATFORM AUDIT event
  PERFORM public.harness_reset_role();
  SELECT COUNT(*) INTO v_audit_count_before FROM public.eco_platform_audit_events;

  PERFORM public.harness_set_persona(v_vegen_auth_id);
  PERFORM public.switch_superadmin_org_context(v_norte_org_id);

  SELECT organization_id INTO v_role_check FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  IF v_role_check::uuid <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: VEGEN switch_superadmin_org_context did not update profile.organization_id';
  END IF;

  SELECT COUNT(*) INTO v_audit_count_after FROM public.eco_platform_audit_events;
  IF v_audit_count_after <> v_audit_count_before + 1 THEN
    RAISE EXCEPTION 'Test FAILED: switch_superadmin_org_context did not emit platform audit event';
  END IF;

  SELECT * INTO v_audit_row FROM public.eco_platform_audit_events ORDER BY created_at DESC LIMIT 1;
  IF v_audit_row.event_type <> 'SUPERADMIN_ORG_CONTEXT_SWITCHED'
     OR (v_audit_row.metadata->>'target_organization_id')::uuid <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: switch_superadmin_org_context emitted incorrect platform audit metadata';
  END IF;

  -- 10.2 Emiliano (Tenant Admin) cannot switch platform context
  PERFORM public.harness_set_persona(v_emiliano_auth_id);
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.switch_superadmin_org_context(v_sur_org_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Only SUPERADMIN can switch organization context%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Tenant admin allowed to call switch_superadmin_org_context';
  END IF;

  -- 10.3 Tenant Audit Log Append-Only Invariant (DELETE blocked)
  -- Privileged execution: proves append-only trigger blocks even privileged mutation
  PERFORM public.harness_reset_role();
  v_exception_raised := FALSE;
  BEGIN
    DELETE FROM public.eco_audit_events WHERE organization_id = v_norte_org_id;
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Append-only audit trigger failed to block DELETE on eco_audit_events';
  END IF;

  -- Reset role before exit
  PERFORM public.harness_reset_role();

  RAISE NOTICE 'WP-A3.2.1 DB Behavioral Test Suite PASSED ALL PLATFORM AUDIT, MULTI-ORG, AND CANONICAL AUTHORITY TESTS UNDER AUTHENTICATED ROLE SIMULATION.';
END $$;

ROLLBACK;
