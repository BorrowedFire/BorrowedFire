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

SRC="$(cd "$(dirname "$0")" && pwd -P)"
MANIFEST_NAME=".borrowedfire-manifest"
MARK_BEGIN="<!-- BEGIN BORROWEDFIRE DOCTRINE -->"
MARK_END="<!-- END BORROWEDFIRE DOCTRINE -->"
# Skill names from older revisions of this repo; eligible for --adopt cleanup.
LEGACY_NAMES="takeoff autoland orbit repo-quality-audit blackbox debrief learn"
LEARNING_SKILLS="borrowedfire-learn remember recall digest"

COPY=0 DRY=0 UNINSTALL=0 ADOPT=0 BRAIN="" OPENCLAW_WS="" INSTALL_ERRORS=0
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

is_git_checkout() {
  local requested top
  [ -d "$1" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
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
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}"   # Codex relocates its root via CODEX_HOME
[ -d "$HOME/.claude" ] && HARNESSES+=("claude|$HOME/.claude/skills|$HOME/.claude/CLAUDE.md")
[ -d "$CODEX_ROOT" ]   && HARNESSES+=("codex|$CODEX_ROOT/skills|$CODEX_ROOT/AGENTS.md")
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

skill_is_managed() { # skill_is_managed <skilldir> <manifest> <name>
  local sd="$1" mf="$2" name="$3" mode tgt src
  mode="$(manifest_mode "$mf" "$name")"
  tgt="$sd/$name"
  src="$SRC/skills/$name"
  case "$mode" in
    link) [ -L "$tgt" ] && [ "$(readlink "$tgt")" = "$src" ] ;;
    copy) [ -d "$tgt" ] && [ ! -L "$tgt" ] && [ -e "$tgt/.borrowedfire-copy" ] ;;
    *) return 1 ;;
  esac
}

skill_has_unmanaged_collision() { # skill_has_unmanaged_collision <skilldir> <manifest> <name>
  local sd="$1" mf="$2" name="$3" mode tgt
  mode="$(manifest_mode "$mf" "$name")"
  tgt="$sd/$name"
  [ -L "$tgt" ] || [ -e "$tgt" ] || return 1
  if [ -L "$tgt" ] && [ "$(readlink "$tgt")" = "$SRC/skills/$name" ]; then
    return 1
  fi
  case "$mode" in
    # A manifest-owned symlink may still point at an older checkout. install_skill
    # safely repoints it before the final exact ownership check.
    link) [ -L "$tgt" ] || return 0 ;;
    copy) [ -d "$tgt" ] && [ ! -L "$tgt" ] && [ -e "$tgt/.borrowedfire-copy" ] || return 0 ;;
    *) return 0 ;;
  esac
  return 1
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
      # a correct link may predate the manifest (manual install / stale manifest):
      # record it so uninstall and pruning manage it
      [ "$DRY" -eq 1 ] || [ "$owned" = "link" ] || manifest_set "$mf" "$name" link
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
        # owned link pointing elsewhere: a moved/re-cloned checkout leaves these
        # dangling - clean those up; a still-working foreign link may be the
        # user's own replacement, so leave it and just de-own
        if [ "$mode" = "link" ] && [ ! -e "$tgt" ]; then
          act "remove   $3 ($4; dangling link from a moved checkout)" rm -f "$tgt"
        else
          say "  LEAVE    $3 - working symlink not pointing at this checkout; de-owning only"
        fi ;;
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

