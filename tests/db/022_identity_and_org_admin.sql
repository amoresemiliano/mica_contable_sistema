-- ============================================================
-- DB BEHAVIORAL SECURITY TEST SUITE FOR WP-A3.2.1 (MIGRATION 022)
-- ============================================================
-- Validates capability-driven authorization for:
-- 1. Identity & Self Profile Access
-- 2. Organization Visibility (ORG_VIEW)
-- 3. Member Profile Visibility (ORG_MEMBER_VIEW)
-- 4. User Role Modification (ORG_MEMBER_PERMISSION_MANAGE)
-- 5. User Activation / Deactivation (ORG_MEMBER_MANAGE)
-- 6. Superadmin Context Switching (SUPPORT_IMPERSONATE / ACCESS_ANY_ORG)
-- 7. Audit Visibility (AUDIT_VIEW_ORG) & Append-Only Invariant
-- 8. Synthetic Overrides, Cross-Tenant Isolation, Fail-Closed Behavior
--
-- Entire script executes under BEGIN ... ROLLBACK.
-- ============================================================

BEGIN;

-- Temporarily apply M022 inside transaction for behavioral validation
\i sql/022_identity_and_org_admin.sql

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

  -- Synthetic users
  v_synth_user_a_auth_id UUID := gen_random_uuid();
  v_synth_user_b_auth_id UUID := gen_random_uuid();
  v_synth_user_c_auth_id UUID := gen_random_uuid();

  v_synth_user_a_profile_id UUID;
  v_synth_user_b_profile_id UUID;
  v_synth_user_c_profile_id UUID;

  v_synth_mem_a_id UUID;
  v_synth_mem_b_id UUID;

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
  v_role_check TEXT;
  v_active_check BOOLEAN;
  v_exception_raised BOOLEAN;
