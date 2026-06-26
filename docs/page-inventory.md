# Page & Route Inventory

> **Phase 1 deliverable.** A map (not a migration) of every LiveView / page /
> route in `openfn/lightning` and the backend logic each depends on: contexts,
> Ecto schemas/queries, Oban jobs, PubSub topics, authorization policies, and
> stateful socket assigns / channel behaviour.
>
> Derived directly from the code on branch `claude/lightning-decoupling-experiment-o3f0rd`.
> Difficulty ratings here feed the Phase 4 "Difficult to move" analysis.

## How to read this document

1. **The big picture** orients you: the auth model, the four runtime surfaces
   (LiveView, REST controllers, WebSocket channels, Oban), and the one part of
   the app that is *already* shaped like the decoupled target.
2. **Route map** is the authoritative router breakdown (pipelines, live_sessions,
   routes, and the existing REST API).
3. **Surface-by-surface inventory** is the heart: each user-facing feature area
   with its modules, contexts, schemas, socket state, PubSub, real-time
   behaviour, policies, and a decoupling-difficulty rating.
4. **Cross-cutting backend layers** is the reference appendix: the context
   catalogue, schema relationships, the full Oban/PubSub/channel/policy/presence
   catalogues that the surfaces draw on.
5. **Decoupling difficulty ranking** synthesizes the hot-spots.

Difficulty legend (how cleanly a surface maps to a stateless REST request/response):
🟢 clean CRUD · 🟡 CRUD + some stateful/async glue · 🟠 significant real-time/async coupling · 🔴 inherently connection-oriented (CRDT/presence/push).

---

## The big picture

Lightning today is a **Phoenix LiveView monolith** with four distinct runtime surfaces sharing one codebase, one database, and one supervision tree:

- **LiveView** (`lib/lightning_web/live/`, ~122 files, ~26 routed pages): the entire interactive UI. State lives server-side in `socket.assigns`; the browser holds a thin DOM synced over the LiveView WebSocket.
- **Controllers** (`lib/lightning_web/controllers/`): classic request/response for auth flows, downloads, webhooks, and **an already-existing JSON REST API** under `controllers/api/`.
- **Channels** (`lib/lightning_web/channels/`, 5 channels over 2 sockets): worker dispatch, run/log streaming, the collaborative editor (Yjs), and AI streaming.
- **Oban** (`lib/lightning/**/*_worker.ex` + cron): background jobs. Note that **run execution is NOT Oban** (it is pull-based; see below).

**Two auth models coexist:**
- *Browser/LiveView:* session cookie → `current_user`, resolved at LiveView **mount** by `on_mount` hooks (`LightningWeb.InitAssigns`, then `LightningWeb.Hooks.:project_scope`). Authorization is woven into the LiveView lifecycle, not a request plug.
- *API/Worker:* bearer tokens. `/api` uses `authenticate_bearer` resolving a `User` or `ProjectRepoConnection`; `/collections` uses JWT via `LightningWeb.Plugs.ApiAuth`; workers use a `WORKER_SECRET`-signed JWT plus per-run scoped tokens.

**The decoupling exemplar already in the tree.** The workflow editor exists in
*two* implementations: the legacy LiveView editor (`workflow_live/edit.ex`, ~3800
lines, heavily coupled) and the **new collaborative editor** (`workflow_live/collaborate.ex`),
which is a thin LiveView shell mounting a React island whose real logic runs over
`WorkflowChannel` + a server-side Y.Doc (`Lightning.Collaboration.Session`). The
collaborative editor is, in effect, what a decoupled surface looks like already:
React client + channel/RPC + CRDT, with the LiveView reduced to a mount point.
This is the most important single observation in the inventory.

---

## Route map

### Pipelines (the auth backbone)

| Pipeline | Key plugs | Enforces |
|---|---|---|
| `:browser` | `fetch_session`, `protect_from_forgery`, `fetch_current_user`, `Plugs.FirstSetup`, `Plugs.BlockRoutes` | HTML session + CSRF; loads `current_user`; blocks signup when disabled |
| `:api` | `accepts(["json"])` | JSON only, no auth (used by webhooks + registration) |
| `:authenticated_api` | `accepts(["json"])`, `Plugs.ApiAuth` | Bearer JWT (via `Lightning.Tokens.verify`) |
| `:authenticated_json` | `fetch_session`, `protect_from_forgery`, `fetch_current_user` | JSON with browser-session auth (cookie + CSRF) |

Custom plugs used inline: `authenticate_bearer` (resolves `User`/`ProjectRepoConnection` into `:current_resource`), `require_authenticated_api_resource`, `require_authenticated_user`, `require_superuser`, `reauth_sudo_mode` + `require_sudo_user` (time-limited sudo tokens).

### live_session blocks (LiveView mount-time auth)

