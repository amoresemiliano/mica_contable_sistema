-- ============================================================
-- DB BEHAVIORAL SECURITY TEST SUITE FOR WP-A3.2.1 (MIGRATION 022)
-- ============================================================
-- Validates capability-driven authorization for:
-- 1. Identity & Self Profile Access
-- 2. Organization Visibility (ORG_VIEW)
-- 3. Member Profile Visibility (ORG_MEMBER_VIEW)
-- 4. User Role Modification (ORG_MEMBER_PERMISSION_MANAGE)
-- 5. Tenant User Activation / Deactivation (ORG_MEMBER_MANAGE)
-- 6. Global User Activation / Deactivation (GLOBAL_USER_MANAGE / PLATFORM_MANAGE)
-- 7. Global Operation Independence from Active Context
-- 8. Multi-Org Role & Membership State Isolation
-- 9. Superadmin Context Switching (SUPPORT_IMPERSONATE / ACCESS_ANY_ORG)
-- 10. Audit Visibility (AUDIT_VIEW_ORG) & Append-Only Invariant
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
  v_role_check TEXT;
  v_active_check BOOLEAN;
  v_tpl_check UUID;
  v_exception_raised BOOLEAN;
BEGIN
  RAISE NOTICE 'Executing WP-A3.2.1 DB Behavioral Test Matrix...';

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


  -- ============================================================
  -- 1. SETUP SYNTHETIC USERS & MULTI-ORG FIXTURES
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

  -- Synth User Multi: Member in BOTH DEMO NORTE (UPLOADER) and DEMO SUR (REVIEWER)
  -- Stale profile.organization_id is intentionally set to DEMO SUR!
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES (v_synth_multi_auth_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'synth_multi_' || v_synth_multi_auth_id::text || '@mica.test', 'pwd', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  SELECT id INTO v_synth_multi_profile_id FROM public.eco_user_profiles WHERE auth_user_id = v_synth_multi_auth_id;
  UPDATE public.eco_user_profiles SET is_active = TRUE, organization_id = v_sur_org_id, role = 'USER' WHERE id = v_synth_multi_profile_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_norte_org_id, v_synth_multi_profile_id, v_tpl_uploader_id, TRUE)
  RETURNING id INTO v_synth_multi_mem_norte_id;

  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_synth_multi_profile_id, v_tpl_reviewer_id, TRUE)
  RETURNING id INTO v_synth_multi_mem_sur_id;


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
  -- 3. ORGANIZATION & MEMBER PROFILE VISIBILITY
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

  -- 3.2 Emiliano can see members of DEMO NORTE (Synth A & Synth Multi)
  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano cannot view member in own org DEMO NORTE';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.eco_user_profiles WHERE id = v_synth_multi_profile_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Test FAILED: Emiliano cannot view multi-org member in DEMO NORTE (stale profile.org_id was SUR)';
  END IF;

  -- 3.3 Emiliano CANNOT see members of DEMO SUR (Synth B)
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
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  PERFORM public.change_user_role(v_synth_multi_profile_id, 'ADMIN');

  -- Verify NORTE membership role template updated to TENANT_ADMIN
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_tpl_check <> v_tpl_tenant_admin_id THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role did not update canonical NORTE membership template to TENANT_ADMIN';
  END IF;

  -- Verify SUR membership role template remains untouched (REVIEWER)
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_sur_id;
  IF v_tpl_check <> v_tpl_reviewer_id THEN
    RAISE EXCEPTION 'Negative Test FAILED: change_user_role leaked into and altered unrelated SUR membership template';
  END IF;

  -- 4.2 Verify profile.role is compatibility only and does NOT confer authority in SUR
  -- Synth Multi's profile.role was synchronized to 'ADMIN', but in SUR their membership is still REVIEWER.
  PERFORM set_config('request.jwt.claim.sub', v_synth_multi_auth_id::text, true);
  IF private.can_org(v_sur_org_id, 'ORG_MEMBER_PERMISSION_MANAGE') THEN
    RAISE EXCEPTION 'Negative Test FAILED: profile.role leaked admin authority into SUR where membership is REVIEWER';
  END IF;


  -- ============================================================
  -- 5. TENANT USER ACTIVATION / DEACTIVATION (set_user_active)
  -- ============================================================

  -- 5.1 Emiliano deactivates Synth Multi in DEMO NORTE:
  -- Only NORTE membership becomes inactive; SUR membership & global profile remain active!
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  PERFORM public.set_user_active(v_synth_multi_profile_id, FALSE);

  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: set_user_active did not deactivate NORTE membership';
  END IF;

  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_sur_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: set_user_active deactivated unrelated SUR membership';
  END IF;

  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_multi_profile_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: Tenant set_user_active deactivated global profile';
  END IF;

  -- Reactivate Synth Multi in NORTE
  PERFORM public.set_user_active(v_synth_multi_profile_id, TRUE);


  -- ============================================================
  -- 6. GLOBAL USER ACTIVATION (set_global_user_active)
  -- ============================================================

  -- 6.1 Platform Superadmin (VEGEN) with active context set to NORTE globally deactivates target profile:
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  INSERT INTO public.eco_user_active_context (user_profile_id, organization_id, updated_at)
  VALUES (v_vegen_profile_id, v_norte_org_id, now())
  ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = v_norte_org_id;

  PERFORM public.set_global_user_active(v_synth_user_a_profile_id, FALSE);

  -- Verify global profile is deactivated
  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> FALSE THEN
    RAISE EXCEPTION 'Test FAILED: set_global_user_active failed when active context was set to NORTE';
  END IF;

  -- Verify membership rows were NOT modified
  SELECT is_active INTO v_active_check FROM public.eco_organization_members WHERE id = v_synth_mem_a_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Negative Test FAILED: set_global_user_active mutated eco_organization_members row';
  END IF;

  -- 6.2 Platform Superadmin with active context NULL globally reactivates target profile:
  DELETE FROM public.eco_user_active_context WHERE user_profile_id = v_vegen_profile_id;
  PERFORM public.set_global_user_active(v_synth_user_a_profile_id, TRUE);

  SELECT is_active INTO v_active_check FROM public.eco_user_profiles WHERE id = v_synth_user_a_profile_id;
  IF v_active_check <> TRUE THEN
    RAISE EXCEPTION 'Test FAILED: set_global_user_active failed when active context was NULL';
  END IF;

  -- 6.3 Tenant Admin CANNOT invoke set_global_user_active
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
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


  -- ============================================================
  -- 7. MULTI-ORG AMBIGUITY FAIL-CLOSED BEHAVIOR
  -- ============================================================

  -- Create a synthetic super-admin user with admin capabilities in BOTH NORTE and SUR
  INSERT INTO public.eco_organization_members (organization_id, user_profile_id, role_template_id, is_active)
  VALUES (v_sur_org_id, v_emiliano_profile_id, v_tpl_tenant_admin_id, TRUE);

  -- Emiliano now holds ORG_MEMBER_PERMISSION_MANAGE in both NORTE and SUR.
  -- Without active context, targeting Synth Multi (who belongs to both) must fail closed on ambiguity:
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
  DELETE FROM public.eco_user_active_context WHERE user_profile_id = v_emiliano_profile_id;

  v_exception_raised := FALSE;
  BEGIN
    PERFORM public.change_user_role(v_synth_multi_profile_id, 'ACCOUNTANT');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%AMBIGUOUS_ORGANIZATION_CONTEXT%' THEN
      v_exception_raised := TRUE;
    END IF;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Multi-org ambiguous target did not fail closed with AMBIGUOUS_ORGANIZATION_CONTEXT';
  END IF;

  -- Providing explicit p_org_id resolves ambiguity cleanly:
  PERFORM public.change_user_role(v_synth_multi_profile_id, 'ACCOUNTANT', v_norte_org_id);
  SELECT role_template_id INTO v_tpl_check FROM public.eco_organization_members WHERE id = v_synth_multi_mem_norte_id;
  IF v_tpl_check <> v_tpl_accountant_id THEN
    RAISE EXCEPTION 'Test FAILED: change_user_role with explicit p_org_id failed';
  END IF;

  -- Clean up extra membership on Emiliano
  DELETE FROM public.eco_organization_members WHERE organization_id = v_sur_org_id AND user_profile_id = v_emiliano_profile_id;


  -- ============================================================
  -- 8. CROSS-ORG TARGET DENIAL & SELF PROTECTION
  -- ============================================================

  -- 8.1 Emiliano attempts role change on Synth B (in DEMO SUR only) -> FAILS (TARGET_NOT_FOUND)
  PERFORM set_config('request.jwt.claim.sub', v_emiliano_auth_id::text, true);
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

  -- 8.2 Self-role change blocked
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

  -- 8.3 Self-deactivation blocked
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
  -- 9. SUPERADMIN CONTEXT SWITCHING & AUDIT INVARIANTS
  -- ============================================================

  -- 9.1 VEGEN (Platform Superadmin) switches context -> SUCCESS
  PERFORM set_config('request.jwt.claim.sub', v_vegen_auth_id::text, true);
  PERFORM public.switch_superadmin_org_context(v_norte_org_id);

  SELECT organization_id INTO v_role_check FROM public.eco_user_profiles WHERE auth_user_id = v_vegen_auth_id;
  IF v_role_check::uuid <> v_norte_org_id THEN
    RAISE EXCEPTION 'Test FAILED: VEGEN switch_superadmin_org_context did not update profile.organization_id';
  END IF;

  -- 9.2 Emiliano (Tenant Admin) cannot switch platform context
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

  -- 9.3 Audit Log Append-Only Invariant (DELETE blocked)
  v_exception_raised := FALSE;
  BEGIN
    DELETE FROM public.eco_audit_events WHERE organization_id = v_norte_org_id;
  EXCEPTION WHEN OTHERS THEN
    v_exception_raised := TRUE;
  END;
  IF NOT v_exception_raised THEN
    RAISE EXCEPTION 'Negative Test FAILED: Append-only audit trigger failed to block DELETE on eco_audit_events';
  END IF;

  RAISE NOTICE 'WP-A3.2.1 DB Behavioral Test Suite PASSED ALL MULTI-ORG, GLOBAL VS TENANT ISOLATION, AND CANONICAL AUTHORITY TESTS.';
END $$;

ROLLBACK;
