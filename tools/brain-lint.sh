#!/usr/bin/env bash
# Lint a Prometheus brain tree against the schema in skills/remember/references/brain-schema.md.
# digest runs this (or the same checks by hand) during its Inventory step; owners can run it any
# time. Exits non-zero on any error. A red result means housekeeping is due, not that data is
# lost.
#
# Usage: brain-lint.sh [--template] [<brain-root>]
#   --template   lint prometheus-template/: skip placeholder-date, INDEX-count, INDEX-freshness,
#                and claim-TTL checks that only make sense on a live brain.
#   <brain-root> defaults to $PROMETHEUS_DIR, then ~/.config/borrowedfire/brain's pointer, then
#                ~/prometheus.
set -u

TEMPLATE=0
BRAIN=""
for arg in "$@"; do
  case "$arg" in
    --template) TEMPLATE=1 ;;
    *) BRAIN="$arg" ;;
  esac
done
if [ -z "$BRAIN" ]; then
  if [ -n "${PROMETHEUS_DIR:-}" ]; then
    BRAIN="$PROMETHEUS_DIR"
  elif [ -f "$HOME/.config/borrowedfire/brain" ]; then
    BRAIN="$(head -1 "$HOME/.config/borrowedfire/brain")"
  else
    BRAIN="$HOME/prometheus"
  fi
fi
[ -d "$BRAIN" ] || { echo "ERROR: brain root '$BRAIN' is not a directory" >&2; exit 1; }
BRAIN="$(cd "$BRAIN" && pwd)"

ERRORS=0
err() { echo "ERROR: $*" >&2; ERRORS=$((ERRORS + 1)); }

frontmatter() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }

# Epoch seconds for a YYYY-MM-DD date or ISO timestamp; GNU date parses both with -d, BSD date
# needs an explicit format per shape. Empty on failure.
to_epoch() {
  date -d "$1" +%s 2>/dev/null ||
    date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null ||
    date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || true
}
NOW="$(date +%s)"

# --- required tree ---
[ -f "$BRAIN/INDEX.md" ] || err "missing INDEX.md"
if [ ! -f "$BRAIN/.gitattributes" ]; then
  err "missing .gitattributes (union-merge rules)"
else
  for rule in 'journal/*.md merge=union' 'inbox/*.md merge=union' 'projects/*.md merge=union'; do
    grep -qF "$rule" "$BRAIN/.gitattributes" || err ".gitattributes: missing rule '$rule'"
  done
fi
for d in config inbox journal people companies projects meetings decisions lessons notes; do
  [ -d "$BRAIN/$d" ] || err "missing directory $d/"
done

# --- per-page checks ---
# Directory -> required frontmatter type. config/ holds instance notes; inbox/ is raw and
# unchecked beyond conflict markers; projects/archive/ is digest-owned archived project pages.
expected_type() {
  case "$1" in
    config) echo "note" ;;
    journal) echo "journal" ;;
    people) echo "person" ;;
    companies) echo "company" ;;
    projects) echo "project" ;;
    meetings) echo "meeting" ;;
    decisions) echo "decision" ;;
    lessons) echo "lesson" ;;
    notes) echo "note" ;;
    *) echo "" ;;
  esac
}

check_page() { # check_page <file> <expected-type>
  page="$1"
  want="$2"
  rel="${page#"$BRAIN"/}"

  head -1 "$page" | grep -qx -- '---' || { err "$rel: no frontmatter block"; return; }

  fm="$(frontmatter "$page")"

  dup="$(printf '%s\n' "$fm" | grep -oE '^[a-z_]+:' | sort | uniq -d | tr '\n' ' ')"
  [ -z "$dup" ] || err "$rel: duplicated frontmatter keys ($dup) — union-merge artifact, digest repairs"

  got="$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p' | head -1 | awk '{print $1}')"
  [ -n "$got" ] || err "$rel: missing frontmatter 'type'"
  if [ -n "$want" ] && [ -n "$got" ] && [ "$got" != "$want" ]; then
    err "$rel: type '$got' does not match directory (expected '$want')"
  fi

  for key in created updated status; do
    printf '%s\n' "$fm" | grep -q "^$key:" || err "$rel: missing frontmatter '$key'"
  done

  created="$(printf '%s\n' "$fm" | sed -n 's/^created:[[:space:]]*//p' | head -1 | awk '{print $1}')"
  updated="$(printf '%s\n' "$fm" | sed -n 's/^updated:[[:space:]]*//p' | head -1 | awk '{print $1}')"
  for pair in "created=$created" "updated=$updated"; do
    val="${pair#*=}"
    key="${pair%%=*}"
    [ -z "$val" ] && continue
    printf '%s' "$val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ||
      err "$rel: $key '$val' is not a YYYY-MM-DD date"
    if [ "$TEMPLATE" -eq 0 ] && [ "$val" = "1970-01-01" ]; then
      err "$rel: $key is the 1970-01-01 template placeholder — set the real date"
    fi
  done

  # updated must not lag the last dated log bullet (ISO dates compare lexically).
  last_bullet="$(grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}:' "$page" | tail -1 | sed 's/^- //; s/:$//')"
  if [ -n "$last_bullet" ] && [ -n "$updated" ] && [ "$updated" \< "$last_bullet" ]; then
    err "$rel: updated '$updated' is older than last log bullet '$last_bullet' — digest reconcile due"
  fi

  # Every dated log bullet (with its wrapped continuation lines) carries a writer tag.
  missing_tag="$(awk '
    function flush() { if (inb && !ok) print start; inb = 0 }
    /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]:/ {
      flush(); inb = 1; ok = 0; start = FNR
      if ($0 ~ /\[[a-z0-9-]+@[A-Za-z0-9._-]+\]/) ok = 1
      next
    }
    /^- / || /^$/ || /^#/ || /^---$/ { flush() }
    inb && /\[[a-z0-9-]+@[A-Za-z0-9._-]+\]/ { ok = 1 }
    END { flush() }
  ' "$page")"
  for line in $missing_tag; do
    err "$rel:$line: dated log bullet has no [harness@host] writer tag"
  done
}

