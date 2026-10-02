-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY, NEVER EXECUTED BY THE AGENT.
-- Run manually BEFORE release: the reviewed mixed platform + three active tenant assignments
-- are the BEFORE fixture. Execute the actual generated UP, operational harness, and both DOWNs.
-- All effects, including those of the fixture operations, are rolled back.
BEGIN;
CREATE TEMP TABLE test_039h_before ON COMMIT DROP AS
SELECT profile_row.id AS target,
 jsonb_build_object(
 'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
 'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
 'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL)) AS legacy_before,
 (SELECT to_jsonb(assignment_row) FROM public.eco_user_platform_role assignment_row WHERE user_profile_id=profile_row.id) AS assignment,
 (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=profile_row.id) AS memberships,
 (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=profile_row.id) AS scopes,
 (SELECT to_jsonb(preset_row) FROM public.eco_role_templates preset_row WHERE code='ACCOUNTING_SUPERADMIN') AS historical_preset,
 (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_role_template_capabilities grant_row
   JOIN public.eco_role_templates preset_row ON preset_row.id=grant_row.role_template_id WHERE preset_row.code='ACCOUNTING_SUPERADMIN') AS grants,
 (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities grant_row
   JOIN public.eco_role_templates preset_row ON preset_row.id=grant_row.role_template_id WHERE preset_row.code='ACCOUNTING_SUPERADMIN') AS bridge,
 (SELECT jsonb_object_agg(signature,pg_get_functiondef(to_regprocedure(signature))) FROM (VALUES ('public.mica_admin_apply(text,jsonb)','072120b4b8571b192d97a74ab6feb710'),
('public.mica_admin_read(uuid,text)','0f86e3543d12ed320edacbadb41eeb49'),
('public.mica_invitation(text,uuid,jsonb)','9764f61728060584b722b40b40e78198'),
('private.mica_capability_allowed(text,text)','29637da1955d7528ad6a2ca958a3d677'),
('private.provision_039b_scopes()','2b28daeff21e7dcb7622e3040425848a'),
('private.trigger_039b_scopes()','0a79519bbb2f99198580ee09e5b279e1'),
('private.admin_038_authorize(uuid,text,text)','5014a1eae244e399259c8b32f47f6332'),
('private.can_operate_mica_org(uuid,text)','4b29dad32114960fde709fbff03ca18d')) checked_function(signature,hash)) AS definitions
FROM public.eco_user_profiles profile_row WHERE id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID;
DO $before_fixture$
BEGIN
 IF (SELECT count(*) FROM test_039h_before)<>1 OR EXISTS(SELECT 1 FROM test_039h_before
   WHERE jsonb_array_length(memberships) IS DISTINCT FROM 3 OR jsonb_array_length(scopes) IS DISTINCT FROM 7
    OR NOT (assignment->>'is_active')::BOOLEAN
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(memberships) reviewed_member WHERE NOT (reviewed_member->>'is_active')::BOOLEAN)) THEN
  RAISE EXCEPTION 'Expected mixed platform and active historical tenant BEFORE fixture'; END IF;
END; $before_fixture$;
-- MICA ourzapkjykzlwsjunzmd. Prepared revision 039g + 039h, ONE transaction.
-- Generated offline. Review both readonly preflights and complete the target manifest first.
-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. No SQL executed by the agent.
-- Run readonly preflight first. No identity, scope, override or authorization-function changes.
LOCK TABLE public.eco_capabilities, private.eco_owner_reserved_capabilities,
 public.eco_role_template_capabilities IN ACCESS EXCLUSIVE MODE;
DO $preflight$
DECLARE v_row RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039g requires postgres'; END IF;
 IF to_regclass('private.migration_039f_bulk_audit') IS NULL OR to_regclass('private.migration_039e_functions') IS NULL THEN
  RAISE EXCEPTION '039e and 039f required'; END IF;
 IF to_regclass('private.migration_039g_create') IS NOT NULL THEN RAISE EXCEPTION '039g already installed'; END IF;
 FOR v_row IN SELECT * FROM (VALUES ('private.guard_036_capability()','f6da0424d8ef369e9a1aa3ac606bb678'),
('private.guard_036_frozen()','64f9d84f56647a9f7e07af3336963e86'),
('private.guard_036_identity()','9a5402784e4eec7de95182228f641de4'),
('private.can_platform(text)','70b56c43ed3a35d1aed06b946be27548'),
('private.admin_038_target(uuid)','54af0f26c4fd816f9b6422e9c822c9ff'),
('private.admin_038_cap(text,text,uuid)','c3df6ced25bd7408ce8c4e33c912faea'),
('public.mica_admin_apply(text,jsonb)','072120b4b8571b192d97a74ab6feb710')) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_row.signature) AND prosecdef
   AND pg_get_userbyid(proowner)='postgres' AND proconfig=ARRAY['search_path=""']::TEXT[]
   AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v_row.hash) THEN
   RAISE EXCEPTION '039g security definition drift: %',v_row.signature; END IF;
 END LOOP;
 FOR v_row IN SELECT * FROM (VALUES ('public.eco_capabilities','guard_036_capability','private.guard_036_capability()'),
 ('private.eco_owner_reserved_capabilities','guard_036_reserved_frozen','private.guard_036_frozen()'),
 ('private.eco_platform_owner','guard_036_owner_frozen','private.guard_036_frozen()'),
 ('public.eco_user_profiles','guard_036_profile','private.guard_036_identity()'),
 ('public.eco_user_platform_role','guard_036_platform_role','private.guard_036_identity()')) x(rel,name,fn) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass(v_row.rel) AND tgname=v_row.name
    AND tgfoid=to_regprocedure(v_row.fn) AND tgenabled='O' AND NOT tgisinternal) THEN
   RAISE EXCEPTION '039g protection trigger differs: %',v_row.name; END IF;
 END LOOP;
 IF (SELECT count(*) FROM private.eco_platform_owner)<>1 THEN RAISE EXCEPTION 'Structural root required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_capabilities c JOIN private.eco_owner_reserved_capabilities r ON r.capability_id=c.id
   WHERE c.code='ORGANIZATION_CREATE' AND c.scope='PLATFORM' AND c.is_active AND c.delegation_class='OWNER_RESERVED') THEN
  RAISE EXCEPTION 'Expected reserved ORGANIZATION_CREATE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_ARCHIVE' AND delegation_class='OWNER_RESERVED' AND is_active) THEN
  RAISE EXCEPTION 'Archive must remain reserved'; END IF;
 IF (SELECT count(*) FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN' AND scope='PLATFORM' AND is_active)<>1 THEN
  RAISE EXCEPTION 'Active accounting preset required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id
   JOIN public.eco_role_templates t ON t.id=a.role_template_id WHERE a.is_active AND t.is_active AND t.scope='PLATFORM'
   AND t.code<>'ACCOUNTING_SUPERADMIN'
   AND NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role x WHERE x.role_template_id=t.id AND x.user_profile_id<>o.user_profile_id)) THEN
  RAISE EXCEPTION 'Exclusive active root preset required'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
   JOIN public.eco_role_templates t ON t.id=g.role_template_id WHERE t.code='ACCOUNTING_SUPERADMIN' AND c.delegation_class='OWNER_RESERVED') THEN
  RAISE EXCEPTION 'Accounting has unexpected reserved grants'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides o JOIN public.eco_capabilities c ON c.id=o.capability_id
   WHERE c.code='ORGANIZATION_CREATE') THEN RAISE EXCEPTION 'Review preexisting create overrides'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
   WHERE c.code='ORGANIZATION_CREATE') THEN RAISE EXCEPTION 'Review preexisting create grants'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039g_create (
 singleton BOOLEAN PRIMARY KEY CHECK(singleton), capability JSONB NOT NULL, reserved_row JSONB NOT NULL,
 root_template UUID NOT NULL, accounting_template UUID NOT NULL, installed_capability JSONB,
 installed_grants JSONB, security_functions JSONB NOT NULL, protection_triggers JSONB NOT NULL
);
ALTER TABLE private.migration_039g_create ENABLE ROW LEVEL SECURITY;
DO $acl$
DECLARE v_row RECORD;
BEGIN
 FOR v_row IN SELECT DISTINCT a.grantee FROM pg_class c,LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
  WHERE c.oid='private.migration_039g_create'::regclass AND a.grantee<>c.relowner LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.migration_039g_create FROM %s',CASE WHEN v_row.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(v_row.grantee)) END);
 END LOOP;
END; $acl$;
INSERT INTO private.migration_039g_create(singleton,capability,reserved_row,root_template,accounting_template,security_functions,protection_triggers)
SELECT TRUE,to_jsonb(c),to_jsonb(r),a.role_template_id,t.id,
 (SELECT jsonb_agg(jsonb_build_object('signature',x.signature,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'acl',to_jsonb(p.proacl)))
  FROM (VALUES ('private.guard_036_capability()','f6da0424d8ef369e9a1aa3ac606bb678'),
('private.guard_036_frozen()','64f9d84f56647a9f7e07af3336963e86'),
('private.guard_036_identity()','9a5402784e4eec7de95182228f641de4'),
('private.can_platform(text)','70b56c43ed3a35d1aed06b946be27548'),
('private.admin_038_target(uuid)','54af0f26c4fd816f9b6422e9c822c9ff'),
('private.admin_038_cap(text,text,uuid)','c3df6ced25bd7408ce8c4e33c912faea'),
('public.mica_admin_apply(text,jsonb)','072120b4b8571b192d97a74ab6feb710')) x(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(x.signature)),
 (SELECT jsonb_agg(jsonb_build_object('oid',g.oid,'definition',pg_get_triggerdef(g.oid),'enabled',g.tgenabled))
  FROM pg_trigger g JOIN (VALUES ('public.eco_capabilities','guard_036_capability','private.guard_036_capability()'),
 ('private.eco_owner_reserved_capabilities','guard_036_reserved_frozen','private.guard_036_frozen()'),
 ('private.eco_platform_owner','guard_036_owner_frozen','private.guard_036_frozen()'),
 ('public.eco_user_profiles','guard_036_profile','private.guard_036_identity()'),
 ('public.eco_user_platform_role','guard_036_platform_role','private.guard_036_identity()')) x(rel,name,fn) ON g.tgrelid=to_regclass(x.rel) AND g.tgname=x.name)
FROM public.eco_capabilities c JOIN private.eco_owner_reserved_capabilities r ON r.capability_id=c.id
CROSS JOIN private.eco_platform_owner o JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id
CROSS JOIN public.eco_role_templates t WHERE c.code='ORGANIZATION_CREATE' AND t.code='ACCOUNTING_SUPERADMIN';
-- Only these two guards are suspended under exclusive locks inside this transaction.
ALTER TABLE public.eco_capabilities DISABLE TRIGGER guard_036_capability;
ALTER TABLE private.eco_owner_reserved_capabilities DISABLE TRIGGER guard_036_reserved_frozen;
UPDATE public.eco_capabilities SET delegation_class='PLATFORM_DELEGABLE' WHERE code='ORGANIZATION_CREATE';
DELETE FROM private.eco_owner_reserved_capabilities WHERE capability_id=(SELECT (capability->>'id')::UUID FROM private.migration_039g_create);
ALTER TABLE public.eco_capabilities ENABLE TRIGGER guard_036_capability;
ALTER TABLE private.eco_owner_reserved_capabilities ENABLE TRIGGER guard_036_reserved_frozen;
INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
 SELECT t,(b.capability->>'id')::UUID FROM private.migration_039g_create b,
 LATERAL unnest(ARRAY[b.root_template,b.accounting_template]) t;
UPDATE private.migration_039g_create b SET
 installed_capability=(SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE c.id=(b.capability->>'id')::UUID),
 installed_grants=(SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_role_template_capabilities g WHERE g.capability_id=(b.capability->>'id')::UUID);
DO $postflight$
DECLARE b RECORD;
BEGIN
 SELECT * INTO STRICT b FROM private.migration_039g_create;
 IF b.installed_capability IS DISTINCT FROM b.capability||jsonb_build_object('delegation_class','PLATFORM_DELEGABLE')
  OR jsonb_array_length(b.installed_grants) IS DISTINCT FROM 2
  OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgname IN('guard_036_capability','guard_036_reserved_frozen') AND tgenabled<>'O') THEN
  RAISE EXCEPTION '039g unexpected installed state'; END IF;
