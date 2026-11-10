---
name: reel-maker
description: Produce short marketing videos and reels through the selected project pipeline, from concept to rendered and visually checked output.
---

# Reel Maker

## Overview

Use this skill to produce a reviewable short-form video package end to end. It orchestrates product-marketing context, customer language, launch framing, social video structure, copywriting, copy-editing, and video rendering without replacing repo-owned source-of-truth rules.

## Workflow

1. **Run the dependency check**
   - Run `python3 scripts/check_skill_updates.py --repo <repo-root>` from this skill directory when the current task depends on Corey Haines marketing skills or the repo's absorbed marketing registry.
   - Treat update findings as report-only. Do not auto-update upstream skills or overwrite the repo's local policy.

2. **Load product and channel truth**
   - Read the product, brand, channel, and copy-review files for the current repo before writing.
   - Include the repo's marketing and social-content workflow docs, the product page, any audience-voice guide, the relevant `DESIGN.md`, and brand or surface guardrails. [The reel contract](references/reel-contract.md) lists what to look for.

3. **Gather real assets and claim evidence**
   - Use real screenshots, app assets, backend data, release state, or existing packages when the copy depends on real product behavior.
   - Record asset provenance in `source-notes.md`: origin path or URL, capture date if known, and whether the asset was copied, generated, or rendered.
   - If a claim cannot be verified, weaken it or mark it as an explicit assumption before rendering.

4. **Build the script before the render**
   - Create or update `script.md` with: hook, body beats, final CTA, caption direction, required visuals, and copy sources.
   - Use the dependent skills in this order as reasoning lenses:
     `product-marketing` -> `customer-research` -> `launch` -> `social` -> `copywriting` -> `copy-editing` -> `video`.
   - Those upstream skills are not installed on every harness. A marketing repo may absorb them
     rather than install them. When a lens skill is missing locally, read its absorbed entry in
     the repo's `config/marketing-skills-index.json` and the routing in
     `config/marketing-capabilities.json` instead; the dependency check reports which are present.
   - Use `marketing-psychology` only to sharpen a selected angle. Use `ad-creative` only for paid or variant-testing work.

5. **Run the copy gate**
   - Create or update `copy-review.md` before rendering.
   - Check clarity, voice, "so what", proof, specificity, emotional pull, and conversion path.
   - Resolve all Critical and Warning issues before rendering unless the user explicitly accepts the risk.
   - Reject generic app-boilerplate copy. Prefer the practical language the product's audience already uses.

6. **Render through the repo-native pipeline**
   - Prefer the repo's existing renderer, templates, scripts, and artifact layout.
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
- [reel contract](references/reel-contract.md): local context, copy rules, package layout, and verification for a marketing repo.
