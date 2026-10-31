---
name: reshape-pass
description:
  Review the code a branch adds or changes for design that is working around
  itself, and reshape it: shapes converted back and forth, guards for cases a
  better shape makes impossible, one thing under several names, comments that
  explain a design fact as a workaround. Use before merging a long-lived
  feature branch, or when a nearly-done implementation feels like it was fitted
  around what was there. Not a bug hunt and not a comment pass.
argument-hint:
  '[path or module to scope to] [review notes file] [--fix to apply as ordered
  commits]'
disable-model-invocation: true
---

Review the code the current branch adds or changes, and find where the design
is working around its own shape instead of changing it.

The tell is accommodation. Code written to fit what was already there, rather
than asking whether what was there should still exist. Each accommodation is
small and defensible on its own. Together they mean the branch merges already
needing a refactor.

**Default is propose-only.** Present the findings and wait; touch nothing. With
`--fix` (or `--apply`), apply the changes to the working tree, one commit per
finding in the order given, using the project's commit convention or skill, and
show what changed.

**Never post anything.** This skill edits files in the working tree and nothing
else. No PR comments, no pushes, no public surface. Pass this constraint to
every subagent.

## Three roles

- **Mapper**: a subagent that builds the map of the area and returns a report.
- **You**: read the map and the code it points at, form and order the
  findings, and in `--fix` mode make the changes.
- **Verifier**: a fresh subagent that did not see the findings being formed,
  running the checks under "Verify" against the real code.

The mapper never judges and the verifier never edits. Findings are yours.

## Read the local rules and the plan first

Read the project's CLAUDE.md and anything it points at for module layout,
naming and testing conventions. A project rule beats this skill. Respect any
boundary the project deliberately holds (a facade, a context module, a strategy
behaviour): reshape inside it, and say so explicitly if a finding would move
something across it.

If a plan, spec or ADR exists for the branch, read it before mapping. It says
what the shape was meant to be, and what was deliberately deferred. A finding
that contradicts the plan has to say so. A deferral defers work, not a bug: if
a bug sits on deferred ground, find the fix that doesn't need the deferred
work, and if there isn't one, report the bug as blocking and say why.

## Scope

The area is what you read; the diff is what makes a finding in scope.

- Diff against the merge-base with the default branch, plus staged and unstaged
  changes. On the default branch with no branch diff, use the uncommitted
  changes; if none, ask what to review.
- If a path or module was given, restrict findings to that area, but still read
  its callers and callees so a reshape doesn't break a consumer you never
  opened.
- Pre-existing code is in scope when the branch built on it in a way that
  exposed the problem. "It was there before" is not a defence: nothing on a
  branch is in main yet, and the branch is the cheapest moment to fix it.
- If the user supplied review notes or a list of smells, treat them as seed
  findings. Map around them, and in the report say which the map confirmed,
  which it reframed (the smell was real, the cause was elsewhere), and what it
  found that the notes didn't.

## Map before you judge

Do not start from the diff hunks. Start from the shapes. The mapper returns a
report of at most a few hundred lines, quoting only converters, guards and
cache writes, never whole files:

- Every struct, typespec, Ecto schema or type alias in the area: fields, owner,
  who constructs it, who consumes it.
- The data flow across module boundaries, and every point where one shape is
  converted into another, quoted verbatim.
- Every place that strips `__struct__`, calls `Map.from_struct`, builds one
  struct from another with `struct/2`, or pattern-matches a map and a struct
  for the same logical data.
- Every guard for a nil, empty or missing value, and where that value comes
  from.
- Every cache write: what shape goes in, what a fresh read of the same record
  returns, and what invalidates the key.
- Public functions in the area and which of them anything outside actually
  calls.
- Tests the branch added or changed, and the fixture state each relies on
  (factory defaults especially).

Read the map, then read the code the map points at. Only then form findings.

Write the map to disk (the scratchpad, or the branch's scratch directory if it
has one) and give the path. Findings go in the same file. That file is the
handoff if the work continues in another session.

## Bugs come first

This is not a bug hunt, but mapping shapes finds bugs: a cache that pins a
transient failure, a guard that catches the wrong case, a test that passes for
the wrong reason. A bug is blocking if you would not ship main with it. Report
blocking bugs before any design finding, and in `--fix` mode commit each one
first and separately.

