-- DEV-ADMIN-FINAL-01. PREPARED ONLY: no SQL executed.
-- Additive Platform contracts. Original tenant RPC bodies/context guards/ACLs are unchanged.
-- New ownership trigger intentionally denies legacy tenant IIBB writes; reads remain unchanged.
-- Requires installed 040. Live schema inspection was unavailable; preflight fails closed on drift.
-- Run with postgres only after reviewing preflight output and negative DB harness.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
LOCK TABLE public.eco_org_activity_iibb_rates IN ACCESS EXCLUSIVE MODE;
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION '041 requires postgres'; END IF;
 IF to_regclass('private.eco_iibb_rate_definitions') IS NOT NULL
  OR to_regprocedure('public.mica_platform_access(text,uuid,jsonb)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public'
   AND table_name='eco_org_activity_iibb_rates' AND column_name='definition_id') THEN
  RAISE EXCEPTION '041 already installed or partial schema'; END IF;
 FOR r IN SELECT * FROM (VALUES ('private.admin_038_actor()','45edc9fdab4ac1f2d5c9a1c252adc5bc'),
 ('private.admin_038_authorize(uuid,text,text)','5014a1eae244e399259c8b32f47f6332'),
 ('private.admin_038_target(uuid)','54af0f26c4fd816f9b6422e9c822c9ff'),
 ('private.platform_org_in_scope(uuid)','0791cb63a9e1038a91b36fec9ece98f4'),
 ('private.has_mica_platform_role()','6556aed246d54a696eaa208e114f871d'),
 ('private.can_platform(text)','70b56c43ed3a35d1aed06b946be27548'),
 ('public.mica_admin_apply(text,jsonb)','1a241c49cbf821600b049451b5e8d6d9'),
 ('public.mica_admin_read(uuid,text)','d367a07ea4c70bce1bb9a6a826b31983'),
 ('public.mica_invitation(text,uuid,jsonb)','ad8728ee56c30e6e763cdc09af4087b2'),
 ('private.admin_039b_users()','739b86af490586adbb5d7c12ff9d751c'),
 ('private.admin_039b_target_visible(uuid)','48f239321f5992a795ba92fd5a2292a9'),
 ('private.admin_038_cap(text,text,uuid)','c3df6ced25bd7408ce8c4e33c912faea')) expected(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature) AND p.prosecdef
   AND pg_get_userbyid(p.proowner)='postgres' AND p.proconfig=ARRAY['search_path=""']::TEXT[]
   AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
   RAISE EXCEPTION '041 canonical function/security drift: %',r.signature; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates WHERE activity_id IS NULL
  OR jurisdiction IS NULL OR length(btrim(jurisdiction))=0 OR rate IS NULL OR rate < 0
  OR (valid_from IS NOT NULL AND valid_to IS NOT NULL AND valid_from > valid_to)) THEN
  RAISE EXCEPTION 'Review invalid historical IIBB rows; 041 never deletes history'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code='RATE_MANAGE_ANY_ORG' AND scope='PLATFORM' AND is_active) THEN
  RAISE EXCEPTION 'Canonical RATE_MANAGE_ANY_ORG required'; END IF;
END; $preflight$;

CREATE TABLE private.eco_iibb_rate_definitions(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 activity_id UUID NOT NULL REFERENCES public.eco_economic_activities(id),
 jurisdiction TEXT NOT NULL CHECK(length(btrim(jurisdiction)) > 0),
 rate NUMERIC(5,2) NOT NULL CHECK(rate >= 0),
 valid_from DATE, valid_to DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(valid_from IS NULL OR valid_to IS NULL OR valid_from <= valid_to)
);
CREATE UNIQUE INDEX eco_iibb_definition_version ON private.eco_iibb_rate_definitions
 (activity_id,jurisdiction,rate,COALESCE(valid_from,'-infinity'::DATE),COALESCE(valid_to,'infinity'::DATE));
