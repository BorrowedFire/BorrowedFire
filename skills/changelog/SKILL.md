---
name: changelog
description: Assemble factual release notes and changelogs from merged history. Invoked by `store-release` (step 8) and `ship`, or explicitly when the user says "/changelog", "changelog", "write the release notes", "what's in this release", "summarize what shipped", or "update the CHANGELOG". Produces user-facing store notes, GitHub Release bodies, and CHANGELOG.md entries from PRs/commits — delegating promotional tone to `signal`. NOT for announcement/launch marketing copy (`signal`) and NOT for creating the release itself (`store-release` / `ship`).
---

# Changelog

Turn merged history into honest, audience-appropriate release notes. The source of truth is what
actually merged — never write a note for something that didn't land.

## Rules

- **Facts from history:** merged PRs (titles, bodies, linked issues) between the last release
  tag/version and the target ref; commits where PRs are thin. The brain's project page `## Log`
  fills in the why.
- **Audience decides the words:**
  - *Store release notes* (App Store "What's New" / Play notes): user-visible changes only, plain
    language, no internal refactors, within store length limits. If the tone should sell, hand the
    draft to `signal` — facts here, persuasion there.
  - *GitHub Release body*: complete but grouped — Features / Fixes / Internal; full clickable PR
    URLs.
  - *CHANGELOG.md*: follow the file's existing convention (Keep-a-Changelog, plain sections,
    whatever is there). Match, don't reform.
- **Never inflate:** a dependency bump is "updated X", not "improved performance and security".
  A fix for a bug users never saw doesn't lead the store notes.
- **Omissions are lies too:** breaking changes, migrations, permission changes, and known issues
  are named plainly, at the top for developer audiences.
- Attribute nothing to a version until its tag/build exists; drafts for an unreleased train say
  "unreleased".

## Flow

1. Determine the range: last release tag (or store-live version) → target ref. `store-release`
   passes this in; standalone, derive from tags and ask only if genuinely ambiguous.
2. Collect merged PRs/commits in range; classify (feature / fix / internal / breaking); drop
   internal noise for user-facing outputs.
3. Draft each requested output per audience rules; keep every claim traceable to a PR/commit.
4. Hand promotional variants to `signal` when asked.
5. Deliver paste-ready text (with character counts for store surfaces), plus the traceability
   list (change → PR URL) so the owner can spot-check.

## Related

`store-release` (invokes this for step 8) · `ship` (release closeout) · `signal` (promotional
tone) · `remember` (notable releases can be logged to the project page).
