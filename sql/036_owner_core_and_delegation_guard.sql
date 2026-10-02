-- 036: local review only. Never run automatically. Apply as database administrator.
-- B: reserved authority comes only from the structural owner and its private grant set.
-- No changes to 035, can_org, operational users, organizations or memberships.
BEGIN;
DO $preflight$
DECLARE
  v RECORD;
  v_cap RECORD;
  v_actor RECORD;
  v_sub TEXT := current_setting('request.jwt.claim.sub', true);
  v_claims TEXT := current_setting('request.jwt.claims', true);
  v_rel REGCLASS;
BEGIN
  IF to_regclass('private.migration_036_backup') IS NOT NULL
    OR to_regclass('private.eco_platform_owner') IS NOT NULL
    OR to_regclass('private.eco_owner_reserved_capabilities') IS NOT NULL
    OR to_regprocedure('private.is_platform_owner()') IS NOT NULL
    OR to_regprocedure('private.guard_036_frozen()') IS NOT NULL
    OR to_regprocedure('private.guard_036_identity()') IS NOT NULL
    OR to_regprocedure('private.guard_036_capability()') IS NOT NULL
    OR to_regprocedure('private.guard_036_grant()') IS NOT NULL
    OR to_regprocedure('private.guard_036_template()') IS NOT NULL
    OR to_regprocedure('public.get_capability_delegation_contract()') IS NOT NULL THEN
    RAISE EXCEPTION '036: target object already exists; refusing overwrite/reapplication';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.eco_capabilities')
    AND attname = 'delegation_class' AND NOT attisdropped) THEN
    RAISE EXCEPTION '036: delegation_class already exists; inspect baseline';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = to_regprocedure('private.can_platform(text)')
    AND prorettype = 'boolean'::regtype AND NOT proretset AND prosecdef AND provolatile = 's'
    AND proargnames = ARRAY['p_capability_code']::TEXT[] AND proconfig @> ARRAY['search_path=""']
    AND pg_get_userbyid(proowner)=current_user
    AND md5(btrim(replace(prosrc,chr(13),''),' ' || chr(10) || chr(9))) = 'bb8759cafcc9ba64d92b549b485d3411') THEN
    RAISE EXCEPTION '036: can_platform differs from reviewed 019 contract; inspect LIVE body first';
  END IF;
  FOR v IN SELECT * FROM (VALUES ('eco_user_profiles','id','uuid'),
    ('eco_user_profiles','auth_user_id','uuid'),
    ('eco_user_profiles','is_active','boolean'),
    ('eco_capabilities','id','uuid'),
    ('eco_capabilities','code','text'),
    ('eco_capabilities','scope','text'),
    ('eco_capabilities','is_active','boolean'),
    ('eco_role_templates','id','uuid'),
    ('eco_role_templates','code','text'),
    ('eco_role_templates','scope','text'),
    ('eco_role_templates','is_active','boolean'),
    ('eco_user_platform_role','user_profile_id','uuid'),
    ('eco_user_platform_role','role_template_id','uuid'),
    ('eco_user_platform_role','is_active','boolean'),
    ('eco_role_template_capabilities','role_template_id','uuid'),
    ('eco_role_template_capabilities','capability_id','uuid'),
    ('eco_role_template_capabilities','created_at','timestamp with time zone'),
    ('eco_user_platform_capability_overrides','user_profile_id','uuid'),
    ('eco_user_platform_capability_overrides','capability_id','uuid'),
    ('eco_user_platform_capability_overrides','effect','text'),
    ('eco_platform_role_org_capabilities','role_template_id','uuid'),
    ('eco_platform_role_org_capabilities','capability_id','uuid'),
    ('eco_membership_capability_overrides','membership_id','uuid'),
    ('eco_membership_capability_overrides','capability_id','uuid'),
    ('eco_membership_capability_overrides','effect','text')
  ) required(table_name,column_name,type_name) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      WHERE c.oid = to_regclass('public.' || v.table_name) AND c.relkind = 'r'
      AND a.attname = v.column_name AND NOT a.attisdropped AND a.atttypid = to_regtype(v.type_name)) THEN
      RAISE EXCEPTION '036: unexpected schema %.% (%)', v.table_name,v.column_name,v.type_name;
    END IF;
  END LOOP;
  -- Lock all grant/identity inputs until commit: no racing assignment between audit and guards.
  LOCK TABLE public.eco_capabilities, public.eco_role_templates, public.eco_user_profiles,
    public.eco_user_platform_role, public.eco_role_template_capabilities,
    public.eco_user_platform_capability_overrides, public.eco_platform_role_org_capabilities,
    public.eco_membership_capability_overrides, public.eco_member_capability_overrides
    IN SHARE ROW EXCLUSIVE MODE;
  FOR v IN SELECT * FROM (VALUES
    ('eco_capabilities',ARRAY['id']), ('eco_capabilities',ARRAY['code']),
    ('eco_user_profiles',ARRAY['id']), ('eco_user_profiles',ARRAY['auth_user_id']),
    ('eco_role_templates',ARRAY['id']), ('eco_role_templates',ARRAY['code']),
    ('eco_user_platform_role',ARRAY['user_profile_id']),
    ('eco_role_template_capabilities',ARRAY['role_template_id','capability_id']),
    ('eco_user_platform_capability_overrides',ARRAY['user_profile_id','capability_id']),
    ('eco_platform_role_org_capabilities',ARRAY['role_template_id','capability_id']),
    ('eco_membership_capability_overrides',ARRAY['membership_id','capability_id'])
  ) required(table_name,cols) LOOP
    v_rel := to_regclass('public.' || v.table_name);
    IF NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid=v_rel AND k.contype IN ('p','u')
      AND NOT k.condeferrable AND k.convalidated AND cardinality(k.conkey)=cardinality(v.cols)
      AND k.conkey @> ARRAY(SELECT attnum FROM pg_attribute WHERE attrelid=v_rel AND attname=ANY(v.cols))::SMALLINT[]) THEN
      RAISE EXCEPTION '036: missing unique constraint %.%', v.table_name,v.cols;
    END IF;
  END LOOP;
  -- Required non-null grant keys and validated identity/template FKs from 019.
  FOR v IN SELECT * FROM (VALUES
    ('eco_user_platform_role','user_profile_id','eco_user_profiles'),
    ('eco_user_platform_role','role_template_id','eco_role_templates'),
    ('eco_role_template_capabilities','role_template_id','eco_role_templates'),
    ('eco_platform_role_org_capabilities','role_template_id','eco_role_templates'),
    ('eco_user_platform_capability_overrides','user_profile_id','eco_user_profiles'),
    ('eco_membership_capability_overrides','membership_id','eco_organization_members')
  ) required(table_name,column_name,target_name) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint k
      JOIN pg_attribute a ON a.attrelid=k.conrelid AND k.conkey=ARRAY[a.attnum]::SMALLINT[]
      JOIN pg_attribute b ON b.attrelid=k.confrelid AND k.confkey=ARRAY[b.attnum]::SMALLINT[]
      WHERE k.conrelid=to_regclass('public.'||v.table_name) AND k.contype='f'
        AND k.convalidated AND NOT k.condeferrable AND a.attname=v.column_name AND a.attnotnull
        AND k.confrelid=to_regclass('public.'||v.target_name) AND b.attname='id') THEN
      RAISE EXCEPTION '036: missing identity/template FK %.%',v.table_name,v.column_name;
    END IF;
  END LOOP;
  -- Require a single-column capability FK on every grant path, including the untouched legacy table.
  FOR v IN SELECT unnest(ARRAY['eco_role_template_capabilities','eco_user_platform_capability_overrides',
    'eco_platform_role_org_capabilities','eco_membership_capability_overrides','eco_member_capability_overrides']) AS table_name LOOP
    IF (SELECT count(*) FROM pg_constraint k JOIN pg_attribute s ON s.attrelid=k.conrelid
      AND k.conkey=ARRAY[s.attnum]::SMALLINT[]
      JOIN pg_attribute a ON a.attrelid=k.confrelid
      AND k.confkey=ARRAY[a.attnum]::SMALLINT[] WHERE k.conrelid=to_regclass('public.'||v.table_name)
      AND k.contype='f' AND k.convalidated AND NOT k.condeferrable AND cardinality(k.conkey)=1
      AND k.confrelid='public.eco_capabilities'::regclass AND a.attname='id'
      AND (v.table_name='eco_member_capability_overrides' OR (s.attname='capability_id' AND s.attnotnull))) <> 1 THEN
      RAISE EXCEPTION '036: expected one capability-id FK on % (including legacy)',v.table_name;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE contype='f' AND confrelid='public.eco_capabilities'::regclass
    AND conrelid NOT IN ('public.eco_role_template_capabilities'::regclass,
      'public.eco_user_platform_capability_overrides'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
      'public.eco_membership_capability_overrides'::regclass,'public.eco_member_capability_overrides'::regclass)) THEN
    RAISE EXCEPTION '036: unreviewed capability reference/grant path';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_member_capability_overrides) THEN
    RAISE EXCEPTION '036: legacy override rows differ from confirmed empty baseline';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.eco_user_profiles p JOIN auth.users u ON u.id=p.auth_user_id
    WHERE p.id='9563f41e-cd57-42d9-8626-9b04bd6e5863' AND p.auth_user_id='c1e16acf-a45c-4e51-a3e5-c95208adc3c6'
    AND p.is_active IS TRUE) THEN RAISE EXCEPTION '036: structural owner identity mismatch'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.eco_role_templates WHERE id='6331de19-de61-43fb-98cd-7d24f2235359'
    AND code='VEGEN_PLATFORM_ADMIN' AND scope='PLATFORM' AND is_active IS TRUE) THEN
    RAISE EXCEPTION '036: confirmed owner presentation template mismatch'; END IF;
  IF (SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id='6331de19-de61-43fb-98cd-7d24f2235359') <> 1
    OR NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id='9563f41e-cd57-42d9-8626-9b04bd6e5863'
      AND role_template_id='6331de19-de61-43fb-98cd-7d24f2235359' AND is_active IS TRUE) THEN
    RAISE EXCEPTION '036: owner role assignment differs'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.eco_capabilities WHERE code='ORGANIZATION_UPDATE'
    AND scope='PLATFORM' AND is_active IS TRUE) THEN
    RAISE EXCEPTION '036: ORGANIZATION_UPDATE must remain active PLATFORM_DELEGABLE'; END IF;
  IF EXISTS (SELECT 1 FROM public.eco_capabilities WHERE scope NOT IN ('PLATFORM','ORGANIZATION') OR scope IS NULL) THEN
    RAISE EXCEPTION '036: unexpected capability scope'; END IF;
  FOR v IN SELECT unnest(ARRAY['PLATFORM_MANAGE', 'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'ACCESS_ANY_ORG', 'SUPPORT_IMPERSONATE', 'HARD_DELETE_EXCEPTIONAL', 'ORGANIZATION_CREATE', 'ORGANIZATION_ARCHIVE', 'PLATFORM_MIGRATIONS_APPLY', 'PLATFORM_TENANTS_PROVISION', 'PLATFORM_SYSTEM_MONITOR']) AS code LOOP
    SELECT * INTO v_cap FROM public.eco_capabilities WHERE code=v.code AND scope='PLATFORM' AND is_active IS TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION '036: required active PLATFORM capability missing: %',v.code; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.eco_role_template_capabilities WHERE capability_id=v_cap.id
      AND role_template_id='6331de19-de61-43fb-98cd-7d24f2235359') THEN
      RAISE EXCEPTION '036: owner expected grant missing: %',v.code; END IF;
    IF EXISTS (SELECT 1 FROM public.eco_user_platform_capability_overrides WHERE capability_id=v_cap.id)
      OR EXISTS (SELECT 1 FROM public.eco_platform_role_org_capabilities WHERE capability_id=v_cap.id)
      OR EXISTS (SELECT 1 FROM public.eco_membership_capability_overrides WHERE capability_id=v_cap.id)
      OR EXISTS (SELECT 1 FROM public.eco_role_template_capabilities WHERE capability_id=v_cap.id
        AND role_template_id <> '6331de19-de61-43fb-98cd-7d24f2235359') THEN
      RAISE EXCEPTION '036: reserved grant/override outside reviewed owner baseline: %',v.code; END IF;
    FOR v_actor IN SELECT id,auth_user_id FROM public.eco_user_profiles WHERE is_active IS TRUE LOOP
      PERFORM set_config('request.jwt.claim.sub',v_actor.auth_user_id::TEXT,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_actor.auth_user_id,'role','authenticated')::TEXT,true);
      IF private.can_platform(v.code) IS DISTINCT FROM (v_actor.id='9563f41e-cd57-42d9-8626-9b04bd6e5863'::UUID) THEN
        RAISE EXCEPTION '036: unexpected effective reserved authority: profile %, capability %',v_actor.id,v.code;
      END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',COALESCE(v_sub,''),true);
  PERFORM set_config('request.jwt.claims',COALESCE(v_claims,''),true);
  IF NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role r JOIN public.eco_role_templates t ON t.id=r.role_template_id
    WHERE r.user_profile_id='f922be9a-449d-417f-8003-2143fcbeef02' AND r.is_active AND t.is_active
    AND t.code='ACCOUNTING_SUPERADMIN' AND t.scope='PLATFORM') THEN RAISE EXCEPTION '036: accounting baseline differs'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname LIKE 'guard_036_%' AND NOT tgisinternal) THEN
    RAISE EXCEPTION '036: trigger names already used'; END IF;
