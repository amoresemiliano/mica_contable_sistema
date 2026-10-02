-- MICA ourzapkjykzlwsjunzmd. PREPARED ONLY. Refuses later grants, overrides and security drift.
BEGIN;
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
COMMIT;
