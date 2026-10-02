-- 038 MICA Contable Argentina. Canonical project: ourzapkjykzlwsjunzmd.
-- PREPARED ONLY. No grants seeded, no existing identities rewritten.
BEGIN;
DO $preflight$
DECLARE r RECORD;
BEGIN
  IF to_regclass('private.migration_038_backup') IS NOT NULL THEN RAISE EXCEPTION '038 already present'; END IF;
  IF to_regclass('private.migration_037a_guard_backup') IS NULL OR
     to_regprocedure('private.can_operate_mica_org(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '038 requires applied 037 and 037a'; END IF;
  IF EXISTS (SELECT 1 FROM private.migration_037a_guard_backup b
    WHERE pg_get_functiondef('private.guard_036_grant()'::regprocedure)<>b.installed_definition) THEN
    RAISE EXCEPTION '038 guard drift'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.handle_new_user()')
    AND prorettype='trigger'::regtype AND pronargs=0 AND pg_get_userbyid(proowner)=current_user
    AND pg_get_userbyid(proowner)='postgres' AND prosecdef AND provolatile='v' AND proconfig IS NULL) THEN
    RAISE EXCEPTION '038 requires review of public.handle_new_user() trigger/owner'; END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal AND (tgtype & 4)=4)<>1
    OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='auth.users'::regclass
      AND tgfoid='public.handle_new_user()'::regprocedure AND tgname='on_auth_user_created'
      AND tgtype=5 AND tgenabled='O') THEN
    RAISE EXCEPTION '038 unexpected auth INSERT trigger; review required'; END IF;
  -- Pending profiles must not require an organization or hidden mandatory columns.
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_user_profiles'::regclass
    AND attname='organization_id' AND attnotnull) THEN
    RAISE EXCEPTION '038 pending profile requires nullable organization_id'; END IF;
  FOR r IN SELECT * FROM (VALUES
    ('eco_organizations','name'),('eco_organizations','legal_name'),('eco_organizations','trade_name'),
    ('eco_organizations','tax_id'),('eco_organizations','tax_id_type'),('eco_organizations','country_code'),
    ('eco_organizations','currency'),('eco_organizations','timezone'),('eco_organizations','is_active'),
    ('eco_user_profiles','auth_user_id'),('eco_user_profiles','is_active'),('eco_user_profiles','role'),
    ('eco_organization_members','role_template_id'),('eco_role_templates','is_system')
  ) x(t,c) LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('public.'||r.t) AND attname=r.c AND NOT attisdropped)
      THEN RAISE EXCEPTION '038 missing %.%',r.t,r.c; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    WHERE a.attrelid='public.eco_user_profiles'::regclass AND a.attnum>0 AND NOT a.attisdropped
      AND a.attnotnull AND d.oid IS NULL AND a.attidentity='' AND a.attgenerated=''
      AND a.attname NOT IN ('auth_user_id','is_active','role')) THEN
    RAISE EXCEPTION '038 profile has unsupported required columns'; END IF;
END;
$preflight$;

CREATE TABLE private.migration_038_backup (
  signature TEXT PRIMARY KEY, definition TEXT NOT NULL, installed_definition TEXT,
  owner_name TEXT NOT NULL, acl ACLITEM[], installed_acl ACLITEM[]
);
INSERT INTO private.migration_038_backup(signature,definition,installed_definition,owner_name,acl)
SELECT 'public.handle_new_user()',pg_get_functiondef(oid),NULL,pg_get_userbyid(proowner),proacl
FROM pg_proc WHERE oid='public.handle_new_user()'::regprocedure;
CREATE TABLE private.eco_mica_presets (
  role_template_id UUID PRIMARY KEY REFERENCES public.eco_role_templates(id) ON DELETE RESTRICT,
  organization_id UUID REFERENCES public.eco_organizations(id) ON DELETE RESTRICT
);
CREATE TABLE private.eco_mica_pending_profiles (
  user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id) ON DELETE RESTRICT,
  approved_at TIMESTAMPTZ
);
ALTER TABLE private.migration_038_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_mica_presets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_mica_pending_profiles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_id UUID;
BEGIN
  -- USER is only a compatibility label; no membership, template, context or grant is created.
  INSERT INTO public.eco_user_profiles(auth_user_id,organization_id,role,is_active)
    VALUES(NEW.id,NULL,'USER',FALSE) RETURNING id INTO v_id;
  INSERT INTO private.eco_mica_pending_profiles(user_profile_id) VALUES(v_id);
  RETURN NEW;
END;
$$;
UPDATE private.migration_038_backup SET installed_definition=pg_get_functiondef('public.handle_new_user()'::regprocedure);

