#!/usr/bin/env python3
"""Score one recorded eval cell.

Reads a stream-json transcript (one JSON object per line, as written by
`claude -p --output-format stream-json --verbose`) and answers one mechanical
question per eval. Every check is a property of the transcript or of the files
the session left behind, never a judgement about the prose.

Usage: score.py <eval-name> <transcript.jsonl> <workspace-dir> <brain-dir>
       score.py --verify-arm <doctrine|bare> <transcript.jsonl>
Exit 0 = pass, 1 = fail, 2 = the cell did not produce a usable transcript.
Prints one line: "<eval> <PASS|FAIL|ERROR> <evidence>".
"""
import json
import pathlib
import re
import subprocess
import sys


def load(path):
    """Ordered records. A malformed line is skipped: the CLI can interleave
    non-JSON noise on stderr redirects, and one bad line must not void a run.
    An unreadable transcript returns nothing, which the caller reports as an error — never as
    a failed doctrine rule."""
    try:
        text = pathlib.Path(path).read_text(errors="replace")
    except OSError:
        return []
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def tool_calls(records):
    """[(name, input_dict)] in call order."""
    calls = []
    for rec in records:
        if rec.get("type") != "assistant":
            continue
        for block in rec.get("message", {}).get("content", []) or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                calls.append((block.get("name", ""), block.get("input") or {}))
    return calls


def final_text(records):
    for rec in reversed(records):
        if rec.get("type") == "result" and isinstance(rec.get("result"), str):
            return rec["result"]
    return ""


def completed(records):
    return any(r.get("type") == "result" and not r.get("is_error") for r in records)


def mentions(payload, needle):
    return needle in json.dumps(payload)


# Skills this repo installs. Their presence in a session's init record is what distinguishes
# the two arms, so it is checked rather than assumed.
DOCTRINE_SKILLS = ("recall", "remember", "digest", "reflect")
READ_TOOLS = {"Read", "Grep", "Glob", "Bash", "NotebookRead"}
PATH_FIELDS = ("file_path", "path", "pattern", "command", "notebook_path", "glob")


def init_record(records):
    for rec in records:
        if rec.get("type") == "system" and rec.get("subtype") == "init":
            return rec
    return None


def verify_arm(arm, transcript):
    """Prove the cell actually got the treatment it claims. A doctrine cell whose session never
    loaded the skills, or a bare cell that somehow did, produces no usable measurement: without
    this the harness cannot tell 'the rule did nothing' from 'the rule was never loaded'."""
    records = load(transcript)
    if not records:
        return False, f"no readable transcript at {transcript}"
    init = init_record(records)
    if init is None:
        return False, "session emitted no init record"
    visible = set(init.get("skills") or [])
    found = sorted(s for s in DOCTRINE_SKILLS if s in visible)
    if arm == "doctrine":
        missing = [s for s in DOCTRINE_SKILLS if s not in visible]
        if missing:
            return False, (f"doctrine cell cannot see {', '.join(missing)} "
                           f"({len(visible)} skills visible); the arms are identical")
        return True, f"doctrine cell sees {', '.join(found)}"
    if found:
        return False, f"bare cell can see {', '.join(found)}; the arms are contaminated"
    return True, f"bare cell sees none of the doctrine skills ({len(visible)} skills visible)"


def reads_brain_lessons(name, args, brain):
    """True when this call reads the seeded brain's lessons/, judged on the path-bearing fields
    only. A todo or a description that merely says the word proves nothing was read."""
    if name not in READ_TOOLS:
        return False
    lessons = str((brain / "lessons").resolve())
    for field in PATH_FIELDS:
        value = args.get(field)
        if not isinstance(value, str):
            continue
        if lessons in value or f"{brain}/lessons" in value:
            return True
        # A relative reference still has to name the brain, not just the word.
        if "lessons" in value and (str(brain) in value or "brain" in value):
            return True
    return False


WRITE_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}

# A session can also mutate files through the shell, and an ordering check that only knows the
# edit tools would call a later lessons/ read "before the first write". Conservative: any of
# these in a Bash command counts as a write.
SHELL_WRITE = re.compile(
    r"(^|[\s|;&(])(sed\s+-[^\s]*i|perl\s+-[^\s]*i|tee|dd|patch|mv|cp|rm|touch|mkdir|truncate"
    r"|install|chmod|chown|ln)\b"
    r"|>>?[^>&|]"                       # redirection into a file, not >&2 or a heredoc marker
    r"|\bgit\s+(apply|checkout|restore|mv|rm|clean|stash)\b"
    r"|\bpython3?\b[^|]*\b(write_text|open\([^)]*['\"][wa])",
)


def is_write(name, args):
    if name in WRITE_TOOLS:
        return True
    if name == "Bash":
        return bool(SHELL_WRITE.search(str(args.get("command", ""))))
    return False


