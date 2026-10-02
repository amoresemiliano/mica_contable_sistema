# MICA — Agent Engineering Context

## Mandatory Engineering Skills

All future MICA engineering work must strictly apply the following three execution protocols:

1. **`autonomous-engineering-execution`** (Global skill)
   - Universal engineering execution protocol for autonomous work packages, minimal human round-trips, evidence-driven decisions, automatic testing/fix loops, adversarial review, and explicit risk-based human gates.

2. **`evidence-first-engineering`** (Global skill)
   - Empirical verification before implementation, systematic evidence classification (FACT != INFERENCE != ASSUMPTION), runtime-aware testing, adversarial self-review, and root-cause sweeps.

3. **`efficient-delivery`** (Project-Local skill)
   - Canonical local skill path: [SKILL.md](file:///c:/Users/Emiliano/Documents/1.%20Sistemas/Contable/sistema/.agents/skills/efficient-delivery/SKILL.md) (also mirrored at `.agent/skills/efficient-delivery/SKILL.md`)
   - Minimizes total human/agent cycles to reach a verified observable result.
   - Enforces 14 core rules including: Meaningful Blocks, Real Environment as Source of Truth, Cheapest Evidence First, Two-Failure Strategy Rule, Human Checks as Acceptance Gates, Pass Means Move Forward, Mode A vs. Mode B execution, and Strict Status Semantics (`IMPLEMENTED`, `STATICALLY_VERIFIED`, `READY_FOR_MANUAL_CHECK`, `DEV_RUNTIME_VERIFIED`, `CLOSED`).
