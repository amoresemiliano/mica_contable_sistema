-- DEV-MANAGEMENT-REPORTING-01. PREPARED ONLY. No remote execution/deployment.
BEGIN;
SELECT pg_advisory_xact_lock(450045);
DO $preflight$
DECLARE r RECORD;
BEGIN
 IF current_user <> 'postgres' THEN RAISE EXCEPTION '045 requires postgres'; END IF;
 IF to_regclass('private.eco_report_inputs') IS NOT NULL
  OR to_regclass('private.eco_report_snapshots') IS NOT NULL
  OR to_regclass('private.eco_report_events') IS NOT NULL
  OR to_regclass('private.reporting_045_facts') IS NOT NULL
  OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','private') AND (p.proname LIKE 'mica_reporting_%' OR p.proname LIKE 'reporting_045_%'))
 THEN RAISE EXCEPTION '045 already installed or partial installation'; END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private.require_039_action(text)'),('private.current_profile_id()'),('private.active_org_id()'),
  ('public.list_my_organization_contexts()')) x(signature) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature) AND prosecdef
   AND pg_get_userbyid(proowner)='postgres' AND proconfig=ARRAY['search_path=""']::TEXT[]) THEN
   RAISE EXCEPTION '045 missing or insecure dependency: %',r.signature; END IF;
 END LOOP;
 FOR r IN SELECT * FROM (VALUES
  ('private.require_039_action(text)','5851f6359f27fd393863ebb16c1a0b96'),
  ('private.current_profile_id()','85451bc03979e6c32397c813f2404165'),
  ('private.active_org_id()','7e23f8766cac59e774222cdb0909f01c')) x(signature,body_hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(r.signature)
   AND md5(btrim(replace(prosrc,chr(13),''),' '||chr(10)||chr(9)))=r.body_hash) THEN
   RAISE EXCEPTION '045 canonical context/permission definition drift: %',r.signature; END IF;
 END LOOP;
 FOR r IN SELECT * FROM (VALUES
  ('eco_normalized_records','normalized_payload','jsonb'),('eco_normalized_records','organization_id','uuid'),
  ('eco_normalized_records','row_id','uuid'),('eco_normalized_records','category_id','uuid'),
  ('eco_normalized_records','activity_id','uuid'),('eco_normalized_records','fecha','date'),
  ('eco_normalized_records','total','numeric'),('eco_normalized_records','status','text'),
  ('eco_financial_movements','normalized_payload','jsonb'),('eco_financial_movements','organization_id','uuid'),
  ('eco_financial_movements','movement_type','text'),('eco_financial_movements','monto','numeric'),
  ('eco_financial_movements','saldo','numeric'),('eco_financial_movements','periodo','text'),
  ('eco_org_activity_iibb_rates','definition_id','uuid'),('eco_org_activity_iibb_rates','rate','numeric'),
  ('eco_import_rows','parse_status','text')) x(table_name,column_name,data_type) LOOP
  IF NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public'
   AND c.table_name=r.table_name AND c.column_name=r.column_name AND c.data_type=r.data_type) THEN
   RAISE EXCEPTION '045 canonical column missing or changed: %.%',r.table_name,r.column_name; END IF;
 END LOOP;
 IF to_regclass('private.migration_043_functions') IS NULL OR to_regclass('private.eco_manual_records') IS NULL
  OR to_regclass('private.eco_iibb_rate_definitions') IS NULL THEN RAISE EXCEPTION '045 requires canonical 039c/041/043'; END IF;
 FOR r IN SELECT * FROM (VALUES ('REPORT_VIEW'),('REPORT_EXPORT'),('MANUAL_MOVEMENT_EDIT')) x(code) LOOP
  IF NOT EXISTS(SELECT 1 FROM public.eco_capabilities WHERE code=r.code AND scope='ORGANIZATION' AND is_active) THEN
   RAISE EXCEPTION '045 missing canonical capability: %',r.code; END IF;
 END LOOP;
END; $preflight$;

