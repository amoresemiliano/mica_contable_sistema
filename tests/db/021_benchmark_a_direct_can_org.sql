-- ============================================================
-- DB PERFORMANCE BENCHMARK — PATTERN A: DIRECT PER-ROW can_org
-- WP-A3.2.0 (Migration 021 Validation)
-- ============================================================
-- Evaluates query plan shape and buffer usage for per-row function evaluation.
-- Contains a single self-contained EXPLAIN statement for Supabase SQL Editor.
-- Enclosed strictly in BEGIN ... ROLLBACK with ZERO persistent state.
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_norte_org_id CONSTANT UUID := '38419581-8163-482c-9813-616fa6214d71'::UUID;
  v_sur_org_id   CONSTANT UUID := 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;
  v_oeste_org_id CONSTANT UUID := '1f5d071f-a09e-4825-9f12-88533383599e'::UUID;
  
  v_synth_auth_id     UUID := gen_random_uuid();
  v_synth_profile_id  UUID;
  v_accountant_tpl_id UUID;
BEGIN
  -- 1. Create synthetic test identity in auth.users (trigger creates eco_user_profiles)
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) VALUES (
    v_synth_auth_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'bench_user_a_' || v_synth_auth_id::text || '@mica.test',
    'fake_encrypted_password',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

  -- 2. Resolve auto-created profile and activate
  SELECT id INTO v_synth_profile_id
  FROM public.eco_user_profiles
  WHERE auth_user_id = v_synth_auth_id;

  IF v_synth_profile_id IS NULL THEN
    RAISE EXCEPTION 'Benchmark Error: eco_user_profiles row was not automatically created for auth.users id %', v_synth_auth_id;
  END IF;

  UPDATE public.eco_user_profiles
  SET is_active = TRUE
  WHERE id = v_synth_profile_id;

  -- 3. Assign ACCOUNTANT role template in Org NORTE (grants RECORD_VIEW capability)
  SELECT id INTO v_accountant_tpl_id
  FROM public.eco_role_templates
  WHERE code = 'ACCOUNTANT';

  INSERT INTO public.eco_organization_members (
    organization_id,
    user_profile_id,
    role_template_id,
    is_active
  ) VALUES (
    v_norte_org_id,
    v_synth_profile_id,
    v_accountant_tpl_id,
    TRUE
  );

  -- 4. Set transaction-local JWT identity claim for synthetic user
  PERFORM set_config('request.jwt.claim.sub', v_synth_auth_id::text, true);

  -- 5. Create temporary benchmark table
  CREATE TEMP TABLE temp_bench_financial_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  ) ON COMMIT DROP;

  -- Populate exactly 10,000 synthetic records:
  --   5,000 rows in NORTE (authorized for caller)
  --   2,500 rows in SUR   (unauthorized for caller)
  --   2,500 rows in OESTE (unauthorized for caller)
  INSERT INTO temp_bench_financial_records (organization_id, amount, description)
  SELECT v_norte_org_id, (random() * 10000)::numeric(15,2), 'NORTE record #' || g
  FROM generate_series(1, 5000) AS g;

  INSERT INTO temp_bench_financial_records (organization_id, amount, description)
  SELECT v_sur_org_id, (random() * 10000)::numeric(15,2), 'SUR record #' || g
  FROM generate_series(1, 2500) AS g;

  INSERT INTO temp_bench_financial_records (organization_id, amount, description)
  SELECT v_oeste_org_id, (random() * 10000)::numeric(15,2), 'OESTE record #' || g
  FROM generate_series(1, 2500) AS g;

  CREATE INDEX idx_temp_bench_records_org ON temp_bench_financial_records(organization_id);
  ANALYZE temp_bench_financial_records;

  RAISE NOTICE 'Benchmark fixture initialized: 10,000 synthetic records created for Pattern A.';
END $$;

-- ============================================================
-- EXPLAIN ANALYZE — PATTERN A: Direct Per-Row can_org Invocation
-- ============================================================
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT COUNT(*), SUM(amount)
FROM temp_bench_financial_records
WHERE private.can_org(organization_id, 'RECORD_VIEW');

ROLLBACK;
