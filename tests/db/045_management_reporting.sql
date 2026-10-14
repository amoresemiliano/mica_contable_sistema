-- PREPARED ONLY. No SQL executed by the agent. Manual DEV security/immutability harness.
-- Privileged fixture setup; real public readers run as authenticated/anon. Nothing persists.
BEGIN;
DO $test$
DECLARE subject UUID; actor UUID; org_a UUID; org_b UUID; result JSONB; snapshot UUID; input UUID;
BEGIN
 SELECT auth_user_id INTO STRICT subject FROM private.eco_platform_owner;
 PERFORM set_config('request.jwt.claim.sub',subject::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',subject,'role','authenticated')::TEXT,TRUE);
 actor:=private.current_profile_id();
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(NULL);
 org_a:=public.mica_admin_apply('organization',jsonb_build_object('name','045 fixture A '||gen_random_uuid()));
 org_b:=public.mica_admin_apply('organization',jsonb_build_object('name','045 fixture B '||gen_random_uuid()));
 PERFORM public.switch_superadmin_org_context(org_a);
 result:=public.mica_reporting_data(org_a,'2026-09-01','2026-09-30');
 IF (result->>'organization_id')::UUID IS DISTINCT FROM org_a THEN RAISE EXCEPTION '045 wrong aggregate tenant'; END IF;
 BEGIN
  PERFORM public.mica_reporting_data(org_b,'2026-09-01','2026-09-30');
  RAISE EXCEPTION '045 arbitrary organization read accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_reporting_service(subject,org_a,'close','{}');
  RAISE EXCEPTION '045 browser could write calculated snapshot';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.mica_reporting_input(org_a,'IVA_OPENING','2026-09','{"technical":0,"free":0}');
  RAISE EXCEPTION '045 browser bypassed trusted input validation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
 INSERT INTO private.eco_report_inputs(organization_id,kind,period,payload,created_by,revision)
  VALUES(org_a,'IVA_OPENING','2026-09','{"technical":0,"free":0}',actor,1) RETURNING id INTO input;
 INSERT INTO private.eco_report_snapshots(organization_id,report_type,date_from,date_to,engine_version,input_hash,inputs,calculated,source_manifest,generated_by,version)
  VALUES(org_a,'IVA','2026-09-01','2026-09-30','management-v1','harness','{}','{"frozen":true}','[]',actor,1) RETURNING id INTO snapshot;
 BEGIN
  UPDATE private.eco_report_snapshots SET calculated='{}' WHERE id=snapshot;
  RAISE EXCEPTION '045 snapshot mutation accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Reporting history is append-only' THEN RAISE; END IF; END;
 BEGIN
  DELETE FROM private.eco_report_inputs WHERE id=input;
  RAISE EXCEPTION '045 manual history deletion accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'Reporting history is append-only' THEN RAISE; END IF; END;
 SET LOCAL ROLE authenticated;
 PERFORM public.switch_superadmin_org_context(org_b);
 IF public.mica_reporting_history(org_b,'2026-09-01','2026-09-30','IVA',snapshot) IS NOT NULL THEN
  RAISE EXCEPTION '045 foreign snapshot visible'; END IF;
 result:=public.mica_reporting_detail(org_b,'2026-09-01','2026-09-30','{}',0,100,snapshot);
 IF (result->>'total')::INTEGER<>0 THEN RAISE EXCEPTION '045 foreign snapshot sources visible'; END IF;
 SET LOCAL ROLE anon;
 BEGIN
  PERFORM public.mica_reporting_data(org_b,'2026-09-01','2026-09-30');
  RAISE EXCEPTION '045 anonymous aggregate read accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 RESET ROLE;
END; $test$;
ROLLBACK;
