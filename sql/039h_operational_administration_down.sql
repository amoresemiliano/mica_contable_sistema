-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Roll back 039h BEFORE 039g.
-- Existing companies, users, memberships and scopes are never deleted.
BEGIN;
LOCK TABLE public.eco_user_platform_role,public.eco_user_profiles,public.eco_role_templates,
 public.eco_role_template_capabilities,public.eco_platform_role_org_capabilities,
 public.eco_user_platform_capability_overrides,private.eco_platform_org_overrides,
 private.eco_platform_org_scopes,public.eco_capabilities,public.eco_organization_members,
 public.eco_membership_capability_overrides,public.eco_member_capability_overrides IN ACCESS EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(380038);
DO $restore$
DECLARE b RECORD; f RECORD; v_saved_member JSONB; v_member_columns TEXT; v_scopes_at_start JSONB;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'postgres only'; END IF;
 SELECT * INTO STRICT b FROM private.migration_039h_state;
 -- The new capability must never have been propagated to a legacy or wrong-scope template.
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities added_grant JOIN public.eco_role_templates grant_template
   ON grant_template.id=added_grant.role_template_id WHERE added_grant.capability_id=b.capability AND grant_template.scope IS DISTINCT FROM 'ORGANIZATION')
  OR EXISTS(SELECT 1 FROM public.eco_platform_role_org_capabilities added_grant JOIN public.eco_role_templates grant_template
   ON grant_template.id=added_grant.role_template_id WHERE added_grant.capability_id=b.capability AND grant_template.scope IS DISTINCT FROM 'PLATFORM') THEN
  RAISE EXCEPTION 'Propagation scope drift; do not alter historical grants'; END IF;
 SELECT COALESCE(jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id),'[]') INTO v_scopes_at_start
 FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=b.target;
 IF (SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY id),'[]') FROM public.eco_organization_members member_row
    WHERE user_profile_id=b.target) IS DISTINCT FROM b.memberships_installed THEN
  RAISE EXCEPTION 'Installed memberships drift: no rollback over later decisions'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides override_row JOIN public.eco_organization_members member_row
    ON member_row.id=override_row.membership_id WHERE member_row.user_profile_id=b.target)
  OR EXISTS(SELECT 1 FROM public.eco_member_capability_overrides legacy_override,
    LATERAL jsonb_each_text(to_jsonb(legacy_override)) legacy_field
    WHERE legacy_field.value=b.target::TEXT OR legacy_field.value IN(SELECT id::TEXT FROM public.eco_organization_members WHERE user_profile_id=b.target)) THEN
  RAISE EXCEPTION 'Unreviewed membership overrides block restoration'; END IF;
 FOR f IN SELECT * FROM private.migration_039h_functions LOOP
  IF pg_get_functiondef(to_regprocedure(f.signature)) IS DISTINCT FROM f.installed
   OR (SELECT pg_get_userbyid(proowner) FROM pg_proc WHERE oid=to_regprocedure(f.signature)) IS DISTINCT FROM f.owner_name
   OR (SELECT to_jsonb(proacl) FROM pg_proc WHERE oid=to_regprocedure(f.signature)) IS DISTINCT FROM f.acl THEN
   RAISE EXCEPTION '039h function/ACL drift: %',f.signature; END IF;
 END LOOP;
 IF (SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.historical_preset->>'id')::UUID) IS DISTINCT FROM b.historical_installed
  OR (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=(b.historical_preset->>'id')::UUID) IS DISTINCT FROM b.historical_grants
  OR (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=(b.historical_preset->>'id')::UUID) IS DISTINCT FROM b.historical_bridge
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=(b.historical_preset->>'id')::UUID AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=(b.historical_preset->>'id')::UUID AND is_active) THEN
  RAISE EXCEPTION 'Deprecated accounting state/grants/recipients drift'; END IF;
 IF (SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=b.target) IS DISTINCT FROM b.installed_assignment
  OR (SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=b.preset) IS DISTINCT FROM b.installed_preset
  OR (SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE id=b.capability) IS DISTINCT FROM b.installed_capability
  OR (SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_role_template_capabilities g WHERE role_template_id=b.preset) IS DISTINCT FROM b.grants
  OR (SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=b.preset) IS DISTINCT FROM b.bridge
  OR (SELECT jsonb_build_object('tenant',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_role_template_capabilities g WHERE capability_id=b.capability),'[]'),
    'platform',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_platform_role_org_capabilities g WHERE capability_id=b.capability),'[]'))) IS DISTINCT FROM b.compat_grants THEN
  RAISE EXCEPTION '039h seeded row drift: preserve subsequent administrative decisions'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=b.preset AND user_profile_id<>b.target)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=b.preset)
  OR EXISTS(SELECT 1 FROM private.eco_mica_invitations WHERE role_template_id=b.preset)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE capability_id=b.capability)
  OR EXISTS(SELECT 1 FROM private.eco_platform_org_overrides WHERE capability_id=b.capability)
  OR EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides WHERE capability_id=b.capability) THEN
  RAISE EXCEPTION '039h now has additional recipients/references; review before rollback'; END IF;
 -- Reactivate the exact historical preset before restoring its recipient. Grants were never removed.
 UPDATE public.eco_role_templates SET is_active=(b.historical_preset->>'is_active')::BOOLEAN,
  updated_at=(b.historical_preset->>'updated_at')::TIMESTAMPTZ WHERE id=(b.historical_preset->>'id')::UUID;
 UPDATE public.eco_user_platform_role SET role_template_id=(b.assignment->>'role_template_id')::UUID,
  updated_at=(b.assignment->>'updated_at')::TIMESTAMPTZ WHERE user_profile_id=b.target;
 IF (SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.historical_preset->>'id')::UUID) IS DISTINCT FROM b.historical_preset
  OR (SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=b.target) IS DISTINCT FROM b.assignment THEN
  RAISE EXCEPTION 'Historical preset/assignment exact restoration failed'; END IF;
 FOR f IN SELECT * FROM private.migration_039h_functions LOOP EXECUTE f.definition; END LOOP;
 -- Restore existing rows only, including all original metadata; never INSERT or DELETE memberships.
 SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO v_member_columns FROM pg_attribute
 WHERE attrelid='public.eco_organization_members'::regclass AND attnum>0 AND NOT attisdropped
   AND attname<>'id' AND attgenerated='' AND attidentity='';
 FOR v_saved_member IN SELECT value FROM jsonb_array_elements(b.memberships_before) LOOP
  EXECUTE format('UPDATE public.eco_organization_members SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.eco_organization_members,$1)) WHERE id=$2',
   v_member_columns,v_member_columns) USING v_saved_member,(v_saved_member->>'id')::UUID;
 END LOOP;
 IF (SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY id),'[]') FROM public.eco_organization_members member_row
    WHERE user_profile_id=b.target) IS DISTINCT FROM b.memberships_before THEN
  RAISE EXCEPTION 'Exact membership restoration failed'; END IF;
 IF (SELECT COALESCE(jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id),'[]') FROM private.eco_platform_org_scopes scope_row
    WHERE user_profile_id=b.target) IS DISTINCT FROM v_scopes_at_start THEN RAISE EXCEPTION 'Rollback changed scopes'; END IF;
 -- compat_grants was checked exactly above; only new preset/new capability rows are removed.
 DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=b.preset OR capability_id=b.capability;
 DELETE FROM public.eco_platform_role_org_capabilities WHERE role_template_id=b.preset OR capability_id=b.capability;
 DELETE FROM private.eco_mica_all_org_presets WHERE role_template_id=b.preset;
 DELETE FROM private.eco_mica_presets WHERE role_template_id=b.preset;
 DELETE FROM public.eco_role_templates WHERE id=b.preset;
 DELETE FROM public.eco_capabilities WHERE id=b.capability;
END; $restore$;
DROP TABLE private.migration_039h_state;
DROP TABLE private.migration_039h_functions;
COMMIT;
