-- DEV-MANAGEMENT-REPORTING-CURRENCY-01. PREPARED ONLY. No source records are rewritten.
-- PostgreSQL deparses both the installed view and a frozen copy of 045 to pin its
-- semantic definition without depending on pg_get_viewdef whitespace formatting.
BEGIN;
SET LOCAL search_path='';
SELECT pg_advisory_xact_lock(450045);
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION '046 requires postgres'; END IF;
 IF to_regclass('private.migration_046_reporting') IS NOT NULL THEN
  RAISE EXCEPTION '046 already installed or partial installation'; END IF;
 IF to_regclass('private.eco_report_inputs') IS NULL OR to_regclass('private.eco_report_snapshots') IS NULL
  OR to_regclass('private.eco_report_events') IS NULL OR to_regclass('private.reporting_045_facts') IS NULL THEN
  RAISE EXCEPTION '046 requires installed 045'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='public' AND p.proname LIKE 'mica_reporting_%')
   OR (n.nspname='private' AND p.proname IN ('reporting_045_number','reporting_045_context')))<>7 THEN
  RAISE EXCEPTION '046 unexpected reporting function contract'; END IF;
 FOR r IN SELECT * FROM (VALUES
 ('private.reporting_045_number(text)','30e229dbfc5d6b9e117923e612fdaea6',FALSE),
 ('private.reporting_045_context(uuid,date,date)','3ece50644eae16c1f61baa014c6bcbfe',TRUE),
 ('public.mica_reporting_data(uuid,date,date,boolean)','96f716f746e780cecbe6cd8c89499c3e',TRUE),
 ('public.mica_reporting_detail(uuid,date,date,jsonb,integer,integer,uuid)','4a1729369f7d17bcef3d12f4766b6bab',TRUE),
 ('public.mica_reporting_history(uuid,date,date,text,uuid)','597e14ee50ed8f53f423b7da7f5a74b8',TRUE),
 ('public.mica_reporting_input(uuid,text,text,jsonb,text,integer)','1725379d6e9e5a528e051856ff9c9b73',TRUE),
 ('public.mica_reporting_service(uuid,uuid,text,jsonb)','df3af0055bd0e1031b337e8e9a7e8660',TRUE)
 ) x(signature,body_hash,security_definer) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.security_definer
   AND p.proconfig=ARRAY['search_path=""']::TEXT[]
   AND md5(btrim(replace(p.prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.body_hash) THEN
   RAISE EXCEPTION '046 installed reporting function/security drift: %',r.signature; END IF;
  IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=to_regprocedure(r.signature) AND a.privilege_type='EXECUTE'
    AND (a.grantee=0 OR a.grantee=(SELECT oid FROM pg_roles WHERE rolname='anon')
     OR (r.signature LIKE 'public.mica_reporting_service(%' AND a.grantee=(SELECT oid FROM pg_roles WHERE rolname='authenticated')))) THEN
   RAISE EXCEPTION '046 reporting RPC grant drift: %',r.signature; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.reporting_045_facts'::regclass AND relkind='v'
  AND pg_get_userbyid(relowner)='postgres' AND reloptions IS NULL)
  OR has_table_privilege('anon','private.reporting_045_facts','SELECT')
  OR has_table_privilege('authenticated','private.reporting_045_facts','SELECT') THEN
  RAISE EXCEPTION '046 reporting view security drift'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('private.eco_report_inputs'::regclass,'private.eco_report_snapshots'::regclass,
   'private.eco_report_events'::regclass) AND NOT relrowsecurity) THEN RAISE EXCEPTION '046 reporting RLS drift'; END IF;
END; $preflight$;