END; $postflight$;

-- MICA ourzapkjykzlwsjunzmd. 039g revision part 2: operational administration.
-- PREPARED ONLY. First review readonly preflight and fill exact UUID snapshots in the manifest.
-- Apply 039g then 039h as one reviewed release. Never deploy only the first part for Marianela.
LOCK TABLE public.eco_user_platform_role,public.eco_user_profiles,public.eco_role_templates,
 public.eco_role_template_capabilities,public.eco_platform_role_org_capabilities,
 public.eco_user_platform_capability_overrides,private.eco_platform_org_overrides,
 private.eco_platform_org_scopes,public.eco_capabilities,public.eco_organization_members,
 public.eco_membership_capability_overrides,public.eco_member_capability_overrides IN ACCESS EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
DECLARE v_row RECORD; target UUID:='f922be9a-449d-417f-8003-2143fcbeef02'::UUID;
BEGIN
 IF current_user<>'postgres' OR to_regclass('private.migration_039g_create') IS NULL THEN RAISE EXCEPTION '039g required, postgres only'; END IF;
 IF to_regclass('private.migration_039h_state') IS NOT NULL THEN RAISE EXCEPTION '039h already installed'; END IF;
 -- NULL scope is legacy and deliberately ignored. Other mismatches require explicit review.
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities source_grant
   JOIN public.eco_role_templates source_template ON source_template.id=source_grant.role_template_id
   JOIN public.eco_capabilities source_capability ON source_capability.id=source_grant.capability_id
   WHERE source_capability.code='ORG_MEMBER_PERMISSION_MANAGE' AND source_template.scope IS NOT NULL
    AND (source_template.scope<>'ORGANIZATION' OR source_capability.scope<>'ORGANIZATION'))
  OR EXISTS(SELECT 1 FROM public.eco_platform_role_org_capabilities source_grant
   JOIN public.eco_role_templates source_template ON source_template.id=source_grant.role_template_id
   JOIN public.eco_capabilities source_capability ON source_capability.id=source_grant.capability_id
   WHERE source_capability.code='ORG_MEMBER_PERMISSION_MANAGE' AND source_template.scope IS NOT NULL
    AND (source_template.scope<>'PLATFORM' OR source_capability.scope<>'ORGANIZATION')) THEN
  RAISE EXCEPTION 'Unexpected non-legacy propagation scope/table'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_role_template_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()'))
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_platform_role_org_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()')) THEN RAISE EXCEPTION '036 grant guards must remain active'; END IF;
 IF target IS NULL OR '{"is_active":true,"created_at":"2026-09-16T04:57:57.750128+00:00","updated_at":"2026-09-16T04:57:57.750128+00:00","user_profile_id":"f922be9a-449d-417f-8003-2143fcbeef02","role_template_id":"1f724ba6-161e-42c2-b773-08aee636ae95"}'::JSONB IS NULL OR '{"id":"f922be9a-449d-417f-8003-2143fcbeef02","role":"SUPERADMIN","is_active":true,"created_at":"2026-08-19T12:39:25.624234+00:00","auth_user_id":"1fb0b3eb-4933-4290-afdc-a13fd1c12103","organization_id":"38419581-8163-482c-9813-616fa6214d71"}'::JSONB IS NULL THEN
  RAISE EXCEPTION 'Review readonly preflight; fill exact target manifest and regenerate before UP'; END IF;
 IF (SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=target) IS DISTINCT FROM '{"is_active":true,"created_at":"2026-09-16T04:57:57.750128+00:00","updated_at":"2026-09-16T04:57:57.750128+00:00","user_profile_id":"f922be9a-449d-417f-8003-2143fcbeef02","role_template_id":"1f724ba6-161e-42c2-b773-08aee636ae95"}'::JSONB
  OR (SELECT to_jsonb(p) FROM public.eco_user_profiles p WHERE id=target) IS DISTINCT FROM '{"id":"f922be9a-449d-417f-8003-2143fcbeef02","role":"SUPERADMIN","is_active":true,"created_at":"2026-08-19T12:39:25.624234+00:00","auth_user_id":"1fb0b3eb-4933-4290-afdc-a13fd1c12103","organization_id":"38419581-8163-482c-9813-616fa6214d71"}'::JSONB THEN
  RAISE EXCEPTION 'Target identity/assignment drift'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
    JOIN public.eco_user_profiles p ON p.id=a.user_profile_id WHERE p.id=target AND p.is_active AND a.is_active AND t.is_active AND t.code='ACCOUNTING_SUPERADMIN')
  OR EXISTS(SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=target)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=target)
  OR EXISTS(SELECT 1 FROM private.eco_platform_org_overrides WHERE user_profile_id=target) THEN
  RAISE EXCEPTION 'Target incompatible or has overrides requiring explicit review'; END IF;
 -- Reviewed identities/state, not a blanket acceptance of arbitrary tenant memberships.
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=target)<>3
  OR EXISTS(SELECT 1 FROM jsonb_to_recordset('[{"id":"43c506ef-ccd8-4e5c-8b48-a3aedd6562e5","organization_id":"38419581-8163-482c-9813-616fa6214d71","preset_code":"CONSULTANT","is_active":true},{"id":"1a4b2b8e-f411-4fdc-a73f-e2eae3d497fc","organization_id":"1f5d071f-a09e-4825-9f12-88533383599e","preset_code":"CONSULTANT","is_active":true},{"id":"27745eb5-bf76-4b59-9b01-416caef5713d","organization_id":"c7af5a5c-1aac-4add-9873-8073044bf979","preset_code":"CONSULTANT","is_active":true}]'::JSONB)
     AS expected_member(id UUID,organization_id UUID,preset_code TEXT,is_active BOOLEAN)
    WHERE NOT EXISTS(SELECT 1 FROM public.eco_organization_members member_row
      JOIN public.eco_role_templates tenant_preset ON tenant_preset.id=member_row.role_template_id
      WHERE member_row.id=expected_member.id AND member_row.user_profile_id=target
       AND member_row.organization_id=expected_member.organization_id AND member_row.is_active=expected_member.is_active
       AND tenant_preset.code=expected_member.preset_code AND tenant_preset.scope='ORGANIZATION' AND tenant_preset.is_active)) THEN
  RAISE EXCEPTION 'Reviewed membership identity/organization/preset/state drift'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides override_row JOIN public.eco_organization_members member_row
    ON member_row.id=override_row.membership_id WHERE member_row.user_profile_id=target)
  OR EXISTS(SELECT 1 FROM public.eco_member_capability_overrides legacy_override,
    LATERAL jsonb_each_text(to_jsonb(legacy_override)) legacy_field
    WHERE legacy_field.value=target::TEXT OR legacy_field.value IN(SELECT id::TEXT FROM public.eco_organization_members WHERE user_profile_id=target)) THEN
  RAISE EXCEPTION 'Unreviewed membership overrides'; END IF;
 IF (SELECT count(*) FROM private.eco_platform_org_scopes WHERE user_profile_id=target)<>7
  OR (SELECT count(*) FROM private.eco_platform_org_scopes WHERE user_profile_id=target AND is_active)<>7 THEN
  RAISE EXCEPTION 'Expected seven active explicit scopes'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_organizations o WHERE o.is_active AND NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes s
   WHERE s.user_profile_id=target AND s.organization_id=o.id AND s.is_active)) THEN RAISE EXCEPTION 'Target missing active explicit scopes'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORG_MEMBER_PRESET_ASSIGN')
  OR EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code='ADMINISTRACION_OPERATIVA_MICA') THEN RAISE EXCEPTION '039h seed collision'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
   WHERE t.code='ACCOUNTING_SUPERADMIN' AND a.is_active AND a.user_profile_id<>target)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members m JOIN public.eco_role_templates t ON t.id=m.role_template_id
   WHERE t.code='ACCOUNTING_SUPERADMIN' AND m.is_active) THEN RAISE EXCEPTION 'Accounting has other active recipients'; END IF;
 FOR v_row IN SELECT * FROM (VALUES ('public.mica_admin_apply(text,jsonb)','072120b4b8571b192d97a74ab6feb710'),
('public.mica_admin_read(uuid,text)','0f86e3543d12ed320edacbadb41eeb49'),
('public.mica_invitation(text,uuid,jsonb)','9764f61728060584b722b40b40e78198'),
('private.mica_capability_allowed(text,text)','29637da1955d7528ad6a2ca958a3d677'),
('private.provision_039b_scopes()','2b28daeff21e7dcb7622e3040425848a'),
('private.trigger_039b_scopes()','0a79519bbb2f99198580ee09e5b279e1'),
('private.admin_038_authorize(uuid,text,text)','5014a1eae244e399259c8b32f47f6332'),
('private.can_operate_mica_org(uuid,text)','4b29dad32114960fde709fbff03ca18d')) x(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(v_row.signature) AND prosecdef AND pg_get_userbyid(proowner)='postgres'
   AND proconfig=ARRAY['search_path=""']::TEXT[] AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=v_row.hash) THEN
   RAISE EXCEPTION '039h function drift: %',v_row.signature; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id
   JOIN public.eco_role_templates t ON t.id=a.role_template_id WHERE t.code='VEGEN_PLATFORM_ADMIN' AND a.is_active AND t.is_active) THEN
  RAISE EXCEPTION 'Root must retain VEGEN_PLATFORM_ADMIN'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgname IN('provision_039b_org','provision_039b_role','provision_039b_template')
    AND tgenabled='O' AND tgfoid=to_regprocedure('private.trigger_039b_scopes()'))<>3 THEN RAISE EXCEPTION 'Explicit scope triggers missing'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039h_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,installed TEXT,owner_name TEXT,acl JSONB);
