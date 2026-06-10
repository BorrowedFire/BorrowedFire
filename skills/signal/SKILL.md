---
name: signal
description: Front door for the Corey Haines Marketing Skills trove when drafting, tuning, reviewing, or strategy-checking any potential user-facing copy or marketing message. Use when the user says "/signal", "signal", "run signal", "signal this copy", "run Marketing Skills", "Corey Haines", or asks to write, rewrite, review, tune, sharpen, or create copy for an app, website, landing page, App Store listing, Google Play listing, promotional text, social post, reel/video script, email, launch announcement, onboarding flow, paywall, pricing surface, ad, SEO page, notification, in-product microcopy, lifecycle message, sales asset, or other customer-facing text.
---

# Signal

## Purpose

Use this as the front door for the Corey Haines Marketing Skills installed under `~/.codex/skills`. First infer the surface, audience, stage, and job of the message, then load and follow the most relevant specialist marketing skill instead of guessing from generic copy instincts.

## Workflow

1. **Classify the surface and marketing problem**
   - Identify where the copy will appear: app store, website, in-app, paywall, onboarding, social, email, ad, launch, SEO, support, notification, or other.
   - Identify the copy job: acquire, activate, explain, reassure, convert, retain, announce, recover, or support.
   - Identify whether the request is really copywriting, positioning, research, conversion strategy, lifecycle, distribution, pricing, sales enablement, measurement, or experimentation.
   - If the surface or job changes the answer materially and cannot be inferred, ask one concise clarifying question. Otherwise proceed with stated assumptions.

2. **Gather local context first**
   - If in a repo, read the nearest `AGENTS.md` or `CLAUDE.md`, then likely product context files such as `README.md`, `CONTEXT.md`, `DESIGN.md`, `docs/strategy/*.md`, `docs/product/*.md`, app metadata, current screenshots, or the file being edited.
   - If `.agents/product-marketing.md`, `.claude/product-marketing.md`, or `product-marketing-context.md` exists, read it before writing.
   - If no product-marketing context exists and the request needs foundational positioning, use `product-marketing` before drafting. For small one-off edits, infer from available repo/user context and state assumptions.

3. **Route to specialist skill(s)**
   - Read `references/corey-haines-marketing-skills.md` for the installed Corey Haines catalog.
   - Read `references/surface-routing.md` and select the smallest useful set of specialist skills.
   - Open each selected skill's `SKILL.md` from `~/.codex/skills/<skill-name>/SKILL.md` and follow the relevant workflow.
   - Default sequence for most copy work: `product-marketing` context if needed -> surface specialist -> `copy-editing` final pass.
   - For ambiguous "run Marketing Skills" requests, prefer a light research/positioning/context pass before producing final wording.
   - Use `marketing-psychology` only to sharpen the chosen angle or diagnose why copy is not landing; do not let it replace concrete audience, channel, and product context.

4. **Tune for the surface**
   - Respect platform limits, truncation behavior, CTA conventions, and what the surface is indexed for.
   - Preserve product truth. Do not overpromise availability, pricing, claims, rankings, AI behavior, privacy, safety, or results.
   - Match the user's stated strategic correction immediately. If the user says the angle is wrong, revise the underlying promise rather than polishing the same angle.

5. **Deliver paste-ready copy**
   - Provide the recommended version first.
   - Include character counts when the surface has limits.
   - Add 1-3 variants only when useful, labeling the strategic difference.
   - Briefly explain why the recommendation fits the surface and context.

## Quality Gates

- **Context gate:** Can the copy be traced to product/audience/context evidence?
- **Surface gate:** Does it fit the channel's limits, reading mode, and conversion job?
- **Promise gate:** Is the claim true now, not just aspirational?
- **Specificity gate:** Does it avoid generic "AI/productivity/app" language when the product has sharper language?
- **Customer-language gate:** Does it sound like the target user, not internal planning language?
- **Final edit gate:** Remove vagueness, filler, inflated claims, and awkward phrasing.
- **Trove gate:** Did you consider the relevant Corey Haines specialist skill rather than defaulting to generic copy editing?

## Output Shape

For narrow copy edits, use:

```text
Recommended:
> [copy]

[character count if relevant]

Why:
- [surface/context reason]
- [positioning reason]
```

For broader work, add:

```text
Assumptions:
- [surface, audience, goal]

Variants:
1. [variant] - [angle]
2. [variant] - [angle]
3. [variant] - [angle]
```
