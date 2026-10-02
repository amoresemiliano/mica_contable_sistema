# 030 audit corrections

## Historical catalog reads

030 leaves both global catalog SELECT policies unchanged. Names remain readable
after withdrawal. Tenant choices still come only from assigned rows; operational
classification and activation RPCs require is_assigned. Reading a global row
does not authorize writes or operational use. The two assignment SELECT policies
continue to hide withdrawn assignments and include inactive assigned rows.

## Frontend capabilities

public.get_my_catalog_capabilities() resolves the caller on the server and returns
three booleans through existing private.can_platform helpers. It accepts no user
or organization ID. The frontend loads these after resolving the profile/role,
clears them at session reset/logout, and rejects malformed/error responses.
Controls and store/handler guards require effective capabilities, not template
names. GLOBAL_CATALOG_MANAGE controls import/create/edit in MICA mode;
CATALOG_ASSIGN_ANY_ORG controls SUPERADMIN assignment. ADMIN keeps tenant-only
activation. ACCESS_ANY_ORG does not bypass organization SELECT RLS. SQL rechecks
permissions on every mutation; cached UI booleans are never authoritative.
The capability RPC is included in the metadata snapshot and restored/removed
by the generic down script according to its pre-030 existence.

## Coordinated rollback

Apply 030 and deploy its frontend during a controlled write-free window; the old
frontend uses assignment RPCs for tenant activation and is not compatible.

030 captures prior function definitions, owners, effective ACL/grant options,
the two changed SELECT policies, and assignment table ACL in
private.migration_030_backup before altering them. Both backup tables are private
and have no PUBLIC/anon/authenticated grants. Global policies are never changed.

The down script must run under the privileged migration owner with clients and
writes stopped. It restores captured functions/policies/effective ACL, removes
new functions, and retains is_assigned. Before projecting withdrawn rows to
is_active=FALSE for the old frontend, it saves both flags and updated_at in
private.migration_030_assignment_state. No business rows are deleted. Metadata
grantor identity is not reconstructed; effective grantees and grant options are.

Deploy the old frontend before reopening. The old frontend intentionally returns
to its old authorization/activation semantics; retained is_assigned is archival
while old code runs. Legacy writes can diverge from that flag. A future forward
migration must reconcile those writes with the archive; do not rerun 030 blindly
or overwrite either backup. Both up and down are intentionally single-use.

Rollback is designed for an otherwise unmodified 030 deployment. Later schema
dependencies or added grants can make restoration fail; the transaction then
rolls back. Runtime rollback verification is pending; no SQL was applied here.

## Verification status

Jest tests are local JavaScript/static SQL checks. tests/db/030_assignment_activation.sql
contains real PostgreSQL/RLS/ACL tests but must be executed separately in a disposable
DEV environment after 030. sql/030_consultant_diagnostics.sql is SELECT-only and
does not provision CONSULTANT or change existing memberships.