CREATE TABLE private.migration_039h_state(id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id), target UUID NOT NULL,
 assignment JSONB NOT NULL,installed_assignment JSONB,scopes JSONB NOT NULL,root_state JSONB NOT NULL,
 preset UUID,capability UUID,installed_preset JSONB,installed_capability JSONB,grants JSONB,bridge JSONB,compat_grants JSONB,
 historical_preset JSONB,historical_installed JSONB,historical_grants JSONB,historical_bridge JSONB,
 memberships_before JSONB,memberships_installed JSONB,legacy_before JSONB);
ALTER TABLE private.migration_039h_functions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.migration_039h_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039h_functions,private.migration_039h_state FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039h_functions SELECT signature,pg_get_functiondef(p.oid),NULL,pg_get_userbyid(p.proowner),to_jsonb(p.proacl)
 FROM (VALUES ('public.mica_admin_apply(text,jsonb)','072120b4b8571b192d97a74ab6feb710'),
('public.mica_admin_read(uuid,text)','0f86e3543d12ed320edacbadb41eeb49'),
('public.mica_invitation(text,uuid,jsonb)','9764f61728060584b722b40b40e78198'),
('private.mica_capability_allowed(text,text)','29637da1955d7528ad6a2ca958a3d677'),
('private.provision_039b_scopes()','2b28daeff21e7dcb7622e3040425848a'),
('private.trigger_039b_scopes()','0a79519bbb2f99198580ee09e5b279e1'),
('private.admin_038_authorize(uuid,text,text)','5014a1eae244e399259c8b32f47f6332'),
('private.can_operate_mica_org(uuid,text)','4b29dad32114960fde709fbff03ca18d')) x(signature,hash) JOIN pg_proc p ON p.oid=to_regprocedure(signature);
INSERT INTO private.migration_039h_state(target,assignment,scopes,root_state)
 SELECT a.user_profile_id,to_jsonb(a),COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY organization_id) FROM private.eco_platform_org_scopes s WHERE s.user_profile_id=a.user_profile_id),'[]'),
 (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(r)) FROM private.eco_platform_owner o
  JOIN public.eco_user_profiles p ON p.id=o.user_profile_id JOIN public.eco_user_platform_role r ON r.user_profile_id=o.user_profile_id)
 FROM public.eco_user_platform_role a WHERE a.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02'::UUID;
UPDATE private.migration_039h_state b SET
 legacy_before=jsonb_build_object(
 'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
 'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
 'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL)),
 memberships_before=(SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY id),'[]') FROM public.eco_organization_members member_row WHERE user_profile_id=b.target),
 historical_preset=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.assignment->>'role_template_id')::UUID),
 historical_grants=(SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID),
 historical_bridge=(SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID);
CREATE OR REPLACE FUNCTION public.mica_admin_apply(p_action TEXT,p_data JSONB)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor UUID:=private.admin_038_actor(); org UUID:=(p_data->>'organization_id')::UUID;
  target UUID:=(p_data->>'user_profile_id')::UUID; result UUID:=(p_data->>'id')::UUID;
  tpl UUID:=(p_data->>'role_template_id')::UUID; cap UUID; member UUID;
  active BOOLEAN:=COALESCE((p_data->>'is_active')::BOOLEAN,TRUE);
  sc TEXT:=p_data->>'scope'; effect TEXT:=p_data->>'effect'; code TEXT; kind TEXT:=p_data->>'kind';
  old_org public.eco_organizations%ROWTYPE; existing RECORD; recipients INTEGER; k TEXT;