| live_session | on_mount | Used by |
|---|---|---|
| `:auth` | `InitAssigns` | sudo re-auth page |
| `:sudo_auth` | `InitAssigns`, `UserAuth.ensure_sudo` | backup-codes pages |
| `:settings` | `InitAssigns` | admin lists (`/settings/**`) |
| `:default` | `InitAssigns` | the main app (`/projects/**`, `/credentials`, `/profile/**`) |
| `:services` | from config | extension routes injected by downstream apps |

`InitAssigns` loads `current_user` from the session token, sidebar prefs, and banners. Project-scoped routes additionally run `LightningWeb.Hooks.:project_scope`, which does the `Permissions.can?(ProjectUsers, :access_project, …)` check **inside mount** and assigns `project`/`project_user`.

### Routed LiveView pages (condensed; all under `:require_authenticated_user`)

| Path | Module | live_session |
|---|---|---|
| `/projects` (`/`) | `DashboardLive.Index` | `:default` |
| `/projects/:project_id/w` | `WorkflowLive.Index` | `:default` (project scope) |
| `/projects/:project_id/w/new`, `/w/:id` | `WorkflowLive.Collaborate` (new editor) | `:default` |
| `/projects/:project_id/w/new/legacy`, `/w/:id/legacy` | `WorkflowLive.Edit` (legacy editor) | `:default` |
| `/projects/:project_id/jobs` | `JobLive.Index` | `:default` |
| `/projects/:project_id/history`, `/history/channels` | `RunLive.Index` | `:default` |
| `/projects/:project_id/runs/:id` | `RunLive.Show` | `:default` |
| `/projects/:project_id/runs/:run_id/.../dataclips/:id/show` | `DataclipLive.Show` | `:default` |
| `/projects/:project_id/settings*` | `ProjectLive.Settings` | `:default` |
| `/projects/:project_id/sandboxes*` | `SandboxLive.Index` | `:default` |
| `/projects/:project_id/channels*` | `ChannelLive.Index` | `:default` |
| `/projects/:project_id/history/channels/:id` | `ChannelRequestLive.Show` | `:default` |
| `/credentials` | `CredentialLive.Index` | `:default` |
| `/profile`, `/profile/tokens`, `/profile/auth/backup_codes` | `ProfileLive.Edit`, `TokensLive.Index`, `BackupCodesLive.Index` | `:default`/`:sudo_auth` |
| `/settings`, `/settings/users*`, `/settings/projects*`, `/settings/audit`, `/settings/authentication*`, `/settings/collections` | `SettingsLive.Index`, `UserLive.*`, `ProjectLive.Index`, `AuditLive.Index`, `AuthProvidersLive.Index`, `CollectionLive.Index` | `:settings` |
| `/auth/confirm_access`, `/first_setup`, `/mfa_required` | `ReAuthenticateLive.New`, `FirstSetupLive.Superuser`, `ProjectLive.MFARequired` | `:auth`/`:default` |

### Non-LiveView controllers

Auth/session: `UserSessionController`, `UserRegistrationController`, `UserConfirmationController`, `UserResetPasswordController`, `UserTOTPController`, `OidcController`, `OauthController`, `BackupCodesController`, `CredentialTransferController`.
Data/files: `DownloadsController` (`/download/yaml`), `CollectionsController#download`, `DataclipController`, `ProjectFileController`, `WorkflowController` (`create_run`/`get_run_steps`/`retry_run`), `VersionControlController`.
Ingress: `WebhooksController` (`POST/GET /i/*path`).

### The existing REST API (`scope "/api"`, bearer auth)

| Method + path | Controller#action |
|---|---|
| `POST /api/users/register` | `RegistrationController#create` (unauthenticated) |
| `GET /api/provision/yaml`, `GET /api/provision/:id`, `POST /api/provision` | `ProvisioningController` |
| `GET /api/projects`, `GET /api/projects/:id` | `ProjectController` |
| `GET /api/credentials`, `POST /api/credentials`, `DELETE /api/credentials/:id` | `CredentialController` |
| `GET /api/projects/:project_id/credentials` | `CredentialController#index` |
| `GET/POST /api/projects/:project_id/workflows`, `GET/PUT .../workflows/:id`, `GET /api/workflows*` | `WorkflowsController` |
| `GET /api/jobs*`, `GET /api/projects/:project_id/jobs*` | `JobController` |
| `GET /api/work_orders*`, nested under project | `WorkOrdersController` |
| `GET /api/runs*`, nested under project | `RunController` |
| `GET /api/log_lines` | `LogLinesController` |
| `GET /api/ai_assistant/sessions` | `AiAssistantController` (cookie/`authenticated_json`) |
| `GET/PUT/POST/DELETE /collections/:name[/:key]` | `CollectionsController` (`:authenticated_api`) |

All `api/*` controllers already use the `with :ok <- Permissions.can(...)` + `action_fallback LightningWeb.FallbackController` pattern, with `*_json.ex` view modules. **This is the seed of the decoupled backend.**

