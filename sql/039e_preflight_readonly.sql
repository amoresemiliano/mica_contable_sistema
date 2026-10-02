-- MICA ourzapkjykzlwsjunzmd. PREPARED, NOT EXECUTED. SELECT only.
SELECT current_database(),current_user,to_regclass('private.migration_039d_retry') AS requires_039d,
  to_regclass('private.migration_039e_functions') AS must_be_absent;
SELECT x.signature,x.hash AS expected_body_md5,p.oid::regprocedure AS actual_signature,
  pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.proconfig,p.proacl,
  md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS actual_body_md5,
  pg_get_functiondef(p.oid) AS definition
FROM (VALUES ('public.update_record_classification(uuid,uuid,uuid)','66643e9e4431cd8a4f27a2f689241165'),
('public.update_movement_classification(uuid,uuid,uuid)','21ffbb5e6ad06b08ed9c82a8334d7f6b'),
('public.get_operational_records_page(uuid,uuid,integer)','48bc90f7adce7a7732bc77790d896357'),
('public.get_operational_financials_page(uuid,uuid,integer)','79c6507e19bfd2f207ade00ec90a8779')) x(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature);
SELECT table_name,column_name,data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name IN ('eco_normalized_records','eco_financial_movements')
  AND column_name IN ('id','organization_id','category_id','activity_id','updated_at','updated_by','deleted_at')
ORDER BY table_name,column_name;
