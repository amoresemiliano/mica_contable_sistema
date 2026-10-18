-- Complete additive organization profile contract. Repository preparation only.
-- Canonical apply: 039i (qualified preset lookup); canonical read: 039h.
-- 039j/039k only harden table ACLs. Their grants, policies and guards remain intact.
-- Read uses an explicit JSON field list, so it must include the five new fields.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
DECLARE v_spec RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '040 requires postgres'; END IF;
 FOR v_spec IN SELECT * FROM (VALUES ('public.mica_admin_apply(text,jsonb)','a3fbc3e14522dc603f5ba9010cebd9bf','1a241c49cbf821600b049451b5e8d6d9'),
('public.mica_admin_read(uuid,text)','958c121637b5f71e0157b1abc3b2a58b','d367a07ea4c70bce1bb9a6a826b31983')) expected(signature,previous_hash,installed_hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(v_spec.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef
   AND p.proconfig=ARRAY['search_path=""']::TEXT[]
   AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) IN(v_spec.previous_hash,v_spec.installed_hash)) THEN
   RAISE EXCEPTION '040 canonical function/security drift: %',v_spec.signature;
  END IF;
 END LOOP;
END; $preflight$;
-- CREATE OR REPLACE retains function identity, owner and existing EXECUTE ACL.
CREATE TEMP TABLE migration_040_rpc_security ON COMMIT DROP AS
 SELECT oid,proowner,proacl,prosecdef,proconfig FROM pg_proc
 WHERE oid IN('public.mica_admin_apply(text,jsonb)'::regprocedure,'public.mica_admin_read(uuid,text)'::regprocedure);
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS contact_person TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS website TEXT;
ALTER TABLE public.eco_organizations ADD COLUMN IF NOT EXISTS address TEXT;
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
      IF k NOT IN ('id','name','legal_name','trade_name','tax_id','is_active','phone','email','contact_person','website','address') THEN RAISE EXCEPTION 'Unsupported organization field %',k; END IF;
    END LOOP;
    IF result IS NULL THEN
      PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_CREATE',NULL);
      IF length(btrim(COALESCE(p_data->>'name','')))=0 THEN RAISE EXCEPTION 'Name required'; END IF;
      INSERT INTO public.eco_organizations(name,legal_name,trade_name,tax_id,tax_id_type,country_code,currency,timezone,is_active,phone,email,contact_person,website,address)
        VALUES(btrim(p_data->>'name'),COALESCE(NULLIF(p_data->>'legal_name',''),p_data->>'name'),p_data->>'trade_name',p_data->>'tax_id',
        'CUIT','AR','ARS','America/Argentina/Buenos_Aires',TRUE,p_data->>'phone',p_data->>'email',p_data->>'contact_person',p_data->>'website',p_data->>'address') RETURNING id INTO result;
    ELSE
      SELECT * INTO STRICT old_org FROM public.eco_organizations WHERE id=result FOR UPDATE;
      IF p_data ? 'is_active' THEN
        PERFORM private.admin_038_authorize(NULL,'ORGANIZATION_ARCHIVE',NULL);
      END IF;
      IF NOT p_data ?| ARRAY['name','legal_name','trade_name','tax_id','is_active','phone','email','contact_person','website','address'] THEN RAISE EXCEPTION 'No organization changes supplied'; END IF;
      IF p_data ?| ARRAY['name','legal_name','trade_name','tax_id','phone','email','contact_person','website','address'] THEN
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
        phone=CASE WHEN p_data?'phone' THEN p_data->>'phone' ELSE phone END,
        email=CASE WHEN p_data?'email' THEN p_data->>'email' ELSE email END,
        contact_person=CASE WHEN p_data?'contact_person' THEN p_data->>'contact_person' ELSE contact_person END,
        website=CASE WHEN p_data?'website' THEN p_data->>'website' ELSE website END,
        address=CASE WHEN p_data?'address' THEN p_data->>'address' ELSE address END,
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
    'organizations',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'legal_name',legal_name,'trade_name',trade_name,'tax_id',tax_id,'is_active',is_active,'phone',phone,'email',email,'contact_person',contact_person,'website',website,'address',address))
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
DO $verify$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_temp.migration_040_rpc_security saved
  LEFT JOIN pg_proc p ON p.oid=saved.oid WHERE p.oid IS NULL
   OR p.proowner IS DISTINCT FROM saved.proowner OR p.proacl IS DISTINCT FROM saved.proacl
   OR p.prosecdef IS DISTINCT FROM saved.prosecdef OR p.proconfig IS DISTINCT FROM saved.proconfig) THEN
  RAISE EXCEPTION '040 changed RPC identity/owner/ACL/security/search_path';
 END IF;
END; $verify$;
COMMIT;