---

## Surface-by-surface inventory

Each block lists: modules · contexts · schemas touched · genuine server-side state · PubSub · real-time/channels · policies · difficulty.

### 1. Dashboard / Projects list 🟢

- **Modules:** `dashboard_live/{index,components,user_projects_section,project_creation_modal}.ex`, `book_demo_banner.ex`.
- **Contexts:** `Projects` (list/create), `Accounts` (banner gating).
- **Schemas:** `projects`, `project_users`.
- **Server state:** thin; sort key/direction in the `UserProjectsSection` component. Rendered data only.
- **PubSub / real-time:** none (could subscribe to `projects_events:all`).
- **Policies:** `ProjectUsers :access_project` per card.
- **Difficulty:** 🟢 straight CRUD + sort.

### 2. Workflow editor / canvas 🔴 (legacy) / 🟠 (collaborative)

The hardest surface, and the most important. Two implementations:

- **Legacy `workflow_live/edit.ex` (🔴):** server holds the authoritative `changeset` + `workflow_params` for the unsaved draft and reconciles with the client via a **bidirectional JSON-patch loop** (`handle_event("push-change", %{patches})` → apply → rebuild changeset → `{:reply, %{patches: delta}}`). Selection/mode/run-follow/version are encoded in the URL as a **state machine**. Writes are gated on **Phoenix Presence edit-priority** (`Workflows.Presence`), not just the authenticated user. Heavy `push_event`→JS-hook imperatives, `jsx`-embedded React (`WorkflowEditor.tsx` etc.), optimistic-lock/snapshot versioning intertwined with socket state.
- **Collaborative `workflow_live/collaborate.ex` (🟠):** thin shell; draft lives in a server-side **Y.Doc** owned by `Collaboration.Session`, synced as binary Yjs frames over `WorkflowChannel`. The LiveView holds almost no editor state. Reference data (`request_credentials`, `request_adaptors`, `get_context`, templates) is async RPC over the channel that *would* map to REST GETs.
- **Sub-components (🟡):** `editor_pane.ex` (Monaco + `Task.start`/`send_update` for adaptor metadata), `job_live/{adaptor_picker,credential_picker,cron_setup_component,kafka_setup_component}.ex` (parent/child changeset-fragment coordination via `phx-target={@myself}` + `on_change` closures), `webhook_auth_method_*` modals, `github_sync_modal.ex` (`assign_async`).
- **Contexts:** `Workflows` (+`Snapshot`, `Presence`, `WorkflowTemplates`), `Invocation` (manual-run dataclips/steps), `Runs` (follow run), `WorkOrders` (`Manual`, retry, `limit_run_creation`), `VersionControl`, `AiAssistant`, `Credentials`, `OauthClients`, `Projects`; also direct `Repo` (flagged as TODO) and `AdaptorRegistry`.
- **Schemas:** `workflows`, `jobs`, `triggers`, `workflow_edges`, `workflow_snapshots`, `workflow_versions`, `webhook_auth_methods`; reads `dataclips`/`steps`/`runs`.
- **PubSub:** subscribes `workflow_events:{project_id}`, `run_events:{run_id}`, `ai_session:{session_id}`; the channel subscribes `project:{project_id}` (history panel) and broadcasts `workflow_saved`, `credentials_updated`, applying-state to peers.
- **Real-time:** Presence edit-lock; Y.Doc CRDT; channel binary sync; PubSub-driven `handle_info`.
- **Policies:** `:create_workflow`/`:edit_workflow`/`:access_read` (re-checked mid-session in the channel so role changes take effect).
- **Difficulty:** legacy 🔴 (CRDT-like patching + presence + RPC-over-socket); collaborative 🟠 (genuinely connection-oriented, but already isolated behind a channel). Pure core `workflow_params.ex` (JSON-patch ↔ changeset) and the serializers are portable.

### 3. Runs & Work Orders / History 🟠

