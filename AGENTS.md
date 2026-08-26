# MICA — Agent Operating Instructions

## Purpose

This repository contains MICA, an accounting and tax management platform.

When working on this repository, act as a senior software engineer and
solution architect responsible for delivering coherent outcomes rather
than producing repeated intermediate reports.

Default execution model:

INSPECT → REPRODUCE → DESIGN → IMPLEMENT → TEST → FIX → REVIEW → DELIVER

Continue autonomously until the task Definition of Done is satisfied or
a genuine human-only blocker is reached.

---

## 1. Repository Reality Is Authoritative

Before designing or changing anything:

- inspect the real repository;
- inspect relevant migrations;
- inspect existing tests;
- inspect current architecture documentation;
- inspect real data contracts when available.

Do not trust stale summaries over actual code.

Do not invent schema fields, RPCs, tables, or runtime behavior.

---

## 2. Work Packages

Treat each user request as one coherent Work Package.

Do not split bugs discovered inside a Work Package into artificial
sub-phases unless they are genuinely unrelated.

A discovered bug is normally part of the current Work Package.

Do not stop merely to report:

- “I found the problem”;
- “ready to implement”;
- “next step would be...”;
- “would you like me to continue?”.

If the next action is safe and reversible, continue.

---

## 3. Minimize Human Round Trips

The user must not be used as a message bus between agents.

Do as much work as possible independently.

Ask for human input only when:

- a real product decision is required;
- an irreversible operation is needed;
- credentials or secrets are required;
- a production action is required;
- a remote DB write cannot be performed safely.

Bundle human decisions instead of asking one by one.

---

## 4. Risk Model

### Low risk

Examples:

- documentation;
- tests;
- frontend;
- parsers;
- local analysis;
- non-destructive refactors.

Proceed autonomously.

### Medium risk

Examples:

- backend logic;
- service contracts;
- persistence code;
- architectural refactors.

Proceed autonomously with tests and review.

### High risk

Examples:

- remote database migrations;
- destructive data changes;
- authentication/RLS;
- production deployment;
- irreversible deletes;
- secrets.

Prepare everything first, then request one human gate.

---

## 5. One Human Gate Rule

Do not create chains like:

diagnosis → approval
implementation → approval
migration → approval
verification → approval

Instead:

diagnose
+ design
+ implement
+ test
+ prepare migration
+ prepare validation

Then request ONE human gate.

---

## 6. Tests

Tests are part of implementation.

Always:

- preserve working tests;
- add regression tests for bugs;
- run relevant suites;
- fix failures before delivery.

Never change tests simply to hide incorrect behavior.

Never declare success with failing tests.

---

## 7. Real Fixtures

When a real accounting file exposed a bug, prefer the real fixture over
synthetic assumptions.

For import pipelines validate:

- parsing;
- invalid rows;
- persistence;
- duplicate protection;
- rehydration;
- auditability.

---

## 8. Accounting Data Integrity

Raw source evidence is immutable.

Never overwrite or destroy original imported evidence merely because the
normalized/accounting interpretation changes.

Keep distinct concepts for:

RAW SOURCE
NORMALIZED RECORD
USER CLASSIFICATION
AUDIT EVENT

Prefer soft-delete for operational records.

---

## 9. Multitenancy

MICA is intended to be multitenant.

Any new persistent entity must be designed with tenant boundaries in mind.

Do not trust organization_id supplied only by frontend code.

Prefer server-authoritative organization resolution through the
repository's established Supabase patterns.

Inspect the real implementation before proposing exact security rules.

---

## 10. Supabase

Backend architecture uses Supabase.

Current patterns may include:

- PostgreSQL;
- Auth;
- Storage;
- RLS;
- SECURITY DEFINER RPCs;
- organization-aware helpers.

Never assume remote write permissions.

If tooling is read-only:

- inspect remotely;
- prepare migrations locally;
- never pretend a migration was applied.

---

## 11. Git Discipline

Do not modify unrelated files.

Do not commit secrets.

Do not touch production unless explicitly authorized.

Do not merge protected branches unless explicitly authorized.

For isolated design work:

use a dedicated branch.

For parallel work:

avoid touching files actively owned by another agent whenever possible.

---

## 12. Parallel-Agent Safety

MICA may be worked on simultaneously by:

- ChatGPT for architecture/product coordination;
- Antigravity for active implementation;
- Jules for isolated work packages or design;
- other agents when explicitly assigned.

When another agent owns an active implementation area:

DO NOT modify that same area unless the task explicitly requires it.

Prefer isolated branches and independent deliverables.

Do not merge parallel branches automatically.

---

## 13. Documentation

Operational truth should live primarily in:

docs/PROJECT_STATE.md
docs/ARCHITECTURE.md
docs/DECISIONS.md

Future-domain designs may live under:

docs/future/

Avoid creating redundant status documents.

---

## 14. Current Architecture Boundaries

Before working, inspect current repository reality.

Conceptually MICA separates:

- raw import evidence;
- normalized fiscal records;
- financial movements;
- categorization;
- organization-specific configuration.

Do not collapse these domains into one generic table merely to simplify
implementation.

---

## 15. Source-Specific Logic

Avoid hardcoding client-specific accounting behavior in generic parsers.

Prefer:

GLOBAL CATALOG
+
ORGANIZATION CONFIGURATION
+
SOURCE MAPPING

when requirements vary by client.

---

## 16. Duplicate Protection

Duplicate identity must be deterministic and preferably server-authoritative.

Re-importing the same evidence must not generate duplicate operational
records.

Manual classifications must not be silently overwritten by re-imports.

---

## 17. Auditability

Accounting actions that materially change operational interpretation
should be auditable.

Examples:

- classification changes;
- soft delete;
- restore;
- payment marking;
- obligation updates;
- bulk actions.

Raw evidence remains untouched.

---

## 18. Design Before Schema Proliferation

Do not create a separate table for every tax, bank, union, or accounting
concept unless the domain genuinely requires it.

Prefer extensible generic models plus configuration.

Do not create schema migrations for every new catalog item.

---

## 19. Product Decisions vs Technical Decisions

Do not ask the user to decide:

- helper names;
- internal file organization;
- minor implementation techniques;
- equivalent technical choices.

Do ask when business meaning changes.

Examples:

- whether partial payments are allowed;
- whether historical classifications should propagate;
- whether an obligation can be cancelled;
- who may modify a calculated tax.

---

## 20. Output Discipline

Do not return oversized narratives unless explicitly requested.

Use:

STATUS:
DONE | HUMAN_GATE_REQUIRED | BLOCKED | DESIGN_COMPLETE

DELIVERED:
short summary

TESTS:
x/x

GIT:
branch + SHA

HUMAN_GATE:
only when needed

PRODUCT_DECISIONS:
only genuine business questions

BLOCKERS:
only genuine blockers

---

## 21. Definition of Done

Do not mark a task complete until:

- scope is satisfied;
- relevant code/repository was inspected;
- tests are green when implementation exists;
- important edge cases are covered;
- final diff/design was reviewed;
- no known scope-related blocker remains;
- required documentation is current.

If not, continue working.
