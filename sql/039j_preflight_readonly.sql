-- MICA ourzapkjykzlwsjunzmd. SELECT ONLY. Prepared, NOT executed by agent.
-- Effective authority is the contract. Grantor/ACL order is diagnostic only.
SELECT relation_row.oid::regclass AS relation,pg_get_userbyid(relation_row.relowner) AS owner,
 relation_row.relrowsecurity,relation_row.relforcerowsecurity,relation_row.relacl
FROM pg_class relation_row WHERE relation_row.oid IN(
 'public.eco_capabilities'::regclass,'public.eco_role_templates'::regclass,
 'public.eco_role_template_capabilities'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
 'public.eco_user_platform_role'::regclass);

SELECT relation_row.oid::regclass AS relation,pg_get_userbyid(grants.grantor) AS grantor,
 CASE WHEN grants.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(grants.grantee) END AS grantee,
 grants.privilege_type,grants.is_grantable
FROM pg_class relation_row CROSS JOIN LATERAL aclexplode(COALESCE(relation_row.relacl,acldefault('r',relation_row.relowner))) grants
WHERE relation_row.oid IN('public.eco_capabilities'::regclass,'public.eco_role_templates'::regclass,
 'public.eco_role_template_capabilities'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
 'public.eco_user_platform_role'::regclass)
ORDER BY relation_row.oid,grants.grantee,grants.privilege_type;

-- Includes inherited/PUBLIC SQL authority; RLS can separately hide all writable rows.
SELECT target.relation,actor.role_name,privilege.privilege_name,
 has_table_privilege(actor.role_name,target.relation,privilege.privilege_name) AS effective_sql_privilege
FROM unnest(ARRAY['public.eco_capabilities','public.eco_role_templates','public.eco_role_template_capabilities',
 'public.eco_platform_role_org_capabilities','public.eco_user_platform_role']) target(relation)
CROSS JOIN unnest(ARRAY['anon','authenticated','postgres','service_role']) actor(role_name)
CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']) privilege(privilege_name);

SELECT policy_row.polrelid::regclass AS relation,policy_row.polname,policy_row.polcmd,policy_row.polroles,
 policy_row.polpermissive,pg_get_expr(policy_row.polqual,policy_row.polrelid) AS using_expression,
 pg_get_expr(policy_row.polwithcheck,policy_row.polrelid) AS check_expression
FROM pg_policy policy_row WHERE policy_row.polrelid IN('public.eco_capabilities'::regclass,'public.eco_role_templates'::regclass,
 'public.eco_role_template_capabilities'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
 'public.eco_user_platform_role'::regclass);
SELECT attrelid::regclass AS relation,attname,attacl FROM pg_attribute
WHERE attrelid IN('public.eco_capabilities'::regclass,'public.eco_role_templates'::regclass,
 'public.eco_role_template_capabilities'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
 'public.eco_user_platform_role'::regclass) AND attacl IS NOT NULL;
SELECT tgrelid::regclass AS relation,tgname,tgenabled,pg_get_triggerdef(oid) AS definition
FROM pg_trigger WHERE tgrelid='public.eco_capabilities'::regclass AND NOT tgisinternal;