resolve_context_target() { # resolve_context_target <path>
  local target="$1" link hops=0 target_dir
  while [ -L "$target" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
    link="$(readlink "$target")" || return 1
    case "$link" in
      /*) target="$link" ;;
      *) target="$(dirname "$target")/$link" ;;
    esac
  done
  target_dir="$(cd "$(dirname "$target")" && pwd -P)" || return 1
  printf '%s/%s\n' "$target_dir" "$(basename "$target")"
}

write_doctrine() { # write_doctrine <context-file> <doctrine-source> <description>
  local cf="$1" source="$2" description="$3" target tmp mode source_lines
  if [ "$DRY" -eq 1 ]; then say "  doctrine $cf ($description)"; return; fi
  mkdir -p "$(dirname "$cf")" || return 1
  touch "$cf" || return 1
  target="$(resolve_context_target "$cf")" || return 1
  tmp="$(mktemp "$(dirname "$target")/.borrowedfire-doctrine.XXXXXX")" || return 1
  if ! awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) {inblock=1; next}
    index($0, e) {inblock=0; next}
    !inblock && /^[[:space:]]*$/ {blanks=blanks $0 ORS; next}
    !inblock {printf "%s%s\n", blanks, $0; blanks=""}
  ' "$target" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! { echo ""; cat "$source"; } >> "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mode="$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null)" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi
  source_lines="$(wc -l < "$source" | tr -d ' ')"
  if [ -z "$source_lines" ] || [ "$source_lines" -eq 0 ] ||
     ! tail -n "$source_lines" "$cf" | cmp -s - "$source"; then
    return 1
  fi
  say "  doctrine $cf ($description)"
}

update_doctrine() { # update_doctrine <context-file>
  write_doctrine "$1" "$SRC/doctrine/DOCTRINE.md" "updated"
}

update_safe_doctrine() { # update_safe_doctrine <context-file>
  write_doctrine "$1" "$SRC/doctrine/DOCTRINE_NO_LEARNING.md" "learning disabled; safety retained"
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
  learning_collision=""
  for learning_name in $LEARNING_SKILLS; do
    if skill_has_unmanaged_collision "$sd" "$mf" "$learning_name"; then
      learning_collision="$learning_name"
      break
    fi
  done

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

  learning_unmanaged=""
  if [ "$DRY" -eq 0 ]; then
    for learning_name in $LEARNING_SKILLS; do
      if ! skill_is_managed "$sd" "$mf" "$learning_name"; then
        learning_unmanaged="$learning_name"
        break
      fi
    done
  fi
  if { [ -n "$learning_collision" ] && [ "$ADOPT" -eq 0 ]; } || [ -n "$learning_unmanaged" ]; then
    learning_problem="${learning_collision:-$learning_unmanaged}"
    if update_safe_doctrine "$cf"; then
      echo "error: $label has an unmanaged automatic-learning dependency ($learning_problem); automatic learning disabled while non-learning doctrine remains active" >&2
    else
      echo "error: $label has an unmanaged automatic-learning dependency ($learning_problem), and the safe doctrine could not be verified; inspect $cf before the next task" >&2
    fi
    INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
  else
    if ! update_doctrine "$cf"; then
      echo "error: $label doctrine update could not be written and verified" >&2
      INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
  fi
done

if [ "$INSTALL_ERRORS" -gt 0 ]; then
  echo "install failed closed: the automatic-learning stack is not fully installer-owned in $INSTALL_ERRORS harness(es)" >&2
  exit 1
fi

# --- brain pointer ---
if [ "$UNINSTALL" -eq 0 ]; then
  ptr="$HOME/.config/borrowedfire/brain"
  if [ -n "$BRAIN" ]; then
    if is_prometheus_root "$BRAIN"; then
      BRAIN="$(cd "$BRAIN" && pwd -P)"
      act "brain pointer -> $BRAIN" mkdir -p "$(dirname "$ptr")"
      [ "$DRY" -eq 1 ] || printf '%s\n' "$BRAIN" > "$ptr"
    else
      echo "warning: --brain '$BRAIN' is not an exact Prometheus Git root with the required schema; pointer not written." >&2
    fi
  elif [ ! -f "$ptr" ] && is_prometheus_root "$HOME/prometheus"; then
    act "brain pointer -> $HOME/prometheus" mkdir -p "$(dirname "$ptr")"
    [ "$DRY" -eq 1 ] || printf '%s\n' "$HOME/prometheus" > "$ptr"
  fi
fi

say "done."
