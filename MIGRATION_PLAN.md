# Lightning Decoupling Experiment — Migration Plan

> **Status:** living document. The `## RESUME STATE` block at the bottom is the
> source of truth for where this experiment is. A fresh run should read that
> block first and resume from the first incomplete phase.

## What this is

A **design experiment** (not a production migration) exploring whether
`openfn/lightning` — today a Phoenix **LiveView** monolith — could be split into:

- **(a)** a "dumb" React frontend (a thin client we do not build here, only
  define the contract for), and
- **(b)** a separate **Elixir + Phoenix** backend service exposing a clear,
  independently-maintained API.

The whole point is to find out, *concretely and honestly*, how tightly coupled
the current architecture is — by mapping it, designing a target, and actually
extracting one real vertical slice to see what fights back.

## Stack decisions (locked — not relitigated)

| Decision | Choice | Rationale (grounded in this repo) |
|---|---|---|
| Backend service language | **Elixir + Phoenix, no LiveView** | Given. Reuse the existing contexts/schemas; the only thing being removed is the LiveView/HEEx presentation layer. |
| API style | **REST** | The repo **already has a REST API** under `lib/lightning_web/controllers/api/` (`project_controller`, `credential_controller`, `run_controller`, `workflows_controller`, `provisioning_controller`, …) with dedicated `*_json.ex` views, a `FallbackController`, and bearer-token auth via `LightningWeb.Plugs.ApiAuth`. There is **no Absinthe/GraphQL** dependency anywhere. Choosing REST means the experiment extends an established, real convention instead of inventing a greenfield GraphQL layer — which keeps the findings honest. |
| Phase 3 vertical slice | **Credentials** | The most genuinely *self-contained* user-facing data surface (avoiding Runs/execution per instructions). It also exposes the richest set of *nameable* "difficult-to-move" blockers: Cloak encryption-at-rest, OAuth token storage/refresh, the `Auditing` trail on every change, the `project_credentials` many-to-many join back to Projects, and Bodyguard policies. Projects was the runner-up but is so central (nearly every table FKs to it) that "self-contained" would be a stretch; its `project.yaml` provisioning contract is still captured in the inventory. |

## Method: phase-gated

Finish each phase → write its artifacts to disk → update `RESUME STATE` →
**git commit** → only then proceed. One commit per phase.

### Deliverables (all markdown, under `docs/`)

| File | Phase | Purpose |
|---|---|---|
| `docs/page-inventory.md` | 1 | Every LiveView/page/route and the backend logic it depends on. A map. |
| `docs/architecture.md` | 2 | Proposed two-component design; the service boundary; how auth/sessions/real-time cross it. |
| `docs/api.md` | 2 | The full REST contract the React client would consume. |
| `docs/migration-analysis.md` | 4 | Honest analysis: recap, per-surface difficulty, and a grounded recommendation (incl. the strongest case against it). |

## Phase definitions

- **Phase 0 — Plan.** This file + `docs/` skeleton. Commit.
- **Phase 1 — Inventory.** Read-heavy, no code changes. Produce `docs/page-inventory.md`.
- **Phase 2 — Target architecture + API.** `docs/architecture.md` + `docs/api.md`.
- **Phase 3 — One real vertical slice (Credentials).** Extract into a new service
  skeleton that compiles and whose tests pass. Other surfaces are documented stubs only.
- **Phase 4 — Honest analysis.** `docs/migration-analysis.md`.

## Known environment constraints (discovered Phase 0)

- **Elixir/mix is NOT installed** in this container (`.tool-versions` targets
  Erlang 27.3.3 / Elixir 1.18.3-otp-27); `node` 22 and `psql`/`pg_isready` are
  present; no `_build`/`deps`. Phase 3 will attempt to provision the toolchain to
  satisfy the "must compile + `mix test` passes" gate. If provisioning is not
  possible in this environment, Phase 3 will deliver the slice as real,
  review-ready code with a clearly-documented verification gap (honesty over
  faking a green run) — and the priority ordering below makes Phase 3 the first
  to be trimmed under budget pressure.

## Budget priority (if low on budget)

Per instructions: **Phase 1 > Phase 4 > Phase 2 > Phase 3.** Documentation and
honest analysis matter more than the executable proof.

