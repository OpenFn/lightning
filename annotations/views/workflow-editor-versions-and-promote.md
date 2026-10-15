---
id: workflow-editor-versions-and-promote
type: view
title: Workflow editor › Versions, run history, restore, edit in sandbox, sync and promote
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id (version chip in the breadcrumbs, recent history panel on the canvas, header "Edit in sandbox", "Save & Sync" and "Promote"), with ?v=, ?release= or ?as_run= for a pinned view
  new_route:                                  # open question 1
  old_route_disposition: unchanged
  reachable_when:
    - the editor session admits the viewer (shared-editor-session; collaborate.ex:25-27)
    - the version chip renders once the workflow has been saved at least once; the whole breadcrumb header is hidden for a new workflow (CollaborativeEditor.tsx:315-316)
    - the history panel renders on an existing workflow only (CollaborativeWorkflowDiagram.tsx:307-325)
    - the publishes list, Restore, "Edit in sandbox" and "Promote" need experimental features on the viewer (useVersionPicker.ts:16-25; Header.tsx:255-259, :820-858)
    - "Edit in sandbox" needs a live workflow outside a sandbox; "Promote" needs a workflow inside a sandbox (Header.tsx:820-836)
    - "Save & Sync" needs a GitHub connection on the project (flow-github-sync-actions reachable_when)

inherits:
  - shared-authenticated-session     # signed-in view
  - shared-project-scope             # S03 is what a "Continue in a sandbox" join lands on for a non-member (6.1); S11 is the archive landing
  - shared-editor-session            # S10 read-only pinned views, S14 refused pinned joins, S20 unload warning skipped for "Edit in sandbox", S07 workflow_saved
  - shared-dataclip-body-viewer      # GET /dataclip/body/:id access rules for the run input loaded in "Edit in sandbox" (EditInSandboxPicker.tsx:656); none of the viewer UI
  - shared-run-components
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: v
    set_by: this view (saves picker, SnapshotVersionDropdown.tsx:114-121 via useVersionSelect.ts:63-69; history run selection without the flag, CollaborativeWorkflowDiagram.tsx:194-204), flow-open-run-in-editor
    effect: joins the read-only room workflow:collaborate:<id>:v<lock_version> (pinnedView.ts:56-67); dropped on load when the publishes list is in use (CollaborativeEditor.tsx:233-239)
  - name: release
    set_by: this view only (publishes list, useVersionSelect.ts:54-62)
    effect: joins the read-only room workflow:collaborate:<id>:release<version_number> (pinnedView.ts:63-64; workflow_channel_test.exs:2617-2729); filters the history panel to that publish's runs (CollaborativeWorkflowDiagram.tsx:234-264)
  - name: as_run
    set_by: this view (history run selection with the flag, CollaborativeWorkflowDiagram.tsx:207-217; useViewAsExecuted.ts:15-27), flow-open-run-in-editor
    effect: joins workflow:collaborate:<id>:run:<run_id>; the chip reads that run's version or "unpublished" (VersionDropdown.tsx:67-77)
  - name: run
    set_by: this view (history run selection, CollaborativeWorkflowDiagram.tsx:192-227); also run viewer and manual run
    effect: owned by workflow-editor-run-viewer; cleared by a publishes-list switch (useVersionSelect.ts:54-62)
  - name: archived=1
    set_by: shared-project-scope S11 (hooks.ex:399-411)
    effect: owned by flow-sandbox-merge (PromotedNotice.tsx:8-39, mounted at CollaborativeEditor.tsx:340)

config_variants:
  default: {}                                                              # experimental features off: saves list only, no restore, no sandbox entry points
  experimental-features: { user.preferences.experimental_features: true }  # publishes list, restore, version tags in history, discard guard, Edit in sandbox, Promote; read under this one when tagged
  sandbox-limited: { Lightning.Extensions.UsageLimiter: "limit_action(:new_sandbox) returns {:error, _, %Message{}}" }   # workflow_channel.ex:2020-2025, :2433-2450

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit    # owned by shared-editor-session; this view is panels and dialogs on it
  events:
    - WorkflowChannel#request_releases           # workflow_channel.ex:594-619
    - WorkflowChannel#request_versions           # workflow_channel.ex:622-651
    - WorkflowChannel#request_restore_check      # workflow_channel.ex:434-452
    - WorkflowChannel#restore_version            # workflow_channel.ex:455-482
    - WorkflowChannel#request_history            # workflow_channel.ex:235-265 (version_number, run_id and bare clauses)
    - WorkflowChannel#list_sandboxes             # workflow_channel.ex:343-364
    - WorkflowChannel#edit_in_sandbox            # workflow_channel.ex:367-406
    - WorkflowChannel#save_and_sync              # handoff only; owned by flow-github-sync-actions
    - WorkflowChannel#request_promote_check, #promote, #archive_sandbox   # handoff only; owned by flow-sandbox-merge
  js_hooks:
    - VersionDropdown (components/VersionDropdown.tsx), publishes list
    - SnapshotVersionDropdown (components/SnapshotVersionDropdown.tsx), saves list
    - RestoreVersionDialog (components/RestoreVersionDialog.tsx) and BreadcrumbContent restore handlers (CollaborativeEditor.tsx:136-197, :347-356)
    - DiscardChangesDialog for version switches and run pins (CollaborativeEditor.tsx:341-346; CollaborativeWorkflowDiagram.tsx:327-340; FullScreenIDE.tsx:1391-1404)
    - hooks useVersionPicker, useVersionSelect, useViewAsExecuted, useDiscardGuard, useVersionMismatch; lib/pinnedView.ts; utils/releaseLabel.tsx
    - MiniHistory floating and panel variants (components/diagram/MiniHistory.tsx; CollaborativeWorkflowDiagram.tsx:307-325; FullScreenIDE.tsx:1294-1310)
    - VersionMismatchBanner (components/diagram/VersionMismatchBanner.tsx)
    - Ctrl/Cmd+H history toggle (CollaborativeWorkflowDiagram.tsx:84-93)
    - EditInSandboxPicker (components/EditInSandboxPicker.tsx) and the Header "Edit in sandbox" button (Header.tsx:836-858, :977-982)
    - GitHubSyncModal (components/GitHubSyncModal.tsx), PromoteDialog (components/PromoteDialog.tsx), PromotedNotice (components/PromotedNotice.tsx); handoff only
  policies:
    - Lightning.Policies.ProjectUsers :edit_workflow       # restore and its check (workflow_channel.ex:439, :460, :1950-1956)
    - Lightning.Policies.Sandboxes :provision_sandbox      # list and create (workflow_channel.ex:347, :381, :1979-1989; policies/sandboxes.ex:94-96); can_provision_sandbox in the context (workflow_channel.ex:1524-1525)
    - Lightning.Policies.Sandboxes :merge_sandbox, :delete_sandbox   # owned by flow-sandbox-merge
  workers: []
  api_endpoints:
    - get /projects/:project_id/runs/:run_id/dataclip  DataclipController :show_for_run   # dataclip_controller.ex:211-244; called by EditInSandboxPicker.tsx:649 (shared with workflow-editor-ide)
  emails: []
  config:
    - user.preferences.experimental_features
    - Lightning.Config.max_sandbox_nesting_depth         # sandboxes.ex:268-271
    - Lightning.Config.max_dataclip_size_bytes           # reviewed run input (sandboxes.ex:233-235)
    - usage limiter :new_sandbox                         # workflow_channel.ex:2020-2025
  not_reachable_here:
    - components/VersionPicker.tsx; the adaptor version combobox, rendered only by ConfigureAdaptorModal.tsx:568 and owned by shared-adaptor-credential-config
    - components/WorkflowDiffBlocks.tsx; rendered only by MessageList.tsx:1260 under an AI assistant reply, not reachable from this view (open question 3)
    - get /projects/:project_id/jobs/:job_id/dataclips DataclipController :search; called for saved inputs (EditInSandboxPicker.tsx:517-520), owned by workflow-editor-manual-run
    - get /dataclip/body/:id DataclipController :show; owned by shared-dataclip-body-viewer
    - Sandboxes.provision/3 clone details (members, credentials, keychains, triggers off); owned by sandboxes-index (its scenarios "Editor creates a sandbox and lands in it", "A new sandbox brings the team along, with the creator in charge", "A new sandbox copies workflows with their triggers off")
    - history_filter "draft" / "unversioned" and WorkOrders.get_workorders_unversioned/1 (see 6.3)
    - default_sandbox_name/2 (see 6.3)

related:
  - workflow-editor-canvas             # hosts the history panel and the header
  - workflow-editor-ide                # hosts the panel variant of the history list and its mismatch banner
  - workflow-editor-run-viewer         # takes over once a run is selected
  - workflow-editor-manual-run         # receives panel=run&dataclip= after "Edit in sandbox"
  - sandboxes-index                    # owns sandbox provisioning details; the other way into a merge
  - history-work-orders                # receives filters[workflow_id] and filters[workorder_id] from the history panel
  - run-show                           # receives run id links from the history panel
  - project-settings-github-sync       # receives #vcs from the sync dialog
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflows/workflow_releases.ex
  - lib/lightning/workflows/snapshot.ex
  - lib/lightning/projects.ex
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/work_orders.ex
  - assets/js/collaborative-editor/CollaborativeEditor.tsx
  - assets/js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.tsx
  - assets/js/collaborative-editor/stores/createSessionContextStore.ts
  - assets/js/collaborative-editor/stores/createHistoryStore.ts
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts
flows:
  - flow-github-sync-actions               # Save & Sync and GitHubSyncModal (S31)
  - flow-sandbox-merge                     # Promote, PromoteDialog, PromotedNotice (S32)
  - flow-workflow-api-edit-conflict        # any open view, pinned or not, blocks API writes (S33)
  - flow-open-run-in-editor                # arrives on ?v= or ?as_run= set by run links; lists this view in its surfaces
  - flow-manual-run-live-follow            # new work orders reach the history panel as history_updated (6.1 row 4)
  - flow-restore-version-open-editor
  - flow-edit-in-sandbox
---

## 1. Purpose

People who build and run a workflow need to see what it looked like before, what ran on which
version, and how to get back to a version that worked. With experimental features they also change
a live workflow by copying it into a sandbox, trying it there with real or redacted data, and
promoting it back. Without this, a bad go-live has no quick way back, a run can't be matched to the
shape that produced it, and the only way to change production would be to edit it directly.

## 2. What it does

- **Browse versions** (members)
  - Browse the workflow's saves and open any one read-only, then return to the latest, editable copy; with experimental features a live workflow lists its publishes instead, with who published each one and how
  - With experimental features, switching away asks before throwing away unsaved edits
  - The version lists stay current after anyone saves, and a failed load says so
- **Roll back a live workflow** (editors, experimental features)
  - Restore an older publish after seeing which triggers it deletes or brings back switched off
  - A restore that is refused says why and changes nothing
- **See what ran** (members)
  - Recent work orders and runs on the canvas, with load, empty and failure states, and links to the full history, a work order or a run
  - Picking a run shows it on the version it ran on, and reading a publish shows only that publish's runs
  - With experimental features, each run is tagged with the version it ran on
- **Edit in a sandbox** (editors, experimental features)
  - Copy a live workflow into a new sandbox and land in it, or continue in an existing sandbox that holds this workflow
  - Choose what a new sandbox starts with: nothing, the open run's reviewed input, or a saved input
  - Creation respects name uniqueness, permissions and the plan's sandbox limit
- **Hand off to other flows** (editors)
  - Save and sync to GitHub from the editor, and in a sandbox promote the workflow to the parent

**Straightforwardness: 2 of 5.** Two numbering schemes, read-only views of the past, a rollback that reaches other people's screens and a sandbox picker with several starting points add up to a page you have to sit and think about.

### Most surprising behaviours

- **(2)** Restoring a publish resets the workflow in place for everyone who has it open, so a colleague's unsaved edits are replaced by the restored version. (4, S34)
- **(2)** If the restore dialog can't work out which triggers will change, it shows no warnings and still lets you restore, so "nothing will break" and "we couldn't check" look exactly the same. (6.2)
- **(3)** "v3" means the third publish in one list and the third save in the other, depending on whether the workflow is live. (6.2, S04)
- **(3)** Choosing "Cancel" on the unsaved-changes prompt after "Edit in sandbox" still leaves the new sandbox behind, and trying again fails because the name is taken. (6.1)
- **(3)** "Continue in a sandbox" lists sandboxes you aren't a member of, with their owner's name or email, and then refuses to let you in. (6.1)

## 3. Who can do what

Sources: `policies/project_users.ex` through `workflow_channel.ex:1516-1541` (`can_edit_workflow`,
`can_provision_sandbox`); `policies/sandboxes.ex:94-96`; client gates `CollaborativeEditor.tsx:135`,
`:271-273`, `Header.tsx:259-262`, `:836-858`. Roles are on the project the editor is open on.
Superuser with no row cannot join the room at all (shared-editor-session section 3).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the version chip and history panel | yes | yes | yes | yes | no | yes, when support access is on |
| Open an older save, publish or run view | yes | yes | yes | yes | no | yes, when support access is on |
| Restore a publish (flag on) | no | yes | yes | yes | no | yes, when support access is on |
| Open "Edit in sandbox" and create a sandbox (flag on) | no | yes | yes | yes | no | no |
| List sandboxes to continue in (flag on) | no | yes | yes | yes | no | no |
| Join a listed sandbox | needs a membership on that sandbox (shared-project-scope S03) | | | | | |
| Save & Sync | see flow-github-sync-actions section 3 | | | | | |
| Promote, archive | see flow-sandbox-merge section 3 | | | | | |

