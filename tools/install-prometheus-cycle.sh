#!/usr/bin/env bash
# Declare the unattended Prometheus learning cycle on one always-on OpenClaw host.
# Uses OpenClaw's declaration key so re-running updates one job instead of creating duplicates.
set -u

SRC="$(cd "$(dirname "$0")/.." && pwd -P)"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
BRAIN=""
CRON_EXPR="35 3 * * *"
TIMEZONE="America/New_York"
AGENT_ID="main"
NOTIFY_CHANNEL=""
NOTIFY_TO=""
DRY=0
ROUTE_PROOF_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/borrowedfire/prometheus-learning-route.sha256"

is_git_checkout() {
  local requested top
  [ -d "$1" ] || return 1
  requested="$(cd "$1" && pwd -P)" || return 1
  top="$(git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)" || return 1
  [ "$requested" = "$top" ]
}

is_prometheus_root() {
  is_git_checkout "$1" &&
    [ -f "$1/INDEX.md" ] &&
    [ -f "$1/config/fleet.md" ] &&
    [ -f "$1/projects/_template.md" ] &&
    [ -f "$1/.gitattributes" ] &&
    grep -qxF 'journal/*.md merge=union' "$1/.gitattributes" &&
    grep -qxF 'inbox/*.md merge=union' "$1/.gitattributes" &&
    grep -qxF 'projects/*.md merge=union' "$1/.gitattributes"
}

managed_learning_stack_matches() {
  python3 - "$SRC" "$1" <<'PY'
import os
import stat
import sys
from pathlib import Path

source_root = Path(sys.argv[1]).resolve()
workspace = Path(sys.argv[2]).resolve()
skills = ("borrowedfire-learn", "remember", "recall", "digest")
manifest_path = workspace / "skills" / ".borrowedfire-manifest"

try:
    lines = manifest_path.read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

manifest = {}
for line in lines:
    parts = line.split()
    if len(parts) != 2 or parts[0] in manifest:
        raise SystemExit(1)
    manifest[parts[0]] = parts[1]

def tree_entries(root, ignore_marker=False):
    entries = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        for name in dirs + files:
            if ignore_marker and name == ".borrowedfire-copy":
                continue
            path = base_path / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISDIR(info.st_mode):
                entries[relative] = ("dir", None)
            elif stat.S_ISREG(info.st_mode):
                entries[relative] = ("file", path.read_bytes())
            elif stat.S_ISLNK(info.st_mode):
                entries[relative] = ("link", os.readlink(path))
            else:
                raise SystemExit(1)
    return entries

for name in skills:
    source = source_root / "skills" / name
    target = workspace / "skills" / name
    mode = manifest.get(name)
    if mode == "link":
        if not target.is_symlink() or os.readlink(target) != str(source):
            raise SystemExit(1)
    elif mode == "copy":
        marker = target / ".borrowedfire-copy"
        if target.is_symlink() or not target.is_dir() or not marker.is_file():
            raise SystemExit(1)
        if tree_entries(source) != tree_entries(target, ignore_marker=True):
            raise SystemExit(1)
    else:
        raise SystemExit(1)

try:
    doctrine = (source_root / "doctrine" / "DOCTRINE.md").read_text(encoding="utf-8")
    context = (workspace / "AGENTS.md").read_text(encoding="utf-8")
except OSError:
    raise SystemExit(1)
if context.count(doctrine) != 1:
    raise SystemExit(1)
PY
}

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
if ! command -v git >/dev/null 2>&1; then
  printf 'git is required to resolve and validate Prometheus.\n' >&2
  exit 1
fi
if [ -z "$BRAIN" ] && is_git_checkout "$HOME/prometheus"; then
  BRAIN="$HOME/prometheus"
fi

if [ -z "$BRAIN" ] || ! is_prometheus_root "$BRAIN"; then
  printf 'Prometheus brain root/schema not found; pass its exact Git root or configure ~/.config/borrowedfire/brain.\n' >&2
  exit 1
fi
BRAIN="$(cd "$BRAIN" && pwd -P)"

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

