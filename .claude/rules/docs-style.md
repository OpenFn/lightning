---
paths:
  - "*.md"
  - "tooling/**/README.md"
---

# User-facing docs

The root `*.md` files ship in exdoc. The reader is a person with a job to do:
an operator deploying Lightning, or a developer running it locally. They are
not here to learn how the code is organised. Write for the job.

## What goes in

- Lead each section with the action or setting, then at most two sentences on
  why. If the reader can act after the first line, the section is done.
- Order sections by how often someone needs them, common first.
- Use the reader's words for things. "Local adaptors", not "the Local
  strategy". The module name can appear once, as a link, for people who want
  the code.
- Real commands and real values in fenced blocks. A worked example beats a
  description of one.
- Troubleshooting belongs in the guide for the thing that broke, as a short
  "if X, check Y" list.

## What stays out

- No Overview, Architecture, How it works, History, Background, or Key
  concepts sections. Internals live in moduledocs. Link to them.
- No paragraph that could sit unchanged in another project's docs.
- No commit SHAs, PR numbers, line references, or "as of" dates in the prose.
  Git has those.
- No repeating a fact that lives in another doc. Link once and stop.

## Environment variables

`DEPLOYMENT.md`'s table is the one place every env var gets its one-line
meaning. A guide uses variables in context, in examples, and may explain a
setting at length, but does not build a second table of them. When you add or
rename a variable, the `DEPLOYMENT.md` row and `.env.example` change in the
same commit.

## Style

- Sentence-case headings. Plain words. Short sentences.
- No em dashes. No bold for emphasis mid-sentence.
- British English.
- Before finishing, run the `unslop` skill over what you wrote, then reread it
  as a newcomer: could you do the task from this page alone, in a minute, with
  nothing left over you didn't need?

`WORKERS.md`'s History section is the pattern to avoid: it explains how the
old runtime worked, which no reader of that page needs.
