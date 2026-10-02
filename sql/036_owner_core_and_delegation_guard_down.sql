-- Manual rollback only; no CASCADE and no reconstruction of the prior helper.
BEGIN;
DO $preflight$
DECLARE b RECORD;
BEGIN
  IF to_regclass('private.migration_036_backup') IS NULL THEN
    RAISE EXCEPTION '036 down: missing LIVE baseline'; END IF;
  LOCK TABLE public.eco_user_platform_role IN SHARE ROW EXCLUSIVE MODE;
  SELECT * INTO STRICT b FROM private.migration_036_backup WHERE singleton;
  -- A harmless post-036 assignment would inherit the old reserved grants on rollback.
  IF (SELECT count(*) FROM public.eco_user_platform_role
    WHERE role_template_id='6331de19-de61-43fb-98cd-7d24f2235359') <> 1
    OR NOT EXISTS (SELECT 1 FROM public.eco_user_platform_role
      WHERE role_template_id='6331de19-de61-43fb-98cd-7d24f2235359'
      AND user_profile_id='9563f41e-cd57-42d9-8626-9b04bd6e5863' AND is_active IS TRUE) THEN
    RAISE EXCEPTION '036 down: owner template assignment drift; restoring grants would delegate the core'; END IF;
  -- 036 never changed the helper owner/ACL. Refuse to discard later administrative changes.
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('private.can_platform(text)')
    AND pg_get_userbyid(proowner)=b.owner_name AND proacl IS NOT DISTINCT FROM b.acl) THEN
    RAISE EXCEPTION '036 down: can_platform owner/ACL drift; review before rollback'; END IF;
END;
$preflight$;
DROP TRIGGER guard_036_grant ON public.eco_role_template_capabilities;
DROP TRIGGER guard_036_grant ON public.eco_user_platform_capability_overrides;
DROP TRIGGER guard_036_grant ON public.eco_platform_role_org_capabilities;
DROP TRIGGER guard_036_grant ON public.eco_membership_capability_overrides;
DROP TRIGGER guard_036_grant ON public.eco_member_capability_overrides;
DROP TRIGGER guard_036_profile ON public.eco_user_profiles;
DROP TRIGGER guard_036_platform_role ON public.eco_user_platform_role;
DROP TRIGGER guard_036_profile_truncate ON public.eco_user_profiles;
DROP TRIGGER guard_036_role_truncate ON public.eco_user_platform_role;
DROP TRIGGER guard_036_capability ON public.eco_capabilities;
DROP TRIGGER guard_036_capability_truncate ON public.eco_capabilities;
DROP TRIGGER guard_036_template ON public.eco_role_templates;
-- Replacing the existing function preserves its original ACL (including NULL/default ACL).
DO $restore$
DECLARE b RECORD;
BEGIN
  SELECT * INTO STRICT b FROM private.migration_036_backup WHERE singleton;
  EXECUTE b.definition;
  INSERT INTO public.eco_role_template_capabilities
  SELECT * FROM jsonb_populate_recordset(NULL::public.eco_role_template_capabilities,b.reserved_grants);
  -- No ON CONFLICT: altered grants must fail rather than silently overwrite later changes.
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='private.can_platform(text)'::regprocedure
    AND pg_get_functiondef(oid)=b.definition AND pg_get_userbyid(proowner)=b.owner_name
    AND proacl IS NOT DISTINCT FROM b.acl) THEN RAISE EXCEPTION '036 down: helper restoration differs'; END IF;
END;
$restore$;
DROP FUNCTION public.get_capability_delegation_contract();
DROP FUNCTION private.guard_036_grant();
DROP FUNCTION private.guard_036_identity();
DROP FUNCTION private.guard_036_capability();
DROP FUNCTION private.guard_036_template();
DROP FUNCTION private.is_platform_owner();
DROP TRIGGER guard_036_owner_frozen ON private.eco_platform_owner;
DROP TRIGGER guard_036_reserved_frozen ON private.eco_owner_reserved_capabilities;
DROP TRIGGER guard_036_backup_frozen ON private.migration_036_backup;
DROP TABLE private.eco_owner_reserved_capabilities;
DROP TABLE private.eco_platform_owner;
DROP TABLE private.migration_036_backup;
DROP FUNCTION private.guard_036_frozen();
-- This column/constraint did not exist before 036 (enforced by the up preflight).
ALTER TABLE public.eco_capabilities DROP CONSTRAINT eco_capabilities_036_delegation_check;
ALTER TABLE public.eco_capabilities DROP COLUMN delegation_class;
COMMIT;
