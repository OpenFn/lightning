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
