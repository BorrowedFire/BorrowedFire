---
name: test-audit
description: Evaluate the value of new or changed tests, audit redundant or weak tests, and run scoped test-pruning campaigns. Use for test authoring and review, test bloat, or test cleanup. Product QA belongs to qa-audit.
---

# Test audit

Keep tests that catch meaningful failures. Remove maintenance cost only when the protected
behavior remains covered or the contract no longer exists.

## Choose the mode

- **Authoring:** apply the four questions below to tests needed by the current change. This does
  not start a suite audit or require a new test for every edit.
- **Audit:** inspect the requested test surface and report candidates. An inspection request
  authorizes no source or test edits. An existing request to fix or clean up that surface does.
- **Campaign:** when the user requests a systematic reduction, read
  [the campaign guide](references/campaign.md). It adds a measurable target and a complete
  inventory so the work continues past the first easy deletions.

Keep the current task's scope and authorization. Apply `land`'s denylist to proposed changes.
Test cleanup does not authorize a product redesign, a protected production change, or a merge.

## Authoring gate

Before adding or changing a test, answer:

1. What observable behavior, invariant, or independent contract does it protect?
2. What credible regression would make it fail?
3. Why would the existing tests miss that regression?
4. Can it exercise the code that owns the behavior without exposing an internal implementation
   solely for this assertion?

If no distinct risk needs protection, add no test. Prefer extending an existing case table when
it exercises the same contract. A second test layer must catch a distinct failure, such as
serialization, delivery, persistence, or lifecycle behavior that the first layer cannot reach.

Use expected values from an independent specification, worked example, or known result. For a
bug fix, demonstrate that the regression fails for the intended reason before the fix and passes
after it. If the original environment cannot be reproduced, use a deliberate mutation or another
independent control and state what that evidence does and does not establish.

A clock, transport, or dependency injection boundary can provide useful deterministic control.
Remove an export, flag, wrapper, or hook only after checking its design purpose and callers.
Do not force real network access or slower end-to-end tests merely to eliminate a useful seam.

## Candidate patterns and retention

Investigate these patterns. A match is a candidate for review, not permission to delete:

- Assertions that compare a value with itself or derive the expected value using the tested code.
- A mock or fixture that supplies the very behavior the production code should produce.
- Negative tests that pass because an unrelated guard rejects the input first.
- Tests that inspect private calls or source spelling while stronger tests cover the same risk.
- Copied fixtures, inventories, manifests, snapshots, or helper scenarios with no distinct contract.
- Duplicate scenarios, assertion-free probes, and tests whose only effect is preserving dead code.
- Names that promise a state transition the inputs and assertions never exercise.

Retain independent protection for public APIs, protocols, security, storage, migrations,
platform behavior, release tooling, generated interfaces, and architecture constraints. Keep
call-order assertions when the order affects observable behavior. A slow or static test can
still be the cheapest reliable guard.

For skills, doctrine, installers, prompts, and configuration, text or bytes may be the product
contract. Retain source inspection when it detects a meaningful contract change. Check that a
harmless rewording or refactor does not break it unless the exact text is itself the contract.
When a guard is suspect, mutate the protected rule and confirm that the guard rejects it.

## Audit workflow

1. Read the repository's instructions, test commands, CI routing, and relevant Prometheus
   lessons. Define the scope. Record the candidate revision and worktree state. Preserve
   unrelated edits. Run baseline checks before attributing failures to a cleanup.
2. For each candidate, read the complete test, production owner, entry points, relevant callers,
   overlapping tests, and history. Inspect dependency source or types when the claim depends on
   them. Record the evidence below before editing.
3. Choose one coherent batch. Move unique assertions into the retained suite before removing
   duplicates. Remove support code only after verifying that no remaining caller needs it.
   Preserve test discovery, platform routing, and CI execution for moved tests.
4. Run the smallest affected and adjacent suites, then the repository's required checks. Keep
   source stable while checks run. Use a disposable copy or worktree for baseline and mutation
   controls; verify restoration before running final proof.
5. Compare removed assertions with retained protection. A green suite or unchanged coverage
   does not establish that a contract survived. For a moved or weakened-looking assertion,
   demonstrate a credible failure that the retained suite still catches.

Use a short report for a focused audit. For each candidate record:

| Field | Required evidence |
|---|---|
| Test | Exact name and location, including relevant parameter cases |
| Failure | The failure its assertions can actually detect |
| Decision | Retain, repair, consolidate, or delete, with the reason |
| Remaining proof | The retained test and distinct contract, or why the contract is obsolete |
| Context | Relevant history, production callers, and support code affected |
| Validation | Risk, baseline result, and the focused command or control |

An unknown history or caller is uncertainty, not proof of obsolescence. Keep uncertain
candidates pending. Treat a baseline failure as a possible product defect. Reproduce it and
report it; repair it only when the current task authorizes that repair.

## Completion and handoff

A focused audit ends when its scoped candidates have evidence and each authorized edit has
passed validation. A campaign uses the additional stopping rules in its guide.

Report the contracts retained, tests removed or repaired, production simplifications, proof
actually run, baseline failures, and unresolved candidates. Count production, tests, and support
separately. If coverage was measured, report the metric and configuration. State branch, PR, and
merge status accurately. Route an authorized landing through `land` and use `reflect` for
verified lessons. An audit does not need a commit or PR unless the task calls for one.

## Source

Adapted from OpenClaw's test-audit skill. See [upstream sources and MIT notice](references/upstream.md).
