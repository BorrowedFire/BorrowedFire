---
name: reel-maker
description: Plan, script, produce, render, and validate short-form marketing videos and Instagram Reels from product context, screenshots, copy gates, and repo-native video tooling. Use when the user asks to make a reel, short-form video, launch video, app announcement video, product demo video, Instagram video post, video script plus render, or to improve weak video copy before production.
---

# Reel Maker

## Overview

Use this skill to produce a reviewable short-form video package end to end. It orchestrates product-marketing context, customer language, launch framing, social video structure, copywriting, copy-editing, and video rendering without replacing repo-owned source-of-truth rules.

## Workflow

1. **Run the dependency check**
   - Run `python3 scripts/check_skill_updates.py --repo <repo-root>` from this skill directory when the current task depends on Corey Haines marketing skills or Spark's absorbed marketing registry.
   - Treat update findings as report-only. Do not auto-update upstream skills or overwrite local Spark policy.

2. **Load product and channel truth**
   - Read the product, brand, channel, and copy-review files for the current repo before writing.
   - In Spark, start with `docs/workflows/marketing-skills.md`, `docs/workflows/social-content-production.md`, `docs/workflows/copy-review.md`, the relevant `products/*.md`, and brand or surface guardrails under `knowledge/`.
   - For NextCatch, also read `docs/nextcatch-player-voice.md`, `nextcatch/DESIGN.md`, and `knowledge/brands/borrowedfire/copy-voice-guardrails.md`.

3. **Gather real assets and claim evidence**
   - Use real screenshots, app assets, backend data, release state, or existing packages when the copy depends on real product behavior.
   - Record asset provenance in `source-notes.md`: origin path or URL, capture date if known, and whether the asset was copied, generated, or rendered.
   - If a claim cannot be verified, weaken it or mark it as an explicit assumption before rendering.

4. **Build the script before the render**
   - Create or update `script.md` with: hook, body beats, final CTA, caption direction, required visuals, and copy sources.
   - Use the dependent skills in this order as reasoning lenses:
     `product-marketing` -> `customer-research` -> `launch` -> `social` -> `copywriting` -> `copy-editing` -> `video`.
   - Those upstream skills are not installed on every harness — Spark deliberately absorbs them
     rather than installing them. When a lens skill is missing locally, read its absorbed entry in
     Spark's `config/marketing-skills-index.json` and the routing in
     `config/marketing-capabilities.json` instead; the dependency check reports which are present.
   - Use `marketing-psychology` only to sharpen a selected angle. Use `ad-creative` only for paid or variant-testing work.

5. **Run the copy gate**
   - Create or update `copy-review.md` before rendering.
   - Check clarity, voice, "so what", proof, specificity, emotional pull, and conversion path.
   - Resolve all Critical and Warning issues before rendering unless the user explicitly accepts the risk.
   - For NextCatch, reject generic app-boilerplate copy and prefer practical Pokemon GO player language.

6. **Render through the repo-native pipeline**
   - Prefer the repo's existing renderer, templates, scripts, and artifact layout.
   - In Spark, render through HyperFrames — the `hyperframes/` module and the `hyperframes` skill family — which is the repo's video path. The retired Remotion `reels/` pipeline is gone; do not reach for it.
   - Do not schedule or publish from this skill. Scheduling remains behind the repo's explicit approval gates.

7. **Verify the finished video**
   - Run the repo's validation command when available.
   - Run `ffprobe` or equivalent to confirm dimensions, frame rate, duration, and codec.
   - Extract preview frames from the beginning, middle, and end; inspect them for blank frames, overlap, unreadable text, wrong assets, or bad crops.
   - Return the final video path, caption path, script path, source notes, preview frames, validations run, and dependency-check result.

## Package Contract

A finished reel package should include:

- `data.json` or equivalent render props
- `script.md`
- `copy-review.md`
- `caption.txt`
- `source-notes.md`
- `reel.mp4`
- `preview/` frames

If the local repo already has a stricter package shape, follow the local repo.

## References

- `references/dependencies.json`: skill dependency manifest and upstream mapping.
- `references/spark-reel-contract.md`: Spark-specific execution contract.