**Preconditions beyond role**
- Restore is offered only in the publishes list, which needs the flag, a live workflow and a project that is not a sandbox (`useVersionPicker.ts:16-25`; `CollaborativeEditor.tsx:266-281`); it is never offered on the newest publish (`VersionDropdown.tsx:292-310`).
- The server lets a restore run from a pinned room too; only edit permission is checked, not the content lock (`workflow_channel.ex:455-482`, `:1950-1956`).
- "Edit in sandbox" is disabled while a version is pinned (`Header.tsx:850`), not while viewing a run as executed.
- Creating a sandbox also needs the plan's sandbox limit to allow it (`EditInSandboxPicker.tsx:397-401`; `workflow_channel.ex:382`) and the parent to be under the nesting cap (`sandboxes.ex:1015-1017`).
- "Edit in sandbox" is offered only outside a sandbox, so the editor never nests from here (`Header.tsx:836`).

## 4. What it touches

**Reads**: `workflow_releases`, `workflow_snapshots`, `workflows`, `triggers`, `users` (publisher names), `projects` (source project names, parent, sandboxes), `project_users`, `work_orders`, `runs`, `steps`, `dataclips`

**Writes**
- Restore, through `Workflows.save_workflow/3` with `skip_reconcile: true` and `record_release: {:restore, n}` (`workflows.ex:1460-1472`): `workflows`, `jobs`, `triggers` (deletes those not in the snapshot), `workflow_edges`, `workflow_snapshots`, `workflow_versions`, `workflow_releases` (kind `restore`, `restored_from_version_number`) (`workflows.ex:330-352`, `:380-405`)
- Edit in sandbox, through `Projects.provision_editing_sandbox/4` (`projects.ex:2400-2432`): a new `projects` row and its `project_users`, `project_credentials`, keychains, cloned `workflows`, `jobs`, `triggers`, `workflow_edges`, and a copied or reviewed starting `dataclips` row (`sandboxes.ex:152-160`, `:1009-1051`); details owned by sandboxes-index
- Deletes the new sandbox again if the clone of this workflow is missing (`projects.ex:2411-2429`)

**Immediate side effects**
- Restore: `ReconcileRequested` on the workflow's collaboration topic, which resets every open live document in place (`workflow_channel.ex:464`; `workflow_reconciler.ex:90-97`, `:108-120`); `workflow_saved` to everyone else in the room (`workflow_channel.ex:466`, `:1890-1900`); `session_context_updated` to the restorer (`workflow_channel.ex:475`)
- Any `workflow_saved` clears the cached version lists so the next open refetches (`createSessionContextStore.ts:303-317`, `:556-575`)
- Edit in sandbox: sandbox-created metric (`sandboxes.ex:1044-1046`)

**Deferred side effects**
- Triggers deleted by a restore stop answering their webhook URLs or firing (`RestoreVersionDialog.tsx:125-147`); triggers it brings back come back switched off (`:149-170`)

**External, non-transactional effects**
- none in this view (GitHub dispatch belongs to flow-github-sync-actions)

**Depends on config**
- `experimental_features` user preference (most of this view)
- Usage limiter `:new_sandbox`; `max_sandbox_nesting_depth`; `max_dataclip_size_bytes`

**Product limits**
- History panel holds the 20 most recent work orders, plus the selected run's (`work_orders.ex:569-580`; `createHistoryStore.ts:296-299`)
- Saved inputs offered for a sandbox: first 100 named inputs (`EditInSandboxPicker.tsx:517-520`)
- The plan's sandbox limit and the nesting cap (S28)

## 5. Scenarios

Verified against `default` unless tagged. Read from code and tests; nothing was run. Several Vitest
files mock the stores and child components wholesale; where a scenario rests on such a test, the
citation says what the mock leaves unproven.