CREATE TEMP VIEW reporting_046_expected_045 AS
WITH fiscal AS (
 SELECT n.*,n.normalized_payload AS p,
  CASE WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('3','8','13','203','208','213') THEN -1
   WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('1','2','6','7','11','12','201','202','206','207','211','212') THEN 1 END AS sign
 FROM public.eco_normalized_records n JOIN public.eco_import_rows ir ON ir.id=n.row_id AND ir.organization_id=n.organization_id
 WHERE n.deleted_at IS NULL AND n.status='ACCEPTED' AND ir.parse_status='ACCEPTED'
)
SELECT id,organization_id,fecha AS day,
 CASE WHEN tipo_operacion='VENTA' THEN 'SALES' WHEN tipo_operacion='COMPRA' THEN 'PURCHASES' ELSE 'TAX' END AS kind,
 category_id,activity_id,COALESCE(razon_social,cuit,'Sin identificar') AS supplier,
 p->>'jurisdiction' AS jurisdiction,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN p->>'moneda' ELSE 'PES' END AS currency,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign *
  (abs(private.reporting_045_number(p->>'netoGravado'))+abs(private.reporting_045_number(p->>'netoNoGravado'))+abs(private.reporting_045_number(p->>'exento'))) END AS net,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'netoGravado')) END AS taxable,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'totalIva')) END AS vat,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(total) ELSE total END AS amount,
 NULL::NUMERIC AS balance,NULL::NUMERIC AS salary_net,NULL::NUMERIC AS sac,
 NULL::TEXT AS account,
 CASE WHEN record_type='PERCEPCIONES_IVA' THEN 'IVA'
  WHEN record_type='PERCEPCIONES_ARBA' AND p->>'jurisdiction' IN ('CABA','BUENOS AIRES') THEN 'IIBB'
  ELSE p->>'tax_type' END AS tax_type,
 p->>'tipo' AS tax_kind,
 'eco_normalized_records'::TEXT AS source_type,
 jsonb_build_object('row_id',row_id,'voucher',comprobante,'credit_note',sign=-1,'created_at',created_at) AS detail
FROM fiscal WHERE tipo_operacion IN ('VENTA','COMPRA','PERCEPCION')
UNION ALL
SELECT f.id,f.organization_id,
 CASE WHEN f.operation_type='SUELDO' AND f.periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN (f.periodo||'-01')::DATE ELSE f.fecha END,
 CASE WHEN f.operation_type='SUELDO' THEN 'PAYROLL' ELSE 'BANK' END,
 f.category_id,f.activity_id,f.descripcion,NULL,'PES',
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado') END,
 NULL,NULL,
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado')
  WHEN f.movement_type='debit' THEN -abs(f.monto) WHEN f.movement_type='credit' THEN abs(f.monto) END,
 f.saldo,private.reporting_045_number(f.normalized_payload->>'sueldoNeto'),
 private.reporting_045_number(f.normalized_payload->>'sacProporcional'),f.account_identifier,NULL,NULL,
 'eco_financial_movements',jsonb_build_object('row_id',f.row_id,'description',f.descripcion,'created_at',f.created_at)
FROM public.eco_financial_movements f JOIN public.eco_import_rows ir ON ir.id=f.row_id AND ir.organization_id=f.organization_id
WHERE f.deleted_at IS NULL AND ir.parse_status='ACCEPTED' AND f.operation_type IN ('SUELDO','BANCO')
UNION ALL
SELECT m.id,m.organization_id,
 CASE WHEN m.payload->>'kind'='INTERNAL' THEN ((m.payload->'fields'->>'imputacion')||'-01')::DATE
  ELSE to_date(m.payload->'fields'->>'fecha','YYYYMMDD') END,
 CASE WHEN m.payload->>'kind'='PURCHASE' THEN 'MANUAL_PURCHASE'
  WHEN m.payload->'fields'->>'tipo'='Ingreso' THEN 'OTHER_INCOME' ELSE 'OTHER_EXPENSE' END,
 NULL,NULL,m.payload->'fields'->>'razonSocial',NULL,'PES',NULL,NULL,NULL,
 private.reporting_045_number(COALESCE(m.payload->'fields'->>'importe',m.payload->'fields'->>'importeTotal')),
 NULL,NULL,NULL,NULL,NULL,NULL,'eco_manual_records',
 jsonb_build_object('manual',TRUE,'created_by',m.created_by,'created_at',m.created_at,'note',m.payload->'fields'->>'descripcion')
