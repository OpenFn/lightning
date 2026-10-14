---
id: flow-toggle-workflow-open-editor
type: flow
title: Switching a workflow on or off while it is open in the editor
status: not-started
owner:

trigger:
  entry: workflows-index
  exit: workflow-editor-canvas
  surfaces:
    - workflows-index
    - capability:workflow-reconciler                      # Lightning.Collaboration.WorkflowReconciler.reconcile_workflow_changes/2 (workflow_reconciler.ex:39-61)
    - pubsub:workflow_events:<project_id>#WorkflowUpdated # broadcast on the same hop; no receiver in lib/ (see 6.3)
    - workflow-editor-canvas
  reachable_when:
    - workflows-index: the viewer may :edit_workflow on the project (index.ex:236, see workflows-index section 3)
    - workflow-editor-canvas: someone has the latest version of the same workflow open, so a SharedDoc named "workflow:<id>" is registered in the :workflow_collaboration :pg scope (workflow_reconciler.ex:42-44, session.ex:172-177)

inherits:
  - shared-project-scope            # who can open either surface; not repeated here

url_params: []

config_variants:
  default: {}                                            # read under this variant
  activation-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(:activate_workflow) returns {:error, _, %Message{}}> }
  experimental-features: { user.preferences.experimental_features: true }   # editor hides its switch and shows a lifecycle badge (Header.tsx:255-258, :700-710)

inventory:
  routes: []                                             # both routes owned by their views
  events:
    - WorkflowLive.Index#toggle_workflow_state           # owned by workflows-index; the hop that starts this flow
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_workflow)   # owned by workflows-index
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - WorkflowReconciler.request_reconciliation/1, reconcile_workflow_document/1, subscribe/1 (workflow_reconciler.ex:63-133); used by the provisioner import path, not by a list switch
    - WorkflowReconciler job and edge operations (workflow_reconciler.ex:213-291); a switch changes only triggers and state

related:
  - lib/lightning_web/live/workflow_live/index.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflows/events.ex
  - lib/lightning/collaboration/workflow_reconciler.ex
  - lib/lightning/collaboration/session.ex
  - lib/lightning/collaboration/workflow_serializer.ex
  - lib/lightning/collaboration/persistence.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - assets/js/collaborative-editor/components/Header.tsx
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts
  - assets/js/collaborative-editor/stores/createSessionContextStore.ts
  - assets/js/collaborative-editor/hooks/useUnsavedChanges.ts
  - test/lightning/collaboration/workflow_reconciler_test.exs
  - test/lightning_web/live/workflow_live/index_test.exs
flows: []
---

## 1. Purpose

An editor switches a workflow on or off from the project's workflow list while a colleague (or
the same person in another tab) has that workflow open in the collaborative editor. The open
editor has to pick up the new trigger state. Otherwise it shows a workflow as running when it was
just stopped, and its next save writes the old trigger state back, silently undoing the switch.

## 2. What it does

