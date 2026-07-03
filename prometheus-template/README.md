# Prometheus — private brain repo template

This is the template for **Prometheus**, your private brain: a git-authoritative markdown memory
shared by every agent harness and machine in your fleet. (Prometheus is the one who borrowed the
fire — the brain deliberately does not share the Borrowed Fire brand name.) The schema that all
skills follow lives in the `remember` skill (`skills/remember/references/brain-schema.md` in the
Borrowed Fire repo) — this template just gives you a conforming starting tree.

## Create your brain (one time)

```sh
# 1. Create a PRIVATE repo (GitHub CLI shown; any private remote works)
gh repo create <you>/prometheus --private

# 2. Instantiate from this template
cp -R prometheus-template ~/prometheus
cd ~/prometheus
git init -b main
git add -A && git commit -m "brain: init from template"
git remote add origin git@github.com:<you>/prometheus.git
git push -u origin main
```

Then on **every fleet machine**: `git clone git@github.com:<you>/prometheus.git ~/prometheus` and
run the Borrowed Fire `install.sh` there (it writes the pointer file the skills use to find the
brain).

## What's in the tree

- `.gitattributes` — union-merge rules that make concurrent multi-machine appends safe. **Do not
  remove.**
- `INDEX.md` — generated map of contents; the `digest` skill owns it.
- `config/fleet.md` — your instance configuration (execution tiers, endpoints, caps). Private by
  design; skills read it, the public repo never contains it.
- `projects/_template.md` — copy this to register a repo/app/idea in the registry.
- `inbox/ journal/ people/ companies/ projects/ meetings/ decisions/ lessons/ notes/` — typed page
  directories per the schema.
- `.locks/` — cooperative locks (`digest` uses this; leave it alone).

## Rules that keep it healthy

- This repo stays **private**. No secrets in it either way — reference where credentials live,
  never their values.
- Never force-push, never rewrite history — history is the audit log.
- Agents append; only `digest` restructures. Humans are welcome to edit anything — it's your
  brain; run `digest` afterward to re-index.
