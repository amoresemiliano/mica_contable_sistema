-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. No SQL executed by the agent.
-- Run readonly preflight first. No identity, scope, override or authorization-function changes.
BEGIN;
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
COMMIT;