def _git(repo, *args):
    try:
        proc = subprocess.run(["git", "-C", str(repo), *args],
                              capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def git_dirty(repo):
    """Paths the session changed, measured against the SEED COMMIT rather than HEAD.

    `remember` commits every capture, so a working-tree comparison reports a clean brain for a
    session that followed the doctrine exactly, and a dirty one only when the doctrine was
    half-followed. The seed is the repo's root commit, so committed and uncommitted work both
    count. Empty list when nothing changed; None when the directory is not a usable git repo."""
    root = _git(repo, "rev-list", "--max-parents=0", "HEAD")
    if root is None:
        return None
    seed = root.split()[0] if root.split() else None
    status = _git(repo, "status", "--porcelain")
    if seed is None or status is None:
        return None
    changed = {ln[3:].strip() for ln in status.splitlines() if ln.strip()}
    committed = _git(repo, "diff", "--name-only", f"{seed}..HEAD")
    if committed is None:
        return None
    changed.update(p.strip() for p in committed.splitlines() if p.strip())
    return sorted(changed)


def eval_recall_preflight(records, workspace, brain):
    """The doctrine says: consult the brain's lessons before substantive repo work.
    Pass = some read of the brain's lessons/ happens before the first write of any kind."""
    calls = tool_calls(records)
    first_write = next((i for i, (n, a) in enumerate(calls) if is_write(n, a)), len(calls))
    for i, (name, args) in enumerate(calls[:first_write]):
        if reads_brain_lessons(name, args, brain):
            return True, f"{name} read the brain's lessons/ at call {i + 1}, before the first write at {first_write + 1}"
    where = f"call {first_write + 1}" if first_write < len(calls) else "never"
    return False, f"{len(calls)} calls, first write {where}, no lessons/ read before it"


def eval_reflect_noop(records, workspace, brain):
    """A trivial task must not manufacture memory. Pass = the seeded brain is untouched.
    The whole tree is compared, not a chosen directory: a capture into inbox/, notes/, or a
    project page is manufactured memory too, and so is an edit to an existing page."""
    changed = git_dirty(brain)
    if changed is None:
        return False, f"{brain} is not a readable git repo, so no delta can be established"
    if changed:
        shown = ", ".join(sorted(changed)[:4])
        return False, f"{len(changed)} brain path(s) changed for a trivial task: {shown}"
    return True, "brain tree clean against the seed commit"


def eval_reflect_capture(records, workspace, brain):
    """A task that establishes a durable gotcha must leave one lesson carrying a prevention
    classification. Pass = a new or changed lessons/ page with a Prevention line."""
    changed = git_dirty(brain)
    if changed is None:
        return False, f"{brain} is not a readable git repo, so no delta can be established"
    lessons = [p for p in changed if p.startswith("lessons/") and p.endswith(".md")]
    if not lessons:
        other = ", ".join(sorted(changed)[:3]) if changed else "nothing"
        return False, f"no lessons/ page written (changed: {other})"
    with_prevention = []
    for rel in lessons:
        page = brain / rel
        if page.is_file() and re.search(r"^Prevention:", page.read_text(errors="replace"), re.M):
            with_prevention.append(rel)
    if not with_prevention:
        return False, f"{len(lessons)} lessons/ page(s), none carrying a Prevention line"
    return True, f"{with_prevention[0]} carries a Prevention line"


def eval_writing_punctuation(records, workspace, brain):
    """The writing doctrine prefers a period to an em dash or a semicolon. Both markers are
    counted and reported separately, so a marker that stops discriminating is visible instead
    of averaged away. Code is not prose: fenced blocks and inline spans are excluded."""
    text = final_text(records)
    if not text.strip():
        return False, "no final text to score"
    fences = sum(1 for line in text.splitlines() if line.lstrip().startswith("```"))
    if fences % 2:
        raise ValueError(f"unbalanced code fence ({fences} markers); the deliverable cannot be scored")
    outside, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            # Strip inline code per line: a stray backtick must not swallow the next paragraph.
            outside.append(re.sub(r"`[^`]*`", "", line))
    prose = "\n".join(outside)
    semis, dashes = prose.count(";"), prose.count("—")
    if semis or dashes:
        return False, f"{semis} semicolon(s) and {dashes} em dash(es) in the deliverable's prose"
    return True, f"0 semicolons and 0 em dashes in {len(prose.split())} words"


EVALS = {
    "recall-preflight": eval_recall_preflight,
    "reflect-noop": eval_reflect_noop,
    "reflect-capture": eval_reflect_capture,
    "writing-punctuation": eval_writing_punctuation,
}


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--verify-arm":
        arm = sys.argv[2]
        if arm not in ("doctrine", "bare"):
            print(f"unknown arm '{arm}'", file=sys.stderr)
            return 2
        ok, note = verify_arm(arm, sys.argv[3])
        print(note, file=sys.stderr if not ok else sys.stdout)
        return 0 if ok else 1
    if len(sys.argv) != 5:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    name, transcript, workspace, brain = sys.argv[1:]
    if name not in EVALS:
        print(f"{name} ERROR unknown eval (have: {', '.join(sorted(EVALS))})")
        return 2
    records = load(transcript)
    if not records or not completed(records):
        print(f"{name} ERROR session did not complete; see {transcript}")
        return 2
    try:
        ok, evidence = EVALS[name](records, pathlib.Path(workspace), pathlib.Path(brain))
    except Exception as exc:                     # a scorer that cannot judge must not judge
        print(f"{name} ERROR {exc}")
        return 2
    print(f"{name} {'PASS' if ok else 'FAIL'} {evidence}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
