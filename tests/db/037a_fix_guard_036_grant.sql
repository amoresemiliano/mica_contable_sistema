-- Supabase SQL Editor, after 037a, as postgres. Prepared only; never executed by Jest.
-- Real membership resolved below; templates are transaction-local fixtures. No fixed template codes.
BEGIN;
DO $test$
DECLARE
  v_member UUID; v_profile UUID;
  v_org_cap UUID; v_org_cap2 UUID; v_platform_cap UUID; v_platform_cap2 UUID; v_reserved UUID;
  v_platform_template UUID := gen_random_uuid();
  v_org_template UUID := gen_random_uuid();
  v_sql TEXT; v_bad_cap UUID;
BEGIN
  SELECT id,user_profile_id INTO v_member,v_profile FROM public.eco_organization_members ORDER BY id LIMIT 1;
  IF v_member IS NULL THEN RAISE EXCEPTION '037a fixture requires an existing membership'; END IF;
  SELECT id INTO STRICT v_org_cap FROM public.eco_capabilities WHERE code='RECORD_VIEW' AND scope='ORGANIZATION' AND is_active;
  SELECT id INTO STRICT v_org_cap2 FROM public.eco_capabilities WHERE code='ORG_VIEW' AND scope='ORGANIZATION' AND is_active;
  SELECT id INTO STRICT v_platform_cap FROM public.eco_capabilities WHERE code='GLOBAL_CATALOG_VIEW' AND scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE';
  SELECT id INTO STRICT v_platform_cap2 FROM public.eco_capabilities WHERE code='GLOBAL_CATALOG_MANAGE' AND scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE';
  SELECT id INTO STRICT v_reserved FROM public.eco_capabilities WHERE code='ACCESS_ANY_ORG' AND delegation_class='OWNER_RESERVED';
  INSERT INTO public.eco_role_templates(id,code,name,scope,is_active,is_system) VALUES
    (v_platform_template,'TEST_037A_'||v_platform_template::TEXT,'037a platform fixture','PLATFORM',TRUE,FALSE),
    (v_org_template,'TEST_037A_'||v_org_template::TEXT,'037a organization fixture','ORGANIZATION',TRUE,FALSE);
  DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=v_member AND capability_id IN(v_org_cap,v_org_cap2,v_platform_cap,v_reserved);
  DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=v_profile AND capability_id IN(v_platform_cap,v_platform_cap2,v_org_cap,v_reserved);

  -- Both INSERT effects and both UPDATE effects must work on a record without role_template_id.
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(v_member,v_org_cap,'ALLOW');
  IF NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE membership_id=v_member AND capability_id=v_org_cap AND effect='ALLOW') THEN RAISE EXCEPTION 'Membership INSERT ALLOW failed'; END IF;
  UPDATE public.eco_membership_capability_overrides SET effect='DENY' WHERE membership_id=v_member AND capability_id=v_org_cap;
  IF NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE membership_id=v_member AND capability_id=v_org_cap AND effect='DENY') THEN RAISE EXCEPTION 'Membership UPDATE DENY failed'; END IF;
  DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=v_member AND capability_id=v_org_cap;
  INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(v_member,v_org_cap,'DENY');
  UPDATE public.eco_membership_capability_overrides SET effect='ALLOW',capability_id=v_org_cap2 WHERE membership_id=v_member AND capability_id=v_org_cap;
  IF NOT EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE membership_id=v_member AND capability_id=v_org_cap2 AND effect='ALLOW') THEN RAISE EXCEPTION 'Membership UPDATE ALLOW/capability failed'; END IF;
  FOREACH v_bad_cap IN ARRAY ARRAY[v_platform_cap,v_reserved] LOOP
    FOREACH v_sql IN ARRAY ARRAY[
      'INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES($1,$2,''ALLOW'')',
      'INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES($1,$2,''DENY'')',
      'UPDATE public.eco_membership_capability_overrides SET capability_id=$2 WHERE membership_id=$1 AND capability_id=$3'
    ] LOOP
      BEGIN
        EXECUTE v_sql USING v_member,v_bad_cap,v_org_cap2;
        RAISE EXCEPTION 'Invalid membership capability accepted';
      EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    END LOOP;
  END LOOP;

  -- Positive cases for the other typed branches.
  INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES(v_platform_template,v_platform_cap),(v_org_template,v_org_cap);
  INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES(v_platform_template,v_org_cap);
  INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES(v_profile,v_platform_cap,'ALLOW');
  UPDATE public.eco_user_platform_capability_overrides SET effect='DENY',capability_id=v_platform_cap2 WHERE user_profile_id=v_profile AND capability_id=v_platform_cap;
  IF NOT EXISTS (SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=v_profile AND capability_id=v_platform_cap2 AND effect='DENY') THEN RAISE EXCEPTION 'Platform override regression'; END IF;
  FOREACH v_sql IN ARRAY ARRAY[
    'INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES($1,$3)',
    'INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES($2,$4)',
    'UPDATE public.eco_role_template_capabilities SET capability_id=$3 WHERE role_template_id=$1 AND capability_id=$4',
    'INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES($2,$3)',
    'INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES($1,$4)',
    'UPDATE public.eco_platform_role_org_capabilities SET role_template_id=$2 WHERE role_template_id=$1 AND capability_id=$3',
    'UPDATE public.eco_platform_role_org_capabilities SET capability_id=$4 WHERE role_template_id=$1 AND capability_id=$3',
    'INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES($5,$3,''ALLOW'')',
    'UPDATE public.eco_user_platform_capability_overrides SET capability_id=$3 WHERE user_profile_id=$5 AND capability_id=$6',
    'INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id) VALUES($1,$7)',
    'INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id) VALUES($1,$7)',
    'INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES($5,$7,''ALLOW'')'
  ] LOOP
    BEGIN
      EXECUTE v_sql USING v_platform_template,v_org_template,v_org_cap,v_platform_cap,v_profile,v_platform_cap2,v_reserved;
      RAISE EXCEPTION 'Invalid grant scope/reserved capability accepted: %',v_sql;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  RAISE NOTICE '037a typed trigger branches and membership ALLOW/DENY passed; rollback follows';
END;
$test$;
ROLLBACK;
