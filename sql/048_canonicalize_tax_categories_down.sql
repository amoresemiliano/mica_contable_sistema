-- Restore exact pre-048 category identities only if affected data/schema has not drifted.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';
LOCK TABLE public.eco_tax_categories, public.eco_org_tax_categories,
  public.eco_normalized_records, public.eco_financial_movements,
  public.eco_organizations IN ACCESS EXCLUSIVE MODE;
DO $preflight$
BEGIN
  IF to_regclass('private.migration_048_category_backup') IS NULL
    OR to_regprocedure('public.mica_category_name_key(text)') IS NULL THEN
    RAISE EXCEPTION '048 rollback requires intact migration ledger and normalization function';
  END IF;
END;
$preflight$;
LOCK TABLE private.migration_048_category_backup IN ACCESS EXCLUSIVE MODE;
CREATE TEMP TABLE mica048_ids(id UUID PRIMARY KEY) ON COMMIT DROP;
INSERT INTO mica048_ids
SELECT (m->>'duplicate_id')::UUID FROM private.migration_048_category_backup b, jsonb_array_elements(b.payload->'map') m
UNION SELECT (m->>'survivor_id')::UUID FROM private.migration_048_category_backup b, jsonb_array_elements(b.payload->'map') m;
CREATE OR REPLACE FUNCTION pg_temp.mica048_snapshot()
RETURNS JSONB LANGUAGE sql STABLE SET search_path = '' AS $snapshot$
SELECT jsonb_build_object(
 'categories',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.eco_tax_categories t WHERE t.id IN (SELECT id FROM pg_temp.mica048_ids)),'[]'::jsonb),
 'assignments',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.eco_org_tax_categories t WHERE t.category_id IN (SELECT id FROM pg_temp.mica048_ids)),'[]'::jsonb),
 'records',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.eco_normalized_records t WHERE t.category_id IN (SELECT id FROM pg_temp.mica048_ids)),'[]'::jsonb),
 'financials',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.eco_financial_movements t WHERE t.category_id IN (SELECT id FROM pg_temp.mica048_ids)),'[]'::jsonb),
 'foreign_keys',COALESCE((SELECT jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid)) ORDER BY conrelid::regclass::text,conname)
   FROM pg_constraint WHERE contype='f' AND confrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass)),'[]'::jsonb),
 'schema',jsonb_build_object(
  'columns',(SELECT jsonb_agg(jsonb_build_object('table',a.attrelid::regclass::text,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',NOT a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity,'column_acl',a.attacl,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attrelid::regclass::text,a.attnum)
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attnum>0 AND NOT a.attisdropped
   AND a.attrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),
  'constraints',(SELECT jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid),'validated',convalidated) ORDER BY conrelid::regclass::text,conname)
   FROM pg_constraint WHERE conrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),
  'indexes',(SELECT jsonb_agg(jsonb_build_object('table',i.indrelid::regclass::text,'name',cl.relname,'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'ready',i.indisready) ORDER BY i.indrelid::regclass::text,cl.relname)
   FROM pg_index i JOIN pg_class cl ON cl.oid=i.indexrelid WHERE i.indrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),
  'security',(SELECT jsonb_agg(jsonb_build_object('table',oid::regclass::text,'acl',relacl,'owner',pg_get_userbyid(relowner),'kind',relkind,'rls',relrowsecurity,'force_rls',relforcerowsecurity) ORDER BY oid::regclass::text)
   FROM pg_class WHERE oid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),
  'policies',COALESCE((SELECT jsonb_agg(jsonb_build_object('table',polrelid::regclass::text,'name',polname,'roles',polroles,'command',polcmd,'permissive',polpermissive,'using',pg_get_expr(polqual,polrelid),'check',pg_get_expr(polwithcheck,polrelid)) ORDER BY polrelid::regclass::text,polname)
   FROM pg_policy WHERE polrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),'[]'::jsonb),
  'triggers',COALESCE((SELECT jsonb_agg(jsonb_build_object('table',tgrelid::regclass::text,'name',tgname,'enabled',tgenabled,'definition',pg_get_triggerdef(oid)) ORDER BY tgrelid::regclass::text,tgname)
   FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)),'[]'::jsonb)
  )
);
$snapshot$;