## What to look for

Each of these is a place where a shape should change and code should
disappear. The fix is always upstream of the symptom.

- **Two shapes for one thing at a boundary.** A function that accepts both a
  lean map and a full struct for the same logical record, and normalises them
  with `Map.delete(:__struct__)`, `Map.get/3` defaults, or `struct/2` that
  silently drops fields. Find the caller that feeds two shapes and make it
  feed one. The converter becomes a field copy or disappears.
- **One record under several names.** Three typespecs projecting the same row,
  two modules declaring a type with the same name and different fields. Decide
  what the record is as the rest of the app sees it, name it once, and make the
  other shapes a render step on top.
- **Downstream guards for upstream facts.** A `{:ok, nil}` branch, a
  `when not is_nil` in a consumer, a default for a missing key. Ask what
  produced the nil. If the producer is in the area, make it produce a
  well-formed value (an empty schema, an empty list, an error tuple) and delete
  the guard. A producer that can return nil pushes the same guard into every
  consumer it will ever have.
- **Comments that explain the data instead of the code.** A comment saying
  "X may be nil even when Y, because Z" is a design fact stated as a
  workaround. It marks the spot where the shape should change. Fix the shape,
  then delete the comment.
- **The same normalisation in several places.** Encoding, decoding, trimming,
  defaulting done at three layers for the same field because each layer did
  not trust the one before. Pick the layer that owns the contract, tighten the
  contract in its typespec, and delete the rest.
- **A concept without a home.** The branch introduced a responsibility (a
  cache, a projection, a lifecycle, a permission) and spread it across
  existing modules as parameters, flags and helper functions instead of
  naming it. The fix is bigger than the ticket said. Say so, cost it, and
  propose the module or struct it should become.
- **Dead surface.** A struct declared and never constructed, a public function
  no one outside calls, an option no caller passes. Delete it.
- **A cache that can disagree with its source.** A cached value shaped
  differently from a fresh read of the same record, or a cache key with no
  invalidation path when the source changes. Report it even when fixing it is
  out of scope.

## What to leave alone

Never touch:

- A boundary the project deliberately holds. Reshape inside it.
- Working code the branch did not build on and that no finding depends on.
- A guard at a trust boundary (user input, external API, deserialised data).
  Those defend against the outside world, not against the code's own shape.
- Anything a `# SAFETY:` or "we deliberately do NOT" comment protects.

When unsure whether a reshape is safe, propose it with the doubt stated and let
the user decide. A wrong refactor on a nearly-done branch costs more than the
accommodation it removes.

## Order the findings

Findings depend on each other. A single projection function removes the need
for a converter, which removes a default, which removes a comment. Order the
list so each step shrinks the ones after it, and say which findings a given
step makes unnecessary.

Split the list in two. **Before merge**: anything that changes behaviour,
touches a cache or a producer's contract, or that a later finding depends on.
**Can follow**: renames, type consolidation and deletions with no behaviour
change and nothing depending on them. Say why each item landed where it did.

## Verify before declaring done

The verifier checks, against the real code:

- For every deleted guard: which producer now guarantees the value, and does
  every path into that producer honour it? Trace them.
- For every merged shape: does anything outside the area pattern-match on the
  old shape? Grep the whole codebase, including tests.
- For every converter removed: is the cached value still identical to a fresh
  read?
- For every filter or guard added, moved or removed: do the tests for the
  excluded case still exclude it for the stated reason, or does a different
  filter now get there first? A fixture with a nil field can make a
  deprecation test pass without ever testing deprecation.
- If any finding changes user-visible behaviour, say so and check whether the
  CHANGELOG needs a line. Reshapes usually don't; a producer that stops
  returning nil sometimes does.
- Run the tests for the area and any consumer touched. In `--fix` mode, run
  them after each commit, not only at the end.

## Output

Blocking bugs first. Then findings in the order they should be applied, split
into before merge and can follow. For each: the smell (from the list above),
the files and functions involved, what the shape should become, what code the
change deletes, and which later findings it makes unnecessary. If review notes
were supplied, say what happened to each. Note anything left alone out of
caution and why. End with the totals, the path of the map file, and in propose
mode how to apply (rerun with `--fix`, or pick items by hand).