- **Modules:** `run_live/{index,show,run_viewer_live,streaming,workorder_component,channel_logs_component,rerun_job_component,export_confirmation_modal,cancel_helper,components}.ex`, `dataclip_live/{show,form_component}.ex`. `streaming.ex` (a `__using__` macro) is the real-time core shared by `show` + `run_viewer_live`.
- **Contexts:** `Invocation` (`search_workorders/2,3` paginated+filtered, `export_workorders`, `get_dataclip!`), `WorkOrders` (`subscribe`, retry/`retry_many`, `cancel_many[_async]`, `SearchParams`), `Runs` (`get`, `subscribe`, `get_log_lines` → `Repo.stream`, `cancel_run`), `Workflows`, `Accounts`, `Channels`; direct `Repo.preload(force: true)`.
- **Schemas:** `work_orders`, `runs`, `steps`, `run_steps`, `dataclips`, `log_lines`.
- **Server state:** `filters`/`filters_changeset` (canonical query, mirrored to URL but mutated in socket); `selected_work_orders` **bulk-selection set** (no URL form, lost on reconnect); `page.entries` **mutated in place** by PubSub handlers; `run`/`steps` accumulated live. Notably **no LiveView `stream/3`** anywhere.
- **PubSub:** `project:{project_id}` (`WorkOrderCreated/Updated`, `RunCreated/Updated`) and `run_events:{run_id}` (`StepStarted/Completed`, `RunUpdated`, `LogAppended`, `DataclipUpdated`).
- **Real-time:** the distinctive **log streaming**: `Runs.get_log_lines` returns `Repo.stream`; inside `assign_async` a transaction does `Stream.chunk_every(100)` → `send(pid, {:log_line_chunk, …})` → `handle_info` → `push_event("logs-{run_id}")`; the actual **log buffer lives client-side in a Zustand store** (`assets/js/log-viewer/store.ts`), not the server. Live tail lines arrive via `LogAppended` → same `push_event`.
- **Policies:** `:run_workflow`, `:edit_data_retention`, dataclip `:view_dataclip`.
- **Difficulty:** 🟠 reads are REST-able; the in-place PubSub-patched collections + chunked log push + filter-coupled live admission need SSE/websocket + client-side assembly.

### 4. Credentials 🟠 (the Phase 3 slice)

- **Modules:** `credential_live/{index,credential_index_component,credential_form_component(~1500 lines),generic_oauth_component,oauth_client_form_component,keychain_credential_form_component,transfer_credential_modal,json_schema_body_component,raw_body_component,oauth_error_formatter,helpers}.ex`, `components/{credentials,oauth,credential_deletion_modal}.ex`.
- **Contexts:** `Credentials` (CRUD, keychain CRUD, transfer, schema-driven validation via `Schema`/`SchemaDocument`, OAuth token helpers, `OauthValidation`), `OauthClients`, `Projects`, `Accounts` (transfer recipients), `Workflows` (`project_workflows_using_credentials` for warn-before-unshare), `AuthProviders.OauthHTTPClient` (outbound OAuth).
- **Schemas:** `credentials`, `credential_bodies` (**`body` is `Lightning.Encrypted.Map`, the only secret store**), `oauth_clients` (**`client_secret` is plaintext**), `keychain_credentials`, `project_credentials`, `project_oauth_clients`. There is **no `oauth_tokens` table**: OAuth tokens live inside the encrypted `credential_bodies.body`.
- **Server state:** in-progress **OAuth flow** state machine (`oauth_progress`, in-memory `oauth_token` rendered as a hidden input until submit, `userinfo`, `selected_scopes`); multi-page wizard `page` enum (no URLs); schema-driven dynamic form (`schema`, `touched_body_fields` MapSet); multi-environment body buffer (`%{env => body}`); project-association buffer diffed at save.
- **PubSub:** `oauth_credential:{socket.id}` bridges the OAuth HTTP callback back into the LiveView via the **`{:forward, mod, opts}` → `send_update`** pattern (`OauthCredentialHelper` + `OidcController`). No other broadcast (saves use `push_navigate` + re-read).
- **Real-time:** no channels/Presence/Y.Doc; "real-time" = LiveView `start_async`/`handle_async` token fetch + the PubSub-bridged popup callback.
- **Policies:** `Users :edit_credential/:delete_credential` (ownership), `Credentials :*_keychain_credential` (`[:owner,:admin]`).
- **Difficulty:** 🟠 plain CRUD/transfer/deletion/list are clean; the OAuth popup + encrypted-state + PubSub→`send_update` loop and the server-side schema-driven dynamic form are the coupled parts. (Full extraction analysis in Phase 3.)

### 5. Project settings 🟠

- **Modules:** `project_live/{settings,form_component,collaborators,invite_collaborator_component,invited_collaborators,new_collaborator_component,github_sync_component,concurrency_input_component,collections_component,mfa_required}.ex`, `components/project_deletion_modal.ex`.
- **Contexts:** `Projects` (project + project-user CRUD, files, sandbox detection), `Credentials`, `VersionControl` (`subscribe`, repo connection CRUD/sync), `Workflows` (count for delete guard), `WebhookAuthMethods`, `Accounts`.
- **Schemas:** `projects`, `project_users`, `project_repo_connections`, `project_files`, `webhook_auth_methods`.
- **Server state:** `permissions` map (many `can_*` booleans), changesets, collaborator-invite buffers, `active_modal` flags; GitHub component holds `AsyncResult` for branch verification.
- **PubSub:** `version_control_events:{user_id}` + the GitHub OAuth `{:forward}`→`send_update` bridge (same family as credentials).
- **Policies:** 11 distinct `ProjectUsers` checks (edit/delete project, add/remove members, alerts, data retention, github connection/sync, etc.). Notable: **view-extension slots** let downstream apps inject LiveComponents via route metadata.
- **Difficulty:** 🟠 collaborator/project CRUD is clean; GitHub-connect OAuth flow + extension slots are LiveView-coupled.