DO $preflight$
DECLARE backup JSONB;
BEGIN
  IF (SELECT count(*) FROM private.migration_048_category_backup)<>1 OR (SELECT count(*) FROM mica048_ids)<>7 THEN
    RAISE EXCEPTION '048 rollback ledger incomplete';
  END IF;
  SELECT payload INTO backup FROM private.migration_048_category_backup;
  IF backup->'before' IS NULL OR backup->'after' IS NULL
    OR pg_temp.mica048_snapshot() IS DISTINCT FROM backup->'after'
    OR pg_get_functiondef('public.mica_category_name_key(text)'::regprocedure) IS DISTINCT FROM backup->>'key_function' THEN
    RAISE EXCEPTION '048 rollback refused: post-migration data/schema/function drift; preserve ledger and investigate';
  END IF;
END;
$preflight$;

ALTER TABLE public.eco_tax_categories DROP CONSTRAINT eco_tax_categories_canonical_name_048_key;
ALTER TABLE public.eco_tax_categories DROP CONSTRAINT eco_tax_categories_nonempty_name_048_check;
ALTER TABLE public.eco_tax_categories DROP COLUMN canonical_name_key;

-- Restore deleted definitions before their FK references. Full rows include original metadata.
INSERT INTO public.eco_tax_categories
SELECT c.* FROM private.migration_048_category_backup b,
  jsonb_populate_recordset(NULL::public.eco_tax_categories,b.payload->'before'->'categories') c
WHERE c.id IN (SELECT (m->>'duplicate_id')::UUID FROM private.migration_048_category_backup l,jsonb_array_elements(l.payload->'map') m);

DO $restore$
DECLARE backup JSONB; r JSONB; table_name TEXT; key_name TEXT; column_list TEXT; value_list TEXT; restored_count BIGINT;
BEGIN
  SELECT payload INTO backup FROM private.migration_048_category_backup;
  FOR table_name,key_name IN VALUES ('eco_normalized_records','records'),('eco_financial_movements','financials') LOOP
    SELECT string_agg(format('%I',attname),',' ORDER BY attnum),
      string_agg(format('b.%I',attname),',' ORDER BY attnum) INTO column_list,value_list
    FROM pg_attribute WHERE attrelid=format('public.%I',table_name)::regclass AND attnum>0 AND NOT attisdropped;
    FOR r IN SELECT value FROM jsonb_array_elements(backup->'before'->key_name) LOOP
      EXECUTE format('UPDATE public.%I t SET (%s)=(SELECT %s FROM jsonb_populate_record(NULL::public.%I,$1) b) WHERE t.id=($1->>''id'')::uuid',
        table_name,column_list,value_list,table_name) USING r;
      GET DIAGNOSTICS restored_count = ROW_COUNT;
      IF restored_count<>1 THEN RAISE EXCEPTION '048 rollback target row missing in %',table_name; END IF;
    END LOOP;
  END LOOP;
END;
$restore$;

-- No incoming assignment FKs are allowed by UP/preflight; exact assignment IDs can be restored.
DELETE FROM public.eco_org_tax_categories WHERE category_id IN (SELECT id FROM mica048_ids);
INSERT INTO public.eco_org_tax_categories
SELECT a.* FROM private.migration_048_category_backup b,
  jsonb_populate_recordset(NULL::public.eco_org_tax_categories,b.payload->'before'->'assignments') a;

DROP FUNCTION public.mica_category_name_key(TEXT); -- RESTRICT: fail if a new dependent object exists.
DO $verify$
BEGIN
  IF pg_temp.mica048_snapshot() IS DISTINCT FROM (SELECT payload->'before' FROM private.migration_048_category_backup) THEN
    RAISE EXCEPTION '048 rollback did not restore exact pre-migration rows/schema/security';
  END IF;
END;
$verify$;
DROP FUNCTION pg_temp.mica048_snapshot();
DROP TABLE private.migration_048_category_backup;
COMMIT;
