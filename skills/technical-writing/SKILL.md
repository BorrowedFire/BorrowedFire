---
name: technical-writing
description: Write or review engineering prose, including docs, agent instructions, brain pages, PR descriptions, and commit messages. Apply the shared clarity and voice standards.
---

# Technical writing

Write so a tired engineer understands on the first read. Apply the four layers below.
Use [the writing guide](references/writing-guide.md) when you need mode-specific advice,
a worked example, or the detailed review checklist.

## Purpose and structure

Choose the document's primary purpose: teach through a tutorial, guide a task, provide reference,
or explain a decision. Use separate sections when a reader needs more than one mode. Keep a
procedure focused on its task and link supporting explanations where they help.

## Sentences for the reader

Name the actor and use active voice. Prefer familiar words and concrete actions. Put the main
point first. Give each thing one name, including the real symbol, file, flag, or command.
Keep links descriptive and claims tied to evidence. Match the repository's terminology and
formatting conventions.

## Instructions with one meaning

Carry one thought per sentence and one instruction per sentence. Put the condition before the
instruction. Preserve the articles and small words that make the sentence parse one way. Split
long sentences when they carry several ideas; clarity decides the length.

Scope each rule to the failure it prevents. Name the sanctioned exceptions. Do not write a
blanket prohibition that forbids an operation the workflow needs. In agent instructions, state
the authorized scope, required outcomes, and stopping point. Retain exact ordering where it
prevents a real failure.

## Clear syntax

Place "only" beside the words it limits. Make pronouns refer to a clear noun. Avoid long noun
strings, ambiguous lists, idioms, and unexplained jargon. Prefer periods to semicolons or em
dashes. Keep domain terms when the project defines them.

## Final pass

Apply `unslop` once to the completed prose. It owns voice and the slop-pattern catalog. Check that
claims, paths, counts, commands, and links match the actual artifact. Read awkward sentences
aloud and fix them. Keep the reader's meaning and natural rhythm ahead of mechanical compliance.

These rules cover engineering docs, agent instructions, brain pages, PR descriptions, and commit
messages. Customer-facing strategy and product copy use `signal`; factual release notes use
`changelog`. Those workflows still preserve the shared clarity rules.

## Sources and detailed standard

The [writing guide](references/writing-guide.md) retains the Diataxis, Google developer style,
ASD-STE100, and Global English guidance, source notes, examples, and attribution.
