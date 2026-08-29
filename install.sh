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
LEGACY_NAMES="takeoff autoland orbit repo-quality-audit blackbox debrief learn borrowedfire-learn"
# Skills the full doctrine mandates by name. The installer must verify every one of them before it
# writes that doctrine, or an agent follows foreign instructions under our banner. Learning carries
# brain-write authority and writing does not, so the error text names the class, but either class
# failing drops the harness to the reduced doctrine: one reduced document beats four variants that
# drift apart, and the install stops loudly with exit 1 rather than settling into a quiet degraded
# state.
LEARNING_SKILLS="reflect remember recall digest"
WRITING_SKILLS="unslop technical-writing"
DOCTRINE_SKILLS="$LEARNING_SKILLS $WRITING_SKILLS"

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

# Uninstall removes skills and doctrine only. A Prometheus learning controller declared by
# tools/install-prometheus-cycle.sh lives in the OpenClaw scheduler and survives this uninstall.
# Its stored job would keep requesting skills that no longer exist. The route-proof file is the
# local trace that a controller was installed on this host.
ROUTE_PROOF_TRACE="${XDG_CONFIG_HOME:-$HOME/.config}/borrowedfire/prometheus-learning-route.sha256"
controller_note() { # print the teardown reminder when a controller trace exists on this host
  # The reminder goes to stderr: two of its call sites are exit-1 paths, and a scripted
  # uninstall that discards stdout must still see it.
  if [ -e "$ROUTE_PROOF_TRACE" ] || [ -L "$ROUTE_PROOF_TRACE" ] || [ -n "$OPENCLAW_WS" ]; then
    {
      say "note: this uninstall does not touch the OpenClaw scheduler. If this host runs the"
      say "      Prometheus learning controller, run tools/install-prometheus-cycle.sh --remove"
      say "      before deleting this checkout, or the nightly job keeps requesting skills that"
      say "      no longer exist."
    } >&2
  fi
}
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
  # A headless controller host can reach this exit with no CLI harness dirs at all. The
  # teardown reminder must still print there, or its nightly job is orphaned silently.
  if [ "$UNINSTALL" -eq 1 ]; then
    controller_note
  fi
  exit 1
fi

# Bind an explicitly requested brain before automatic-learning doctrine can be
# activated in any harness. A rejected or unwritable switch must not leave new
# doctrine silently using an older pointer.
if [ "$UNINSTALL" -eq 0 ] && [ -n "$BRAIN" ]; then
  if ! is_prometheus_root "$BRAIN"; then
    echo "error: --brain '$BRAIN' is not an exact Prometheus Git root with the required schema; installation aborted before doctrine changes." >&2
    exit 1
  fi
  BRAIN="$(cd "$BRAIN" && pwd -P)"
  ptr="$HOME/.config/borrowedfire/brain"
  say "  brain pointer -> $BRAIN"
  if [ "$DRY" -eq 0 ]; then
    ptr_dir="$(dirname "$ptr")"
    mkdir -p "$ptr_dir" || {
      echo "error: brain pointer directory could not be created; installation aborted before doctrine changes." >&2
      exit 1
    }
    ptr_tmp="$(mktemp "$ptr_dir/.brain.XXXXXX")" || {
      echo "error: brain pointer staging file could not be created; installation aborted before doctrine changes." >&2
      exit 1
    }
    if ! printf '%s\n' "$BRAIN" > "$ptr_tmp" || ! chmod 600 "$ptr_tmp" || ! mv -f "$ptr_tmp" "$ptr"; then
      rm -f "$ptr_tmp"
      echo "error: brain pointer could not be written atomically; installation aborted before doctrine changes." >&2
      exit 1
    fi
  fi
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
    copy) [ -d "$tgt" ] && [ ! -L "$tgt" ] && [ -e "$tgt/.borrowedfire-copy" ] &&
      copied_skill_matches "$src" "$tgt" ;;
    *) return 1 ;;
  esac
}

