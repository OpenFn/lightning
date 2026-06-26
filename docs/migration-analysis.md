# Migration Analysis: Honest Assessment

> **Phase 4 deliverable.** What this experiment revealed, grounded in the Phase 1
> inventory (`page-inventory.md`), the Phase 2 design (`architecture.md`,
> `api.md`), and especially the Phase 3 Credentials slice that was actually built
> and tested (`../decoupling-experiment/credentials_service/`).

## TL;DR

- **Decouple the presentation/transport boundary: worth doing, incrementally.**
  Put a thin React client in front of a Phoenix backend that exposes the REST +
  real-time contract that already half-exists. Keep one backend app and one
  database.
- **A true backend service/DB split: not worth it now.** The Credentials slice
  showed the data-tier coupling (shared encryption key, cross-context
  `Ecto.Multi`, the `project_credentials` seam, opaque cross-service FKs) makes
  that expensive for little near-term gain.
- **The target shape already exists in the tree** (the collaborative workflow
  editor: React island + channel + Y.Doc; and the `controllers/api/*` REST
  skeleton). This is an extension of existing patterns, not a greenfield rewrite.
- The honest risk: you take on the cost of re-deriving everything LiveView gives
  for free (server-side pagination/filter/policy-scoping) without getting the
  headline "independently deployable backend" benefit, and you live with two UI
  paradigms during a multi-quarter migration.

## 1. Architecture overview (recap)

Full detail in `architecture.md`. Two components:

- **A. React SPA (thin client):** routing, rendering, ephemeral UI state. Calls
  REST for I/O; subscribes to Phoenix Channels for real-time. Holds no
  authoritative domain state and enforces no authorization.
- **B. Phoenix backend, LiveView removed:** the existing contexts, schemas, Oban,
  PubSub, Cloak vault, Bodyguard policies, and channels, kept as-is. The
  `controllers/api/*` REST API is expanded into the full contract; a request-level
  authorization plug replaces the `on_mount :project_scope` hook.

The boundary is exactly two things: the **REST contract** (reads/writes) and the
**real-time channel/event contract** (run/log streaming, project history, AI
streaming, collaborative editing). Everything else (encryption keys, Oban, the
Yjs `:pg` topology, policies, worker JWTs, PubSub) stays server-internal. One
shared PostgreSQL; no data-tier split.

## 2. API documentation (recap / link)

Full contract in `api.md`. REST under `/api/v1`, bearer-token auth, the existing
`FallbackController` status mapping (404/403/401/422), page-based pagination.
A real finding the contract resolves: the existing API ships **two incompatible
JSON conventions** (JSON:API for projects/workflows/runs via `API.Helpers`; a flat
`{credentials: [...]}` shape for credentials). The v1 contract standardizes on the
JSON:API envelope. Credentials is specified in full (multi-environment encrypted
bodies, the never-return-body invariant, the OAuth popup/callback sub-flow), and
the slice implements it.

## 3. Page inventory: what moves, where it lands, what resists

Per surface: the backend logic it relies on today, where that lands in the
two-component design, and the **specific** blocker that resists clean extraction.
🟢 clean · 🟡 some glue · 🟠 real-time/async coupling · 🔴 connection-oriented.

