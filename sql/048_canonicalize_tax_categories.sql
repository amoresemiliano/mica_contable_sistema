-- DEV-CATEGORY-CANONICALIZATION-048. Prepared for manual DEV application only.
-- No name-based bulk merge: these five duplicate IDs are the complete mutation set.
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';
LOCK TABLE public.eco_tax_categories, public.eco_org_tax_categories,
  public.eco_normalized_records, public.eco_financial_movements,
  public.eco_organizations IN ACCESS EXCLUSIVE MODE;
-- Freeze the reviewed zero-reference set while checking it and deleting categories.
LOCK TABLE public.eco_classification_rules, public.eco_movement_allocations,
  public.eco_tax_subcategories IN SHARE MODE;

DO $preflight$
BEGIN
  IF current_setting('server_encoding')<>'UTF8' OR current_setting('server_version_num')::INT<130000 THEN
    RAISE EXCEPTION '048 requires PostgreSQL 13+ / UTF8 for built-in Unicode normalization';
  END IF;
  IF to_regclass('private.migration_048_category_backup') IS NOT NULL
     OR to_regprocedure('public.mica_category_name_key(text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_tax_categories'::regclass
       AND attname='canonical_name_key' AND NOT attisdropped) THEN
    RAISE EXCEPTION '048 already installed or object-name drift; do not rerun UP';
  END IF;
END;
$preflight$;