FROM private.eco_manual_records m WHERE m.deleted_at IS NULL;
CREATE TEMP VIEW reporting_046_expected_046 AS
WITH fiscal AS (
 SELECT n.*,n.normalized_payload AS p,
  CASE WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('3','8','13','203','208','213') THEN -1
   WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('1','2','6','7','11','12','201','202','206','207','211','212') THEN 1 END AS sign
 FROM public.eco_normalized_records n JOIN public.eco_import_rows ir ON ir.id=n.row_id AND ir.organization_id=n.organization_id
 WHERE n.deleted_at IS NULL AND n.status='ACCEPTED' AND ir.parse_status='ACCEPTED'
)
SELECT id,organization_id,fecha AS day,
 CASE WHEN tipo_operacion='VENTA' THEN 'SALES' WHEN tipo_operacion='COMPRA' THEN 'PURCHASES' ELSE 'TAX' END AS kind,
 category_id,activity_id,COALESCE(razon_social,cuit,'Sin identificar') AS supplier,
 p->>'jurisdiction' AS jurisdiction,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN
  CASE WHEN upper(btrim(p->>'moneda')) IN ('PES','ARS','$') THEN 'ARS'
   ELSE upper(btrim(p->>'moneda')) END ELSE 'ARS' END AS currency,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign *
  (abs(private.reporting_045_number(p->>'netoGravado'))+abs(private.reporting_045_number(p->>'netoNoGravado'))+abs(private.reporting_045_number(p->>'exento'))) END AS net,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'netoGravado')) END AS taxable,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'totalIva')) END AS vat,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(total) ELSE total END AS amount,
 NULL::NUMERIC AS balance,NULL::NUMERIC AS salary_net,NULL::NUMERIC AS sac,
 NULL::TEXT AS account,
 CASE WHEN record_type='PERCEPCIONES_IVA' THEN 'IVA'
  WHEN record_type='PERCEPCIONES_ARBA' AND p->>'jurisdiction' IN ('CABA','BUENOS AIRES') THEN 'IIBB'
  ELSE p->>'tax_type' END AS tax_type,
 p->>'tipo' AS tax_kind,
 'eco_normalized_records'::TEXT AS source_type,
 jsonb_build_object('row_id',row_id,'voucher',comprobante,'credit_note',sign=-1,'created_at',created_at) AS detail
FROM fiscal WHERE tipo_operacion IN ('VENTA','COMPRA','PERCEPCION')
UNION ALL
SELECT f.id,f.organization_id,
 CASE WHEN f.operation_type='SUELDO' AND f.periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN (f.periodo||'-01')::DATE ELSE f.fecha END,
 CASE WHEN f.operation_type='SUELDO' THEN 'PAYROLL' ELSE 'BANK' END,
 f.category_id,f.activity_id,f.descripcion,NULL,'ARS',
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado') END,
 NULL,NULL,
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado')
  WHEN f.movement_type='debit' THEN -abs(f.monto) WHEN f.movement_type='credit' THEN abs(f.monto) END,
 f.saldo,private.reporting_045_number(f.normalized_payload->>'sueldoNeto'),
 private.reporting_045_number(f.normalized_payload->>'sacProporcional'),f.account_identifier,NULL,NULL,
 'eco_financial_movements',jsonb_build_object('row_id',f.row_id,'description',f.descripcion,'created_at',f.created_at)
FROM public.eco_financial_movements f JOIN public.eco_import_rows ir ON ir.id=f.row_id AND ir.organization_id=f.organization_id
WHERE f.deleted_at IS NULL AND ir.parse_status='ACCEPTED' AND f.operation_type IN ('SUELDO','BANCO')
UNION ALL
SELECT m.id,m.organization_id,
 CASE WHEN m.payload->>'kind'='INTERNAL' THEN ((m.payload->'fields'->>'imputacion')||'-01')::DATE
  ELSE to_date(m.payload->'fields'->>'fecha','YYYYMMDD') END,
 CASE WHEN m.payload->>'kind'='PURCHASE' THEN 'MANUAL_PURCHASE'
  WHEN m.payload->'fields'->>'tipo'='Ingreso' THEN 'OTHER_INCOME' ELSE 'OTHER_EXPENSE' END,
 NULL,NULL,m.payload->'fields'->>'razonSocial',NULL,'ARS',NULL,NULL,NULL,
 private.reporting_045_number(COALESCE(m.payload->'fields'->>'importe',m.payload->'fields'->>'importeTotal')),
 NULL,NULL,NULL,NULL,NULL,NULL,'eco_manual_records',
 jsonb_build_object('manual',TRUE,'created_by',m.created_by,'created_at',m.created_at,'note',m.payload->'fields'->>'descripcion')
FROM private.eco_manual_records m WHERE m.deleted_at IS NULL;
DO $view_pin$
BEGIN
 IF pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM
    pg_get_viewdef('pg_temp.reporting_046_expected_045'::regclass,FALSE) THEN
  RAISE EXCEPTION '046 installed 045 view drift or partial installation'; END IF;
END; $view_pin$;

CREATE TEMP TABLE reporting_046_function_security ON COMMIT DROP AS
 SELECT p.oid,p.proowner,p.proacl,p.prosecdef,p.proconfig,p.prosrc FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname LIKE 'mica_reporting_%')
 OR (n.nspname='private' AND p.proname IN ('reporting_045_number','reporting_045_context'));
CREATE TEMP TABLE reporting_046_relation_security ON COMMIT DROP AS
 SELECT oid,relowner,relacl,reloptions,relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid IN
 ('private.reporting_045_facts'::regclass,'private.eco_report_inputs'::regclass,'private.eco_report_snapshots'::regclass,
 'private.eco_report_events'::regclass,'public.eco_normalized_records'::regclass,'public.eco_financial_movements'::regclass,
 'public.eco_import_rows'::regclass,'private.eco_manual_records'::regclass);
CREATE TABLE private.migration_046_reporting(
 singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK(singleton),
 definition TEXT NOT NULL,installed_definition TEXT,
 view_oid OID NOT NULL,owner_oid OID NOT NULL,acl ACLITEM[],options TEXT[]
);
ALTER TABLE private.migration_046_reporting ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.migration_046_reporting FROM PUBLIC,anon,authenticated;
INSERT INTO private.migration_046_reporting(definition,view_oid,owner_oid,acl,options)
 SELECT pg_get_viewdef(oid,FALSE),oid,relowner,relacl,reloptions FROM pg_class WHERE oid='private.reporting_045_facts'::regclass;

-- Only projected currency changes. Source JSON, amounts, signs and tenant predicates stay intact.
CREATE OR REPLACE VIEW private.reporting_045_facts AS
WITH fiscal AS (
 SELECT n.*,n.normalized_payload AS p,
  CASE WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('3','8','13','203','208','213') THEN -1
   WHEN (n.normalized_payload->>'tipo_cbte')::TEXT IN ('1','2','6','7','11','12','201','202','206','207','211','212') THEN 1 END AS sign
 FROM public.eco_normalized_records n JOIN public.eco_import_rows ir ON ir.id=n.row_id AND ir.organization_id=n.organization_id
 WHERE n.deleted_at IS NULL AND n.status='ACCEPTED' AND ir.parse_status='ACCEPTED'
)
SELECT id,organization_id,fecha AS day,
 CASE WHEN tipo_operacion='VENTA' THEN 'SALES' WHEN tipo_operacion='COMPRA' THEN 'PURCHASES' ELSE 'TAX' END AS kind,
 category_id,activity_id,COALESCE(razon_social,cuit,'Sin identificar') AS supplier,
 p->>'jurisdiction' AS jurisdiction,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN
  CASE WHEN upper(btrim(p->>'moneda')) IN ('PES','ARS','$') THEN 'ARS'
   ELSE upper(btrim(p->>'moneda')) END ELSE 'ARS' END AS currency,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign *
  (abs(private.reporting_045_number(p->>'netoGravado'))+abs(private.reporting_045_number(p->>'netoNoGravado'))+abs(private.reporting_045_number(p->>'exento'))) END AS net,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'netoGravado')) END AS taxable,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(private.reporting_045_number(p->>'totalIva')) END AS vat,
 CASE WHEN tipo_operacion IN ('VENTA','COMPRA') THEN sign*abs(total) ELSE total END AS amount,
 NULL::NUMERIC AS balance,NULL::NUMERIC AS salary_net,NULL::NUMERIC AS sac,
 NULL::TEXT AS account,
 CASE WHEN record_type='PERCEPCIONES_IVA' THEN 'IVA'
  WHEN record_type='PERCEPCIONES_ARBA' AND p->>'jurisdiction' IN ('CABA','BUENOS AIRES') THEN 'IIBB'
  ELSE p->>'tax_type' END AS tax_type,
 p->>'tipo' AS tax_kind,
 'eco_normalized_records'::TEXT AS source_type,
 jsonb_build_object('row_id',row_id,'voucher',comprobante,'credit_note',sign=-1,'created_at',created_at) AS detail
