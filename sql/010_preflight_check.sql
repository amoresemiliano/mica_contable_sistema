-- READ-ONLY PRE-FLIGHT CHECK DE MIGRATION 010 V4.1

-- 1. Versión de PostgreSQL y extensión pgcrypto
SELECT version();
SELECT extname, extnamespace::regnamespace AS schema_name, extversion FROM pg_extension WHERE extname = 'pgcrypto';

-- 2. Constraints reales en todas las tablas afectadas
SELECT conrelid::regclass AS table_name, conname, pg_get_constraintdef(oid) AS constraint_def
FROM pg_constraint
WHERE conrelid IN (
  'public.eco_source_imports'::regclass,
  'public.eco_source_files'::regclass,
  'public.eco_import_rows'::regclass,
  'public.eco_normalized_records'::regclass,
  'public.eco_import_issues'::regclass
);

-- 3. Funciones y Firmas Actuales
SELECT p.oid, n.nspname, p.proname, pg_get_function_arguments(p.oid), pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname IN ('public', 'private')
  AND p.proname IN ('create_import', 'persist_import_batch', 'resolve_issue', 'has_issue_access', 'func_role', 'org_id');

-- 4. Conteo de Filas en Tablas eco_*
SELECT 'eco_organizations' AS table_name, count(*) FROM public.eco_organizations
UNION ALL SELECT 'eco_user_profiles', count(*) FROM public.eco_user_profiles
UNION ALL SELECT 'eco_source_imports', count(*) FROM public.eco_source_imports
UNION ALL SELECT 'eco_source_files', count(*) FROM public.eco_source_files
UNION ALL SELECT 'eco_import_rows', count(*) FROM public.eco_import_rows
UNION ALL SELECT 'eco_normalized_records', count(*) FROM public.eco_normalized_records
UNION ALL SELECT 'eco_import_issues', count(*) FROM public.eco_import_issues;

-- 5. Verificación de NULLs que recibirán NOT NULL
SELECT 'eco_user_profiles.organization_id' AS column_check, count(*) AS null_count
FROM public.eco_user_profiles WHERE organization_id IS NULL;

-- 6. Duplicados Potenciales en eco_normalized_records por (organization_id, identity_key, fiscal_fingerprint)
SELECT organization_id, identity_key, fiscal_fingerprint, count(*)
FROM public.eco_normalized_records
WHERE identity_key IS NOT NULL AND fiscal_fingerprint IS NOT NULL
GROUP BY organization_id, identity_key, fiscal_fingerprint
HAVING count(*) > 1;

-- 7. Duplicados Potenciales en eco_source_files por (organization_id, sha256_hash)
SELECT organization_id, sha256_hash, count(*)
FROM public.eco_source_files
WHERE sha256_hash IS NOT NULL
GROUP BY organization_id, sha256_hash
HAVING count(*) > 1;

-- 8. Policies RLS activas en las 5 tablas
SELECT tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename LIKE 'eco_%';

-- 9. Grants en funciones públicas
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name IN ('create_import', 'persist_import_batch', 'resolve_issue', 'check_file_importable');
