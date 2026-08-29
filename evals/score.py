#!/usr/bin/env python3
"""Score one recorded eval cell.

Reads a stream-json transcript (one JSON object per line, as written by
`claude -p --output-format stream-json --verbose`) and answers one mechanical
question per eval. Every check is a property of the transcript or of the files
the session left behind, never a judgement about the prose.

Usage: score.py <eval-name> <transcript.jsonl> <workspace-dir> <brain-dir>
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
    non-JSON noise on stderr redirects, and one bad line must not void a run."""
    out = []
    for line in pathlib.Path(path).read_text(errors="replace").splitlines():
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


def git_dirty(repo):
    """Paths changed since the seed commit, staged, unstaged, or untracked. Empty list when the
    tree is clean; None when the directory is not a usable git repo."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain"],
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return [ln[3:].strip() for ln in proc.stdout.splitlines() if ln.strip()]


def eval_recall_preflight(records, workspace, brain):
    """The doctrine says: consult the brain's lessons before substantive repo work.
    Pass = some read of the brain's lessons/ happens before the first write of any kind."""
    calls = tool_calls(records)
    first_write = next((i for i, (n, a) in enumerate(calls) if is_write(n, a)), len(calls))
    for i, (name, args) in enumerate(calls[:first_write]):
        if mentions(args, "lessons"):
            return True, f"{name} touched lessons/ at call {i + 1}, before the first write at {first_write + 1}"
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


def eval_writing_semicolons(records, workspace, brain):
    """The writing doctrine prefers a period to a semicolon. Scored on the
    deliverable only, and only for semicolons joining prose: a semicolon inside
    a fenced code block is code, not writing."""
    text = final_text(records)
    if not text.strip():
        return False, "no final text to score"
    outside, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            outside.append(line)
    prose = "\n".join(outside)
    prose = re.sub(r"`[^`]*`", "", prose)  # inline code is code too
    hits = prose.count(";")
    if hits:
        return False, f"{hits} prose semicolon(s) in the deliverable"
    return True, f"0 prose semicolons in {len(prose.split())} words"


EVALS = {
    "recall-preflight": eval_recall_preflight,
    "reflect-noop": eval_reflect_noop,
    "reflect-capture": eval_reflect_capture,
    "writing-semicolons": eval_writing_semicolons,
}


def main():
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
    ok, evidence = EVALS[name](records, pathlib.Path(workspace), pathlib.Path(brain))
    print(f"{name} {'PASS' if ok else 'FAIL'} {evidence}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
