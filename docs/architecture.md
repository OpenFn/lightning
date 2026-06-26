# Target Architecture: Decoupled Frontend / Backend

> **Phase 2 deliverable.** The proposed two-component design (a thin React client
> and a separate Elixir/Phoenix no-LiveView backend), the service boundary, and
> how auth/sessions/real-time cross it. Grounded in the Phase 1 inventory
> (`docs/page-inventory.md`).

## Today: the LiveView monolith

One Phoenix OTP app holds everything: business logic (`lib/lightning/` contexts +
Ecto + Oban), presentation (`lib/lightning_web/live/`, ~122 LiveView modules), a
REST API skeleton (`lib/lightning_web/controllers/api/`), and 5 WebSocket channels.
The browser is thin by construction but **not decoupled**: LiveView keeps the
authoritative UI state in `socket.assigns` server-side and ships DOM diffs over a
private WebSocket protocol. Authorization runs inside the LiveView lifecycle
(`on_mount :project_scope` + inline `Permissions.can?` in `handle_event`), so there
is no single request-level API contract that a non-LiveView client could consume.

The consequence: the frontend and backend are not two layers with a contract
between them, they are one program. You cannot rebuild the UI in React without
re-expressing, as an explicit API, a large amount of behaviour that currently
only exists implicitly in the LiveView event lifecycle.

## Proposed: two components

```
┌─────────────────────────┐         ┌──────────────────────────────────────────┐
│  Component A             │  HTTPS  │  Component B                               │
│  React SPA (thin client) │ ──REST─▶│  Phoenix backend service (NO LiveView)     │
│                          │         │                                            │
│  - routing, rendering    │◀─WS/SSE─│  lib/lightning/**          (contexts, kept)│
│  - local UI state        │  (push) │  lib/lightning_web/                        │
│  - calls REST for I/O    │         │    controllers/api/**      (REST, expanded) │
│  - subscribes to channels│         │    channels/**             (real-time, kept)│
│    for real-time         │         │    plugs/** (auth)         (NEW: authz plug)│
└─────────────────────────┘         │  Oban, PubSub, Cloak vault, Bodyguard      │
                                     │  Postgres (shared, single DB)              │
                                     └──────────────────────────────────────────┘
                                                    ▲ worker JWT (unchanged)
                                              ┌─────┴───────┐
                                              │ @openfn/ws-worker │ (external, unchanged)
                                              └───────────────────┘
```

**Component A: React SPA.** Owns routing and rendering. Holds only ephemeral UI
state (form drafts, selections, expanded rows) that today lives in `socket.assigns`.
For every read or write it calls the REST API; for live updates it subscribes to
Phoenix Channels (or SSE). It is "dumb" in the sense that it holds no authoritative
domain state and enforces no authorization, only reflects it.

**Component B: Phoenix backend, LiveView removed.** This is the existing app minus
`lib/lightning_web/live/`. The contexts, schemas, Oban workers, PubSub, Cloak
vault, Bodyguard policies, and channels are kept essentially as-is. What changes:
the REST API under `controllers/api/` is expanded from a partial read API into the
full contract (`docs/api.md`), and a request-level authorization plug replaces the
`on_mount :project_scope` hook.

**Honest scoping of "separate service."** The instruction frames Component B as "a
separate Elixir/Phoenix backend service." The pragmatic and truthful first form of
that is **one Phoenix backend (contexts + API + channels) serving a separate React
frontend**, sharing one OTP app and one database. A *stronger* split (separate
deployables, separate databases, network calls between backend services) is a
further, much harder step that the Phase 1 inventory shows is gated on encryption-key
sharing, cross-context Ecto transactions, and same-DB joins. This document designs
the first form and flags the second as out of scope (see "Data ownership" and the
Phase 3 Credentials slice). The decoupling that delivers value here is the
**presentation/transport boundary**, not a data-tier split.

## The service boundary

The contract between A and B has exactly two parts:

