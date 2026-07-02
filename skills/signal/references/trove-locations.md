# Locating the Corey Haines Marketing Skills trove

The trove is a separately installed set of marketing skills. Its location depends on the harness
running this skill. Search these roots in order and use the first that contains marketing skill
directories (each has a `SKILL.md`):

1. `~/.codex/skills/`
2. `~/.claude/skills/`
3. `~/.qwen/skills/`
4. The current agent workspace's `skills/` directory (OpenClaw-style harnesses).

Open a selected skill as `<root>/<skill-name>/SKILL.md`.

**If the trove is absent** (no root contains the catalog's skills): say so, then proceed using
`signal`'s own quality gates and general marketing judgment — do not fabricate a specialist
workflow, and do not block the user's copy request on a missing install. If only *some* listed
skills exist, prefer the nearest installed alternative and note the substitution.

**Catalog drift:** the catalog in `corey-haines-marketing-skills.md` is a snapshot. When it
disagrees with what is actually on disk, trust the disk.
