# Test-pruning campaign

Use this guide when the user requests a systematic reduction across a named test surface.
Apply the authoring, retention, evidence, and authorization rules in [test-audit](../SKILL.md).

## Set a target that can be checked

Honor the user's metric and limits. If the user requests a campaign without numbers, use this
starting target and state it before editing: remove 20% of the baseline's least useful test
cases, with no more than a 2 percentage point drop in each available production coverage
metric. Apply the limit separately to line coverage and branch coverage. Keep stricter repository
thresholds. This is a search target, not a deletion quota.
The target never permits losing the only meaningful protection for a current contract.

Use the test runner's collected cases as the count, including parameter rows. Moving cases into
a table or renaming them does not count as removing cases. If the project cannot enumerate
cases reliably, choose and state a reproducible metric before editing, such as test and support
code lines. Report both cases and code size when available. Exclude formatting-only changes and
generated output from claimed reductions.

Record the production revision, test commands, collected inventory, existing failures, and
coverage tool, version, configuration, and included production files. Use the same settings and
production file set for the final comparison. If production code is legitimately removed,
report that denominator change separately and compare the common files too. Do not change
exclusions, thresholds, instrumentation, or test discovery to meet the target.

For example, a change from 90% to 88% is a 2 percentage point drop. Report line and branch
coverage separately. Also inspect losses on the changed files; a repository average can hide a
lost error branch. If a metric cannot be measured, report that constraint as unverified. Do not
claim that the campaign met a coverage limit without comparable measurements.

## Inspect the whole scope

Split the inventory by the production behavior each group owns. Include shared fixtures,
cross-package scenarios, platform variants, and CI-only suites. For each test case, record
retain, repair, consolidate, or delete with the evidence required by the skill. Parameter rows
need separate decisions when their risks differ.

Keep one ledger across batches. Each entry needs a current decision, remaining proof, and
validation status. Use parallel discovery only when the active workflow permits it and the
groups can be reviewed independently. Serialize edits to shared harnesses and support files.

After classifying individual cases, inspect overlapping suites. Identify which suite will
retain each contract, the unique assertions that must move, and the support code that becomes
unused. This second pass catches redundant layers that isolated test-by-test review misses.

## Apply and verify coherent batches

For each authorized batch:

1. Transfer required assertions, then remove confirmed duplicates and unused support.
2. Run affected and adjacent checks. Confirm that moved tests still execute in CI.
3. Compare the deleted assertions with the retained suite. Use independent review when the
   workflow provides it. Check negative paths and the reason each rejection occurs.
4. For each transferred or repaired contract, use a targeted mutation or failing control to
   show that the retained assertion detects its intended failure. Restore the source exactly.
5. Update the ledger and measurements before starting the next batch.

When a baseline failure reveals a product defect, keep it visible. Fix it only within existing
authority and record that work separately from test reduction. When upstream changes touch a
retired test, reassess the contract and move its new protection before preserving the deletion.
Follow the repository's branch and review rules. Large campaigns can use several coherent PRs.

## Finish the goal or explain the limit

Continue across batches until the target is met with retained contracts and passing checks, or
every in-scope case has been reviewed and no further safe reduction is supported. A first useful
batch is progress, not completion. A written inventory of remaining work is not completion.

Missing credentials, unavailable runners, an owner decision, or the active workflow's resource
limit can end execution early. Preserve the ledger and report the campaign as incomplete. If
the full inventory supports less than the target, report the achieved reduction and the
specific protections that prevent further removal. Do not weaken tests to reach a percentage.

After the last edit, run the full scoped suite and required repository checks. Compare baseline
and final case counts, test/support/production size, coverage, and runtime when measured under
comparable conditions. Report lost covered lines or branches and their contract disposition.
Distinguish target met, scope exhausted below target, and incomplete proof.

Store durable test-ownership lessons through `reflect`. A campaign does not authorize rewriting
shared doctrine or instructions in unrelated repositories.