if [ "$DRY" -eq 1 ]; then
  printf 'would declare %s (%s) at %s [%s]\n' "$JOB_NAME" "$DECLARATION_KEY" "$CRON_EXPR" "$TIMEZONE"
  printf 'Prometheus: %s\n' "$BRAIN"
  printf 'Agent: %s; notification channel: %s; explicit destination configured\n' "$AGENT_ID" "$NOTIFY_CHANNEL"
  exit 0
fi

AGENTS_OUTPUT="$("$OPENCLAW_BIN" agents list --json)" || {
  printf 'Configured OpenClaw agents could not be inspected; no job was declared.\n' >&2
  exit 1
}
AGENT_WORKSPACE="$(printf '%s' "$AGENTS_OUTPUT" | python3 -c '
import json
import sys

requested = sys.argv[1]
try:
    agents = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)
if not isinstance(agents, list):
    raise SystemExit(1)
matches = [item for item in agents if isinstance(item, dict) and item.get("id") == requested]
if len(matches) != 1 or not isinstance(matches[0].get("workspace"), str) or not matches[0]["workspace"].strip():
    raise SystemExit(1)
print(matches[0]["workspace"].strip())
' "$AGENT_ID")" || {
  printf 'Requested OpenClaw agent is not configured with one concrete workspace; no job was declared.\n' >&2
  exit 1
}
if [ ! -d "$AGENT_WORKSPACE" ]; then
  printf 'Requested OpenClaw agent workspace does not exist; no job was declared.\n' >&2
  exit 1
fi
AGENT_WORKSPACE="$(cd "$AGENT_WORKSPACE" && pwd -P)"
if ! managed_learning_stack_matches "$AGENT_WORKSPACE"; then
  printf 'Requested OpenClaw workspace lacks the exact installer-managed learning stack and doctrine from this checkout; no job was declared.\n' >&2
  exit 1
fi

HOST_ID="$(hostname -s)" || {
  printf 'Host identity could not be resolved; no job was declared.\n' >&2
  exit 1
}
WATERMARK_FILE="$(python3 - "$HOST_ID" "$AGENT_ID" "$AGENT_WORKSPACE" <<'PY'
import hashlib
import os
import re
import sys

def slug(value):
    normalized = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    if not normalized:
        raise SystemExit(1)
    return normalized

host = slug(sys.argv[1])
agent = slug(sys.argv[2])
workspace = os.path.realpath(sys.argv[3])
workspace_name = slug(os.path.basename(workspace))
workspace_hash = hashlib.sha256(workspace.encode("utf-8")).hexdigest()[:12]
print(f"notes/openclaw-{host}-{agent}-{workspace_name}-{workspace_hash}-ingest.md")
PY
)" || {
  printf 'Host/agent/workspace watermark identity could not be derived; no job was declared.\n' >&2
  exit 1
}

MESSAGE="Run the installed borrowedfire-learn skill in fleet mode. The Prometheus root is $BRAIN. Follow the skill and its cycle-contract reference exactly. Use only $WATERMARK_FILE as this controller binding's high-water mark; ingest only verified durable deltas visible in this agent workspace since that mark; deduplicate before using remember; advance the mark only after durable commit/push; and invoke digest only when seven days have elapsed since its last completed run or inbox backlog exceeds 15. Never claim access to another host, agent, or workspace's private session history. Do not mutate product repositories, accounts, credentials, deployments, releases, stores, skills, doctrine, or scheduler configuration, except to delete one exact local-only .brain-outbox/<file> after its capture is committed and pushed to Prometheus; never delete the directory, another item, or a pending item. Do not announce routine success or a no-op. Use the configured message target only for one concise material-digest summary, an actionable owner decision, conflicting evidence, a sync/push failure, or a concrete prevention follow-up."
TOOLS_ALLOW="read,edit,write,apply_patch,exec,process,message"

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
  --no-deliver
  --channel "$NOTIFY_CHANNEL"
  --to "$NOTIFY_TO"
  --timeout-seconds 900
  --tools "$TOOLS_ALLOW"
  --message "$MESSAGE"
  --json
)

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

CONVERGE_ARGS=(
  cron edit "$JOB_ID"
  --name "$JOB_NAME"
  --description "$DESCRIPTION"
  --agent "$AGENT_ID"
  --session isolated
  --clear-session-key
  --wake now
  --cron "$CRON_EXPR"
  --tz "$TIMEZONE"
  --message "$MESSAGE"
  --timeout-seconds 900
  --no-light-context
  --tools "$TOOLS_ALLOW"
  --no-deliver
  --channel "$NOTIFY_CHANNEL"
  --to "$NOTIFY_TO"
)