### 6. Settings / Profile (current user) 🟡

- **Modules:** `profile_live/{edit,form_component,mfa_component,github_component,experimental_features_component,components}.ex`, `backup_codes_live/index.ex`, `tokens_live/index.ex`, `components/{user_deletion_modal,token_deletion_modal}.ex`.
- **Contexts:** `Accounts` (user update, MFA/TOTP, backup codes, API tokens, prefs), `VersionControl` (GitHub link).
- **Schemas:** `users`, `user_tokens`, `user_totps`, `user_backup_codes`.
- **Server state:** changesets; one-time `new_token` display held in socket; MFA enrollment secret/QR state.
- **PubSub:** `version_control_events:{user_id}` (`OauthTokenAdded/Failed`).
- **Policies:** `Users :delete_account/:delete_api_token` (ownership).
- **Difficulty:** 🟡 CRUD-able except the GitHub-link OAuth callback and the MFA enrollment handshake (stateful multi-step).

### 7. Project workspace: Sandboxes, Channels 🟡

- **Modules:** `sandbox_live/{index,form_component,components}.ex`, `channel_live/{index,form_component,helpers}.ex`, `channel_request_live/{show,components,helpers,timing}.ex`. (Here "Channels" = data-ingestion channels, **not** Phoenix Channels; experimental-feature gated.)
- **Contexts:** `Projects` + `Projects.Sandboxes`, `VersionControl` (sandbox merge), `Channels`, `DashboardStats`.
- **Schemas:** `projects` (sandbox = project fork), `channels` + `channel_*` sub-tables.
- **Server state:** sandbox merge accumulates a **selection set** of workflows/credentials in `socket.assigns` (lost on reconnect).
- **Difficulty:** 🟡 CRUD + server-accumulated selection (would need explicit ID lists over REST).

### 8. Collections 🟢

- **Modules:** `collection_live/{index,collection_creation_modal,components}.ex`, `project_live/collections_component.ex`.
- **Contexts:** `Collections` (list/create/delete). **Schemas:** `collections`, `collection_items`.
- **Difficulty:** 🟢 admin CRUD; per-project view re-checks `Collections :access_collection`. (The collection *data API* at `/collections/*` is already REST.)

### 9. Users / Admin (superuser & admin-space) 🟢

- **Modules:** `project_live/index.ex` (all-projects admin), `user_live/{index,edit,form_component,table_component,components}.ex`, `audit_live/index.ex`, `auth_providers/{index,form_component}.ex`.
- **Contexts:** `Accounts`, `Projects`, `Auditing` (`list_all/1` paginated), `AuthProviders`.
- **Schemas:** `users`, `projects`, `audit_events`, `auth_providers`.
- **Server state:** lists + sort/filter/`page`; audit renders structured diffs (and embedded encrypted credential bodies) as server-side HEEx.
- **Policies:** `Users :access_admin_space` (superuser).
- **Difficulty:** 🟢 mostly clean; only `send_update`/parent-pid messaging between auth-provider form and host.

### 10. AI Assistant 🟠

- **Modules:** `ai_assistant/{component(~1690 lines),mode_behavior,mode_registry,modes/job_code,modes/workflow_template,error_handler,pagination_meta,quotes}.ex`, `workflow_live/workflow_ai_chat_component.ex`. Host page is the workflow editor; backend transport is `AiAssistantChannel` + the `MessageProcessor` Oban worker.
- **Contexts:** `AiAssistant` (sessions/messages, `query`/`query_stream`), `AiAssistant.Limiter` → `Services.UsageLimiter`, `Accounts`, `Workflows`, `Projects`, `Invocation` (logs/dataclips for context).
- **Schemas:** `ai_chat_sessions`, `ai_chat_messages`.
- **Server state:** `pending_message` (`AsyncResult`, flipped by PubSub, not a local task); authoritative message state lives in the DB + the Oban worker, not the socket.
- **PubSub:** `ai_session:{session_id}` carries `:streaming_chunk`/`:streaming_status`/`:streaming_changes`/`:streaming_error`/`:message_status_changed`. The component cannot subscribe itself (shares the parent process), so the host LiveView subscribes and routes via a `session_id ⇒ component_id` registry + `send_update`.
- **Real-time:** request side is already async-via-Oban (REST-friendly); token streaming needs SSE/websocket. Two transport contracts on one topic: whole-message (LiveView) vs token stream (channel → React).
- **Difficulty:** 🟠 POST-a-message + SSE-the-reply is close to what the topic already does.

### 11. Auth pages 🟢