FROM fiscal WHERE tipo_operacion IN ('VENTA','COMPRA','PERCEPCION')
UNION ALL
SELECT f.id,f.organization_id,
 CASE WHEN f.operation_type='SUELDO' AND f.periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN (f.periodo||'-01')::DATE ELSE f.fecha END,
 CASE WHEN f.operation_type='SUELDO' THEN 'PAYROLL' ELSE 'BANK' END,
 f.category_id,f.activity_id,f.descripcion,NULL,'ARS',
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado') END,
 NULL,NULL,
 CASE WHEN f.operation_type='SUELDO' THEN private.reporting_045_number(f.normalized_payload->>'sueldoBrutoCalculado')
  WHEN f.movement_type='debit' THEN -abs(f.monto) WHEN f.movement_type='credit' THEN abs(f.monto) END,
 f.saldo,private.reporting_045_number(f.normalized_payload->>'sueldoNeto'),
 private.reporting_045_number(f.normalized_payload->>'sacProporcional'),f.account_identifier,NULL,NULL,
 'eco_financial_movements',jsonb_build_object('row_id',f.row_id,'description',f.descripcion,'created_at',f.created_at)
FROM public.eco_financial_movements f JOIN public.eco_import_rows ir ON ir.id=f.row_id AND ir.organization_id=f.organization_id
WHERE f.deleted_at IS NULL AND ir.parse_status='ACCEPTED' AND f.operation_type IN ('SUELDO','BANCO')
UNION ALL
SELECT m.id,m.organization_id,
 CASE WHEN m.payload->>'kind'='INTERNAL' THEN ((m.payload->'fields'->>'imputacion')||'-01')::DATE
  ELSE to_date(m.payload->'fields'->>'fecha','YYYYMMDD') END,
 CASE WHEN m.payload->>'kind'='PURCHASE' THEN 'MANUAL_PURCHASE'
  WHEN m.payload->'fields'->>'tipo'='Ingreso' THEN 'OTHER_INCOME' ELSE 'OTHER_EXPENSE' END,
 NULL,NULL,m.payload->'fields'->>'razonSocial',NULL,'ARS',NULL,NULL,NULL,
 private.reporting_045_number(COALESCE(m.payload->'fields'->>'importe',m.payload->'fields'->>'importeTotal')),
 NULL,NULL,NULL,NULL,NULL,NULL,'eco_manual_records',
 jsonb_build_object('manual',TRUE,'created_by',m.created_by,'created_at',m.created_at,'note',m.payload->'fields'->>'descripcion')
FROM private.eco_manual_records m WHERE m.deleted_at IS NULL;
DO $postflight$
BEGIN
 IF pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE) IS DISTINCT FROM
    pg_get_viewdef('pg_temp.reporting_046_expected_046'::regclass,FALSE) THEN RAISE EXCEPTION '046 repaired view mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM reporting_046_function_security b LEFT JOIN pg_proc p ON p.oid=b.oid
  WHERE p.oid IS NULL OR ROW(p.proowner,p.proacl,p.prosecdef,p.proconfig,p.prosrc) IS DISTINCT FROM
   ROW(b.proowner,b.proacl,b.prosecdef,b.proconfig,b.prosrc)) THEN RAISE EXCEPTION '046 reporting function/ACL changed'; END IF;
 IF EXISTS(SELECT 1 FROM reporting_046_relation_security b LEFT JOIN pg_class c ON c.oid=b.oid
  WHERE c.oid IS NULL OR ROW(c.relowner,c.relacl,c.reloptions,c.relrowsecurity,c.relforcerowsecurity) IS DISTINCT FROM
   ROW(b.relowner,b.relacl,b.reloptions,b.relrowsecurity,b.relforcerowsecurity)) THEN RAISE EXCEPTION '046 relation security changed'; END IF;
END; $postflight$;
UPDATE private.migration_046_reporting SET installed_definition=pg_get_viewdef('private.reporting_045_facts'::regclass,FALSE);
DROP VIEW pg_temp.reporting_046_expected_045;
DROP VIEW pg_temp.reporting_046_expected_046;
COMMIT;