for d in config journal people companies projects meetings decisions lessons notes; do
  [ -d "$BRAIN/$d" ] || continue
  for page in "$BRAIN/$d"/*.md; do
    [ -e "$page" ] || continue
    case "$(basename "$page")" in _template.md) continue ;; esac
    check_page "$page" "$(expected_type "$d")"
  done
done
for page in "$BRAIN"/projects/archive/*.md; do
  [ -e "$page" ] || continue
  check_page "$page" "project"
  grep -q '^status:[[:space:]]*archived' "$page" || err "projects/archive/$(basename "$page"): status must be 'archived'"
done

# --- conflict markers, everywhere including inbox ---
while IFS= read -r hit; do
  err "merge conflict markers: $hit"
done < <(grep -rlE '^(<<<<<<<|=======|>>>>>>>)' --include='*.md' "$BRAIN" 2>/dev/null | sed "s|^$BRAIN/||")

# --- wikilinks resolve (template placeholders exempt) ---
while IFS=: read -r file link; do
  target="$(printf '%s' "$link" | sed 's/^\[\[//; s/\]\]$//; s/|.*//')"
  case "$target" in *'<'*) continue ;; esac
  [ -f "$BRAIN/$target.md" ] || [ -f "$BRAIN/$target" ] ||
    err "${file#"$BRAIN"/}: broken wikilink [[$target]]"
done < <(grep -roE '\[\[[^]]+\]\]' --include='*.md' "$BRAIN" | grep -v '_template.md:')

# --- dead queue claims: released in a later log bullet, or past the 24h TTL ---
if [ "$TEMPLATE" -eq 0 ]; then
  while IFS=: read -r file line text; do
    # A claim released per maintainer's format leaves a 'released claim on <item>' log bullet
    # on the same page; such a claim is dead regardless of age.
    item="$(printf '%s' "$text" | awk '{print $3}')"
    if [ -n "$item" ] && grep -qF "released claim on $item" "$file"; then
      err "${file#"$BRAIN"/}:$line: dead queue claim (released in a log bullet) — digest queue sweep due"
      continue
    fi
    last_field="$(printf '%s' "$text" | awk '{print $NF}')"
    day="$(printf '%s' "$last_field" | cut -c1-10)"
    if ! printf '%s' "$day" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      err "${file#"$BRAIN"/}:$line: claim has no trailing timestamp"
      continue
    fi
    # A full ISO stamp gets the TTL plus an hour of grace, measured from the claim time. A
    # date-only stamp anchors at midnight, so allow 48h before calling it dead.
    epoch=""
    limit=172800
    case "$last_field" in
      *T*)
        epoch="$(to_epoch "$last_field")"
        [ -n "$epoch" ] && limit=90000
        ;;
    esac
    [ -n "$epoch" ] || epoch="$(to_epoch "$day")"
    [ -n "$epoch" ] || continue
    if [ $((NOW - epoch)) -gt "$limit" ]; then
      err "${file#"$BRAIN"/}:$line: dead queue claim from $day — digest queue sweep due"
    fi
  done < <(grep -rnE '^- claimed ' --include='*.md' "$BRAIN/projects" 2>/dev/null)
fi

# --- INDEX freshness and counts ---
if [ "$TEMPLATE" -eq 0 ] && [ -f "$BRAIN/INDEX.md" ]; then
  gen="$(sed -n 's/^Last generated: \([0-9-]*\).*/\1/p' "$BRAIN/INDEX.md" | head -1)"
  if [ -z "$gen" ]; then
    err "INDEX.md: no 'Last generated:' line — run digest"
  else
    gen_epoch="$(to_epoch "$gen")"
    # 'Last generated' is date-only, so the anchor is midnight. Seven days plus six hours of
    # grace clears the nightly pass's own window (03:35 on day seven) without masking a missed
    # run past the same morning.
    if [ -n "$gen_epoch" ] && [ $((NOW - gen_epoch)) -gt $((7 * 86400 + 6 * 3600)) ]; then
      err "INDEX.md: last completed digest was $gen — over the 7-day cadence, digest due"
    fi
  fi

  for d in journal people companies meetings decisions lessons notes; do
    stated="$(sed -n "s/^- $d: \([0-9][0-9]*\).*/\1/p" "$BRAIN/INDEX.md" | head -1)"
    [ -n "$stated" ] || { err "INDEX.md: missing count line for $d"; continue; }
    actual=$(find "$BRAIN/$d" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    [ "$stated" = "$actual" ] || err "INDEX.md: $d count $stated, tree has $actual — digest refresh due"
  done
  stated="$(sed -n 's/^- projects: \([0-9][0-9]*\) active.*/\1/p' "$BRAIN/INDEX.md" | head -1)"
  if [ -n "$stated" ]; then
    actual=$(grep -l '^status:[[:space:]]*active' "$BRAIN/projects"/*.md 2>/dev/null | grep -cv '_template.md')
    [ "$stated" = "$actual" ] || err "INDEX.md: active project count $stated, tree has $actual — digest refresh due"
  else
    err "INDEX.md: missing '- projects: N active' count line"
  fi
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "brain-lint: $ERRORS error(s) in $BRAIN" >&2
  exit 1
fi
echo "brain-lint: OK ($BRAIN)"