copied_skill_matches() { # copied_skill_matches <source> <target>
  # The ownership marker alone proves provenance, not currency. Automatic
  # doctrine may run only when every copied learning dependency is byte-current.
  diff -qr -x .borrowedfire-copy "$1" "$2" >/dev/null 2>&1
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

doctrine_skill_class() { # doctrine_skill_class <name>: which capability the skill backs
  case " $LEARNING_SKILLS " in
    *" $1 "*) echo "automatic-learning"; return ;;
  esac
  echo "writing"
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
      # Ours, pointing elsewhere (e.g. the repo moved). Honor an explicit
      # copy-mode conversion instead of preserving the stale install mode.
      if [ "$COPY" -eq 1 ]; then
        say "  convert  $name (moved link -> copy)"
        if [ "$DRY" -eq 0 ]; then
          if copy_skill "$src" "$tgt"; then
            manifest_set "$mf" "$name" copy
          else
            echo "warning: convert of $name failed" >&2
          fi
        fi
      else
        act "repoint  $name" ln -sfn "$src" "$tgt"
      fi
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

file_mode() { # file_mode <path>
  local target="$1" mode
  if mode="$(stat -c '%a' "$target" 2>/dev/null)"; then
    printf '%s\n' "$mode"
  elif mode="$(stat -f '%Lp' "$target" 2>/dev/null)"; then
    printf '%s\n' "$mode"
  else
    return 1
  fi
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
  mode="$(file_mode "$target")" || {
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
  local cf="$1" target tmp mode
  [ -f "$cf" ] || return 0
  if [ "$DRY" -eq 1 ]; then say "  doctrine $cf (would remove block)"; return; fi
  target="$(resolve_context_target "$cf")" || return 1
  tmp="$(mktemp "$(dirname "$target")/.borrowedfire-doctrine.XXXXXX")" || return 1
  mode="$(file_mode "$target")" || {
    rm -f "$tmp"
    return 1
  }
  if ! awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    index($0, b) {inblock=1; next}
    index($0, e) {inblock=0; next}
    !inblock {print}
  ' "$target" > "$tmp" || ! chmod "$mode" "$tmp" || ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    return 1
  fi
  if grep -qF "$MARK_BEGIN" "$target" || grep -qF "$MARK_END" "$target"; then
    return 1
  fi
  say "  doctrine $cf (block removed)"
}

# --- main loop ---
for row in "${HARNESSES[@]}"; do
  label="${row%%|*}"; rest="${row#*|}"
  sd="${rest%%|*}"; cf="${rest#*|}"
  mf="$sd/$MANIFEST_NAME"
  say "== $label ($sd)"
  [ "$DRY" -eq 1 ] || mkdir -p "$sd"
  doctrine_collision=""
  for doctrine_skill in $DOCTRINE_SKILLS; do
    if skill_has_unmanaged_collision "$sd" "$mf" "$doctrine_skill"; then
      doctrine_collision="$doctrine_skill"
      break
    fi
  done

  if [ "$UNINSTALL" -eq 1 ]; then
    # Remove the automatic invocation before its skills. If the context cannot
    # be updated, leave the runnable stack intact and fail the uninstall.
    if ! remove_doctrine "$cf"; then
      echo "error: $label doctrine could not be removed; owned skills were left installed" >&2
      INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
      continue
    fi
    if [ -f "$mf" ]; then
      snap="$(mktemp)"; cp "$mf" "$snap"   # snapshot: remove_entry rewrites the manifest
      while IFS=' ' read -r name _mode; do
        [ -n "$name" ] && remove_entry "$sd" "$mf" "$name" "uninstall"
      done < "$snap"
      rm -f "$snap"
      [ "$DRY" -eq 1 ] || rm -f "$mf"
    fi
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

  doctrine_unmanaged=""
  if [ "$DRY" -eq 0 ]; then
    for doctrine_skill in $DOCTRINE_SKILLS; do
      if ! skill_is_managed "$sd" "$mf" "$doctrine_skill"; then
        doctrine_unmanaged="$doctrine_skill"
        break
      fi
    done
  fi
  if { [ -n "$doctrine_collision" ] && [ "$ADOPT" -eq 0 ]; } || [ -n "$doctrine_unmanaged" ]; then
    doctrine_problem="${doctrine_collision:-$doctrine_unmanaged}"
    doctrine_problem_class="$(doctrine_skill_class "$doctrine_problem")"
    if update_safe_doctrine "$cf"; then
      echo "error: $label has an unmanaged $doctrine_problem_class dependency ($doctrine_problem); the reduced doctrine is active - automatic learning disabled, writing skills not mandated" >&2
    else
      echo "error: $label has an unmanaged $doctrine_problem_class dependency ($doctrine_problem), and the reduced doctrine could not be verified; inspect $cf before the next task" >&2
    fi
    INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
  else
    if ! update_doctrine "$cf"; then
      echo "error: $label doctrine update could not be written and verified" >&2
      INSTALL_ERRORS=$((INSTALL_ERRORS + 1))
    fi
  fi
done

# The note prints before the fail-closed exit below on purpose: a partly failed uninstall on a
# messy host is exactly when the owner needs the reminder.
if [ "$UNINSTALL" -eq 1 ]; then
  controller_note
fi

if [ "$INSTALL_ERRORS" -gt 0 ]; then
  echo "operation failed closed: the doctrine-mandated skill stack is not safe in $INSTALL_ERRORS harness(es)" >&2
  exit 1
fi

# --- brain pointer ---
if [ "$UNINSTALL" -eq 0 ]; then
  ptr="$HOME/.config/borrowedfire/brain"
  if [ -z "$BRAIN" ] && [ ! -f "$ptr" ] && is_prometheus_root "$HOME/prometheus"; then
    act "brain pointer -> $HOME/prometheus" mkdir -p "$(dirname "$ptr")"
    if [ "$DRY" -eq 0 ]; then
      printf '%s\n' "$HOME/prometheus" > "$ptr" && chmod 600 "$ptr"
    fi
  fi
fi

say "done."