END;
$preflight$;

CREATE TABLE private.migration_036_backup (
  singleton BOOLEAN PRIMARY KEY CHECK(singleton), definition TEXT NOT NULL,
  owner_name TEXT NOT NULL, acl ACLITEM[], reserved_grants JSONB NOT NULL
);
REVOKE ALL ON private.migration_036_backup FROM PUBLIC, anon, authenticated;
INSERT INTO private.migration_036_backup
SELECT TRUE,pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl,
  (SELECT jsonb_agg(to_jsonb(g)) FROM public.eco_role_template_capabilities g
   JOIN public.eco_capabilities c ON c.id=g.capability_id WHERE c.code IN ('PLATFORM_MANAGE', 'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'ACCESS_ANY_ORG', 'SUPPORT_IMPERSONATE', 'HARD_DELETE_EXCEPTIONAL', 'ORGANIZATION_CREATE', 'ORGANIZATION_ARCHIVE', 'PLATFORM_MIGRATIONS_APPLY', 'PLATFORM_TENANTS_PROVISION', 'PLATFORM_SYSTEM_MONITOR'))
FROM pg_proc p WHERE p.oid='private.can_platform(text)'::regprocedure;

ALTER TABLE public.eco_capabilities ADD COLUMN delegation_class TEXT;
UPDATE public.eco_capabilities SET delegation_class=CASE WHEN code IN ('PLATFORM_MANAGE', 'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'ACCESS_ANY_ORG', 'SUPPORT_IMPERSONATE', 'HARD_DELETE_EXCEPTIONAL', 'ORGANIZATION_CREATE', 'ORGANIZATION_ARCHIVE', 'PLATFORM_MIGRATIONS_APPLY', 'PLATFORM_TENANTS_PROVISION', 'PLATFORM_SYSTEM_MONITOR') THEN 'OWNER_RESERVED'
  WHEN scope='PLATFORM' THEN 'PLATFORM_DELEGABLE' ELSE 'ORGANIZATION_DELEGABLE' END;
ALTER TABLE public.eco_capabilities ALTER COLUMN delegation_class SET NOT NULL;
ALTER TABLE public.eco_capabilities ADD CONSTRAINT eco_capabilities_036_delegation_check CHECK (
  (scope='PLATFORM' AND delegation_class IN ('OWNER_RESERVED','PLATFORM_DELEGABLE')) OR
  (scope='ORGANIZATION' AND delegation_class='ORGANIZATION_DELEGABLE'));

CREATE TABLE private.eco_platform_owner (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(singleton),
  user_profile_id UUID NOT NULL UNIQUE REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT,
  auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE private.eco_owner_reserved_capabilities (
  capability_id UUID PRIMARY KEY REFERENCES public.eco_capabilities(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
REVOKE ALL ON private.eco_platform_owner, private.eco_owner_reserved_capabilities FROM PUBLIC, anon, authenticated;
INSERT INTO private.eco_platform_owner(user_profile_id,auth_user_id)
VALUES ('9563f41e-cd57-42d9-8626-9b04bd6e5863','c1e16acf-a45c-4e51-a3e5-c95208adc3c6');
INSERT INTO private.eco_owner_reserved_capabilities(capability_id)
SELECT id FROM public.eco_capabilities WHERE delegation_class='OWNER_RESERVED';
DELETE FROM public.eco_role_template_capabilities g USING public.eco_capabilities c
WHERE g.capability_id=c.id AND c.delegation_class='OWNER_RESERVED';

CREATE FUNCTION private.is_platform_owner()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
    WHERE o.auth_user_id=auth.uid() AND p.auth_user_id=o.auth_user_id AND p.is_active IS TRUE
      AND p.id=private.current_profile_id());
$$;

CREATE OR REPLACE FUNCTION private.can_platform(p_capability_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_cap_id UUID;
    v_role_template_id UUID;
    v_has_base BOOLEAN := FALSE;
    v_override_effect TEXT;
    v_delegation_class TEXT;
BEGIN
    IF p_capability_code IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 1. current profile exists and is active
    v_profile_id := private.current_profile_id();
    IF v_profile_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 2. requested capability exists, scope = PLATFORM, is_active = TRUE
    SELECT id, delegation_class INTO v_cap_id, v_delegation_class
    FROM public.eco_capabilities
    WHERE code = p_capability_code
      AND scope = 'PLATFORM'
      AND is_active = TRUE;

    IF v_cap_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Reserved eligibility is structural; ordinary presets and overrides cannot grant it.
    IF v_delegation_class = 'OWNER_RESERVED' THEN
        RETURN private.is_platform_owner() AND EXISTS (
          SELECT 1 FROM private.eco_owner_reserved_capabilities WHERE capability_id = v_cap_id);
    END IF;
    -- 3. eco_user_platform_role exists and is_active = TRUE
    -- 4. referenced role template: scope = PLATFORM, is_active = TRUE
    SELECT upr.role_template_id INTO v_role_template_id
    FROM public.eco_user_platform_role upr
    JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
    WHERE upr.user_profile_id = v_profile_id
      AND upr.is_active = TRUE
      AND rt.scope = 'PLATFORM'
      AND rt.is_active = TRUE;

    -- 5. base grant is read from eco_role_template_capabilities
    IF v_role_template_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1
            FROM public.eco_role_template_capabilities
            WHERE role_template_id = v_role_template_id
              AND capability_id = v_cap_id
        ) INTO v_has_base;
    END IF;

    -- 6. user-specific override is read from eco_user_platform_capability_overrides
    SELECT effect INTO v_override_effect
    FROM public.eco_user_platform_capability_overrides
    WHERE user_profile_id = v_profile_id
      AND capability_id = v_cap_id;

    -- 7. explicit DENY wins
    IF v_override_effect = 'DENY' THEN
        RETURN FALSE;
    END IF;

    -- 8. explicit ALLOW can grant a capability absent from base template
    IF v_override_effect = 'ALLOW' THEN
        RETURN TRUE;
    END IF;

    -- 9. otherwise return base grant
    RETURN v_has_base;
END;
$$;
-- CREATE OR REPLACE preserves can_platform owner and ACL; 036 does not change either.

CREATE FUNCTION private.guard_036_frozen()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RAISE EXCEPTION '036: protected structural state; exceptional administrative migration required' USING ERRCODE='42501';
END; $$;
CREATE TRIGGER guard_036_owner_frozen BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.eco_platform_owner
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();
CREATE TRIGGER guard_036_reserved_frozen BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.eco_owner_reserved_capabilities
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();
CREATE TRIGGER guard_036_backup_frozen BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.migration_036_backup
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();

CREATE FUNCTION private.guard_036_identity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_owner UUID; v_auth UUID;
BEGIN
  SELECT user_profile_id,auth_user_id INTO STRICT v_owner,v_auth FROM private.eco_platform_owner;
  IF TG_TABLE_NAME='eco_user_profiles' THEN
    IF OLD.id=v_owner THEN
      IF TG_OP='DELETE' THEN RAISE EXCEPTION '036: owner profile protected' USING ERRCODE='42501'; END IF;
      IF NEW.id IS DISTINCT FROM OLD.id OR NEW.auth_user_id IS DISTINCT FROM v_auth OR NEW.is_active IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION '036: owner profile protected' USING ERRCODE='42501'; END IF;
    END IF;
  ELSE
    IF (TG_OP<>'INSERT' AND OLD.user_profile_id=v_owner) OR (TG_OP<>'DELETE' AND NEW.user_profile_id=v_owner) THEN
      RAISE EXCEPTION '036: owner platform assignment protected' USING ERRCODE='42501';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER guard_036_profile BEFORE UPDATE OR DELETE ON public.eco_user_profiles
FOR EACH ROW EXECUTE FUNCTION private.guard_036_identity();
CREATE TRIGGER guard_036_platform_role BEFORE INSERT OR UPDATE OR DELETE ON public.eco_user_platform_role
FOR EACH ROW EXECUTE FUNCTION private.guard_036_identity();
CREATE TRIGGER guard_036_profile_truncate BEFORE TRUNCATE ON public.eco_user_profiles
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();
CREATE TRIGGER guard_036_role_truncate BEFORE TRUNCATE ON public.eco_user_platform_role
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();

CREATE FUNCTION private.guard_036_capability()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.delegation_class='OWNER_RESERVED' OR NEW.code IN ('PLATFORM_MANAGE', 'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'ACCESS_ANY_ORG', 'SUPPORT_IMPERSONATE', 'HARD_DELETE_EXCEPTIONAL', 'ORGANIZATION_CREATE', 'ORGANIZATION_ARCHIVE', 'PLATFORM_MIGRATIONS_APPLY', 'PLATFORM_TENANTS_PROVISION', 'PLATFORM_SYSTEM_MONITOR') THEN
      RAISE EXCEPTION '036: reserved registration is not ordinary capability CRUD' USING ERRCODE='42501'; END IF;
  ELSE
    IF OLD.delegation_class='OWNER_RESERVED' AND (TG_OP='DELETE' OR NEW.is_active IS DISTINCT FROM TRUE) THEN
      RAISE EXCEPTION '036: reserved capability protected' USING ERRCODE='42501'; END IF;
    IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.code IS DISTINCT FROM OLD.code
      OR NEW.scope IS DISTINCT FROM OLD.scope OR NEW.delegation_class IS DISTINCT FROM OLD.delegation_class) THEN
      RAISE EXCEPTION '036: capability identity/scope/classification immutable in ordinary CRUD' USING ERRCODE='42501'; END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER guard_036_capability BEFORE INSERT OR UPDATE OR DELETE ON public.eco_capabilities
FOR EACH ROW EXECUTE FUNCTION private.guard_036_capability();
CREATE TRIGGER guard_036_capability_truncate BEFORE TRUNCATE ON public.eco_capabilities
FOR EACH STATEMENT EXECUTE FUNCTION private.guard_036_frozen();

CREATE FUNCTION private.guard_036_grant()
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
  ELSE
    IF v_scope<>'ORGANIZATION' THEN RAISE EXCEPTION '036: organization grant scope mismatch' USING ERRCODE='42501'; END IF;
    IF TG_TABLE_NAME='eco_platform_role_org_capabilities' AND NOT EXISTS (
      SELECT 1 FROM public.eco_role_templates WHERE id=NEW.role_template_id AND scope='PLATFORM') THEN
      RAISE EXCEPTION '036: bridge requires platform template' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN NEW;
END; $$;
DO $guards$
DECLARE v RECORD;
BEGIN
  FOR v IN SELECT k.conrelid::regclass AS relation,a.attname FROM pg_constraint k
    JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
    WHERE k.contype='f' AND k.confrelid='public.eco_capabilities'::regclass
      AND k.conrelid IN ('public.eco_role_template_capabilities'::regclass,
        'public.eco_user_platform_capability_overrides'::regclass,'public.eco_platform_role_org_capabilities'::regclass,
        'public.eco_membership_capability_overrides'::regclass,'public.eco_member_capability_overrides'::regclass) LOOP
    EXECUTE format('CREATE TRIGGER guard_036_grant BEFORE INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION private.guard_036_grant(%L)',v.relation,v.attname);
  END LOOP;
END;
$guards$;
CREATE FUNCTION private.guard_036_template()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.eco_user_platform_role r JOIN private.eco_platform_owner o ON o.user_profile_id=r.user_profile_id
    WHERE r.role_template_id=OLD.id) THEN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION '036: owner presentation template protected' USING ERRCODE='42501'; END IF;
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.code IS DISTINCT FROM OLD.code OR NEW.is_active IS DISTINCT FROM TRUE THEN
      RAISE EXCEPTION '036: owner presentation template protected' USING ERRCODE='42501'; END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  IF NEW.scope IS DISTINCT FROM OLD.scope THEN
    RAISE EXCEPTION '036: template scope changes require reviewed migration' USING ERRCODE='42501'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER guard_036_template BEFORE UPDATE OR DELETE ON public.eco_role_templates
FOR EACH ROW EXECUTE FUNCTION private.guard_036_template();

-- Metadata only: is_delegable is eligibility, NOT permission for this actor to assign.
CREATE FUNCTION public.get_capability_delegation_contract()
RETURNS TABLE(code TEXT, scope TEXT, delegation_class TEXT, is_delegable BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR private.current_profile_id() IS NULL THEN
    RAISE EXCEPTION 'Active profile required' USING ERRCODE='42501'; END IF;
  RETURN QUERY SELECT c.code,c.scope,c.delegation_class,c.delegation_class<>'OWNER_RESERVED'
    FROM public.eco_capabilities c WHERE c.is_active IS TRUE
      AND (c.delegation_class<>'OWNER_RESERVED' OR private.is_platform_owner()) ORDER BY c.code;
END; $$;
-- Remove default grants from NEW helpers/tables, including any project-specific default ACL.
DO $acl$
DECLARE v RECORD; a RECORD; v_role TEXT;
BEGIN
  FOR v IN SELECT p.oid::regprocedure AS signature,p.proowner,p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.nspname='private' AND p.proname IN ('is_platform_owner','guard_036_frozen','guard_036_identity',
      'guard_036_capability','guard_036_grant','guard_036_template'))
      OR (n.nspname='public' AND p.proname='get_capability_delegation_contract') LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(v.proacl,acldefault('f',v.proowner))) WHERE grantee<>v.proowner LOOP
      v_role := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',v.signature,v_role);
    END LOOP;
  END LOOP;
  FOR v IN SELECT oid::regclass AS relation,relowner,relacl FROM pg_class WHERE oid IN
    ('private.eco_platform_owner'::regclass,'private.eco_owner_reserved_capabilities'::regclass,'private.migration_036_backup'::regclass) LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(v.relacl,acldefault('r',v.relowner))) WHERE grantee<>v.relowner LOOP
      v_role := CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON TABLE %s FROM %s',v.relation,v_role);
    END LOOP;
  END LOOP;
END;
$acl$;
GRANT EXECUTE ON FUNCTION public.get_capability_delegation_contract() TO authenticated;
COMMIT;
