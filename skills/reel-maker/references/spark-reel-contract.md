# Spark Reel Contract

Use this reference only when the current repo is Spark or a closely related Borrowed Fire social-content checkout.

## Required Local Context

Read these before drafting copy:

- `docs/workflows/marketing-skills.md`
- `docs/workflows/social-content-production.md`
- `docs/workflows/copy-review.md`
- `products/<product>.md`
- relevant `DESIGN.md` files
- relevant files under `knowledge/`

For NextCatch reels, also read:

- `docs/nextcatch-player-voice.md`
- `nextcatch/DESIGN.md`
- `knowledge/brands/borrowedfire/copy-voice-guardrails.md`
- existing reference packages under `nextcatch/posts/` or `nextcatch/posted/` when the user names a precedent

## Copy Rules

- Write like a real player or founder update, not a marketing department.
- Say what changed, why the audience should care, and what action or feedback is needed.
- Prefer concrete player problems over generic app availability copy.
- For NextCatch raid conversion, use lobby, queue, room, host, invite, and pass-burn language where accurate.
- Do not imply paid or gated NextCatch content is free.
- Do not use generic phrases like "ultimate companion", "download now", "built for trainers", "game-changing", or "do not miss out".

## Artifact Rules

Use a package directory with:

- `data.json`
- `script.md`
- `copy-review.md`
- `caption.txt`
- `source-notes.md`
- `reel.mp4`
- `preview/`

If the package is for NextCatch, keep it under `nextcatch/posts/<date>/<slug>/` unless the repo already has a more specific convention.

## Verification

Run:

- `python3 scripts/validate_social_content.py`
- `python3 scripts/validate_spark.py`
- the HyperFrames render for the composition (see the `hyperframes` and `hyperframes-cli` skills); Spark's video path lives in `hyperframes/`
- `ffprobe` on the finished MP4
- `ffmpeg` preview-frame extraction

Inspect the preview frames before presenting the final result.