if ! "$OPENCLAW_BIN" "${CONVERGE_ARGS[@]}" >/dev/null; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Agent/workspace job convergence failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

if ! "$OPENCLAW_BIN" cron edit "$JOB_ID" --no-failure-alert >/dev/null; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Old failure-alert policy could not be cleared; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

ALERT_ARGS=(
  cron edit "$JOB_ID"
  --failure-alert
  --failure-alert-after 2
  --failure-alert-cooldown 12h
  --failure-alert-include-skipped
  --failure-alert-mode announce
  --failure-alert-channel "$NOTIFY_CHANNEL"
  --failure-alert-to "$NOTIFY_TO"
)

if ! "$OPENCLAW_BIN" "${ALERT_ARGS[@]}" >/dev/null; then
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
    "name": sys.argv[7],
    "description": sys.argv[8],
    "message": sys.argv[9],
    "tools": sys.argv[10].split(","),
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
agent_payload = job.get("payload")
checks = [
    job.get("id") == expected["job_id"],
    job.get("declarationKey") == "borrowedfire.prometheus-learning.v1",
    job.get("name") == expected["name"],
    job.get("displayName") == expected["name"],
    job.get("description") == expected["description"],
    job.get("enabled") is False,
    job.get("agentId") == expected["agent_id"],
    job.get("sessionTarget") == "isolated",
    not job.get("sessionKey"),
    job.get("wakeMode") == "now",
    isinstance(delivery, dict) and delivery.get("mode") == "none",
    isinstance(delivery, dict) and delivery.get("channel") == expected["channel"],
    isinstance(delivery, dict) and delivery.get("to") == expected["to"],
    isinstance(delivery, dict) and not delivery.get("accountId"),
    isinstance(delivery, dict) and delivery.get("threadId") is None,
    isinstance(failure, dict) and failure.get("after") == 2,
    isinstance(failure, dict) and failure.get("cooldownMs") == 43200000,
    isinstance(failure, dict) and failure.get("includeSkipped") is True,
    isinstance(failure, dict) and failure.get("mode") == "announce",
    isinstance(failure, dict) and failure.get("channel") == expected["channel"],
    isinstance(failure, dict) and failure.get("to") == expected["to"],
    isinstance(failure, dict) and not failure.get("accountId"),
    isinstance(schedule, dict) and schedule.get("expr") == expected["expr"],
    isinstance(schedule, dict) and schedule.get("tz") == expected["timezone"],
    isinstance(agent_payload, dict) and agent_payload.get("kind") == "agentTurn",
    isinstance(agent_payload, dict) and agent_payload.get("message") == expected["message"],
    isinstance(agent_payload, dict) and agent_payload.get("timeoutSeconds") == 900,
    isinstance(agent_payload, dict) and agent_payload.get("lightContext") is False,
    isinstance(agent_payload, dict) and agent_payload.get("toolsAllow") == expected["tools"],
]
if not all(checks):
    raise SystemExit(1)
' "$JOB_ID" "$AGENT_ID" "$CRON_EXPR" "$TIMEZONE" "$NOTIFY_CHANNEL" "$NOTIFY_TO" "$JOB_NAME" "$DESCRIPTION" "$MESSAGE" "$TOOLS_ALLOW"; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Stored job does not match the requested safe configuration; Prometheus learning job is disabled.\n' >&2
  exit 1
fi

ROUTE_HASH="$(python3 - "$NOTIFY_CHANNEL" "$NOTIFY_TO" <<'PY'
import hashlib
import sys

print(hashlib.sha256((sys.argv[1] + "\0" + sys.argv[2]).encode("utf-8")).hexdigest())
PY
)" || {
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Could not derive the private notification-route proof; Prometheus learning job is disabled.\n' >&2
  exit 1
}

STORED_ROUTE_HASH=""
if [ -e "$ROUTE_PROOF_FILE" ] || [ -L "$ROUTE_PROOF_FILE" ]; then
  STORED_ROUTE_HASH="$(python3 - "$ROUTE_PROOF_FILE" <<'PY'