ALTER TABLE private.eco_iibb_rate_definitions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.eco_iibb_rate_definitions FROM PUBLIC,anon,authenticated;
ALTER TABLE public.eco_org_activity_iibb_rates ADD COLUMN definition_id UUID
 REFERENCES private.eco_iibb_rate_definitions(id);
-- Preserve every existing row/UUID/value/date/active state. Only attach provenance.
INSERT INTO private.eco_iibb_rate_definitions(activity_id,jurisdiction,rate,valid_from,valid_to,is_active)
 SELECT activity_id,jurisdiction,rate,valid_from,valid_to,bool_or(COALESCE(is_active,FALSE))
 FROM public.eco_org_activity_iibb_rates GROUP BY activity_id,jurisdiction,rate,valid_from,valid_to;
UPDATE public.eco_org_activity_iibb_rates r SET definition_id=d.id
 FROM private.eco_iibb_rate_definitions d WHERE r.activity_id=d.activity_id AND r.jurisdiction=d.jurisdiction
 AND r.rate=d.rate AND r.valid_from IS NOT DISTINCT FROM d.valid_from AND r.valid_to IS NOT DISTINCT FROM d.valid_to;
CREATE INDEX eco_org_iibb_definition ON public.eco_org_activity_iibb_rates(organization_id,definition_id);

-- Cross-org authority deliberately does not call can_operate_mica_org:
-- that function must continue to require confirmed tenant context.
CREATE FUNCTION private.admin_041_platform(p_cap TEXT,p_org UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_038_actor();
BEGIN
 IF NOT private.has_mica_platform_role() OR NOT (CASE WHEN p_cap='GLOBAL_USER_MANAGE'
  THEN COALESCE(private.admin_039b_users(),FALSE) ELSE COALESCE(private.can_platform(p_cap),FALSE) END)
  OR EXISTS(SELECT 1 FROM public.eco_user_active_context WHERE user_profile_id=actor AND organization_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Confirmed Platform administration authority required' USING ERRCODE='42501'; END IF;
 IF p_org IS NOT NULL AND NOT COALESCE(private.platform_org_in_scope(p_org),FALSE) THEN
  RAISE EXCEPTION 'Organization outside explicit Platform scope' USING ERRCODE='42501'; END IF;
 RETURN actor;
END; $$;

CREATE FUNCTION private.admin_041_bridge(p_org UUID,p_code TEXT)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_041_platform('GLOBAL_USER_MANAGE',p_org); cap UUID; effect TEXT;
BEGIN
 IF p_org IS NULL THEN RAISE EXCEPTION 'Explicit organization required' USING ERRCODE='42501'; END IF;
 SELECT id INTO cap FROM public.eco_capabilities WHERE code=p_code AND scope='ORGANIZATION'
  AND is_active AND delegation_class<>'OWNER_RESERVED' AND private.mica_capability_allowed(code,scope);
 IF cap IS NULL THEN RAISE EXCEPTION 'Capability not delegable' USING ERRCODE='42501'; END IF;
 SELECT o.effect INTO effect FROM private.eco_platform_org_overrides o
  WHERE o.user_profile_id=actor AND o.organization_id=p_org AND o.capability_id=cap;
 IF effect='DENY' OR EXISTS(SELECT 1 FROM public.eco_membership_capability_overrides o
  JOIN public.eco_organization_members m ON m.id=o.membership_id
  WHERE m.user_profile_id=actor AND m.organization_id=p_org AND m.is_active AND o.capability_id=cap AND o.effect='DENY') THEN
  RAISE EXCEPTION 'Delegation explicitly denied' USING ERRCODE='42501'; END IF;
 IF effect='ALLOW' THEN RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN public.eco_role_templates t ON t.id=a.role_template_id
  JOIN public.eco_platform_role_org_capabilities g ON g.role_template_id=t.id
  WHERE a.user_profile_id=actor AND a.is_active AND t.is_active AND t.scope='PLATFORM' AND g.capability_id=cap) THEN
  RAISE EXCEPTION 'Required organization authority is not bridged' USING ERRCODE='42501'; END IF;
END; $$;

CREATE FUNCTION private.admin_041_role(p_org UUID,p_role UUID)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE code TEXT;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_templates t JOIN private.eco_mica_presets p ON p.role_template_id=t.id
  WHERE t.id=p_role AND t.is_active AND t.scope='ORGANIZATION' AND t.code<>'ACCOUNTING_SUPERADMIN'
   AND (p.organization_id IS NULL OR p.organization_id=p_org))
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id
   WHERE a.role_template_id=p_role) THEN RAISE EXCEPTION 'Incompatible or protected role' USING ERRCODE='42501'; END IF;
 FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
  WHERE g.role_template_id=p_role LOOP PERFORM private.admin_041_bridge(p_org,code); END LOOP;
