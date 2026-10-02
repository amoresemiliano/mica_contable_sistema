-- MICA ourzapkjykzlwsjunzmd. SELECT ONLY; not executed by agent.
-- Copy each reviewed policies array into 039k_policy_manifest.json and regenerate offline.
SELECT v_relation::REGCLASS AS relation,(SELECT COALESCE(jsonb_agg(jsonb_build_object('name',policy_row.polname,'command',policy_row.polcmd,
 'permissive',policy_row.polpermissive,'roles',(SELECT jsonb_agg(CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
 ORDER BY CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END) FROM unnest(policy_row.polroles) role_oid),
 'using',pg_get_expr(policy_row.polqual,policy_row.polrelid),'check',pg_get_expr(policy_row.polwithcheck,policy_row.polrelid)) ORDER BY policy_row.polname),'[]')
 FROM pg_policy policy_row WHERE policy_row.polrelid=v_relation) AS policies
FROM unnest(ARRAY['public.eco_role_templates'::REGCLASS,'public.eco_role_template_capabilities'::REGCLASS,'public.eco_platform_role_org_capabilities'::REGCLASS,'public.eco_user_platform_role'::REGCLASS,'public.eco_user_platform_capability_overrides'::REGCLASS,'public.eco_membership_capability_overrides'::REGCLASS]) v_relation;
SELECT relation_row.oid::REGCLASS,pg_get_userbyid(relation_row.relowner),relation_row.relrowsecurity,relation_row.relforcerowsecurity
FROM pg_class relation_row WHERE relation_row.oid IN('public.eco_role_templates'::REGCLASS,'public.eco_role_template_capabilities'::REGCLASS,'public.eco_platform_role_org_capabilities'::REGCLASS,'public.eco_user_platform_role'::REGCLASS,'public.eco_user_platform_capability_overrides'::REGCLASS,'public.eco_membership_capability_overrides'::REGCLASS);
SELECT target.table_name,actor.role_name,privilege.privilege_name,
 has_table_privilege(actor.role_name,'public.'||target.table_name,privilege.privilege_name) AS effective_authority
FROM unnest(ARRAY['eco_role_templates','eco_role_template_capabilities','eco_platform_role_org_capabilities','eco_user_platform_role','eco_user_platform_capability_overrides','eco_membership_capability_overrides']) target(table_name)
CROSS JOIN unnest(ARRAY['anon','authenticated','service_role','postgres']) actor(role_name)
CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) privilege(privilege_name);
SELECT tgrelid::REGCLASS,tgname,tgenabled,pg_get_triggerdef(oid) FROM pg_trigger
WHERE tgrelid IN('public.eco_role_templates'::REGCLASS,'public.eco_role_template_capabilities'::REGCLASS,'public.eco_platform_role_org_capabilities'::REGCLASS,'public.eco_user_platform_role'::REGCLASS,'public.eco_user_platform_capability_overrides'::REGCLASS,'public.eco_membership_capability_overrides'::REGCLASS) AND NOT tgisinternal;
SELECT to_jsonb(owner_row) AS structural_owner,template_row.code FROM private.eco_platform_owner owner_row
JOIN public.eco_user_platform_role assignment_row ON assignment_row.user_profile_id=owner_row.user_profile_id
JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id;
SELECT to_jsonb(assignment_row),template_row.code FROM public.eco_user_platform_role assignment_row
JOIN public.eco_role_templates template_row ON template_row.id=assignment_row.role_template_id
WHERE assignment_row.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID;
