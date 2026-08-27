JULES — UPDATE MICA AGENTS.md
ENGINEERING DELIVERY PROTOCOL V2

Goal:

Update the existing repository-level AGENTS.md with the new delivery protocol.

This change belongs only to Jules' isolated branch / design workspace.

Do NOT modify dev.
Do NOT merge.

Preserve the existing AGENTS.md and integrate these rules coherently.

==================================================
1. DELIVERY PIPELINE
==================================================

Default engineering pipeline:

INSPECT
→ REPRODUCE
→ DESIGN
→ IMPLEMENT
→ TEST
→ EPHEMERAL INTEGRATION ENVIRONMENT
→ ADVERSARIAL REVIEW
→ FIX
→ RETEST
→ FINAL REVIEW
→ DELIVER

Optimize for fewer total human round trips,
not the fastest initial response.

==================================================
2. EPHEMERAL INTEGRATION VALIDATION
==================================================

For database/schema/RPC/RLS work:

when technically possible, use an isolated disposable database before declaring a design or implementation ready.

Possible environments:

- local PostgreSQL;
- Supabase local;
- Docker;
- temporary test database;
- isolated snapshot.

Validate:

- migration application;
- constraints;
- RPC behavior;
- role/security behavior;
- edge cases;
- idempotency;
- rollback/down when appropriate.

Static review alone is not sufficient for high-risk DB delivery.

==================================================
3. ADVERSARIAL REVIEW
==================================================

Before final submission, perform a deliberate adversarial review.

Try to break the solution.

Inspect:

- nulls;
- open-ended ranges;
- duplicates;
- partial failures;
- cross-tenant access;
- authorization;
- concurrency assumptions;
- destructive cascades;
- historical-data loss;
- incompatible schema changes;
- stale/manual classifications being overwritten;
- unsafe retries.

==================================================
4. MIGRATION FREEZE RULE
==================================================

Once a migration reaches Human Gate:

new product features must NOT be added to it.

Only execution/security/integrity blockers may modify the frozen migration.

New product requirements belong to the next Work Package.

==================================================
5. SCOPE FREEZE
==================================================

At the beginning of a Work Package define:

- objective;
- scope;
- out of scope;
- acceptance criteria;
- Definition of Done.

Do not absorb unlimited new features into an active migration.

==================================================
6. IMPLEMENTER VS REVIEWER
==================================================

When Jules is assigned as a reviewer:

do not modify the implementation branch.

Review adversarially and return findings.

When Jules is assigned implementation:

work only in the assigned isolated branch.

Do not let two agents concurrently modify the same implementation surface.

==================================================
7. WORKTREE SAFETY
==================================================

If the current worktree is dirty or contains unrelated files:

do not clean/reset/stash unrelated work automatically.

Prefer:

- fresh clone;
- git worktree;
- isolated workspace.

Never use destructive Git cleanup unless explicitly authorized.

==================================================
8. DATA PLATFORM PRINCIPLE
==================================================

For OLTP/OLAP architecture:

application-level dual writes are NOT the default.

Preferred model:

APPLICATION
→ OLTP SOURCE OF TRUTH
→ CDC / ELT
→ ANALYTICS

The application writes once.

Analytics ingestion must be:

- asynchronous;
- restartable;
- idempotent;
- observable.

==================================================
9. ANALYTICAL DATA PRINCIPLES
==================================================

Analytics must distinguish:

RAW ANALYTICS
from
CURATED / DIMENSIONAL MODEL.

Transactional schema should not automatically become the analytical schema.

Prefer:

RAW / LANDING
→ TRANSFORM
→ FACTS + DIMENSIONS
→ REPORTING / AI

Preserve history required for analytical reasoning.

==================================================
10. HIGH-RISK DELIVERY REPORT
==================================================

For DB/data-platform work report:

STATUS
GIT
TESTS
EPHEMERAL_DB
ADVERSARIAL_REVIEW
KNOWN_LIMITATIONS
BLOCKERS

Do not produce long chat narratives if documentation files contain the details.

==================================================
11. CONTINUE EXISTING RULES
==================================================

Preserve all existing MICA AGENTS.md rules around:

- accounting auditability;
- immutable raw evidence;
- multitenancy;
- Supabase;
- Git discipline;
- source-specific logic;
- duplicate protection;
- concise reports.

==================================================
DELIVERY
==================================================

Modify only AGENTS.md.

Run tests.

Commit/push to the isolated Jules branch.

Return:

STATUS: DONE | BLOCKED
GIT: <sha>
TESTS: x/x PASS
AGENTS_PROTOCOL_V2: ACTIVE|FAIL
