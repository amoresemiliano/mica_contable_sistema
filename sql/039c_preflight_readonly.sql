-- READ ONLY, human execution only. Canonical MICA ourzapkjykzlwsjunzmd.
SELECT signature,hash AS expected_md5,md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS live_md5, p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) AS owner
FROM (VALUES ('private.mica_capability_allowed(text,text)','e0c89e3492e59dd4f0e2a5cf84086b40'),
('private.require_039_import(text,text)','a4f8f9f032e1d1ddef886e9c8306e19c'),
('public.request_failed_import_retry(uuid)','a5b2e0a74413514a34e33e98604052c4'),
('public.persist_import_batch(uuid,jsonb,jsonb)','45814412c9cf62dcb2ea7476da7917a7'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)','ba0d33f9925a622faf528d9445910e98'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)','bdd30c0aade623cc986b7409aca53ed8'),
('public.check_file_importable(text)','bf3df3596d9b6b44d9202052eca29599')) x(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(signature);
SELECT to_jsonb(c) FROM public.eco_capabilities c WHERE code='FISCAL_DOCUMENT_IMPORT';
