# API Contract: REST

> **Phase 2 deliverable.** The REST API contract the React client would consume:
> conventions, auth, errors, pagination, and per-resource request/response shapes.
> Grounded in the existing `lib/lightning_web/controllers/api/` code; shapes are
> taken from the real `*_json.ex` views and schemas where they exist today.

**Status legend:** ✅ exists today · 🟡 partially exists · 🆕 proposed (designed here, not yet built).

The Phase 3 vertical slice is **Credentials**, so that resource is specified in
full. Other resources are specified to a level sufficient to define the boundary.

---

## 1. Conventions

- **Base path:** `/api`. Introduce explicit versioning for the decoupled contract:
  `/api/v1` (or an `Accept: application/vnd.openfn.v1+json` header). Today there is
  no version segment.
- **Transport:** HTTPS only. `Content-Type: application/json` for request bodies;
  responses are JSON.
- **IDs:** UUID v4 strings (every schema uses `Ecto.UUID`).
- **Timestamps:** ISO 8601 UTC (`inserted_at`, `updated_at`).

### Resolve the JSON-shape inconsistency (decision)

The current API ships **two incompatible response conventions**:

- **JSON:API-style** (`projects`, and the `WorkflowsController`/`RunController`/
  `WorkOrdersController`/`JobController` family) via `LightningWeb.API.Helpers`:
  `{ "data": [ { "type", "id", "attributes", "relationships", "links" } ], "included": [], "links": { self, first, last, next, prev } }`.
- **Flat custom** (`credentials`): `{ "credentials": [ {...} ], "errors": {} }`.

**Decision for the v1 contract: standardize on the JSON:API-style envelope** used
by the majority of resources. It already carries pagination links and relationships,
and it is the dominant existing pattern. Credentials (the flat outlier) is migrated
to the envelope as part of the Phase 3 slice. This document shows credentials in the
**target** envelope; the "today" flat shape is noted inline for reference.

---

## 2. Authentication

All `/api` endpoints (except login and webhook ingress) require
`Authorization: Bearer <token>`. ✅ The bearer mechanism exists today
(`authenticate_bearer` resolves a `User` or a `ProjectRepoConnection`;
`Plugs.ApiAuth` verifies JWTs for `/collections`).