CREATE TABLE private.eco_report_inputs(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
 kind TEXT NOT NULL CHECK(kind IN ('IVA_OPENING','PERIOD_ADJUSTMENT','IIBB_CONFIG','CM_COEFFICIENTS','ANNUAL_TAX','ALERT_SETTINGS')),
 period TEXT NOT NULL CHECK(period ~ '^[0-9]{4}(-(0[1-9]|1[0-2]))?$'), payload JSONB NOT NULL,
 created_by UUID NOT NULL REFERENCES public.eco_user_profiles(id), created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 note TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL CHECK(revision>0),
 UNIQUE(organization_id,kind,period,revision), CHECK(jsonb_typeof(payload)='object')
);
CREATE TABLE private.eco_report_snapshots(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
 report_type TEXT NOT NULL CHECK(report_type IN ('IVA','IIBB','RESULTADOS','GANANCIAS')),
 date_from DATE NOT NULL,date_to DATE NOT NULL, engine_version TEXT NOT NULL CHECK(engine_version='management-v1'),
 input_hash TEXT NOT NULL, inputs JSONB NOT NULL, calculated JSONB NOT NULL, source_manifest JSONB NOT NULL,
 generated_by UUID NOT NULL REFERENCES public.eco_user_profiles(id), generated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
 version INTEGER NOT NULL CHECK(version>0), CHECK(date_from<=date_to),
 UNIQUE(organization_id,report_type,date_from,date_to,version)
);
CREATE TABLE private.eco_report_events(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), organization_id UUID NOT NULL REFERENCES public.eco_organizations(id),
 report_type TEXT NOT NULL CHECK(report_type IN ('IVA','IIBB','RESULTADOS','GANANCIAS')),
 date_from DATE NOT NULL,date_to DATE NOT NULL, snapshot_id UUID REFERENCES private.eco_report_snapshots(id),
 status TEXT NOT NULL CHECK(status IN ('BORRADOR','REVISADO','CERRADO','REABIERTO')),
 actor UUID NOT NULL REFERENCES public.eco_user_profiles(id), happened_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), note TEXT NOT NULL DEFAULT ''
);
CREATE INDEX eco_report_input_lookup ON private.eco_report_inputs(organization_id,kind,period,revision DESC);
CREATE INDEX eco_report_event_lookup ON private.eco_report_events(organization_id,report_type,date_from,date_to,happened_at DESC);
ALTER TABLE private.eco_report_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_report_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.eco_report_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.eco_report_inputs,private.eco_report_snapshots,private.eco_report_events FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.reporting_045_immutable() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'Reporting history is append-only'; END; $$;
CREATE TRIGGER reporting_045_inputs_immutable BEFORE UPDATE OR DELETE ON private.eco_report_inputs FOR EACH ROW EXECUTE FUNCTION private.reporting_045_immutable();
CREATE TRIGGER reporting_045_snapshots_immutable BEFORE UPDATE OR DELETE ON private.eco_report_snapshots FOR EACH ROW EXECUTE FUNCTION private.reporting_045_immutable();
CREATE TRIGGER reporting_045_events_immutable BEFORE UPDATE OR DELETE ON private.eco_report_events FOR EACH ROW EXECUTE FUNCTION private.reporting_045_immutable();

CREATE FUNCTION private.reporting_045_number(p_value TEXT) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_value ~ '^-?[0-9]{1,13}([.][0-9]{1,6})?$' THEN p_value::NUMERIC END;
$$;

-- Internal source projection. Not exposed through PostgREST or direct grants.
CREATE VIEW private.reporting_045_facts AS
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
REVOKE ALL ON private.reporting_045_facts FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.reporting_045_context(p_expected_org UUID,p_from DATE,p_to DATE) RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.require_039_action('REPORT_VIEW');
BEGIN
 IF org IS NULL OR org IS DISTINCT FROM p_expected_org THEN RAISE EXCEPTION 'Reporting context changed' USING ERRCODE='42501'; END IF;
 IF p_from IS NULL OR p_to IS NULL OR p_from>p_to OR p_to>p_from+INTERVAL '36 months' THEN RAISE EXCEPTION 'Reporting range must be at most 36 months'; END IF;
 RETURN org;
END; $$;