-- No extension dependency: built-in Unicode NFD plus the ECMAScript whitespace set.
CREATE FUNCTION public.mica_category_name_key(p_name TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE SET search_path = '' AS $key$
  SELECT lower(btrim(regexp_replace(
    regexp_replace(normalize(p_name,NFD), U&'[\0300-\036f]', '', 'g'),
    U&'[\0009-\000d\0020\00a0\1680\2000-\200a\2028\2029\202f\205f\3000\feff]+', ' ', 'g')));
$key$;
REVOKE ALL ON FUNCTION public.mica_category_name_key(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mica_category_name_key(TEXT) TO authenticated;

CREATE TEMP TABLE mica048_map(duplicate_id UUID PRIMARY KEY, survivor_id UUID NOT NULL, concept TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO mica048_map VALUES
 ('326eaed3-d6cb-4d63-8adb-47116ad94bf5','c15675d7-be33-4400-84c3-9985e1a59579','honorarios profesionales'),
 ('3c86c6f9-aea0-4dc3-98e0-e30836daf0e5','c15675d7-be33-4400-84c3-9985e1a59579','honorarios profesionales'),
 ('46200cf5-c488-47b8-b946-e637885c7c82','c15675d7-be33-4400-84c3-9985e1a59579','honorarios profesionales'),
 ('e26570a7-6e09-40a4-8901-62b835df145e','c15675d7-be33-4400-84c3-9985e1a59579','honorarios profesionales'),
 ('a209c838-d3e3-4e3c-9b4f-4619c83cc336','02768384-f366-4fd9-aa0c-a437866cfeb4','telefonia');
CREATE TEMP TABLE mica048_ids(id UUID PRIMARY KEY) ON COMMIT DROP;
INSERT INTO mica048_ids SELECT duplicate_id FROM mica048_map UNION SELECT survivor_id FROM mica048_map;

-- Shared UP/DOWN snapshot helper is defined below. It does not persist beyond this session.
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
DECLARE v_row RECORD; n BIGINT; expected BIGINT; baigorria UUID;
BEGIN
  IF public.mica_category_name_key(' TELEFONÍA ')<>'telefonia'
    OR public.mica_category_name_key(' HONORARIOS  PROFESIONALES ')<>'honorarios profesionales'
    OR public.mica_category_name_key(U&'Telefoni\0301a')<>'telefonia' THEN
    RAISE EXCEPTION '048 database normalization/locale incompatible with application contract';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.eco_tax_categories'::regclass
    AND attname IN ('name','category_type') AND NOT attnotnull AND NOT attisdropped) THEN
    RAISE EXCEPTION '048 nullable name/type schema drift would weaken canonical uniqueness';
  END IF;
  -- Every incoming FK is inspected, with exactly one validated FK per explicit pair.
  IF (SELECT count(*) FROM pg_constraint WHERE contype='f'
      AND confrelid='public.eco_tax_categories'::regclass) <> 6 THEN
    RAISE EXCEPTION '048 category FK inventory drift; review pg_constraint before mutation';
  END IF;
  FOR v_row IN SELECT * FROM (VALUES
    ('public.eco_org_tax_categories'::regclass,'category_id','MUTATED',NULL::TEXT),
    ('public.eco_normalized_records'::regclass,'category_id','MUTATED',NULL::TEXT),
    ('public.eco_financial_movements'::regclass,'category_id','MUTATED',NULL::TEXT),
    ('public.eco_classification_rules'::regclass,'target_category_id','VERIFIED_ZERO',NULL::TEXT),
    ('public.eco_movement_allocations'::regclass,'category_id','VERIFIED_ZERO',NULL::TEXT),
    ('public.eco_tax_subcategories'::regclass,'category_id','VERIFIED_ZERO','c')
  ) refs(reference_table,reference_column,reference_scope,required_delete_action)
  LOOP
    SELECT count(*) INTO n FROM pg_constraint c
    JOIN pg_attribute src ON src.attrelid=c.conrelid AND src.attnum=c.conkey[1]
    JOIN pg_attribute dst ON dst.attrelid=c.confrelid AND dst.attnum=c.confkey[1]
    WHERE c.contype='f' AND c.confrelid='public.eco_tax_categories'::regclass
      AND c.conrelid=v_row.reference_table AND src.attname::TEXT=v_row.reference_column
      AND dst.attname='id' AND src.atttypid='uuid'::regtype AND dst.atttypid='uuid'::regtype
      AND array_length(c.conkey,1)=1 AND array_length(c.confkey,1)=1 AND c.convalidated
      AND (v_row.required_delete_action IS NULL OR c.confdeltype::TEXT=v_row.required_delete_action);
    IF n<>1 THEN RAISE EXCEPTION '048 category FK inventory drift for %.%: expected single validated UUID FK to category id',
      v_row.reference_table,v_row.reference_column; END IF;
    IF v_row.reference_scope='VERIFIED_ZERO' THEN
      EXECUTE format('SELECT count(*) FROM %s WHERE %I IN (SELECT duplicate_id FROM pg_temp.mica048_map)',
        v_row.reference_table,v_row.reference_column) INTO n;
      IF n<>0 THEN RAISE EXCEPTION '048 verified-zero reference drift in %.% (% rows); no automatic reassignment or cascading deletion allowed',
        v_row.reference_table,v_row.reference_column,n; END IF;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE contype='f'
      AND confrelid='public.eco_org_tax_categories'::regclass) THEN
    RAISE EXCEPTION '048 assignment rows have incoming references; merge requires review';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (
    'public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,
    'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)) THEN
    RAISE EXCEPTION '048 unreviewed user triggers on affected tables; exact rollback cannot be guaranteed';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attnum>0 AND NOT attisdropped
    AND (attgenerated<>'' OR attidentity<>'') AND attrelid IN (
      'public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass,
      'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass)) THEN
    RAISE EXCEPTION '048 unreviewed generated/identity column; exact restoration requires review';
  END IF;
  IF (SELECT count(*) FROM public.eco_tax_categories WHERE id IN (SELECT id FROM mica048_ids)) <> 7 THEN
    RAISE EXCEPTION '048 survivor or explicit duplicate missing';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_tax_categories c JOIN mica048_ids i ON i.id=c.id
    WHERE c.category_type IS DISTINCT FROM 'EXPENSE' OR public.mica_category_name_key(c.name) IS DISTINCT FROM
      CASE WHEN c.id IN ('02768384-f366-4fd9-aa0c-a437866cfeb4','a209c838-d3e3-4e3c-9b4f-4619c83cc336')
        THEN 'telefonia' ELSE 'honorarios profesionales' END) THEN
    RAISE EXCEPTION '048 expected concept name/category_type drift';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_tax_categories c WHERE c.category_type='EXPENSE'
    AND public.mica_category_name_key(c.name) IN ('honorarios profesionales','telefonia')
    AND c.id NOT IN (SELECT id FROM mica048_ids)) THEN
    RAISE EXCEPTION '048 additional definition of a diagnosed concept; explicit mapping required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_tax_categories WHERE id NOT IN (SELECT duplicate_id FROM mica048_map)
    GROUP BY category_type,public.mica_category_name_key(name) HAVING count(*)>1)
    OR EXISTS (SELECT 1 FROM public.eco_tax_categories WHERE public.mica_category_name_key(name)='') THEN
    RAISE EXCEPTION '048 other canonical-name conflicts/empty names prevent safe global uniqueness';
  END IF;

  -- Fail closed for undeclared scalar/JSON/text references, including historical reports.
  -- Historical JSON is never rewritten automatically. Only the three MUTATED FKs move.
  FOR v_row IN SELECT ns.nspname,cl.relname,a.attname
    FROM pg_attribute a JOIN pg_class cl ON cl.oid=a.attrelid JOIN pg_namespace ns ON ns.oid=cl.relnamespace
    WHERE ns.nspname IN ('public','private') AND cl.relkind IN ('r','p')
      AND a.attnum>0 AND NOT a.attisdropped
      AND NOT (ns.nspname='public' AND (
        (cl.relname='eco_tax_categories' AND a.attname='id') OR
        (cl.relname IN ('eco_org_tax_categories','eco_normalized_records','eco_financial_movements') AND a.attname='category_id')))
  LOOP
    EXECUTE format('SELECT count(*) FROM %I.%I t WHERE EXISTS (SELECT 1 FROM pg_temp.mica048_map m WHERE position(m.duplicate_id::text in t.%I::text)>0)',
      v_row.nspname,v_row.relname,v_row.attname) INTO n;
    IF n>0 THEN RAISE EXCEPTION '048 unreviewed reference in %.% column % (% rows)',v_row.nspname,v_row.relname,v_row.attname,n; END IF;
  END LOOP;

  -- Exact record counts from the supplied DEV diagnosis, including soft-deleted rows.
  FOR v_row IN SELECT id FROM mica048_ids LOOP
    expected := CASE WHEN v_row.id='c15675d7-be33-4400-84c3-9985e1a59579' THEN 15
      WHEN v_row.id='a209c838-d3e3-4e3c-9b4f-4619c83cc336' THEN 1 ELSE 0 END;
    SELECT count(*) INTO n FROM public.eco_normalized_records WHERE category_id=v_row.id;
    IF n<>expected THEN RAISE EXCEPTION '048 normalized reference count drift for %: expected %, found %',v_row.id,expected,n; END IF;
    IF EXISTS (SELECT 1 FROM public.eco_financial_movements WHERE category_id=v_row.id) THEN
      RAISE EXCEPTION '048 unexpected financial reference for %',v_row.id;
    END IF;
  END LOOP;

  SELECT a.organization_id INTO baigorria FROM public.eco_org_tax_categories a
    JOIN public.eco_organizations o ON o.id=a.organization_id
    WHERE a.category_id='c15675d7-be33-4400-84c3-9985e1a59579'
      AND public.mica_category_name_key(o.name) LIKE '%baigorria%';
  IF baigorria IS NULL OR (SELECT count(*) FROM public.eco_organizations WHERE public.mica_category_name_key(name) LIKE '%baigorria%')<>1 THEN
    RAISE EXCEPTION '048 BAIGORRIA identity/assignment drift';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.eco_org_tax_categories WHERE organization_id=baigorria AND category_id='02768384-f366-4fd9-aa0c-a437866cfeb4')
    OR NOT EXISTS (SELECT 1 FROM public.eco_org_tax_categories a JOIN public.eco_organizations o ON o.id=a.organization_id
      WHERE a.category_id='02768384-f366-4fd9-aa0c-a437866cfeb4' AND public.mica_category_name_key(o.name) ~ '^mica( |$)') THEN
    RAISE EXCEPTION '048 Telefonia survivor assignment drift';
  END IF;
  FOR v_row IN SELECT m.*, CASE m.duplicate_id
    WHEN '326eaed3-d6cb-4d63-8adb-47116ad94bf5' THEN 'demo oeste'
    WHEN '3c86c6f9-aea0-4dc3-98e0-e30836daf0e5' THEN 'demo norte'
    WHEN '46200cf5-c488-47b8-b946-e637885c7c82' THEN 'mica'
    WHEN 'a209c838-d3e3-4e3c-9b4f-4619c83cc336' THEN 'demo norte' ELSE NULL END AS org_name FROM mica048_map m
  LOOP
    SELECT count(*) INTO n FROM public.eco_org_tax_categories WHERE category_id=v_row.duplicate_id;
    expected := CASE WHEN v_row.org_name IS NULL THEN 0 ELSE 1 END;
    IF n<>expected OR EXISTS (
      SELECT 1 FROM public.eco_org_tax_categories a JOIN public.eco_organizations o ON o.id=a.organization_id
      WHERE a.category_id=v_row.duplicate_id AND NOT (public.mica_category_name_key(o.name)=v_row.org_name
        OR (v_row.org_name='mica' AND public.mica_category_name_key(o.name) ~ '^mica( |$)'))) THEN
      RAISE EXCEPTION '048 duplicate organization assignment drift for %',v_row.duplicate_id;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.eco_org_tax_categories a JOIN public.eco_organizations o ON o.id=a.organization_id
    WHERE a.category_id IN (SELECT survivor_id FROM mica048_map) AND NOT (
      a.organization_id=baigorria OR public.mica_category_name_key(o.name) ~ '^mica( |$)'
      OR public.mica_category_name_key(o.name)='demo norte'
      OR (a.category_id='c15675d7-be33-4400-84c3-9985e1a59579' AND public.mica_category_name_key(o.name)='demo oeste'))) THEN
    RAISE EXCEPTION '048 survivor organization assignment outside diagnosed/compatible scope';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_normalized_records nr WHERE nr.category_id IN (SELECT id FROM mica048_ids)
    AND NOT EXISTS (SELECT 1 FROM public.eco_org_tax_categories a WHERE a.organization_id=nr.organization_id AND a.category_id=nr.category_id)) THEN
    RAISE EXCEPTION '048 record organization does not match its diagnosed assignment';
  END IF;
  IF EXISTS (SELECT 1 FROM public.eco_normalized_records WHERE category_id='c15675d7-be33-4400-84c3-9985e1a59579' AND organization_id<>baigorria) THEN
    RAISE EXCEPTION '048 Honorarios survivor records outside BAIGORRIA';
  END IF;

  -- Conflicting custom labels or enabled/disabled states are not guessed or silently broadened.
  IF EXISTS (SELECT 1 FROM public.eco_org_tax_categories d JOIN mica048_map m ON m.duplicate_id=d.category_id
    JOIN public.eco_org_tax_categories s ON s.organization_id=d.organization_id AND s.category_id=m.survivor_id
    WHERE s.is_assigned IS DISTINCT FROM d.is_assigned OR s.is_active IS DISTINCT FROM d.is_active
      OR (NULLIF(btrim(s.custom_name),'') IS NOT NULL AND NULLIF(btrim(d.custom_name),'') IS NOT NULL
        AND s.custom_name IS DISTINCT FROM d.custom_name)) THEN
    RAISE EXCEPTION '048 overlapping assignment metadata conflict; explicit resolution required';
  END IF;
