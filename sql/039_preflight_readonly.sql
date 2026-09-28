-- MICA canonical project ourzapkjykzlwsjunzmd ONLY.
-- Prepared for manual SQL Editor use. SELECT only; not executed by tooling.
-- 1: Expect 18 rows, matches_up_preflight=true. Review arguments/result/ACL.
-- ACLs are captured by UP and restored by DOWN; UP deliberately restricts RPCs
-- to owner/authenticated. Extra LIVE grantees must be reviewed before application.
WITH expected(signature,hash) AS (VALUES ('public.create_import(text,text)','44af4071c2e6efa61c9e34b5201560ee'),
('public.persist_import_batch(uuid,jsonb,jsonb)','4ec257f1deccb099ee3ca43485ad9f40'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','5e51b97b79bfcd556f91a93bca288488'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','32787b5f20ec6781b7c4c51b221f6faa'),
('public.request_failed_import_retry(uuid)','288284ae2611572da43cdd744c58cf1c'),
('public.check_file_importable(text)','11ed6fc83312f88a5d44ec1426765bbe'),
('public.soft_delete_normalized_record(uuid)','c90cb428d54baf598bb4912dcb4d3122'),
('public.soft_delete_financial_movement(uuid)','3a7c75142ac68f354354c09d3fa2214a'),
('public.restore_normalized_record(uuid)','c5d545377a4d27174e718cb3d3eff52a'),
('public.restore_financial_movement(uuid)','9d7a43998cc2cc535ace9764c6a29103'),
('public.update_record_classification(uuid,uuid,uuid)','e3d9687abd70d9974d03668101580ac9'),
('public.update_movement_classification(uuid,uuid,uuid)','7593a3a547813b98bb5bdf1df291e177'),
('public.bulk_update_record_classification(text,date,date,uuid,uuid)','6cc0a335b007b21ded2e58e3c0f4275a'),
('public.get_active_org_iibb_rates()','b514b0f3d1f886303e3a1a7572644cd7'),
('public.get_active_normalized_records()','9dc4cb1cf48e80cce449026367585ab7'),
('public.get_active_financial_movements()','8aeed6886048ea6443b9e6e95c382977'),
('public.get_deleted_normalized_records()','be2172f131e5a008ea82dd7f44b98773'),
('public.get_deleted_financial_movements()','ee4dad2b401a152c78764eaf87217bbb'))
SELECT e.signature, e.hash AS expected_body_md5,
  md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS live_body_md5,
  pg_get_function_arguments(p.oid) AS arguments, pg_get_function_result(p.oid) AS result,
  pg_get_userbyid(p.proowner) AS owner, p.prosecdef, p.provolatile, p.proconfig,
  p.proacl::TEXT AS explicit_acl,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
  COALESCE(p.prosecdef AND pg_get_userbyid(p.proowner)=current_user
    AND p.proconfig @> ARRAY['search_path=""']
    AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9)))=e.hash,FALSE) AS matches_up_preflight
FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
ORDER BY e.signature;

-- 2: Direct dependencies. All must exist; public wrappers require authenticated
-- and deny anon. Private helper ACLs are reported, not redefined by 039.
SELECT x.signature,p.oid IS NOT NULL AS exists,
  pg_get_function_result(p.oid) AS result,pg_get_userbyid(p.proowner) AS owner,
  p.prosecdef,p.proconfig,p.proacl::TEXT AS explicit_acl,
  has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM (VALUES ('private.can_operate_mica_org(uuid,text)'),('public.can_operate_mica_org(uuid,text)'),
  ('private.active_org_id()'),('private.org_id()'),('private.current_profile_id()'),
  ('public.mica_admin_apply(text,jsonb)'),('public.mica_admin_read(uuid,text)')) x(signature)
LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature)
ORDER BY x.signature;

-- 3: Existing 038 objects; 039 backup must be absent.
SELECT name,to_regclass(name) IS NOT NULL AS exists
FROM (VALUES ('private.migration_038_backup'),('private.eco_mica_presets'),
  ('private.eco_mica_pending_profiles'),('private.migration_039_functions')) x(name);

-- 4: Only datasets consumed by 039 policies; each organization_id must be uuid.
SELECT x.name,a.attname,format_type(a.atttypid,a.atttypmod) AS column_type,c.relrowsecurity
FROM (VALUES ('public.eco_normalized_records'),('public.eco_financial_movements'),
  ('public.eco_source_imports'),('public.eco_source_files'),('public.eco_import_rows'),
  ('public.eco_import_issues'),('public.eco_org_tax_categories'),
  ('public.eco_org_economic_activities'),('public.eco_org_activity_iibb_rates')) x(name)
LEFT JOIN pg_class c ON c.oid=to_regclass(x.name)
LEFT JOIN pg_attribute a ON a.attrelid=c.oid AND a.attname='organization_id' AND NOT a.attisdropped
ORDER BY x.name;