END; $$;

CREATE FUNCTION private.admin_041_platform_role(p_role UUID)
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE code TEXT;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.eco_role_templates t JOIN private.eco_mica_presets m ON m.role_template_id=t.id
  WHERE t.id=p_role AND t.is_active AND t.scope='PLATFORM' AND m.organization_id IS NULL
  AND t.code NOT IN('ROOT_TECHNICAL_MICA','VEGEN_PLATFORM_ADMIN','ACCOUNTING_SUPERADMIN'))
  OR EXISTS(SELECT 1 FROM public.eco_user_platform_role a JOIN private.eco_platform_owner o ON o.user_profile_id=a.user_profile_id
   WHERE a.role_template_id=p_role) THEN RAISE EXCEPTION 'Incompatible or protected Platform role' USING ERRCODE='42501'; END IF;
 IF NOT private.is_platform_owner() AND EXISTS(SELECT 1 FROM private.eco_mica_all_org_presets WHERE role_template_id=p_role)
  AND EXISTS(SELECT 1 FROM public.eco_organizations WHERE is_active AND NOT private.platform_org_in_scope(id)) THEN
  RAISE EXCEPTION 'Cannot delegate Platform role beyond explicit scope' USING ERRCODE='42501'; END IF;
 FOR code IN SELECT c.code FROM public.eco_role_template_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
  WHERE g.role_template_id=p_role LOOP PERFORM private.admin_038_cap(code,'PLATFORM',NULL); END LOOP;
 FOR code IN SELECT c.code FROM public.eco_platform_role_org_capabilities g JOIN public.eco_capabilities c ON c.id=g.capability_id
  WHERE g.role_template_id=p_role LOOP PERFORM private.admin_038_cap(code,'ORGANIZATION',NULL); END LOOP;
END; $$;