- **Modules:** `re_authenticate_live/new.ex` (sudo re-auth), `first_setup_live/superuser.ex`, `account_confirmation_modal.ex`, plus the controllers listed above.
- **Contexts:** `Accounts` (sudo token, TOTP/password validation, superuser registration).
- **Difficulty:** 🟢 close to form-POST semantics; translate to REST readily.

---

## Cross-cutting backend layers (reference)

### Context catalogue

| Context | File | Owned schemas (→ table) | Purpose |
|---|---|---|---|
| `Projects` | `projects.ex` | `Project`→projects, `ProjectUser`→project_users, `ProjectCredential`→project_credentials, `ProjectOauthClient`→project_oauth_clients, `File`→project_files | Top-level org unit; membership; sandboxes; provisioning; digests; scheduled deletion |
| `Credentials` | `credentials.ex` | `Credential`→credentials, `CredentialBody`→credential_bodies, `KeychainCredential`→keychain_credentials, `OauthClient`→oauth_clients | External-service auth; encrypted bodies; OAuth lifecycle. **Also an `Oban.Worker`** (`purge_deleted` cron) |
| `OauthClients` | `oauth_clients.ex` | (operates on Credentials schemas) | OAuth client CRUD + project association |
| `Workflows` | `workflows.ex` | `Workflow`→workflows, `Job`→jobs, `Trigger`→triggers, `Edge`→workflow_edges, `Snapshot`→workflow_snapshots, `WorkflowVersion`→workflow_versions, `WorkflowTemplate`, `WebhookAuthMethod`→webhook_auth_methods | DAG definition; snapshots with `lock_version`; scheduling; templates |
| `Jobs` | `jobs.ex` | (operates on `Workflows.Job`) | Thin query helpers over jobs |
| `Accounts` | `accounts.ex` | `User`→users, `UserToken`→user_tokens, `UserTOTP`→user_totps, `UserBackupCode`→user_backup_codes | Users, auth, sessions/tokens, MFA. **Oban worker** (`purge_deleted`) |
| `Invocation` | `invocation.ex` | `Dataclip`→dataclips, `Step`→steps, `RunStep`→run_steps, `LogLine`→log_lines | Execution data: dataclips, steps, logs |
| `WorkOrders` | `work_orders.ex` | `WorkOrder`→work_orders, `Manual` (embedded) | Top-level execution requests; retries; cancellations |
| `Runs` | `runs.ex` | `Run`→runs, `RunOptions` (embedded) | Worker-facing run lifecycle |
| `Collections` | `collections.ex` | `Collection`→collections, `Item`→collection_items | Project-scoped KV store |
| `AiAssistant` | `ai_assistant/ai_assistant.ex` | `ChatSession`→ai_chat_sessions, `ChatMessage`→ai_chat_messages | AI chat; Apollo; streaming |
| `VersionControl` | `version_control/version_control.ex` | `ProjectRepoConnection`→project_repo_connections | GitHub connections, sync/PR |
| `KafkaTriggers` | `kafka_triggers.ex` | `TriggerKafkaMessageRecord`→trigger_kafka_message_records | Kafka consumer pipelines + dedupe |
| `AuthProviders` | `auth_providers.ex` | `AuthConfig`→auth_providers | SSO/OIDC config + shared OAuth HTTP client |
| `UsageTracking` | `usage_tracking.ex` | `Report`, `DailyReportConfiguration` | Anonymous usage submission (cron) |
| `Auditing` | `auditing.ex` | `Audit`→audit_events | Append-only audit trail (polymorphic actor) |
| `Collaboration` | `collaboration.ex` | `DocumentState`→collaboration_document_states | Yjs CRDT persistence |
| `Channels` | `channels.ex` | `Channel`, `ChannelAuthMethod`, `ChannelEvent`, `ChannelRequest`, `ChannelSnapshot` | Data-ingestion "channels" (≠ Phoenix Channels) |

### Schema relationships (the boundary tables)

```
users ──< credentials (user_id) ; users ──< oauth_clients (user_id) ; users ──< project_users
projects ──< project_users (role) ; projects ──< workflows ; projects ──< collections ; ...
projects ──< project_credentials  ──> credentials      (M:N projects↔credentials)
projects ──< project_oauth_clients ──> oauth_clients    (M:N projects↔oauth_clients)
workflows ──< jobs ──< (workflow_edges) >── triggers ; workflows ──< snapshots ──< versions
credentials ──< credential_bodies (1:N, per-environment ENCRYPTED body)
oauth_clients ──< credentials (credentials.oauth_client_id, nullable)
jobs ──> project_credentials (jobs.project_credential_id, nullable)   ← the only credential↔execution link
jobs ──> keychain_credentials (jobs.keychain_credential_id, nullable)
```