| Surface | Backend logic today | Lands as | Difficult to move (specific blocker) |
|---|---|---|---|
| Dashboard / Projects list 🟢 | `Projects`, `Accounts`; sort in socket | REST `GET /projects` + React list | None of substance. In-socket sort/filter becomes query params. |
| Collections 🟢 | `Collections`; already a REST data API at `/collections` | REST CRUD + React | None. This is the model the rest should resemble. |
| Users / Audit / AuthProviders admin 🟢 | `Accounts`, `Auditing.list_all`, `AuthProviders` | REST + React tables | Audit view renders encrypted bodies server-side; decryption stays backend. `send_update`/parent-pid messaging is LiveView glue, drops out. |
| Auth pages 🟢 | `Accounts` (password/TOTP/sudo/superuser) | REST `/auth/*` endpoints | **Policy/auth woven into the lifecycle**: today the session cookie + `on_mount` do this implicitly; must become explicit token endpoints + a plug. |
| Profile / Settings 🟡 | `Accounts` (MFA/tokens/prefs), `VersionControl` | REST + React | MFA enrollment is a stateful multi-step handshake; one-time token display; the GitHub-link **OAuth `{:forward}`→`send_update` bridge**. |
| Project settings 🟠 | `Projects`, `VersionControl`, `WebhookAuthMethods`, 11 `ProjectUsers` policy checks | REST + React | **Policy woven into mount and per-event**; the **GitHub OAuth callback bridge**; LiveView **view-extension slots** (downstream apps inject components via route metadata) have no SPA analogue. |
| Sandboxes / ingestion Channels 🟡 | `Projects.Sandboxes`, `VersionControl`, `Channels` | REST + React | **Stateful socket-assign selection set** (merge picks workflows/credentials, lost on reconnect) must become explicit client-held ID lists. |
| Credentials 🟠 (**the slice**) | `Credentials` (+Cloak, OAuth, transfer, keychain), `OauthClients`, `project_credentials` join | REST `/credentials` + React (built, tested) | **Encryption key must travel with data; `Ecto.Multi` deletion spans context boundaries; OAuth popup/callback + token-refresh; audit emitted inside the Multi; `oauth_clients.client_secret` plaintext; project scope is a join, not a column.** All observed first-hand (see §3a). |
| Runs & Work Orders / History 🟠 | `Invocation.search_workorders`, `WorkOrders`, `Runs` (log `Repo.stream`) | REST reads + `run:{id}` / `project:{id}` channels | **PubSub real-time** (in-place-patched server collections); **chunked log streaming** to a client Zustand buffer; **bulk actions are Oban jobs** reporting via PubSub; **bulk-selection socket state**. |
| Workflow editor 🟠 (already decoupled) | `Workflows` (+Snapshot, Presence), Y.Doc, `WorkflowChannel` | Already React island + channel + Y.Doc | **Yjs CRDT + `:pg` + presence**: connection-oriented, stays on a channel. Reference-data RPC could move to REST. This surface is the template, not the problem. |
| AI Assistant 🟠 | `AiAssistant`, `MessageProcessor` **Oban**, `ai_session` PubSub | REST POST + SSE/channel stream | **Oban + PubSub + `send_update` async lifecycle**; component-registration indirection; dual transport (whole-message vs token stream). |
| Provisioning / project.yaml 🟠 | `Provisioning` context, synchronous in controller | REST `/provision` (exists) | **The `project.yaml` portability contract**: a stable, documented import/export format that external tooling and CLI depend on. Credentials are part of it, so the Credentials service must keep honoring the contract, which couples it back to Projects/Workflows shapes. |
| Worker dispatch 🔴 | `WorkerChannel`, `Runs.Queue` (FOR UPDATE SKIP LOCKED), `WorkerPresence` | Unchanged (`WorkerSocket`) | Not the React client. Pull-based push loop with presence-derived capacity; stays as-is. |
| Synchronous webhook response 🔴 | `WebhooksController` blocks on a PubSub `receive` | Server-internal, unchanged | The HTTP webhook caller is external; the request/response rendezvous is the inverse of stateless. Not a client concern. |

### 3a. What the Credentials slice actually proved (not hypotheticals)

Building and testing `credentials_service` surfaced these, concretely:

1. **The encryption key travels with the data.** `credential_bodies.body` is only
   ever ciphertext (Cloak). The slice had to stand up its own `Vault` with the
   same kind of key. Any service owning that table needs the key or a
   re-encryption migration. The monolith's `audit_events` also embed encrypted
   bodies, pulling the audit store into scope.
2. **`Ecto.Multi` spans context boundaries.** Credential deletion in the monolith
   nulls `jobs.project_credential_id` (Workflows), deletes `project_credentials`
   (here), revokes OAuth tokens over HTTP (AuthProviders), and emails the owner
   (Accounts) in one transaction. In the slice, only the local
   `project_credentials` delete stayed transactional; the rest became a named seam
   (`remove_external_associations/1`). **This is the clearest argument against a
   DB/service split**: you lose atomicity exactly where the monolith relies on it.
3. **Identity and project scope are opaque cross-context FKs.** `user_id` and
   `project_id` became plain `:binary_id` columns, not `belongs_to`. The service
   cannot answer "can this user access this project?" locally because roles live
   in `project_users` (Projects). Authorization needs a membership contract across
   the boundary.
4. **OAuth refresh is hot-path, networked, and transactional**, so it was kept as
   a documented stub rather than built. It sits on the critical path of every run
   that uses an OAuth credential.
5. **`oauth_clients.client_secret` is plaintext at rest** today. Preserved
   faithfully (flagged), not silently "fixed."
6. **The HTTP layer was the easy part.** The REST controller, JSON:API view, and
   moving auth into a plug were straightforward, because `controllers/api/*`
   already modeled the pattern. **All the friction is in data/transaction/
   encryption coupling, none in the request/response layer.**

## 4. Recommendation