BEGIN
  IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::TEXT)>32768 THEN RAISE EXCEPTION 'Invalid payload'; END IF;
  -- Serialize before checking recipients and authority to avoid assignment races.
  PERFORM pg_advisory_xact_lock(380038);
  IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN'
    AND ((p_action='preset' AND id=result) OR (p_action IN ('platform_role','membership') AND id=tpl))) THEN
    RAISE EXCEPTION 'Deprecated preset is historical only' USING ERRCODE='42501'; END IF;
  IF NOT private.is_platform_owner() AND private.can_platform('MICA_ADMIN_MANAGE') THEN
    IF org IS NOT NULL AND NOT private.platform_org_in_scope(org) THEN RAISE EXCEPTION 'Organization outside scope' USING ERRCODE='42501'; END IF;
    IF p_action='preset' AND result IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role r WHERE r.role_template_id=result AND NOT private.admin_039b_target_visible(r.user_profile_id))
        OR EXISTS (SELECT 1 FROM public.eco_organization_members m WHERE m.role_template_id=result AND NOT private.platform_org_in_scope(m.organization_id)) THEN
        RAISE EXCEPTION 'Preset recipients outside scope' USING ERRCODE='42501'; END IF;
    END IF;
    IF p_action='platform_role' THEN
      IF EXISTS (SELECT 1 FROM private.eco_mica_all_org_presets WHERE role_template_id=tpl)
        AND EXISTS (SELECT 1 FROM public.eco_organizations o WHERE o.is_active AND NOT private.platform_org_in_scope(o.id)) THEN
        RAISE EXCEPTION 'Cannot assign all-organization preset beyond own scope' USING ERRCODE='42501'; END IF;
      FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
        PERFORM private.admin_038_cap(code,'PLATFORM',NULL); END LOOP;
      FOR code IN SELECT c.code FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
        PERFORM private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;
    END IF;
  END IF;

  IF p_action='organization' THEN
    FOR k IN SELECT jsonb_object_keys(p_data) LOOP
      IF k NOT IN ('id','name','legal_name','trade_name','tax_id','is_active') THEN RAISE EXCEPTION 'Unsupported organization field %',k; END IF;
    END LOOP;
    IF result IS NULL THEN
      PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_CREATE',NULL);
      IF length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Name required'; END IF;
      INSERT INTO public.eco_organizations(name,legal_name,trade_name,tax_id,tax_id_type,country_code,currency,timezone,is_active)
        VALUES(btrim(p_data->>'name'),COALESCE(NULLIF(p_data->>'legal_name',''),p_data->>'name'),p_data->>'trade_name',p_data->>'tax_id',
        'CUIT','AR','ARS','America/Argentina/Buenos_Aires',TRUE) RETURNING id INTO result;
    ELSE
      SELECT * INTO STRICT old_org FROM public.eco_organizations WHERE id=result FOR UPDATE;
      IF p_data ? 'is_active' THEN
        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_ARCHIVE',NULL);
      END IF;
      IF NOT p_data ?| ARRAY['name','legal_name','trade_name','tax_id','is_active'] THEN RAISE EXCEPTION 'No organization changes supplied'; END IF;
      IF p_data ?| ARRAY['name','legal_name','trade_name','tax_id'] THEN
        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_UPDATE',NULL);
        IF NOT private.is_platform_owner() AND NOT EXISTS (SELECT 1 FROM private.eco_platform_org_scopes
          WHERE user_profile_id=actor AND organization_id=result AND is_active) THEN
          RAISE EXCEPTION 'Organization outside explicit scope' USING ERRCODE='42501'; END IF;
      END IF;
      IF p_data ? 'name' AND length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Name required'; END IF;
      UPDATE public.eco_organizations SET name=COALESCE(p_data->>'name',name),
        legal_name=CASE WHEN p_data?'legal_name' THEN p_data->>'legal_name' ELSE legal_name END,
        trade_name=CASE WHEN p_data?'trade_name' THEN p_data->>'trade_name' ELSE trade_name END,
        tax_id=CASE WHEN p_data?'tax_id' THEN p_data->>'tax_id' ELSE tax_id END,
        is_active=CASE WHEN p_data?'is_active' THEN active ELSE is_active END WHERE id=result;
    END IF;
  ELSIF p_action='preset' THEN
    PERFORM private.admin_038_authorize(org,'PLATFORM_MANAGE','ORG_MEMBER_PERMISSION_MANAGE');
    IF sc NOT IN ('PLATFORM','ORGANIZATION') OR sc IS NULL OR (sc='PLATFORM' AND org IS NOT NULL) THEN RAISE EXCEPTION 'Invalid preset scope'; END IF;
    IF length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Preset name required'; END IF;
    IF jsonb_typeof(p_data->'capabilities') IS DISTINCT FROM 'array' OR
       jsonb_typeof(p_data->'bridge') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Capability arrays required'; END IF;
    IF sc='ORGANIZATION' AND jsonb_array_length(p_data->'bridge')<>0 THEN RAISE EXCEPTION 'Bridge requires PLATFORM'; END IF;
    IF sc='ORGANIZATION' AND (p_data->'capabilities') ? 'RECORD_RESTORE' THEN
      RAISE EXCEPTION 'Restore requires a MICA platform preset bridge' USING ERRCODE='42501'; END IF;
    IF result IS NOT NULL THEN
      SELECT t.scope,r.organization_id INTO STRICT existing FROM private.eco_mica_presets r
        JOIN public.eco_role_templates t ON t.id=r.role_template_id WHERE t.id=result FOR UPDATE OF t;
      IF existing.scope<>sc OR existing.organization_id IS DISTINCT FROM org THEN RAISE EXCEPTION 'Preset scope is immutable'; END IF;
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role r JOIN private.eco_platform_owner o ON o.user_profile_id=r.user_profile_id WHERE r.role_template_id=result)
        OR EXISTS (SELECT 1 FROM public.eco_organization_members m JOIN private.eco_platform_owner o ON o.user_profile_id=m.user_profile_id WHERE m.role_template_id=result)
        THEN RAISE EXCEPTION 'Root preset protected' USING ERRCODE='42501'; END IF;
      SELECT (SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id=result)+
        (SELECT count(*) FROM public.eco_organization_members WHERE role_template_id=result) INTO recipients;
      IF recipients>0 AND (p_data->>'expected_recipients')::INTEGER IS DISTINCT FROM recipients THEN
        RAISE EXCEPTION 'Confirm current preset recipient count: %',recipients; END IF;
      IF org IS NOT NULL AND EXISTS (SELECT 1 FROM public.eco_organization_members WHERE role_template_id=result AND organization_id<>org)
        THEN RAISE EXCEPTION 'Preset has recipients outside organization' USING ERRCODE='42501'; END IF;
    ELSE
      result:=gen_random_uuid();
      INSERT INTO public.eco_role_templates(id,code,name,scope,is_system,is_active)
        VALUES(result,'MICA_'||replace(result::TEXT,'-',''),p_data->>'name',sc,FALSE,active);
      INSERT INTO private.eco_mica_presets VALUES(result,org);
    END IF;
    FOR code IN SELECT jsonb_array_elements_text(p_data->'capabilities') LOOP
      PERFORM private.admin_038_cap(code,sc,org);
    END LOOP;
    FOR code IN SELECT jsonb_array_elements_text(p_data->'bridge') LOOP
      PERFORM private.admin_038_cap(code,'ORGANIZATION',org);
    END LOOP;
    DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=result;
    DELETE FROM public.eco_platform_role_org_capabilities WHERE role_template_id=result;
    INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
      SELECT DISTINCT result,private.admin_038_cap(value,sc,org) FROM jsonb_array_elements_text(p_data->'capabilities');
    INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
      SELECT DISTINCT result,private.admin_038_cap(value,'ORGANIZATION',org) FROM jsonb_array_elements_text(p_data->'bridge');
    UPDATE public.eco_role_templates SET name=p_data->>'name',is_active=active,updated_at=now() WHERE id=result;
  ELSIF p_action IN ('user','platform_role','membership','scope','override') THEN
    PERFORM private.admin_038_target(target);
    IF p_action='membership' THEN
      PERFORM private.admin_038_authorize(org,'GLOBAL_USER_MANAGE','ORG_MEMBER_MANAGE');
      IF org IS NULL THEN RAISE EXCEPTION 'Membership requires organization'; END IF;
      PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PRESET_ASSIGN');
      IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN
        RAISE EXCEPTION 'Platform user requires explicit scopes, not artificial membership'; END IF;
    ELSIF p_action='override' AND kind='membership' THEN
      IF org IS NULL THEN RAISE EXCEPTION 'Membership override requires organization'; END IF;
      PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');
    ELSE
      PERFORM private.admin_038_authorize(NULL,'GLOBAL_USER_MANAGE',NULL);
    END IF;
    IF p_action IN ('platform_role','membership') THEN
      SELECT t.scope,r.organization_id INTO STRICT existing FROM private.eco_mica_presets r
        JOIN public.eco_role_templates t ON t.id=r.role_template_id WHERE t.id=tpl AND t.is_active;
      IF (p_action='platform_role' AND (existing.scope<>'PLATFORM' OR org IS NOT NULL))
        OR (p_action='membership' AND (existing.scope<>'ORGANIZATION' OR
          (existing.organization_id IS NOT NULL AND existing.organization_id<>org))) THEN RAISE EXCEPTION 'Incompatible preset'; END IF;
      IF p_action='membership' THEN
        FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
          PERFORM private.admin_038_cap(code,'ORGANIZATION',org);
        END LOOP;
        IF NOT EXISTS (SELECT 1 FROM public.eco_organization_members WHERE organization_id=org AND user_profile_id=target) THEN
          PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_INVITE'); END IF;
        INSERT INTO public.eco_organization_members(organization_id,user_profile_id,role_template_id,is_active)
          VALUES(org,target,tpl,active) ON CONFLICT(organization_id,user_profile_id)
          DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=EXCLUDED.is_active RETURNING id INTO result;
      ELSE
        IF EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active) THEN
          RAISE EXCEPTION 'Deactivate tenant memberships before platform assignment'; END IF;
        INSERT INTO public.eco_user_platform_role(user_profile_id,role_template_id,is_active) VALUES(target,tpl,active)
          ON CONFLICT(user_profile_id) DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=EXCLUDED.is_active;
        result:=target;
      END IF;
    ELSIF p_action='scope' THEN
      IF org IS NULL OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=org AND is_active)
        OR NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN RAISE EXCEPTION 'Active organization and platform assignment required'; END IF;
      INSERT INTO private.eco_platform_org_scopes(user_profile_id,organization_id,is_active) VALUES(target,org,active)
        ON CONFLICT(user_profile_id,organization_id) DO UPDATE SET is_active=EXCLUDED.is_active;
      result:=target;
    ELSIF p_action='override' THEN
      IF effect IS NULL OR effect NOT IN ('ALLOW','DENY','INHERITED') OR kind IS NULL OR kind NOT IN ('platform','membership','platform_org') THEN RAISE EXCEPTION 'Invalid override'; END IF;
      IF p_data->>'capability'='DATA_RESTORE_ANY_ORG' AND effect='ALLOW' AND
        (kind<>'platform' OR NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a
          JOIN public.eco_role_templates t ON t.id=a.role_template_id
          WHERE a.user_profile_id=target AND a.is_active AND t.is_active AND t.scope='PLATFORM')
          OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active)) THEN
        RAISE EXCEPTION 'Restore platform delegation requires a MICA platform recipient, never a tenant' USING ERRCODE='42501'; END IF;
      cap:=private.admin_038_cap(p_data->>'capability',CASE WHEN kind='platform' THEN 'PLATFORM' ELSE 'ORGANIZATION' END,
        CASE WHEN kind='membership' THEN org ELSE NULL END);
      IF kind='membership' THEN
        SELECT id INTO STRICT member FROM public.eco_organization_members WHERE organization_id=org AND user_profile_id=target;
        DELETE FROM public.eco_membership_capability_overrides WHERE membership_id=member AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO public.eco_membership_capability_overrides(membership_id,capability_id,effect) VALUES(member,cap,effect); END IF;
      ELSIF kind='platform_org' THEN
        IF NOT EXISTS (SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=target AND organization_id=org AND is_active)
          OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=org AND is_active) THEN RAISE EXCEPTION 'Explicit active scope required'; END IF;
        DELETE FROM private.eco_platform_org_overrides WHERE user_profile_id=target AND organization_id=org AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO private.eco_platform_org_overrides VALUES(target,org,cap,effect,now()); END IF;
      ELSE
        IF org IS NOT NULL THEN RAISE EXCEPTION 'Platform override cannot name a tenant'; END IF;
        DELETE FROM public.eco_user_platform_capability_overrides WHERE user_profile_id=target AND capability_id=cap;
        IF effect<>'INHERITED' THEN INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect) VALUES(target,cap,effect); END IF;
      END IF;
      result:=target;
    ELSE
      IF active AND NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active)
        AND NOT EXISTS (SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND is_active) THEN
        RAISE EXCEPTION 'Assign an active preset and scope before approval'; END IF;
      UPDATE public.eco_user_profiles SET is_active=active WHERE id=target;
      IF active AND EXISTS (SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=target AND approved_at IS NULL) THEN
        IF EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN
          org:=NULL;
        ELSE
          IF org IS NULL THEN
            IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=target AND is_active)<>1 THEN
              RAISE EXCEPTION 'Select the initial organization for this pending user'; END IF;
            SELECT organization_id INTO org FROM public.eco_organization_members WHERE user_profile_id=target AND is_active;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM public.eco_organization_members m JOIN public.eco_organizations o ON o.id=m.organization_id
            WHERE m.user_profile_id=target AND m.organization_id=org AND m.is_active AND o.is_active) THEN
            RAISE EXCEPTION 'Initial context requires an active membership and organization'; END IF;
        END IF;
        INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(target,org)
          ON CONFLICT(user_profile_id) DO UPDATE SET organization_id=EXCLUDED.organization_id,updated_at=now();
        UPDATE public.eco_user_profiles SET organization_id=org WHERE id=target;
        UPDATE private.eco_mica_pending_profiles SET approved_at=now() WHERE user_profile_id=target;
      END IF;
      result:=target;
    END IF;
  ELSIF p_action='tenant_activate' THEN
    PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_MANAGE');
    PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PRESET_ASSIGN');
    PERFORM private.admin_038_target(target);
    IF org IS NULL OR NOT EXISTS(SELECT 1 FROM public.eco_organization_members
      WHERE user_profile_id=target AND organization_id=org AND is_active)
      OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target)
      OR NOT EXISTS(SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=target AND approved_at IS NULL)
      OR NOT EXISTS(SELECT 1 FROM private.eco_mica_invitations WHERE assigned_to=target AND organization_id=org AND assigned_at IS NOT NULL)
      OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=target AND organization_id<>org)
      OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
        WHERE p.id=target AND NOT p.is_active AND u.email_confirmed_at IS NOT NULL) THEN
      RAISE EXCEPTION 'Only an invited confirmed pending tenant may be initially activated' USING ERRCODE='42501'; END IF;
    UPDATE public.eco_user_profiles SET is_active=TRUE,organization_id=org WHERE id=target;
    INSERT INTO public.eco_user_active_context(user_profile_id,organization_id) VALUES(target,org)
      ON CONFLICT(user_profile_id) DO UPDATE SET organization_id=EXCLUDED.organization_id,updated_at=now();
    UPDATE private.eco_mica_pending_profiles SET approved_at=now() WHERE user_profile_id=target;
    result:=target;
  ELSE RAISE EXCEPTION 'Unknown administration action';
  END IF;
  INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,target_user_profile_id,metadata)
    VALUES(actor,'MICA_ADMIN_'||upper(p_action),target,jsonb_build_object('organization_id',org,'target_id',result,'changes',p_data));
  RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.mica_admin_read(p_org UUID DEFAULT NULL,p_search TEXT DEFAULT '')
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor(); global_users BOOLEAN:=COALESCE(private.admin_039b_users(),FALSE);
  users_allowed BOOLEAN; presets_allowed BOOLEAN; result JSONB;
