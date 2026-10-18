# MICA release baseline — 2026-10-18

## Release identity

Repository: `amoresemiliano/mica_contable_sistema`.

- Validated DEV content commit: `0dd728fb43fa1a6156093adc9b96635353782e54`.
- Validated content tree: `dcafee86bdaa1fb17a9202cf026bd5c9896f0974`.
- History-preserving release merge: `af5e8aabbf24bc5a71dbb1073b6557c3adbd137c`.
- Annotated release tag: `mica-release-2026-10-18`.
- Final release commit: the commit resolved by that tag, which adds only this
  baseline document to the merge above. Resolve its exact SHA with
  `git rev-parse 'mica-release-2026-10-18^{commit}'`.

The final commit cannot embed its own hash in its file contents. The annotated
tag and final delivery record identify that SHA without a self-reference cycle.
Both `main` and `dev` are aligned to that same final commit and tree. The final
tree differs from the validated DEV tree only by this document; runtime, SQL,
tests and Edge source are byte-identical Git objects.

## Git audit and merge decision

Before alignment:

| Reference | Commit |
| --- | --- |
| origin/main | `5e58ffb7c16f3f56e8d10d89a0eb5b84d2a51b1e` |
| origin/dev | `0dd728fb43fa1a6156093adc9b96635353782e54` |
| Merge base | `85d07469bd2c57dd26b48ff207354a31fbd0b6f9` |

There were two main-only commits and twenty dev-only commits. Main-only history:

- `05aae89905de95bebc75754a96882a5a948d7aee`: adds the Jules engineering task to
  `AGENTS.md`.
- `5e58ffb7c16f3f56e8d10d89a0eb5b84d2a51b1e`: previous release merge.

Dev-only commits (newest first): `0dd728f`, `59b40a5`, `c346754`, `0b327b0`,
`2bcf327`, `87b2619`, `32aca8a`, `6f81b40`, `64a7a36`, `93ef0fa`, `f216d14`,
`7d0ea1c`, `8b2bfb3`, `ed8e9b4`, `e0a7497`, `313a75d`, `2d93d39`, `f66096c`,
`7e4c290`, `91ca388`.

Before alignment, main versus dev differed in 131 files: administration,
importers, reporting, health metrics, operational workspaces, migration sources
040–048, tests and documentation. Relative to the common base, main introduced
only `AGENTS.md` content; it had no unique runtime fix to carry forward.

Strategy: ordinary `--no-ff --no-commit` merge of validated dev into main in an
isolated detached worktree, followed by an explicit metadata decision and merge
commit. There were **no merge conflicts**. Both original branch tips are direct
parents of the merge, preserving all history without a force-push.

The automatically retained main-only `AGENTS.md` was deliberately omitted from
the release tree: its contents are a task scoped to Jules' isolated branch,
including instructions to modify only that file and not merge into dev. It is
absent from the validated release tree and is not required production metadata.
Its original commit and the previous production merge remain in ancestry.

The merge tree was proven exactly equal to the canonical DEV tree before adding
this document. The final metadata commit changes only this document. Both remote
branches and the annotated tag are published in one atomic push, with only
fast-forward branch updates.

## Frontend environments and evidence

PROD_CODE_STATUS: `VALIDATED_RELEASE`.
DEV_CODE_STATUS: `VALIDATED_RELEASE`.

The Product Owner's release instruction confirms that the currently deployed
PROD frontend runtime is identical to the validated DEV runtime and designates
that state as the canonical production release. This is the operational
acceptance evidence for deployed content. No new deployment is required or
performed during baseline alignment.

Repository verification proves the release preserves the exact validated
`index.html`, `src/` and Edge implementation. It does not independently prove
the bytes served by hosting. Public PROD/DEV URLs were requested for an optional
read-only comparison; none was supplied at baseline preparation. No claim of a
fresh authenticated hosted smoke test or full remote asset-hash audit is made.

The repository describes BlueHost's manual deployment process in
`docs/DEPLOY_BLUEHOST_DEV.md`; no tracked GitHub Actions deployment workflow is
present. No hosting update, remote pull, configuration change or deployment
command is part of this release closure.

## Shared Supabase and migration baseline

Project reference: `ourzapkjykzlwsjunzmd`.
Migration ceiling: **048**, including the validated category canonicalization
and its guarded foreign-key validation.

**DEV and PROD intentionally share the same database. Therefore database changes
applied for DEV are immediately shared by PROD. Future DB migrations must
continue to be treated with production-level caution.**

The Product Owner confirms that the shared database already contains the
validated schema/data changes through 048. This closure records that accepted
state; it does not reapply, query, alter or repair database objects or data.
No remote SQL was executed.

## Edge function baseline

Function: `mica-reporting`, on the shared Supabase project.

Release source: `supabase/functions/mica-reporting/index.ts`, with its imported
reporting and health implementations in `src/js/core/reporting/` and
`src/js/core/metrics/`. These files are unchanged from the validated commit.
The handler authenticates the caller and delegates reporting/health actions
through the existing permission and organization boundary.

A read-only HTTP `OPTIONS` request to the project's function endpoint returned
**204** during closure. This confirms endpoint reachability, not its deployed
source version or authenticated reporting behavior. No Edge function or secret
was deployed, changed or rotated. Exact remote Edge bundle equivalence is not
independently attested by this reachability check.

## Included functionality

- Stabilized company and platform administration, managed-company context,
  memberships and tax categorization.
- Resumable importers and supported source-format compatibility.
- Auditable management reporting with documented currency and numeric handling.
- Deterministic business health metrics, confidence, priorities and traceability.
- Refined executive presentation and consistent operational workspaces.
- Scoped downloads, semantic sorting and independent horizontal table scrolling.
- Category canonicalization through migration 048.
- Final platform navigation stabilization and responsive toolbar refinement.

## Validation and non-blocking future work

Release verification is Git content/ancestry verification: exact canonical merge
tree, document-only final delta, identical final main/dev trees, empty branch
diff, preserved original tips, annotated tag target, and read-only remote ref
verification after push. No product code changed, so an additional product test
cycle was not required to prove this metadata-only alignment.

The validated UX package records 141 focused tests and three local browser suites
passing. Its general suite recorded 15 preexisting failures: historical SQL hash
expectations, a Supabase mock and old duplicated-organization header assertions.
See `docs/DEV_FINAL_UX_STABILITY_01.md` for evidence and limitations. They remain
non-blocking for this accepted release and are not repaired here.

Deferred work, explicitly outside this release:

- Safe deletion/deactivation of test organizations.
- Further accountant feedback and future UX refinements.
- Additional metrics, benchmarks and scenarios.
- Remaining historic test-hash failures and related test maintenance.
- Future DEV/PROD environment separation, if desired.

No unrelated local file was staged, committed, cleaned, reset or deleted. Release
preparation used `scratch/release-baseline-2026-10-18` as a new isolated worktree.
The preexisting modified DB test and historical untracked evidence are retained.

## Branch policy from this baseline

**main** is the production baseline and receives only validated releases.
**dev** is the active integration/development branch; all new work starts there.
Optional feature/work branches start from dev and merge into dev first.

Promotion sequence:

1. Validate dev.
2. Promote the validated release to main with preserved history.
3. Deploy the production runtime under a separately authorized deployment task.
4. Verify production smoke tests.

Because the database is shared, schema migrations are production-impacting even
during DEV testing. Frontend branch isolation does not isolate database changes.
No new feature work belongs on main between validated promotions.

## Reproducible certification

```powershell
git fetch origin main dev --tags
git rev-parse origin/main origin/dev
git rev-parse 'origin/main^{tree}' 'origin/dev^{tree}'
git diff --exit-code origin/main origin/dev
git rev-parse 'mica-release-2026-10-18^{commit}'
git diff --name-status 0dd728fb43fa1a6156093adc9b96635353782e54 origin/main
```

At closure the two refs and tag target must match; the branch diff must be empty;
the final command must list only this document as added. Future dev work may
legitimately move dev after this certification; the release tag stays immutable.

SQL_EXECUTED: NO. PROD_DATA_TOUCHED: NO. DEPLOYED: NO.
