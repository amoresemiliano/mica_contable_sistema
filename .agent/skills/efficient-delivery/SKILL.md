---
name: efficient-delivery
description: Project-local execution standard for MICA to minimize total human/agent cycles required to reach a verified observable result.
---

# Efficient Delivery — MICA

## Purpose
Minimize total human/agent cycles required to reach a verified observable result.

This skill is MANDATORY for all future MICA engineering work.

---

## Core Rules

### 1. BUILD MEANINGFUL BLOCKS
- Prefer coherent implementation blocks over micro-patches.
- A Work Package should produce a meaningful observable result.
- Do not open a new WP for every small defect if the defect belongs to the same implementation block.

### 2. REAL ENVIRONMENT IS SOURCE OF TRUTH
- Agent reports are not proof.
- Priority of evidence:
  1. Real DEV DB / runtime / browser
  2. Terminal output
  3. Integration tests
  4. Static tests
  5. Agent report
- Never claim runtime behavior was verified if only static analysis was run.

### 3. CHEAPEST EVIDENCE FIRST
- Before creating another implementation prompt or WP, ask:
  *"Can this assumption be verified more cheaply with one SQL query, terminal command, HTTP request, or browser check?"*
- If yes, prefer that evidence first.

### 4. TWO-FAILURE STRATEGY RULE
- **First failure in a layer:** Diagnose and correct if root cause is clear.
- **Second failure in the SAME layer/class:**
  - STOP incremental patching.
  - Perform root-cause sweep.
  - Reconsider architecture, test strategy, or implementation approach.
- Do not wait for the human owner to request a strategy change.

### 5. HUMAN CHECKS ARE ACCEPTANCE GATES
- Each substantial WP should finish with approximately 3–6 objective manual checks whenever practical.
- Checks should be:
  - Copy-paste ready
  - Fast
  - Deterministic
  - Tied to observable acceptance criteria
- Formats: SQL, terminal, browser, API response.
- Avoid large manual audit procedures unless necessary.

### 6. PASS MEANS MOVE FORWARD
- Once critical acceptance checks pass:
  - Close the layer.
  - Record known non-blocking debt.
  - Continue to the next product objective.
- Do not pursue unlimited perfection or continue expanding validation without a specific risk.

### 7. DISTINGUISH TWO EXECUTION MODES

#### MODE A — EVIDENCE BEFORE BUILD
Use when:
- Architecture assumption is uncertain.
- Destructive migration risk exists.
- Live behavior is unknown and one cheap query can resolve it.

**Sequence:**
`VERIFY → DESIGN → IMPLEMENT → CHECK`

#### MODE B — BUILD THEN VERIFY
Use when:
- Architecture/contract is already frozen.
- Implementation scope is clear.
- Environment contains test data.
- Rollback/recovery is straightforward.

**Sequence:**
`IMPLEMENT MEANINGFUL BLOCK → STATIC CHECK → HUMAN RUNTIME CHECK → FIX ONLY REAL FAILURES → CLOSE`

*Prefer MODE B when excessive pre-analysis would cost more than implementation.*

### 8. DOCUMENTATION DOES NOT EQUAL PROGRESS
- Do not optimize for documentation volume.
- Documentation is useful only when it:
  - Preserves a contract
  - Enables execution
  - Enables verification
  - Reduces future uncertainty
- A well-documented WP that produces no observable progress is not successful.

### 9. TESTS GREEN != DONE
- Use precise statuses:
  - `IMPLEMENTED`
  - `STATICALLY_VERIFIED`
  - `READY_FOR_MANUAL_CHECK`
  - `DEV_RUNTIME_VERIFIED`
  - `CLOSED`
- Never use `DONE` merely because unit/static tests pass.

### 10. HUMAN OWNER TIME IS EXPENSIVE
- Minimize:
  - Repeated manual SQL operations
  - Repeated deployments
  - Repeated copy/paste cycles
  - Redundant questions
  - Multiple prompts for one coherent implementation
- Batch safe engineering work before human gates.

### 11. DATABASE WORK
- For manual DB operations:
  - Agent prepares scripts.
  - Human applies them.
  - Verification uses small deterministic queries.
  - One step at a time during manual execution.
- Never assume a migration applied because repository code exists.

### 12. DRIFT HANDLING
- When live DEV differs from repository expectations:
  - Classify the drift.
  - Verify it with direct evidence.
  - Fix the canonical migration/repository.
  - Avoid maintaining undocumented manual-only state.

### 13. LEGACY SYSTEM RULE
- MICA currently contains test/demo data.
- Do not preserve obsolete authorization compatibility merely because it exists.
- Preserve valuable business/importer behavior.
- Prefer clean canonical architecture when legacy state conflicts with it.

### 14. AUTONOMOUS IMPROVEMENT OBLIGATION
- The agent must proactively identify inefficient process patterns.
- Do not wait for the human owner to suggest:
  - Simpler validation
  - Architectural reset
  - Larger coherent WP
  - Cheaper evidence source
  - Strategy change after repeated failure
- If a materially more efficient approach becomes evident, surface it.
