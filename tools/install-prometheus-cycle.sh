#!/usr/bin/env bash
# Declare the unattended Prometheus learning cycle on one always-on OpenClaw host.
# Uses OpenClaw's declaration key so re-running updates one job instead of creating duplicates.
set -u

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BRAIN=""
CRON_EXPR="35 2 * * *"
TIMEZONE="America/New_York"
DRY=0

usage() {
  printf '%s\n' \
    "usage: $0 [--brain <path>] [--cron <expression>] [--tz <iana-zone>] [--dry-run]" \
    "" \
    "Declares one nightly OpenClaw agent job. Provider/model selection remains in private" \
    "fleet configuration; this public installer does not pin either."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --brain) shift; BRAIN="${1:-}" ;;
    --cron) shift; CRON_EXPR="${1:-}" ;;
    --tz) shift; TIMEZONE="${1:-}" ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$BRAIN" ] && [ -n "${PROMETHEUS_DIR:-}" ]; then
  BRAIN="$PROMETHEUS_DIR"
fi
if [ -z "$BRAIN" ] && [ -f "$HOME/.config/borrowedfire/brain" ]; then
  IFS= read -r BRAIN < "$HOME/.config/borrowedfire/brain"
fi
if [ -z "$BRAIN" ] && [ -d "$HOME/prometheus/.git" ]; then
  BRAIN="$HOME/prometheus"
fi

if [ -z "$BRAIN" ] || [ ! -d "$BRAIN/.git" ]; then
  printf 'Prometheus brain not found; pass --brain or configure ~/.config/borrowedfire/brain.\n' >&2
  exit 1
fi
BRAIN="$(cd "$BRAIN" && pwd)"

if [ "$DRY" -eq 0 ] && ! command -v "$OPENCLAW_BIN" >/dev/null 2>&1; then
  printf 'OpenClaw CLI not found: %s\n' "$OPENCLAW_BIN" >&2
  exit 1
fi

JOB_NAME="Prometheus Learning Cycle"
DECLARATION_KEY="borrowedfire.prometheus-learning.v1"
DESCRIPTION="Nightly verified learning, status capture, and due-only consolidation in the shared Prometheus brain."
MESSAGE="Run the installed learn skill in fleet mode. The Prometheus root is $BRAIN. Follow the skill and its cycle-contract reference exactly. Ingest only verified durable deltas visible on this host since its successful high-water mark; deduplicate before using remember; advance the mark only after durable commit/push; and invoke digest only when seven days have elapsed since its last completed run or inbox backlog exceeds 15. Never claim access to another host's session history. Do not mutate product repositories, accounts, credentials, deployments, releases, stores, skills, doctrine, or scheduler configuration. Do not announce routine success or a no-op. Use the existing message capability only for an actionable owner decision, conflicting evidence, a sync/push failure, or a concrete prevention follow-up."

ARGS=(
  cron add
  --name "$JOB_NAME"
  --display-name "$JOB_NAME"
  --description "$DESCRIPTION"
  --declaration-key "$DECLARATION_KEY"
  --cron "$CRON_EXPR"
  --tz "$TIMEZONE"
  --session isolated
  --wake now
  --light-context
  --expect-final
  --no-deliver
  --timeout-seconds 900
  --tools "read,edit,write,apply_patch,exec,process,message"
  --message "$MESSAGE"
  --json
)

if [ "$DRY" -eq 1 ]; then
  printf 'would declare %s (%s) at %s [%s]\n' "$JOB_NAME" "$DECLARATION_KEY" "$CRON_EXPR" "$TIMEZONE"
  printf 'Prometheus: %s\n' "$BRAIN"
  exit 0
fi

"$OPENCLAW_BIN" "${ARGS[@]}"
