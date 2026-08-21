#!/usr/bin/env bash
# Declare the unattended Prometheus learning cycle on one always-on OpenClaw host.
# Uses OpenClaw's declaration key so re-running updates one job instead of creating duplicates.
set -u

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BRAIN=""
CRON_EXPR="35 3 * * *"
TIMEZONE="America/New_York"
AGENT_ID="main"
NOTIFY_CHANNEL=""
NOTIFY_TO=""
DRY=0

usage() {
  printf '%s\n' \
    "usage: $0 [--brain <path>] [--agent <id>] [--cron <expression>] [--tz <iana-zone>]" \
    "          --notify-channel <channel> --notify-to <destination> [--dry-run]" \
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
    --notify-channel) shift; NOTIFY_CHANNEL="${1:-}" ;;
    --notify-to) shift; NOTIFY_TO="${1:-}" ;;
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
if [ -z "$AGENT_ID" ] || [ -z "$NOTIFY_CHANNEL" ] || [ -z "$NOTIFY_TO" ]; then
  printf 'agent id, notification channel, and notification destination must not be blank.\n' >&2
  exit 1
fi

JOB_NAME="Prometheus Learning Cycle"
DECLARATION_KEY="borrowedfire.prometheus-learning.v1"
DESCRIPTION="Nightly verified learning, status capture, and due-only consolidation in the shared Prometheus brain."
MESSAGE="Run the installed learn skill in fleet mode. The Prometheus root is $BRAIN. Follow the skill and its cycle-contract reference exactly. Ingest only verified durable deltas visible on this host since its successful high-water mark; deduplicate before using remember; advance the mark only after durable commit/push; and invoke digest only when seven days have elapsed since its last completed run or inbox backlog exceeds 15. Never claim access to another host's session history. Do not mutate product repositories, accounts, credentials, deployments, releases, stores, skills, doctrine, or scheduler configuration. Do not announce routine success or a no-op. Use the configured message target only for one concise material-digest summary, an actionable owner decision, conflicting evidence, a sync/push failure, or a concrete prevention follow-up."

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
  --channel "$NOTIFY_CHANNEL"
  --to "$NOTIFY_TO"
  --timeout-seconds 900
  --tools "read,edit,write,apply_patch,exec,process,message"
  --message "$MESSAGE"
  --json
)

if [ "$DRY" -eq 1 ]; then
  printf 'would declare %s (%s) at %s [%s]\n' "$JOB_NAME" "$DECLARATION_KEY" "$CRON_EXPR" "$TIMEZONE"
  printf 'Prometheus: %s\n' "$BRAIN"
  printf 'Agent: %s; notification channel: %s; explicit destination configured\n' "$AGENT_ID" "$NOTIFY_CHANNEL"
  exit 0
fi

STATUS_OUTPUT="$("$OPENCLAW_BIN" cron status --json)" || exit $?
if ! printf '%s' "$STATUS_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
if not isinstance(payload, dict) or payload.get("enabled") is not True:
    raise SystemExit(1)
'; then
  printf 'OpenClaw scheduler is disabled or its status could not be verified; no job was declared.\n' >&2
  exit 1
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
  --failure-alert-channel "$NOTIFY_CHANNEL"
  --failure-alert-to "$NOTIFY_TO"
)

if ! "$OPENCLAW_BIN" "${ALERT_ARGS[@]}"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Failure-alert setup failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

VERIFY_OUTPUT="$("$OPENCLAW_BIN" cron get "$JOB_ID")" || {
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Job verification failed; Prometheus learning job is disabled.\n' >&2
  exit 1
}
if ! printf '%s' "$VERIFY_OUTPUT" | python3 -c '
import json
import sys

expected = {
    "job_id": sys.argv[1],
    "agent_id": sys.argv[2],
    "expr": sys.argv[3],
    "timezone": sys.argv[4],
    "channel": sys.argv[5],
    "to": sys.argv[6],
}
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
job = payload.get("job", payload) if isinstance(payload, dict) else None
if not isinstance(job, dict):
    raise SystemExit(1)
delivery = job.get("delivery")
failure = job.get("failureAlert")
schedule = job.get("schedule")
checks = [
    job.get("id") == expected["job_id"],
    job.get("declarationKey") == "borrowedfire.prometheus-learning.v1",
    job.get("enabled") is False,
    job.get("agentId") == expected["agent_id"],
    job.get("sessionTarget") == "isolated",
    isinstance(delivery, dict) and delivery.get("mode") == "none",
    isinstance(delivery, dict) and delivery.get("channel") == expected["channel"],
    isinstance(delivery, dict) and delivery.get("to") == expected["to"],
    isinstance(failure, dict) and failure.get("after") == 2,
    isinstance(failure, dict) and failure.get("includeSkipped") is True,
    isinstance(failure, dict) and failure.get("channel") == expected["channel"],
    isinstance(failure, dict) and failure.get("to") == expected["to"],
    isinstance(schedule, dict) and schedule.get("expr") == expected["expr"],
    isinstance(schedule, dict) and schedule.get("tz") == expected["timezone"],
]
if not all(checks):
    raise SystemExit(1)
' "$JOB_ID" "$AGENT_ID" "$CRON_EXPR" "$TIMEZONE" "$NOTIFY_CHANNEL" "$NOTIFY_TO"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Stored job does not match the requested safe configuration; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

if ! "$OPENCLAW_BIN" cron enable "$JOB_ID"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Enable failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi
