-- MICA ourzapkjykzlwsjunzmd. 039i PREPARED ONLY. No SQL executed by the agent.
-- Only qualifies the deprecated-preset lookup. No data/grant/scope/authority changes.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '039i requires postgres'; END IF;
 IF to_regclass('private.migration_039g_create') IS NULL
  OR to_regclass('private.migration_039h_state') IS NULL
  OR to_regclass('private.migration_039h_functions') IS NULL THEN
  RAISE EXCEPTION '039g and 039h must be installed'; END IF;
 IF to_regclass('private.migration_039i_function') IS NOT NULL THEN RAISE EXCEPTION '039i already installed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row JOIN private.migration_039h_functions saved_function
   ON saved_function.signature='public.mica_admin_apply(text,jsonb)'
   WHERE proc_row.oid=to_regprocedure(saved_function.signature)
    AND pg_get_userbyid(proc_row.proowner)='postgres' AND proc_row.prosecdef
    AND proc_row.proconfig=ARRAY['search_path=""']::TEXT[]
    AND pg_get_functiondef(proc_row.oid)=saved_function.installed
    AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
    AND saved_function.owner_name='postgres'
    AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='eebb7bac1017afb6e46b0cdb90a5d423') THEN
  RAISE EXCEPTION '039i exact 039h definition/owner/ACL/security drift'; END IF;
END; $preflight$;
CREATE TABLE private.migration_039i_function(
 id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(id),definition TEXT NOT NULL,installed TEXT,
 owner_name TEXT NOT NULL,acl JSONB,settings TEXT[],security_definer BOOLEAN NOT NULL);
ALTER TABLE private.migration_039i_function ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_039i_function FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_039i_function(id,definition,owner_name,acl,settings,security_definer)
 SELECT TRUE,pg_get_functiondef(proc_row.oid),pg_get_userbyid(proc_row.proowner),to_jsonb(proc_row.proacl),proc_row.proconfig,proc_row.prosecdef
 FROM pg_proc proc_row WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)');
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
  IF EXISTS(SELECT 1 FROM public.eco_role_templates rt WHERE rt.code='ACCOUNTING_SUPERADMIN'
    AND ((p_action='preset' AND rt.id=result) OR (p_action IN ('platform_role','membership') AND rt.id=tpl))) THEN
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
DO $verify$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc proc_row CROSS JOIN private.migration_039i_function saved_function
  WHERE proc_row.oid=to_regprocedure('public.mica_admin_apply(text,jsonb)')
   AND pg_get_userbyid(proc_row.proowner)=saved_function.owner_name
   AND to_jsonb(proc_row.proacl) IS NOT DISTINCT FROM saved_function.acl
   AND proc_row.proconfig IS NOT DISTINCT FROM saved_function.settings
   AND proc_row.prosecdef=saved_function.security_definer
   AND md5(btrim(replace(proc_row.prosrc,chr(13),''),' '||chr(10)||chr(9)))='a3fbc3e14522dc603f5ba9010cebd9bf') THEN
  RAISE EXCEPTION '039i installation changed owner/ACL/security or unexpected body'; END IF;
 UPDATE private.migration_039i_function SET installed=pg_get_functiondef(to_regprocedure('public.mica_admin_apply(text,jsonb)'));
END; $verify$;
COMMIT;
