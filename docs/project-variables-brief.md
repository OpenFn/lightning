# Product Brief: Project Variables

> Status: **Proposal for review** — this is a design proposal grounded in a read of the
> current codebase. Product scope decisions (marked 🔶) should be confirmed by the
> product owner before implementation. This document does not change any behavior.

## 1. Summary

**Project Variables** are project-scoped, named key/value pairs that any workflow in
the project can read at runtime. They fill the gap between two things Lightning already
has:

- **Credentials** — user-owned, adaptor-schema-shaped, one-attached-per-job, meant for
  *authentication*. Wrong shape for "the base URL of the DHIS2 server" or "the current
  reporting period."
- **Collections** — project-scoped key/value, but unencrypted, unbounded operational
  data (dedup keys, cursors) fetched via HTTP from inside job code. Wrong shape for
  *configuration* that should be declared once and vary by environment.

A Project Variable is: *a small piece of project configuration, owned by the project,
that varies between a sandbox and production, and that many workflows share.*

Two flavours:
- **Plain variables** — visible values (API base URLs, org unit IDs, environment names,
  batch sizes, feature flags).
- **Secret variables** 🔶 — encrypted, write-only in the UI, masked in logs (a shared
  API key or signing secret that isn't tied to a specific adaptor credential).

## 2. Why now / the gap

Today, an implementer who wants "one value shared across 12 workflows that differs
between sandbox and prod" has three bad options:

1. Hard-code it into every job body (drifts, error-prone, leaks secrets into snapshots).
2. Abuse a Credential (must invent an adaptor schema, is user-owned so it breaks when the
   user leaves, attaches per-job).
3. Abuse a Collection (unencrypted, requires an HTTP fetch call in job code, not
   environment-aware).

Project Variables give a first-class home for this. **There is already inert scaffolding
for it**: `Lightning.ExportUtils`'s `@ordering_map` reserves a `:globals` key at both the
`project` and `job` level (`lib/lightning/export_utils.ex:20-53`), but nothing in the
codebase populates it. The feature appears to have been anticipated under the name
"globals."

## 3. How it works (mental model)

- A variable belongs to a **project** (not a user, not a workflow).
- A variable is scoped to an **environment**. Lightning already has this concept:
  `Project.env` (default `"main"`) is the label the credential resolver uses to pick which
  encrypted `credential_body` to hand a run (`lib/lightning/credentials/resolver.ex:135-156`).
  Sandboxes carry their own `env`. **Variables reuse this exact mechanism**, so a variable
  automatically resolves to the sandbox value in a sandbox run and the prod value in a
  prod run — no new environment concept required.
- At runtime the resolved variables are handed to the job as a single object,
  recommended `state.globals` (reusing the existing name), e.g. `state.globals.DHIS2_URL`.
- Management lives in **Project Settings → a new "Variables" tab**, mirroring the existing
  Collections tab.

## 4. Design detail

### 4.1 Data model

New table `project_variables` (follows the `keychain_credentials` / `channels` migration
conventions — `binary_id` PK, `project_id` FK `on_delete: :delete_all`, compound unique
index, `timestamps()`):

| column | type | notes |
|---|---|---|
| `id` | `binary_id` | PK |
| `project_id` | `binary_id` FK → projects | `null: false`, `on_delete: :delete_all` |
| `environment` | `string` | default `"main"`; same slug rules as `credential_bodies.name` (`^[a-z0-9][a-z0-9_-]{0,31}$`) |
| `key` | `string` | e.g. `DHIS2_URL`; validated to a safe identifier (`^[A-Z][A-Z0-9_]*$` recommended so it maps cleanly to a JS/object key) |
| `value` | `string` **or** `Lightning.Encrypted.Binary` 🔶 | see 4.2 |
| `secret` | `boolean` | default `false` |
| timestamps | | |

Unique index on `(project_id, environment, key)`. Plain index on `project_id`.

Schema module `Lightning.Projects.ProjectVariable` using the shared `Lightning.Schema`
macro; reverse assoc `has_many :project_variables` on `Project`.

### 4.2 Plain vs secret storage 🔶

Two viable approaches:

- **(A) Single column, always encrypted at rest.** Store `value` as
  `Lightning.Encrypted.Binary` (the same Cloak vault credentials use, `lib/lightning/vault.ex`).
  The `secret` flag only controls UI visibility and log scrubbing. Simplest schema, no
  branching, defence-in-depth for plain values too. Downside: plain values can't be
  read/filtered in SQL, and export must decrypt.
- **(B) Two columns / conditional.** Plain values in a plaintext column, secret values in
  an encrypted column. More faithful to intent, but more code paths and validation.

**Recommendation: (A)** — encrypt everything, let `secret` drive visibility/scrubbing.
Fewer branches, matches the credential precedent, cheap given values are small.

### 4.3 Runtime consumption — the central decision 🔴

The worker (`@openfn/ws-worker`) is an **external repo**. Lightning hands a run its data
over the `run:<id>` Phoenix channel. Today the worker does three pulls: `fetch:plan`
(metadata + credential/dataclip *pointers*, no bodies), `fetch:dataclip` (→ `state.data`),
`fetch:credential` (→ `state.configuration`). See `lib/lightning_web/channels/run_channel.ex`.

Options for getting variables into the job:

- **(1) New `fetch:globals` channel message (recommended).** Parallels `fetch:credential`
  exactly: the worker calls it once per run, Lightning resolves the project's variables for
  the run's environment, seeds the `Scrubber` GenServer with the secret values (so they're
  redacted from logs, exactly as credential secrets are — `run_channel.ex:461-480`), and
  replies with the map. The worker merges it into `state.globals`.
  **Requires a coordinated change in the external ws-worker repo.**
