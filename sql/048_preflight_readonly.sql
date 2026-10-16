-- Optional manual DEV evidence BEFORE 048 UP. Read-only; no functions/tables created.
-- Run as the migration owner so RLS cannot hide references. Do not run against PROD.
SELECT current_database() AS database_name,current_setting('server_version') AS postgres_version,
  current_setting('server_encoding') AS encoding;

SELECT ns.nspname AS reference_schema,t.relname AS reference_table,c.conname,
  pg_get_constraintdef(c.oid) AS definition,c.convalidated
FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=t.relnamespace
WHERE c.contype='f' AND c.confrelid IN ('public.eco_tax_categories'::regclass,'public.eco_org_tax_categories'::regclass)
ORDER BY 1,2,3;

WITH expected(id,kind) AS (VALUES
 ('c15675d7-be33-4400-84c3-9985e1a59579'::UUID,'HONORARIOS survivor'),
 ('326eaed3-d6cb-4d63-8adb-47116ad94bf5'::UUID,'HONORARIOS duplicate'),
 ('3c86c6f9-aea0-4dc3-98e0-e30836daf0e5'::UUID,'HONORARIOS duplicate'),
 ('46200cf5-c488-47b8-b946-e637885c7c82'::UUID,'HONORARIOS duplicate'),
 ('e26570a7-6e09-40a4-8901-62b835df145e'::UUID,'HONORARIOS duplicate'),
 ('02768384-f366-4fd9-aa0c-a437866cfeb4'::UUID,'TELEFONIA survivor'),
 ('a209c838-d3e3-4e3c-9b4f-4619c83cc336'::UUID,'TELEFONIA duplicate'))
SELECT e.kind,e.id,c.name,c.category_type,c.is_active,
 (SELECT count(*) FROM public.eco_normalized_records WHERE category_id=e.id) AS normalized_records,
 (SELECT count(*) FROM public.eco_financial_movements WHERE category_id=e.id) AS financial_movements,
 (SELECT count(*) FROM public.eco_org_tax_categories WHERE category_id=e.id) AS organization_assignments
FROM expected e LEFT JOIN public.eco_tax_categories c ON c.id=e.id ORDER BY e.kind,e.id;

SELECT c.id AS category_id,c.name,o.id AS organization_id,o.name AS organization,
 a.id AS assignment_id,a.is_assigned,a.is_active,a.custom_name
FROM public.eco_org_tax_categories a JOIN public.eco_tax_categories c ON c.id=a.category_id
JOIN public.eco_organizations o ON o.id=a.organization_id
WHERE c.id IN ('c15675d7-be33-4400-84c3-9985e1a59579','326eaed3-d6cb-4d63-8adb-47116ad94bf5',
 '3c86c6f9-aea0-4dc3-98e0-e30836daf0e5','46200cf5-c488-47b8-b946-e637885c7c82','e26570a7-6e09-40a4-8901-62b835df145e',
 '02768384-f366-4fd9-aa0c-a437866cfeb4','a209c838-d3e3-4e3c-9b4f-4619c83cc336')
ORDER BY c.name,o.name;

WITH definitions AS (
 SELECT id,category_type,lower(btrim(regexp_replace(
  regexp_replace(normalize(name,NFD),U&'[\0300-\036f]','','g'),
  U&'[\0009-\000d\0020\00a0\1680\2000-\200a\2028\2029\202f\205f\3000\feff]+',' ','g'))) AS key
 FROM public.eco_tax_categories)
SELECT category_type,key,count(*) AS definitions,array_agg(id ORDER BY id) AS ids
FROM definitions GROUP BY category_type,key HAVING count(*)>1 OR key='' ORDER BY 1,2;

-- Notice any undeclared/serialized references; 048 UP will abort on them.
DO $readonly$
DECLARE v_column RECORD; n BIGINT;
  duplicate_ids UUID[]:=ARRAY['326eaed3-d6cb-4d63-8adb-47116ad94bf5','3c86c6f9-aea0-4dc3-98e0-e30836daf0e5',
    '46200cf5-c488-47b8-b946-e637885c7c82','e26570a7-6e09-40a4-8901-62b835df145e','a209c838-d3e3-4e3c-9b4f-4619c83cc336']::UUID[];
BEGIN
 FOR v_column IN SELECT ns.nspname,cl.relname,a.attname FROM pg_attribute a
  JOIN pg_class cl ON cl.oid=a.attrelid JOIN pg_namespace ns ON ns.oid=cl.relnamespace
  WHERE ns.nspname IN ('public','private') AND cl.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped
   AND NOT (ns.nspname='public' AND ((cl.relname='eco_tax_categories' AND a.attname='id')
    OR (cl.relname IN ('eco_org_tax_categories','eco_normalized_records','eco_financial_movements') AND a.attname='category_id')))
 LOOP
  EXECUTE format('SELECT count(*) FROM %I.%I t WHERE EXISTS (SELECT 1 FROM unnest($1::uuid[]) ids(id) WHERE position(ids.id::text in t.%I::text)>0)',
    v_column.nspname,v_column.relname,v_column.attname) INTO n USING duplicate_ids;
  IF n>0 THEN RAISE NOTICE '048 additional reference: %.% column % (% rows)',v_column.nspname,v_column.relname,v_column.attname,n; END IF;
 END LOOP;
END;
$readonly$;
