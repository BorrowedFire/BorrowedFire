---
name: qa-audit
description: Audit a bounded app surface or release candidate and report defects with evidence. Fix code only when the requested scope authorizes fixes.
---

# QA Audit

Run a focused QA operating loop for a repo: discover what exists, make the test surface explicit,
execute the best available checks, record defects, fix what is safe and in scope, regress, and
report confidence plus remaining risk.

This skill is intentionally bounded. It is not a promise to test an entire codebase forever, and
it should not become spreadsheet theater. Back the report with real commands, app paths,
screenshots, logs, test results, or review notes. A focused audit may use one report. Use the
full artifact set when the user requests a reusable audit or names an artifact directory.

## When to Use

Use this for:

- A release candidate, milestone, feature, route set, screen flow, API group, job family, or
  small repo.
- "What features do we have, what did we test, what defects remain?"
- Turning a broad QA prompt into a repeatable process with stopping rules.
- Preparing a repo for owner review, store handoff (`store-release`), customer demo, or launch
  readiness.

## Inputs

Default scope is the current repo and the smallest surface implied by the user. If the scope is
ambiguous, pick a conservative scope and state it before execution. Ask only when a wrong scope
would create meaningful risk.

Useful invocation shapes:

- `qa-audit auth flow`
- `qa-audit iOS release candidate`
- `qa-audit API endpoints under /billing`
- `qa-audit full small repo --no-fix`

Optional flags:

| Flag | Default | Effect |
|---|---:|---|
| `--no-fix` | off | Audit only; do not edit code. |
| `--fix-safe` | on only when the request includes fixes | Fix narrow, high-confidence defects that stay inside scope. |
| `--max-defects N` | 25 | Stop discovery once the defect list is large enough to need triage. |
| `--max-passes N` | 2 | Limit fix/regression loops. |
| `--artifact-dir PATH` | unset | Write the reusable artifact set to this directory. |

`--no-fix` overrides `--fix-safe`. An audit-only request does not authorize implementation or
test edits. Carry forward a prior grant to fix the scoped defects without asking again.

For a reusable audit, resolve `<audit-dir>` once from `--artifact-dir`, or use `qa` if the user
requested durable repository artifacts without naming a directory. For a focused audit, use the
same evidence categories in one report and keep temporary evidence outside the repository.

## Reusable audit artifacts

When the requested audit needs the full artifact set, create or update:

- `<audit-dir>/feature-inventory.md` - entrypoints, screens/routes/endpoints/jobs/configs discovered from code.
- `<audit-dir>/test-matrix.md` - checks mapped to features, risk, method, owner/agent status, and evidence.
- `<audit-dir>/defects.md` - defects with severity, repro, evidence, status, fix commit if any, and regression result.
- `<audit-dir>/coverage-summary.md` - confidence, what was proven, what was not proven, residual risks, and next decisions.

**Artifact policy:** commit repository artifacts only when the request or existing repository
convention calls for it. A request to inspect and report does not itself require a commit or PR.
Use the selected output form throughout the loop. Keep the evidence categories in the focused
report, or use their corresponding files above for a reusable audit.

## Operating Loop

1. **Preflight.** Read repo instructions, current branch, dirty state, package/build/test scripts,
   CI config, app surfaces, and recent changes. `recall` the repo's `lessons/` and registry page
   if a brain is available. Preserve unrelated edits. If a check regenerates tracked files, use
   an isolated copy or worktree that preserves the intended candidate. Do not reset or clean the
   user's checkout to restore a test baseline. Do not edit yet.
2. **Scope.** Define the audit boundary in one sentence: repo, surface, target users,
   environments, and explicit non-goals.
3. **Discover features from code.** Build the feature inventory from routes, screens, components,
   API handlers, jobs, config, migrations, tests, and docs. Mark inferred items as inferred.
4. **Build the matrix.** Record happy paths, edge cases, auth/permission
   checks, error states, data integrity, accessibility/usability where relevant, and regression
   checks for recently changed areas.
5. **Execute checks.** Run repo-native automated tests first, then targeted manual or tool-driven
   checks for the scoped surface. Prefer real app/browser/simulator/API execution over static
   guesses.
6. **Log defects.** Every defect needs severity, affected feature, repro steps, expected/actual
   behavior, evidence, status, and suspected root invariant. If evidence is weak, mark it
   "needs repro" instead of pretending.