CREATE FUNCTION public.mica_platform_access(p_action TEXT,p_org UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_041_platform('GLOBAL_USER_MANAGE',p_org); org RECORD; targets JSONB:='[]';
 role_id UUID:=(p_data->>'role_template_id')::UUID; target UUID; auth_id UUID; confirmed BOOLEAN;
 v_email TEXT:=lower(btrim(p_data->>'email')); result UUID; invitation private.eco_mica_invitations%ROWTYPE;
 active BOOLEAN:=COALESCE((p_data->>'is_active')::BOOLEAN,TRUE); candidate RECORD;
 roles JSONB; platform_roles JSONB:='[]'; profiles JSONB; invitations JSONB;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::TEXT)>4096 THEN RAISE EXCEPTION 'Invalid access payload'; END IF;
 PERFORM pg_advisory_xact_lock(380038);
 actor:=private.admin_041_platform('GLOBAL_USER_MANAGE',p_org);
 IF p_action='options' THEN
  FOR org IN SELECT id,name FROM public.eco_organizations WHERE is_active ORDER BY name,id LOOP
   BEGIN
    PERFORM private.admin_041_bridge(org.id,'ORG_MEMBER_INVITE');
    PERFORM private.admin_041_bridge(org.id,'ORG_MEMBER_MANAGE');
    PERFORM private.admin_041_bridge(org.id,'ORG_MEMBER_PRESET_ASSIGN');
    roles:='[]';
    FOR candidate IN SELECT t.id AS role_template_id FROM public.eco_role_templates t
      JOIN private.eco_mica_presets m ON m.role_template_id=t.id
      WHERE t.scope='ORGANIZATION' AND t.is_active AND t.code<>'ACCOUNTING_SUPERADMIN'
       AND (m.organization_id IS NULL OR m.organization_id=org.id) LOOP
      BEGIN
       PERFORM private.admin_041_role(org.id,candidate.role_template_id);
       roles:=roles||(SELECT jsonb_build_array(jsonb_build_object('id',t.id,'name',t.name)) FROM public.eco_role_templates t WHERE t.id=candidate.role_template_id);
      EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    END LOOP;
    targets:=targets||jsonb_build_array(jsonb_build_object('id',org.id,'name',org.name,'roles',roles));
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  FOR candidate IN SELECT t.id,t.name FROM public.eco_role_templates t JOIN private.eco_mica_presets m ON m.role_template_id=t.id
   WHERE t.scope='PLATFORM' AND t.is_active LOOP
   BEGIN
    PERFORM private.admin_041_platform_role(candidate.id);
    platform_roles:=platform_roles||jsonb_build_array(jsonb_build_object('id',candidate.id,'name',candidate.name));
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  RETURN jsonb_build_object('organizations',targets,'platform_roles',platform_roles);
 END IF;
 -- Existing Platform invitation/role path remains canonical, including protected/delegation checks.
 IF p_org IS NULL THEN
  IF p_action<>'save' THEN RAISE EXCEPTION 'Unsupported Platform action'; END IF;
  PERFORM private.admin_041_platform_role(role_id);
  SELECT p.id INTO target FROM auth.users u JOIN public.eco_user_profiles p ON p.auth_user_id=u.id
   WHERE lower(u.email)=v_email AND u.email_confirmed_at IS NOT NULL;
  IF target IS NOT NULL THEN
   result:=public.mica_admin_apply('platform_role',jsonb_build_object('user_profile_id',target,'role_template_id',role_id,'is_active',active));
   RETURN jsonb_build_object('status','ASSIGNED','user_profile_id',result);
  END IF;
  RETURN public.mica_invitation('create',NULL,p_data);
 END IF;
 PERFORM private.admin_041_bridge(p_org,'ORG_MEMBER_INVITE');
 PERFORM private.admin_041_bridge(p_org,'ORG_MEMBER_MANAGE');
 PERFORM private.admin_041_bridge(p_org,'ORG_MEMBER_PRESET_ASSIGN');
 IF p_action='list' THEN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'email',u.email,'name',COALESCE(u.raw_user_meta_data->>'full_name',split_part(u.email,'@',1)),'is_active',p.is_active,
   'pending',NOT p.is_active,'protected',EXISTS(SELECT 1 FROM private.eco_platform_owner o WHERE o.user_profile_id=p.id),
   'membership_id',m.id,'role_template_id',m.role_template_id,'role_name',t.name,'member_active',m.is_active)),'[]')
   INTO profiles FROM public.eco_organization_members m JOIN public.eco_user_profiles p ON p.id=m.user_profile_id
   JOIN auth.users u ON u.id=p.auth_user_id JOIN public.eco_role_templates t ON t.id=m.role_template_id
   WHERE m.organization_id=p_org AND private.admin_039b_target_visible(p.id);
  SELECT COALESCE(jsonb_agg(to_jsonb(i)||jsonb_build_object('user_profile_id',p.id)),'[]') INTO invitations
   FROM private.eco_mica_invitations i LEFT JOIN auth.users u ON lower(u.email)=i.email AND u.email_confirmed_at IS NOT NULL
   LEFT JOIN public.eco_user_profiles p ON p.auth_user_id=u.id WHERE i.organization_id=p_org AND i.assigned_at IS NULL
   AND (p.id IS NULL OR private.admin_039b_target_visible(p.id));
  RETURN jsonb_build_object('users',profiles,'invitations',invitations);
 END IF;
 IF p_action='confirm' THEN
  SELECT * INTO STRICT invitation FROM private.eco_mica_invitations WHERE id=(p_data->>'id')::UUID AND organization_id=p_org FOR UPDATE;
  IF invitation.assigned_at IS NOT NULL THEN RAISE EXCEPTION 'Invitation already assigned'; END IF;
  v_email:=invitation.email; role_id:=invitation.role_template_id;
 ELSIF p_action NOT IN ('save','remove') THEN RAISE EXCEPTION 'Unsupported company action'; END IF;
 IF p_action='remove' THEN
  target:=(p_data->>'user_profile_id')::UUID;
  PERFORM private.admin_038_target(target);
  UPDATE public.eco_organization_members SET is_active=FALSE WHERE organization_id=p_org AND user_profile_id=target RETURNING id INTO result;
  IF result IS NULL THEN RAISE EXCEPTION 'Membership not found in target'; END IF;
 ELSE
  IF v_email IS NULL OR length(v_email)>254 OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN RAISE EXCEPTION 'Invalid email'; END IF;
  PERFORM private.admin_041_role(p_org,role_id);
  SELECT u.id,u.email_confirmed_at IS NOT NULL,p.id INTO auth_id,confirmed,target FROM auth.users u
   LEFT JOIN public.eco_user_profiles p ON p.auth_user_id=u.id WHERE lower(u.email)=v_email;
  IF auth_id IS NOT NULL THEN
   IF NOT confirmed OR target IS NULL THEN RAISE EXCEPTION 'Existing account must authenticate and confirm email; no duplicate invitation'; END IF;
   IF p_action='confirm' AND target IS DISTINCT FROM (p_data->>'user_profile_id')::UUID THEN RAISE EXCEPTION 'Review pending identity again'; END IF;
   PERFORM private.admin_038_target(target);
   IF EXISTS(SELECT 1 FROM public.eco_user_platform_role WHERE user_profile_id=target AND is_active) THEN
    RAISE EXCEPTION 'Platform users require explicit scopes, not artificial membership' USING ERRCODE='42501'; END IF;
   INSERT INTO public.eco_organization_members(organization_id,user_profile_id,role_template_id,is_active)
    VALUES(p_org,target,role_id,active) ON CONFLICT(organization_id,user_profile_id)
    DO UPDATE SET role_template_id=EXCLUDED.role_template_id,is_active=EXCLUDED.is_active RETURNING id INTO result;
   IF p_action='confirm' THEN UPDATE private.eco_mica_invitations SET assigned_to=target,assigned_at=now() WHERE id=invitation.id; END IF;
  ELSE
   IF p_action='confirm' THEN RAISE EXCEPTION 'Account must authenticate first'; END IF;
   INSERT INTO private.eco_mica_invitations(email,organization_id,role_template_id,created_by) VALUES(v_email,p_org,role_id,actor)
    ON CONFLICT(email) DO NOTHING RETURNING id INTO result;
   IF result IS NULL THEN
    SELECT i.id INTO result FROM private.eco_mica_invitations i WHERE i.email=v_email AND i.organization_id=p_org AND i.role_template_id=role_id AND i.assigned_at IS NULL;
    IF result IS NULL THEN RAISE EXCEPTION 'An invitation already exists; review its destination and role'; END IF;
   END IF;
  END IF;
 END IF;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'MICA_PLATFORM_COMPANY_ACCESS',jsonb_build_object('action',p_action,'organization_id',p_org,'user_profile_id',target,'id',result,'role_template_id',role_id));
 RETURN jsonb_build_object('id',result,'user_profile_id',target,'status',CASE WHEN target IS NULL THEN 'PENDING_AUTHENTICATION' ELSE 'ASSIGNED' END,'activated',FALSE);