BEGIN
  IF length(COALESCE(p_search,''))>100 THEN RAISE EXCEPTION 'Search too long'; END IF;
  IF p_org IS NOT NULL AND (NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=actor AND organization_id=p_org)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org AND is_active)) THEN
    RAISE EXCEPTION 'Confirmed active tenant context required' USING ERRCODE='42501'; END IF;
  users_allowed:=global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_VIEW'),FALSE));
  presets_allowed:=COALESCE(private.admin_039b_presets(),FALSE)
    OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE));
  SELECT jsonb_build_object(
    'rights',jsonb_build_object(
      'organizations',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'create_organization',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE),
      'update_organization',COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE),
      'archive_organization',COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'users',users_allowed,'global_users',global_users,'presets',presets_allowed,
      'global_presets',COALESCE(private.admin_039b_presets(),FALSE),
      'assignments',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)),
      'memberships',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PRESET_ASSIGN'),FALSE)
        AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_MANAGE'),FALSE))),
    'organizations',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'legal_name',legal_name,'trade_name',trade_name,'tax_id',tax_id,'is_active',is_active))
      FROM (SELECT o.* FROM public.eco_organizations o WHERE
        ((COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE) OR global_users)
          AND (private.is_platform_owner() OR EXISTS (SELECT 1 FROM private.eco_platform_org_scopes s WHERE s.organization_id=o.id AND s.user_profile_id=actor AND s.is_active)))
        OR (o.id=p_org AND COALESCE(private.can_operate_mica_org(p_org,'ORG_VIEW'),FALSE))
        ORDER BY o.name,o.id LIMIT 250) q),'[]'::JSONB),
    'users',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'email',email,'is_active',is_active,'protected',protected,'pending',pending))
      FROM (SELECT p.id,u.email,p.is_active,EXISTS(SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=p.id) AS protected,
        EXISTS(SELECT 1 FROM private.eco_mica_pending_profiles WHERE user_profile_id=p.id AND approved_at IS NULL) AS pending
        FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
        WHERE users_allowed AND private.admin_039b_target_visible(p.id) AND (global_users OR EXISTS (SELECT 1 FROM public.eco_organization_members m WHERE m.user_profile_id=p.id AND m.organization_id=p_org))
          AND (COALESCE(p_search,'')='' OR strpos(lower(COALESCE(u.email,'')),lower(p_search))>0)
        ORDER BY u.email,p.id LIMIT 200) q),'[]'::JSONB),
    'capabilities',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',code,'scope',scope,'description',description) ORDER BY scope,code)
      FROM public.eco_capabilities WHERE (presets_allowed OR users_allowed) AND is_active AND delegation_class<>'OWNER_RESERVED'
        AND private.mica_capability_allowed(code,scope) AND (scope='ORGANIZATION' OR global_users OR COALESCE(private.admin_039b_presets(),FALSE))),'[]'::JSONB),
    'presets',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'scope',t.scope,'organization_id',r.organization_id,'is_active',t.is_active,
      'recipients',(SELECT count(*) FROM public.eco_organization_members WHERE role_template_id=t.id)+(SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id=t.id),
      'capabilities',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB),
      'bridge',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB)))
      FROM private.eco_mica_presets r JOIN public.eco_role_templates t ON t.id=r.role_template_id
      WHERE (presets_allowed OR users_allowed) AND (global_users OR COALESCE(private.admin_039b_presets(),FALSE) OR
        (t.scope='ORGANIZATION' AND (r.organization_id IS NULL OR r.organization_id=p_org)))),'[]'::JSONB)
  ) INTO result;
  -- Assignment rows are restricted to the same bounded visible user set.
  result := result || jsonb_build_object(
    'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',x.user_profile_id,'organization_id',x.organization_id)) FROM public.eco_user_active_context x WHERE x.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v) AND (global_users OR x.organization_id=p_org)), '[]'::JSONB),
    'memberships',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',m.id,'user_profile_id',m.user_profile_id,'organization_id',m.organization_id,'role_template_id',m.role_template_id,'is_active',m.is_active))
      FROM public.eco_organization_members m WHERE (global_users OR m.organization_id=p_org) AND m.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'platform_roles',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',r.user_profile_id,'role_template_id',r.role_template_id,'is_active',r.is_active))
      FROM public.eco_user_platform_role r WHERE global_users AND r.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'scopes',COALESCE((SELECT jsonb_agg(jsonb_build_object('user_profile_id',s.user_profile_id,'organization_id',s.organization_id,'is_active',s.is_active))
      FROM private.eco_platform_org_scopes s WHERE global_users AND s.user_profile_id IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB),
    'overrides',COALESCE((SELECT jsonb_agg(jsonb_build_object('kind',q.kind,'user_profile_id',q.profile,'organization_id',q.org,'capability',c.code,'effect',q.effect))
      FROM (
        SELECT 'platform' AS kind,user_profile_id AS profile,NULL::UUID AS org,capability_id,effect FROM public.eco_user_platform_capability_overrides WHERE global_users
        UNION ALL SELECT 'platform_org',user_profile_id,organization_id,capability_id,effect FROM private.eco_platform_org_overrides WHERE global_users
        UNION ALL SELECT 'membership',m.user_profile_id,m.organization_id,o.capability_id,o.effect FROM public.eco_membership_capability_overrides o
          JOIN public.eco_organization_members m ON m.id=o.membership_id WHERE global_users OR m.organization_id=p_org
      ) q JOIN public.eco_capabilities c ON c.id=q.capability_id
      WHERE c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)
        AND q.profile IN(SELECT (v->>'id')::UUID FROM jsonb_array_elements(result->'users') v)),'[]'::JSONB));
-- Presentation rights derive from effective authority, never a preset name or email.
  IF NOT global_users AND NOT COALESCE(private.admin_039b_presets(),FALSE)
    AND NOT COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE) THEN
    result:=result||jsonb_build_object('capabilities','[]'::JSONB,'overrides','[]'::JSONB,
      'presets',COALESCE((SELECT jsonb_agg(p-'capabilities'-'bridge'-'recipients') FROM jsonb_array_elements(result->'presets') p
        WHERE p->>'scope'='ORGANIZATION' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(p->'capabilities') c(code)
          WHERE NOT COALESCE(private.can_operate_mica_org(p_org,c.code),FALSE))),'[]'::JSONB),
      'rights',(result->'rights')||jsonb_build_object('operational_admin',TRUE,'presets',FALSE,'assignments',FALSE));
  END IF;
  RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.mica_invitation(p_action TEXT,p_org UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor(); tpl UUID; target UUID; v_email TEXT; result UUID; sc TEXT; tpl_org UUID;
 invitation private.eco_mica_invitations%ROWTYPE; code TEXT;
BEGIN
 PERFORM private.admin_038_authorize(p_org,'GLOBAL_USER_MANAGE','ORG_MEMBER_INVITE');
 IF p_org IS NOT NULL THEN PERFORM private.admin_038_authorize(p_org,NULL,'ORG_MEMBER_PRESET_ASSIGN'); END IF;
 IF NOT private.is_platform_owner() AND private.can_platform('MICA_ADMIN_MANAGE') AND p_org IS NOT NULL
  AND NOT private.platform_org_in_scope(p_org) THEN RAISE EXCEPTION 'Invitation outside scope' USING ERRCODE='42501'; END IF;
 IF p_action='list' THEN
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(i)||jsonb_build_object('user_profile_id',p.id,'pending',p.is_active=FALSE))
   FROM private.eco_mica_invitations i LEFT JOIN auth.users u ON lower(u.email)=i.email AND u.email_confirmed_at IS NOT NULL
   LEFT JOIN public.eco_user_profiles p ON p.auth_user_id=u.id
   WHERE i.organization_id IS NOT DISTINCT FROM p_org
     AND (p.id IS NULL OR private.admin_039b_target_visible(p.id))),'[]'::JSONB);
 END IF;
 PERFORM pg_advisory_xact_lock(380038);
 IF p_action='assign' THEN
  SELECT * INTO STRICT invitation FROM private.eco_mica_invitations WHERE id=(p_data->>'id')::UUID
   AND organization_id IS NOT DISTINCT FROM p_org FOR UPDATE;
  IF invitation.assigned_at IS NOT NULL THEN RAISE EXCEPTION 'Invitation already assigned'; END IF;
  SELECT p.id INTO STRICT target FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
   WHERE lower(u.email)=invitation.email AND u.email_confirmed_at IS NOT NULL AND NOT p.is_active;
  IF target IS DISTINCT FROM (p_data->>'user_profile_id')::UUID THEN RAISE EXCEPTION 'Review pending identity again'; END IF;
  PERFORM private.admin_038_target(target);
  PERFORM public.mica_admin_apply(CASE WHEN p_org IS NULL THEN 'platform_role' ELSE 'membership' END,
   jsonb_build_object('user_profile_id',target,'role_template_id',invitation.role_template_id,'organization_id',p_org,'is_active',TRUE));
  UPDATE private.eco_mica_invitations SET assigned_to=target,assigned_at=now() WHERE id=invitation.id;
  -- Activation is deliberately separate and uses mica_admin_apply('user').
  RETURN jsonb_build_object('user_profile_id',target,'assigned',TRUE,'activated',FALSE);
 END IF;
 IF p_action IS DISTINCT FROM 'create' OR jsonb_typeof(p_data) IS DISTINCT FROM 'object' OR octet_length(p_data::TEXT)>2048 THEN RAISE EXCEPTION 'Invalid invitation'; END IF;
 v_email:=lower(btrim(p_data->>'email')); tpl:=(p_data->>'role_template_id')::UUID;
 IF v_email IS NULL OR length(v_email)>254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid email'; END IF;
 IF EXISTS(SELECT 1 FROM auth.users WHERE lower(auth.users.email)=v_email) THEN RAISE EXCEPTION 'Email already registered: use Usuarios and Asignaciones'; END IF;
 SELECT t.scope,m.organization_id INTO STRICT sc,tpl_org FROM public.eco_role_templates t
  JOIN private.eco_mica_presets m ON m.role_template_id=t.id WHERE t.id=tpl AND t.is_active;
 IF (p_org IS NULL AND sc<>'PLATFORM') OR (p_org IS NOT NULL AND sc<>'ORGANIZATION')
  OR (tpl_org IS NOT NULL AND tpl_org IS DISTINCT FROM p_org)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id WHERE a.role_template_id=tpl) THEN
  RAISE EXCEPTION 'Incompatible or protected preset' USING ERRCODE='42501'; END IF;
 FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
  PERFORM private.admin_038_cap(code,sc,p_org); END LOOP;
 FOR code IN SELECT c.code FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE g.role_template_id=tpl LOOP
  PERFORM private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;
 INSERT INTO private.eco_mica_invitations(email,organization_id,role_template_id,created_by) VALUES(v_email,p_org,tpl,actor) RETURNING id INTO result;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'MICA_INVITATION_PENDING',jsonb_build_object('invitation_id',result,'organization_id',p_org));
 RETURN jsonb_build_object('id',result,'status','PENDING_AUTHENTICATION');
END; $$;

CREATE OR REPLACE FUNCTION private.mica_capability_allowed(p_code TEXT,p_scope TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM (VALUES
    ('ORG_MEMBER_PRESET_ASSIGN','ORGANIZATION'),
    ('FISCAL_DOCUMENT_IMPORT','ORGANIZATION'),
    ('DATA_RESTORE_ANY_ORG','PLATFORM'),
    ('MICA_ADMIN_MANAGE','PLATFORM'),
    ('PLATFORM_MANAGE','PLATFORM'),
    ('GLOBAL_USER_MANAGE','PLATFORM'),
    ('PLAN_MANAGE','PLATFORM'),
    ('ACCESS_ANY_ORG','PLATFORM'),
    ('SUPPORT_IMPERSONATE','PLATFORM'),
    ('HARD_DELETE_EXCEPTIONAL','PLATFORM'),
    ('ORGANIZATION_CREATE','PLATFORM'),
    ('ORGANIZATION_UPDATE','PLATFORM'),
    ('ORGANIZATION_ARCHIVE','PLATFORM'),
    ('PLATFORM_MIGRATIONS_APPLY','PLATFORM'),
    ('PLATFORM_TENANTS_PROVISION','PLATFORM'),
    ('PLATFORM_SYSTEM_MONITOR','PLATFORM'),
    ('GLOBAL_CATALOG_VIEW','PLATFORM'),
    ('GLOBAL_CATALOG_MANAGE','PLATFORM'),
    ('CATALOG_ASSIGN_ANY_ORG','PLATFORM'),
    ('RATE_MANAGE_ANY_ORG','PLATFORM'),
    ('REPORT_COMPARE_SCOPED_ORGS','PLATFORM'),
    ('REPORT_CONSOLIDATED_SCOPED_ORGS','PLATFORM'),
    ('SAAS_ANALYTICS_VIEW','PLATFORM'),
    ('AUDIT_PLATFORM_VIEW','PLATFORM'),
    ('ORG_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_VIEW','ORGANIZATION'),
    ('ORG_SETTINGS_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_VIEW','ORGANIZATION'),
    ('ORG_MEMBER_INVITE','ORGANIZATION'),
    ('ORG_MEMBER_MANAGE','ORGANIZATION'),
    ('ORG_MEMBER_PERMISSION_MANAGE','ORGANIZATION'),
    ('IMPORT_VIEW','ORGANIZATION'),
    ('IMPORT_CREATE','ORGANIZATION'),
    ('IMPORT_RETRY','ORGANIZATION'),
    ('IMPORT_REVIEW','ORGANIZATION'),
    ('RECORD_VIEW','ORGANIZATION'),
    ('RECORD_CLASSIFY','ORGANIZATION'),
    ('RECORD_SOFT_DELETE','ORGANIZATION'),
    ('RECORD_RESTORE','ORGANIZATION'),
    ('PERCEPTION_IMPORT','ORGANIZATION'),
    ('BANK_IMPORT','ORGANIZATION'),
    ('PAYROLL_IMPORT','ORGANIZATION'),
    ('ISSUE_RESOLVE','ORGANIZATION'),
    ('CATALOG_ORG_VIEW','ORGANIZATION'),
    ('CATALOG_ACTIVITY_MANAGE','ORGANIZATION'),
    ('CATALOG_CATEGORY_MANAGE','ORGANIZATION'),
    ('REPORT_VIEW','ORGANIZATION'),
    ('REPORT_EXPORT','ORGANIZATION'),
    ('TICKET_CREATE','ORGANIZATION'),
    ('TICKET_VIEW_ORG','ORGANIZATION'),
    ('AUDIT_VIEW_ORG','ORGANIZATION'),
    ('FINANCIAL_ALLOCATION_EDIT','ORGANIZATION'),
    ('SENSITIVEDATA_BANKING_READ','ORGANIZATION'),
    ('SENSITIVEDATA_SALARIES_READ','ORGANIZATION'),
    ('DOCUMENTS_UPLOAD','ORGANIZATION'),
    ('DOCUMENTS_OCR_PROCESS','ORGANIZATION'),
    ('DOCUMENTS_OCR_VERIFY','ORGANIZATION'),
    ('PURCHASES_INVOICES_MANAGE','ORGANIZATION'),
    ('SUPPLIERS_VIEW','ORGANIZATION'),
    ('SUPPLIERS_MANAGE','ORGANIZATION'),
    ('SALES_VIEW','ORGANIZATION'),
    ('PERSONNEL_EMPLOYEES_MANAGE','ORGANIZATION'),
    ('INTEGRATIONS_CONFIG_MANAGE','ORGANIZATION'),
    ('INTEGRATIONS_SYNC_TRIGGER','ORGANIZATION'),
    ('MANUAL_MOVEMENT_VIEW','ORGANIZATION'),
    ('MANUAL_MOVEMENT_CREATE','ORGANIZATION'),
    ('MANUAL_MOVEMENT_EDIT','ORGANIZATION'),
    ('MANUAL_MOVEMENT_SOFT_DELETE','ORGANIZATION')
  ) allowed(code,scope) WHERE code=p_code AND scope=p_scope);
