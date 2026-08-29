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


WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}


def eval_recall_preflight(records, workspace, brain):
    """The doctrine says: consult the brain's lessons before substantive repo work.
    Pass = some read of the brain's lessons/ happens before the first file write."""
    calls = tool_calls(records)
    first_write = next((i for i, (n, _) in enumerate(calls) if n in WRITE_TOOLS), len(calls))
    for i, (name, args) in enumerate(calls[:first_write]):
        if mentions(args, "lessons"):
            return True, f"{name} touched lessons/ at call {i + 1}, before the first write at {first_write + 1}"
    return False, f"{len(calls)} calls, first write at {first_write + 1}, no lessons/ read before it"


def eval_reflect_noop(records, workspace, brain):
    """A trivial task must not manufacture memory. Pass = no new brain page."""
    pages = sorted(p.name for p in (brain / "lessons").glob("*.md") if p.name != "_template.md")
    pages += sorted(p.name for p in (brain / "decisions").glob("*.md"))
    seeded = {"seeded-lesson.md"}
    created = [p for p in pages if p not in seeded]
    if created:
        return False, f"created {len(created)} page(s) for a trivial task: {', '.join(created)}"
    return True, "no brain pages created"


def eval_reflect_capture(records, workspace, brain):
    """A task that establishes a durable gotcha must leave one lesson carrying a
    prevention classification. Pass = a new lessons/ page with a Prevention line."""
    fresh = [p for p in (brain / "lessons").glob("*.md")
             if p.name not in {"_template.md", "seeded-lesson.md"}]
    if not fresh:
        return False, "no new lessons/ page"
    with_prevention = [p for p in fresh
                       if re.search(r"^Prevention:", p.read_text(), re.M)]
    if not with_prevention:
        return False, f"{len(fresh)} new page(s), none carrying a Prevention line"
    return True, f"{with_prevention[0].name} carries a Prevention line"


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