**Tables that FK to `projects`:** project_users, project_credentials, project_oauth_clients, project_files, project_repo_connections, workflows, collections, keychain_credentials, webhook_auth_methods, ai_chat_sessions, channels (+ sub-tables), dataclips. Runs/work_orders reach projects transitively via workflows. **Key seam:** credentials have no `project_id`; project scope is entirely the `project_credentials` join.

### Encryption at rest (Cloak, via `Lightning.Vault`)

- `credential_bodies.body` → `Lightning.Encrypted.Map` (the secret store; includes OAuth tokens).
- `users.github_oauth_token` → `Encrypted.Map`; `user_backup_codes.code` → `Encrypted.Binary`.
- `webhook_auth_methods.{username,password,api_key}` and Kafka trigger config username/password → `Encrypted`.
- `audit_events` metadata re-encrypts credential bodies (so the audit store also holds secret blobs).
- **Not encrypted today:** `oauth_clients.client_secret` (plaintext).

### Oban workers (queues: scheduler 1, workflow_failures 1, background 1, history_exports 1, ai_assistant 10, search_indexing 2)

> **Run execution is NOT Oban.** Runs are dispatched pull-based: workers `claim` rows via `WorkerChannel` → `Lightning.Runs.Queue.claim` (`FOR UPDATE SKIP LOCKED`). The `Services.RunQueue`/`FifoRunQueue` behaviour is the pluggable enqueue side.

| Worker | Queue | Trigger | Class |
|---|---|---|---|
| `WorkOrders.RetryManyWorkOrdersJob` | scheduler | History bulk retry | user-facing |
| `WorkOrders.CancelManyWorkOrdersJob` | scheduler | History bulk cancel | user-facing |
| `WorkOrders.ExportWorker` | history_exports | History export | async download |
| `AiAssistant.MessageProcessor` | ai_assistant | AI new/retry message | streams LLM via PubSub |
| `Workflows.Scheduler` | scheduler | cron `* * * * *` | creates cron-trigger work orders |
| `KafkaTriggers.DuplicateTrackingCleanupWorker` | background | cron `*/10` | dedupe prune |
| `UsageTracking.{DayWorker,ReportWorker,ResubmissionCandidatesWorker,ResubmissionWorker}` | background | cron | usage reports |
| `DigestEmailWorker` | background | cron daily/weekly/monthly | project digests |
| `Accounts.UserNotifier` | background | inline | transactional email |
| `ObanPruner` | background | cron `* * * * *` | prune Oban jobs |
| `Janitor` | background | cron `*/5` | mark lost runs |
| `Accounts`/`Credentials`/`Projects`/`WebhookAuthMethods` (`purge_deleted`/`data_retention`) | background | cron | soft-delete purge + retention |
| `LogLines.SearchVectorWorker`, `Invocation.DataclipSearchVectorWorker` | search_indexing | cron, self-chaining | tsvector backfill |

Oban is already stateless/DB-backed and survives decoupling unchanged; only **result delivery** (MessageProcessor, bulk WorkOrder jobs) is client-coupled via PubSub.

### PubSub topics (all via `Lightning.broadcast/2` on `Lightning.PubSub`)

| Topic | Events | Broadcaster → Subscriber |
|---|---|---|
| `run_events:{run_id}` | `StepStarted/Completed`, `RunUpdated`, `LogAppended`, `DataclipUpdated` | Runs context → RunChannel (browser) + Run viewer LiveView |
| `project:{project_id}` | `WorkOrderCreated/Updated`, `RunCreated/Updated` | WorkOrders → History LiveView + editor history panel |
| `all_events` | `RunCreated` | WorkOrders → `WorkListener` (worker `work-available` nudge) |
| `workflow_events:{project_id}` | `WorkflowUpdated` | Workflows → editor/index LiveViews |
| `ai_session:{session_id}` | streaming `:*` + `:message_status_changed` | MessageProcessor → AiAssistantChannel + editor |
| `work_order:{id}:webhook_response` | `{:webhook_response, status, body}` | RunChannel → **WebhooksController (blocks on `receive`)** |
| `workflow:collaborate:{id}` | `credentials_updated`, `webhook_auth_methods_updated`, applying-state | collaborate LiveView/AiChannel → WorkflowChannel peers |
| `projects_events:all`, `users:all` | `ProjectCreated/Deleted`, `UserRegistered` | admin LiveViews |
| `version_control_events:{user_id}` | `OauthTokenAdded/Failed` | VCS GitHub callback → project settings/profile |
| `kafka_trigger_updated` | `KafkaTriggerUpdated`, `…NotificationSent` | Kafka LiveViews |
| `oauth_credential:{socket.id}` | OAuth completion (`{:forward,…}`) | OidcController → credential form LiveView |

Real-time UI flows have no stateless REST equivalent without polling/SSE; each load-bearing topic (`run_events`, `project`) is consumed by **both** a LiveView and a channel, so any decoupling must preserve a publish boundary a React client can subscribe to. The `webhook_response` topic is a synchronous request/response rendezvous (the inverse of stateless).