$$;
DO $seed$
DECLARE cap UUID; tpl UUID; b RECORD;
BEGIN
 SELECT * INTO STRICT b FROM private.migration_039h_state;
 INSERT INTO public.eco_capabilities(code,description,scope,delegation_class,is_active)
 VALUES('ORG_MEMBER_PRESET_ASSIGN','Asignar un preset tenant existente, sin editar permisos','ORGANIZATION','ORGANIZATION_DELEGABLE',TRUE) RETURNING id INTO cap;
 INSERT INTO public.eco_role_templates(code,name,scope,is_system,is_active)
 VALUES('ADMINISTRACION_OPERATIVA_MICA','Administración operativa MICA','PLATFORM',FALSE,TRUE) RETURNING id INTO tpl;
 INSERT INTO private.eco_mica_presets VALUES(tpl,NULL);
 INSERT INTO private.eco_mica_all_org_presets VALUES(tpl);
 INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
 SELECT tpl,id FROM public.eco_capabilities WHERE code=ANY(ARRAY['ORGANIZATION_CREATE','ORGANIZATION_UPDATE','GLOBAL_CATALOG_VIEW','GLOBAL_CATALOG_MANAGE','CATALOG_ASSIGN_ANY_ORG','RATE_MANAGE_ANY_ORG','DATA_RESTORE_ANY_ORG','REPORT_COMPARE_SCOPED_ORGS','REPORT_CONSOLIDATED_SCOPED_ORGS']::TEXT[]) AND is_active AND scope='PLATFORM' AND delegation_class='PLATFORM_DELEGABLE';
 IF (SELECT count(*) FROM public.eco_role_template_capabilities WHERE role_template_id=tpl)<>9 THEN RAISE EXCEPTION 'Platform seed incomplete'; END IF;
 INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
 SELECT tpl,id FROM public.eco_capabilities WHERE code=ANY(ARRAY['ORG_VIEW','ORG_SETTINGS_VIEW','ORG_SETTINGS_MANAGE','ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','IMPORT_VIEW','IMPORT_CREATE','IMPORT_RETRY','IMPORT_REVIEW','RECORD_VIEW','RECORD_CLASSIFY','RECORD_SOFT_DELETE','RECORD_RESTORE','PERCEPTION_IMPORT','BANK_IMPORT','PAYROLL_IMPORT','ISSUE_RESOLVE','CATALOG_ORG_VIEW','CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','REPORT_VIEW','REPORT_EXPORT','TICKET_CREATE','TICKET_VIEW_ORG','AUDIT_VIEW_ORG','FINANCIAL_ALLOCATION_EDIT','SENSITIVEDATA_BANKING_READ','SENSITIVEDATA_SALARIES_READ','DOCUMENTS_UPLOAD','DOCUMENTS_OCR_PROCESS','DOCUMENTS_OCR_VERIFY','PURCHASES_INVOICES_MANAGE','SUPPLIERS_VIEW','SUPPLIERS_MANAGE','SALES_VIEW','PERSONNEL_EMPLOYEES_MANAGE','INTEGRATIONS_CONFIG_MANAGE','INTEGRATIONS_SYNC_TRIGGER','MANUAL_MOVEMENT_VIEW','MANUAL_MOVEMENT_CREATE','MANUAL_MOVEMENT_EDIT','MANUAL_MOVEMENT_SOFT_DELETE','FISCAL_DOCUMENT_IMPORT','ORG_MEMBER_PRESET_ASSIGN']::TEXT[]) AND is_active AND scope='ORGANIZATION';
 IF (SELECT count(*) FROM public.eco_platform_role_org_capabilities WHERE role_template_id=tpl)<>45 THEN RAISE EXCEPTION 'Bridge seed incomplete'; END IF;
 -- Preserve existing tenant managers and root after separating assignment from permission editing.
 INSERT INTO public.eco_role_template_capabilities(role_template_id,capability_id)
 SELECT g.role_template_id,cap FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
 JOIN public.eco_role_templates source_template ON source_template.id=g.role_template_id
 WHERE c.code='ORG_MEMBER_PERMISSION_MANAGE' AND c.scope='ORGANIZATION' AND source_template.scope='ORGANIZATION'
  AND g.role_template_id<>(b.assignment->>'role_template_id')::UUID;
 INSERT INTO public.eco_platform_role_org_capabilities(role_template_id,capability_id)
 SELECT g.role_template_id,cap FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
 JOIN public.eco_role_templates source_template ON source_template.id=g.role_template_id
 WHERE c.code='ORG_MEMBER_PERMISSION_MANAGE' AND c.scope='ORGANIZATION' AND source_template.scope='PLATFORM'
  AND g.role_template_id<>(b.assignment->>'role_template_id')::UUID;
 -- Preserve historical rows and presets; normalize only the three reviewed active flags.
 UPDATE public.eco_organization_members SET is_active=FALSE WHERE user_profile_id=b.target
  AND id IN(SELECT (saved_member->>'id')::UUID FROM jsonb_array_elements(b.memberships_before) saved_member);
 UPDATE public.eco_user_platform_role SET role_template_id=tpl WHERE user_profile_id=b.target;
 -- Deprecate only after reassignment; preserve the historical preset and every grant row.
 IF EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=(b.assignment->>'role_template_id')::UUID AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=(b.assignment->>'role_template_id')::UUID AND is_active) THEN
  RAISE EXCEPTION 'Cannot deprecate accounting with active recipients'; END IF;
 UPDATE public.eco_role_templates SET is_active=FALSE WHERE id=(b.assignment->>'role_template_id')::UUID;
 UPDATE private.migration_039h_state SET preset=tpl,capability=cap,
 memberships_installed=(SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=b.target),
 historical_installed=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=(b.assignment->>'role_template_id')::UUID),
 installed_assignment=(SELECT to_jsonb(a) FROM public.eco_user_platform_role a WHERE user_profile_id=b.target),
 installed_preset=(SELECT to_jsonb(t) FROM public.eco_role_templates t WHERE id=tpl),
 installed_capability=(SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE id=cap),
 grants=(SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_role_template_capabilities g WHERE role_template_id=tpl),
 bridge=(SELECT jsonb_agg(to_jsonb(g) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=tpl),
 compat_grants=(SELECT jsonb_build_object('tenant',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_role_template_capabilities g WHERE capability_id=cap),'[]'),
 'platform',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) FROM public.eco_platform_role_org_capabilities g WHERE capability_id=cap),'[]')));
 IF b.scopes IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY organization_id),'[]') FROM private.eco_platform_org_scopes s WHERE user_profile_id=b.target) THEN RAISE EXCEPTION 'Existing scopes changed'; END IF;
 IF b.legacy_before IS DISTINCT FROM jsonb_build_object(
 'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
 'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
 'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL)) THEN RAISE EXCEPTION 'Legacy templates or grants changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_role_template_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()'))
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.eco_platform_role_org_capabilities'::regclass
   AND tgname='guard_036_grant' AND tgenabled='O' AND tgfoid=to_regprocedure('private.guard_036_grant()')) THEN RAISE EXCEPTION '036 grant guards must remain active'; END IF;
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=b.target)<>3
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=b.target AND is_active)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(b.memberships_before) saved_member WHERE NOT EXISTS(
    SELECT 1 FROM public.eco_organization_members member_row WHERE member_row.id=(saved_member->>'id')::UUID
     AND member_row.user_profile_id=b.target AND member_row.organization_id=(saved_member->>'organization_id')::UUID
     AND member_row.role_template_id=(saved_member->>'role_template_id')::UUID)) THEN
  RAISE EXCEPTION 'Membership normalization changed identity or left active tenants'; END IF;
 IF b.historical_grants IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID)
  OR b.historical_bridge IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=(b.assignment->>'role_template_id')::UUID) THEN
  RAISE EXCEPTION 'Historical accounting grants changed'; END IF;
 IF b.root_state IS DISTINCT FROM (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(r)) FROM private.eco_platform_owner o
 JOIN public.eco_user_profiles p ON p.id=o.user_profile_id JOIN public.eco_user_platform_role r ON r.user_profile_id=o.user_profile_id) THEN RAISE EXCEPTION 'Root changed'; END IF;
END; $seed$;
UPDATE private.migration_039h_functions SET installed=pg_get_functiondef(to_regprocedure(signature));


SAVEPOINT operational_checks;
-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. After reviewed 039g + 039h. Never executed by agent.
-- Uses the reviewed target UUID (Marianela), not email authorization. All changes roll back.
DO $test$
DECLARE actor UUID; actor_auth UUID; root_id UUID; root_auth UUID; root_preset UUID; org UUID;
 tenant_auth UUID:=gen_random_uuid(); tenant UUID; invitation JSONB; result JSONB; cap TEXT; action TEXT; kind TEXT;
 reader UUID; accountant UUID; operational UUID; historical UUID; root_before JSONB; scopes_before JSONB; rowdata RECORD; v_scope RECORD;
