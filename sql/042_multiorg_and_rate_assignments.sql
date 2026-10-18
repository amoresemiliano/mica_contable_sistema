-- DEV-ADMIN-MULTIORG-TAX-01. Prepared only. DO NOT execute remotely.
-- Add tenant context contracts; retain historical 041 and the Platform switch contract.
BEGIN;
SELECT pg_advisory_xact_lock(380038);
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION '042 requires postgres'; END IF;
 IF to_regclass('private.migration_042_functions') IS NOT NULL
  OR to_regprocedure('public.list_my_organization_contexts()') IS NOT NULL
  OR to_regprocedure('public.switch_my_organization_context(uuid)') IS NOT NULL THEN
  RAISE EXCEPTION '042 already installed or partial installation'; END IF;
 FOR r IN SELECT * FROM (VALUES
 ('private.current_profile_id()','85451bc03979e6c32397c813f2404165'),
 ('private.active_org_id()','7e23f8766cac59e774222cdb0909f01c'),
 ('private.org_id()','6b648c441f19bbd13cd63ea14459d303'),
 ('private.platform_org_in_scope(uuid)','0791cb63a9e1038a91b36fec9ece98f4'),
 ('public.list_operational_org_targets()','97ea9970bb25af3eb59ab0a9a4ef0695'),
 ('public.switch_superadmin_org_context(uuid)','2cffd80fe1ad64567fc2a4592284083b'),
 ('public.get_my_operational_context()','6d6dadbe08edad67a69c98da9d9c7698'),
 ('private.admin_041_platform(text,uuid)','0f9f194428a1454dad13314461872cb3'),
 ('private.guard_041_iibb_assignment()','c996383340b1002afcddd1b09d142071'),
 ('public.mica_platform_iibb(text,uuid,jsonb)','619a265fc6696bd2adecf377e3f7db65')
 ) expected(signature,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature) AND p.prosecdef
   AND pg_get_userbyid(p.proowner)='postgres' AND p.proconfig=ARRAY['search_path=""']::TEXT[]
   AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.hash) THEN
   RAISE EXCEPTION '042 canonical function/security drift: %',r.signature; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) g
  WHERE p.oid IN(to_regprocedure('public.get_my_operational_context()'),to_regprocedure('public.mica_platform_iibb(text,uuid,jsonb)'))
   AND g.privilege_type='EXECUTE' AND (g.grantee=0 OR g.grantee=(SELECT oid FROM pg_roles WHERE rolname='anon'))) THEN
  RAISE EXCEPTION '042 public/anon RPC grant drift'; END IF;
END; $preflight$;
CREATE TABLE private.migration_042_functions(signature TEXT PRIMARY KEY,definition TEXT NOT NULL,owner_name NAME NOT NULL,acl ACLITEM[]);
ALTER TABLE private.migration_042_functions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_042_functions FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_042_functions
 SELECT p.oid::regprocedure::TEXT,pg_get_functiondef(p.oid),pg_get_userbyid(p.proowner),p.proacl FROM pg_proc p
 WHERE p.oid IN(to_regprocedure('public.get_my_operational_context()'),to_regprocedure('public.mica_platform_iibb(text,uuid,jsonb)'));