END; $$;

-- Global-owned snapshots cannot be mutated through legacy tenant RPCs or direct grants.
-- Reading remains governed by the existing tenant RLS and operational snapshot contract.
CREATE FUNCTION private.guard_041_iibb_assignment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE target UUID; definition private.eco_iibb_rate_definitions%ROWTYPE;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'IIBB history cannot be deleted' USING ERRCODE='42501'; END IF;
 target:=NEW.organization_id;
 PERFORM private.admin_041_platform('RATE_MANAGE_ANY_ORG',target);
 IF NEW.definition_id IS NULL THEN RAISE EXCEPTION 'Global rate definition required' USING ERRCODE='42501'; END IF;
 SELECT * INTO STRICT definition FROM private.eco_iibb_rate_definitions WHERE id=NEW.definition_id;
 IF NEW.activity_id IS DISTINCT FROM definition.activity_id OR NEW.jurisdiction IS DISTINCT FROM definition.jurisdiction
  OR NEW.rate IS DISTINCT FROM definition.rate OR NEW.valid_from IS DISTINCT FROM definition.valid_from
  OR NEW.valid_to IS DISTINCT FROM definition.valid_to THEN RAISE EXCEPTION 'Rate version is immutable' USING ERRCODE='42501'; END IF;
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.organization_id IS DISTINCT FROM OLD.organization_id OR NEW.definition_id IS DISTINCT FROM OLD.definition_id) THEN
  RAISE EXCEPTION 'Assignment destination and version are immutable' USING ERRCODE='42501'; END IF;
 IF NEW.is_active AND (TG_OP='INSERT' OR NOT COALESCE(OLD.is_active,FALSE)) THEN
  PERFORM pg_advisory_xact_lock(380038);
  IF NOT definition.is_active OR NOT EXISTS(SELECT 1 FROM public.eco_org_economic_activities m
   JOIN public.eco_economic_activities a ON a.id=m.activity_id WHERE m.organization_id=target
   AND m.activity_id=definition.activity_id AND m.is_assigned AND m.is_active AND a.is_active) THEN
   RAISE EXCEPTION 'Active definition and activity assignment required'; END IF;
  IF EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates r WHERE r.organization_id=target AND r.id<>NEW.id
   AND r.activity_id=NEW.activity_id AND r.jurisdiction=NEW.jurisdiction AND r.is_active
   AND COALESCE(NEW.valid_from,'-infinity'::DATE)<=COALESCE(r.valid_to,'infinity'::DATE)
   AND COALESCE(NEW.valid_to,'infinity'::DATE)>=COALESCE(r.valid_from,'-infinity'::DATE)) THEN
   RAISE EXCEPTION 'Conflicting active rate period'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER guard_041_iibb_assignment BEFORE INSERT OR UPDATE OR DELETE ON public.eco_org_activity_iibb_rates
 FOR EACH ROW EXECUTE FUNCTION private.guard_041_iibb_assignment();
