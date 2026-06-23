---
name: repo-quality-audit
description: Build and run a bounded, repo-native QA audit loop for a feature, app surface, release candidate, or small repo. Use when the user says "repo quality audit", "QA audit", "test matrix", "audit this release candidate", "find defects", "feature inventory", or wants a reusable agent loop that discovers features, builds durable QA artifacts, executes tests/manual checks, logs defects, fixes safe issues, and reports confidence without pretending the whole codebase is proven.
---

# Repo Quality Audit

Run a focused QA operating loop for a repo: discover what exists, make the test surface explicit, execute the best available checks, record defects, fix what is safe and in scope, regress, and report confidence plus remaining risk.

This skill is intentionally bounded. It is not a promise to test an entire codebase forever, and it should not become spreadsheet theater. The output is durable repo evidence in `qa/`, backed by real commands, app paths, screenshots, logs, test results, or review notes.

## When to Use

Use this for:

- A release candidate, milestone, feature, route set, screen flow, API group, job family, or small repo.
- "What features do we have, what did we test, what defects remain?"
- Turning a broad QA prompt into a repeatable process with stopping rules.
- Preparing a repo for owner review, App Store/Play Store handoff, customer demo, or launch readiness.

Do not use this for:

- Landing one existing PR end to end. Use `autoland`.
- Store submission or mobile binary release trains. Use `orbit`.
- Continuous backlog orchestration. Use `maintainer`.
- Pure copy/message tuning. Use `signal`.

## Inputs

Default scope is the current repo and the smallest surface implied by the user. If the scope is ambiguous, pick a conservative scope and state it before execution. Ask only when a wrong scope would create meaningful risk.

Useful invocation shapes:

- `repo-quality-audit auth flow`
- `repo-quality-audit iOS release candidate`
- `repo-quality-audit API endpoints under /billing`
- `repo-quality-audit full small repo --no-fix`

Optional flags:

| Flag | Default | Effect |
|---|---:|---|
| `--no-fix` | off | Audit only; do not edit code. |
| `--fix-safe` | on | Fix narrow, high-confidence defects that stay inside scope. |
| `--max-defects N` | 25 | Stop discovery once the defect list is large enough to need triage. |
| `--max-passes N` | 2 | Limit fix/regression loops. |
| `--artifact-dir PATH` | `qa` | Write audit artifacts somewhere else. |

## Required Artifacts

Create or update these files in the repo unless the user asks for a different location:

- `qa/feature-inventory.md` - entrypoints, screens/routes/endpoints/jobs/configs discovered from code.
- `qa/test-matrix.md` - checks mapped to features, risk, method, owner/agent status, and evidence.
- `qa/defects.md` - defects with severity, repro, evidence, status, fix commit if any, and regression result.
- `qa/coverage-summary.md` - confidence, what was proven, what was not proven, residual risks, and next decisions.

Keep these artifacts concise enough to be maintained. Link to exact commands, screenshots, PRs, logs, or files rather than dumping raw output.

## Operating Loop

1. **Preflight.** Read repo instructions, current branch, dirty state, package/build/test scripts, CI config, app surfaces, and recent changes. Do not edit yet.
2. **Scope.** Define the audit boundary in one sentence: repo, surface, target users, environments, and explicit non-goals.
3. **Discover features from code.** Build `feature-inventory.md` from routes, screens, components, API handlers, jobs, config, migrations, tests, and docs. Mark inferred items as inferred.
4. **Build the matrix.** Create `test-matrix.md` with happy paths, edge cases, auth/permission checks, error states, data integrity, accessibility/usability where relevant, and regression checks for recently changed areas.
5. **Execute checks.** Run repo-native automated tests first, then targeted manual or tool-driven checks for the scoped surface. Prefer real app/browser/simulator/API execution over static guesses.
6. **Log defects.** Every defect needs severity, affected feature, repro steps, expected/actual behavior, evidence, and status. If evidence is weak, mark it "needs repro" instead of pretending.
7. **Fix safe issues.** If fixing is allowed, only fix narrow, high-confidence issues inside scope. Avoid redesigns, product calls, migrations, auth/payment changes, secrets, destructive operations, or release steps unless separately authorized.
8. **Regress.** Re-run the exact failing check plus adjacent checks after each fix. Update defect status with the proof.
9. **Summarize.** Update `coverage-summary.md` with confidence, completed evidence, untested surfaces, open defects by severity, and decision-ready next steps.

## Feature Inventory Heuristics

Use repo-native discovery before guesses:

- Web: routes, pages/app directories, API route handlers, middleware, forms, auth guards, env/config, analytics, payments, background jobs.
- iOS/macOS: app targets, views, view models, navigation, entitlements, persistence, widgets, deep links, notification paths, store config.
- Android: activities/fragments/Compose navigation, services/workers, manifests, permissions, persistence, Play config.
- Backend: controllers/handlers, schemas, migrations, queues, scheduled jobs, RLS/policies, webhooks, observability.
- CLI/tools: commands, flags, config files, IO boundaries, failure modes, install/update paths.

## Severity

- **P0** - data loss, security/privacy breach, broken critical path, production outage.
- **P1** - release-blocking user-facing failure or high-risk correctness issue.
- **P2** - meaningful defect with workaround or limited blast radius.
- **P3** - polish, docs, minor accessibility, small inconsistency.

## Fix Boundaries

Allowed without another ask when `--fix-safe` is active:

- Test fixes, obvious null/error handling, broken links/routes, validation gaps, copy typos, small UI state bugs, narrow regressions with clear evidence.

Stop and ask with a decision-ready brief before:

- Product behavior choices, auth/permissions, payments/IAP, database migrations/RLS/prod data writes, secrets/signing/env changes, destructive operations, release/build submission, broad refactors, or fixes that grow past the audit scope.

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
Repo Quality Audit: <scope>
Artifacts: qa/feature-inventory.md, qa/test-matrix.md, qa/defects.md, qa/coverage-summary.md

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

`autoland` for landing one PR after fixes are ready. `maintainer` for queue orchestration. `orbit` for mobile store releases.