BEGIN
 SELECT target,preset INTO STRICT actor,operational FROM private.migration_039h_state;
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_template_capabilities tenant_grant
   JOIN public.eco_role_templates tenant_template ON tenant_template.id=tenant_grant.role_template_id
   JOIN public.eco_capabilities tenant_capability ON tenant_capability.id=tenant_grant.capability_id
   WHERE tenant_template.code='MICA_ORG_ADMIN' AND tenant_template.scope='ORGANIZATION' AND tenant_capability.code='ORG_MEMBER_PRESET_ASSIGN') THEN
  RAISE EXCEPTION 'MICA_ORG_ADMIN assignment grant missing'; END IF;
 IF (SELECT count(*) FROM public.eco_platform_role_org_capabilities platform_grant
   JOIN public.eco_role_templates platform_template ON platform_template.id=platform_grant.role_template_id
   JOIN public.eco_capabilities bridge_capability ON bridge_capability.id=platform_grant.capability_id
   WHERE platform_template.code IN('VEGEN_PLATFORM_ADMIN','ADMINISTRACION_OPERATIVA_MICA') AND platform_template.scope='PLATFORM'
    AND bridge_capability.code='ORG_MEMBER_PRESET_ASSIGN')<>2 THEN RAISE EXCEPTION 'Root/operational assignment bridge missing'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_templates legacy_template
   JOIN public.eco_role_template_capabilities legacy_grant ON legacy_grant.role_template_id=legacy_template.id
   JOIN public.eco_capabilities legacy_capability ON legacy_capability.id=legacy_grant.capability_id
   WHERE legacy_template.scope IS NULL AND legacy_capability.code='ORG_MEMBER_PRESET_ASSIGN')
  OR EXISTS(SELECT 1 FROM public.eco_role_templates legacy_template
   JOIN public.eco_platform_role_org_capabilities legacy_grant ON legacy_grant.role_template_id=legacy_template.id
   JOIN public.eco_capabilities legacy_capability ON legacy_capability.id=legacy_grant.capability_id
   WHERE legacy_template.scope IS NULL AND legacy_capability.code='ORG_MEMBER_PRESET_ASSIGN') THEN
  RAISE EXCEPTION 'OWNER or other NULL-scope legacy received assignment capability'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgname='guard_036_grant' AND tgenabled='O'
   AND tgfoid=to_regprocedure('private.guard_036_grant()') AND tgrelid IN('public.eco_role_template_capabilities'::regclass,
    'public.eco_platform_role_org_capabilities'::regclass))<>2 THEN RAISE EXCEPTION 'Grant guards are not active'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state saved_state WHERE saved_state.legacy_before IS DISTINCT FROM jsonb_build_object(
   'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
   'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
    JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
   'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
    JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL))) THEN
  RAISE EXCEPTION 'Legacy templates/grants snapshot differs'; END IF;
 SELECT auth_user_id INTO STRICT actor_auth FROM public.eco_user_profiles WHERE id=actor;
 IF (SELECT count(*) FROM public.eco_organization_members WHERE user_profile_id=actor)<>3
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=actor AND is_active) THEN
  RAISE EXCEPTION 'Historical memberships missing or still active'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state saved_state WHERE saved_state.memberships_installed IS DISTINCT FROM
   (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=actor)
   OR saved_state.scopes IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=actor)) THEN
  RAISE EXCEPTION 'Historical memberships or seven scopes changed'; END IF;
 SELECT user_profile_id,auth_user_id INTO STRICT root_id,root_auth FROM private.eco_platform_owner;
 SELECT role_template_id INTO STRICT root_preset FROM public.eco_user_platform_role WHERE user_profile_id=root_id;
 SELECT id INTO STRICT historical FROM public.eco_role_templates WHERE code='ACCOUNTING_SUPERADMIN';
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
   WHERE a.user_profile_id=actor AND a.is_active AND t.id=operational AND t.code='ADMINISTRACION_OPERATIVA_MICA' AND t.is_active) THEN
  RAISE EXCEPTION 'Marianela operational assignment missing'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=historical AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE role_template_id=historical AND is_active)
  OR EXISTS(SELECT 1 FROM public.eco_organization_members WHERE role_template_id=historical AND is_active) THEN
  RAISE EXCEPTION 'Accounting is reusable or has active recipients'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_templates WHERE id=root_preset AND code='VEGEN_PLATFORM_ADMIN' AND is_active) THEN
  RAISE EXCEPTION 'Root preset changed'; END IF;
 IF EXISTS(SELECT 1 FROM public.eco_role_template_capabilities g JOIN public.eco_role_templates t ON t.id=g.role_template_id
   JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code='ORGANIZATION_CREATE' AND t.is_active AND t.id NOT IN(root_preset,operational))
  OR NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_ARCHIVE' AND delegation_class='OWNER_RESERVED' AND is_active) THEN
  RAISE EXCEPTION 'Create/archive boundary changed'; END IF;
 IF EXISTS(SELECT 1 FROM private.migration_039h_state b WHERE
   b.historical_grants IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_role_template_capabilities g WHERE role_template_id=historical)
   OR b.historical_bridge IS DISTINCT FROM (SELECT COALESCE(jsonb_agg(to_jsonb(g) ORDER BY capability_id),'[]') FROM public.eco_platform_role_org_capabilities g WHERE role_template_id=historical)) THEN
  RAISE EXCEPTION 'Historical grants changed'; END IF;
 SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(a)) INTO root_before
 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
 JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id;
 SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY organization_id),'[]') INTO scopes_before FROM private.eco_platform_org_scopes s WHERE user_profile_id=actor;
 SELECT id INTO STRICT reader FROM public.eco_role_templates WHERE code='MICA_READ_ONLY';
 SELECT id INTO STRICT accountant FROM public.eco_role_templates WHERE code='MICA_ACCOUNTANT';
 PERFORM set_config('request.jwt.claim.sub',actor_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_auth,'role','authenticated')::TEXT,TRUE);
 -- Exercise ALL seven reviewed organizations, including the three historical tenant organizations,
 -- and MICA / Nueva ORG / Una de prueba / Vanina. Only platform scopes and bridge authorize now.
 FOR v_scope IN SELECT organization_id FROM private.eco_platform_org_scopes WHERE user_profile_id=actor AND is_active LOOP
  SET LOCAL ROLE authenticated;
  PERFORM public.switch_superadmin_org_context(v_scope.organization_id);
  IF NOT public.can_operate_mica_org(v_scope.organization_id,'RECORD_VIEW')
   OR NOT public.can_operate_mica_org(v_scope.organization_id,'RECORD_CLASSIFY') THEN
   RAISE EXCEPTION 'Scope-only operation failed in %',v_scope.organization_id; END IF;
  RESET ROLE;
 END LOOP;
 FOREACH cap IN ARRAY ARRAY['MICA_ADMIN_MANAGE','AUDIT_PLATFORM_VIEW','SAAS_ANALYTICS_VIEW','PLATFORM_MANAGE','GLOBAL_USER_MANAGE',
 'PLAN_MANAGE','ACCESS_ANY_ORG','SUPPORT_IMPERSONATE','HARD_DELETE_EXCEPTIONAL','ORGANIZATION_ARCHIVE',
 'PLATFORM_MIGRATIONS_APPLY','PLATFORM_TENANTS_PROVISION','PLATFORM_SYSTEM_MONITOR'] LOOP
  IF private.can_platform(cap) THEN RAISE EXCEPTION 'Forbidden platform capability: %',cap; END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 org:=public.mica_admin_apply('organization',jsonb_build_object('name','039h company '||tenant_auth));
 PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'name','039h edited','legal_name','039h Legal SA',
  'trade_name','039h Comercial','tax_id','30712345678'));
 PERFORM public.switch_superadmin_org_context(org);
 result:=public.mica_admin_read(org,'');
 IF NOT (result->'rights'->>'operational_admin')::BOOLEAN OR (result->'rights'->>'presets')::BOOLEAN
  OR (result->'rights'->>'assignments')::BOOLEAN OR result->'capabilities'<>'[]'::JSONB OR result->'overrides'<>'[]'::JSONB THEN
  RAISE EXCEPTION 'Operational UI exposed structural tools'; END IF;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('id',org,'is_active',FALSE));
  RAISE EXCEPTION 'Archive allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM public.create_import('ARCA_RECIBIDOS','COMPRA');
 PERFORM public.create_import('ARCA_EMITIDOS','VENTA');
 PERFORM public.create_import('PERCEPCIONES_IVA','PERCEPCION');
 PERFORM public.create_import('PERCEPCIONES_ARBA','PERCEPCION');
 PERFORM public.create_import('BANK_STATEMENT_BBVA','BANCO');
 PERFORM public.create_import('PAYROLL_ACONPY','SUELDO');
 invitation:=public.mica_invitation('create',org,jsonb_build_object('email','039h-'||tenant_auth||'@example.invalid','role_template_id',reader));
 RESET ROLE;
 SELECT * INTO STRICT rowdata FROM public.eco_organizations WHERE id=org;
 IF rowdata.name<>'039h edited' OR rowdata.legal_name<>'039h Legal SA' OR rowdata.trade_name<>'039h Comercial'
  OR rowdata.tax_id<>'30712345678' OR NOT rowdata.is_active THEN RAISE EXCEPTION 'Company update failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes WHERE user_profile_id=actor AND organization_id=org AND is_active) THEN
  RAISE EXCEPTION 'New organization missing explicit scope'; END IF;
 IF private.can_operate_mica_org(org,'ORG_MEMBER_PERMISSION_MANAGE') THEN RAISE EXCEPTION 'Permission editing leaked'; END IF;
 FOREACH cap IN ARRAY ARRAY['ORG_MEMBER_VIEW','ORG_MEMBER_INVITE','ORG_MEMBER_MANAGE','ORG_MEMBER_PRESET_ASSIGN',
 'CATALOG_ACTIVITY_MANAGE','CATALOG_CATEGORY_MANAGE','RECORD_CLASSIFY','FINANCIAL_ALLOCATION_EDIT','MANUAL_MOVEMENT_CREATE',
 'MANUAL_MOVEMENT_EDIT','RECORD_SOFT_DELETE','RECORD_RESTORE'] LOOP
  IF NOT private.can_operate_mica_org(org,cap) THEN RAISE EXCEPTION 'Operational grant missing: %',cap; END IF;
 END LOOP;
 INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(tenant_auth,'039h-'||tenant_auth||'@example.invalid',now());
 SELECT id INTO STRICT tenant FROM public.eco_user_profiles WHERE auth_user_id=tenant_auth;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_invitation('assign',org,jsonb_build_object('id',invitation->>'id','user_profile_id',tenant));
 PERFORM public.mica_admin_apply('tenant_activate',jsonb_build_object('organization_id',org,'user_profile_id',tenant));
 PERFORM public.mica_admin_apply('membership',jsonb_build_object('organization_id',org,'user_profile_id',tenant,'role_template_id',accountant,'is_active',TRUE));
 RESET ROLE;
 IF NOT EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=tenant AND organization_id=org AND role_template_id=accountant AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=tenant AND is_active) THEN RAISE EXCEPTION 'Tenant assignment/activation failed'; END IF;
 SET LOCAL ROLE authenticated;
 PERFORM public.mica_admin_apply('membership',jsonb_build_object('organization_id',org,'user_profile_id',tenant,'role_template_id',reader,'is_active',FALSE));
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM public.eco_organization_members WHERE user_profile_id=tenant AND organization_id=org AND is_active)
  OR NOT EXISTS(SELECT 1 FROM public.eco_user_profiles WHERE id=tenant AND is_active) THEN RAISE EXCEPTION 'Tenant deactivation altered global account'; END IF;
 SET LOCAL ROLE authenticated;
 FOREACH action IN ARRAY ARRAY['user','platform_role','scope'] LOOP
  BEGIN
   PERFORM public.mica_admin_apply(action,jsonb_build_object('user_profile_id',tenant,'role_template_id',operational,
    'organization_id',CASE WHEN action='scope' THEN org ELSE NULL END,'is_active',FALSE));
   RAISE EXCEPTION 'Forbidden action allowed: %',action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 FOREACH kind IN ARRAY ARRAY['platform','platform_org','membership'] LOOP
  FOREACH action IN ARRAY ARRAY['ALLOW','DENY'] LOOP
   BEGIN
    PERFORM public.mica_admin_apply('override',jsonb_build_object('user_profile_id',tenant,'organization_id',CASE WHEN kind='platform' THEN NULL ELSE org END,
      'kind',kind,'effect',action,'capability',CASE WHEN kind='platform' THEN 'ORGANIZATION_CREATE' ELSE 'RECORD_VIEW' END));
    RAISE EXCEPTION 'Override allowed: % %',kind,action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
 END LOOP;
 BEGIN
  PERFORM public.mica_invitation('create',NULL,jsonb_build_object('email','platform-'||tenant_auth||'@example.invalid','role_template_id',operational));
  RAISE EXCEPTION 'Platform invitation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('name','Forbidden','scope','ORGANIZATION','organization_id',org,'capabilities','[]'::JSONB,'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Preset creation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE public.eco_capabilities SET description='forbidden' WHERE code='ORGANIZATION_CREATE';
  RAISE EXCEPTION 'Capability edit allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM private.eco_platform_owner WHERE user_profile_id=root_id;
  RAISE EXCEPTION 'Structural owner deletion allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM public.eco_role_template_capabilities WHERE role_template_id=root_preset;
  RAISE EXCEPTION 'Root grants deletion allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH action IN ARRAY ARRAY['user','platform_role','scope','membership','override'] LOOP
  BEGIN
   PERFORM public.mica_admin_apply(action,jsonb_build_object('user_profile_id',root_id,'role_template_id',reader,'organization_id',org,'is_active',FALSE,
    'kind','membership','effect','DENY','capability','RECORD_VIEW'));
   RAISE EXCEPTION 'Root administration allowed: %',action; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',root_preset,'name','Forbidden','scope','PLATFORM','capabilities','[]'::JSONB,'bridge','[]'::JSONB));
  RAISE EXCEPTION 'Root preset edit allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 INSERT INTO public.eco_user_platform_capability_overrides(user_profile_id,capability_id,effect)
 SELECT actor,id,'DENY' FROM public.eco_capabilities WHERE code='ORGANIZATION_CREATE';
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.mica_admin_apply('organization',jsonb_build_object('name','Denied'));
  RAISE EXCEPTION 'DENY bypassed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(scopes_before) old WHERE NOT EXISTS(SELECT 1 FROM private.eco_platform_org_scopes s WHERE to_jsonb(s)=old)) THEN
  RAISE EXCEPTION 'Existing scope changed'; END IF;
 IF root_before IS DISTINCT FROM (SELECT jsonb_build_object('owner',to_jsonb(o),'profile',to_jsonb(p),'role',to_jsonb(a))
 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
 JOIN public.eco_user_platform_role a ON a.user_profile_id=o.user_profile_id) THEN RAISE EXCEPTION 'Root state changed'; END IF;
 PERFORM set_config('request.jwt.claim.sub',root_auth::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',root_auth,'role','authenticated')::TEXT,TRUE);
 FOR cap IN SELECT code FROM public.eco_capabilities WHERE delegation_class='OWNER_RESERVED' LOOP
  IF NOT private.can_platform(cap) THEN RAISE EXCEPTION 'Root reserved authority lost: %',cap; END IF;
 END LOOP;
 SET LOCAL ROLE authenticated;
 result:=public.mica_admin_read(NULL,'');
 IF NOT (result->'rights'->>'global_users')::BOOLEAN OR NOT (result->'rights'->>'global_presets')::BOOLEAN THEN RAISE EXCEPTION 'Root UI authority lost'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'presets') p WHERE p->>'code'='ACCOUNTING_SUPERADMIN' AND (p->>'is_active')::BOOLEAN) THEN
  RAISE EXCEPTION 'Deprecated preset exposed as assignable'; END IF;
 BEGIN
  PERFORM public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',tenant,'role_template_id',historical));
  RAISE EXCEPTION 'Deprecated preset assignment allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_admin_apply('preset',jsonb_build_object('id',historical,'is_active',TRUE));
  RAISE EXCEPTION 'Deprecated preset reactivation allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END; $test$;

