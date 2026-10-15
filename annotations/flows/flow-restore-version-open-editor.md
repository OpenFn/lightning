---
id: flow-restore-version-open-editor
type: flow
title: Restoring a workflow version while others have it open
status: not-started
owner:

trigger:
  entry: workflow-editor-versions-and-promote
  exit: workflow-editor-canvas
  surfaces:
    - workflow-editor-versions-and-promote                                  # tab A: "Restore v<n>" in the publishes list (S09 there)
    - pubsub:workflow_collaboration:<workflow_id>#ReconcileRequested       # workflow_channel.ex:464; workflow_reconciler.ex:90-94, :136
    - capability:workflow-reconciler                                        # DocumentSupervisor resets the live SharedDoc (document_supervisor.ex:204-224; workflow_reconciler.ex:109-161)
    - pubsub:workflow:collaborate:<workflow_id>#workflow_saved             # workflow_channel.ex:466, :1890-1900
    - workflow-editor-canvas                                                # tab B: a colleague's editor on Latest
    - workflow-editor-ide                                                   # tab B with a step's code open
  reachable_when:
    - entry: the restorer has experimental features, the workflow is live outside a sandbox, and the restorer may :edit_workflow (workflow-editor-versions-and-promote section 3)
    - exit: someone has the latest version of the same workflow open, so a DocumentSupervisor for "workflow:<id>" is subscribed to the collaboration topic (document_supervisor.ex:120-122)

inherits:
  - shared-editor-session        # S04 stale shared draft replaced on open; S06 save; S07 workflow_saved to everyone; S14 who may join
  - shared-project-scope         # who can open either tab

url_params: []

config_variants:
  experimental-features: { restorer user.preferences.experimental_features: true }    # needed to start the flow at all; every scenario is read under it
  colleague-can-edit: { colleague user.preferences.experimental_features: false }      # the colleague's editor is not content-locked on a live workflow, so they can hold unsaved edits (workflow_channel.ex:1507-1510)

inventory:
  routes: []                                         # live /projects/:project_id/w/:id owned by shared-editor-session
  events:
    - WorkflowChannel#restore_version                # owned by workflow-editor-versions-and-promote; the hop that starts this flow
    - WorkflowChannel handle_info %Phoenix.Socket.Broadcast{event: "workflow_saved"}   # workflow_channel.ex:1155-1160; how pinned rooms hear the restore
    - DocumentSupervisor handle_info %ReconcileRequested{}                              # document_supervisor.ex:204-224
  js_hooks:
    - createSessionContextStore workflowSavedHandler   # createSessionContextStore.ts:556-575, :654
  policies:
    - Lightning.Policies.ProjectUsers :edit_workflow   # owned by workflow-editor-versions-and-promote
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features
  not_reachable_here:
    - WorkflowReconciler.reconcile_workflow_changes/2 incremental path (workflow_reconciler.ex:38-61); skipped by restore (workflows.ex:1469); owned by flow-toggle-workflow-open-editor
    - WorkflowReconciler.request_reconciliation/1 list clause (workflow_reconciler.ex:86-88); used by the provisioner and sandbox merge

related:
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/workflows.ex
  - lib/lightning/collaboration/workflow_reconciler.ex
  - lib/lightning/collaboration/document_supervisor.ex
  - lib/lightning/collaboration/workflow_serializer.ex
  - assets/js/collaborative-editor/CollaborativeEditor.tsx
  - assets/js/collaborative-editor/stores/createSessionContextStore.ts
  - assets/js/collaborative-editor/hooks/useUnsavedChanges.ts
  - assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning/collaboration/reconcile_workflow_document_test.exs
  - test/lightning/collaboration/document_supervisor_test.exs
  - flow-toggle-workflow-open-editor            # the incremental reconcile for saves made outside the editor
  - flow-sandbox-merge                          # promote uses the same ReconcileRequested reset
flows: []
---

## 1. Purpose

An editor rolls a live workflow back to an earlier publish while a colleague has the same
workflow open in another tab. The colleague's editor has to switch to the restored content.
Otherwise they keep looking at, and could save, a version that was just rolled back, and the
rollback is undone without anyone noticing.

## 2. What it does

1. An editor (with experimental features on) restores an earlier published version of a workflow.
   - If they're refused, or someone else saves at the same moment, they see "Could not restore" and nobody else is affected.
2. The old version becomes the workflow again and is recorded as a new publish, "Restored v1", under their name.
3. Everyone with the workflow open on the latest version sees it switch to the restored content.
   - That includes the canvas and any step code they have open, with no unsaved changes marker.
   - A colleague who then edits and saves keeps the rollback rather than undoing it.
4. Anyone reading an older version stays on it, and everyone's version list shows the new publish next time they open it.

**Straightforwardness: 2 of 5.** "Everyone switches to the restored version" sounds simple, but what happens to colleagues' unsaved work, read-only views and the restorer's own list takes real thought.

### Most surprising behaviours

- **(2)** A colleague who can edit has their unsaved changes wiped by the restore, with no message telling them why. (6.2)
- **(2)** If switching open editors over fails, colleagues may still be told the save happened, see their old content marked as unsaved changes, and undo the rollback by saving. (6.1)
- **(2)** Someone reading an older, read-only version may be told they have unsaved changes and warned when leaving, on a page they can't edit. This happens after any save, not just a restore. (6.1)
- **(3)** The person who restored doesn't see the new publish in their own version list until they reload. (6.1)
- **(3)** A colleague with a step open that the restore removed is told it "didn't exist in this version", as if they'd switched versions themselves, and open screens may flash an empty workflow during the switch. (6.1, 6.2)

## 3. Who can do what

Sources: `workflow_channel.ex:455-482`, `:1950-1956` (who may start); `workflow_reconciler.ex:109-161`
(the reset has no actor check: it applies to every session on the document); `workflow_channel.ex:79-82`,
`:1155-1160` (every channel, pinned or not, hears `workflow_saved`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start the flow (restore a publish) | no | yes | yes | yes | no | yes, when support access is on |
| See the restored workflow in an open editor | yes | yes | yes | yes | n/a, can't join | yes, when support access is on |

**Preconditions beyond role**
- Only a committed restore reaches anyone: authorisation, an unknown version and a concurrent save all reply with an error before the reconcile or broadcast (`workflow_channel.ex:460-463`, `:478-480`, `:1428-1432`).
- Only the latest document `workflow:<id>` is reset; version, release and run rooms are not subscribed (`document_supervisor.ex:120-122`).
- With nobody holding the latest document open the reset is a logged no-op (`workflow_reconciler.ex:112-118`); the next open replaces any stored draft older than the restore (shared-editor-session S04; `persistence.ex:114`).

## 4. What it touches

**Reads**: `workflow_releases`, `workflow_snapshots` (`workflow_channel.ex:461-462`); `workflows`, `jobs`, `triggers`, `workflow_edges` (`workflows.ex:1465-1467`; reloaded by the reset, `workflow_reconciler.ex:138-141`)

**Writes**
- Hop 1, tab A: `workflows`, `jobs`, `triggers` (deletes those not in the snapshot), `workflow_edges`, `workflow_snapshots`, `workflow_versions`, `workflow_releases` (kind `restore`), and `audit_events` only when a trigger's enabled flag changes; one transaction (`workflows.ex:1460-1472`, `:326-352`, `:380-405`, `:734-759`); detail owned by workflow-editor-versions-and-promote section 4
- Hop 3, reconciler: the live Y.Doc's `jobs`, `edges`, `triggers`, `positions` and `errors` are cleared and the `workflow` map overwritten, then reserialised from the database inside `SharedDoc.update_doc/2` (`workflow_reconciler.ex:144-161`; `workflow_serializer.ex:56-92`); the persistence writer stores the result like any other document update

**Immediate side effects**
- Hop 1: `WorkflowUpdated` and saved-workflow telemetry from `after_commit`; the incremental reconcile is skipped (`workflows.ex:513-527`, `:1469`)
- Hop 2: `ReconcileRequested` on `workflow_collaboration:<id>`, after commit (`workflow_channel.ex:464`; `workflow_reconciler.ex:79-94`)
- Hop 2: `workflow_saved` with the new `lock_version` and workflow to every channel on the workflow except the restorer's own (`workflow_channel.ex:466`, `:1890-1900`); live rooms push it through `handle_out` (`:1173-1177`), pinned rooms through `handle_info` (`:1155-1160`)
- Hop 2: `session_context_updated` to the restorer only (`workflow_channel.ex:475`)
- Hop 4, tab B: `workflow_saved` sets the latest lock version, clears cached version lists and replaces the saved baseline (`createSessionContextStore.ts:302-317`, `:556-575`); the Y.Doc update re-renders canvas, inspectors and IDE

**Deferred side effects**
- none

**External, non-transactional effects**
- none; the reset is in memory and runs after commit, so its failure cannot undo the restore (`document_supervisor.ex:204-224`)

**Depends on config**
- `experimental-features` on the restorer: without it there is no Restore control (workflow-editor-versions-and-promote section 3)
- `colleague-can-edit`: a colleague with the flag sees the live workflow content-locked and has nothing unsaved to lose (`workflow_channel.ex:1507-1510`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Restoring a workflow version while others have it open
  In order to roll back a bad go-live without leaving colleagues on the broken version
  As an editor restoring an earlier publish
  I want every open editor on the workflow to switch to the restored content

  @S01 @pending @variant:experimental-features
  Scenario: A colleague on Latest sees the restored workflow
    # Value: nobody keeps working from a version that was just rolled back.
    Given "Intake" is live with publishes v1 and v2, and v2 added the step "Notify"
    And "Ben" has "Intake" open on Latest in tab B
    When I restore v1 in tab A
    Then I see "Restored v1"
    And eventually tab B's canvas no longer shows "Notify"
    And tab B shows no unsaved changes marker
    # workflow_channel.ex:455-482; workflows.ex:1460-1472; workflow_reconciler.ex:90-94, :109-161
    # document_supervisor.ex:120-122, :204-210; createSessionContextStore.ts:556-575; useUnsavedChanges.ts:9-56
    # reconcile_workflow_document_test.exs:65-91 (broadcast resets a live doc; no end-to-end restore test)

  @S02 @pending @variant:experimental-features
  Scenario: A colleague's code editor shows the restored step body
    # Value: someone in the code editor doesn't keep editing a body that is no longer what runs.
    Given v2 of "Intake" changed the body of "Fetch cases"
    And "Ben" has "Fetch cases" open in the code editor in tab B
    When I restore v1 in tab A
    Then eventually tab B's code editor shows v1's body of "Fetch cases"
    # workflow_reconciler.ex:144-161; workflow_serializer.ex:80; FullScreenIDE.tsx:1020-1033

  @S03 @pending @variant:experimental-features @variant:colleague-can-edit
  Scenario: A colleague's next save keeps the rollback
    # Value: a rollback is not undone by a colleague saving an editor that still held the old version.
    Given "Ben" has "Intake" open on Latest without experimental features
    When I restore v1 in tab A
    And "Ben" renames step "Fetch cases" to "Fetch all cases" in tab B and saves
    Then "Intake" has v1's steps with "Fetch all cases" renamed
    And "Intake" does not have the step "Notify"
    # workflow_reconciler.ex:144-161 (doc carries the new lock_version, workflow_serializer.ex:69)
    # shared-editor-session S06 (save from the doc); workflow_channel.ex:1507-1510

  @S04 @pending @variant:experimental-features
  Scenario: A colleague's version list shows the restore
    # Value: colleagues can see the workflow was rolled back, to what, and by whom.
    Given "Ben" has "Intake" open on Latest in tab B and has opened its version list
    When I restore v1 in tab A
    And "Ben" opens the version list again
    Then the list is fetched again and shows v3 "Restored v1" with my name
    # workflow_channel.ex:466, :1890-1900; createSessionContextStore.ts:302-317, :556-575
    # VersionDropdown.tsx:114-134; releaseLabel.tsx:23-25

  @S05 @pending @variant:experimental-features
  Scenario: A colleague reading an older version keeps seeing it
    # Value: someone comparing against a past version isn't moved off it mid-review.
    Given "Ben" is reading v2 of "Intake" in tab B
    When I restore v1 in tab A
    Then tab B still shows v2, including the step "Notify"
    And "Ben"'s version list includes v3 when he opens it again
    # document_supervisor.ex:120-122; workflow_channel.ex:79-82, :1155-1160; createSessionContextStore.ts:556-575

  @S06 @pending @variant:experimental-features
  Scenario: A refused restore leaves colleagues' editors alone
    # Value: colleagues never lose their view or their edits to a rollback that didn't happen.
    Given "Ben" has "Intake" open on Latest in tab B
    And someone else saves "Intake" while I restore v1
    When I see "Could not restore v1"
    Then tab B still shows the workflow as it was
    # workflow_channel.ex:458-481, :1428-1432 (no reconcile or broadcast on the error branch)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A reset that raises or exits is only logged, but `workflow_saved` still goes out and replaces the colleague's saved baseline with the restored workflow. Their document keeps the old content, now marked unsaved, and a save writes it back over the restore. Read from code | `document_supervisor.ex:204-224`; `workflow_channel.ex:464-466`; `createSessionContextStore.ts:571-573` | an "unsaved changes" marker for edits they never made; a save that silently undoes the rollback | fix |
| The restorer's own publishes list is not invalidated: `workflow_saved` skips the restorer, and `session_context_updated` sets the latest lock version directly without clearing cached lists, unlike `setLatestSnapshotLockVersion`. Contradicts workflow-editor-versions-and-promote S09 "the version list shows a new v3"; its cited tests mock the list. Read from code | `workflow_channel.ex:1890-1900`; `createSessionContextStore.ts:197-204` vs `:302-317`; `VersionDropdown.tsx:128-131` | reopening the chip in tab A shows no v3 until reload | fix |
| A colleague reading an older version gets the restored latest workflow as their saved baseline, so a read-only pinned view reads as having unsaved changes; with experimental features, leaving warns and switching version asks to discard. The server guards this for the restorer's socket only. Not specific to restore: any save does it. Read from code | `createSessionContextStore.ts:556-575`; `useUnsavedChanges.ts:36-56`; `useUnloadWarning.ts:11-32`; `useDiscardGuard.tsx:13-18`; `workflow_channel_test.exs:2411-2435` | a "leave site?" prompt or discard dialog on a page they cannot edit | fix |
| A colleague with a step open in the code editor that the restore deleted is told it "didn't exist in this version of the workflow", although they are on Latest | `FullScreenIDE.tsx:767-773`, `:1007-1018` | copy that blames a version switch they didn't make | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Under `colleague-can-edit`, a colleague's unsaved edits are wiped by the reset with no notice; `workflow_saved` shows no toast | `workflow_reconciler.ex:144-161`; `createSessionContextStore.ts:556-575` | decide |
| The reset clears in one Y.Doc transaction and reserialises in a second, so connected clients may render an empty workflow between the two. Read from code | `workflow_reconciler.ex:151-160`; `workflow_serializer.ex:65-89` | decide |
| The reset clears the `errors` map, so validation errors shown to everyone disappear | `workflow_reconciler.ex:150`, `:156` | preserve |
| Restore skips the incremental reconciler and asks for a full reset instead, because a wholesale replacement is more than it can express | `workflows.ex:1446-1456`, `:1469`; `workflow_channel.ex:464` | preserve |
| The `workflow` map's keys are overwritten, not cleared | `workflow_reconciler.ex:144-161`; `workflow_serializer.ex:67-78` | preserve |
| The reset runs on whichever node owns the document; the request is a cluster-wide PubSub broadcast | `workflow_reconciler.ex:90-94`; `lib/lightning.ex:25-27` | preserve |
| A failed reset leaves the document process standing | `document_supervisor.ex:204-224`; `document_supervisor_test.exs:93-150` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The restore and its broadcasts run synchronously in the restorer's channel process, not as an async task | `workflow_channel.ex:455-482` | no, beyond the dialog's in-flight state | preserve |

### 6.5 Things seen but not understood

- The reset and `workflow_saved` take different paths (PubSub to the DocumentSupervisor then the SharedDoc, versus PubSub straight to channels), so their order at tab B is not fixed; a brief unsaved-changes marker is possible. Not traced (`workflow_channel.ex:464-466`). (decide)
- Each job's Y.Text is recreated by the reset; whether the colleague's Monaco binding and cursor follow the new Y.Text cleanly was not checked (`workflow_reconciler.ex:152`; `FullScreenIDE.tsx:1020-1033`). (decide)
- workflow-editor-versions-and-promote 6.5 asks what happens when a restored snapshot names a credential that has left the project. The restore goes through the same `credential_scope_check` step as any save, so it should be refused before commit and never reach colleagues; the error copy was not followed (`workflows.ex:337-338`, `:418-428`). (decide)
- Whether `audit_events` records anything for a restore that changes no trigger's enabled flag was not followed past `maybe_audit_workflow_state_changes` (`workflows.ex:734-759`). (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. Should a colleague be told that someone restored a version, especially when their unsaved edits were discarded (6.2 row 1)?
2. Should `workflow_saved` be withheld, or the baseline left alone, when the reset fails (6.1 row 1)?
3. Should `workflow_saved` update the saved baseline in pinned rooms at all (6.1 row 3)? This belongs with shared-editor-session S07.

## Proposed flows

none

## Proposed shared

none. Referenced: shared-editor-session (S04, S06, S07), shared-project-scope.