REVOKE ALL ON FUNCTION private.guard_041_iibb_assignment() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.mica_platform_iibb(p_action TEXT,p_org UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org);
 definition private.eco_iibb_rate_definitions%ROWTYPE; result UUID; definitions JSONB; targets JSONB;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::TEXT)>4096 THEN RAISE EXCEPTION 'Invalid rate payload'; END IF;
 PERFORM pg_advisory_xact_lock(380038);
 actor:=private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org);
 IF p_action='list' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(d)||jsonb_build_object('activity_name',a.name,'assigned',EXISTS(
   SELECT 1 FROM public.eco_org_activity_iibb_rates r WHERE r.organization_id=p_org AND r.definition_id=d.id AND r.is_active)) ORDER BY a.name,d.jurisdiction,d.valid_from),'[]')
   INTO definitions FROM private.eco_iibb_rate_definitions d JOIN public.eco_economic_activities a ON a.id=d.activity_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',o.id,'name',o.name) ORDER BY o.name),'[]') INTO targets
   FROM public.eco_organizations o WHERE private.platform_org_in_scope(o.id);
  RETURN jsonb_build_object('definitions',definitions,'organizations',targets,'activities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) ORDER BY a.name) FROM public.eco_economic_activities a WHERE a.is_active),'[]'));
 END IF;
 IF p_action='create' THEN
  IF NOT EXISTS(SELECT 1 FROM public.eco_economic_activities WHERE id=(p_data->>'activity_id')::UUID AND is_active)
   OR length(btrim(COALESCE(p_data->>'jurisdiction','')))=0 OR length(p_data->>'jurisdiction')>160
   OR (p_data->>'rate') IS NULL OR (p_data->>'rate')::NUMERIC<0 OR (p_data->>'rate')::NUMERIC>100 THEN
   RAISE EXCEPTION 'Invalid rate definition'; END IF;
  INSERT INTO private.eco_iibb_rate_definitions(activity_id,jurisdiction,rate,valid_from,valid_to)
   VALUES((p_data->>'activity_id')::UUID,btrim(p_data->>'jurisdiction'),(p_data->>'rate')::NUMERIC,
    NULLIF(p_data->>'valid_from','')::DATE,NULLIF(p_data->>'valid_to','')::DATE) RETURNING id INTO result;
 ELSE
  SELECT * INTO STRICT definition FROM private.eco_iibb_rate_definitions WHERE id=(p_data->>'id')::UUID FOR UPDATE;
  result:=definition.id;
  IF p_action='set_active' THEN
   IF NOT p_data ? 'is_active' OR jsonb_typeof(p_data->'is_active')<>'boolean' THEN RAISE EXCEPTION 'Explicit active state required'; END IF;
   UPDATE private.eco_iibb_rate_definitions SET is_active=(p_data->>'is_active')::BOOLEAN WHERE id=definition.id;
  ELSIF p_action IN ('assign','unassign') THEN
   IF p_org IS NULL THEN RAISE EXCEPTION 'Explicit target organization required' USING ERRCODE='42501'; END IF;
   IF p_action='assign' THEN
    IF NOT definition.is_active OR NOT EXISTS(SELECT 1 FROM public.eco_org_economic_activities m
     JOIN public.eco_economic_activities a ON a.id=m.activity_id WHERE m.organization_id=p_org AND m.activity_id=definition.activity_id AND m.is_assigned AND m.is_active AND a.is_active) THEN
     RAISE EXCEPTION 'Active definition and activity assignment required'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates WHERE organization_id=p_org AND definition_id=definition.id AND is_active) THEN
     IF EXISTS(SELECT 1 FROM public.eco_org_activity_iibb_rates r WHERE r.organization_id=p_org AND r.activity_id=definition.activity_id
      AND r.jurisdiction=definition.jurisdiction AND r.is_active
      AND COALESCE(definition.valid_from,'-infinity'::DATE)<=COALESCE(r.valid_to,'infinity'::DATE)
      AND COALESCE(definition.valid_to,'infinity'::DATE)>=COALESCE(r.valid_from,'-infinity'::DATE)) THEN
      RAISE EXCEPTION 'Conflicting active rate period'; END IF;
     INSERT INTO public.eco_org_activity_iibb_rates(organization_id,activity_id,jurisdiction,rate,valid_from,valid_to,is_active,definition_id)
      VALUES(p_org,definition.activity_id,definition.jurisdiction,definition.rate,definition.valid_from,definition.valid_to,TRUE,definition.id);
    END IF;
   ELSE
    UPDATE public.eco_org_activity_iibb_rates SET is_active=FALSE,updated_at=now()
     WHERE organization_id=p_org AND definition_id=definition.id AND is_active;
   END IF;
  ELSE RAISE EXCEPTION 'Unsupported rate action'; END IF;
 END IF;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'MICA_PLATFORM_IIBB',jsonb_build_object('action',p_action,'organization_id',p_org,'definition_id',result));
 RETURN jsonb_build_object('id',result);
END; $$;

REVOKE ALL ON FUNCTION private.admin_041_platform(TEXT,UUID),private.admin_041_bridge(UUID,TEXT),private.admin_041_role(UUID,UUID) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.admin_041_platform_role(UUID) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.mica_platform_access(TEXT,UUID,JSONB),public.mica_platform_iibb(TEXT,UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mica_platform_access(TEXT,UUID,JSONB),public.mica_platform_iibb(TEXT,UUID,JSONB) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