### Channels (5 channels, 2 sockets)

- **`UserSocket`** (`Phoenix.Token` user token): `WorkflowChannel` (`workflow:collaborate:*`, Yjs CRDT + async reference-data RPC + history fan-in), `RunChannel` browser path (subscribe `run_events` → push), `AiAssistantChannel` (`ai_assistant:*`, enqueue Oban + push streaming).
- **`WorkerSocket`** (`WORKER_SECRET` JWT): `WorkerChannel` (`worker:queue`, `claim` loop + `WorkerPresence` capacity + a linked `WorkListener` GenServer), `RunChannel` worker path (run lifecycle RPC: `fetch:plan/credential/dataclip`, `step:*`, `run:log`, holds a stateful `Scrubber` process per run).

### Authorization (Bodyguard)

Entry point `Lightning.Policies.Permissions.can/4` + `can?/4`. Modules: `ProjectUsers` (the core membership policy, ~25 actions by role owner/admin/editor/viewer + support-user cross-access), `Users` (admin space, account/token/credential ownership), `Workflows`, `Credentials` (keychain), `Collections`, `Dataclips`, `Exports`, `Provisioning`, `Sandboxes`. **Policies are pure functions of `(action, actor, resource)`** with no socket/process state, so they are the most portable layer. The friction is *where* they run: today much authorization lives in LiveView `on_mount` (`:project_scope`) and inline `handle_event` checks, not a request plug. The `api/*` controllers already model the portable pattern (`with :ok <- Permissions.can(...)` + `action_fallback`).

### Presence & collaborative state (the 🔴 core)

- **`Workflows.Presence`** (`Phoenix.Presence`, topic `workflow-{id}:presence`): tracks editors and computes **edit-priority** (first-joined non-view-only user with ≤1 session may save). No stateless analogue.
- **`WorkerPresence`** (topic `workers:presence`): per-worker `capacity`; `total_worker_capacity/0` sums across the cluster.
- **Server-side Yjs** (`lib/lightning/collaboration/`): per document a `DocumentSupervisor` starts a `Yex.Sync.SharedDoc` (the in-memory CRDT, registered in `:pg` group `:workflow_collaboration` for cluster-wide discovery) + a `PersistenceWriter` (debounced batch writes of CRDT updates/checkpoints to `collaboration_document_states`). Per connected editor a `Session` GenServer (`:temporary`, monitors the channel pid) bridges channel↔SharedDoc, tracks Presence, and serializes the Y.Doc back to a `Workflow` (with `lock_version`) on save. `WorkflowSerializer`/`WorkflowResolver`/`Persistence` are the portable pieces; the live shared CRDT is not.

---

## Decoupling difficulty ranking (synthesized; feeds Phase 4)

From hardest to easiest to put behind a stateless REST API:

1. **🔴 Server-side Yjs/Y.Doc collaboration** (`collaboration/*`, `WorkflowChannel` yjs handlers): live CRDT + `:pg` replication; effectively cannot be stateless. (But the new collaborative editor already isolates this behind a channel + React island.)
2. **🔴 Worker dispatch** (`WorkerChannel` + `WorkListener` + `WorkerPresence` + run-scoped JWTs): pull-based push loop with presence-derived capacity.
3. **🔴 Presence / edit-priority** (`Workflows.Presence`): pure connection state.
4. **🟠 Real-time run/log/history streaming** (`run_events:*`, `project:*` → RunChannel/LiveView): needs SSE/websocket; the underlying *reads* are REST-able.
5. **🟠 Synchronous webhook-response rendezvous** (`work_order:*:webhook_response`): request blocks on a PubSub `receive`.
6. **🟠 AI streaming** (`ai_session:*`, `AiAssistantChannel`, `MessageProcessor`): request side already async/REST-friendly; only the token stream needs SSE.
7. **🟡 Legacy workflow-editor JSON-patch loop** (`workflow_live/edit.ex`): superseded by the collaborative editor.
8. **🟡 OAuth callback bridges** (`{:forward,…}`→`send_update` in Credentials/Project Settings/Profile): popup callback can't return to the originating tab.
9. **🟢 Oban workers**: already stateless/DB-backed; only result delivery is client-coupled.
10. **🟢 Bodyguard policies**: pure functions; most portable layer.
11. **🟢 The bulk of admin/list/CRUD surfaces** (Dashboard, Projects/Users/Audit/AuthProviders, Collections, Sandboxes, Auth pages, credential/project CRUD): standard CRUD + in-socket sort/filter + modal routing.

**The single most useful finding:** the app *already contains* a worked example of the decoupled target (the collaborative editor: thin LiveView shell + React island + channel/RPC + Y.Doc), and *already contains* a REST API skeleton (`controllers/api/*` with policies + JSON views). A decoupling effort is less a greenfield rewrite than an extension of two patterns already in the tree.
