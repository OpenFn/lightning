---
name: create-plan
description: Turn a feature request, issue file, or Linear ticket into a phased implementation plan that /implement-plan executes. The lead session steers and decides, cheap agents gather facts, and an independent reviewer checks the draft against the code before it is final. Usage /create-plan [issue path | Linear ID | one-line brief]
disable-model-invocation: false
---

# Create plan

You are the lead. You hold the design, make the recommendations, and talk to
the user. Workers read the codebase and return conclusions; you read only what
the user names and what workers hand back. Protect this context window.

## Roles

| Job | Who | Model |
|---|---|---|
| Steer, decide, write the plan, talk to the user | this session | whatever the session is running |
| Find files; find `.context/` docs | `codebase-locator`, `context-locator` | haiku (pinned in agent) |
| Explain how a component works; find a pattern to copy | `codebase-analyzer`, `codebase-pattern-finder` | sonnet (pinned) |
| Read `.context/` history | `context-analyzer` | sonnet (pinned) |
| Library docs, prior art | `web-search-researcher`, only when the user asks | sonnet (pinned) |
| Generate alternatives when the approach is open | `idea-machine` | pass `model: sonnet` |
| Review the draft against the code | `general-purpose` | pass `model: opus` |

`/model` changes this session only. An agent whose file does not pin a model
gets an explicit `model:` on every dispatch.

## Process

### 1. Load the brief

- `$ARGUMENTS` is a path: read it in full. A Linear ID (`ABC-123`): fetch the
  issue and its comments. Empty: ask in one line what we are planning.
- Read every file the user names yourself, in full.
- In one message, dispatch `codebase-locator` and `context-locator` with the
  brief. Then send `codebase-analyzer` at each component the change touches;
  one agent per area, in parallel. Ask each for conclusions with `file:line`
  citations, not file dumps.
- `.context/` is large and rarely pruned. Send `context-analyzer` only at the
  hits whose date is close to the code they describe, or that record a decision
  rather than an implementation. Treat anything it marks superseded as history:
  it explains why, it does not describe what is there now. Never copy an older
  plan's approach without re-verifying against the code.

### 2. Resolve open questions

- **Facts are your job.** Never ask the user something an agent can look up.
- Present every open **decision** at once, numbered, each with your
  recommended answer and a one-line why. Ask again when new decisions appear.
  Stop when there are none left.
- When the user states a fact about the code, verify it with an agent before you
  build on it. Say so if it does not hold.
- When the approach is genuinely open, dispatch `idea-machine` and bring back
  two or three options with a recommendation. Do not present a survey.

### 3. Structure sign-off

Show, in plain prose: the goal; what we are not doing; the **seams** where
tests will go (the highest existing seam that proves the behaviour, per
`/tdd`); the phases as one-liners, each naming its implementation agent. One
approval gate. Write no detail before it.

### 4. Write the plan

- Path: `.context/shared/plans/YYYY-MM-DD[-XXXX]-slug.md`, `XXXX` the ticket
  number when there is one. Template: [plan-template.md](plan-template.md).
- Phases are **tracer bullets**: each lands a thin working slice through every
  layer it touches, with its tests, sized to one fresh context window.
  Exception: a wide mechanical refactor goes expand, migrate in batches,
  contract, so CI stays green throughout.
- Each phase names an **Implementation Agent** from CLAUDE.md §Available
  Agents and the model it should run on. `/implement-plan` starts a fresh
  agent per phase.
- Automated success criteria are commands that exist in this repo. Manual
  criteria are listed separately.
- The CHANGELOG review is a checklist item in the last phase, not a footnote.
- No open questions survive into the file.

### 5. Independent review

Dispatch one fresh `general-purpose` agent, `model: opus`, with the plan path
and this checklist: every cited `file:line` exists and says what the plan
claims; each phase depends only on earlier phases; every automated criterion
is a runnable command in this repo; nothing in "What we're not doing" is
needed by a phase; each phase fits one context window. Findings only, no
edits. Fix what holds. Where you disagree, keep your version and say why.

### 6. Hand back

Give the user the path, the phase list, and any reviewer finding you rejected.
Iterate until the user is happy. If the brief came from Linear, offer to attach
the plan to the issue; after any Linear write, re-fetch to confirm it landed. End
with the next step: `/implement-plan <path>`.

## Scaling up

When the change spans many areas, offer a Workflow and run it only if the user
opts in: locate (haiku) → analyse each area in parallel (sonnet) → you
synthesise and write → review (opus). Load `workflow-authoring` before
writing the script.

## Rules

- You grep once at most; the second search is a locator's job.
- Recommend, do not survey. A choice you can default, you default and say so.
- Plain language to the user. The plan path is the only file path in your prose.