**Recommended: decouple the presentation/transport boundary, incrementally, and
keep one backend app + one database. Do not pursue a backend service/DB split
now.**

Why, grounded in the slice and inventory:

- The valuable, achievable win is a **thin React client over a clear API +
  real-time contract**. Half of that contract already exists (`controllers/api/*`,
  the channels). The slice proved the HTTP/controller/auth-plug layer is cheap to
  produce for a clean surface.
- The expensive, low-reward part is splitting the **data tier**. The slice showed
  the coupling is real and concrete: shared encryption keys, an `Ecto.Multi` that
  reaches across contexts, the `project_credentials` join seam, and authorization
  that depends on another context's tables. Turning those into distributed
  transactions and cross-service contracts buys little while a single team ships
  from one repo.
- Sequence it strangler-fig (see §5), easiest surfaces first, leaving the
  connection-oriented surfaces (collaboration, run streaming, AI) on channels,
  where the workflow editor already demonstrates the end state.

**The strongest case against this recommendation** (argued in good faith):

1. **You pay LiveView's hidden bill without its benefit.** LiveView gives
   server-side pagination, filtering, sorting, authorization, and real-time "for
   free." A REST/React rebuild must re-derive every bit of that as explicit API
   params, guards, and subscriptions. That is a large, mostly-manual cost, for an
   app where LiveView velocity is currently high.
2. **You don't get the headline benefit.** Keeping one app and one DB means no
   independently deployable/scalable backend, no separate team ownership of a
   backend service, no polyglot frontend freedom beyond "it's React now." If the
   actual goal is *service* decoupling, this does not deliver it, and may entrench
   a half-migrated codebase (two UI paradigms, two state models, two test stacks)
   for years.
3. **The cheaper alternative may capture most of the value.** The collaborative
   editor shows React running well *inside* LiveView as an island. Expanding that
   island pattern (more React, still LiveView-hosted, talking over channels) could
   deliver most of the frontend-DX win at a fraction of the cost of a full SPA +
   REST contract, while keeping real-time for free.

A reasonable reading of all this: do the **contract + app-shell groundwork**
(§5 Stage 0-1) because it is cheap and reversible, then decide per-surface whether
full React-over-REST beats an expanded island. Let the easy surfaces prove the ROI
before committing to the hard ones.

## 5. Staging & sequencing: how we'd actually do this

> **Requested explicitly (Brandon).** Working hypothesis to evaluate: rebuild the
> app shell first, then incrementally retire the LiveView-rendered tables/grids
> and rebuild them properly as React-over-REST, strangler-fig, not big-bang.

**Verdict: the hypothesis is right in shape, with two refinements.** (a) Do a
contract/plumbing stage *before* the shell, and (b) treat "rebuild the tables
properly" as a warning, not just a goal, because the hard part is re-deriving the
server-side query logic the tables get for free today.

- **Stage 0: Contract + plumbing (cheap, do first).** Pin `/api/v1`; add the auth
  plug + token issuance (login/refresh) so the SPA can authenticate; generate a
  typed client from the API (OpenAPI or types derived from the `*_json.ex` views);
  stand up contract tests. Reuse the existing `api/*` controllers + `SearchParams`
  rather than reinventing. Exit: a React app can authenticate and read one
  resource through a typed client, with contract tests green.
- **Stage 1: App shell.** Build the React nav/layout/auth/routing shell. During
  migration it hosts a mix of new React surfaces and still-LiveView surfaces
  (route-proxy per path, the way `collaborate` and conventional pages already
  coexist). Exit: the shell renders, auth works, and at least one real surface is
  served as React while the rest remain LiveView.
- **Stage 2: Peel the easy tables (🟢).** Collections, Projects/Users/Audit/
  AuthProviders admin lists, Dashboard. These are CRUD + sort/filter; the work is
  moving sort/filter/pagination into query params and rendering tables in React.
  Highest ROI, lowest risk. Exit: each list ships as React-over-REST with E2E
  parity.
- **Stage 3: Medium surfaces (🟡).** Profile/Settings, Project settings,
  Sandboxes, Credentials. Here the §3a coupling bites: OAuth callback flows,
  encryption-backed forms, server-held selection sets. The Credentials slice is
  the worked example. Exit: each surface ships with its OAuth/encryption flows
  intact (server-side) and a React form over the contract.
- **Stage 4: Real-time surfaces, REST-first then channel.** Runs/History: ship the
  reads over REST first (correct but poll-based), then add the `run:{id}` /
  `project:{id}` channel subscriptions for live updates. AI: POST + stream.
