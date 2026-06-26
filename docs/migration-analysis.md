# Migration Analysis — Honest Assessment

> **Phase 4 deliverable.** The honest write-up of what this experiment revealed.
>
> _Status: skeleton — to be filled in Phase 4, grounded in what the Phase 3
> Credentials slice actually showed (not hypotheticals)._

## 1. Architecture overview (recap)

_TBD — recap of `docs/architecture.md`._

## 2. API documentation (recap / link)

_TBD — recap of / link to `docs/api.md`._

## 3. Page inventory — what moves, where it lands, what resists

> For each surface: what backend logic existed, where it now lives in the
> two-component design, and a **"Difficult to move"** column naming the
> *specific* blocker (stateful socket assigns, Oban job, Ecto.Multi transaction,
> policy/auth woven into mount, PubSub real-time, project.yaml portability
> contract) observed while doing the Phase 3 slice.

_TBD_

## 4. Recommendation

_TBD — is this the right approach to make OpenFn less tightly coupled?
Grounded in what the slice revealed. Includes the strongest case **against**
this recommendation._

## 5. Staging & sequencing — how we'd actually do this

> **Requested explicitly (Brandon).** If we decided to *actually* do this, how
> should the work be staged? Evaluate the working hypothesis below against what
> the Phase 3 slice revealed — agree, refine, or push back; don't just restate it.

**Hypothesis to evaluate:** rebuild the **app shell** first (outer nav / layout /
auth chrome as a thin React client against the REST API), then incrementally
**retire the LiveView-rendered tables/grids** (History, Projects, Credentials
index, Runs, Collections, …) and **rebuild them "properly"** as React components
backed by REST endpoints — one surface at a time (strangler-fig), rather than a
big-bang rewrite.

_TBD — produce a concrete, ordered staging plan: what ships first, what the
"app shell" milestone actually includes, the order surfaces should be peeled off
(easiest/most-self-contained → hardest/most-stateful, informed by §3's
"Difficult to move" column), where the seams/strangler-fig routing live, what
stays on LiveView longest (collaborative editor, run/log streaming), and the
exit criteria for each stage. Call out the risks of the "rebuild the tables
properly" framing (e.g. re-deriving server-side filtering/pagination/policy
scoping that LiveView currently does for free)._

## 6. Perspective: a professional React developer

> **Requested explicitly (Brandon).** Answer from the seat of a professional
> React developer working on this product, grounded in the Phase 1 inventory and
> the Phase 3 slice (not generic SPA-vs-LiveView talking points).

Three questions to answer directly:

1. **Is the architecture slowing us down?** Where does the LiveView coupling
   actually cost a frontend developer day to day (e.g. having to write Elixir to
   change UI behaviour, no typed client contract, React confined to islands inside
   `phx-update="ignore"`, server-roundtrip for interactions, shared `socket.assigns`
   state model)? Where does it *help* (real-time for free, no API to version, one
   deploy)? Be specific to what the inventory shows.
2. **Velocity: increase or waste of effort?** Would a thin-React-over-REST design
   measurably speed up frontend work, or is it churn that mostly relocates
   complexity? Tie the answer to concrete surfaces from §3 (the clean 🟢 CRUD
   surfaces vs the 🔴 connection-oriented ones) and to what the Credentials slice
   showed about how much logic actually has to move.
3. **Can it be automated, with automated testing?** How much of this migration is
   mechanical/scriptable (route extraction, JSON contract generation from existing
   `*_json.ex` views, schema/type generation for the client, codemods) vs.
   irreducibly manual (re-deriving server-side filter/pagination/policy logic,
   the OAuth/real-time/CRDT surfaces)? What does an automated test strategy look
   like across the boundary (contract tests against the REST API, Playwright/E2E
   that already exists, type-checking the generated client)? Give a realistic
   automate-able percentage and name what resists automation._TBD_