Editor clicks a workflow's switch on the list → triggers and state saved → the saved trigger changes are written into the workflow's live Y.Doc → every open editor on the latest version shows the new on/off state, and its next save keeps it.

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-42`, `:160-172` via `index.ex:236` (who may
switch); `workflow_reconciler.ex:39-61` (the reconcile has no actor check of its own: it applies
to every open session on the document).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start the flow (switch from the list) | no | yes | yes | yes | no | yes, when support access is on |
| See the new state in an open editor | yes, if they have it open | yes | yes | yes | n/a | yes, when support access is on |

**Preconditions beyond role**
- The switch must actually save; a refused or failed save never reaches the reconciler (`index.ex:241-267`, `workflows.ex:466-473`).
- Only the latest document `workflow:<id>` is reconciled; version views `workflow:<id>:v<n>` are not (`workflow_reconciler.ex:31-35`, `:42`).
- With nobody holding the document open the reconcile is a logged no-op (`workflow_reconciler.ex:44-48`).

## 4. What it touches

**Reads**: `workflows`, `triggers` (`index.ex:238-240`, `workflows.ex:1439`, `:1482`); the live Y.Doc's `triggers` array and `workflow` map (`workflow_reconciler.ex:305-316`, `:178-211`)

**Writes**
- Hop 1, list: `triggers.enabled`, `workflows.state`, `workflow_snapshots`, `audit_events`, and on switch-on a `workflow_releases` row (owned by workflows-index section 4; `workflows.ex:1437-1443`, `:1480-1486`, `:330-352`)
- Hop 2, reconciler: for every trigger on the workflow, sets `enabled`, `custom_path`, `cron_expression` and `type` on its Y.Map in the live Y.Doc, in one Y.Doc transaction inside `SharedDoc.update_doc/2` (`workflows.ex:1421-1429`, `:1488-1490`, `workflow_reconciler.ex:51-55`, `:182-211`, `:303-316`, `:333-350`)

**Immediate side effects** (in the same request)
- Hop 2a: `WorkflowUpdated` on `workflow_events:<project_id>` (`workflows.ex:514`, `workflows/events.ex:9-14`, `:29`); nothing in lib/ subscribes (see 6.3)
- Hop 2b: reconcile runs after commit, in the list's LiveView process, outside the save's rescue (`workflows.ex:507-527`)
- Hop 3: the Y.Doc update reaches every session observing the SharedDoc and from there each open editor over its workflow channel (`session.ex:121-123`); the editor's `enabled` is re-derived as "any trigger enabled" (`createWorkflowStore.ts:160-162`) and drives the header switch (`Header.tsx:239`, `:700-708`)

**Deferred side effects** (later, elsewhere)
- The next save from the open editor deserializes trigger `enabled` from the Y.Doc, so it persists the reconciled value (`session.ex:507-523`, `workflow_serializer.ex:260-268`)

**External, non-transactional effects**
- none; the Y.Doc write is in memory and happens after the database commit, so a failure there cannot roll the switch back (`workflows.ex:507-512`)

**Depends on config**
- `experimental-features`: the editor shows a Live/Draft badge instead of a switch, and the badge is not refreshed by this flow (see 6.2) (`Header.tsx:255-258`, `:667-690`)
- `activation-limited`: switch-on may be refused before any save (`index.ex:317-327`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Switching a workflow on or off while it is open in the editor
  In order to keep everyone looking at a workflow in agreement about whether it is running
  As an editor switching a workflow from the list
  I want any open editor on that workflow to show the new state

  @S01 @pending
  Scenario Outline: A switch on the list shows in an open editor
    # Value: someone in the editor sees at once that the workflow was stopped or started, instead of a switch that says otherwise.
    Given "Intake" has its webhook trigger <before>
    And "amara@example.org" has "Intake" open in the editor in a second tab
    When I click the "Intake" switch on the workflows list
    Then I see "Workflow updated"
    And eventually the second tab's workflow switch is <after>
    # index.ex:220-248, :317-333; workflows.ex:1437-1443, :1480-1486, :513-527
    # workflow_reconciler.ex:39-55, :303-316, :333-350; session.ex:121-123
    # createWorkflowStore.ts:160-162; Header.tsx:239, :700-708
    # workflow_reconciler_test.exs:403-447 (trigger update op only; no end-to-end test)
    Examples:
      | before   | after |
      | enabled  | off   |
      | disabled | on    |

  @S02 @pending
  Scenario: Saving from the open editor does not undo a switch made on the list
    # Value: unrelated edits saved in an open editor never silently re-enable a workflow someone just switched off.
    Given "Intake" is live with its webhook trigger enabled
    And "amara@example.org" has "Intake" open in the editor
    When I switch "Intake" off on the workflows list
    And "amara@example.org" renames a job and saves
    Then "Intake" still has its trigger disabled
    # workflow_reconciler.ex:303-316; session.ex:507-523; workflow_serializer.ex:260-268

  @S03 @pending
  Scenario: A version view is not changed by a switch on the list
    # Value: someone reviewing an earlier version keeps seeing what that version was.
    Given "amara@example.org" is viewing version 3 of "Intake" in the editor
    When I switch "Intake" off on the workflows list
    Then the version 3 view still shows its trigger as it was in version 3
    # workflow_reconciler.ex:31-35, :42

  @S04 @pending @variant:activation-limited
  Scenario: A switch refused by the plan limit does not reach the open editor
    # Value: an open editor never shows a workflow as on when the limit kept it off.
    Given the usage limiter refuses workflow activation with "No more workflows"
    And "Intake" has its trigger disabled
    And "amara@example.org" has "Intake" open in the editor
    When I click the "Intake" switch on the workflows list
    Then I see "No more workflows"
    And the editor's workflow switch stays off
    # index.ex:250-254, :317-327 (no save, so workflows.ex:513-527 never runs)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The editor's unsaved-changes baseline is refreshed only by a `workflow_saved` channel message, which only editor saves send; after a list switch the Y.Doc trigger `enabled` differs from the stale baseline | `useUnsavedChanges.ts:10`, `:49-53`, `:93-99`; `createSessionContextStore.ts:556-572`; `workflow_channel.ex:856`, `:890` | likely an "unsaved changes" state in the editor for a change that is already saved | fix |
| The reconciler writes `custom_path`, `cron_expression` and `type` with `get_field`, so every trigger gets its database values, not only `enabled` | `workflow_reconciler.ex:310-311`; `workflows.ex:1488-1490` | an unsaved cron expression or webhook path edit in the open editor reverts when someone switches the workflow on the list | fix |
| A trigger deleted in the editor but not yet saved is missing from the Y.Doc; `find_in_array` returns nil and `Yex.Map.set(nil, ...)` is called | `workflow_reconciler.ex:313-316`, `:348`, `:370-375`; `workflows.ex:507-512` (raise is not rescued after commit) | the switch is saved, then something crashes: the list page or the document process (see 6.5) | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `state` (live/draft) is not among the reconciled fields, and no `lifecycle_changed` push is sent, so under experimental features the editor's Live/Draft badge and the channel's lifecycle lock keep the old state. The list only offers this outside sandboxes via a crafted event (see workflows-index 6.2) | `workflow_reconciler.ex:179-188`; `workflow_channel.ex:1173-1196`; `Header.tsx:255-258`, `:667-690` | decide |
| `lock_version` is in the reconciled list, but `optimistic_lock` bumps it only inside the repo, so the Y.Doc keeps the old value; editor saves reload from the database, and a cold start self-heals through `reconcile_or_reset` | `workflow_reconciler.ex:187`; `workflow.ex:98`; `workflow_reconciler_test.exs:527-532`; `session.ex:509-512`; `persistence.ex:114-133` | preserve |
| The reconcile runs synchronously in the list's LiveView process after commit | `workflows.ex:513-527` | preserve |
| The editor's "on" means any trigger enabled; the list's switch uses its own rule (workflows-index 6.1, "three definitions of enabled") | `createWorkflowStore.ts:160-162` | decide |
| Document lookup is through `:pg`, so an editor on another node is reconciled too; the first group member is used | `session.ex:172-177` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `WorkflowUpdated` on `workflow_events:<project_id>` | `workflows/events.ex:9-14`, `:24-26`; `workflows.ex:514` | no subscriber in lib/ (`hooks.ex:15` subscribes `Projects.Events`); only `provisioner_test.exs:1442` asserts it. Listed in surfaces because the lead's scope names it, but it does not carry this flow |
| TODO to message all sessions after a reconcile | `workflow_reconciler.ex:58-59` | not implemented |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| none | | | |

### 6.5 Things seen but not understood

- Yex sources are not in this checkout, so whether `SharedDoc.update_doc/2` runs the function in the SharedDoc process or the caller is unread; that decides which process the 6.1 nil-trigger crash takes down (`workflow_reconciler.ex:51`).
- The list switch captures a new snapshot, but the editor's `latestSnapshotLockVersion` is updated only from `workflow_saved` (`workflow_channel.ex:853-859`, `createSessionContextStore.ts:556-572`); unclear whether the editor then mislabels which version is latest.
- No test drives the list switch through to an open editor; the reconciler test builds its changeset by hand (`workflow_reconciler_test.exs:403-447`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a list switch refresh the editor's saved baseline and lifecycle state, as an editor save does (see 6.1, 6.2)?
- Should the reconciler write only the trigger fields that changed (see 6.1)?
- Should `workflow_events:<project_id>` be removed or given a receiver (see 6.3)?

## Proposed flows

none

## Proposed shared

none
