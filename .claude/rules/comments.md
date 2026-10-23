---
paths:
  - "lib/**/*.ex"
  - "test/**/*.exs"
  - "assets/js/**/*.ts"
  - "assets/js/**/*.tsx"
---

# Comments and docs

A comment promises the reader something the code can't tell them. Every one
that breaks the promise teaches people to skip the next, and agents read every
comment and act on it, so a wrong one misleads twice. Fewer, true, plain.

## When a comment earns its place

Keep a comment only if it carries one of these:

- a constraint the names don't show,
- a decision a competent reader would otherwise reverse ("we deliberately
  don't retry here"),
- a workaround for something outside the codebase,
- a pointer to where a rule comes from.

Anything else goes. If a comment exists because the code is unclear, rename or
extract instead.

```elixir
# Ecto's :utc_datetime type rejects non-zero microseconds, so truncate
# before casting or the changeset fails.
scheduled_at = DateTime.truncate(DateTime.utc_now(), :second)
```

## Which kind of comment

- `@moduledoc`: what the module is for and when to reach for it. One or two
  sentences is usually enough. Use `@moduledoc false` rather than a filler
  sentence.
- `@doc`: how to call the function and what happens. Read in IEx, editor
  hovers and by agents, usually without the source. The first line is one
  sentence that stands alone.
- `#`: why this line is like this, for someone already in the body.

In TypeScript, JSDoc on an export plays the part of `@doc`.

## A `@doc` describes what the caller gets, not the steps inside

Say what the inputs must be, every return shape including error tuples, and
side effects the caller can't see (writes, broadcasts, audit rows). Don't walk
through the body in order: that goes wrong the moment someone reorders it.

```elixir
@doc """
Replaces a credential's body on behalf of `actor`.

Returns `{:error, :unauthorized}` if the actor can't write credentials in the
project, or `{:error, changeset}` if the body is invalid. The audit event is
written in the same transaction.
"""
```

## Explain a rule once, where it's enforced

When several modules rely on the same rule, the explanation lives in the
module that enforces it. The others say nothing, or one line pointing there if
the caller would otherwise look wrong. Don't describe another module's
behaviour in a comment; it goes wrong when that module changes and nothing
flags it.

## Write what will still be true next month

| Goes stale | Lasts |
|---|---|
| Step-by-step account of the body | What the function promises |
| Callers, routes ("used by the API controller") | Constraints on inputs |
| Counts, line numbers, file paths | Why a rule exists |
| "Currently", "for now", "new", "now also" | Error shapes and side effects |
| Ticket, PR and refactor history | Link to the external source of a rule |

Never narrate the change ("added for CON-331", "now also handles service
accounts"). That is the commit message's job. Code reads as if it was always
written that way.

When you change behaviour, re-read the comments in that function and its
`@doc`, and fix anything the change made false in the same commit.

A TODO says what is left and why it isn't done now. "TODO: fix" is not a TODO.

## Plain words

- Full sentences a colleague would say out loud. If a reader would need a
  follow-up question to decode it, rewrite it.
- No coined shorthand: "the state rule", "project-less scope", "raw-actor
  clause". Say the thing it stands for.
- No filler: "simply", "note that", "it's worth noting", "this ensures that".
- Don't weld clauses together with colons and semicolons. Two sentences, or
  one simpler one.
- No spaced em dashes; prefer a full stop.
- `mix format` doesn't wrap comments. Reflow a paragraph after editing it so
  every line but the last runs to 80 columns. In a `@doc` or `@moduledoc`, a
  blank line separates ideas, and three or more parallel items go in a list.

## Tests

- Put the intent in the test name, not a comment above it.
- Comment setup only when the reason isn't visible ("inserted out of order so
  the query has to sort").
- Don't restate an assertion. Do say why when it pins deliberate behaviour a
  reader might "fix" (a refusal that looks like a bug).
