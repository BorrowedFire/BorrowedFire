#!/usr/bin/env bash
# Borrowed Fire installer: distribute skills/ + the doctrine block to every agent
# harness on this machine. Manifest-owned and idempotent - safe to re-run anytime.
#
#   ./install.sh [--copy] [--dry-run] [--uninstall] [--adopt]
#                [--brain <path>] [--openclaw-workspace <path>]
#
#   --copy                copy skill dirs instead of symlinking (auto-fallback anyway)
#   --dry-run             print planned actions only
#   --uninstall           remove manifest-owned skills + doctrine blocks, nothing else
#   --adopt               take ownership of legacy/unowned dirs that match our skill
#                         names or known legacy names (backs them up first)
#   --brain <path>        write the brain pointer (~/.config/borrowedfire/brain)
#   --openclaw-workspace  path to an OpenClaw workspace to install into
set -u

SRC="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_NAME=".borrowedfire-manifest"
MARK_BEGIN="<!-- BEGIN BORROWEDFIRE DOCTRINE -->"
MARK_END="<!-- END BORROWEDFIRE DOCTRINE -->"
# Skill names from older revisions of this repo; eligible for --adopt cleanup.
LEGACY_NAMES="takeoff autoland orbit repo-quality-audit blackbox debrief"

COPY=0 DRY=0 UNINSTALL=0 ADOPT=0 BRAIN="" OPENCLAW_WS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) COPY=1 ;;
    --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --adopt) ADOPT=1 ;;
    --brain) shift; BRAIN="${1:-}" ;;
    --openclaw-workspace) shift; OPENCLAW_WS="${1:-}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { echo "$@"; }
act() { # act <description> <command...>: honor --dry-run
  local desc="$1"; shift
  say "  $desc"
  [ "$DRY" -eq 1 ] || "$@"
}

# --- preflight: never distribute a broken skill set ---
if [ "$UNINSTALL" -eq 0 ]; then
  if ! "$SRC/tools/skill-lint.sh" >/dev/null; then
    echo "install aborted: skill-lint failed" >&2
    exit 1
  fi
fi

# --- harness detection: root dir existing == harness present ---
# array of rows "<label>|<skills-dir>|<context-file>" (array: paths may contain spaces)
HARNESSES=()
[ -d "$HOME/.claude" ] && HARNESSES+=("claude|$HOME/.claude/skills|$HOME/.claude/CLAUDE.md")
[ -d "$HOME/.codex" ]  && HARNESSES+=("codex|$HOME/.codex/skills|$HOME/.codex/AGENTS.md")
[ -d "$HOME/.qwen" ]   && HARNESSES+=("qwen|$HOME/.qwen/skills|$HOME/.qwen/QWEN.md")
if [ -n "$OPENCLAW_WS" ]; then
  if [ -d "$OPENCLAW_WS" ]; then
    HARNESSES+=("openclaw|$OPENCLAW_WS/skills|$OPENCLAW_WS/AGENTS.md")
  else
    echo "warning: --openclaw-workspace '$OPENCLAW_WS' does not exist; skipping" >&2
  fi
fi
if [ "${#HARNESSES[@]}" -eq 0 ]; then
  echo "no harnesses detected (looked for ~/.claude, ~/.codex, ~/.qwen; pass --openclaw-workspace for OpenClaw)" >&2
  exit 1
fi

manifest_mode() { # manifest_mode <manifest> <name> -> prints mode or nothing
  [ -f "$1" ] && awk -v n="$2" '$1 == n {print $2}' "$1"
}
manifest_set() { # manifest_set <manifest> <name> <mode>
  local mf="$1" name="$2" mode="$3" tmp
  tmp="$(mktemp)"
  [ -f "$mf" ] && awk -v n="$name" '$1 != n' "$mf" > "$tmp"
  echo "$name $mode" >> "$tmp"
  sort "$tmp" > "$mf" && rm -f "$tmp"
}
manifest_del() { # manifest_del <manifest> <name>
  local mf="$1" name="$2" tmp
  [ -f "$mf" ] || return 0
  tmp="$(mktemp)"
  awk -v n="$name" '$1 != n' "$mf" > "$tmp" && mv "$tmp" "$mf"
}

