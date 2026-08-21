# Prometheus learning-cycle contract

Use this reference for unattended fleet runs and scheduler installation. Session-mode learning is
defined in `../SKILL.md` and needs no scheduler.

## Cadence

- **Every substantive task:** the shared Borrowed Fire doctrine invokes `borrowedfire-learn` before final
  closeout. A verified no-op is acceptable.
- **Nightly fleet pass:** one always-on OpenClaw host runs at 03:35 in the owner's timezone. It
  ingests only new local-harness notes/outboxes and exact-current project status into Prometheus.
- **Digest:** the nightly pass invokes `digest` only when at least seven days have elapsed since
  the last completed digest or the inbox exceeds 15 items. The digest lock prevents overlapping
  restructurers.

Nightly timing is deliberately separate from harness-local memory curation. Override the cron
expression when the host has a different maintenance window.

## Required unattended behavior

The fleet worker must:

1. resolve and sync the private Prometheus git repo;
2. scope the high-water mark to harness, stable full host/machine identity, agent, canonical
   workspace, and the effective OpenClaw state/config/profile identity, with text components
   sanitized and the complete binding hashed; never claim visibility into another controller
   binding. On a missing mark, use the cycle-start time as a prospective baseline: do not backfill
   pre-existing session notes, but still inspect pending outboxes and exact-current project status;
3. retain only verified durable deltas and deduplicate before capture;
4. leave ambiguous items pending rather than advancing past them;
5. use `remember` for writes and `digest` for restructuring;
6. avoid product-repo, account, credential, deployment, release, store, skill, doctrine, and
   scheduler mutations, except deleting the exact local-only `.brain-outbox/<file>` whose content
   has already been committed and pushed to Prometheus; never delete a pending item or directory;
7. run with normal bootstrap context so the installed skill and doctrine remain visible; do not
   set a restrictive payload tool allowlist because it suppresses the skills prompt—use the
   private agent-level tool policy for restrictions. OpenClaw may represent a cleared payload
   restriction as either no value or the explicit unrestricted wildcard `["*"]`;
8. stay disabled until scheduler-level alerts cover pre-turn failures and skipped runs;
9. avoid routine notifications; notify the owner for a material digest, actionable conflict,
   failure, or prevention decision.
10. fail without creating a product-repository outbox when Prometheus is unavailable; unattended
    fleet authority never includes a repo-local fallback write.

The scheduler's own run history is the audit trail for successful no-op runs. Prometheus pages are
the audit trail for material captures. Do not add “ran successfully” journal noise.

## Installation

From the canonical public Borrowed Fire checkout, install copy-mode skills into the exact OpenClaw
agent workspace, bind the private brain, and then declare the controller:

```sh
./install.sh --copy --brain /absolute/path/to/prometheus --openclaw-workspace /absolute/path/to/openclaw-workspace
./tools/install-prometheus-cycle.sh --notify-channel <channel> --notify-to <owner-route>
```

The installer resolves Prometheus with the standard pointer rules and declares one idempotent
OpenClaw job. It requires an explicit owner-notification destination and sends one live
route-verification message on every installer convergence before enabling the job. Credential-only
changes cannot be fingerprinted safely from OpenClaw's redacted configuration, so a cached route
hash is never substituted for this live check. It resolves the account from the selected
agent's sole channel-wide binding or the channel's runtime default when bindings are scoped or
ambiguous, then pins that same account on the probe, job delivery, and failure alert. It also
converges the recurring job as persistent, clearing stale one-shot deletion state. A private
host-local route hash records the full controller binding, OpenClaw-reported active config path,
resolved redacted channel configuration, account bindings/status, and OpenClaw version as an audit
identity. It does not pin a model/provider; private fleet policy remains
authoritative. Before it mutates the scheduler, it also asks OpenClaw to prove that
`borrowedfire-learn`, `remember`, `recall`, and `digest` are visible to the exact configured agent.
Copy mode is the portable default for OpenClaw; a symlink install is accepted only when OpenClaw's
effective trusted-target and agent-skill policies expose the same complete stack. Changing agents
disables, removes, and verifies removal of the prior declaration before creating the replacement,
so one declaration key cannot leave two nightly controllers enabled.

Useful overrides:

```sh
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>'
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --agent main --cron '35 4 * * *' --tz America/New_York
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --brain /absolute/path/to/prometheus
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --dry-run
```

Re-run after changing the skill or schedule. The declaration key updates the same job instead of
creating another one.
