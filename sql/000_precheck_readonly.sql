-- sql/000_precheck_readonly.sql
-- Precheck script for initial migration
SELECT current_database();
SELECT version();
SELECT schema_name FROM information_schema.schemata;
SELECT nspname FROM pg_namespace WHERE nspname = 'private';
SELECT extname FROM pg_extension;
SELECT * FROM pg_type WHERE typname LIKE 'eco_%';
SELECT * FROM pg_class WHERE relname LIKE 'eco_%';
SELECT * FROM pg_constraint WHERE conname LIKE 'eco_%';
SELECT * FROM pg_indexes WHERE indexname LIKE 'eco_%';
SELECT * FROM pg_trigger WHERE tgname LIKE 'eco_%';
SELECT * FROM pg_proc WHERE proname LIKE 'eco_%';
SELECT * FROM pg_tables WHERE schemaname = 'public' AND rowsecurity = true;
SELECT * FROM pg_policies WHERE policyname LIKE 'eco_%';
SELECT * FROM storage.buckets WHERE id = 'eco-imports-private-staging';
SELECT * FROM storage.policies WHERE name LIKE 'eco_%';