copy_skill() { # copy_skill <src> <tgt>: copy + drop the ownership marker inside
  rm -rf "$2" && cp -R "$1" "$2" && touch "$2/.borrowedfire-copy"
}

install_skill() { # install_skill <skilldir> <manifest> <name>
  local sd="$1" mf="$2" name="$3" owned
  local src="$SRC/skills/$name" tgt="$sd/$name"
  owned="$(manifest_mode "$mf" "$name")"

  if [ -L "$tgt" ] && [ "$(readlink "$tgt")" = "$src" ]; then
    if [ "$COPY" -eq 1 ]; then
      # switching an existing linked install to copy mode
      say "  convert  $name (link -> copy)"
      if [ "$DRY" -eq 0 ]; then
        if copy_skill "$src" "$tgt"; then
          manifest_set "$mf" "$name" copy
        else
          echo "warning: convert of $name failed" >&2
        fi
      fi
    else
      say "  ok       $name (linked)"
    fi
    return
  fi

  if [ -L "$tgt" ] || [ -e "$tgt" ]; then
    if [ "$owned" = "link" ] && [ -L "$tgt" ]; then
      # ours, pointing elsewhere (e.g. the repo moved): repoint
      act "repoint  $name" ln -sfn "$src" "$tgt"
      return
    fi
    if [ "$owned" = "copy" ] && [ ! -L "$tgt" ] && [ -e "$tgt/.borrowedfire-copy" ]; then
      say "  update   $name (copy)"
      if [ "$DRY" -eq 0 ]; then
        copy_skill "$src" "$tgt" || echo "warning: update of $name failed" >&2
      fi
      return
    fi
    # not manifest-owned (or the on-disk shape no longer matches the manifest):
    # a user's own skill dir or symlink - never touch it without --adopt
    if [ "$ADOPT" -eq 1 ]; then
      local bak="$sd/.borrowedfire-backup"
      act "adopt    $name (backed up to .borrowedfire-backup/)" mkdir -p "$bak"
      [ "$DRY" -eq 1 ] || mv "$tgt" "$bak/$name.$(date +%Y%m%d%H%M%S)"
    else
      say "  SKIP     $name - exists and not owned by Borrowed Fire (rerun with --adopt to replace)"
      return
    fi
  fi

  if [ "$COPY" -eq 1 ]; then
    say "  copy     $name"
    if [ "$DRY" -eq 0 ]; then
      if copy_skill "$src" "$tgt"; then
        manifest_set "$mf" "$name" copy
      else
        echo "warning: copy of $name failed; not recorded" >&2
      fi
    fi
  else
    if [ "$DRY" -eq 1 ]; then
      say "  link     $name"
    elif ln -s "$src" "$tgt" 2>/dev/null; then
      say "  link     $name"
      manifest_set "$mf" "$name" link
    else
      say "  copy     $name (symlink unsupported here)"
      if copy_skill "$src" "$tgt"; then
        manifest_set "$mf" "$name" copy
      else
        echo "warning: copy of $name failed; not recorded" >&2
      fi
    fi
  fi
}