CREATE FUNCTION public.mica_reporting_data(p_expected_org UUID,p_from DATE,p_to DATE,p_export BOOLEAN DEFAULT FALSE) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.reporting_045_context(p_expected_org,p_from,p_to); result JSONB;
BEGIN
 IF p_export THEN PERFORM private.require_039_action('REPORT_EXPORT'); END IF;
 WITH facts AS (
  SELECT f.*,COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'activity_id',r.activity_id,'jurisdiction',r.jurisdiction,'rate',r.rate) ORDER BY r.id)
   FROM public.eco_org_activity_iibb_rates r
   WHERE r.organization_id=org AND r.activity_id=f.activity_id AND r.is_active
    AND (r.valid_from IS NULL OR r.valid_from<=f.day) AND (r.valid_to IS NULL OR r.valid_to>=f.day)),'[]') AS rates
  FROM private.reporting_045_facts f WHERE f.organization_id=org AND f.day BETWEEN p_from AND p_to
 ), groups AS (
  SELECT to_char(day,'YYYY-MM') AS month,kind,source_type,category_id,activity_id,supplier,jurisdiction,currency,tax_type,tax_kind,rates,
   count(*) AS count,count(*) FILTER(WHERE net IS NULL AND kind IN ('SALES','PURCHASES','PAYROLL','MANUAL_PURCHASE')) AS missing_net,
   count(*) FILTER(WHERE vat IS NULL AND kind IN ('SALES','PURCHASES','MANUAL_PURCHASE')) AS missing_vat,
   count(*) FILTER(WHERE amount IS NULL) AS missing_amount,
   round(sum(net)*100)::BIGINT AS net,round(sum(taxable)*100)::BIGINT AS taxable,
   round(sum(vat)*100)::BIGINT AS vat,round(sum(amount)*100)::BIGINT AS amount,
   round(sum(amount) FILTER(WHERE (detail->>'credit_note')::BOOLEAN)*100)::BIGINT AS credit_notes,
   round(sum(net) FILTER(WHERE (detail->>'credit_note')::BOOLEAN)*100)::BIGINT AS credit_notes_net,
   round(sum(amount) FILTER(WHERE amount>0)*100)::BIGINT AS income,
   round(-sum(amount) FILTER(WHERE amount<0)*100)::BIGINT AS outflow,
   round(max(abs(amount)) FILTER(WHERE kind='BANK' AND category_id IS NULL)*100)::BIGINT AS largest_unclassified,
   round(sum(salary_net)*100)::BIGINT AS salary_net,round(sum(sac)*100)::BIGINT AS sac
  FROM facts GROUP BY to_char(day,'YYYY-MM'),kind,source_type,category_id,activity_id,supplier,jurisdiction,currency,tax_type,tax_kind,rates
 ), bounds AS (
  SELECT account,count(*) AS observations,min(day) AS first_day,max(day) AS last_day,
   round(min(balance)*100)::BIGINT AS minimum,round(max(balance)*100)::BIGINT AS maximum,round(avg(balance)*100)::BIGINT AS average
  FROM facts f WHERE kind='BANK' AND balance IS NOT NULL GROUP BY account
 ), accounts AS (
  SELECT b.*,
   CASE WHEN (SELECT count(*) FROM facts x WHERE x.kind='BANK' AND x.account IS NOT DISTINCT FROM b.account AND x.balance IS NOT NULL AND x.day=b.first_day)=1
    THEN (SELECT round(x.balance*100)::BIGINT FROM facts x WHERE x.kind='BANK' AND x.account IS NOT DISTINCT FROM b.account AND x.day=b.first_day AND x.balance IS NOT NULL LIMIT 1) END AS first,
   CASE WHEN (SELECT count(*) FROM facts x WHERE x.kind='BANK' AND x.account IS NOT DISTINCT FROM b.account AND x.balance IS NOT NULL AND x.day=b.last_day)=1
    THEN (SELECT round(x.balance*100)::BIGINT FROM facts x WHERE x.kind='BANK' AND x.account IS NOT DISTINCT FROM b.account AND x.day=b.last_day AND x.balance IS NOT NULL LIMIT 1) END AS last
  FROM bounds b
 )
 SELECT jsonb_build_object('organization_id',org,'organization',
  (SELECT jsonb_build_object('name',o.name,'cuit',COALESCE(to_jsonb(o)->>'tax_id',to_jsonb(o)->>'cuit')) FROM public.eco_organizations o WHERE o.id=org),
  'date_from',p_from,'date_to',p_to,'actor',private.current_profile_id(),
  'groups',COALESCE((SELECT jsonb_agg(to_jsonb(g) ORDER BY month,kind,category_id,activity_id,supplier,jurisdiction,currency,tax_type,tax_kind,rates::TEXT) FROM groups g),'[]'),
  'accounts',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY account) FROM accounts a),'[]'),
  'inputs',COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY kind,period) FROM
   (SELECT DISTINCT ON(kind,period) * FROM private.eco_report_inputs WHERE organization_id=org ORDER BY kind,period,revision DESC) i),'[]'),
  'categories',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) ORDER BY c.id) FROM public.eco_tax_categories c
   WHERE c.id IN(SELECT category_id FROM facts)),'[]'),
  'activities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'code',a.arca_code) ORDER BY a.id) FROM public.eco_economic_activities a
   WHERE a.id IN(SELECT activity_id FROM facts)),'[]'),
  'quality',jsonb_build_object('import_issues',(SELECT count(*) FROM public.eco_import_issues i WHERE i.organization_id=org AND i.created_at::DATE BETWEEN p_from AND p_to),
   'excluded_amendments',(SELECT count(*) FROM public.eco_normalized_records n JOIN public.eco_import_rows ir ON ir.id=n.row_id WHERE n.organization_id=org AND n.deleted_at IS NULL AND n.fecha BETWEEN p_from AND p_to AND ir.parse_status='POSSIBLE_AMENDMENT'),
   'undated',(SELECT count(*) FROM private.reporting_045_facts f WHERE f.organization_id=org AND f.day IS NULL))) INTO result;
 RETURN result||jsonb_build_object('input_hash',md5(result::TEXT));