| Endpoint | Status | Purpose |
|---|---|---|
| `POST /api/v1/auth/session` | 🆕 | Exchange email/password (+ TOTP if enabled) for an access token (+ refresh). |
| `DELETE /api/v1/auth/session` | 🆕 | Revoke the current token (logout). |
| `POST /api/v1/auth/session/refresh` | 🆕 | Rotate an access token. |
| `GET /api/v1/auth/me` | 🆕 | Current user + capabilities (replaces `InitAssigns` mount data). |
| `POST /api/v1/auth/totp`, `/auth/sudo`, `/auth/password_reset*`, `/auth/confirm*` | 🆕 | MFA, sudo step-up, password reset, email confirmation (mirror today's controllers). |
| `POST /api/users/register` | ✅ | Self-registration (`RegistrationController`, unauthenticated). |

**Socket auth.** ✅ The React client connects the real-time socket with the same
token: `UserSocket.connect` already verifies a `Phoenix.Token` user-socket token and
assigns `current_user`.

**Authorization.** Enforced per request against Bodyguard policies
(`Lightning.Policies.Permissions.can/4`). ✅ The `api/*` controllers already do this
inline; 🆕 a `RequireProjectAccess` plug should formalize the `:project_scope` check
that LiveView does in `on_mount`.

---

## 3. Errors & status codes

✅ `LightningWeb.FallbackController` already defines the mapping:

| Status | Trigger | Body |
|---|---|---|
| `400 Bad Request` | `{:error, :bad_request}`, `{:error, binary}`, extension `Message` | `{ "error": "<text>" }` or error view |
| `401 Unauthorized` | `{:error, :unauthorized}`, auth failure | `401` error view |
| `403 Forbidden` | `{:error, :forbidden}` (policy denied) | `403` error view |
| `404 Not Found` | `{:error, :not_found}`, missing/invalid-UUID resource | `404` error view |
| `409 Conflict` | `{:error, :conflict}` (e.g. ambiguous collection name) | `{ "error": "<text>" }` |
| `422 Unprocessable Entity` | `{:error, %Ecto.Changeset{}}` | `{ "errors": { "<field>": ["<message>", ...] } }` |

🆕 For the v1 contract, standardize all error bodies on a single envelope:
`{ "errors": [ { "status", "code", "title", "detail", "source": { "pointer" } } ] }`.
The changeset shape (`{ "errors": { field: [msgs] } }`, produced by
`LightningWeb.ChangesetJSON.errors/1`) is the most useful existing form and maps
cleanly onto per-field `source.pointer` entries.

---

## 4. Pagination, filtering, sorting

- **Pagination:** ✅ page-based (Scrivener). `?page=<n>&page_size=<n>`; responses
  carry `links.{first,last,next,prev}` (built by `API.Helpers.pagination_links/2`)
  and should also expose `meta.{page_number,page_size,total_pages,total_entries}`.
- **Filtering:** resource-specific query params. ✅ Work orders already have a rich
  filter model (`Lightning.WorkOrders.SearchParams`: status, date ranges, search
  text, workflow). The contract exposes these as documented query params.
- **Sorting:** 🆕 `?sort=<field>` / `?sort=-<field>` (descending). LiveView list
  views sort in-socket today (`TableHelpers.filter_and_sort`); this moves into the
  query.

---

## 5. Resources

### 5.1 Auth & session

See §2. Returns the authenticated user, role/permission summary, and project
memberships needed to render the app shell.

### 5.2 Projects 🟡

✅ Today: `GET /api/projects` (paginated list), `GET /api/projects/:id`. JSON:API
envelope (real shape from `ProjectJSON`):

```jsonc
// GET /api/v1/projects  → 200
{
  "data": [
    { "type": "projects", "id": "<uuid>",
      "attributes": { "name": "My Project", "description": "..." },
      "relationships": {}, "links": { "self": "/api/projects/<uuid>" } }
  ],
  "included": [],
  "links": { "self": "...", "first": "...", "last": "...", "next": null, "prev": null }
}
```

🆕 To support the app shell and project settings surfaces, add: `POST /api/v1/projects`,
`PATCH /api/v1/projects/:id`, `DELETE /api/v1/projects/:id` (owner-only;
`schedule_deletion` semantics), project-members sub-resource
(`GET/POST/PATCH/DELETE /api/v1/projects/:id/members`), and project provisioning
(✅ `GET /api/provision/yaml`, `POST /api/provision`, `GET /api/provision/:id`
already exist for the `project.yaml` contract).

### 5.3 Credentials (Phase 3 slice, full spec)

Backed by `credentials`, `credential_bodies` (encrypted, per-environment),
`oauth_clients`, `keychain_credentials`, and the `project_credentials` /
`project_oauth_clients` join tables. **Security invariant (✅ enforced today):
credential body values are NEVER returned in any response.** Only metadata and the
*names* of environments are exposed.

#### Resource shape (target JSON:API envelope)

```jsonc
{
  "type": "credentials",
  "id": "<uuid>",
  "attributes": {
    "name": "My API Key",
    "schema": "http",                 // adaptor schema name, or "oauth", or "raw"
    "external_id": null,
    "production": false,
    "environments": ["main", "staging"], // names only; values never exposed
    "transfer_status": null,          // null | "pending" | "completed"
    "scheduled_deletion": null,       // ISO8601 or null
    "inserted_at": "...", "updated_at": "..."
  },
  "relationships": {
    "owner":          { "data": { "type": "users", "id": "<uuid>" } },
    "oauth_client":   { "data": { "type": "oauth_clients", "id": "<uuid>" } | null },
    "projects":       { "data": [ { "type": "projects", "id": "<uuid>" } ] }
  }
}
```

> Today's flat shape (`CredentialJSON`) is:
> `{ "credentials": [ { "id","name","schema","external_id","user_id","project_credentials":[...],"projects":[{ "id","name","description" }],"inserted_at","updated_at" } ], "errors": {} }`.
> It exposes `user_id` directly and the full `project_credentials` join rows. The
> target moves owner/projects into `relationships` and drops the join rows.

#### Endpoints

| Method + path | Status | Auth / policy | Purpose |
|---|---|---|---|
| `GET /api/v1/credentials` | ✅ | bearer; returns caller's own credentials | List own credentials. |
| `GET /api/v1/credentials?project_id=<uuid>` | ✅ | `ProjectUsers :access_project` | List a project's credentials. |
| `GET /api/v1/projects/:project_id/credentials` | ✅ | `ProjectUsers :access_project` | Same, nested form. |
| `GET /api/v1/credentials/:id` | 🆕 | owner or project access | Show one (metadata only). |
| `POST /api/v1/credentials` | ✅ | bearer; project access for each association | Create. |
| `PATCH /api/v1/credentials/:id` | 🆕 | owner | Update name/body/associations/environments. |
| `DELETE /api/v1/credentials/:id` | ✅ | owner (`Users :delete_credential`) | Delete (blocked if in use by workflows). |
| `POST /api/v1/credentials/:id/scheduled_deletion` | 🆕 | owner | Schedule soft deletion. |
| `DELETE /api/v1/credentials/:id/scheduled_deletion` | 🆕 | owner | Cancel scheduled deletion. |
| `POST /api/v1/credentials/:id/transfer` | 🆕 | owner | Initiate transfer to another user. |
| `POST /api/v1/credentials/:id/transfer/confirm` | 🆕 | recipient (token) | Confirm a transfer. |
| `DELETE /api/v1/credentials/:id/transfer` | 🆕 | owner | Revoke a pending transfer. |
| `GET /api/v1/credential_schemas/:name` | 🆕 | bearer | JSON schema descriptor for the dynamic form (replaces server-side field inference). |

**Create request** (✅ today accepts `name` + flat `body` + `project_credentials`;
🆕 target adds multi-environment `bodies` and uses `relationships`-style associations):

```jsonc
// POST /api/v1/credentials
{
  "name": "My API Key",            // required; format ^[a-zA-Z0-9_\- ]*$
  "schema": "http",                // optional; drives validation against the schema
  "external_id": null,             // optional; unique per user
  "bodies": {                       // 🆕 per-environment; "main" required.
    "main":    { "username": "u", "password": "p" },
    "staging": { "username": "u2", "password": "p2" }
  },
  // (✅ older single-env form still accepted: "body": { ... } → stored as "main")
  "project_ids": ["<uuid>", "..."] // 🆕 (today: "project_credentials":[{"project_id"}])
}
```

- `201 Created`, body = the credential resource (metadata only, **never the body**).
- `422` with `{ "errors": { "name": ["..."], "bodies": ["contains too many sensitive keys (...)"] } }`
  on validation failure. (Body complexity cap = `Config.max_credential_sensitive_values`,
  default 50, enforced by `CredentialBody.validate_sensitive_values_count/1`.)
- `403` if the caller lacks `create_project_credential` on any associated project.

**Update request** (`PATCH`): same body; environments present in `bodies` are
upserted, environments omitted that previously existed are deleted (mirrors the
context's `Ecto.Multi` upsert/delete logic). OAuth refresh tokens are preserved
server-side and cannot be set or read by the client.

#### OAuth sub-flow 🆕 (Phase 1 flags this as the hardest part to make stateless)

OAuth credentials store their token inside the encrypted `credential_bodies.body`
(there is no `oauth_tokens` table). The token lifecycle (authorize → exchange →
refresh → revoke) is server-side and security-sensitive. The decoupled contract:

| Method + path | Purpose |
|---|---|
| `GET /api/v1/oauth_clients?project_id=<uuid>` | List OAuth clients available to a project. |
| `POST /api/v1/oauth_clients` | Register an OAuth client (provider endpoints, scopes). `client_secret` is write-only and is **plaintext at rest today** (extraction is the moment to encrypt it). |
| `POST /api/v1/credentials/oauth/authorize_url` | Server builds the provider authorize URL + an encrypted `state`; client opens it in a popup. |
| `GET /api/v1/credentials/oauth/callback` | Provider redirect target; server exchanges the code for a token, stores it encrypted, and notifies the client. |

The browser-popup + encrypted-state round-trip that LiveView does over a
PubSub→`send_update` bridge becomes: popup → callback endpoint → the client is
notified over its real-time channel (`oauth:credential:<request_id>` event) or by
polling `GET /api/v1/credentials/:id`. **This is genuinely awkward over REST and is
analyzed in Phase 3/4 as a "difficult to move" item.**

#### Keychain credentials 🆕

`GET/POST/PATCH/DELETE /api/v1/projects/:project_id/keychain_credentials`
(policy `Credentials :*_keychain_credential`, requires project `owner`/`admin`). A
keychain credential is a JSONPath (`path`) + a `default_credential_id`; the path
must resolve within the project's `project_credentials`.

### 5.4 Workflows / Jobs / Triggers / Edges 🟡

✅ Today: `GET /api/workflows`, `GET /api/workflows/:id`, and nested under a project
`GET/POST /api/projects/:project_id/workflows`, `GET/PUT /api/projects/:project_id/workflows/:id`.
✅ `GET /api/jobs`, `GET /api/projects/:project_id/jobs[/:id]`.

The full workflow document (jobs + triggers + edges + positions) is created/updated
as one nested resource (the editor's save path). **Interactive editing is NOT
REST**: it runs over the `workflow:collaborate:{id}` channel (Yjs). REST covers
list/show/create/replace and non-collaborative saves; the collaboration channel
covers live multi-user editing. Snapshots and `lock_version` optimistic locking are
part of the workflow resource.

### 5.5 Runs / Work Orders 🟡

✅ Today (read-only): `GET /api/work_orders[/:id]`, `GET /api/runs[/:id]`,
`GET /api/log_lines`, all also nested under a project. 🆕 Add the write actions that
are controller/LiveView-only today: `POST /api/v1/projects/:project_id/workflows/:id/runs`
(manual run; ✅ exists as `WorkflowController#create_run`), `POST .../work_orders/:id/retry`,
`POST .../work_orders/retry` (bulk), `POST .../work_orders/cancel` (bulk),
`POST .../runs/:id/retry` (✅ `WorkflowController#retry_run`).

Live run/log updates are delivered over the `run:{id}` channel, not polled (§6).
Bulk retry/cancel are async (Oban) and report completion over the project channel.

### 5.6 Collections ✅

Already a clean REST/streaming API under `/collections` (JWT auth):
`GET /collections/:name` (stream), `GET/PUT/DELETE /collections/:name/:key`,
`POST /collections/:name` (bulk put), `DELETE /collections/:name` (delete all).
No change needed; this is the model the rest of the API should resemble.

---

## 6. Real-time / subscriptions

The client subscribes over Phoenix Channels (token-authenticated `UserSocket`). The
event contract mirrors the existing PubSub topics (see `docs/page-inventory.md`):

| Channel topic | Client subscribes when | Events pushed |
|---|---|---|
| `run:{run_id}` | viewing a run | `run:updated`, `step:started`, `step:completed`, `logs`, `dataclip:updated` |
| `project:{project_id}:history` | viewing History | `work_order:created`, `work_order:updated`, `run:created`, `run:updated` |
| `ai_assistant:{session_id}` | AI chat open | `streaming_chunk`, `streaming_status`, `streaming_changes`, `message_status_changed` |
| `workflow:collaborate:{workflow_id}` | editing a workflow | Yjs binary sync frames; `workflow_saved`; presence diffs |
| `oauth:credential:{request_id}` | mid OAuth popup flow | `oauth:completed` / `oauth:failed` |

**Reads first, real-time second.** Every channel above has a REST GET that returns
the current state (fetch the run, fetch log lines, fetch work orders, fetch the AI
session). A surface can ship correct-but-poll-based on REST alone, then add its
channel subscription for live updates. The only exception is collaborative editing,
which is intrinsically channel-based (Yjs) and has no REST equivalent.
