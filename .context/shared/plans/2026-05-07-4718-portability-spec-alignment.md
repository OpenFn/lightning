# Standardize Project & Workflow Export to Match Portability Spec — Implementation Plan

> Issue: [#4718 Standardize project and workflow export to match portability spec](https://github.com/OpenFn/lightning/issues/4718)
> Branch: `claude/plan-lightning-4718-wx2Rc`
> Issue context: [`.context/shared/issues/issue-4718-standardize-project-workflow-export.md`](../issues/issue-4718-standardize-project-workflow-export.md)

## Overview

Lightning currently emits and consumes a YAML format that does not align with the `@openfn/cli`'s workflow / project format. This plan introduces a versioned format layer ("v2", the CLI-aligned format), switches every Lightning **export** site to v2, makes every **import** site accept both v1 and v2 transparently, and adds a sandbox/parent guard that prevents a sandbox project from claiming the same `(repo, branch)` as any ancestor.

Five user-visible deliverables (the five image bullets):

1. **Canvas Code panel** ("View workflow as code") shows v2 — cascades to canvas Download and Publish-as-Template
2. **Create-new from YAML** accepts v2 (and still accepts v1) — cascades to template picker
3. **Project settings → Export project** emits v2
4. **GitHub sync** speaks v2 (the YAML the CLI pulls/deploys)
5. **Sandbox cannot link to its parent's `(repo, branch)`** — extended to the full ancestor chain

## Current State Analysis

### YAML format today (the "v1" / Lightning format)

Workflow shape produced by `lib/lightning/export_utils.ex:332` (server) and `assets/js/yaml/util.ts:44` (client):

```yaml
name: Foo
jobs:                       # object keyed by hyphenated job name
  job-key:
    id: <uuid>              # only when re-importable; canvas view strips it
    name: Job Name
    adaptor: '@openfn/language-common@latest'
    body: |
      fn(state => state)
    credential: <key>       # optional
    pos: { x: 100, y: 200 } # client-only; server omits
triggers:                   # object keyed by trigger type
  webhook:
    type: webhook
    enabled: true
edges:                      # object keyed by `source->target`
  webhook->job-key:
    source_trigger: webhook
    target_job: job-key
    condition_type: always
    enabled: true
```

Project shape produced by `Lightning.ExportUtils.build_yaml_tree/2` (`lib/lightning/export_utils.ex:332-371`): `name`, `description`, `collections`, `credentials`, `workflows` (all keyed objects, no UUIDs at the project level except where embedded inside workflow-level records).

### Target "v2" / CLI format

Per [kit#1117](https://github.com/OpenFn/kit/issues/1117) and the in-flight portability spec [docs#774](https://github.com/OpenFn/docs/pull/774):

- Top-level `steps:` **array** (replaces `jobs:` object)
- Each step declares its outgoing edges via `next:` (replaces top-level `edges:`)
- Triggers are an **array**, edges from triggers carried via `next:` on each trigger
- Job code field is the CLI's name (likely `expression:`, TBD pending docs#774)
- Project file is **stateless**: no UUIDs, no endpoint, no domain; any "statey" runtime info lives under `.openfn:` keys per kit#1398

> **Spec status:** [docs#774](https://github.com/OpenFn/docs/pull/774) is explicitly a draft. We treat **the @openfn/cli's parser** as the authoritative source for v2 field names. The plan isolates field-level mappings inside one module on each side (Elixir + TS) so finalising the spec is a small follow-up edit.

### Critical constraint: the Provisioner

`Lightning.Projects.Provisioner.import_document/4` (`lib/lightning/projects/provisioner.ex:39-115`) requires every workflow / job / trigger / edge / collection record to carry a UUID `id`. This is non-negotiable: it's how the changeset distinguishes inserts from updates and is how snapshots/audits reference records.

⇒ **v2 imports MUST go through a translation step that injects UUIDs before reaching the Provisioner.** The Provisioner itself does not change.

### GitHub sync coupling

Lightning never writes the workflow `spec.yaml` to GitHub directly (`lib/lightning/version_control/version_control.ex`). It commits two GitHub Actions workflow files (`priv/github/pull.yml`, `priv/github/deploy.yml`). The actual `spec.yaml` round-trips via `openfn/cli-pull-action` and `openfn/cli-deploy-action`. The format coupling lives at:

- **Outbound** (CLI pulls): `Lightning.ExportUtils.generate_new_yaml/2` is what the CLI fetches. Switching this to v2 = GitHub repo content becomes v2.
- **Inbound** (CLI deploys): `Provisioner.import_document` consumes whatever the CLI sends. Adding v2 acceptance = CLI deploys can post v2.

We change those two functions; we do not touch `priv/github/*.yml`.

### Sandbox / parent linking

- `Project` has `belongs_to :parent` (`lib/lightning/projects/project.ex:40`); `sandbox?/1` tests `parent_id` is binary.
- `ProjectRepoConnection` has `repo`, `branch`, `project_id`, with `unique_constraint(:project_id)` only (`lib/lightning/version_control/project_repo_connection.ex:62-69`). **No constraint** prevents a sandbox from claiming its parent's repo+branch pair.
- Connection is created in `VersionControl.create_github_connection/2` (`lib/lightning/version_control/version_control.ex:33-51`); the user picks repo and branch in `github_sync_component.html.heex:107-145`.

## Desired End State

- `mix test` and `cd assets && npm test` pass
- Exporting a workflow from anywhere in Lightning produces a v2 YAML byte-for-byte equivalent to what `@openfn/cli` writes
- Importing either a v1 or v2 workflow YAML produces an identical `Workflow` record set (verified by round-trip + golden-file tests)
- Existing `WorkflowTemplate` rows (v1) still load via the template picker; new templates published from the canvas write v2
- A user cannot save a `ProjectRepoConnection` for a sandbox whose `(repo, branch)` matches any ancestor's; LiveView form surfaces the conflict before submit
- GitHub sync of an existing project succeeds end-to-end after the change (verified manually against a test repo)

### Key Discoveries

- `convertWorkflowStateToSpec(state, includeIds=false)` (`assets/js/yaml/util.ts:44`) already strips IDs — the canvas Code panel uses it. The v2 work parallels this idiom: `serializeWorkflowV2(state)` is a sibling, not a replacement.
- `Provisioner.import_document` requires UUIDs (`lib/lightning/projects/provisioner.ex:7-9`, `:74`). v2 import flows MUST run through `Lightning.Workflows.YamlFormatV2.to_provisioner_doc/2` first.
- `assets/js/yaml/schema/workflow-spec.json` is the AJV schema currently used for v1 import. v2 needs its own schema next to it.
- `ExportUtils.generate_new_yaml/2` is the **single point** of outbound YAML — used by `Projects.export_project/3`, the workflow Download button, and the GitHub-sync-pull. Replacing its body is the largest leverage point.
- `WorkflowTemplate.code` is plain text. `parseWorkflowTemplate(code)` (`assets/js/yaml/util.ts:321`) is the single read path — adding format detection there covers all template consumers.
- `Project.sandbox?/1` and the existing `ancestors/1` walker (`lib/lightning/projects/sandboxes.ex:242-249`) give the chain we need for the v5 guard.

## What We're NOT Doing

- **Not designing the v2 spec.** Field names like `steps`/`next`/`expression` track the CLI; the in-flight `docs#774` may rename things — those edits land in the format-translation module only.
- **Not modifying `@openfn/cli`** (lives in OpenFn/kit, separate repo).
- **Not touching `priv/github/pull.yml` or `priv/github/deploy.yml`.** Those reference external action versions; format alignment happens via what Lightning serves to / accepts from the CLI.
- **Not migrating existing data.** `WorkflowTemplate` rows stay as v1 in the DB. Detection happens at read time.
- **No format toggle.** Per user direction: **export is v2 only**; **import accepts both** v1 and v2.
- **No DB unique constraint on `(repo, branch)`.** Different sandboxes legitimately share a repo on different branches; the guard is changeset-level.
- **Not changing Y.Doc schema.** Workflow state in collaborative editor stays as-is; v2 only matters at the YAML serialization boundary.
- **Not addressing** the `reconfigure_github_connection` no-op-persist bug surfaced by the analyzer (`version_control.ex:55-67`). Logging here as a follow-up.

## Implementation Approach

Six phases. Phases 1–3 are pure additions (scaffolding + format implementation + tests) with no user-visible change — safe to ship behind a no-op feature switch. Phases 4–6 wire those primitives into the user-facing flows. The two surfaces (Elixir, TS) get parallel modules so each can be tested independently.

```
                  ┌─────────────────────────────┐
                  │ Phase 1: Translation layer  │   add YamlFormatV2 modules
                  │   (Elixir + TS scaffolds)   │   (no behavior change)
                  └──────────────┬──────────────┘
                                 │
                  ┌──────────────▼──────────────┐
                  │ Phase 2: Workflow v2 impl   │   serialize/parse round-trip
                  │   + format detector         │
                  └──────────────┬──────────────┘
                                 │
                  ┌──────────────▼──────────────┐
                  │ Phase 3: Project v2 impl    │   stateless, .openfn keys
                  │   + Provisioner adapter     │
                  └──────────────┬──────────────┘
                                 │
        ┌────────────────────────┼─────────────────────┐
        ▼                        ▼                     ▼
┌───────────────┐       ┌───────────────┐      ┌────────────────┐
│Phase 4: Export│       │Phase 5: Import│      │Phase 6: Sandbox│
│  cutover (v2) │       │ accept v1+v2  │      │ ancestor guard │
└───────────────┘       └───────────────┘      └────────────────┘
```

Phases 4–6 are independent; can land in any order.

---

## Phase 1: Scaffolding — Versioned Format Layer

**Implementation Agent**: `phoenix-elixir-expert` (Elixir side) and `react-collab-editor` (TS side).

### Overview
Introduce skeleton modules with explicit contracts, no behavior change yet. This makes phases 2–3 small, focused diffs.

### Changes Required

#### 1. New Elixir module: format façade
**File**: `lib/lightning/workflows/yaml_format.ex` (new)

Public API — single entry point used by every other Elixir caller:

```elixir
defmodule Lightning.Workflows.YamlFormat do
  @moduledoc """
  Single boundary between Lightning's runtime structs and YAML files.
  Knows about format versions; delegates to YamlFormatV1 or YamlFormatV2.

  Outbound (export) writes V2 only.
  Inbound (parse) auto-detects V1 vs V2.
  """

  alias Lightning.Workflows.YamlFormatV1
  alias Lightning.Workflows.YamlFormatV2

  @type format_version :: :v1 | :v2
  @type parsed_doc :: %{format: format_version(), doc: map()}

  # Outbound
  @spec serialize_workflow(Workflow.t()) :: {:ok, binary()}
  @spec serialize_project(Project.t(), [Snapshot.t()] | nil) :: {:ok, binary()}

  # Inbound
  @spec parse_workflow(binary()) :: {:ok, parsed_doc()} | {:error, term()}
  @spec parse_project(binary()) :: {:ok, parsed_doc()} | {:error, term()}
  @spec detect_format(map() | binary()) :: format_version()

  # Bridge to provisioner — injects UUIDs where the doc lacks them
  @spec to_provisioner_doc(parsed_doc(), Project.t() | nil) :: map()
end
```

**File**: `lib/lightning/workflows/yaml_format/v1.ex` (new) — wraps existing `ExportUtils.generate_new_yaml`. Just an extraction, no logic change.

**File**: `lib/lightning/workflows/yaml_format/v2.ex` (new) — empty stubs returning `{:error, :not_implemented}`. Filled in Phase 2.

#### 2. New TS façade
**File**: `assets/js/yaml/format.ts` (new)

```typescript
export type FormatVersion = 'v1' | 'v2';
export type ParsedDoc = { format: FormatVersion; spec: WorkflowSpec };

export const serializeWorkflow = (state: WorkflowState): string => /* v2 */;
export const parseWorkflow = (yamlString: string): ParsedDoc => /* auto */;
export const detectFormat = (parsed: unknown): FormatVersion;
```

**File**: `assets/js/yaml/v1.ts` (new) — extract today's `convertWorkflowStateToSpec` / `convertWorkflowSpecToState` / `parseWorkflowYAML` here unchanged.

**File**: `assets/js/yaml/v2.ts` (new) — stubs throwing `Error("v2 not yet implemented")`. Filled in Phase 2.

#### 3. Move existing util.ts re-exports

`assets/js/yaml/util.ts` becomes a thin pass-through that re-exports `format.ts` symbols, so existing call sites compile unchanged.

### Success Criteria

#### Automated:
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes (no behavior change)
- [ ] `cd assets && npm test` passes
- [ ] `cd assets && npx tsc --noEmit --project ./tsconfig.browser.json` passes

#### Manual:
- [ ] Diff review confirms no callers changed; only file moves + new empty modules

---

## Phase 2: Workflow v2 — serialize, parse, detect

**Implementation Agent**: `phoenix-elixir-expert` and `react-collab-editor`. Each side independently testable.

### Overview
Implement the v2 workflow YAML in both languages. Round-trip tests against shared golden fixtures guarantee Elixir and TS produce identical bytes for the same input.

### Changes Required

#### 1. Elixir: `Lightning.Workflows.YamlFormatV2`
**File**: `lib/lightning/workflows/yaml_format/v2.ex`

Key responsibilities:
- `serialize_workflow(workflow)` builds the `steps:` array with inline `next:` from the workflow's edges
- `parse_workflow(yaml)` validates structure (steps array, each step's `next:` references known step ids), returns canonical map
- `detect_format(parsed)` — heuristics: `steps:` present + `jobs:` absent ⇒ `:v2`; `jobs:`/`triggers:`/`edges:` triple ⇒ `:v1`; ambiguity ⇒ `:v1` (legacy bias) with a warning logged

Field mapping (initial — all marked `# TBD docs#774` and confined to this module):

| v1 (Lightning) | v2 (CLI) |
|---|---|
| `jobs[key].name` | `steps[].name` |
| `jobs[key].body` | `steps[].expression` |
| `jobs[key].adaptor` | `steps[].adaptor` |
| `triggers[type]` | `triggers[]` (still keyed in spec? confirm) |
| `edges[k].source_trigger`/`source_job` + `target_job` + `condition_type` | `next:` on source step/trigger |
| `condition_expression` (js_expression edges) | `next:` value as object with `condition`/`expression` |

#### 2. TS: `assets/js/yaml/v2.ts`

Mirror of the Elixir module. Add an AJV schema:

**File**: `assets/js/yaml/schema/workflow-spec-v2.json` (new) — declares `steps`/`triggers` as arrays, validates `next:` shape.

#### 3. Shared golden fixtures
**Directory**: `test/fixtures/yaml_format_v2/`

For each scenario, two files — `*.v1.yaml` and `*.v2.yaml` — that represent **the same workflow** in both formats. Used by both Elixir and JS tests:

- `simple-webhook.v{1,2}.yaml`
- `cron-with-cursor.v{1,2}.yaml`
- `js-expression-edge.v{1,2}.yaml`
- `multi-trigger.v{1,2}.yaml`
- `kafka-trigger.v{1,2}.yaml`
- `branching-jobs.v{1,2}.yaml`

#### 4. Tests

**Elixir** — `test/lightning/workflows/yaml_format_v2_test.exs`:
- For each fixture: `parse_workflow(v2)` ⇒ canonical map; serialize the canonical map ⇒ matches `v2.yaml` byte-for-byte (after key-ordering normalization)
- `detect_format` returns `:v2` for v2 fixtures, `:v1` for v1 fixtures
- Round-trip property test: build a `Workflow` via factories, serialize v2, parse v2, build provisioner doc, re-import, compare workflow shape

**JS** — `assets/js/yaml/v2.test.ts`:
- Round-trip: `WorkflowState → serializeV2 → parseV2 → state` matches input
- Cross-language equivalence: Elixir-produced YAML in fixture parses to the same `WorkflowSpec` as JS-produced YAML

### Success Criteria

#### Automated:
- [ ] `mix test test/lightning/workflows/yaml_format_v2_test.exs` passes
- [ ] `cd assets && npm test -- v2` passes
- [ ] Property round-trip suite covers all six fixtures
- [ ] AJV schema rejects malformed v2 (missing `steps:`, dangling `next:` reference)

#### Manual:
- [ ] Take a v2 YAML emitted by `@openfn/cli` against a real workflow; paste into `parseWorkflowYAML` ⇒ no errors
- [ ] Reverse: a v2 YAML emitted by Lightning round-trips through `@openfn/cli` without errors

---

## Phase 3: Project v2 — stateless serialization + Provisioner adapter

**Implementation Agent**: `phoenix-elixir-expert`.

### Overview
Project-level YAML must be statelessly portable per kit#1398 — no UUIDs in the canonical body, optional `.openfn:` block carrying ephemeral state. Adds the bridge that lets the existing Provisioner consume v2 docs.

### Changes Required

#### 1. Project serialization
**File**: `lib/lightning/workflows/yaml_format/v2.ex`

Add `serialize_project(project)`:
- Flatten `name`, `description`, `collections`, `credentials`, `workflows` (each workflow inlined as v2 workflow)
- Strip every `id:` UUID field; instead use stable hyphenated names as map keys / step ids (already the convention)
- Produce optional trailing `.openfn:` block carrying `{ project_id, endpoint }` so a re-import can correlate (the CLI will populate this on first deploy)

#### 2. Provisioner adapter
**File**: `lib/lightning/workflows/yaml_format.ex`

`to_provisioner_doc(parsed_doc, existing_project)`:
- Walk every record (project / workflow / job / trigger / edge / collection)
- For each, look up the existing UUID by `(parent, name)` against `existing_project`; if not found, generate a new UUID
- Emit a doc shaped exactly like Provisioner's current input

Key rule: **the converter is the only place that maps "stable name → UUID"**. The Provisioner itself remains UUID-required.

#### 3. Tests
**File**: `test/lightning/workflows/yaml_format_project_v2_test.exs`

- Serialize a fixture project → v2 → parse v2 → `to_provisioner_doc` against same project → `Provisioner.import_document` → assert no diff
- Stateless property: serialize project A, write to disk, mutate project A's UUIDs in DB, parse same YAML, import — assert workflow names/edges match (UUIDs reassigned correctly via name lookup)
- `.openfn:` round-trip: presence of the block does not change semantic content

### Success Criteria

#### Automated:
- [ ] `mix test test/lightning/workflows/yaml_format_project_v2_test.exs` passes
- [ ] Cross-project round trip (export project A → import into a fresh empty project → exported YAML byte-equal modulo `.openfn:`) passes

#### Manual:
- [ ] Export a real project, manually delete the `.openfn:` block, re-import into a clean DB — succeeds and produces the same workflow set

---

## Phase 4: Export Cutover — every export site emits v2

**Implementation Agent**: `phoenix-elixir-expert` + `react-collab-editor`.

### Overview
With the format layer in place, switch every outbound YAML producer to v2. No fallback, no toggle.

### Changes Required

#### 1. Server-side single-source replacement
**File**: `lib/lightning/export_utils.ex`

Replace the body of `generate_new_yaml/2` (`:422-456`) with `Lightning.Workflows.YamlFormat.serialize_project/2`. Keep the public arity/signature unchanged — every caller (`Projects.export_project/3`, GitHub-sync's serve-to-CLI path) inherits v2 transparently.

Decision point: **delete `ExportUtils` ordering / yaml-stringify helpers** (the bespoke `to_new_yaml` recursion), since v2 uses the standard YAML library. Keep `ExportUtils` as a thin façade for backwards-compat callers, or remove and update callers — leaning toward remove.

#### 2. Canvas Code panel
**File**: `assets/js/collaborative-editor/components/inspector/CodeViewPanel.tsx:23-44`

Replace `convertWorkflowStateToSpec(state, false) → YAML.stringify` with `serializeWorkflow(state)` from `assets/js/yaml/format.ts`. This single change drives:
- The textarea content (1a in image)
- The Download button payload (1a — uses the same textarea via `DownloadText` hook in `lib/lightning_web/live/workflow_live/edit.ex:885-892`)
- Publish-as-template payload (1b — `TemplatePublishPanel.tsx:99-127` uses the same converter)

#### 3. Publish-as-template
**File**: `assets/js/collaborative-editor/components/inspector/TemplatePublishPanel.tsx:99-111`

Same swap. The backend `WorkflowTemplate.code` column receives v2 going forward; old rows stay as v1 (handled in Phase 5).

#### 4. Project export endpoint
**File**: `lib/lightning_web/controllers/downloads_controller.ex:10-31`

No code change needed — calls `Projects.export_project/3` which calls the now-v2 serializer. Update the response filename suggestion if appropriate (`project-<id>.yaml` is fine).

#### 5. Documentation/feature copy
- Update any in-app help text referencing the format
- Update `assets/js/collaborative-editor/components/left-panel/YAMLImportPanel.tsx` placeholder/example to show v2 syntax

### Success Criteria

#### Automated:
- [ ] All export-related tests updated (v1 → v2 fixtures): `mix test test/lightning/export_utils_test.exs`, etc.
- [ ] `cd assets && npm test` passes (CodeViewPanel, TemplatePublishPanel test snapshots regenerated)

#### Manual:
- [ ] Open a workflow, View as Code → output is v2
- [ ] Click Download → file is v2
- [ ] Project Settings → Export Project → file is v2
- [ ] Publish as template → re-open the published template via picker → loads identically
- [ ] Trigger a GitHub sync push → resulting commit on the repo contains v2 YAML

---

## Phase 5: Import Acceptance — both v1 and v2

**Implementation Agent**: `phoenix-elixir-expert` + `react-collab-editor`.

### Overview
Every parse path detects format and dispatches. Provisioner-side imports route through the UUID-injection bridge.

### Changes Required

#### 1. JS YAML import panel (image #2)
**File**: `assets/js/yaml/util.ts:278-331` (and the underlying `parseWorkflowYAML` / `parseWorkflowTemplate`)

Replace direct AJV-against-v1-schema with:

```ts
export const parseWorkflowYAML = (yamlString: string): WorkflowSpec => {
  const parsed = YAML.parse(yamlString);
  const fmt = detectFormat(parsed);
  if (fmt === 'v2') return parseWorkflowV2(parsed);
  return parseWorkflowV1(parsed);
};
```

`parseWorkflowTemplate` gets the same treatment — covers image #2a (template picker) and the canonical/base templates already in the DB as v1.

#### 2. Server-side provisioner imports
**File**: `lib/lightning_web/controllers/api/provisioning_controller.ex` (and any `ProjectRepoConnection`-driven import path)

Where the controller currently passes the parsed YAML map to `Provisioner.import_document/4`, route through `YamlFormat.parse_project` then `YamlFormat.to_provisioner_doc/2` first.

CLI deploys via the GitHub action ⇒ same code path, same v1/v2 acceptance. **No change needed in `priv/github/*.yml`.**

#### 3. Template picker auto-detect
**File**: `assets/js/yaml/TemplateToWorkflow.ts` and `assets/js/collaborative-editor/components/left-panel/TemplatePanel.tsx`

Both use `parseWorkflowTemplate` — auto-detect inherits.

#### 4. Update existing fixtures conservatively
- Keep `test/fixtures/canonical_project.yaml` (v1) as the v1 regression fixture
- Add `test/fixtures/canonical_project.v2.yaml` with the same workflows in v2

### Success Criteria

#### Automated:
- [ ] Existing `Provisioner` test suite passes (v1 documents still import)
- [ ] New tests: import v2 doc → workflow records identical to v1-imported equivalent
- [ ] `assets/js/yaml/util.test.ts` covers detection + dispatch
- [ ] `assets/js/collaborative-editor/components/left-panel/YAMLImportPanel.test.tsx` updated for both formats

#### Manual:
- [ ] Drag a v1 YAML file into the import panel → succeeds
- [ ] Drag a v2 YAML file into the import panel → succeeds
- [ ] Pick an existing template (stored as v1) → loads correctly
- [ ] Publish a new template (writes v2) → pick that template later → loads correctly

---

## Phase 6: Sandbox / Parent Repo Guard

**Implementation Agent**: `phoenix-elixir-expert`.

### Overview
A sandbox cannot share a `(repo, branch)` pair with any project on its ancestor chain. Cheap check on connection create/update; LiveView form surfaces it inline.

### Changes Required

#### 1. Changeset validation
**File**: `lib/lightning/version_control/project_repo_connection.ex:62-69`

Add a custom validator invoked by both `create_changeset/2` and `configure_changeset`:

```elixir
defp validate_no_ancestor_branch_conflict(changeset) do
  with {:ok, project_id} <- fetch_change(changeset, :project_id) || fetch_field(changeset, :project_id),
       {:ok, repo}       <- fetch_field(changeset, :repo),
       {:ok, branch}     <- fetch_field(changeset, :branch),
       project           <- Lightning.Projects.get_project!(project_id),
       ancestor_ids      <- Lightning.Projects.ancestor_ids(project) do
    if Repo.exists?(
         from c in __MODULE__,
           where: c.project_id in ^ancestor_ids,
           where: c.repo == ^repo,
           where: c.branch == ^branch
       ) do
      add_error(changeset, :branch,
        "this branch is already linked to a parent project; sandboxes must use a different branch")
    else
      changeset
    end
  end
end
```

`Lightning.Projects.ancestor_ids/1` — new helper next to `ancestors/1` in `lib/lightning/projects/sandboxes.ex:242-249`, returns a list of UUID strings (no Project structs needed).

#### 2. Context-level guard (defense in depth)
**File**: `lib/lightning/version_control/version_control.ex:33-51`

Add a `with` clause in `create_github_connection` that runs the same query before insert and returns `{:error, :branch_used_by_ancestor}` — protects against direct API callers bypassing the form.

#### 3. LiveView form
**File**: `lib/lightning_web/live/project_live/github_sync_component.ex:149-173`

In `validate_changes/2`, when both repo and branch are set on a sandbox project, query for ancestor conflict and add a validation error to the assigned changeset. The existing template at `github_sync_component.html.heex:123-145` will render the error next to the branch selector with no template change needed.

Disable the Save button while the conflict error is present.

#### 4. Tests
- `test/lightning/version_control/project_repo_connection_test.exs` — changeset rejects (repo, branch) matching parent's
- `test/lightning/version_control/project_repo_connection_test.exs` — multi-level ancestor: grandparent uses (X, main), grandchild sandbox attempting same — rejected
- `test/lightning_web/live/project_live/github_sync_component_test.exs` — form surfaces error inline; Save disabled
- `test/lightning_web/live/project_live/github_sync_component_test.exs` — non-sandbox project (parent_id nil) is unaffected

### Success Criteria

#### Automated:
- [ ] All new tests pass
- [ ] Existing `version_control_test.exs` regression suite passes (non-sandbox flows unchanged)

#### Manual:
- [ ] Create sandbox of project P (linked to repo X, branch `main`)
- [ ] Try to link sandbox to (X, `main`) → form shows error, Save disabled
- [ ] Link sandbox to (X, `dev`) → succeeds
- [ ] Link sandbox to (Y, `main`) → succeeds (different repo)
- [ ] Sandbox-of-sandbox: grandchild attempting grandparent's (repo, branch) → error

---

## Testing Strategy

### Unit Tests
- Per-format serialize/parse round-trip (Phases 2–3)
- AJV schema validation of v2 (Phase 2)
- Provisioner adapter UUID injection idempotency (Phase 3)
- Format detection edge cases — empty doc, partial doc, doc with both `steps:` and `jobs:` (Phase 5)
- Sandbox ancestor walk (Phase 6)

### Integration Tests
- `Provisioner.import_document` against both v1 and v2 fixtures (Phase 5)
- `WorkflowTemplate` round trip: publish-as-template (writes v2) → load-from-template (parses v2) → identical state (Phases 4 + 5)
- GitHub sync end-to-end against a test repo using `Tesla.Mock` for the GitHub API: deploy a v2 project, pull it back, verify identity (Phases 4 + 5)

### Manual Testing Steps
1. Open a workflow with cron + webhook + js-expression edges; click View as Code; copy the YAML; confirm it pastes into a v1-stripped `@openfn/cli` deploy and runs
2. Take a known v1 workflow YAML from a customer repo; drag-drop into Create New from YAML; confirm import succeeds
3. Take a v2 YAML written by `@openfn/cli`; drag-drop into Create New from YAML; confirm import succeeds and produces equivalent records
4. Publish a workflow as a template; immediately load it via the template picker; expect identical canvas
5. Configure GitHub sync on a sandbox attempting parent's repo+branch; expect inline error
6. Configure GitHub sync on a sandbox using a different branch on the parent's repo; expect success

## Performance Considerations

- Format detection adds one extra YAML parse pass (we must parse before we can detect). Mitigation: detect on the already-parsed map, not on the raw string. No round-trip overhead.
- Sandbox ancestor query is at most O(depth) DB queries on the projects table; depth is small in practice. Single recursive CTE could replace the walker but isn't worth it at this scale.
- The Provisioner adapter does a `(name → UUID)` lookup per record. For projects with thousands of jobs this is O(n) DB hits unless we batch — preload existing project workflows once at the entry point.

## Migration Notes

- **No DB migration.** All format detection happens at read time.
- **WorkflowTemplate rows** stay as v1 in `code` column. New `publish_template` writes v2. The format detector at parse time handles both.
- **GitHub repos** in customer organizations will continue to contain v1 YAML committed by older CLI runs. The next deploy after this lands re-writes them as v2 when they're pulled and re-pushed by the action. No proactive migration.
- **Existing Lightning installations** importing a project YAML via the provisioning API see no behavior change for v1 inputs.

## Out-of-band Follow-ups (Not in scope)

- Finalize the v2 field names once `docs#774` lands; localized edits to `yaml_format/v2.ex` + `assets/js/yaml/v2.ts` + the AJV schema only
- Coordinate with `@openfn/cli` (kit) maintainers to ensure the CLI emits / accepts the same v2 shape
- Fix `reconfigure_github_connection` no-op-persist bug (`version_control.ex:55-67`) — separate ticket
- Consider: deprecate v1 export entirely after a release cycle (currently kept as legacy *internal* path only — public surface is already v2-only)