END; $$;

CREATE FUNCTION public.mica_reporting_detail(p_expected_org UUID,p_from DATE,p_to DATE,p_filter JSONB DEFAULT '{}',p_offset INTEGER DEFAULT 0,p_limit INTEGER DEFAULT 100,p_snapshot UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.reporting_045_context(p_expected_org,p_from,p_to);
BEGIN
 IF p_offset<0 OR p_limit NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_filter)<>'object' THEN RAISE EXCEPTION 'Invalid detail page'; END IF;
 IF p_snapshot IS NULL AND p_filter->>'kind' IN ('ISSUES','AMENDMENTS') THEN
  RETURN (WITH records AS (
   SELECT i.id,i.organization_id,i.created_at::DATE AS day,'eco_import_issues'::TEXT AS source_type,i.message AS supplier,NULL::NUMERIC AS amount,
    jsonb_build_object('status',i.status,'record_id',i.record_id,'row_id',i.row_id,'issue_type',i.issue_type) AS detail
   FROM public.eco_import_issues i WHERE p_filter->>'kind'='ISSUES' AND i.organization_id=org AND i.created_at::DATE BETWEEN p_from AND p_to
   UNION ALL
   SELECT n.id,n.organization_id,n.fecha,'eco_normalized_records',n.razon_social,n.total,jsonb_build_object('status','POSSIBLE_AMENDMENT','row_id',n.row_id)
   FROM public.eco_normalized_records n JOIN public.eco_import_rows ir ON ir.id=n.row_id AND ir.organization_id=n.organization_id
   WHERE p_filter->>'kind'='AMENDMENTS' AND n.organization_id=org AND n.deleted_at IS NULL AND n.fecha BETWEEN p_from AND p_to AND ir.parse_status='POSSIBLE_AMENDMENT'
  ) SELECT jsonb_build_object('organization_id',org,'total',(SELECT count(*) FROM records),
   'rows',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY day,id) FROM (SELECT * FROM records ORDER BY day,id OFFSET p_offset LIMIT p_limit) x),'[]')));
 END IF;
 RETURN (WITH source AS (
  SELECT f.* FROM private.reporting_045_facts f WHERE p_snapshot IS NULL AND f.organization_id=org
  UNION ALL
  SELECT f.* FROM private.eco_report_snapshots s,
   LATERAL jsonb_populate_recordset(NULL::private.reporting_045_facts,s.source_manifest) f
  WHERE p_snapshot IS NOT NULL AND s.id=p_snapshot AND s.organization_id=org
 ), filtered AS (
  SELECT f.* FROM source f WHERE f.organization_id=org AND (f.day BETWEEN p_from AND p_to OR (p_filter->>'kind'='UNDATED' AND f.day IS NULL))
   AND (NOT p_filter ? 'kind' OR f.kind=p_filter->>'kind' OR p_filter->>'kind'='UNDATED')
   AND (NOT p_filter ? 'month' OR to_char(f.day,'YYYY-MM')=p_filter->>'month')
   AND (NOT p_filter ? 'category_id' OR f.category_id IS NOT DISTINCT FROM (p_filter->>'category_id')::UUID)
   AND (NOT p_filter ? 'activity_id' OR f.activity_id IS NOT DISTINCT FROM (p_filter->>'activity_id')::UUID)
   AND (NOT p_filter ? 'supplier' OR f.supplier IS NOT DISTINCT FROM p_filter->>'supplier')
   AND (NOT p_filter ? 'tax_type' OR f.tax_type=p_filter->>'tax_type')
   AND (NOT p_filter ? 'tax_kind' OR f.tax_kind=p_filter->>'tax_kind')
   AND (NOT p_filter ? 'jurisdiction' OR f.jurisdiction=p_filter->>'jurisdiction')
   AND (NOT p_filter ? 'currency' OR f.currency=p_filter->>'currency')
 ) SELECT jsonb_build_object('organization_id',org,'total',(SELECT count(*) FROM filtered),
   'rows',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY day,id) FROM (SELECT * FROM filtered ORDER BY day,id OFFSET p_offset LIMIT p_limit) x),'[]')));
