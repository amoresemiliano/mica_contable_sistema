-- Definitions only; run as privileged DEV owner. No business/private row data.
SELECT s AS signature, md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9))) AS body_md5,
 pg_get_functiondef(p.oid) AS installed_definition
FROM (VALUES
('private.persist_perceptions_chunk_rows(uuid,jsonb,jsonb)'),
('private.persist_financial_chunk_rows(uuid,jsonb,jsonb)'),
('private.reuse_import_chunk_file(uuid,text)'),
('public.persist_import_chunk(uuid,jsonb,jsonb,text,integer,integer)'),
('public.get_resumable_import(text)'),
('public.persist_perceptions_batch(uuid,jsonb,jsonb)'),
('public.persist_financial_movements_batch(uuid,jsonb,jsonb)'),
('private.reuse_039c_file(uuid,text)')
) x(s) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(s);
