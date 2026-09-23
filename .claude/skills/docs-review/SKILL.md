---
name: docs-review
description: Review a user-facing doc the way a reader would. Two fresh agents, one trying to do real tasks from the page alone, one cutting words. Usage /docs-review <path> [task; task; ...]
disable-model-invocation: true
---

# Docs review

`$ARGUMENTS` is a doc path, optionally followed by a semicolon-separated list
of reader tasks. If no tasks are given, derive three from the doc's headings
before you start and state them in the report.

Run both agents in parallel, `subagent_type: general-purpose`,
`model: sonnet`. Neither gets this conversation's context. That is the point:
they read the page cold, like a user.

## Agent 1: newcomer test

Prompt, with the path and tasks filled in:

> Read `<path>` and nothing else. Do not open source code or other docs unless
> the page links you there, and if it does, note that you had to leave.
>
> For each task below, describe in two or three lines the steps you would take
> using only what the page told you. Then say honestly which of these happened:
> you found it within the first screen; you had to hunt; you had to guess; you
> could not do it from this page. Quote the sentence that finally answered
> you, or say none did.
>
> Tasks:
> <tasks, one per line>
>
> Then list, as one line each, any paragraph you skipped because it wasn't
> helping you do anything, and any sentence you had to read twice.
>
> Report under 40 lines. No praise, no suggestions for new sections.

## Agent 2: cut pass

Prompt:

> Read `<path>`. Produce a version at most three quarters of the length that
> loses no command, setting, value, or instruction. You may cut explanation,
> repetition, history, hedging, and anything a reader could not act on. Keep
> the headings unless a section empties out, in which case remove it and say
> so. Also apply the `unslop` skill's checklist while you cut.
>
> Write the result to `.scratch/<basename>.cut.md`. Then report, in under 20
> lines: word count before and after, each section you shortened by more than
> half with a one-line reason, and any sentence you were unsure was safe to
> cut. Do not edit the original.

## Report back

Relay both results in plain prose. Lead with the tasks the newcomer could not
do or had to guess at. Then the paragraphs both agents flagged, since those
are the surest cuts. Point at the `.cut.md` file for the trimmed draft and
leave the decision to Stu. Do not apply changes yourself.