CREATE FUNCTION public.list_my_organization_contexts()
RETURNS TABLE(organization_id UUID,organization_name TEXT,context_type TEXT,role_template_id UUID,role_name TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.current_profile_id();
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE='42501'; END IF;
 IF private.has_mica_platform_role() THEN
  RETURN QUERY SELECT o.id,o.name::TEXT,'ORGANIZATION'::TEXT,t.id,t.name::TEXT
   FROM public.eco_organizations o CROSS JOIN public.eco_user_platform_role r
   JOIN public.eco_role_templates t ON t.id=r.role_template_id
   WHERE r.user_profile_id=actor AND r.is_active AND t.is_active AND t.scope='PLATFORM'
    AND private.platform_org_in_scope(o.id) ORDER BY o.name,o.id;
 ELSE
  RETURN QUERY SELECT o.id,o.name::TEXT,'ORGANIZATION'::TEXT,t.id,t.name::TEXT
   FROM public.eco_organization_members m JOIN public.eco_organizations o ON o.id=m.organization_id
   JOIN public.eco_role_templates t ON t.id=m.role_template_id
   WHERE m.user_profile_id=actor AND m.is_active AND o.is_active AND t.is_active AND t.scope='ORGANIZATION'
   ORDER BY o.name,o.id;
 END IF;
END; $$;

CREATE FUNCTION public.switch_my_organization_context(p_org_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.current_profile_id(); previous UUID; membership UUID;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE='42501'; END IF;
 -- Keep the existing Platform scope/null behavior and audit path unchanged.
 IF private.has_mica_platform_role() THEN PERFORM public.switch_superadmin_org_context(p_org_id); RETURN; END IF;
 PERFORM 1 FROM public.eco_user_profiles WHERE id=actor AND is_active FOR UPDATE;
 IF NOT FOUND OR p_org_id IS NULL THEN RAISE EXCEPTION 'Active organization membership required' USING ERRCODE='42501'; END IF;
 SELECT m.id INTO membership FROM public.eco_organization_members m
  JOIN public.eco_organizations o ON o.id=m.organization_id JOIN public.eco_role_templates t ON t.id=m.role_template_id
  WHERE m.user_profile_id=actor AND m.organization_id=p_org_id AND m.is_active AND o.is_active
   AND t.is_active AND t.scope='ORGANIZATION' FOR SHARE OF m,o,t;
 IF membership IS NULL THEN RAISE EXCEPTION 'Organization missing, inactive or outside active memberships' USING ERRCODE='42501'; END IF;
 previous:=private.active_org_id();
 -- Organization is session context. Never write tenant profile.organization_id or membership ownership.
 INSERT INTO public.eco_user_active_context(user_profile_id,organization_id,updated_at)
  VALUES(actor,p_org_id,clock_timestamp()) ON CONFLICT(user_profile_id) DO UPDATE
  SET organization_id=EXCLUDED.organization_id,updated_at=EXCLUDED.updated_at;
 INSERT INTO public.eco_platform_audit_events(actor_user_profile_id,event_type,metadata)
  VALUES(actor,'ORGANIZATION_CONTEXT_SWITCHED',jsonb_build_object('previous_organization_id',previous,'target_organization_id',p_org_id));
END; $$;

CREATE OR REPLACE FUNCTION public.get_my_operational_context()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.current_profile_id(); org UUID; org_name TEXT; role_name TEXT; role_scope TEXT; role_id UUID; platform BOOLEAN;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE='42501'; END IF;
 -- Resolution can persist a safe initial context, so this reader must be VOLATILE.
 PERFORM 1 FROM public.eco_user_profiles WHERE id=actor AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active authenticated profile required' USING ERRCODE='42501'; END IF;
 platform:=private.has_mica_platform_role(); org:=private.active_org_id();
 IF platform THEN
  IF org IS NOT NULL AND NOT COALESCE(private.platform_org_in_scope(org),FALSE) THEN
   PERFORM public.switch_superadmin_org_context(NULL); org:=NULL;
  END IF;
 ELSE
  IF org IS NULL OR NOT EXISTS(SELECT 1 FROM public.list_my_organization_contexts() c WHERE c.organization_id=org) THEN
   -- Preserve an accessible prior legacy default. Otherwise use the catalogue's name/id order,
   -- never creation order. Every valid membership is immediately exposed in the selector.
   SELECT c.organization_id INTO org FROM public.list_my_organization_contexts() c
    JOIN public.eco_user_profiles p ON p.id=actor AND p.organization_id=c.organization_id;
   IF org IS NULL THEN SELECT c.organization_id INTO org FROM public.list_my_organization_contexts() c
    ORDER BY c.organization_name,c.organization_id LIMIT 1; END IF;
   IF org IS NULL THEN RAISE EXCEPTION 'No active organization membership' USING ERRCODE='42501'; END IF;
   PERFORM public.switch_my_organization_context(org);
  END IF;
 END IF;
 IF org IS NOT NULL THEN
  SELECT o.name INTO org_name FROM public.eco_organizations o WHERE o.id=org AND o.is_active;
  SELECT t.name,t.scope,t.id INTO role_name,role_scope,role_id FROM public.eco_organization_members m
   JOIN public.eco_role_templates t ON t.id=m.role_template_id WHERE m.user_profile_id=actor
   AND m.organization_id=org AND m.is_active AND t.is_active AND t.scope='ORGANIZATION';
 END IF;
 IF role_name IS NULL AND platform THEN
  SELECT t.name,t.scope,t.id INTO role_name,role_scope,role_id FROM public.eco_user_platform_role r
   JOIN public.eco_role_templates t ON t.id=r.role_template_id
   WHERE r.user_profile_id=actor AND r.is_active AND t.is_active AND t.scope='PLATFORM';
 END IF;
 RETURN jsonb_build_object('organization_id',org,'organization_name',org_name,'profile_name',role_name,
  'profile_scope',role_scope,'role_template_id',role_id,'can_switch_platform_context',platform,'can_switch_organization_context',NOT platform);
END; $$;

CREATE OR REPLACE FUNCTION public.mica_platform_iibb(p_action TEXT,p_org UUID DEFAULT NULL,p_data JSONB DEFAULT '{}')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor UUID:=private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org);
 definition private.eco_iibb_rate_definitions%ROWTYPE; result UUID; definitions JSONB; targets JSONB;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR octet_length(p_data::TEXT)>4096 THEN RAISE EXCEPTION 'Invalid rate payload'; END IF;
 PERFORM pg_advisory_xact_lock(380038);
 actor:=private.admin_041_platform('RATE_MANAGE_ANY_ORG',p_org);
 IF p_action='list' THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(d)||jsonb_build_object('activity_name',a.name,'assigned',EXISTS(
   SELECT 1 FROM public.eco_org_activity_iibb_rates r WHERE r.organization_id=p_org AND r.definition_id=d.id AND r.is_active),'activity_assigned',EXISTS(SELECT 1 FROM public.eco_org_economic_activities m WHERE m.organization_id=p_org AND m.activity_id=d.activity_id AND m.is_assigned AND m.is_active AND a.is_active)) ORDER BY a.name,d.jurisdiction,d.valid_from),'[]')
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
    IF NOT definition.is_active THEN RAISE EXCEPTION 'La definición IIBB está inactiva.'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.eco_org_economic_activities m
     JOIN public.eco_economic_activities a ON a.id=m.activity_id WHERE m.organization_id=p_org AND m.activity_id=definition.activity_id AND m.is_assigned AND m.is_active AND a.is_active) THEN
     RAISE EXCEPTION 'Primero asigná la actividad económica % a esta empresa.',
      (SELECT name FROM public.eco_economic_activities WHERE id=definition.activity_id); END IF;
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

REVOKE ALL ON FUNCTION public.list_my_organization_contexts(),public.switch_my_organization_context(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_my_organization_contexts(),public.switch_my_organization_context(UUID) TO authenticated;
-- CREATE OR REPLACE retains owner/grants of the two replaced RPCs.
NOTIFY pgrst,'reload schema';
COMMIT;
