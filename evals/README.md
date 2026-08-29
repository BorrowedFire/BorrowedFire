# Doctrine evals

The test suites prove the machinery: the installer writes what it claims, the brain protocol
survives concurrent writers, the scheduler declaration converges. None of them proves the thing
the system exists for — that an agent reading the doctrine behaves differently from one that
never saw it.

That gap has bitten before. A rule sat at the top of a context file for weeks and never fired,
and it surfaced by accident (`lessons/name-a-standard-and-it-will-not-fire`). These evals close
it by measuring behavior instead of text.

## What an eval measures

Each eval runs the same task twice: once with the Borrowed Fire skills installed (`doctrine`
arm) and once with an empty skill set (`bare` arm). The result that matters is the **gap**.

| eval | doctrine rule under test | mechanical pass condition | kind |
|---|---|---|---|
| `recall-preflight` | consult the brain's lessons before substantive repo work | a read of `lessons/` precedes the first write of any kind | discriminator |
| `reflect-capture` | a task establishing a durable gotcha captures one lesson with a prevention class | a changed `lessons/` page carries a `Prevention:` line | discriminator |
| `writing-punctuation` | prefer a period to an em dash or a semicolon | zero semicolons and zero em dashes in the deliverable's prose | discriminator |
| `reflect-noop` | a trivial task captures nothing; a clean no-op is success | the seeded brain tree is unchanged | guard |

A **discriminator** should differ between the arms: the bare arm has no reason to consult a brain
nobody told it to consult, and no reason to prefer a period. A **guard** should pass in both — the
bare arm has no `reflect` to run, so it cannot manufacture memory, and the point is that
installing the doctrine does not start manufacturing it either. Read a guard's equal columns as
"no regression", and a discriminator's equal columns as "this rule is not doing any work".

Every condition is a property of the transcript or of the files the session left behind. No
model judges another model's output, so a run is reproducible and cheap to argue with.

Read the results the way the runner prints them: **a discriminator is firing when `doctrine`
passes and `bare` does not.** Equal columns on a discriminator mean the behavior was not
produced by the doctrine — the model would have done it anyway, and the rule is decoration. A
rule that fails in both arms is not reaching the agent at all.

## Running it

```sh
export ANTHROPIC_API_KEY=...        # required, see Isolation
evals/run.sh                        # 4 evals x 2 arms x 2 repeats = 16 sessions
evals/run.sh --evals recall-preflight --repeats 4 --keep
```

Flags: `--evals a,b` · `--arms doctrine,bare` · `--repeats N` · `--model M` · `--keep` (keep the
transcripts for inspection).

**This is a pre-release gate, not a CI step.** Every cell is a real agent session that costs
real money and takes real time, and the results are noisy at small `N`. Run it before a release
that touches doctrine, the memory skills, or the writing standard. `tests/test-evals.sh` runs in
CI instead: it proves the scorer against recorded transcripts and costs nothing.

## Isolation

Each cell gets a throwaway `HOME`, a fresh git workspace, and its own brain seeded from
`prometheus-template/`. The `doctrine` arm installs the skills into that `HOME` with
`install.sh --copy`; the `bare` arm installs nothing. The two arms differ by exactly one thing.

The runner requires `ANTHROPIC_API_KEY` and has no fallback. A sandbox `HOME` cannot use the
interactive login, because OAuth credentials live in the system keychain rather than in the home
directory. Running against the operator's real `HOME` would load their own skills into *both*
arms, so the bare arm would silently measure the doctrine too. Ponytail's benchmark shipped that
exact bug — a `SessionStart` hook fired on every arm, and the baseline was secretly running the
skill under test — and caught it only after nearly publishing a 4% result. The runner refuses
that configuration rather than reporting a number it cannot stand behind.

Two consequences of that design are easy to get backwards, and this harness got the first one
wrong before review caught it:

- **Cells do not restrict `--setting-sources`.** `install.sh` writes the skills and the doctrine
  block into the *user* source of the cell's own `HOME`. Excluding `user` looks like isolation
  and is actually the opposite: it strips the treatment, both arms become identical, and every
  eval reports that the doctrine does nothing. Isolation comes from the sandbox `HOME` alone.
- **Both arms get `--add-dir <brain>`.** An asymmetric grant would let the doctrine arm reach a
  brain the bare arm physically cannot open, so every gap would measure the grant rather than
  the rule. The bare arm can reach the brain and has no reason to look in it.

Because that first mistake is invisible in the results — it shows up as a clean, confident
"no effect" — every cell verifies its own arm before it is scored. The session's `init` record
lists the skills it loaded. A `doctrine` cell that cannot see `recall`, `remember`, `digest`, and
`reflect` is an error, not a failing rule, and so is a `bare` cell that can see any of them. A
run that cannot tell "the rule did nothing" from "the rule was never loaded" is worth less than
no run at all.

## Adding an eval

1. Add a `prompt_for` case in `run.sh` — one task, stated the way a user would state it. Never
   name the rule in the prompt. Asking "remember to check lessons first" measures instruction
   following, not whether the doctrine fires on its own.
2. Add a scorer in `score.py` returning `(passed, evidence)`. Read the transcript's tool calls
   or the files on disk. If a check needs a model to judge it, it is not ready to be an eval.
3. Add fixtures to `tests/test-evals.sh` covering a passing case, a failing case, and the
   near-miss you expect to get wrong.

## Honest limits

- **Small N.** The default of 2 repeats detects a large gap, not a small one. A one-cell
  difference is noise. Raise `--repeats` before believing a narrow result.
- **Four rules of many.** The doctrine says more than these evals measure. An unmeasured rule is
  unproven, not proven-absent.
- **Prompts age.** A task the model learns to do unprompted stops discriminating between the
  arms. A converged eval should be replaced, not celebrated.
- **The scorer is a proxy.** `recall-preflight` proves that `lessons/` was read before a write,
  not that the lesson changed the fix. That is the honest ceiling of a mechanical check.
- **No live cell has ever run.** Every check here was proven against recorded transcripts and a
  mock endpoint. The first real invocation is a calibration run, not a measurement: read its
  arm-check lines first, and treat a surprising column as a harness bug until the transcripts
  say otherwise.

## Known gaps, deferred on purpose

Three review rounds each found this harness measuring the wrong thing in a new place, so these
are recorded rather than quietly carried. All bias the measured gap toward zero, which means a
weak result is the expected failure and a strong one is trustworthy.

- follow-up: `reads_brain_lessons` misses `Bash` reads written through `$PROMETHEUS_DIR`, and
  `Grep` calls that split the brain across `path` and `glob`. The doctrine teaches the
  `$PROMETHEUS_DIR` idiom, so the false negative lands on the doctrine arm only. Trigger: the
  first live run showing `recall-preflight` failing in the doctrine arm with a brain read
  visible in the transcript.
- follow-up: `SHELL_WRITE` counts `2>/dev/null` as a write, so an orienting `ls -la 2>/dev/null`
  pins the first write to call one and fails an otherwise correct session. Trigger: same run,
  same eval.
- follow-up: `verify_arm` reads only the first `init` record and has no exception guard, so a
  changed init schema produces a traceback instead of a clean error. Trigger: a CLI upgrade, or
  any cell whose arm check dies rather than failing.
- follow-up: the runner has no per-cell timeout, so one stuck session hangs a 16-cell run with
  no partial report. Trigger: the first run that has to be interrupted.
- follow-up: `writing-punctuation` counts only the em dash and the semicolon the doctrine names.
  A model steered onto en dashes or ` -- ` scores clean. Trigger: a doctrine arm that passes
  this eval while its prose still reads as dash-joined.
