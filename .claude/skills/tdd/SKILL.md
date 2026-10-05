---
name: tdd
description: Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. Covers both stacks — ExUnit and Vitest/Playwright.
---

# Test-Driven Development

TDD is the red → green loop. This skill is the reference that makes that loop produce tests worth keeping: what a good test is, where tests go, the anti-patterns, and the rules of the loop. Every section applies on every cycle — consult them before and during the loop, not after.

When exploring the codebase, match the domain language already in use so test names and interface vocabulary line up with it: the context modules in `lib/lightning/` are the glossary (workflow, job, trigger, edge, snapshot, run, step, work order — these are distinct things, don't blur them). CLAUDE.md §Key Contexts is the map.

## What a good test is

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't. A good test reads like a specification — "user can checkout with valid cart" tells you exactly what capability exists — and survives refactors because it doesn't care about internal structure.

`.claude/guidelines/testing-essentials.md` is the reference for what a keepable test looks like here. Two rules from it that bear on every cycle:

- **Group related assertions.** Multiple assertions about one operation belong in one test. One-property-per-test produces files where the shape is buried in noise. In Elixir, pattern-match the whole struct instead of asserting field by field.
- **400 lines is the ceiling for a test file.** Past that, consolidate and extract setup into helpers.

## Seams — where tests go

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything — agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

Ask: "What's the public interface, and which seams should we test?"

The seams this codebase actually offers, and what you test them through:

| Seam | Test through | Case module |
| --- | --- | --- |
| Context module public API (`Lightning.Workflows`, `Lightning.Runs`, …) | direct function calls | `DataCase` |
| HTTP endpoint / controller | `Phoenix.ConnTest` | `ConnCase` |
| LiveView page | `Phoenix.LiveViewTest` — render and interact, don't call `handle_event` | `ConnCase` |
| Phoenix channel | join and push | `ChannelCase` |
| Oban worker | `perform/1` with a real job struct | `DataCase` |
| React store | `getSnapshot()` and the store's commands | Vitest |
| React component | React Testing Library, through the DOM | Vitest |
| Whole user journey (LiveView + React + DB) | Playwright | `npm run test:e2e` |

Schema modules and `changeset/2` are a seam too, but a shallow one — prefer testing validation through the context function that calls it, unless the changeset is itself complex enough to earn its own test.

## Mocking

There is no repo guideline for this, so: Mox is the default and by a wide margin the house style. Grep `test/` for `Mox`, `Mimic` and `with_mock` to see the current split.

- **Mox** for collaborators behind a behaviour that gets injected — HTTP via `Tesla.Adapter`, the extension hooks, `Lightning.Config`. Mocks are declared once in `test/test_helper.exs`; add new ones there. Stays `async: true`.
- **Mimic** only when the collaborator genuinely can't be injected: `File`, `IO`, `:hackney` are already `Mimic.copy`'d in `test/test_helper.exs`.
- **`:mock`'s `with_mock`** — don't add new uses. It swaps the module globally, so almost every file using it runs `async: false`.
- **Bypass** for a real HTTP server when you're testing the request that goes out on the wire (`test/support/bypass_helpers.ex`).
- **Stub modules** over expectation-based mocks when you only need a canned answer and don't care that the call happened: see `test/support/stub_rate_limiter.ex` and `stub_usage_limiter.ex`.

Mocking your own module is the smell, not the tool. If a test needs Mimic to reach past a boundary you own, the boundary is in the wrong place.

## Anti-patterns

- **Implementation-coupled** — mocks internal collaborators, tests private methods, or verifies through a side channel (querying the database instead of using the interface). The tell: the test breaks when you refactor but behavior hasn't changed. Local forms: a `Repo.get` assertion where the context function would have told you, or reading a Y.Doc's internal arrays where the store's snapshot would have. The one sanctioned exception is counting store `notify()` calls, where the count *is* the behaviour — see testing-essentials.md §Test behavior not implementation.
- **Tautological** — the assertion recomputes the expected value the way the code does (`expect(add(a, b)).toBe(a + b)`, a snapshot derived by hand the same way, a constant asserted equal to itself), so it passes by construction and can never disagree with the code. Expected values must come from an independent source of truth — a known-good literal, a worked example, the spec.
- **Horizontal slicing** — writing all tests first, then all implementation. Bulk tests verify _imagined_ behavior: you test the _shape_ of things rather than user-facing behavior, the tests go insensitive to real changes, and you commit to test structure before understanding the implementation. Work in **vertical slices** instead — one test → one implementation → repeat, each test a **tracer bullet** that responds to what the last cycle taught you.

## Rules of the loop

- **Red before green.** Write the failing test first, then only enough code to pass it. Don't anticipate future tests or add speculative features.
- **One slice at a time.** One seam, one test, one minimal implementation per cycle.
- **Run only the slice.** `mix test path/to/test.exs:42` or `npm test -- useSession.test.ts` (from `assets/`). Full-suite runs belong at the end of the session, not inside the loop.
- **Green means green.** `warnings_as_errors: true`, so a warning is a red. Don't move on with one outstanding.
- **Refactoring is not part of the loop.** It belongs to the review stage — `/code-review` for defects, `/simplify` for cleanup — not the red → green implementation cycle.