END; $$;

CREATE FUNCTION public.mica_reporting_input(p_expected_org UUID,p_kind TEXT,p_period TEXT,p_payload JSONB,p_note TEXT DEFAULT '',p_revision INTEGER DEFAULT 0) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.require_039_action('REPORT_VIEW'); current_revision INTEGER; result UUID;
BEGIN
 PERFORM private.require_039_action('MANUAL_MOVEMENT_EDIT');
 IF org IS NULL OR org IS DISTINCT FROM p_expected_org THEN RAISE EXCEPTION 'Reporting context changed' USING ERRCODE='42501'; END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::TEXT)>131072 OR length(p_note)>2000 THEN RAISE EXCEPTION 'Invalid reporting input'; END IF;
 -- Domain validation is performed by the same versioned engine in the trusted Edge endpoint.
 -- Reject direct unvalidated browser writes: only service_role may call this writer.
 IF auth.role()<>'service_role' THEN RAISE EXCEPTION 'Use the reporting service for validated inputs' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::TEXT||p_kind||p_period,450045));
 SELECT COALESCE(max(revision),0) INTO current_revision FROM private.eco_report_inputs WHERE organization_id=org AND kind=p_kind AND period=p_period;
 IF current_revision<>p_revision THEN RAISE EXCEPTION 'Reporting input revision changed'; END IF;
 INSERT INTO private.eco_report_inputs(organization_id,kind,period,payload,created_by,note,revision)
  VALUES(org,p_kind,p_period,p_payload,private.current_profile_id(),p_note,current_revision+1) RETURNING id INTO result;
 RETURN result;
END; $$;

CREATE FUNCTION public.mica_reporting_history(p_expected_org UUID,p_from DATE,p_to DATE,p_type TEXT,p_snapshot UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID:=private.reporting_045_context(p_expected_org,p_from,p_to);
BEGIN
 IF p_snapshot IS NOT NULL THEN RETURN (SELECT to_jsonb(s)-'source_manifest' FROM private.eco_report_snapshots s WHERE s.id=p_snapshot AND s.organization_id=org); END IF;
 RETURN jsonb_build_object('events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY happened_at DESC,id) FROM private.eco_report_events e
   WHERE e.organization_id=org AND e.report_type=p_type AND e.date_from=p_from AND e.date_to=p_to),'[]'),
  'snapshots',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'version',s.version,'generated_at',s.generated_at,'generated_by',s.generated_by,'report_type',s.report_type) ORDER BY s.version DESC)
   FROM private.eco_report_snapshots s WHERE s.organization_id=org AND s.report_type=p_type AND s.date_from=p_from AND s.date_to=p_to),'[]'));
END; $$;