END;
$preflight$;

CREATE TABLE private.migration_048_category_backup (
  singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(singleton), payload JSONB NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.migration_048_category_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.migration_048_category_backup FROM PUBLIC, anon, authenticated;
INSERT INTO private.migration_048_category_backup(payload)
SELECT jsonb_build_object('before',pg_temp.mica048_snapshot(),'map',(SELECT jsonb_agg(to_jsonb(m) ORDER BY duplicate_id) FROM mica048_map m));

UPDATE public.eco_normalized_records r SET category_id=m.survivor_id FROM mica048_map m WHERE r.category_id=m.duplicate_id;
UPDATE public.eco_financial_movements r SET category_id=m.survivor_id FROM mica048_map m WHERE r.category_id=m.duplicate_id;
-- Keep the existing survivor assignment ID; fill only an absent custom label.
UPDATE public.eco_org_tax_categories s SET custom_name=COALESCE(NULLIF(btrim(s.custom_name),''),d.custom_name)
FROM public.eco_org_tax_categories d JOIN mica048_map m ON m.duplicate_id=d.category_id
WHERE s.organization_id=d.organization_id AND s.category_id=m.survivor_id AND NULLIF(btrim(s.custom_name),'') IS NULL;
DELETE FROM public.eco_org_tax_categories d USING mica048_map m
WHERE d.category_id=m.duplicate_id AND EXISTS (SELECT 1 FROM public.eco_org_tax_categories s
  WHERE s.organization_id=d.organization_id AND s.category_id=m.survivor_id);
UPDATE public.eco_org_tax_categories a SET category_id=m.survivor_id FROM mica048_map m WHERE a.category_id=m.duplicate_id;
DELETE FROM public.eco_tax_categories c USING mica048_map m WHERE c.id=m.duplicate_id;

ALTER TABLE public.eco_tax_categories ADD COLUMN canonical_name_key TEXT
  GENERATED ALWAYS AS (public.mica_category_name_key(name)) STORED;
ALTER TABLE public.eco_tax_categories ADD CONSTRAINT eco_tax_categories_canonical_name_048_key UNIQUE(category_type,canonical_name_key);
ALTER TABLE public.eco_tax_categories ADD CONSTRAINT eco_tax_categories_nonempty_name_048_check CHECK(canonical_name_key<>'');

DO $postconditions$
BEGIN
  IF EXISTS (SELECT 1 FROM mica048_map m JOIN public.eco_tax_categories c ON c.id=m.duplicate_id)
    OR (SELECT count(*) FROM public.eco_tax_categories WHERE category_type='EXPENSE' AND canonical_name_key='honorarios profesionales')<>1
    OR (SELECT count(*) FROM public.eco_tax_categories WHERE category_type='EXPENSE' AND canonical_name_key='telefonia')<>1
    OR (SELECT count(*) FROM public.eco_normalized_records WHERE category_id='c15675d7-be33-4400-84c3-9985e1a59579')<>15
    OR (SELECT count(*) FROM public.eco_normalized_records WHERE category_id='02768384-f366-4fd9-aa0c-a437866cfeb4')<>1
    OR EXISTS (SELECT 1 FROM public.eco_org_tax_categories WHERE category_id IN (SELECT duplicate_id FROM mica048_map))
    OR EXISTS (SELECT 1 FROM public.eco_normalized_records WHERE category_id IN (SELECT duplicate_id FROM mica048_map))
    OR EXISTS (SELECT 1 FROM public.eco_financial_movements WHERE category_id IN (SELECT duplicate_id FROM mica048_map)) THEN
    RAISE EXCEPTION '048 canonicalization postcondition failed';
  END IF;
END;
$postconditions$;
UPDATE private.migration_048_category_backup SET payload=payload || jsonb_build_object(
  'after',pg_temp.mica048_snapshot(),'key_function',pg_get_functiondef('public.mica_category_name_key(text)'::regprocedure));
DROP FUNCTION pg_temp.mica048_snapshot();
COMMIT;
