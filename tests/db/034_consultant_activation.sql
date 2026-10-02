-- Manual test AFTER 034 as postgres in isolated DEV. Not executed by Jest.
-- Fixtures, context switches and overrides are transactional; all end in ROLLBACK.
-- If the client stops on an error, issue ROLLBACK before continuing.
BEGIN;
DO $$
DECLARE
  v_template UUID;
  v_actor RECORD;
  v_org UUID;
  v_member UUID;
  v_cap TEXT;
  v_kind TEXT;
  v_action TEXT;
  v_case TEXT;
  v_item UUID;
  v_activity UUID := gen_random_uuid();
  v_category UUID := gen_random_uuid();
BEGIN
  SELECT id INTO STRICT v_template FROM public.eco_role_templates
  WHERE code = 'CONSULTANT' AND scope = 'ORGANIZATION' AND is_active IS TRUE;
  IF v_template <> 'd578bfd2-2e89-4867-a8b8-0567ee49355c'::UUID THEN
    RAISE EXCEPTION 'Unexpected CONSULTANT template';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id = v_template) THEN
    RAISE EXCEPTION 'CONSULTANT has a platform role';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_role_template_capabilities g
    JOIN public.eco_capabilities c ON c.id = g.capability_id
    WHERE g.role_template_id = v_template AND c.scope IS DISTINCT FROM 'ORGANIZATION') THEN
    RAISE EXCEPTION 'CONSULTANT has platform/non-organization grants';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.migration_034_consultant_backup b
    WHERE b.template_id = v_template AND b.was_active IS TRUE
    AND b.tenant_admin_state = (SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]'::JSONB)
      FROM public.eco_role_templates t WHERE t.code = 'TENANT_ADMIN')) THEN
    RAISE EXCEPTION 'Missing 034 baseline or TENANT_ADMIN changed';
  END IF;

  INSERT INTO public.eco_economic_activities(id, name, arca_code)
  VALUES (v_activity, '034 activation fixture', v_activity::TEXT);
  INSERT INTO public.eco_tax_categories(id, name, category_type)
  VALUES (v_category, '034 activation fixture', 'EXPENSE');

  FOR v_actor IN SELECT * FROM (VALUES
    ('NORTE', '6562ac9c-87b3-4886-a535-2d2e812a44b3'::UUID, 'f290b025-86a6-4809-8aee-ed184e1b204d'::UUID),
    ('OESTE', '20f07e8e-4713-4884-bdbc-0a56e8da372e'::UUID, '0182c4e0-7983-474b-acb7-c8b04f1ac7b3'::UUID),
    ('SUR', '06d75e90-28b3-4a10-ad5b-a6c5a1f4c16d'::UUID, '986a7906-213e-4f35-b7b9-f67da128f4a1'::UUID)
  ) AS actors(label, profile_id, auth_user_id) LOOP
    SELECT p.organization_id, m.id INTO STRICT v_org, v_member
    FROM public.eco_user_profiles p
    JOIN public.eco_organization_members m ON m.user_profile_id = p.id AND m.organization_id = p.organization_id
    JOIN public.eco_organizations o ON o.id = m.organization_id
    WHERE p.id = v_actor.profile_id AND p.auth_user_id = v_actor.auth_user_id
      AND p.is_active IS TRUE AND m.is_active IS TRUE AND o.is_active IS TRUE
      AND m.role_template_id = v_template;
    IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id = v_actor.profile_id) THEN
      RAISE EXCEPTION '% unexpectedly has a platform role', v_actor.label;
    END IF;
    INSERT INTO public.eco_user_active_context(user_profile_id, organization_id)
    VALUES (v_actor.profile_id, v_org)
    ON CONFLICT (user_profile_id) DO UPDATE SET organization_id = EXCLUDED.organization_id;
    INSERT INTO public.eco_org_economic_activities(organization_id, activity_id, is_assigned, is_active)
    VALUES (v_org, v_activity, TRUE, TRUE);
    INSERT INTO public.eco_org_tax_categories(organization_id, category_id, is_assigned, is_active)
    VALUES (v_org, v_category, TRUE, TRUE);
    PERFORM set_config('request.jwt.claim.sub', v_actor.auth_user_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor.auth_user_id, 'role', 'authenticated')::TEXT, true);
    -- Under authenticated, test the public boundary; private schema access is not required.
    EXECUTE 'SET LOCAL ROLE authenticated';
    FOREACH v_cap IN ARRAY ARRAY['ORG_VIEW', 'CATALOG_ACTIVITY_MANAGE', 'CATALOG_CATEGORY_MANAGE'] LOOP
      IF NOT EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_org) r
        WHERE r.code = v_cap AND r.scope = 'ORGANIZATION' AND r.organization_id = v_org) THEN
        RAISE EXCEPTION '% effective capabilities omit %', v_actor.label, v_cap;
      END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_org) WHERE scope = 'PLATFORM') THEN
      RAISE EXCEPTION '% unexpectedly acquired platform capabilities', v_actor.label;
    END IF;
    PERFORM public.deactivate_economic_activity(v_activity);
    PERFORM public.deactivate_tax_category(v_category);
    IF NOT EXISTS (SELECT 1 FROM public.eco_org_economic_activities
      WHERE organization_id = v_org AND activity_id = v_activity AND is_assigned AND NOT is_active)
      OR NOT EXISTS (SELECT 1 FROM public.eco_org_tax_categories
      WHERE organization_id = v_org AND category_id = v_category AND is_assigned AND NOT is_active) THEN
      RAISE EXCEPTION '% deactivation failed', v_actor.label;
    END IF;
    PERFORM public.activate_economic_activity(v_activity);
    PERFORM public.activate_tax_category(v_category);
    IF NOT EXISTS (SELECT 1 FROM public.eco_org_economic_activities
      WHERE organization_id = v_org AND activity_id = v_activity AND is_assigned AND is_active)
      OR NOT EXISTS (SELECT 1 FROM public.eco_org_tax_categories
      WHERE organization_id = v_org AND category_id = v_category AND is_assigned AND is_active) THEN
      RAISE EXCEPTION '% reactivation failed', v_actor.label;
    END IF;
    EXECUTE 'RESET ROLE';

    FOREACH v_kind IN ARRAY ARRAY['economic_activity', 'tax_category'] LOOP
      v_cap := CASE WHEN v_kind = 'economic_activity' THEN 'CATALOG_ACTIVITY_MANAGE' ELSE 'CATALOG_CATEGORY_MANAGE' END;
      v_item := CASE WHEN v_kind = 'economic_activity' THEN v_activity ELSE v_category END;
      FOREACH v_case IN ARRAY ARRAY['DENY', 'ABSENT'] LOOP
        -- Inner subtransaction rolls back every temporary permission change.
        BEGIN
          IF v_case = 'DENY' THEN
            INSERT INTO public.eco_membership_capability_overrides(membership_id, capability_id, effect)
            SELECT v_member, id, 'DENY' FROM public.eco_capabilities WHERE code = v_cap
            ON CONFLICT (membership_id, capability_id) DO UPDATE SET effect = 'DENY';
          ELSE
            DELETE FROM public.eco_role_template_capabilities g USING public.eco_capabilities c
            WHERE g.role_template_id = v_template AND g.capability_id = c.id AND c.code = v_cap;
            DELETE FROM public.eco_membership_capability_overrides ov USING public.eco_capabilities c
            WHERE ov.membership_id = v_member AND ov.capability_id = c.id AND c.code = v_cap;
          END IF;
          EXECUTE 'SET LOCAL ROLE authenticated';
          IF EXISTS (SELECT 1 FROM public.get_my_effective_capabilities(v_org) r
            WHERE r.code = v_cap AND r.scope = 'ORGANIZATION' AND r.organization_id = v_org) THEN
            RAISE EXCEPTION '%: % did not revoke %', v_actor.label, v_case, v_cap;
          END IF;
          FOREACH v_action IN ARRAY ARRAY['activate', 'deactivate'] LOOP
            BEGIN
              EXECUTE format('SELECT public.%s_%s($1)', v_action, v_kind) USING v_item;
              RAISE EXCEPTION '%: unauthorized % allowed under %', v_actor.label, v_action, v_case;
            EXCEPTION WHEN insufficient_privilege THEN NULL; END;
          END LOOP;
          EXECUTE 'RESET ROLE';
          RAISE EXCEPTION 'Restore temporary permission fixture' USING ERRCODE = 'Z0034';
        EXCEPTION WHEN SQLSTATE 'Z0034' THEN NULL; END;
      END LOOP;
    END LOOP;
    RAISE NOTICE '%: all CONSULTANT capability and activation checks passed', v_actor.label;
  END LOOP;
END;
$$;
ROLLBACK;
