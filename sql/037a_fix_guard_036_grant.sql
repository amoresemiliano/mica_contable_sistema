-- 037a: hotfix after applied 036/037. Prepare only; apply manually.
BEGIN;
DO $preflight$
BEGIN
  IF to_regclass('private.migration_037a_guard_backup') IS NOT NULL THEN
    RAISE EXCEPTION '037a: backup exists; refusing reapplication'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure('private.guard_036_grant()') AND p.prorettype='trigger'::regtype
      AND p.pronargs=0 AND p.prosecdef AND p.provolatile='v' AND l.lanname='plpgsql'
      AND p.proconfig=ARRAY['search_path=""']::TEXT[] AND pg_get_userbyid(p.proowner)=current_user
      AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9)))='1206d1ddb5aba5be009e631edf7c0525') THEN
    RAISE EXCEPTION '037a: function differs from reviewed defective 036 body/attributes/owner'; END IF;
  -- Serialize affected grant writes while capturing and replacing the shared trigger function.
  LOCK TABLE public.eco_role_template_capabilities,public.eco_user_platform_capability_overrides,
    public.eco_platform_role_org_capabilities,public.eco_membership_capability_overrides,
    public.eco_member_capability_overrides IN SHARE ROW EXCLUSIVE MODE;
END;
$preflight$;
CREATE TABLE private.migration_037a_guard_backup (
  singleton BOOLEAN PRIMARY KEY CHECK(singleton),
  function_oid OID NOT NULL, definition TEXT NOT NULL, owner_name TEXT NOT NULL,
  acl ACLITEM[], installed_definition TEXT
);
ALTER TABLE private.migration_037a_guard_backup ENABLE ROW LEVEL SECURITY;
-- Revoke project-specific default ACL as well as PUBLIC/anon/authenticated.
DO $acl$
DECLARE a RECORD; v RECORD; v_grantee TEXT;
BEGIN
  SELECT relowner,relacl INTO v FROM pg_class WHERE oid='private.migration_037a_guard_backup'::regclass;
  FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(v.relacl,acldefault('r',v.relowner))) WHERE grantee<>v.relowner LOOP
    v_grantee:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
    EXECUTE format('REVOKE ALL ON TABLE private.migration_037a_guard_backup FROM %s',v_grantee);
  END LOOP;
END;
$acl$;
REVOKE ALL ON TABLE private.migration_037a_guard_backup FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_037a_guard_backup(singleton,function_oid,definition,owner_name,acl)
SELECT TRUE,oid,pg_get_functiondef(oid),pg_get_userbyid(proowner),proacl FROM pg_proc
WHERE oid='private.guard_036_grant()'::regprocedure;

CREATE OR REPLACE FUNCTION private.guard_036_grant()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id UUID; v_class TEXT; v_scope TEXT; v_template_scope TEXT;
BEGIN
  v_id := (to_jsonb(NEW)->>TG_ARGV[0])::UUID;
  SELECT delegation_class,scope INTO v_class,v_scope FROM public.eco_capabilities WHERE id=v_id FOR SHARE;
  IF v_class IS NULL OR v_class='OWNER_RESERVED' THEN
    RAISE EXCEPTION '036: reserved or unknown capability cannot be delegated' USING ERRCODE='42501'; END IF;
  -- Legacy GRANT/REVOKE semantics stay untouched: only the reserved boundary applies here.
  IF TG_TABLE_NAME='eco_member_capability_overrides' THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME='eco_role_template_capabilities' THEN
    SELECT scope INTO v_template_scope FROM public.eco_role_templates WHERE id=NEW.role_template_id FOR SHARE;
    IF v_template_scope IS DISTINCT FROM v_scope THEN
      RAISE EXCEPTION '036: incompatible template capability scope' USING ERRCODE='42501'; END IF;
  ELSIF TG_TABLE_NAME='eco_user_platform_capability_overrides' THEN
    IF v_scope<>'PLATFORM' THEN RAISE EXCEPTION '036: platform override scope mismatch' USING ERRCODE='42501'; END IF;
  ELSIF TG_TABLE_NAME='eco_platform_role_org_capabilities' THEN
    IF v_scope<>'ORGANIZATION' THEN RAISE EXCEPTION '036: organization grant scope mismatch' USING ERRCODE='42501'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.eco_role_templates WHERE id=NEW.role_template_id AND scope='PLATFORM') THEN
      RAISE EXCEPTION '036: bridge requires platform template' USING ERRCODE='42501'; END IF;
  ELSIF TG_TABLE_NAME='eco_membership_capability_overrides' THEN
    IF v_scope<>'ORGANIZATION' THEN RAISE EXCEPTION '036: organization grant scope mismatch' USING ERRCODE='42501'; END IF;
  ELSE
    RAISE EXCEPTION '037a: unsupported grant table %',TG_TABLE_NAME USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END; $$;

DO $verify$
DECLARE b RECORD;
BEGIN
  SELECT * INTO STRICT b FROM private.migration_037a_guard_backup WHERE singleton;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('private.guard_036_grant()')
    AND oid=b.function_oid AND pg_get_userbyid(proowner)=b.owner_name AND proacl IS NOT DISTINCT FROM b.acl) THEN
    RAISE EXCEPTION '037a: function identity/owner/ACL changed'; END IF;
  UPDATE private.migration_037a_guard_backup SET installed_definition=pg_get_functiondef(b.function_oid) WHERE singleton;
END;
$verify$;
-- Existing triggers retain the same function OID. No trigger recreation or grant data changes.
COMMIT;