- **(2) Embed in `fetch:plan`.** Add a `"globals"` key to `RunWithOptions.render/1`
  (`lib/lightning_web/channels/run_with_options.ex:21-32`). No extra round-trip, but the
  plan is not scrubbed, so this is only safe for **plain** variables. Also still requires
  the worker to read the new key and merge it. Good fit if v1 is plain-only.
- **(3) HTTP API, Collections-style (no worker change).** Expose
  `GET /projects/:id/variables` behind the existing run-scoped JWT (`authenticated_api`
  pipeline), and read it from job code via an adaptor helper. Zero cross-repo dependency,
  reuses the Collections pattern (`collections_controller.ex`), but worse DX (explicit
  fetch in job code) and no automatic `state.globals`.

**Recommendation: (1) for the real feature; (3) as the fallback if a ws-worker change
can't be scheduled.** Either way, resolve variables at **fetch/run time** (live, current
environment) to match how credentials already behave — *not* frozen into the workflow
snapshot.

### 4.4 Authorization

Follow the `KeychainCredential` precedent (the closest existing project-scoped resource),
`lib/lightning/policies/credentials.ex`:

- Add `:manage_project_variables` to `Lightning.Policies.ProjectUsers` — **owner/admin**
  only (create/edit/delete), same tier as `:create_collection`.
- Reading a **plain** variable's value: any project member (viewer+). Reading/revealing a
  **secret** value: never in the UI (write-only); only the runtime resolver, gated like
  the collections `Run` policy clause — the run's project must match the variable's project
  (`lib/lightning/policies/collections.ex:24-26`).

### 4.5 Audit

Credentials are audited; Collections are **not**. Variables (especially secrets) are
security-relevant config, so audit them like credentials
(`lib/lightning/credentials/audit.ex`): events `created` / `updated` / `deleted`. **Never
record a secret value in the audit `changes` map** — record the key, environment, and
`secret` flag only (plain values may be recorded).

### 4.6 Provisioning / export / GitHub sync 🔶

Wire variables into the shared provisioning pipeline (`lib/lightning/projects/provisioner.ex`
`cast_assoc` + `preload_dependencies/2`) and YAML export (`export_utils.ex`, populating the
already-reserved `:globals` slot). Decision:

- **Plain variables**: export key + value.
- **Secret variables**: export key + `secret: true` but **omit the value** (you cannot put
  a plaintext secret in a YAML file that lands in GitHub). This matches GitHub Actions,
  where secrets are declared but never exported. Importers create the key and expect the
  value to be set out-of-band.

### 4.7 Sandboxes 🔶

Collections clone *names only, never data* into sandboxes (`sandboxes.ex`). For variables,
because they're environment-scoped, the natural behaviour is: a sandbox has its own `env`,
so it simply resolves its own environment's variables. Decision: on sandbox creation, do we
(a) copy the parent's variable **keys** (empty/placeholder values) so the structure is
visible, (b) copy keys **and plain values**, or (c) copy nothing. Recommend **(a)** for
parity with the collections model; secrets never copy.

### 4.8 UI

New `LightningWeb.ProjectLive.VariablesComponent` live_component, rendered from a new
`<:tab hash="variables">` / `<:panel hash="variables">` in
`lib/lightning_web/live/project_live/settings.html.heex`, mirroring the Collections tab
(`settings.html.heex:367-377`). Table of key / environment / secret?, add/edit/delete
modals. Secret values render write-only (never displayed after save; edit replaces).
Compute `can_manage_project_variables` in `settings.ex mount/2` alongside
`can_create_collection`.

## 5. Scope

**v1 (recommended minimum):**
- `project_variables` table + `ProjectVariable` schema + `Lightning.Projects` context CRUD.
- Variables tab in project settings (owner/admin manage).
- Environment-scoped resolution reusing `project.env`.
- Runtime delivery into `state.globals` (option 1 or 2).
- Audit events.

**Defer to v2 (unless product says otherwise):**
- Secret variables (if v1 ships plain-only, the encryption/scrubbing surface disappears and
  runtime delivery can safely use option 2 — a much smaller change). 🔶
- Provisioning/YAML export + GitHub sync + sandbox propagation.
- Job-level variable overrides (the `:globals` scaffolding exists at *job* level too — the
  original vision may have included per-job overrides; out of scope for v1).
- Templating variables into credential bodies / adaptor config (`${VAR}` interpolation).

## 6. Implementation plan

**Phase 1 — Data + context (backend, no user-visible change)**
1. Migration `create_project_variables` (conventions per `keychain_credentials`).
2. `Lightning.Projects.ProjectVariable` schema + changeset (key/env validation, `secret`).
3. `Project` assoc `has_many :project_variables`.
4. Context functions in `Lightning.Projects`: `list_project_variables/2`,
   `upsert_project_variable/2`, `delete_project_variable/1`,
   `resolve_project_variables/2` (project_id + environment → map).
5. Tests (factory + context tests).

**Phase 2 — Authorization + audit**
6. `:manage_project_variables` action in `Lightning.Policies.ProjectUsers`.
7. `Lightning.Projects.VariableAudit` (or reuse) with `created`/`updated`/`deleted`,
   value-redaction for secrets.

**Phase 3 — UI**
8. `VariablesComponent` + Variables tab in project settings.
9. `can_manage_project_variables` wiring in `settings.ex`.
10. LiveView tests.

**Phase 4 — Runtime delivery** (the cross-repo phase)
11. Resolver + `handle_in("fetch:globals", ...)` in `RunChannel` (or `"globals"` key in
    `RunWithOptions.render/1`), seeding the `Scrubber` for secrets.
12. **Coordinate the matching change in `@openfn/ws-worker`** to fetch and merge into
    `state.globals`.
13. Integration test (`test/integration/web_and_worker_test.exs` pattern).

**Phase 5 — Provisioning (v2)**
14. `cast_assoc` in `Provisioner`, preload, populate `:globals` in `ExportUtils`, decide
    secret-omission, sandbox propagation.

## 7. Risky decisions

See the separate summary at the end of the brief. Each is marked 🔴 (high) / 🔶 (medium)
inline above.