BEGIN
  RAISE NOTICE 'Executing WP-A3.2.1 DB Behavioral Test Matrix...';

  -- Resolve real user IDs
  SELECT id INTO v_vegen_auth_id     FROM auth.users WHERE email = 'vegendigital@gmail.com';
  SELECT id INTO v_marianela_auth_id FROM auth.users WHERE email = 'drcmarianela@gmail.com';
  SELECT id INTO v_emiliano_auth_id  FROM auth.users WHERE email = 'emilianodirosa1@gmail.com';
  SELECT id INTO v_edravi_auth_id    FROM auth.users WHERE email = 'edravi77@gmail.com';
  SELECT id INTO v_calle_auth_id     FROM auth.users WHERE email = 'calleelcalvario16@gmail.com';

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


  -- ============================================================
  -- 1. SETUP SYNTHETIC USERS & PROFILES
  -- ============================================================

  -- Synth User A (Member in DEMO NORTE)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_synth_user_a_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'synth_a_' || v_synth_user_a_auth_id::text || '@mica.test', 'pwd', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  SELECT id INTO v_synth_user_a_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_synth_user_a_auth_id;
  UPDATE public.eco_user_profiles SET is_active = TRUE, organization_id = v_norte_org_id, role = 'USER' WHERE id = v_synth_user_a_profile_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_synth_user_a_profile_id, v_tpl_uploader_id, TRUE)
  RETURNING id INTO v_synth_mem_a_id;

  -- Synth User B (Member in DEMO SUR)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_synth_user_b_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'synth_b_' || v_synth_user_b_auth_id::text || '@mica.test', 'pwd', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  SELECT id INTO v_synth_user_b_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_synth_user_b_auth_id;
  UPDATE public.eco_user_profiles SET is_active = TRUE, organization_id = v_sur_org_id, role = 'USER' WHERE id = v_synth_user_b_profile_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_synth_user_b_profile_id, v_tpl_reviewer_id, TRUE)
  RETURNING id INTO v_synth_mem_b_id;

  -- Synth User C (Inactive user in DEMO NORTE)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_synth_user_c_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'synth_c_' || v_synth_user_c_auth_id::text || '@mica.test', 'pwd', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  SELECT id INTO v_synth_user_c_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_synth_user_c_auth_id;
  UPDATE public.eco_user_profiles SET is_active = FALSE, organization_id = v_norte_org_id, role = 'USER' WHERE id = v_synth_user_c_profile_id;


  -- ============================================================
  -- 2. IDENTITY & SELF PROFILE TESTS
  -- ============================================================

  -- 2.1 Active user can read self profile
  PERFORM set_config('request.jwt.claim.sub', v_synth_user_a_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Active user cannot read own profile';
  END IF;

  -- 2.2 Inactive user fails closed (cannot read own profile via RLS)
  PERFORM set_config('request.jwt.claim.sub', v_synth_user_c_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_c_profile_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Inactive user profile was able to read own record via RLS';
  END IF;


  -- ============================================================
  -- 3. ORGANIZATION VISIBILITY (ORG_VIEW)
  -- ============================================================

  -- 3.1 Emiliano (Admin NORTE) sees only DEMO NORTE
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_organizations WHERE id = v_norte_org_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano denied ORG_VIEW for DEMO NORTE';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_organizations WHERE id = v_sur_org_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Emiliano granted ORG_VIEW for DEMO SUR';
  END IF;

  -- 3.2 Marianela (Accounting Superadmin) sees scoped orgs (NORTE, SUR, OESTE) but not unassigned MICA
  PERFORM set_config('request.jwt.claim.sub', v_marianela_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_organizations WHERE id IN (v_norte_org_id, v_sur_org_id, v_oeste_org_id);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Test FAILED: Marianela missing scoped orgs in ORG_VIEW';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_organizations WHERE id = v_mica_org_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Marianela granted ORG_VIEW in unassigned MICA org';
  END IF;


  -- ============================================================
  -- 4. MEMBER PROFILE VISIBILITY (ORG_MEMBER_VIEW)
  -- ============================================================

  -- 4.1 Emiliano (Admin NORTE) can see members of DEMO NORTE (Synth A)
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano cannot view member in own org DEMO NORTE';
  END IF;

  -- 4.2 Emiliano CANNOT see members of DEMO SUR (Synth B)
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_b_profile_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Emiliano cross-tenant viewed member in DEMO SUR';
  END IF;


  -- ============================================================
  -- 5. USER ROLE MODIFICATION (change_user_role)
  -- ============================================================

  -- 5.1 Emiliano changes role of Synth A in DEMO NORTE -> SUCCESS
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  PERFORM public.change_user_role(v_synth_user_a_profile_id, 'REVIEWER');

  SELECT role INTO v_role_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_role_check <> 'REVIEWER' THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role did not update role to REVIEWER';
  END IF;

  -- 5.2 Emiliano attempts self-role change -> FAILS (SELF_ROLE_CHANGE_NOT_ALLOWED)
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_emiliano_profile_id, 'USER');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%SELF_ROLE_CHANGE_NOT_ALLOWED%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Self-role modification was not blocked with SELF_ROLE_CHANGE_NOT_ALLOWED';
  END IF;

  -- 5.3 Emiliano attempts cross-org role change on Synth B (in DEMO SUR) -> FAILS (FORBIDDEN)
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_synth_user_b_profile_id, 'ADMIN');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Cross-org role change was not rejected with FORBIDDEN';
  END IF;

  -- 5.4 Synth A (UPLOADER, no ORG_MEMBER_PERMISSION_MANAGE) attempts role change -> FAILS (FORBIDDEN)
  PERFORM set_config('request.jwt.claim.sub', v_synth_user_a_auth_id::text, true);
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_emiliano_profile_id, 'USER');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Non-privileged user change_user_role was not rejected with FORBIDDEN';
  END IF;

  -- 5.5 Synthetic ALLOW override grants change_user_role capability to Synth A
  INSERT INTO public.eco_membership_capability_overrides (membership_id, capability_id, effect)
  VALUES (v_synth_mem_a_id, v_cap_role_manage_id, 'ALLOW');

  PERFORM set_config('request.jwt.claim.sub', v_synth_user_a_auth_id::text, true);
  PERFORM public.change_user_role(v_emiliano_profile_id, 'ADMIN'); -- Succeeded via override


  -- ============================================================
  -- 6. USER ACTIVATION / DEACTIVATION (set_user_active)
  -- ============================================================

  -- 6.1 Emiliano deactivates Synth A in DEMO NORTE -> SUCCESS
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  PERFORM public.set_user_active(v_synth_user_a_profile_id, FALSE);

  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: set_user_active did not deactivate target profile';
  END IF;

  -- 6.2 Emiliano reactivates Synth A in DEMO NORTE -> SUCCESS
  PERFORM public.set_user_active(v_synth_user_a_profile_id, TRUE);
  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Test FAILED: set_user_active did not reactivate target profile';
  END IF;

  -- 6.3 Self-deactivation blocked
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

  -- 6.4 Cross-tenant status change blocked
  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.set_user_active(v_synth_user_b_profile_id, FALSE);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%FORBIDDEN%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Cross-tenant set_user_active was not blocked with FORBIDDEN';
  END IF;


  -- ============================================================
  -- 7. SUPERADMIN CONTEXT SWITCHING (switch_superadmin_org_context)
  -- ============================================================

  -- 7.1 VEGEN (Platform Superadmin) switches context -> SUCCESS
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  PERFORM public.switch_superadmin_org_context(v_norte_org_id);

  SELECT organization_id INTO v_role_check FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  IF v_role_check::uuid <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: VEGEN switch_superadmin_org_context did not update profile.organization_id';
  END IF;

  SELECT organization_id INTO v_role_check FROM public.eco_user_active_context WHERE user_profile_id = (SELECT id FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id);
  IF v_role_check::uuid <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: VEGEN switch_superadmin_org_context did not update eco_user_active_context';
  END IF;

  -- 7.2 Emiliano (Tenant Admin) attempts switch_superadmin_org_context -> FAILS
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
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


  -- ============================================================
  -- 8. AUDIT VISIBILITY & APPEND-ONLY INVARIANT
  -- ============================================================

  -- 8.1 Emiliano views audit events for DEMO NORTE
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  SELECT COUNT(*) INTO v_count FROM public.eco_audit_events WHERE organization_id = v_norte_org_id;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano cannot view audit events for DEMO NORTE';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_audit_events WHERE organization_id = v_sur_org_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Negative Test FAILED: Emiliano viewed audit events from DEMO SUR';
  END IF;

  -- 8.2 Append-only trigger test (DELETE on eco_audit_events blocked)
  v_exception_raised := FALSE;
  BEGIN
    DELETE FROM public.eco_audit_events WHERE organization_id = v_norte_org_id;
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Append-only audit trigger failed to block DELETE on eco_audit_events';
  END IF;

  RAISE NOTICE 'WP-A3.2.1 DB Behavioral Test Suite PASSED ALL 21 TEST CASES SUCCESSFULLY.';
END $$;

ROLLBACK;