- **Stage 5: Leave on channels deliberately.** The workflow editor (Yjs) is
  already the target shape; do not "REST-ify" it. Worker dispatch and the webhook
  rendezvous stay server-internal.

**The "rebuild the tables properly" caution.** The risk is silently dropping the
server-side filtering, pagination, and policy-scoping that LiveViews do inline
(`TableHelpers.filter_and_sort`, `SearchParams`, `Permissions.can?` per event).
Budget explicitly for re-expressing those as API query params + an authorization
plug, and reuse the existing JSON views and search params instead of reinventing
them. Each stage keeps both paradigms working; nothing is removed until its React
replacement reaches E2E parity (the existing Playwright suite is the net).

## 6. Perspective: a professional React developer

> **Requested explicitly (Brandon):** is the architecture slowing us down? would
> this migration increase velocity or be wasted effort? how automatable is it,
> with automated testing?

**Is the architecture slowing us down?** In specific, real ways, yes:

- React lives in **islands** (`phx-hook="ReactComponent"`, `phx-update="ignore"`)
  embedded in LiveView. You are a guest in someone else's render tree and
  lifecycle, not the owner of the page.
- There is **no typed API contract**. Props arrive from LiveView underscore_cased
  and untyped; you discover shapes by reading Elixir. Changing UI behaviour often
  means editing `.ex`/HEEx, so a frontend specialist must read and write Elixir to
  do frontend work.
- The state model is **`socket.assigns` on the server**, reconciled over a
  socket, which is foreign to React's local-state/data-fetching mental model. The
  workflow editor's JSON-patch reconciliation is the extreme case.
- **Testing is heavy**: meaningful tests run the whole LiveView+DB stack (the
  Playwright E2E suite). Fast, isolated component tests are limited because
  components depend on LiveView-provided assigns and server round-trips.

But it genuinely **helps** in ways a React dev should not dismiss: real-time and
optimistic UI come essentially for free, there is no API to version, there is one
deploy, and authorization is enforced server-side by default. The collaborative
editor shows you *can* write serious React here.

**Velocity: increase or waste?** Nuanced, and it depends on the surface and the
team:

- For the **🟢/🟡 CRUD surfaces (most of the app)**, a typed REST client + React
  would clearly speed iteration and let frontend specialists work without Elixir.
  This is where the velocity win is real.
- For the **🔴 surfaces**, there is little to gain: the editor is already React,
  and run-streaming/AI must stay channel-based regardless.
- The slice is the key evidence on cost: for a clean surface, the **backend logic
  that has to move is modest** (the Credentials context extracted cleanly; the
  hard parts, encryption/OAuth/audit, stay on the backend either way). So the
  migration cost is **front-loaded into the contract and the re-derivation of
  server-side query/policy logic**, not spread across endless business-logic
  rewrites.
- Net: it **increases velocity for frontend-heavy iteration** and hiring of
  frontend specialists, but it is closer to a **wash (or a loss) if the team is
  small and full-stack-Elixir and is shipping fine today**. The honest answer is
  "increase, conditional on the team you want to have and the surfaces you iterate
  on most."

**Can it be automated, with automated testing?** Partially. Be skeptical of
"codemod the whole thing":

- **Automatable (≈40-60% of the mechanical work):** generating the API contract
  and TypeScript types from the existing `*_json.ex` views (or an OpenAPI spec),
  scaffolding React data hooks/queries from that contract, route extraction, and
  repetitive island→page conversions. The existing JSON views are a real head
  start.
- **Not automatable:** re-deriving server-side filtering/pagination/policy-scoping
  into API params and an auth plug (judgement, per surface), the OAuth/real-time/
  CRDT surfaces, and the UX decisions that come with owning the page. These are
  the same things §3a/§5 flag as hard.
- **Automated testing across the boundary** is the strong part of the story:
  contract tests (schema/OpenAPI validation, or consumer-driven contract tests)
  catch backend/frontend drift; the **existing Playwright E2E suite** is the
  per-surface regression net during the strangler migration; a typed client makes
  `tsc` catch breakage at build time; and the slice shows backend **ExUnit
  controller tests are cheap** once a surface is REST (17 tests, including the
  never-return-body and 401/403/404 cases, were quick to write and fast to run).

**Bottom line from the React seat:** the architecture is a real drag on
*frontend-specialist* velocity and testability, and the migration would help most
where the app is plain CRUD. But it is front-loaded work whose biggest tasks
(server-side query/policy re-derivation, real-time, OAuth) resist automation, and
it does not, by itself, give you an independently deployable backend. Do Stage 0-2
first, measure the ROI on the easy surfaces, and let that decide how far to push.