ROLLBACK TO SAVEPOINT operational_checks;
-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Roll back 039h BEFORE 039g.
-- Existing companies, users, memberships and scopes are never deleted.
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

-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Refuses later grants, overrides and security drift.
LOCK TABLE public.eco_capabilities, private.eco_owner_reserved_capabilities,
 public.eco_role_template_capabilities, public.eco_user_platform_capability_overrides IN ACCESS EXCLUSIVE MODE;
DO $restore$
DECLARE b RECORD; x JSONB; v_id UUID; actual JSONB;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039g DOWN requires postgres'; END IF;
 IF to_regclass('private.migration_039g_create') IS NULL THEN RAISE EXCEPTION '039g not installed'; END IF;
 SELECT * INTO STRICT b FROM private.migration_039g_create;
 v_id:=(b.capability->>'id')::UUID;
 SELECT to_jsonb(c) INTO actual FROM public.eco_capabilities c WHERE id=v_id;
 IF actual IS DISTINCT FROM b.installed_capability THEN RAISE EXCEPTION '039g capability drift'; END IF;
 SELECT jsonb_agg(to_jsonb(g) ORDER BY role_template_id) INTO actual FROM public.eco_role_template_capabilities g WHERE capability_id=v_id;
 IF actual IS DISTINCT FROM b.installed_grants OR EXISTS(SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE capability_id=v_id)
  OR EXISTS(SELECT 1 FROM private.eco_owner_reserved_capabilities WHERE capability_id=v_id) THEN
  RAISE EXCEPTION '039g delegation drift: preserve later decisions'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(b.security_functions) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid=to_regprocedure(x->>'signature')
   AND pg_get_functiondef(p.oid)=x->>'definition' AND p.proowner=(x->>'owner')::OID
   AND COALESCE(to_jsonb(p.proacl),'null'::JSONB) IS NOT DISTINCT FROM x->'acl') THEN
   RAISE EXCEPTION '039g security function drift: %',x->>'signature'; END IF;
 END LOOP;
 FOR x IN SELECT value FROM jsonb_array_elements(b.protection_triggers) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE oid=(x->>'oid')::OID AND pg_get_triggerdef(oid)=x->>'definition'
   AND tgenabled::TEXT=x->>'enabled') THEN RAISE EXCEPTION '039g protection trigger drift'; END IF;
 END LOOP;
 DELETE FROM public.eco_role_template_capabilities WHERE capability_id=v_id;
 ALTER TABLE public.eco_capabilities DISABLE TRIGGER guard_036_capability;
 ALTER TABLE private.eco_owner_reserved_capabilities DISABLE TRIGGER guard_036_reserved_frozen;
 UPDATE public.eco_capabilities SET delegation_class=b.capability->>'delegation_class' WHERE id=v_id;
 INSERT INTO private.eco_owner_reserved_capabilities SELECT (jsonb_populate_record(NULL::private.eco_owner_reserved_capabilities,b.reserved_row)).*;
 ALTER TABLE public.eco_capabilities ENABLE TRIGGER guard_036_capability;
 ALTER TABLE private.eco_owner_reserved_capabilities ENABLE TRIGGER guard_036_reserved_frozen;
 IF (SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE id=v_id) IS DISTINCT FROM b.capability
  OR (SELECT to_jsonb(r) FROM private.eco_owner_reserved_capabilities r WHERE capability_id=v_id) IS DISTINCT FROM b.reserved_row THEN
  RAISE EXCEPTION '039g exact restoration failed'; END IF;
END; $restore$;
DROP TABLE private.migration_039g_create;

DO $after_down$
DECLARE v_before RECORD;
BEGIN
 SELECT * INTO STRICT v_before FROM test_039h_before;
 IF v_before.legacy_before IS DISTINCT FROM jsonb_build_object(
 'templates',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_template) ORDER BY id),'[]') FROM public.eco_role_templates legacy_template WHERE scope IS NULL),
 'direct',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_role_template_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL),
 'bridge',(SELECT COALESCE(jsonb_agg(to_jsonb(legacy_grant) ORDER BY role_template_id,capability_id),'[]') FROM public.eco_platform_role_org_capabilities legacy_grant
   JOIN public.eco_role_templates legacy_template ON legacy_template.id=legacy_grant.role_template_id WHERE legacy_template.scope IS NULL)) THEN RAISE EXCEPTION 'Roundtrip changed legacy templates or grants'; END IF;
 IF v_before.memberships IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(member_row) ORDER BY id) FROM public.eco_organization_members member_row WHERE user_profile_id=v_before.target)
  OR v_before.scopes IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY organization_id) FROM private.eco_platform_org_scopes scope_row WHERE user_profile_id=v_before.target)
  OR v_before.assignment IS DISTINCT FROM (SELECT to_jsonb(assignment_row) FROM public.eco_user_platform_role assignment_row WHERE user_profile_id=v_before.target)
  OR v_before.historical_preset IS DISTINCT FROM (SELECT to_jsonb(preset_row) FROM public.eco_role_templates preset_row WHERE code='ACCOUNTING_SUPERADMIN')
  OR v_before.grants IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_role_template_capabilities grant_row WHERE role_template_id=(v_before.historical_preset->>'id')::UUID)
  OR v_before.bridge IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(grant_row) ORDER BY capability_id) FROM public.eco_platform_role_org_capabilities grant_row WHERE role_template_id=(v_before.historical_preset->>'id')::UUID)
  OR EXISTS(SELECT 1 FROM jsonb_each_text(v_before.definitions) checked_definition WHERE pg_get_functiondef(to_regprocedure(checked_definition.key)) IS DISTINCT FROM checked_definition.value) THEN
  RAISE EXCEPTION 'Roundtrip did not restore exact memberships/scopes/assignment/preset/grants/functions'; END IF;
END; $after_down$;
ROLLBACK;