7. **Fix safe issues.** If fixing is allowed, only fix narrow, high-confidence issues inside
   scope. All fixes go on **one audit branch**; the branch lands through `land` (its gates, its
   denylist) — qa-audit never merges its own fixes. Avoid redesigns, product calls, or anything on
   the denylist unless separately authorized.
8. **Regress.** Re-run the exact failing check plus adjacent checks after each fix. Update defect
   status with the proof.
9. **Summarize.** Record coverage confidence, completed evidence, untested
   surfaces, open defects by severity, and decision-ready next steps. Capture recurring defect
   patterns via `remember` to `lessons/`.

**Evidence rungs.** Grade every piece of recorded evidence on the proof ladder in `land`'s Live
Proof Gate, and write the rung next to the evidence in the test matrix and defect records. In
the coverage summary, "proven" means rung 4 or higher: the check ran real code or drove the real
surface. Rungs 1-3 (a claim, a cited line, a walked-through argument) are review notes. List them
under "not proven" with the rung each reached.

## Defect-Class Circuit Breaker

The **second validated defect with the same root invariant** stops isolated fixes. Before another
fix/regression pass:

1. Name the invariant and the authoritative owner/state transition.
2. Inventory every entry point and consumer.
3. Mark lifecycle re-entry, async suspension, authorization identity/role, migration/legacy state,
   retention/deletion/cleanup, and retry/idempotency as `applicable`, `not applicable` with a
   reason, or `unverified`.
4. Add the resulting state and negative paths to the test matrix.
5. When fixing is allowed, fix the smallest coherent invariant boundary, add regression coverage
   for each exposed transition, and rerun focused plus adjacent-consumer checks. When `--no-fix`
   is active, do not edit implementation or tests; record the candidate boundary, required
   regressions, and missing proof in the defect records and coverage summary.

A new validated related defect after this audit and a subsequent pass, an unbounded invariant, or
a required product/security/architecture decision ends the pass and becomes a decision-ready
escalation. Do not raise the pass limit or keep patching symptoms.

## Feature Inventory Heuristics

Use repo-native discovery before guesses:

- Web: routes, pages/app directories, API route handlers, middleware, forms, auth guards,
  env/config, analytics, payments, background jobs.
- iOS/macOS: app targets, views, view models, navigation, entitlements, persistence, widgets,
  deep links, notification paths, store config.
- Android: activities/fragments/Compose navigation, services/workers, manifests, permissions,
  persistence, Play config.
- Backend: controllers/handlers, schemas, migrations, queues, scheduled jobs, RLS/policies,
  webhooks, observability.
- CLI/tools: commands, flags, config files, IO boundaries, failure modes, install/update paths.

## Severity

- **P0** - data loss, security/privacy breach, broken critical path, production outage.
- **P1** - release-blocking user-facing failure or high-risk correctness issue.
- **P2** - meaningful defect with workaround or limited blast radius.
- **P3** - polish, docs, minor accessibility, small inconsistency.

## Fix Boundaries

Allowed without another ask when `--fix-safe` is active and `--no-fix` is not:

- Test fixes, obvious null/error handling, broken links/routes, validation gaps, copy typos,
  small UI state bugs, narrow regressions with clear evidence.

Stop and ask with a decision-ready brief before:

- Product behavior choices, anything on `land`'s denylist (`references/denylist.md`), broad
  refactors, or fixes that grow past the audit scope.

## Stopping Rules

Stop the loop and report when any of these happens:

- All scoped matrix rows have evidence or explicit "not tested" reasons.
- P0/P1 defects are fixed or decision-ready, and remaining P2/P3 work is logged.
- `--max-defects` or `--max-passes` is reached.
- Required credentials, devices, external systems, or owner decisions are missing.
- The same failure recurs after a genuine fix attempt.

Never claim "complete" for untested surfaces. Say "scoped audit complete" and name the scope.

## Report Format

Final report should be short and evidence-first:

```
QA Audit: <scope>
Artifacts: <links, only when the audit created separate artifacts>

Proven:
- <feature/check -> evidence>

Fixed:
- <defect -> commit/proof>

Open:
- P1 <defect -> exact decision or next proof needed>
- P2/P3 summary

Confidence:
- <high/medium/low> for <scope>, because <evidence>
- Not proven: <surfaces>
```

## Related

`land` for landing the audit branch. `maintainer` for queue orchestration. `store-release` for
mobile store releases. `remember` for lesson write-back.