import os
import stat
import sys

path = sys.argv[1]
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
    info = os.fstat(descriptor)
    if not stat.S_ISREG(info.st_mode):
        raise OSError("route proof is not a regular file")
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
        value = handle.read().strip()
except OSError:
    raise SystemExit(1)
print(value)
PY
)" || {
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Existing notification-route proof is unsafe or unreadable; Prometheus learning job is disabled.\n' >&2
    exit 1
  }
fi

if [ "$STORED_ROUTE_HASH" != "$ROUTE_HASH" ]; then
  PROOF_DIR="$(dirname "$ROUTE_PROOF_FILE")"
  mkdir -p "$PROOF_DIR" || {
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Could not prepare notification-route proof storage; Prometheus learning job is disabled.\n' >&2
    exit 1
  }
  PROOF_TMP="$(mktemp "$PROOF_DIR/.prometheus-learning-route.XXXXXX")" || {
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Could not prepare notification-route proof storage; Prometheus learning job is disabled.\n' >&2
    exit 1
  }
  if ! chmod 600 "$PROOF_TMP"; then
    rm -f "$PROOF_TMP"
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Could not prepare notification-route proof storage; Prometheus learning job is disabled.\n' >&2
    exit 1
  fi
  PROBE_MESSAGE="Prometheus learning notifications are configured on this host. This is a one-time route verification."
  PROBE_OUTPUT="$("$OPENCLAW_BIN" message send \
    --channel "$NOTIFY_CHANNEL" \
    --target "$NOTIFY_TO" \
    --message "$PROBE_MESSAGE" \
    --json)" || {
      rm -f "$PROOF_TMP"
      "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
      printf 'Live notification-route verification failed; Prometheus learning job is disabled.\n' >&2
      exit 1
    }
  if ! printf '%s' "$PROBE_OUTPUT" | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

def acknowledged(value):
    if isinstance(value, dict):
        for key, item in value.items():
            normalized = key.replace("_", "").lower()
            if normalized in {"messageid", "sentmessageid"} and isinstance(item, str) and item.strip():
                return True
        return any(acknowledged(item) for item in value.values())
    if isinstance(value, list):
        return any(acknowledged(item) for item in value)
    return False

if not acknowledged(payload):
    raise SystemExit(1)
'; then
    rm -f "$PROOF_TMP"
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Notification provider returned no message acknowledgement; Prometheus learning job is disabled.\n' >&2
    exit 1
  fi

  if ! printf '%s\n' "$ROUTE_HASH" > "$PROOF_TMP" ||
     ! python3 - "$PROOF_TMP" "$ROUTE_PROOF_FILE" "$ROUTE_HASH" <<'PY'
import os
import stat
import sys

temporary, target, expected = sys.argv[1:]
try:
    if os.path.lexists(target):
        current = os.lstat(target)
        if not stat.S_ISREG(current.st_mode) or stat.S_ISLNK(current.st_mode):
            raise OSError("unsafe route proof target")
    os.replace(temporary, target)
    current = os.lstat(target)
    if not stat.S_ISREG(current.st_mode) or stat.S_ISLNK(current.st_mode):
        raise OSError("unsafe route proof result")
    if stat.S_IMODE(current.st_mode) != 0o600:
        raise OSError("route proof permissions are not private")
    with open(target, encoding="utf-8") as handle:
        if handle.read().splitlines() != [expected]:
            raise OSError("route proof contents do not match")
except OSError:
    raise SystemExit(1)
PY
  then
    rm -f "$PROOF_TMP"
    "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
    printf 'Could not persist and verify notification-route proof; Prometheus learning job is disabled.\n' >&2
    exit 1
  fi
  printf 'Notification route verified with a live one-time message.\n'
else
  printf 'Notification route already has a matching host-local live proof.\n'
fi

if ! "$OPENCLAW_BIN" cron enable "$JOB_ID" >/dev/null; then
  "$OPENCLAW_BIN" cron disable "$JOB_ID" >/dev/null 2>&1 || true
  printf 'Enable failed; Prometheus learning job is disabled.\n' >&2
  exit 1
fi
printf 'Prometheus learning job enabled after exact configuration and route verification.\n'
