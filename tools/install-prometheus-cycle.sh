#!/usr/bin/env bash
# Declare the unattended Prometheus learning cycle on one always-on OpenClaw host.
# Uses OpenClaw's declaration key so re-running updates one job instead of creating duplicates.
set -u

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BRAIN=""
CRON_EXPR="35 2 * * *"
TIMEZONE="America/New_York"
AGENT_ID="main"
FAILURE_CHANNEL="last"
FAILURE_TO=""
DRY=0

usage() {
  printf '%s\n' \
    "usage: $0 [--brain <path>] [--agent <id>] [--cron <expression>] [--tz <iana-zone>]" \
    "          [--failure-channel <channel>] [--failure-to <destination>] [--dry-run]" \
    "" \
    "Declares one nightly OpenClaw agent job. Provider/model selection remains in private" \
    "fleet configuration; this public installer does not pin either."
}

while [ $# -gt 0 ]; do
  case "$1" in
    --brain) shift; BRAIN="${1:-}" ;;
    --agent) shift; AGENT_ID="${1:-}" ;;
    --cron) shift; CRON_EXPR="${1:-}" ;;
    --tz) shift; TIMEZONE="${1:-}" ;;
    --failure-channel) shift; FAILURE_CHANNEL="${1:-}" ;;
    --failure-to) shift; FAILURE_TO="${1:-}" ;;
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
if [ "$DRY" -eq 0 ] && ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required to validate the OpenClaw declaration response.\n' >&2
  exit 1
fi
if [ -z "$AGENT_ID" ] || [ -z "$FAILURE_CHANNEL" ]; then
  printf 'agent id and failure channel must not be blank.\n' >&2
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
  --disabled
  --agent "$AGENT_ID"
  --cron "$CRON_EXPR"
  --tz "$TIMEZONE"
  --session isolated
  --wake now
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
  printf 'Agent: %s; failure channel: %s\n' "$AGENT_ID" "$FAILURE_CHANNEL"
  exit 0
fi

CREATE_OUTPUT="$("$OPENCLAW_BIN" "${ARGS[@]}")" || exit $?
printf '%s\n' "$CREATE_OUTPUT"
JOB_ID="$(printf '%s' "$CREATE_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

job = payload.get("job") if isinstance(payload, dict) else None
job_id = payload.get("id") if isinstance(payload, dict) else None
if not job_id and isinstance(job, dict):
    job_id = job.get("id")
if not isinstance(job_id, str) or not job_id.strip():
    raise SystemExit(1)
print(job_id)
')" || {
  printf 'OpenClaw returned no parseable job id; the declaration remains disabled.\n' >&2
  exit 1
}

ALERT_ARGS=(
  cron edit "$JOB_ID"
  --failure-alert
  --failure-alert-after 2
  --failure-alert-cooldown 12h
  --failure-alert-include-skipped
  --failure-alert-channel "$FAILURE_CHANNEL"
)
[ -z "$FAILURE_TO" ] || ALERT_ARGS+=(--failure-alert-to "$FAILURE_TO")

if ! "$OPENCLAW_BIN" "${ALERT_ARGS[@]}"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Failure-alert setup failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

if ! "$OPENCLAW_BIN" cron enable "$JOB_ID"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Enable failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi
