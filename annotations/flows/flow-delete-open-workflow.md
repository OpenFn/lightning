---
id: flow-delete-open-workflow
type: flow
title: Deleting a workflow that someone has open
status: not-started
owner:

trigger:
  entry: workflows-index
  exit: workflows-index                     # in the other session's tab
  surfaces:
    - workflows-index
    - pubsub:project_events:<project_id>#WorkflowDeleted
    - workflow-editor-canvas
    - workflows-index
  reachable_when:
    - deleting side: viewer may `:delete_workflow` (index.ex:93-99, :289, project_users.ex:39-42, :166-172)
    - receiving side: a LiveView mounted with `{LightningWeb.Hooks, :ensure_workflow_belongs_to_project}` on that workflow's id (collaborate.ex:26, health.ex:11, hooks.ex:138-151)

inherits:
  - shared-project-scope            # receiving end is S12 (hooks.ex:320-341); this flow only asserts the handoff

url_params: []

config_variants:
  default: {}                       # read under this variant; nothing on either hop reads config

inventory:
  routes:
    - live /projects/:project_id/w  WorkflowLive.Index :index           # owned by workflows-index
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit  # owned by workflow-editor-canvas
    - live /projects/:project_id/w/:id/health  WorkflowLive.Health :show  # receives the same handler; no annotation yet
  events:
    - WorkflowLive.Index#delete_workflow                                  # owned by workflows-index
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:delete_workflow)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Lightning.Projects.Provisioner workflow deletions also broadcast WorkflowDeleted (provisioner.ex:132-134); a second entry, not this flow's

related:
  - lib/lightning_web/live/workflow_live/index.ex
  - lib/lightning_web/live/workflow_live/dashboard_components.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflows/events.ex
  - lib/lightning/projects/events.ex
  - lib/lightning_web/hooks.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/live/workflow_live/health.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/channels/ai_assistant_channel.ex
  - test/lightning_web/live/project_live/deletion_teardown_test.exs
  - test/lightning/workflows_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/channels/ai_assistant_channel_test.exs
  - test/lightning_web/live/workflow_live/index_test.exs
flows: []
---

## 1. Purpose

Editors delete workflows from the project's workflow list while colleagues may still have that
workflow open in the editor. Those colleagues need to find out straight away and be put somewhere
useful, rather than carry on editing, chatting with the AI assistant about, or saving a workflow
that no longer exists.

## 2. What it does

Editor confirms "Delete" on workflows-index → `WorkflowDeleted` on the project topic → any other session holding that workflow open lands on the workflow list with "Workflow deleted." and its editor and AI assistant channels close.

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-42` (`:delete_workflow` is an editor action),
`:166-172` (editor actions: owner, admin, editor; support with no row when support access is on),
`index.ex:93-99`, `:289`. The receiving side checks no role: every session on that workflow is
sent away (`hooks.ex:325-335`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Delete a workflow from the list | no | yes | yes | yes | no | yes, when support access is on |
| Be sent back to the list when the open workflow is deleted | yes | yes | yes | yes | n/a | yes |

**Preconditions beyond role**
- The workflow must belong to the project and not already be marked for deletion (`index.ex:290-291`, `workflows.ex:145-157`).
- Delete permission is the mount-time assign, not re-checked per click (`index.ex:93-99`, `:289`).
- Only sessions whose mount passed `:ensure_workflow_belongs_to_project` with that id are sent away; other project pages and `/w/new` hold no `current_workflow_id` (`hooks.ex:138-162`, `:336-341`).

## 4. What it touches

**Reads**: `workflows`, `triggers`, `project_users`

**Writes**
- Hop 1, delete: `workflows.deleted_at` and name renamed to `<name>_del`; every trigger of the workflow `enabled = false, custom_path = nil, legacy_bare_path = false`; `audit_events` `marked_for_deletion`; one transaction (`workflows.ex:901-921`, `:939-952`)

**Immediate side effects** (in the same request)
- Hop 1: the deleting tab shows "Workflow successfully deleted." and patches the list (`index.ex:295-301`); detail owned by workflows-index S17
- Hop 2: after commit only, `WorkflowUpdated` on `workflow_events:<project_id>` and `WorkflowDeleted{workflow_id, project_id}` on `project_events:<project_id>` (`workflows.ex:922-931`, `workflows/events.ex:9-14`, `projects/events.ex:123-131`, `:165`)
- Hop 3, receivers of `WorkflowDeleted`:
  - LiveViews holding that workflow (editor, health page): flash "Workflow deleted." and `push_navigate` to `/projects/:project_id/w` (`hooks.ex:325-335`; shared-project-scope S12)
  - Every other project-scoped LiveView: halts the event and stays (`hooks.ex:336-341`)
  - `WorkflowChannel` on that workflow stops with `:normal`; others ignore it (`workflow_channel.ex:1085-1091`, `:1139-1149`)
  - `AiAssistantChannel` on a session for that workflow stops with `:normal`; others ignore it (`ai_assistant_channel.ex:497-506`, `:516-527`)

**Deferred side effects** (later, elsewhere)
- Webhook and cron triggers of the workflow stop starting work orders (trigger `enabled = false`); purge by the nightly sweep is owned by workflows-index (`workflows.ex:1007-1075`)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

Verified against `default`. The deleting tab's own outcome (flash, row gone, triggers off, audit)
is workflows-index S17; the receiving redirect is shared-project-scope S12. This flow joins them
and owns what happens to the other session's channels.

```gherkin
Feature: Deleting a workflow that someone has open
  In order to retire a workflow without leaving colleagues working on something that is gone
  As an editor on a project
  I want other open sessions on that workflow to be told and moved to the workflow list

  @S01 @pending
  Scenario Outline: A colleague with the workflow open is sent back to the list
    # Value: nobody keeps editing or reading a workflow that has been deleted, and they learn why it went.
    Given project "Malawi HIV" has workflow "Intake"
    And another member has "<page>" of "Intake" open
    When I delete "Intake" from the workflows page and confirm
    Then I see "Workflow successfully deleted."
    And the other member's page follows shared-project-scope S12
    # handoff only: index.ex:277-301, workflows.ex:922-931, projects/events.ex:123-131, hooks.ex:325-335
    # deletion_teardown_test.exs:253-267 (editor only; health is read from health.ex:11, not tested)
    Examples:
      | page                |
      | the editor          |
      | the health page     |

  @S02 @pending
  Scenario: The open editor's collaboration and AI assistant sessions end
    # Value: a soft-deleted workflow still authorises frames, so without this a lingering tab could keep writing to the deleted workflow's shared document and AI session.
    Given another member has the collaborative editor and the AI assistant open on "Intake"
    When I delete "Intake"
    Then their editor channel for "Intake" closes
    And their AI assistant channel for "Intake" closes
    # workflow_channel.ex:1085-1091, ai_assistant_channel.ex:494-506
    # workflow_channel_test.exs:2258-2271, ai_assistant_channel_test.exs:1328-1340

  @S03 @pending
  Scenario: People on other workflows and other project pages are not interrupted
    # Value: deleting one workflow doesn't throw colleagues out of unrelated work in the same project.
    Given another member has workflow "Sync DHIS2" open in the editor, with its editor and AI assistant channels joined
    And a third member has the project's workflows, settings and history pages open
    When I delete "Intake"
    Then all of those pages stay where they are
    And those channels stay joined
    # hooks.ex:336-341, workflow_channel.ex:1139-1149, ai_assistant_channel.ex:516-527
    # deletion_teardown_test.exs:269-312, workflow_channel_test.exs:2273-2295, ai_assistant_channel_test.exs:1342-1356

  @S04 @pending
  Scenario: Nobody is sent away when the delete fails
    # Value: colleagues are never thrown out of a workflow that was not actually deleted.
    Given another member has "Intake" open in the editor
    When deleting "Intake" fails in the database
    Then no WorkflowDeleted is broadcast
    And their editor stays open
    # workflows.ex:922-924 (broadcast only on {:ok, _}); no test found