CREATE FUNCTION private.admin_038_actor()
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v UUID;
BEGIN
  SELECT id INTO v FROM public.eco_user_profiles WHERE auth_user_id=auth.uid() AND is_active;
  IF v IS NULL THEN RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE='42501'; END IF;
  RETURN v;
END; $$;

CREATE FUNCTION private.admin_038_authorize(p_org UUID,p_platform TEXT,p_tenant TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM private.admin_038_actor();
  -- Global identity/preset administration is a PLATFORM action, not an ACCESS_ANY_ORG bypass.
  IF p_org IS NULL THEN
    IF NOT COALESCE(private.can_platform(p_platform),FALSE) THEN
      RAISE EXCEPTION 'Platform administration denied' USING ERRCODE='42501'; END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=private.admin_038_actor() AND organization_id=p_org)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org AND is_active)
    OR NOT (COALESCE(private.can_platform('GLOBAL_USER_MANAGE'),FALSE)
      OR COALESCE(private.can_operate_mica_org(p_org,p_tenant),FALSE)) THEN
    RAISE EXCEPTION 'Tenant administration denied: confirmed context and action required' USING ERRCODE='42501';
  END IF;
END; $$;

CREATE FUNCTION private.admin_038_target(p_profile UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM public.eco_user_profiles WHERE id=p_profile FOR UPDATE;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM private.eco_platform_owner WHERE user_profile_id=p_profile) THEN
    RAISE EXCEPTION 'Missing or protected target' USING ERRCODE='42501'; END IF;
  IF p_profile=private.admin_038_actor() THEN
    RAISE EXCEPTION 'Self administration is not allowed' USING ERRCODE='42501'; END IF;
END; $$;

CREATE FUNCTION private.admin_038_cap(p_code TEXT,p_scope TEXT,p_org UUID)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v UUID;
BEGIN
  SELECT id INTO v FROM public.eco_capabilities WHERE code=p_code AND scope=p_scope AND is_active
    AND delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(code,scope);
  IF v IS NULL THEN RAISE EXCEPTION 'Capability not administrable in MICA' USING ERRCODE='42501'; END IF;
  -- A tenant permission manager may never delegate beyond their own effective authority.
  IF p_org IS NOT NULL AND NOT COALESCE(private.can_platform('GLOBAL_USER_MANAGE'),FALSE)
    AND NOT COALESCE(private.can_operate_mica_org(p_org,p_code),FALSE) THEN
    RAISE EXCEPTION 'Cannot delegate an action you do not possess' USING ERRCODE='42501'; END IF;
  RETURN v;
END; $$;

CREATE FUNCTION public.mica_admin_apply(p_action TEXT,p_data JSONB)
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
  -- Serialize administrator mutations, including shared preset edits and recipient assignments.
  PERFORM pg_advisory_xact_lock(380038);
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
      PERFORM private.admin_038_authorize(org,NULL,'ORG_MEMBER_PERMISSION_MANAGE');
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
  ELSE RAISE EXCEPTION 'Unknown administration action';
  END IF;
  INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,target_user_profile_id,metadata)
    VALUES(actor,'MICA_ADMIN_'||upper(p_action),target,jsonb_build_object('organization_id',org,'target_id',result,'changes',p_data));
  RETURN result;
END; $$;

CREATE FUNCTION public.mica_admin_read(p_org UUID DEFAULT NULL,p_search TEXT DEFAULT '')
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor(); global_users BOOLEAN:=COALESCE(private.can_platform('GLOBAL_USER_MANAGE'),FALSE);
  users_allowed BOOLEAN; presets_allowed BOOLEAN; result JSONB;
