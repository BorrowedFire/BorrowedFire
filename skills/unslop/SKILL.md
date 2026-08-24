---
name: unslop
description: Cut AI tells from any prose and put a human voice back in. Owns the slop-pattern catalog every other skill cites. Applies to every reply, doc, commit message, PR body, brief, and marketing draft before it ships; run it without being asked. Use when the user says "/unslop", "unslop this", "cut the AI tells", "this reads like AI", "make this sound human", or "de-slop it". NOT the document standard - mode, structure, and instruction rules live in `technical-writing`, which calls this skill. NOT marketing strategy or positioning (`signal`).
---

# Unslop

Edit text to remove AI patterns and put a human voice back in. This skill owns the pattern
catalog. Other skills cite it by name and do not restate the list.

## Where this applies

Every piece of prose this system produces: chat replies, `SKILL.md` bodies, READMEs, design notes,
commit messages, PR descriptions, Owner Decision Briefs, land-log entries, brain pages, release
notes from `changelog`, and customer copy from `signal`. Run it before the text ships, not after
someone complains.

Do not run it over source code, generated output, test fixtures, or a quoted third-party passage.
Editing a quote makes it a misquote.

## Process

1. Scan for the patterns below.
2. Rewrite. Preserve meaning, match intended tone.
3. Add soul (see next section).
4. Self-audit: "What makes this obviously AI generated?" Fix remaining tells.

## Adding soul

Removing patterns is half the job. Sterile, voiceless writing is just as obvious.

- **Have opinions.** React to facts instead of neutrally listing pros and cons.
- **Vary rhythm.** Short sentences. Then longer ones that take their time. Mix it up.
- **Acknowledge complexity.** "Impressive but also kind of unsettling" beats "impressive."
- **Use "I" when it fits.** First person isn't unprofessional.
- **Let some mess in.** Perfect structure looks machine-made.
- **Be specific.** Not "this is concerning" but "there's something unsettling about agents churning
  away at 3am."

## Established domain terms win

A word in the catalog below is fine when the project already uses it as its ubiquitous language,
defined in a `CONTEXT.md`, a README, or the doctrine. Read the project's own vocabulary before you
flag a word. In Borrowed Fire that set includes `harness` (an agent runtime such as Claude Code or
Codex), `primitive` (the smallest reusable workflow unit), `brain` (Prometheus), `gate`, and
`denylist`.

The catalog targets a metaphor invented for one paragraph. It does not target a term the system
defines once and reuses everywhere. Renaming an established term is the "one name per thing" rule
broken, not obeyed.

## Patterns to detect and fix

### Content

1. **Puffery.** "pivotal moment", "testament to", "evolving landscape", "setting the stage for",
   "indelible mark", "deeply rooted". Cut puffery, state what happened.
2. **Name-dropping.** Listing media outlets without context. Pick one, say what was said.
3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...",
   "fostering...". Delete or expand with real sources.
4. **Promotional language.** "nestled", "vibrant", "breathtaking", "groundbreaking", "renowned",
   "stunning", "must-visit". Use neutral descriptions.
5. **Vague attributions.** "Experts believe", "Industry reports suggest", "Some critics argue". Name
   the source or delete.
6. **Formulaic challenges.** "Despite challenges... continues to thrive." Replace with specific
   facts.

### Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay,
   intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore,
   vibrant. Replace with plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Just say "is" or
   "has".
9. **"Not just X, but Y."** State the point directly instead.
10. **Rule of three.** Forcing ideas into groups of three. Use the natural number.
11. **Synonym cycling.** Protagonist, main character, central figure, hero all in one paragraph.
    Pick one, repeat it.
12. **False ranges.** "from X to Y" where X and Y aren't on a meaningful scale. List topics
    directly.

### Style

13. **Em dash overuse.** An em dash where a period or a comma would do is an AI tell. Replace it
    with a period or a comma. Reaching for parentheses or an en dash instead trades one tell for
    another, so do not. **Scope:** this covers prose you are writing or editing now. Leave an em
    dash that is load-bearing in an existing template, heading format, table cell, quoted string,
    or published title. Rewriting those churns text that did not change and breaks anything that
    matches on the old shape.
14. **Colon overuse.** Colons are fine before a list or example. Not as mid-sentence connectors.
    "If you're coming from traditional automation: instead of registering event handlers, you
    describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own
    without comparison framing. "Describing when the scheduler should fire works best as plain
    English." Same meaning, no crutch punctuation.
15. **Boldface overuse.** Don't bold every proper noun or acronym.
16. **Inline-header lists.** The tell is a bold label and colon that restates the line:
    "**Performance:** Performance improved...". Convert those to prose. A bold lead-in that ends in
    a period, names the item, and is followed by genuinely new detail ("**Schema in TypeScript.**
    Tables live in one file.") is fine, not a tell.
17. **Title case headings.** Use sentence case.
18. **Decorative emojis.** Remove emoji used as decoration in headings and bullets. An emoji that
    carries a defined status meaning in an established template (a warning marker, a pass or fail
    glyph) is not decoration. Leave it.
19. **Curly quotes.** Replace with straight quotes.

### Communication artifacts

20. **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Of course!", "Certainly!",
    "Found the smoking gun!" Remove.
21. **Cutoff disclaimers.** "While specific details are limited..." Find sources or remove.
22. **Sycophantic tone.** "Great question! You're absolutely right!" Respond directly.

### Filler

23. **Filler phrases.** "In order to" becomes "To". "Due to the fact that" becomes "Because". "It is
    important to note that" gets deleted.
24. **Excessive hedging.** "could potentially possibly be argued that it might" becomes "may".
25. **Generic conclusions.** "The future looks bright." State specific plans or facts.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, bedrock,
    scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate
    (for moving code), endgame, north star, flywheel. These read as technical but usually have a
    plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes
    "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the
    mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out".
    "Endgame" becomes "the last phase". Pick the concrete word. Check the established-terms rule
    above before you flag one.

### Plain speech

27. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read",
    "types that follow your schema" name a feeling. The fix names the mechanism or a number:
    "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build".
    Ask what the sentence tells the reader to do or know, then write that. If you can't restate it
    as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear
    unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break
    it in two or drop clauses. One idea per sentence.
29. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor:
    "queries are validated" becomes "the compiler validates queries", "the file is parsed by the
    loader" becomes "the loader parses the file". Passive is fine only when the actor is unknown or
    genuinely doesn't matter.
30. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number.
    "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the
    verb is wrong.
31. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate"
    becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym
    is rarely clearer.

## Composing this skill

Other skills reference `unslop` by name and let it own the catalog. Do not restate the patterns
elsewhere. When a new offender shows up twice, add it here with its replacement rather than writing
the correction again in another skill.

## Related

- `technical-writing` owns document mode, sentence rules, and the review checklist. It calls this
  skill for voice.
- `signal` owns customer-facing copy strategy. Its drafts still pass through this skill.
- `changelog` owns factual release notes. Its sentences still pass through this skill.

## Credit

Adapted from `unslop` in [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan
(poteto), MIT licensed. Borrowed Fire changes: scoped the em dash and emoji rules to their hazard,
added the established-domain-terms carve-out, and added the surfaces and routing sections.
