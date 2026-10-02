# Prompt — Jules final re-review

Review the attached revised MICA WP-A1 architecture package.

This is a focused re-review after your previous verdict `APPROVE_WITH_CHANGES`.

Confirm specifically whether the prior blockers/findings are resolved:

1. active context now uses `ON DELETE SET NULL`;
2. ACCOUNTING_SUPERADMIN now has an explicit platform-role → organization-capability bridge that is effective only with active organization membership;
3. platform role `is_active`, role-template `is_active`, and capability `is_active` are explicit requirements;
4. PLATFORM_SUPERADMIN `ACCESS_ANY_ORG` is acknowledged as a future entitlement and does not bypass membership in WP-A1;
5. existing `UNIQUE(organization_id, user_profile_id)` is preserved and tested;
6. WP-A1 avoids split-brain by not migrating real users and not introducing dual-write;
7. explicit ALLOW override semantics are defined.

Do NOT implement anything.

Return only:

VERDICT: APPROVE | APPROVE_WITH_CHANGES | BLOCK

REMAINING_BLOCKERS

REMAINING_HIGH_RISK_FINDINGS

FINAL_RECOMMENDATION