BEGIN
  IF length(COALESCE(p_search,''))>100 THEN RAISE EXCEPTION 'Search too long'; END IF;
  IF p_org IS NOT NULL AND (NOT EXISTS (SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=actor AND organization_id=p_org)
    OR NOT EXISTS (SELECT 1 FROM public.eco_organizations WHERE id=p_org AND is_active)) THEN
    RAISE EXCEPTION 'Confirmed active tenant context required' USING ERRCODE='42501'; END IF;
  users_allowed:=global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_VIEW'),FALSE));
  presets_allowed:=COALESCE(private.can_platform('PLATFORM_MANAGE'),FALSE)
    OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE));
  SELECT jsonb_build_object(
    'rights',jsonb_build_object(
      'organizations',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE) OR COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'create_organization',COALESCE(private.can_platform('ORGANIZATION_CREATE'),FALSE),
      'update_organization',COALESCE(private.can_platform('ORGANIZATION_UPDATE'),FALSE),
      'archive_organization',COALESCE(private.can_platform('ORGANIZATION_ARCHIVE'),FALSE),
      'users',users_allowed,'global_users',global_users,'presets',presets_allowed,
      'global_presets',COALESCE(private.can_platform('PLATFORM_MANAGE'),FALSE),
      'assignments',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)),
      'memberships',global_users OR (p_org IS NOT NULL AND COALESCE(private.can_operate_mica_org(p_org,'ORG_MEMBER_PERMISSION_MANAGE'),FALSE)
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
        WHERE users_allowed AND (global_users OR EXISTS (SELECT 1 FROM public.eco_organization_members m WHERE m.user_profile_id=p.id AND m.organization_id=p_org))
          AND (COALESCE(p_search,'')='' OR strpos(lower(COALESCE(u.email,'')),lower(p_search))>0)
        ORDER BY u.email,p.id LIMIT 200) q),'[]'::JSONB),
    'capabilities',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',code,'scope',scope,'description',description) ORDER BY scope,code)
      FROM public.eco_capabilities WHERE (presets_allowed OR users_allowed) AND is_active AND delegation_class<>'OWNER_RESERVED'
        AND private.mica_capability_allowed(code,scope) AND (scope='ORGANIZATION' OR global_users OR COALESCE(private.can_platform('PLATFORM_MANAGE'),FALSE))),'[]'::JSONB),
    'presets',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'scope',t.scope,'organization_id',r.organization_id,'is_active',t.is_active,
      'recipients',(SELECT count(*) FROM public.eco_organization_members WHERE role_template_id=t.id)+(SELECT count(*) FROM public.eco_user_platform_role WHERE role_template_id=t.id),
      'capabilities',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB),
      'bridge',COALESCE((SELECT jsonb_agg(c.code ORDER BY c.code) FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
         WHERE g.role_template_id=t.id AND c.delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(c.code,c.scope)),'[]'::JSONB)))
      FROM private.eco_mica_presets r JOIN public.eco_role_templates t ON t.id=r.role_template_id
      WHERE (presets_allowed OR users_allowed) AND (global_users OR COALESCE(private.can_platform('PLATFORM_MANAGE'),FALSE) OR
        (t.scope='ORGANIZATION' AND (r.organization_id IS NULL OR r.organization_id=p_org)))),'[]'::JSONB)
  ) INTO result;
  -- Assignment rows are restricted to the same bounded visible user set.
  RETURN result || jsonb_build_object(
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
END; $$;

-- Revoke any installation-specific default ACL, not just PUBLIC.
DO $acl$
DECLARE r RECORD; a RECORD; who TEXT;
BEGIN
  FOR r IN SELECT oid,relowner,relacl FROM pg_class WHERE oid IN
    ('private.migration_038_backup'::regclass,'private.eco_mica_presets'::regclass,'private.eco_mica_pending_profiles'::regclass) LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(r.relacl,acldefault('r',r.relowner))) WHERE grantee<>r.relowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON TABLE %s FROM %s',r.oid::regclass,who);
    END LOOP;
  END LOOP;
  FOR r IN SELECT oid,proowner,proacl FROM pg_proc WHERE oid IN
    ('public.handle_new_user()'::regprocedure,
     'private.admin_038_actor()'::regprocedure,'private.admin_038_authorize(uuid,text,text)'::regprocedure,
     'private.admin_038_target(uuid)'::regprocedure,'private.admin_038_cap(text,text,uuid)'::regprocedure,
     'public.mica_admin_read(uuid,text)'::regprocedure,'public.mica_admin_apply(text,jsonb)'::regprocedure) LOOP
    FOR a IN SELECT DISTINCT grantee FROM aclexplode(COALESCE(r.proacl,acldefault('f',r.proowner))) WHERE grantee<>r.proowner LOOP
      who:=CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END;
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',r.oid::regprocedure,who);
    END LOOP;
  END LOOP;
END;
$acl$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mica_admin_read(UUID,TEXT),public.mica_admin_apply(TEXT,JSONB) TO authenticated;
INSERT INTO private.migration_038_backup(signature,definition,installed_definition,owner_name,acl)
SELECT oid::regprocedure::TEXT,'',pg_get_functiondef(oid),pg_get_userbyid(proowner),proacl FROM pg_proc WHERE oid IN
  ('private.admin_038_actor()'::regprocedure,'private.admin_038_authorize(uuid,text,text)'::regprocedure,
   'private.admin_038_target(uuid)'::regprocedure,'private.admin_038_cap(text,text,uuid)'::regprocedure,
   'public.mica_admin_read(uuid,text)'::regprocedure,'public.mica_admin_apply(text,jsonb)'::regprocedure);
UPDATE private.migration_038_backup b SET installed_acl=p.proacl FROM pg_proc p WHERE p.oid=to_regprocedure(b.signature);
COMMIT;
