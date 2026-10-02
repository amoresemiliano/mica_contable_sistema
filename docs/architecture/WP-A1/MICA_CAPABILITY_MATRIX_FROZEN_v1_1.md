# MICA — Capability Matrix v1.1

Status: **REVISED/FROZEN FOR RE-REVIEW**

## Platform capabilities

| Capability | PLATFORM_SUPERADMIN | ACCOUNTING_SUPERADMIN |
|---|---:|---:|
| PLATFORM_MANAGE | YES | NO |
| ORGANIZATION_CREATE | YES | NO |
| ORGANIZATION_UPDATE | YES | NO |
| ORGANIZATION_ARCHIVE | YES | NO |
| GLOBAL_USER_MANAGE | YES | NO |
| PLAN_MANAGE | YES | NO |
| GLOBAL_CATALOG_VIEW | YES | YES |
| GLOBAL_CATALOG_MANAGE | YES | NO |
| CATALOG_ASSIGN_ANY_ORG | YES | YES |
| RATE_MANAGE_ANY_ORG | YES | YES |
| ACCESS_ANY_ORG | YES* | NO |
| REPORT_COMPARE_SCOPED_ORGS | YES | YES |
| REPORT_CONSOLIDATED_SCOPED_ORGS | YES | YES |
| SAAS_ANALYTICS_VIEW | YES | NO |
| SUPPORT_IMPERSONATE | YES | NO |
| HARD_DELETE_EXCEPTIONAL | YES | NO |
| AUDIT_PLATFORM_VIEW | YES | NO |

`* ACCESS_ANY_ORG` is a future elevated-access entitlement. WP-A1 does not yet implement the audited bypass path.

## Organization capability grants from PLATFORM roles

These are stored in `eco_platform_role_org_capabilities` and require ACTIVE membership in the target organization.

For `ACCOUNTING_SUPERADMIN`, grant:

- ORG_VIEW
- ORG_SETTINGS_VIEW
- IMPORT_VIEW
- IMPORT_CREATE
- IMPORT_RETRY
- IMPORT_REVIEW
- RECORD_VIEW
- RECORD_CLASSIFY
- RECORD_SOFT_DELETE
- RECORD_RESTORE
- PERCEPTION_IMPORT
- BANK_IMPORT
- PAYROLL_IMPORT
- ISSUE_RESOLVE
- CATALOG_ORG_VIEW
- REPORT_VIEW
- REPORT_EXPORT
- TICKET_CREATE
- TICKET_VIEW_ORG
- AUDIT_VIEW_ORG

Do NOT grant:
- ORG_SETTINGS_MANAGE
- ORG_MEMBER_INVITE
- ORG_MEMBER_MANAGE
- ORG_MEMBER_PERMISSION_MANAGE

Those remain tenant/platform administration concerns.

## Organization role templates

| Capability | TENANT_ADMIN | ACCOUNTANT | UPLOADER | REVIEWER | READ_ONLY | EXTERNAL_AUDITOR |
|---|---:|---:|---:|---:|---:|---:|
| ORG_VIEW | YES | YES | YES | YES | YES | YES |
| ORG_SETTINGS_VIEW | YES | YES | NO | NO | YES | YES |
| ORG_SETTINGS_MANAGE | YES | NO | NO | NO | NO | NO |
| ORG_MEMBER_VIEW | YES | NO | NO | NO | NO | NO |
| ORG_MEMBER_INVITE | YES | NO | NO | NO | NO | NO |
| ORG_MEMBER_MANAGE | YES | NO | NO | NO | NO | NO |
| ORG_MEMBER_PERMISSION_MANAGE | YES | NO | NO | NO | NO | NO |
| IMPORT_VIEW | YES | YES | YES | YES | YES | YES |
| IMPORT_CREATE | YES | YES | YES | NO | NO | NO |
| IMPORT_RETRY | YES | YES | YES | NO | NO | NO |
| IMPORT_REVIEW | YES | YES | NO | YES | YES | YES |
| RECORD_VIEW | YES | YES | YES | YES | YES | YES |
| RECORD_CLASSIFY | YES | YES | NO | YES | NO | NO |
| RECORD_SOFT_DELETE | YES | YES | NO | NO | NO | NO |
| RECORD_RESTORE | NO | NO | NO | NO | NO | NO |
| PERCEPTION_IMPORT | YES | YES | YES | NO | NO | NO |
| BANK_IMPORT | YES | YES | YES | NO | NO | NO |
| PAYROLL_IMPORT | YES | YES | YES | NO | NO | NO |
| ISSUE_RESOLVE | YES | YES | NO | YES | NO | NO |
| CATALOG_ORG_VIEW | YES | YES | YES | YES | YES | YES |
| REPORT_VIEW | YES | YES | YES | YES | YES | YES |
| REPORT_EXPORT | YES | YES | YES | YES | YES | YES |
| TICKET_CREATE | YES | YES | YES | YES | YES | YES |
| TICKET_VIEW_ORG | YES | YES | NO | NO | NO | NO |
| AUDIT_VIEW_ORG | YES | YES | NO | NO | NO | YES |

## Precedence

For organization authorization:
1. active membership is mandatory;
2. membership template grant OR eligible platform-role org grant establishes base grant;
3. explicit membership DENY => deny;
4. explicit membership ALLOW => allow;
5. otherwise base grant result.

A platform role never makes ACCOUNTING_SUPERADMIN a member of an organization.