1. **The REST API** (`docs/api.md`): all reads and writes the client performs.
   Request/response shapes, status codes, auth, pagination.
2. **The real-time channel/event contract**: the topics the client may subscribe
   to and the event payloads it will receive (run/log streaming, project history,
   AI streaming, collaborative editing).

Everything else stays *inside* Component B and is never exposed across the boundary:

| Stays server-only | Why |
|---|---|
| Cloak vault + encryption keys (`Lightning.Vault`) | Secrets in `credential_bodies.body` are decrypted only to serve workers; never crosses to the React client. |
| Oban workers + cron | Background work has no client coupling except result delivery (which becomes a channel push or a polled status endpoint). |
| Bodyguard policies | Pure `(action, actor, resource)` functions; enforced behind the API, never trusted from the client. |
| Yjs `SharedDoc` + `:pg` topology | The collaborative-editing CRDT lives in memory across the cluster; the client speaks the Yjs binary protocol over a channel, it does not see the topology. |
| Worker dispatch (`WorkerSocket`, run-scoped JWTs) | The worker is a separate external actor, not the React client. Unchanged. |
| PubSub topics | Internal fan-out; the client sees a curated subscription channel, not raw PubSub. |

The single most important enabling fact from Phase 1: **both halves of this
boundary already exist in the tree.** The REST half is modeled by
`controllers/api/*` (with `action_fallback`, Bodyguard checks, and `*_json.ex`
views). The real-time half is modeled by the collaborative editor
(`WorkflowChannel` + `Collaboration.Session` + a React island), which is already a
thin-LiveView-shell + React + channel design. Decoupling is an extension of two
existing patterns, not a greenfield invention.

## Authentication & sessions across the boundary

**Today (dual model).** Browser/LiveView uses a session cookie resolved to
`current_user` at mount by `InitAssigns`; the API uses bearer tokens
(`authenticate_bearer` → `User`/`ProjectRepoConnection`; `Plugs.ApiAuth` → JWT).

**Target (single token model for the SPA).** The React client authenticates once
and receives a token, then sends it as `Authorization: Bearer <token>` on every
REST call and uses it to connect the channel socket. The building blocks already
exist:

- `Lightning.Accounts.UserToken` + `Lightning.Tokens` already mint/verify tokens.
- `UserSocket` already connects by verifying a `Phoenix.Token` user-socket token.
- The `api/*` controllers already authorize per request with `Permissions.can`.

Concretely:

1. **Login** (`POST /api/auth/session`, proposed) validates email/password (and
   TOTP when enabled) and returns a short-lived access token (+ a refresh token or
   a rotation scheme). MFA, email confirmation, sudo re-auth, and password reset
   become explicit endpoints mirroring today's controllers.
2. **Authorization moves to a plug.** A `RequireProjectAccess` plug (or per-action
   `with :ok <- Permissions.can(...)`, the pattern `api/*` already uses) replaces
   the implicit `on_mount :project_scope`. This is the single biggest auth change:
   today a large share of authorization is woven into the LiveView lifecycle and
   inline event handlers and must be re-expressed as request-level guards.
3. **CSRF.** Bearer-token-in-header auth sidesteps the cookie CSRF concern that
   `protect_from_forgery` handled for LiveView. If a cookie is used to hold the
   token, it must be `HttpOnly`/`SameSite` with CSRF protection; the cleaner path
   is a non-cookie token in memory + refresh rotation.
4. **Sessions become stateless.** No server-side socket session holds user state
   between requests; each REST call is self-authenticating. The only stateful
   "sessions" that remain are the genuinely connection-oriented ones (a live run
   subscription, an editor collaboration session), which are channel-scoped.

## Real-time across the boundary

LiveView gave real-time "for free" by pushing DOM diffs. Without it, the push
flows identified in Phase 1 need an explicit transport. **Keep Phoenix Channels**
as that transport (the client library is mature and the channels already exist);
SSE is a viable alternative for the strictly one-directional streams.

