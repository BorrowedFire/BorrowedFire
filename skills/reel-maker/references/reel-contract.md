# Reel Contract

Use this reference when the current repo holds the product's marketing and social content.

## Required Local Context

Read these before drafting copy, using the repo's own names for them:

- the marketing-skills, social-content-production, and copy-review workflow docs
- the product page, such as `products/<product>.md`
- the audience-voice or player-voice guide for the product, when one exists
- relevant `DESIGN.md` files
- brand and copy-voice guardrails, such as files under `knowledge/`
- existing reference packages for the product when the user names a precedent

## Copy Rules

- Write like a real user or founder update, not a marketing department.
- Say what changed, why the audience should care, and what action or feedback is needed.
- Prefer concrete user problems over generic app availability copy.
- Use the audience's own words for the feature where they are accurate.
- Do not imply paid or gated content is free.
- Do not use generic phrases like "ultimate companion", "download now", "game-changing", or "do not miss out".

## Artifact Rules

Use a package directory with:

- `data.json`
- `script.md`
- `copy-review.md`
- `caption.txt`
- `source-notes.md`
- `reel.mp4`
- `preview/`

Keep the package where the repo already stores the product's posts, such as
`<product>/posts/<date>/<slug>/`. Follow a more specific repo convention when one exists.

## Verification

Run:

- the repo's content and repo validation scripts
- the repo's render command for the composition
- `ffprobe` on the finished MP4
- `ffmpeg` preview-frame extraction

Inspect the preview frames before presenting the final result.