---

## RESUME STATE

> Update this block at the end of every phase, then commit.

- **Phase 0 — Plan:** ✅ COMPLETE
- **Phase 1 — Inventory:** ✅ COMPLETE (`docs/page-inventory.md` written: route map, surface-by-surface inventory of all ~26 routed LiveViews/feature areas, and cross-cutting catalogues for contexts/schemas/Oban/PubSub/channels/policies/presence, plus a decoupling-difficulty ranking)
- **Phase 2 — Architecture + API:** ✅ COMPLETE (`docs/architecture.md` = two-component design + service boundary + auth/sessions/real-time crossing; `docs/api.md` = REST contract with Credentials fully specified, grounded in the real `*_json.ex`/`FallbackController`/schema shapes, and the JSON:API-vs-flat inconsistency resolved)
- **Phase 3 — Vertical slice (Credentials):** ✅ COMPLETE (new `decoupling-experiment/credentials_service/` Phoenix+Ecto service: real Cloak-encrypted schemas, Credentials context, REST controller/JSON per `docs/api.md`, auth-in-a-plug; **compiles and `mix test` = 17 tests, 0 failures**. Toolchain provisioned: Elixir 1.17.3/OTP25 + Postgres 16. Other surfaces are documented stubs in `stubs.ex`. Findings captured in `decoupling-experiment/README.md`.)
- **Phase 4 — Honest analysis:** ⬜ NOT STARTED

**Next action:** Begin Phase 4 — write `docs/migration-analysis.md` in full
(recap arch+API, the per-surface "Difficult to move" table grounded in the slice,
the recommendation + strongest counter-case, the §5 staging plan, and the §6
professional-React-developer perspective). Then commit + push. This is the last
phase and the second-highest priority.

**Phase 3 findings to fold into Phase 4 (observed while extracting Credentials):**
encryption key must travel with the data (Cloak); `user_id`/`project_id` become
opaque cross-context FKs (identity + project-membership contracts needed);
deletion is an `Ecto.Multi` spanning context boundaries (only the local
`project_credentials` delete stays atomic; nulling `jobs.project_credential_id` +
OAuth revoke + owner email become cross-service ops); OAuth refresh is
hot-path/network/transactional (stubbed); audit trail emits inside the Multi
(stubbed); `oauth_clients.client_secret` plaintext at rest (faithful gap); the
REST/controller/JSON/auth-plug layer was the easy part.

**Key Phase 1 findings to carry forward:** (1) the app already contains the
decoupled target shape (collaborative editor = thin LiveView shell + React island
+ `WorkflowChannel` + Y.Doc) and a REST skeleton (`controllers/api/*` with
Bodyguard policies + `*_json.ex` views); (2) auth is woven into LiveView
`on_mount`/inline handlers, not a request plug; (3) run execution is pull-based
(not Oban); (4) hardest-to-move = Yjs collaboration, worker dispatch, presence
edit-lock, real-time run/log streaming, synchronous webhook-response rendezvous;
(5) Credentials slice specifics: secrets in encrypted `credential_bodies.body`
(no `oauth_tokens` table), `oauth_clients.client_secret` plaintext, project scope
via `project_credentials` join, Credentials context is itself an Oban worker.

**Decisions already made:** API = REST; Phase 3 slice = Credentials. (See table above.)

**Additional requirements (added mid-run by Brandon):**
- **Phase 4 must include a staging/sequencing recommendation** for how to
  actually do the migration. Working hypothesis to evaluate (agree/refine/push
  back, grounded in the slice): *rebuild the app shell first (React nav/layout/auth
  against the REST API), then incrementally retire the LiveView-rendered tables/grids
  and rebuild them properly as React components backed by REST — strangler-fig,
  one surface at a time, not big-bang.* Section 5 of `docs/migration-analysis.md`
  is stubbed for this.
- **Phase 4 must include a professional React developer's perspective** (§6 of
  `docs/migration-analysis.md`, stubbed): is the current architecture slowing
  frontend work down? would the migration increase velocity or be wasted effort?
  how automatable is the migration (with automated testing)? Answers must be
  grounded in the inventory + the Credentials slice, not generic talking points.