```

## 6. Unclear value

### 6.1 Possible bugs

none. The crash when a delete fails (`index.ex:303-304`) is workflows-index 6.1; it happens after the no-broadcast path in S04 (`workflows.ex:922-924`), so the receiving side is unaffected.

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A session that misses the broadcast (socket disconnected at the time) re-mounts on reconnect and is bounced by the mount check instead, with error "Workflow not found" rather than info "Workflow deleted." | `hooks.ex:145-156`, `workflows.ex:1330-1336`, `query.ex:35-40` | decide |
| Provisioner imports (GitHub sync, CLI deploy) that remove a workflow emit the same event, so open editors bounce identically from a non-UI delete | `provisioner.ex:132-134`; `provisioner_test.exs:1460-1482` | preserve |
| The flash names neither the workflow nor who deleted it | `hooks.ex:332` | decide |
| Receiving page uses `push_navigate` (live navigation), unlike project deletion which uses a full `redirect` | `hooks.ex:333`, `:304-307` | preserve |
| The broadcast re-loads the workflow with its triggers after commit only to build the `WorkflowUpdated` payload | `workflows.ex:924-925` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Deletion rides the quiet project topic, not `workflow_events`, so ordinary saves never wake editors or channels; tests guard both halves | `workflows.ex:927-930`, `workflows/events.ex:16-27`, `projects/events.ex:144-158`; `workflows_test.exs:2343-2370`, `deletion_teardown_test.exs:314-330` | no | preserve |
| Every project-scoped LiveView and channel on the project receives every workflow deletion and must halt or ignore it | `projects/events.ex:144-158`, `hooks.ex:336-341` | no | preserve |

### 6.5 Things seen but not understood

- Whether the browser editor shows anything between its `WorkflowChannel` stopping and the LiveView `push_navigate` arriving, and whether the Yjs provider tries to rejoin in that window, was not followed into `assets/js/collaborative-editor` (`workflow_channel.ex:1085-1091`, `hooks.ex:325-335`). (preserve)
- Unsaved edits in the receiving editor are dropped with no prompt; whether that is acceptable or should offer a copy was not established (`hooks.ex:330-333`). (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a session that missed the broadcast see the same "Workflow deleted." message as one that received it (see 6.2)?
- Should the receiving tab be told which workflow was deleted and by whom?
- Should unsaved edits in the receiving editor be preserved or offered for export?

## Proposed flows

none

## Proposed shared

- `shared-channel-project-scope`: already proposed by flow-schedule-project-deletion; S02 and S03's channel halves here would move there (`workflow_channel.ex:1085-1149`, `ai_assistant_channel.ex:494-527`).

## Summary

- Scenarios: 4 (S01 to S04), all `@pending`.
- Section 6: 6.1 has 0 (the delete-failure crash is cross-referenced to workflows-index 6.1), 6.2 has 5, 6.3 has 0, 6.4 has 2, 6.5 has 2.
- Flows: none proposed; references workflows-index S17 and shared-project-scope S12.
- Shared: inherits shared-project-scope; endorses shared-channel-project-scope.
- Unsure: the health page also receives the redirect but has no annotation and no test; S04 has no test; workflow-editor-canvas has no annotation file yet, so its `flows:` list can't be checked.
