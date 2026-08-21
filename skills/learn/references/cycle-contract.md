# Prometheus learning-cycle contract

Use this reference for unattended fleet runs and scheduler installation. Session-mode learning is
defined in `../SKILL.md` and needs no scheduler.

## Cadence

- **Every substantive task:** the shared Borrowed Fire doctrine invokes `learn` before final
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
2. use the host-specific high-water mark and never claim visibility into other machines;
3. retain only verified durable deltas and deduplicate before capture;
4. leave ambiguous items pending rather than advancing past them;
5. use `remember` for writes and `digest` for restructuring;
6. avoid product-repo, account, credential, deployment, release, store, skill, doctrine, and
   scheduler mutations;
7. run with normal bootstrap context so the installed skill and doctrine remain visible;
8. stay disabled until scheduler-level alerts cover pre-turn failures and skipped runs;
9. avoid routine notifications; notify the owner for a material digest, actionable conflict,
   failure, or prevention decision.

The scheduler's own run history is the audit trail for successful no-op runs. Prometheus pages are
the audit trail for material captures. Do not add “ran successfully” journal noise.

## Installation

After installing Borrowed Fire skills into the OpenClaw workspace, run from the canonical public
Borrowed Fire checkout:

```sh
./tools/install-prometheus-cycle.sh --notify-channel <channel> --notify-to <owner-route>
```

The installer resolves Prometheus with the standard pointer rules and declares one idempotent
OpenClaw job. It requires and verifies an explicit owner-notification destination before enabling
the job. It does not pin a model/provider; private fleet policy remains authoritative.

Useful overrides:

```sh
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>'
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --agent main --cron '35 4 * * *' --tz America/New_York
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --brain /absolute/path/to/prometheus
./tools/install-prometheus-cycle.sh --notify-channel imessage --notify-to '<owner-route>' --dry-run
```

Re-run after changing the skill or schedule. The declaration key updates the same job instead of
creating another one.