| Real-time flow (Phase 1) | Transport in target | Notes |
|---|---|---|
| Run state / steps / logs (`run_events:{run_id}`) | Channel `run:{id}` (browser path already exists in `RunChannel`) | Client subscribes on opening a run; receives `run:updated`, `step:*`, `logs`. Log buffering already client-side (Zustand). |
| Work order / history (`project:{project_id}`) | Channel `project:{id}:history` | History table subscribes; receives created/updated events. |
| AI streaming (`ai_session:{id}`) | Channel `ai_assistant:*` (exists) | POST a message (REST or channel), stream tokens back. |
| Collaborative editing (Yjs) | Channel `workflow:collaborate:{id}` (exists) | Binary CRDT sync; cannot be REST. Already the decoupled shape. |
| Presence / edit-priority | Channel + `Phoenix.Presence` (exists) | Inherently connection-state; stays. |
| Worker dispatch | `WorkerSocket` (exists, unchanged) | Not the React client. |
| Synchronous webhook response | Server-internal PubSub rendezvous (unchanged) | The webhook caller is external; not a client concern. |

The reads underlying every push flow are independently exposable as REST GETs
(fetch a run, fetch log lines, fetch work orders); the channel only adds the
"and tell me when it changes" layer. This means a surface can be migrated to REST
first (correct but poll-based) and gain its real-time channel second.

## Data ownership & shared database

For this experiment: **one PostgreSQL database, one schema, one OTP app.** Component
B owns all tables; Component A owns none. We deliberately do **not** split the
database. Phase 1 shows why a data split is a separate project: nearly every table
FKs to `projects`, credential project-scoping is a `project_credentials` join (not
a column), `credential_bodies.body` encryption is keyed by a shared vault, and
several context operations are single-DB `Ecto.Multi` transactions across tables
owned by different contexts (the Credentials deletion path nulls `jobs.project_credential_id`
and deletes `project_credentials` in one transaction). Splitting the DB turns those
into distributed transactions. That is the strong-form "separate service" cost, and
it is out of scope here.

## Migration strategy: strangler-fig, not big-bang

The two implementations of the workflow editor already prove the strangler-fig
pattern is viable in this codebase: a new React-over-channel surface
(`collaborate.ex`) runs side by side with the legacy LiveView surface
(`edit.ex`), selected per route. Generalize that: a reverse proxy (or the Phoenix
router itself) routes each surface to either the React SPA or the surviving
LiveView, and surfaces are peeled off one at a time, easiest first. The full
ordered sequence (app shell first, then retire the LiveView-rendered tables) is
evaluated in `docs/migration-analysis.md` §5, grounded in what the Phase 3 slice
reveals.

## Open questions / risks

- **Re-deriving "free" LiveView behaviour.** Server-side pagination, filtering,
  sorting, and policy-scoped queries that LiveViews do inline must become explicit
  API query parameters and authorization guards. This is real work, not a
  translation.
- **API convention debt.** The existing API is internally inconsistent (JSON:API
  for projects/workflows/runs; a flat shape for credentials). The contract must
  pick one (see `docs/api.md`).
- **Real-time fan-out at scale.** LiveView multiplexed everything over one socket
  with server diffing. A channel-per-concern model needs attention to subscription
  lifecycle and payload size (the log-streaming chunking is a good existing model).
- **Auth token lifecycle.** Access/refresh rotation, revocation, and MFA/sudo step-up
  must be designed; today they lean on the session cookie.
- **Collaboration stays channel-based.** The Yjs editor cannot become REST and
  should not try to; the design keeps it on a channel. That is acceptable: it is
  already isolated.
- **One app vs true service split.** This design decouples presentation/transport
  while keeping one backend + one DB. If the goal later becomes independently
  deployable backend services, the Phase 3/4 findings on encryption, cross-context
  transactions, and the `project_credentials` seam are the gating constraints.