remove_entry() { # remove_entry <skilldir> <manifest> <name> <why>
  # Only delete what still looks like ours; a shape change since install means
  # the user replaced it - de-own the manifest entry but leave the files alone.
  local tgt="$1/$3" mode
  mode="$(manifest_mode "$2" "$3")"
  if [ -L "$tgt" ]; then
    case "$(readlink "$tgt")" in
      "$SRC"/skills/*)
        act "remove   $3 ($4)" rm -f "$tgt" ;;
      *)
        say "  LEAVE    $3 - symlink no longer points at Borrowed Fire; de-owning only" ;;
    esac
  elif [ -d "$tgt" ]; then
    if [ "$mode" = "copy" ] && [ -e "$tgt/.borrowedfire-copy" ]; then
      act "remove   $3 ($4)" rm -rf "$tgt"
    else
      say "  LEAVE    $3 - directory is not (or no longer) our copy; de-owning only"
    fi
  fi
  [ "$DRY" -eq 1 ] || manifest_del "$2" "$3"
}

update_doctrine() { # update_doctrine <context-file>
  local cf="$1" tmp
  if [ "$DRY" -eq 1 ]; then say "  doctrine $cf"; return; fi
  mkdir -p "$(dirname "$cf")"
  touch "$cf"
  tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) {inblock=1; next}
    index($0, e) {inblock=0; next}
    !inblock {print}
  ' "$cf" > "$tmp"
  # trim trailing blank lines, then append the current block
  printf '%s\n' "$(cat "$tmp")" > "$cf" 2>/dev/null || cat "$tmp" > "$cf"
  { echo ""; cat "$SRC/doctrine/DOCTRINE.md"; } >> "$cf"
  rm -f "$tmp"
  say "  doctrine $cf (updated)"
}

remove_doctrine() { # remove_doctrine <context-file>
  local cf="$1" tmp
  [ -f "$cf" ] || return 0
  if [ "$DRY" -eq 1 ]; then say "  doctrine $cf (would remove block)"; return; fi
  tmp="$(mktemp)"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) {inblock=1; next}
    index($0, e) {inblock=0; next}
    !inblock {print}
  ' "$cf" > "$tmp" && mv "$tmp" "$cf"
  say "  doctrine $cf (block removed)"
}

# --- main loop ---
for row in "${HARNESSES[@]}"; do
  label="${row%%|*}"; rest="${row#*|}"
  sd="${rest%%|*}"; cf="${rest#*|}"
  mf="$sd/$MANIFEST_NAME"
  say "== $label ($sd)"
  [ "$DRY" -eq 1 ] || mkdir -p "$sd"

  if [ "$UNINSTALL" -eq 1 ]; then
    if [ -f "$mf" ]; then
      snap="$(mktemp)"; cp "$mf" "$snap"   # snapshot: remove_entry rewrites the manifest
      while IFS=' ' read -r name _mode; do
        [ -n "$name" ] && remove_entry "$sd" "$mf" "$name" "uninstall"
      done < "$snap"
      rm -f "$snap"
      [ "$DRY" -eq 1 ] || rm -f "$mf"
    fi
    remove_doctrine "$cf"
    continue
  fi

  # prune: manifest entries whose source skill no longer exists (renames)
  if [ -f "$mf" ]; then
    snap="$(mktemp)"; cp "$mf" "$snap"     # snapshot: remove_entry rewrites the manifest
    while IFS=' ' read -r name _mode; do
      [ -n "$name" ] || continue
      [ -d "$SRC/skills/$name" ] || remove_entry "$sd" "$mf" "$name" "pruned - no longer in skills/"
    done < "$snap"
    rm -f "$snap"
  fi

  # legacy dirs from pre-installer manual installs
  for legacy in $LEGACY_NAMES; do
    tgt="$sd/$legacy"
    if { [ -L "$tgt" ] || [ -d "$tgt" ]; } && [ -z "$(manifest_mode "$mf" "$legacy")" ]; then
      if [ "$ADOPT" -eq 1 ]; then
        bak="$sd/.borrowedfire-backup"
        act "retire   $legacy (legacy name; backed up)" mkdir -p "$bak"
        [ "$DRY" -eq 1 ] || mv "$tgt" "$bak/$legacy.$(date +%Y%m%d%H%M%S)"
      else
        say "  WARN     $legacy - legacy skill dir present; it will compete with the renamed skill (rerun with --adopt to retire it)"
      fi
    fi
  done

  for src_dir in "$SRC"/skills/*/; do
    install_skill "$sd" "$mf" "$(basename "$src_dir")"
  done

  update_doctrine "$cf"
done

# --- brain pointer ---
if [ "$UNINSTALL" -eq 0 ]; then
  ptr="$HOME/.config/borrowedfire/brain"
  if [ -n "$BRAIN" ]; then
    if [ -d "$BRAIN" ]; then
      act "brain pointer -> $BRAIN" mkdir -p "$(dirname "$ptr")"
      [ "$DRY" -eq 1 ] || printf '%s\n' "$BRAIN" > "$ptr"
    else
      echo "warning: --brain '$BRAIN' does not exist; pointer not written. Clone your brain repo there first (see bfbrain-template/README.md)." >&2
    fi
  elif [ ! -f "$ptr" ] && [ -d "$HOME/bfbrain/.git" ]; then
    act "brain pointer -> $HOME/bfbrain" mkdir -p "$(dirname "$ptr")"
    [ "$DRY" -eq 1 ] || printf '%s\n' "$HOME/bfbrain" > "$ptr"
  fi
fi

say "done."