```gherkin
Feature: Workflow versions, history and sandbox editing
  In order to see what a workflow was, what ran on it, and change it safely
  As a member of a project
  I want to browse versions and runs, roll back, and work on copies

  @S01 @pending
  Scenario: Member opens an earlier save read-only
    # Value: anyone can check what the workflow looked like at an earlier save without being able to change it by accident.
    Given workflow "Intake" has saves 3, 4 and 5, and 5 is current
    When I open the version chip, which reads "latest"
    Then I see "latest" and each save as "v5", "v4", "v3" with its time
    When I pick "v3"
    Then the URL carries "v=3" and the chip reads "v3" in yellow
    And the canvas shows save 3 and is read-only
    When I pick "latest"
    Then the pin is removed and I am back on the editable workflow
    # SnapshotVersionDropdown.tsx:39-54, :114-121, :154-226; useVersionSelect.ts:63-69; pinnedView.ts:56-67
    # workflow_channel.ex:622-651; read-only is shared-editor-session S10
    # SnapshotVersionDropdown.test.tsx:61-74, :209-245; workflow_channel_test.exs:6828-6870

  @S02 @pending @variant:experimental-features
  Scenario: A live workflow lists its publishes and where each came from
    # Value: people can tell who put each version into production and whether it was published, promoted from a sandbox or restored.
    Given "Intake" is live outside a sandbox with publishes v1 (first go-live), v2 (promoted from sandbox "fix-dates"), v3 (published from draft) and v4 (restored v2)
    When I open the version chip
    Then "Latest" comes first, then a "Version history" list newest first
    And each row shows its v-number, "Initial go-live", "Promoted sandbox fix-dates", "Published from draft" or "Restored v2", the publisher's name and the date
    And only v4 has a green pill
    And ordinary saves are not listed
    # VersionDropdown.tsx:183-312; releaseLabel.tsx:10-33; workflow_channel.ex:594-619, :1463-1481; workflow_releases.ex:52-62
    # VersionDropdown.test.tsx:637-723, :1016-1061; workflow_channel_test.exs:6607-6827

  @S03 @pending @variant:experimental-features
  Scenario: Member opens a publish read-only and comes back to Latest
    # Value: a publish can be inspected in place, and there is always a way back to the editable copy, even before anything is published.
    Given "Intake" is live with publishes v1 and v2
    When I pick "v1" from the version chip
    Then the URL carries "release=1" and no "run", "step", "v" or "as_run"
    And the chip reads "v1" and the v1 row is marked
    And the canvas shows v1 and is read-only
    When I pick "Latest"
    Then the pin is removed
    # useVersionSelect.ts:54-62; VersionDropdown.tsx:60-77, :145-152, :183-206, :227-229
    # useVersionSelect.test.tsx:54-68, :108-122; VersionDropdown.test.tsx:755-797, :831-886; workflow_channel_test.exs:2617-2685

  @S04 @pending @variant:experimental-features
  Scenario Outline: The list matches what the workflow's versions mean
    # Value: on a live workflow the numbers people see are the versions that went to production; elsewhere they are every save.
    Given "Intake" is <state> <where>
    When I open the version chip
    Then I see the <list> list
    Examples:
      | state | where                 | list      |
      | live  | in an ordinary project | publishes |
      | draft | in an ordinary project | saves     |
      | live  | in a sandbox          | saves     |
    # useVersionPicker.ts:16-25; CollaborativeEditor.tsx:266-281; useVersionPicker.test.tsx:33-66

  @S05 @pending @variant:experimental-features
  Scenario: A saved-version link on a live workflow falls back to the live copy
    # Value: an old "v=" link can't open a numbering that the live workflow's list no longer uses.
    Given "Intake" is live outside a sandbox
    When I open "Intake" with "v=5" in the URL
    Then "v=5" is removed from the URL without adding a history entry
    # CollaborativeEditor.tsx:233-239; CollaborativeEditor.restore.test.tsx:224-246 (BreadcrumbContent rendered with Header and VersionDropdown mocked)

  @S06 @pending @variant:experimental-features
  Scenario: Switching version with unsaved edits asks first
    # Value: nobody loses work just by looking at an older version.
    Given I am an editor with unsaved changes in "Intake"
    When I pick another version
    Then I see "You have unsaved changes" and nothing has switched yet
    When I choose "Cancel"
    Then I stay where I was
    When I pick it again and choose "Save and switch"
    Then the workflow is saved and then the version switches
    When the save fails instead
    Then I stay on my copy with the dialog usable
    # useVersionSelect.ts:71-76; useDiscardGuard.tsx:18-60; DiscardChangesDialog.tsx:23-106; CollaborativeEditor.tsx:341-346
    # useVersionSelect.test.tsx:140-229; CollaborativeEditor.discardGuard.test.tsx:142-235

  @S07 @pending
  Scenario: The version list catches up with saves
    # Value: nobody pins or restores from a list that is missing the latest save or publish.
    Given I opened the version chip on "Intake" once
    When anyone in the room saves "Intake"
    And I open the version chip again
    Then the list is fetched again and includes the new save
    # createSessionContextStore.ts:303-317, :556-575; VersionDropdown.tsx:114-134; SnapshotVersionDropdown.tsx:85-103
    # VersionDropdown.test.tsx:401-438, :512-540; SnapshotVersionDropdown.test.tsx:110-139

  @S08 @pending
  Scenario: A version list that fails to load says so and tries again
    # Value: a passing failure doesn't leave history unreachable for the rest of the session.
    Given loading the versions of "Intake" fails
    When I open the version chip
    Then I see "Failed to load versions" in the menu and as an alert
    When I close and reopen the chip
    Then the versions are requested again
    # VersionDropdown.tsx:128-143, :212-215; SnapshotVersionDropdown.tsx:97-112; createSessionContextStore.ts:416-424, :473-480
    # VersionDropdown.test.tsx:439-511, :1181-1250; SnapshotVersionDropdown.test.tsx:140-207

  @S09 @pending @variant:experimental-features
  Scenario: Editor restores an earlier publish without taking the workflow offline
    # Value: a bad go-live can be rolled back in one step while the workflow keeps serving.
    Given "Intake" is live with publishes v1 and v2, and v2 broke a job
    And I am an editor
    When I choose "Restore" on the v1 row
    Then I see "Restore v1?" explaining that v1's content is put back and published, and later work is lost
    When I choose "Restore v1"
    Then I see "Restored v1"
    And "Intake" is still live with v1's job bodies
    And the version list shows a new v3 "Restored v1"
    And choosing "Restore" did not also pin v1
    # VersionDropdown.tsx:292-310; CollaborativeEditor.tsx:143-197; RestoreVersionDialog.tsx:106-114, :174-190
    # workflow_channel.ex:455-482; workflows.ex:1460-1472, :380-405; snapshot.ex:344-352
    # workflow_channel_test.exs:2437-2476; VersionDropdown.test.tsx:1274-1310; RestoreVersionDialog.test.tsx:110-120

  @S10 @pending @variant:experimental-features
  Scenario: The restore dialog says which triggers it will delete or bring back off
    # Value: nobody silently breaks an integration that calls a webhook URL, or forgets to re-enable a trigger.
    Given "Intake" gained a webhook at "/payments" and lost its cron trigger since v1
    When I choose "Restore" on the v1 row
    Then "Restore v1" stays disabled with "Checking what this will change..." until the check answers
    And I see "One trigger will be deleted" naming "the webhook at /payments, which is on now" and "Anything calling those URLs stops working."
    And I see "One trigger comes back switched off" naming "a scheduled trigger", explaining that a version does not record its authentication
    # RestoreVersionDialog.tsx:41-47, :116-170, :185; CollaborativeEditor.tsx:143-164; workflow_channel.ex:434-452, :1434-1461
    # RestoreVersionDialog.test.tsx:70-108; CollaborativeEditor.restore.test.tsx:151-208; workflow_channel_test.exs:2537-2587, :2608-2614

  @S11 @pending @variant:experimental-features
  Scenario: Viewers can't restore
    # Value: only people trusted to change the workflow can roll production back.
    Given I am a viewer on "Intake"
    When I open the version chip
    Then no row offers "Restore"
    And a restore request sent anyway is refused with a permission message
    # CollaborativeEditor.tsx:135, :271-273; VersionDropdown.tsx:294; workflow_channel.ex:460, :1950-1956
    # VersionDropdown.test.tsx:1311-1320; workflow_channel_test.exs:2484-2504

  @S12 @pending @variant:experimental-features
  Scenario Outline: A refused restore says why and leaves the workflow as it was
    # Value: a restore never half-happens, and a colleague's save is not overwritten by one.
    Given I am an editor restoring v1 of "Intake"
    When <cause>
    Then I see "Could not restore v1" with "<message>"
    And the restore dialog stays open and usable
    Examples:
      | cause                                         | message                                                  |
      | someone else saves "Intake" at the same time  | Someone else saved this workflow. Try the restore again. |
      | v1 no longer exists                           | That version no longer exists                            |
    # workflow_channel.ex:461-463, :479, :1428-1432, :1670-1686; CollaborativeEditor.tsx:166-186; RestoreVersionDialog.tsx:69-75
    # workflow_channel_test.exs:2478-2482, :2589-2606; RestoreVersionDialog.test.tsx:121-132

  @S13 @pending
  Scenario: Member sees recent activity without leaving the editor
    # Value: people can tell at a glance whether the workflow is working.
    Given "Intake" has work orders with runs
    When I expand the history panel on the canvas, or press Ctrl+H (Cmd+H on a Mac)
    Then "Recent History" lists the most recent work orders newest first, each with its state and when it last ran
    And expanding a work order lists its runs with state, when and how long
    And the panel stays expanded or collapsed the next time I open the editor
    # MiniHistory.tsx:555-597, :633-649, :745-891; CollaborativeWorkflowDiagram.tsx:73-93, :234-256; workflow_channel.ex:253-265, :2351-2387; work_orders.ex:553-580
    # MiniHistory.test.tsx:266-375, :427-587; CollaborativeWorkflowDiagram.preferences.test.tsx:214-283; workflow_channel_test.exs:4963-5114

  @S14 @pending
  Scenario Outline: The history panel says when there is nothing to show or it could not load
    # Value: a failed load is never mistaken for a workflow that has never run.
    Given <condition>
    When I expand the history panel
    Then I see "<message>"
    Examples:
      | condition                         | message                                                              |
      | "Intake" has never run            | No related history                                                   |
      | history is still loading          | Loading history...                                                   |
      | loading history failed            | Failed to load history, with a "Retry" button that asks again        |
    # MiniHistory.tsx:826-877; CollaborativeWorkflowDiagram.tsx:318-323; createHistoryStore.ts:667-700
    # MiniHistory.test.tsx:376-426, :995-1147

  @S15 @pending
  Scenario: Picking a run shows it on the version it ran on
    # Value: the canvas a run is read against is the shape that actually produced it.
    Given run "a1b2c3" of "Intake" ran on save 3, and save 5 is current
    When I pick that run in the history panel
    Then the URL carries "v=3" and "run=a1b2c3"
    When I pick a run that ran on save 5 instead
    Then the pin is removed and "run" names that run
    And picking a work order with a single run picks that run
    # CollaborativeWorkflowDiagram.tsx:192-205; MiniHistory.tsx:584-597
    # CollaborativeWorkflowDiagram.runSelection.test.tsx:278-308; MiniHistory.test.tsx:508-553

  @S16 @pending @variant:experimental-features
  Scenario: On a live workflow, a run of older content opens as it executed
    # Value: a run of an earlier publish is shown on the content it ran, without making the live workflow editable.
    Given "Intake" is live and run "a1b2c3" ran on content that is no longer live
    When I pick that run in the history panel
    Then the URL carries "as_run=a1b2c3" and "run=a1b2c3"
    And the chip reads that run's version, or "unpublished"
    When I have unsaved changes in a sandbox or draft and pick a run of older content there
    Then I am asked before my edits are thrown away
    # CollaborativeWorkflowDiagram.tsx:207-217; useViewAsExecuted.ts:15-27; VersionDropdown.tsx:51-53, :67-77
    # CollaborativeWorkflowDiagram.runSelection.test.tsx:205-277, :325-340; useViewAsExecuted.test.tsx:39-145; VersionDropdown.test.tsx:161-207

  @S17 @pending
  Scenario: A run read on another version says so and offers to switch
    # Value: nobody misreads a run against a workflow shape that has changed since it ran.
    Given run "a1b2c3" ran on save 3 and the canvas shows save 5 with that run selected
    When I look at the history panel
    Then I see "This run took place on version 3." and "View as executed"
    When I choose "View as executed"
    Then the canvas switches to save 3, asking first if I have unsaved changes
    # useVersionMismatch.ts:28-80; VersionMismatchBanner.tsx:29-67; MiniHistory.tsx:810-818, :883-890; CollaborativeWorkflowDiagram.tsx:173-190
    # MiniHistory.test.tsx:195-265

  @S18 @pending @variant:experimental-features
  Scenario: Reading a publish shows only the runs of that publish
    # Value: people can see what one publish did in production without other versions' runs mixed in.
    Given "Intake" has runs on v1 and on v2
    When I open v1 from the version chip
    Then the history panel lists only the work orders with runs on v1
    # CollaborativeWorkflowDiagram.tsx:234-264; createHistoryStore.ts:681-688; workflow_channel.ex:235-250, :2323-2340; work_orders.ex:620-650
    # workflow_channel_test.exs:5115-5157 (server only; nothing on the client asserts the filter is sent)

  @S19 @pending @variant:experimental-features
  Scenario: Each run is tagged with the version it ran on
    # Value: people can tell which publish a run belongs to without opening it.
    Given "Intake" is live and its runs ran on v2 and on content never published
    When I expand a work order in the history panel
    Then runs read "v2" or "unpublished" before the run id
    And on a draft they read the save number instead
    And without experimental features no tag is shown
    # MiniHistory.tsx:130-162, :266-343; workflow_channel.ex:2372-2387; workflow_releases.ex:85-106
    # MiniHistory.test.tsx:109-165, :1409-1440; workflow_channel_test.exs:5084-5114

  @S20 @pending
  Scenario: History links lead to the full history, a work order or a run
    # Value: people can go from the summary to the detail they need.
    Given the history panel lists work order "wo1" with run "r1"
    When I choose the stack icon "View full history for this workflow"
    Then I am taken to the history page filtered to "Intake"
    When I choose the work order id
    Then I am taken to the history page filtered to that work order
    When I choose the run id
    Then I am taken to that run's page
    # MiniHistory.tsx:603-631, :769-784; navigation.ts:26-79; MiniHistory.test.tsx:768-882

  @S21 @pending @variant:experimental-features
  Scenario: Editor copies a live workflow into a new sandbox and lands in it
    # Value: a production workflow can be changed and tested without touching what is live.
    Given "Intake" is live in an ordinary project and I am an editor
    When I choose "Edit in sandbox"
    Then I see "Edit in sandbox" with "Create a new sandbox" and "Starts from the version live now."
    And "Create sandbox" is disabled until I type a name
    When I type "Trying dates" and choose "Create sandbox"
    Then a sandbox is created from the parent with this workflow's copy as a disabled draft
    And the flow "flow-edit-in-sandbox" has started for that sandbox's copy of "Intake"
    # Header.tsx:836-858, :977-982; EditInSandboxPicker.tsx:589-621, :718-721, :888-1003, :384-393
    # workflow_channel.ex:367-406; projects.ex:2400-2432
    # EditInSandboxPicker.test.tsx:901-923, :1059-1111, :1260-1286; Header.sandbox.test.tsx:635-660; workflow_channel_test.exs:914-950, :959-966

  @S22 @pending @variant:experimental-features
  Scenario: Starting a sandbox from the open run's input, checked first
    # Value: a fix can be tried against the data that broke production, with anything sensitive removed before it leaves.
    Given run "a1b2c3" is open in "Intake" and its input was kept
    When I choose "Edit in sandbox"
    Then "This run's input" is selected and the button reads "Continue"
    When I choose "Continue"
    Then I see "Check the data before it leaves production" with the input in an editable JSON editor
    When I remove a field and choose "Create sandbox"
    Then the sandbox starts with my edited copy named "Input from run a1b2c3" and the original is untouched
    When I instead edit it into something that is not a JSON object
    Then I see "This needs to be a JSON object." or "This isn't valid JSON." and nothing is created
    # EditInSandboxPicker.tsx:446-472, :623-699, :337-353, :770-885; workflow_channel.ex:2035-2046; sandboxes.ex:191-245
    # EditInSandboxPicker.test.tsx:235-258, :297-411, :665-692; workflow_channel_test.exs:781-803

  @S23 @pending @variant:experimental-features
  Scenario: A run whose input was not kept can't seed a sandbox
    # Value: nobody starts a sandbox believing it holds real data when it holds none.
    Given the open run's input was not kept
    When I choose "This run's input" and "Continue"
    Then I see "This run's input was not kept, so there is nothing to copy." and "Continue" is disabled
    # EditInSandboxPicker.tsx:649-654, :718-721, :1041-1050; EditInSandboxPicker.test.tsx:634-664

  @S24 @pending @variant:experimental-features
  Scenario: The picker says when the sandbox forks a newer version than the run used
    # Value: people know their sandbox holds the current workflow, not the version their run ran on.
    Given the open run ran on v2 and v3 is live
    When I choose "This run's input"
    Then I see "This run used v2. The sandbox starts from v3, the version live now"
    # EditInSandboxPicker.tsx:545-561, :826-834, :1052-1062; EditInSandboxPicker.test.tsx:693-751

  @S25 @pending @variant:experimental-features
  Scenario: Starting a sandbox from a saved input
    # Value: a named input meant for reuse can travel into a sandbox; transient step results can't.
    Given the project has named inputs "Sample patient" (saved input) and "Step result" (step result)
    When I choose "A saved input"
    Then only "Sample patient" is listed, and "Create sandbox" waits until I pick it
    When I pick it and create the sandbox
    Then it is sent by id and the sandbox starts with a copy of it
    When it was removed from the project in the meantime
    Then I see "That saved input is no longer available in this project."
    # EditInSandboxPicker.tsx:203-295, :331-335, :510-543, :624-627; workflow_channel.ex:383, :1581-1585, :2027-2033; sandboxes.ex:169-189
    # EditInSandboxPicker.test.tsx:752-900; workflow_channel_test.exs:804-870

  @S26 @pending @variant:experimental-features
  Scenario: Editor continues in a sandbox that already holds the workflow
    # Value: people pick up a colleague's work instead of forking production again.
    Given sandboxes "fix-dates" and "old-try" of the project hold a workflow named "Intake", and "gone" is scheduled for deletion
    When I open "Edit in sandbox"
    Then "Continue in a sandbox" lists "fix-dates" and "old-try", newest first, each with its owner and when it was created
    And sandboxes without "Intake" and "gone" are not listed
    When I choose "fix-dates"
    Then the flow "flow-edit-in-sandbox" has started for the "Intake" copy in "fix-dates"
    And the section is hidden when no sandbox qualifies
    # EditInSandboxPicker.tsx:95-167, :474-508, :701-710, :1079-1113; workflow_channel.ex:343-364, :2070-2094; projects.ex:2184-2217
    # EditInSandboxPicker.test.tsx:929-1057, :1287-1310; workflow_channel_test.exs:581-697

  @S27 @pending @variant:experimental-features
  Scenario: A sandbox name already used under the project is refused in place
    # Value: two sandboxes of the same project are never confused by name.
    Given the project already has a sandbox "trying-dates"
    When I create a sandbox named "Trying dates"
    Then I see "A sandbox with this name exists already." under the name field
    # EditInSandboxPicker.tsx:79-93, :604-614, :993-1003; workflow_channel.ex:2048-2056; EditInSandboxPicker.test.tsx:1125-1190

  @S28 @pending @variant:experimental-features @variant:sandbox-limited
  Scenario: The plan's sandbox limit stops a new sandbox but not joining one
    # Value: the plan's sandbox limit is explained before anyone tries, and existing sandboxes stay usable.
    Given the plan allows no more sandboxes
    When I open "Edit in sandbox"
    Then "Create sandbox" is disabled with a lock and the limiter's message as its tooltip
    And typing a name or pressing Enter does not get past it
    And a create request sent anyway is refused with the limiter's message
    And I can still join a listed sandbox
    # EditInSandboxPicker.tsx:397-401, :913-987; workflow_channel.ex:382, :1688-1694, :2020-2025, :2433-2450
    # EditInSandboxPicker.test.tsx:1322-1413; workflow_channel_test.exs:967-986

  @S29 @pending @variant:experimental-features
  Scenario: People who can't create sandboxes can't start one from the editor
    # Value: only people trusted to change the project can copy it into a sandbox.
    Given I am a viewer on "Intake", which is live
    Then "Edit in sandbox" is disabled with "You do not have permission to create a sandbox in this project."
    And listing or creating sandboxes is refused by the server
    And while I read an older publish as an editor, "Edit in sandbox" is disabled too
    # Header.tsx:259-261, :836-858; workflow_channel.ex:347-363, :381, :1979-1989; policies/sandboxes.ex:94-96
    # Header.sandbox.test.tsx:251-266, :408-416; workflow_channel_test.exs:698-720, :987-1009

  @S30 @pending @variant:experimental-features
  Scenario: Leaving for a sandbox with unsaved changes asks first
    # Value: nobody loses work by jumping to a sandbox.
    Given I have unsaved changes in "Intake"
    When I choose a sandbox to continue in
    Then I see "You have unsaved changes" and nothing navigates yet
    When I choose "Save and switch"
    Then the workflow is saved and then I am taken to the sandbox, without the browser's own leave warning
    # EditInSandboxPicker.tsx:367-374, :395, :601-603, :705-707, :1120-1126; unloadGuard.ts:5-7; shared-editor-session S20
    # EditInSandboxPicker.test.tsx:1415-1561, :1563-1625

  @S31 @pending
  Scenario: Save & Sync hands off to the GitHub sync flow
    # Value: an editor can publish their change to the project's repository from where they made it.
    Given "Intake" is in a project connected to GitHub and I am an editor
    When I choose "Save & Sync"
    Then the dialog "Save and sync changes to GitHub" names the repository and branch
    And the flow "flow-github-sync-actions" has started when I confirm
    # Header.tsx:144-191, :910; GitHubSyncModal.tsx:33-212; owned by flow-github-sync-actions S02

  @S32 @pending @variant:experimental-features
  Scenario: Promote hands off to the sandbox merge flow, and only acts on the current workflow
    # Value: nobody promotes a version they are only reading, believing it is what they are sending.
    Given "Intake" is open in a sandbox
    When I choose "Promote"
    Then the flow "flow-sandbox-merge" has started
    When I am reading an older save of it instead
    Then "Promote" is disabled with "You are reading the past. Promote acts on the current workflow."
    # Header.tsx:347-349, :820-834, :967-976; owned by flow-sandbox-merge S06 to S15

  @S33 @pending
  Scenario: Any open view of the workflow counts as open for API writes
    # Value: an API update can't land under someone who is reading or editing the workflow, whichever version they hold.
    Given I have "Intake" open on an older save
    Then the flow "flow-workflow-api-edit-conflict" treats "Intake" as open in the editor
    # flow-workflow-api-edit-conflict reachable_when (workflow_channel.ex:62-72; workflow_resolver.ex:161-199)

  @S34 @pending @variant:experimental-features
  Scenario: A restore reaches colleagues who have the workflow open
    # Value: everyone working on the workflow sees the rolled-back content, not a copy that no longer exists.
    Given "Ben" has "Intake" open on Latest
    When I restore v1
    Then the flow "flow-restore-version-open-editor" has started for "Ben"
    # workflow_channel.ex:464-466; workflow_reconciler.ex:90-120
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The history panel's "Retry" asks for history without the publish filter the first request used, so a reader of v1 whose history failed sees every recent run after retrying. Read from code | `CollaborativeWorkflowDiagram.tsx:243-246` vs `:320-323`; `createHistoryStore.ts:681-688` | a v1 view listing runs of v2 and drafts | fix |
| "Edit in sandbox" creates the sandbox before asking about unsaved changes; choosing "Cancel" leaves the new sandbox behind and re-enables "Create sandbox", and a second try fails on the name. The test for this path asserts only that the button is enabled and nothing navigated | `EditInSandboxPicker.tsx:595-603`, `:712-716`; `EditInSandboxPicker.test.tsx:1515-1539` | "A sandbox with this name exists already." for a sandbox they think they cancelled | fix |
| "Continue in a sandbox" lists every active sandbox of the project that holds the workflow, with its owner's name or email, whether or not the viewer is a member of it; joining one they are not on lands on "project not found" | `projects.ex:2184-2202`; `workflow_channel.ex:343-364`, `:2070-2094`; shared-project-scope S03 | a sandbox offered, then refused | decide |
| Live `history_updated` events add any new work order to the list, including while it is filtered to one publish, so runs of the live version appear in an older publish's history. Read from code | `createHistoryStore.ts:286-300`; `CollaborativeWorkflowDiagram.tsx:234-256` | runs from other versions creeping into a v1 view | fix |
| The tooltip on the disabled "Edit in sandbox" button while a version is pinned says "This acts on the current workflow.", which describes an action the button won't take | `Header.tsx:343-345`, `:836-850` | a tooltip that reads as if the button works | fix |
| The history panel's close button is labelled "Back to landing" for screen readers but closes the panel | `MiniHistory.tsx:667-675` | screen readers announce the wrong action | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A failed restore check, or one the server refuses (no permission, unknown version), shows no trigger warnings at all and lets the restore go ahead, so "nothing will break" and "we couldn't tell" look the same. Deliberate per its test | `CollaborativeEditor.tsx:157-161`; `workflow_channel.ex:447-450`; `CollaborativeEditor.restore.test.tsx:210-222` | decide |
| A late answer for a restore check the person abandoned is ignored | `CollaborativeEditor.tsx:141-155`; `CollaborativeEditor.restore.test.tsx:167-208` | preserve |
| Restoring while reading an older version leaves that view pinned and its idea of the workflow unchanged | `workflow_channel.ex:468-473`; `workflow_channel_test.exs:2411-2435` | preserve |
| The restore dialog can't be dismissed (Cancel, Escape, backdrop) while a restore is in flight | `RestoreVersionDialog.tsx:62-67`, `:174-178` | preserve |
| "Restore" is invisible until the row is hovered or the link focused | `VersionDropdown.tsx:296-305` | decide |
| The discard guard on version switching exists only with experimental features; without them switching never asks | `useVersionSelect.ts:71-74`; `useVersionSelect.test.tsx:123-138` | decide |
| The saves list says "latest" in lower case and formats dates with the browser locale; the publishes list says "Latest" and uses "d MMM yyyy" | `SnapshotVersionDropdown.tsx:183-185`, `:216`; `VersionDropdown.tsx:202`, `:231-236` | decide |
| Save numbers are cut with `substring(0, 7)`, a leftover from hash-style versions; harmless for integers | `SnapshotVersionDropdown.tsx:48`, `:198` | decide |
| The pinned label is built from the raw URL value, so `?release=abc` reads "vabc" | `VersionDropdown.tsx:67-71` | decide |
| "v3" means publish 3 in one list and save 3 in the other; they are separate rooms | `pinnedView.ts:56-67`; `workflow_channel_test.exs:2686-2729` | preserve |
| Saves are sorted current first, then by number descending; a run's publish number is the newest publish of its save | `workflow_channel.ex:644-646`; `workflow_releases.ex:85-106` | preserve |
| Version lists for a new workflow short-circuit to empty | `workflow_channel.ex:599-600`, `:628-629` | preserve |
| The history panel's collapsed state is remembered per browser | `CollaborativeWorkflowDiagram.tsx:73-82`; `CollaborativeWorkflowDiagram.preferences.test.tsx:214-283` | preserve |
| Without the flag, history rows are filled pills and runs carry no version tag; with it, coloured dots and tags | `MiniHistory.tsx:173-181`, `:357-365`, `:130-162`; `MiniHistory.test.tsx:109-220` | decide |
| The IDE's history panel picks a run without pinning its version or opening it as executed, and is never filtered to a publish, unlike the canvas panel | `FullScreenIDE.tsx:266-273`, `:582`, `:1294-1310`; `CollaborativeWorkflowDiagram.tsx:192-227` | decide |
| Links out of the history panel are full page loads | `navigation.ts:26-79` | preserve |
| The sandbox name typed is made URL-safe on the server ("Trying dates" becomes "trying-dates"); a name of only symbols becomes blank and is refused as a field error. Read from code | `workflow_channel.ex:2048-2056`; `lib/lightning/helpers.ex:221-228` | decide |
| A sandbox made from the editor always gets env "dev" and a random colour; the sandboxes page lets people choose | `workflow_channel.ex:373-378` | decide |
| "This run's input" is the first step's input of the open run | `EditInSandboxPicker.tsx:446-447` | decide |
| A reviewed body without a name is called "Reviewed input" | `EditInSandboxPicker.tsx:697`; `sandboxes.ex:212-219` | preserve |
| The server lets a pinned room create a sandbox, branching from the current workflow; only the client disables the button | `workflow_channel.ex:371`, `:2058-2063`; `workflow_channel_test.exs:746-780` | preserve |
| Joining or landing in a sandbox goes through the LiveView redirect, falling back to a hard navigation that suppresses the unload warning | `EditInSandboxPicker.tsx:355-393`; `EditInSandboxPicker.test.tsx:1563-1625` | preserve |
| The sandbox list and the saved inputs failing to load are toasts; the picker stays usable | `EditInSandboxPicker.tsx:491-497`, `:527-534` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `request_history` with `"draft"` or `"unversioned"`, and `WorkOrders.get_workorders_unversioned/1` | `workflow_channel.ex:2323`, `:2342-2349`; `work_orders.ex:662-700` | the client only ever sends the `release` URL value (`CollaborativeWorkflowDiagram.tsx:243-246`); covered only by `workflow_channel_test.exs:5158` |
| `default_sandbox_name/2` ("<workflow>-sandbox") | `workflow_channel.ex:2048-2053`, `:2065-2068` | the picker never sends a blank name (`EditInSandboxPicker.tsx:718-721`; `createWorkflowStore.ts:1623-1626`) |
| `VersionPicker.tsx` | `ConfigureAdaptorModal.tsx:568` | the adaptor version combobox, not part of this view; owned by shared-adaptor-credential-config |
| `WorkflowDiffBlocks.tsx` | `MessageList.tsx:1260` | rendered only under AI assistant replies |
| `request_history` with `run_id` while a publish is pinned | `createHistoryStore.ts:681-688` | `version_number` wins, so the run's work order is not guaranteed in the list |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| History holds 20 work orders, live updates drop the oldest past 20 | `work_orders.ex:569-580`; `createHistoryStore.ts:296-299` | yes, older work orders need the full history page | preserve |
| Saved inputs fetched with `limit: 100`, named only | `EditInSandboxPicker.tsx:517-520` | yes, past 100 not offered | preserve |
| Reviewed input capped at `max_dataclip_size_bytes` | `sandboxes.ex:233-235`; `workflow_channel.ex:1571-1575` | yes, "The input you reviewed is too large to copy into a sandbox." | preserve |
| Version lists and restore checks run as unsupervised tasks; a crash replies "failed to handle <event>" | `workflow_channel.ex:1203-1225` | yes, as "Failed to load versions" | preserve |
| The publishes list re-reads all publishes with their snapshots, publishers and source projects on every open after a save | `workflow_releases.ex:52-62` | no | preserve |

### 6.5 Things seen but not understood

- The discard dialog says unsaved changes "are gone" when switching version or leaving for a sandbox, but shared-editor-session S03 says the shared draft is persisted and survives a reload. Whether switching rooms actually loses anything that had reached the server was not traced (`DiscardChangesDialog.tsx:28`; `useDiscardGuard.tsx:1-4`; shared-editor-session S03). (decide)
- `handleGoToVersion` calls `handleVersionSelect` with a save number; under the publishes list that would set `release=<save number>`. It looks unreachable because the publishes list and the content lock share the same conditions, but the two are computed separately on client and server (`CollaborativeWorkflowDiagram.tsx:175-190`; `useVersionPicker.ts:16-25`; `workflow_channel.ex:1507-1510`). (decide)
- A restore puts back the snapshot's credential ids; what happens when a credential has since left the project (scope check, foreign key) was not followed (`snapshot.ex:301-308`; `workflows.ex:337-339`). (decide)
- The saves list shows "latest" only when its newest entry is the current save; a workflow whose current lock version has no snapshot would offer no way back from the list. Not checked whether such workflows exist (`SnapshotVersionDropdown.tsx:168-192`; `workflow_channel.ex:631-641`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. New route shape for pinned views: keep `v`, `release` and `as_run` as query parameters, or give versions their own path?
2. Should the editor list sandboxes the viewer cannot open (6.1 row 3)?
3. `WorkflowDiffBlocks.tsx` is in this view's inventory row but renders only in the AI assistant; workflow-editor-ai-assistant should take it.
4. shared-editor-session `not_reachable_here` gives Ctrl/Cmd+H to workflow-editor-canvas, which does not cover it; this file takes it (S13). One of the two should change.
5. flow-manual-run-live-follow does not list this view in its surfaces although new work orders reach the history panel through it; either add it or drop the reference here.
6. Should the discard dialog's "they are gone" copy stand (6.5 item 1)?
7. Is the silent restore check failure (6.2 row 1) the intended trade-off?

## Proposed flows

- `flow-restore-version-open-editor`: a restore commits, `ReconcileRequested` resets every open live document of the workflow in place, collaborators see the restored content (and lose unsaved shared edits), and their version lists refetch on `workflow_saved`. Surfaces: workflow-editor-versions-and-promote, pubsub:workflow_collaboration:<workflow id>#ReconcileRequested, workflow-editor-canvas (a colleague's open editor), workflow-editor-ide.
- `flow-edit-in-sandbox`: an editor creates or joins a sandbox from a live workflow, is redirected to the sandbox's copy of the workflow, and lands on the run panel with the carried input preselected when one was chosen. Surfaces: workflow-editor-versions-and-promote, controller:liveview-redirect (/projects/<sandbox>/w/<copy>?panel=run&dataclip=<id>), shared-project-scope (membership gate on the sandbox), workflow-editor-manual-run, workflow-editor-canvas.

## Proposed shared

none. Referenced: shared-authenticated-session, shared-project-scope (S03, S11), shared-editor-session (S07, S10, S14, S20), shared-dataclip-body-viewer (endpoint access only); shared-adaptor-credential-config owns `VersionPicker.tsx`.

## Lead resolution (batch 6)

- `flow-restore-version-open-editor` and `flow-edit-in-sandbox` created. This view added to flow-manual-run-live-follow surfaces.
