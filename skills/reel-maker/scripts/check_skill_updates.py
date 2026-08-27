#!/usr/bin/env python3
"""Report dependency and upstream freshness for the reel-maker skill.

The script is intentionally report-only. It never installs, updates, or rewrites
skills because downstream repos may carry local policy overlays.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
def _default_skill_root() -> Path:
    """First installed agent skills directory. This skill ships to every
    harness, so the default must not assume Codex."""
    candidates = [
        Path(os.environ["CODEX_HOME"]) / "skills" if os.environ.get("CODEX_HOME") else None,
        Path.home() / ".codex" / "skills",
        Path.home() / ".claude" / "skills",
    ]
    for candidate in candidates:
        if candidate and candidate.is_dir():
            return candidate
    return Path.home() / ".claude" / "skills"


DEFAULT_SKILL_ROOT = _default_skill_root()
MANIFEST = ROOT / "references" / "dependencies.json"


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return data


def _frontmatter(path: Path) -> dict[str, str | None]:
    if not path.exists():
        return {"name": None, "description": None, "version": None}

    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not match:
        return {"name": None, "description": None, "version": None}

    raw = match.group(1)
    name = _match_scalar(raw, "name")
    description = _match_scalar(raw, "description")
    version = _match_scalar(raw, "version")
    return {"name": name, "description": description, "version": version}


def _match_scalar(raw: str, key: str) -> str | None:
    match = re.search(rf"(?m)^\s*{re.escape(key)}:\s*(.+?)\s*$", raw)
    if not match:
        return None
    value = match.group(1).strip()
    if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
        value = value[1:-1]
    return value


def _load_registry(repo: Path | None) -> tuple[dict[str, Any] | None, Path | None]:
    if repo is None:
        return None, None
    registry_path = repo / "config" / "marketing-skills-index.json"
    if not registry_path.exists():
        return None, registry_path
    return _load_json(registry_path), registry_path


def _registry_by_id(registry: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    if not registry:
        return {}
    skills = registry.get("skills", [])
    if not isinstance(skills, list):
        return {}
    return {item.get("id"): item for item in skills if isinstance(item, dict) and item.get("id")}


def _latest_upstream_commit(repo_slug: str, path: str, timeout: int) -> dict[str, str | None]:
    query = urllib.parse.urlencode({"path": path, "per_page": "1"})
    url = f"https://api.github.com/repos/{repo_slug}/commits?{query}"
    request = urllib.request.Request(url, headers={"User-Agent": "codex-reel-maker"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not payload:
        return {"sha": None, "date": None, "url": url}
    commit = payload[0]
    return {
        "sha": str(commit.get("sha", ""))[:12] or None,
        "date": commit.get("commit", {}).get("committer", {}).get("date"),
        "url": commit.get("html_url") or url,
    }


def _parse_date(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    candidate = value.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(candidate)
    except ValueError:
        try:
            parsed = dt.datetime.fromisoformat(f"{value}T00:00:00+00:00")
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


def _drift_status(registry_reviewed: str | None, commit_date: str | None) -> str:
    reviewed = _parse_date(registry_reviewed)
    latest = _parse_date(commit_date)
    if reviewed is None or latest is None:
        return "unknown"
    if latest.date() > reviewed.date():
        return "upstream-changed-since-review"
    return "current-against-registry-review"


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    manifest = _load_json(args.manifest)
    repo = Path(args.repo).resolve() if args.repo else None
    skill_root = Path(args.skill_root).expanduser().resolve()
    registry, registry_path = _load_registry(repo)
    indexed = _registry_by_id(registry)
    source = registry.get("source", {}) if registry else {}
    upstream = manifest.get("upstream", {})
    upstream_repo = upstream.get("repository", "coreyhaines31/marketingskills")

    entries: list[dict[str, Any]] = []
    for dep in manifest.get("dependencies", []):
        local_skill = dep["local_skill"]
        upstream_skill = dep["upstream_skill"]
        skill_md = skill_root / local_skill / "SKILL.md"
        local_meta = _frontmatter(skill_md)
        registry_entry = indexed.get(upstream_skill, {})
        source_path = (
            registry_entry.get("source_path")
            or dep.get("upstream_source_path")
            or f"skills/{upstream_skill}/SKILL.md"
        )

        upstream_commit: dict[str, str | None] | None = None
        upstream_error = None
        if not args.no_network:
            try:
                upstream_commit = _latest_upstream_commit(upstream_repo, source_path, args.timeout)
            except Exception as exc:  # noqa: BLE001 - report-only script must fail soft.
                upstream_error = f"{type(exc).__name__}: {exc}"

        entries.append(
            {
                "role": dep.get("role"),
                "required": bool(dep.get("required", False)),
                "local_skill": local_skill,
                "local_path": str(skill_md),
                "local_installed": skill_md.exists(),
                "local_version": local_meta.get("version"),
                "upstream_skill": upstream_skill,
                "upstream_source_path": source_path,
                "registry_version": registry_entry.get("upstream_version"),
                "registry_last_reviewed": source.get("last_reviewed"),
                "upstream_latest": upstream_commit,
                "upstream_error": upstream_error,
                "status": _drift_status(
                    source.get("last_reviewed"),
                    upstream_commit.get("date") if upstream_commit else None,
                )
                if not args.no_network and upstream_error is None
                else "not-checked",
            }
        )

    return {
        "skill": manifest.get("skill_name", "reel-maker"),
        "policy": upstream.get("policy"),
        "skill_root": str(skill_root),
        "repo": str(repo) if repo else None,
        "registry_path": str(registry_path) if registry_path else None,
        "registry_loaded": registry is not None,
        "registry_source_last_reviewed": source.get("last_reviewed"),
        "dependencies": entries,
    }


def print_markdown(report: dict[str, Any]) -> None:
    print(f"# {report['skill']} dependency check")
    print()
    print(f"- policy: {report.get('policy')}")
    print(f"- skill root: {report['skill_root']}")
    print(f"- registry: {report.get('registry_path') or 'not found'}")
    print(f"- registry loaded: {report['registry_loaded']}")
    print(f"- registry last reviewed: {report.get('registry_source_last_reviewed') or 'unknown'}")
    print()
    for dep in report["dependencies"]:
        marker = "required" if dep["required"] else "optional"
        installed = "installed" if dep["local_installed"] else "missing"
        print(f"## {dep['local_skill']} ({marker})")
        print(f"- role: {dep['role']}")
        print(f"- local: {installed}; version: {dep.get('local_version') or 'unknown'}")
        print(
            "- upstream: "
            f"{dep['upstream_skill']} via {dep['upstream_source_path']}; "
            f"registry version: {dep.get('registry_version') or 'unknown'}"
        )
        if dep.get("upstream_latest"):
            latest = dep["upstream_latest"]
            print(f"- latest upstream commit: {latest.get('date') or 'unknown'} {latest.get('sha') or ''}")
        if dep.get("upstream_error"):
            print(f"- upstream check: {dep['upstream_error']}")
        print(f"- status: {dep['status']}")
        print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.getcwd(), help="Repository root to inspect for the Spark marketing registry.")
    parser.add_argument("--skill-root", default=str(DEFAULT_SKILL_ROOT), help="Directory containing installed agent skills.")
    parser.add_argument("--manifest", type=Path, default=MANIFEST, help="Dependency manifest path.")
    parser.add_argument("--no-network", action="store_true", help="Skip GitHub upstream freshness checks.")
    parser.add_argument("--json", action="store_true", help="Print JSON instead of Markdown.")
    parser.add_argument("--timeout", type=int, default=10, help="Network timeout in seconds.")
    args = parser.parse_args()

    report = build_report(args)
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_markdown(report)

    missing_required = [
        dep["local_skill"]
        for dep in report["dependencies"]
        if dep["required"] and not dep["local_installed"]
    ]
    if missing_required:
        print(f"Missing required local skills: {', '.join(missing_required)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