-- Trusted service writer: explicitly impersonate only the verified JWT subject supplied by Edge.
-- EXECUTE is service_role-only. Browser JWTs cannot choose an actor or provide calculated values.
CREATE FUNCTION public.mica_reporting_service(p_subject UUID,p_expected_org UUID,p_action TEXT,p_data JSONB) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE org UUID; actor UUID; inputs JSONB; snapshot UUID; next_version INTEGER; previous_status TEXT; result UUID;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Reporting service role required' USING ERRCODE='42501'; END IF;
 PERFORM set_config('request.jwt.claim.sub',p_subject::TEXT,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',p_subject,'role','service_role')::TEXT,TRUE);
 org:=private.require_039_action('REPORT_VIEW'); actor:=private.current_profile_id();
 PERFORM 1 FROM public.eco_user_profiles WHERE id=actor FOR SHARE;
 PERFORM 1 FROM public.eco_user_active_context WHERE user_profile_id=actor FOR SHARE;
 IF org IS NULL OR org IS DISTINCT FROM p_expected_org THEN RAISE EXCEPTION 'Reporting context changed' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::TEXT,450045));
 IF p_action='input' THEN
  result:=public.mica_reporting_input(org,p_data->>'kind',p_data->>'period',p_data->'payload',COALESCE(p_data->>'note',''),(p_data->>'revision')::INTEGER);
  RETURN jsonb_build_object('id',result,'organization_id',org);
 END IF;
 IF p_action NOT IN ('review','close','reopen') THEN RAISE EXCEPTION 'Invalid report action'; END IF;
 PERFORM private.require_039_action('REPORT_EXPORT'); PERFORM private.require_039_action('MANUAL_MOVEMENT_EDIT');
 -- Freeze all input tables against concurrent imports/reclassification during verification and capture.
 LOCK TABLE public.eco_normalized_records,public.eco_financial_movements,public.eco_import_rows,public.eco_import_issues,
  public.eco_org_activity_iibb_rates,public.eco_tax_categories,public.eco_economic_activities,public.eco_organizations,
  private.eco_manual_records IN SHARE MODE;
 inputs:=public.mica_reporting_data(org,(p_data->>'source_from')::DATE,(p_data->>'source_to')::DATE,TRUE);
 IF inputs->>'input_hash' IS DISTINCT FROM p_data->>'input_hash' THEN RAISE EXCEPTION 'Report sources changed; regenerate before continuing'; END IF;
 SELECT e.status INTO previous_status FROM private.eco_report_events e WHERE e.organization_id=org AND e.report_type=p_data->>'type'
  AND e.date_from=(p_data->>'from')::DATE AND e.date_to=(p_data->>'to')::DATE ORDER BY happened_at DESC,id DESC LIMIT 1;
 IF previous_status='CERRADO' AND p_action<>'reopen' THEN RAISE EXCEPTION 'Closed report must be explicitly reopened'; END IF;
 IF p_action='reopen' AND previous_status IS DISTINCT FROM 'CERRADO' THEN RAISE EXCEPTION 'Only a closed report can be reopened'; END IF;
 IF p_action='close' THEN
  IF p_data->>'engine_version'<>'management-v1' OR jsonb_typeof(p_data->'calculated') IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid calculated snapshot'; END IF;
  SELECT COALESCE(max(version),0)+1 INTO next_version FROM private.eco_report_snapshots s WHERE s.organization_id=org AND s.report_type=p_data->>'type'
   AND s.date_from=(p_data->>'from')::DATE AND s.date_to=(p_data->>'to')::DATE;
  INSERT INTO private.eco_report_snapshots(organization_id,report_type,date_from,date_to,engine_version,input_hash,inputs,calculated,source_manifest,generated_by,version)
   VALUES(org,p_data->>'type',(p_data->>'from')::DATE,(p_data->>'to')::DATE,'management-v1',inputs->>'input_hash',inputs,p_data->'calculated',
    COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY day,id) FROM private.reporting_045_facts f WHERE f.organization_id=org AND f.day BETWEEN (p_data->>'source_from')::DATE AND (p_data->>'source_to')::DATE),'[]'),actor,next_version)
   RETURNING id INTO snapshot;
 END IF;
 INSERT INTO private.eco_report_events(organization_id,report_type,date_from,date_to,snapshot_id,status,actor,note)
  VALUES(org,p_data->>'type',(p_data->>'from')::DATE,(p_data->>'to')::DATE,snapshot,
   CASE p_action WHEN 'close' THEN 'CERRADO' WHEN 'review' THEN 'REVISADO' ELSE 'REABIERTO' END,actor,COALESCE(p_data->>'note',''));
 RETURN jsonb_build_object('organization_id',org,'snapshot_id',snapshot,'version',next_version);
END; $$;

REVOKE ALL ON FUNCTION private.reporting_045_immutable(),private.reporting_045_number(TEXT),private.reporting_045_context(UUID,DATE,DATE) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.mica_reporting_data(UUID,DATE,DATE,BOOLEAN),public.mica_reporting_detail(UUID,DATE,DATE,JSONB,INTEGER,INTEGER,UUID),public.mica_reporting_history(UUID,DATE,DATE,TEXT,UUID),public.mica_reporting_input(UUID,TEXT,TEXT,JSONB,TEXT,INTEGER),public.mica_reporting_service(UUID,UUID,TEXT,JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mica_reporting_data(UUID,DATE,DATE,BOOLEAN),public.mica_reporting_detail(UUID,DATE,DATE,JSONB,INTEGER,INTEGER,UUID),public.mica_reporting_history(UUID,DATE,DATE,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mica_reporting_service(UUID,UUID,TEXT,JSONB) TO service_role;
COMMIT;
