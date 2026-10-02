-- sql/006_postcheck_readonly.sql
-- Postcheck script for initial migration
SELECT * FROM pg_class WHERE relname LIKE 'eco_%';
SELECT nspname FROM pg_namespace WHERE nspname = 'private';
SELECT * FROM pg_proc WHERE proname IN ('org_id', 'func_role') AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'private');
SELECT * FROM pg_tables WHERE schemaname = 'public' AND rowsecurity = true AND tablename LIKE 'eco_%';
SELECT * FROM pg_policies WHERE policyname LIKE 'eco_%' OR tablename LIKE 'eco_%';
SELECT * FROM storage.buckets WHERE id = 'eco-imports-private-staging';
SELECT * FROM storage.policies WHERE name LIKE 'eco_%' OR name LIKE 'Allow org%';
