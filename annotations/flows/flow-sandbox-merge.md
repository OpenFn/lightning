---
id: flow-sandbox-merge
type: flow
title: Merge a sandbox into its parent
status: not-started
owner:

trigger:
  entry: sandboxes-index                      # or workflow-editor-versions-and-promote (the editor's Promote button)
  exit: workflows-index                       # the parent's workflow list after a list merge; the parent's editor after promote and archive
  surfaces:
    - sandboxes-index
    - workflow-editor-versions-and-promote
    - external:github-workflow-dispatch       # list merge only, when the parent is synced
    - pubsub:workflow_collaboration:<parent workflow id>#ReconcileRequested
    - workflow-editor-canvas                  # a colleague's open editor on the parent workflow
    - pubsub:project_events:<parent id>#WorkflowDeleted   # list merge only, when a deletion was ticked
    - pubsub:project_events:<sandbox subtree ids>#ProjectDeletionScheduled
    - workflows-index
    - workflow-editor-canvas                  # the parent's copy of the workflow, after promote and archive
  reachable_when:
    - "list entry: the merge action is enabled on a sandbox card (admin or owner on the sandbox, or on the workspace root) and the viewer is editor or above on the target (sandboxes-index S32-S34; index.ex:476-550)"
    - "editor entry: experimental features on for the viewer, the workflow is saved and the project has a parent (Header.tsx:259, :820-834)"

inherits:
  - shared-project-scope            # S10 and S11 are the receiving end of the archive; S12 the receiving end of a merged deletion
  - shared-authenticated-session

url_params:
  - name: archived=1
    set_by: shared-project-scope S11 (hooks.ex:399-411)
    effect: the parent editor shows the "Promoted to parent project" or "Sandbox archived" toast once, then strips the param (PromotedNotice.tsx:14-38)

config_variants:
  default: {}                                          # experimental features off; only the list entry exists; read under this one
  experimental-features: { user.preferences.experimental_features: true }   # Promote button and the archive redirect to the parent copy (Header.tsx:255-259; hooks.ex:296-317); read under this one
  github-sync: { parent has a project_repo_connection }  # data state; list entry only (index.ex:1128-1160)

inventory:
  routes: []                                           # owned by sandboxes-index and the editor
  events:
    - SandboxLive.Index#confirm-merge                  # owned by sandboxes-index; this flow asserts what follows it
    - WorkflowChannel#request_promote_check            # workflow_channel.ex:409-430
    - WorkflowChannel#promote                          # workflow_channel.ex:485-498
    - WorkflowChannel#archive_sandbox                  # workflow_channel.ex:501-513
  js_hooks: []                                         # React: PromoteDialog.tsx, PromotedNotice.tsx, lib/promoteHandoff.ts
  policies:
    - Lightning.Policies.Sandboxes (:merge_sandbox on the parent, :delete_sandbox on the sandbox) (policies/sandboxes.ex:98-119)
    - Lightning.Policies.Credentials (:create_keychain_credential, inside merge; sandboxes.ex:619-626)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Sandboxes.merge/4 with no :selected_workflow_ids (delete every unmatched target workflow; merge_projects.ex:878-886); neither entry omits it
    - Sandboxes.preview_collections/2 (sandboxes.ex:1430-1445); the list modal computes its own preview

related:
  - sandboxes-index                      # owns the merge modal (S32-S47): targets, workflow, credential and collection selection, error copy
  - flow-sandbox-scheduled-deletion      # the archive half: subtree scheduled, triggers off, purge
  - flow-delete-open-workflow            # a merged deletion bounces open editors the same way (provisioner.ex:132-134)
  - flow-github-sync-actions             # started by the list merge (sandboxes-index S47)
  - shared-project-settings-tab-chrome   # its 6.1 row on what merge carries is answered here
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/projects/merge_projects.ex
  - lib/lightning/projects/provisioner.ex
  - lib/lightning/projects.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/hooks.ex
  - assets/js/collaborative-editor/components/Header.tsx
  - assets/js/collaborative-editor/components/PromoteDialog.tsx
  - assets/js/collaborative-editor/components/PromotedNotice.tsx
  - test/lightning/sandboxes_test.exs
  - test/lightning/projects_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning/collaboration/reconcile_workflow_document_test.exs
  - test/lightning_web/live/project_live/deletion_teardown_test.exs
  - assets/test/collaborative-editor/components/Header.sandbox.test.tsx
  - assets/test/collaborative-editor/components/PromotedNotice.test.tsx
flows: []
---

## 1. Purpose

People who build workflows try changes in a sandbox, then bring them back to the live parent
project, either the whole sandbox from the sandboxes list or one workflow at a time from the
editor. The live project has to end up with exactly what was chosen, nothing half-applied, and
colleagues working on the parent or in the sandbox have to see the result rather than keep
working on a stale or retired copy.

## 2. What it does

1. An admin merges a whole sandbox from the sandboxes list, or an editor clicks "Save and promote" on one workflow in the sandbox editor.
   - The promote dialog warns first if the parent's copy of that workflow has changed since the sandbox was made
   - From the list, a parent that syncs to GitHub is committed to the repository before and after the merge
2. The parent is updated all at once or not at all: the chosen workflows change, the chosen credentials and keychains come across, missing collections are created empty, and the parent's own settings and team stay as they were.
3. Colleagues with a parent workflow open see the merged version appear without reloading; anyone with a workflow open that the merge deleted is moved off it.
4. The sandbox is retired: a list merge always schedules it for deletion, while after a promote an admin can choose "Archive sandbox" or anyone can keep it to promote more workflows. Its triggers are switched off and anyone still in it is moved out.
5. The person who merged lands on the parent's workflow list, or after promote and archive, on the parent's copy of the workflow with "Promoted to parent project".

**Straightforwardness: 2 of 5.** The two ways in look like the same action but carry different things across, and several of the differences quietly leave the live project in a state the person didn't expect.

### Most surprising behaviours

- **(2)** Promoting one workflow doesn't bring across credentials that only the sandbox has. The dialog says "Changes promoted" and the live job then fails because it has no credential. (6.1)
- **(2)** The promote dialog says the parent "starts processing data with these changes", but a workflow that is new to the parent arrives as a draft with its triggers off, so it never runs. (6.1)
- **(2)** Workflows are matched by name. Rename one in the sandbox and promoting it creates a second workflow in the parent while the old one keeps running. (6.2)
- **(3)** The merge wins over whatever is in the parent. A colleague mid-edit on the parent workflow has their screen reset to the merged version, and their unsaved changes are overwritten. (S02, 6.2)
- **(3)** Promote does less than a list merge in other ways too: it creates every sandbox-only collection in the parent, even unrelated ones, and it skips the GitHub commit, so a synced repository falls behind. (6.1)

## 3. Who can do what

Columns are the viewer's role on the project named in the row. Sources: `policies/sandboxes.ex:64-70`,
`:98-119`; `workflow_channel.ex:485-513`, `:1991-2012`, `:1526-1527`; sandboxes-index section 3 for the list entry.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Merge from the list: role on the sandbox | no | no | yes | yes | no | no |
| Merge from the list: role on the parent | no | yes | yes | yes | no | no |
| See Promote in the sandbox editor (flag on) | yes | yes | yes | yes | n/a | yes |
| Promote: role on the parent | no | yes | yes | yes | no | no |
| Promote: role on the sandbox (the save that precedes it) | no | yes | yes | yes | no | yes, when support access is on |
| Archive after promote: role on the sandbox | no | no | yes | yes | no | no |

**Preconditions beyond role**
- An admin or owner on the workspace root may merge or archive any sandbox in it (`policies/sandboxes.ex:109-119`, `:178-181`).
- Promote checks only the parent side; unlike the list, it does not require admin on the sandbox (`workflow_channel.ex:490-492`; `workflow_channel_test.exs:1122-1164`; `projects_test.exs:4606-4635`).
- `:merge_sandbox` and `:delete_sandbox` go through `Scope`, so an unmet MFA requirement or a project already scheduled for deletion refuses them (`policies/sandboxes.ex:98-119`; `scope.ex:139-152`).
- A keychain only the sandbox has is carried only when the merger may create keychains on the parent (`sandboxes.ex:596-626`).
- Promote and the archive redirect need the experimental features flag on the viewer (`Header.tsx:255-259`; `hooks.ex:296-302`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `workflows`, `jobs`, `triggers`, `edges`, `workflow_versions`, `project_credentials`, `keychain_credentials`, `collections`, `project_repo_connections`

**Writes** (one transaction, `sandboxes.ex:314-348`)
- Hop 1, credentials: `project_credentials` rows on the parent for the selected sandbox-only credentials, recomputed from the database, `ON CONFLICT DO NOTHING` (`sandboxes.ex:520-549`)
- Hop 1, keychains: `keychain_credentials` (and their default credential's `project_credentials`) for sandbox-only keychains the carried jobs use (`sandboxes.ex:582-680`)
- Hop 1, workflows: the parent's `workflows`, `jobs`, `triggers`, `edges` through `Provisioner.import_document` with `allow_stale: true`; matched by name; parent trigger on/off state kept; new workflows arrive `draft` with triggers off (`sandboxes.ex:335-341`; `merge_projects.ex:16-21`, `:952-1007`; `trigger.ex:49`; `workflow.ex:64`)
- Hop 1, history: `workflow_versions`, `workflow_snapshots`, `audit_events` (provisioner and snapshot events), and on promote one `workflow_releases` row of kind `promote` (`provisioner.ex:113-127`, `:470-540`)
- Hop 1, collections: empty `collections` for sandbox-only names, never deleting (`sandboxes.ex:1463-1475`)
- Hop 1, sync points: a `workflow_versions` row on each merged sandbox workflow with the parent's new head (`sandboxes.ex:393-420`)
- Hop 3, archive: `projects.scheduled_deletion` and `triggers.enabled = false` on the sandbox subtree (`sandboxes.ex:942-973`)

**Immediate side effects** (in the same request)
- After commit: `WorkflowUpdated` per imported workflow and `WorkflowDeleted` for deleted ones (`provisioner.ex:128-134`); `ReconcileRequested` on `workflow_collaboration:<id>` for each merged parent workflow (`sandboxes.ex:349-355`; `workflow_reconciler.ex:90-97`, `:136`)
- PromEx: provisioner import (`provisioner.ex:136-138`); sandbox merged, list entry only (`index.ex:1170`)
- List entry: flash and `push_navigate` to `/projects/<parent>/w` (`index.ex:1162-1205`)
- Promote entry: dialog moves to "Changes promoted" (`PromoteDialog.tsx:109-116`, `:226-246`)
- Archive: `ProjectDeletionScheduled` on each subtree project's topic after commit (`sandboxes.ex:965-972`); open pages leave per shared-project-scope S10 and S11
- Merge failures logged at error (`sandboxes.ex:683-716`)

**Deferred side effects**
- The nightly purge deletes the archived sandbox after the grace period (flow-sandbox-scheduled-deletion)

**External, non-transactional effects**
- List entry, parent synced to GitHub: two `openfn-pull.yml` dispatches around the merge (`index.ex:1128-1160`; sandboxes-index S47)

**Depends on config**
- Experimental features flag (editor entry and archive redirect); usage limiter (provisioner import can refuse with the limiter's text; `workflow_channel.ex:1688-1694`; sandboxes-index S45)

**Product limits**
- none beyond sandboxes-index

## 5. Scenarios

Verified against `default` for the list entry and `experimental-features` for the editor entry. The
list modal's own behaviour (targets, preselection, labels, credential and collection checkboxes, error
copy) is sandboxes-index S32-S47; the receiving redirects are shared-project-scope S10, S11 and S12.

```gherkin
Feature: Merge a sandbox into its parent
  In order to put work tried safely in a sandbox into the live project
  As someone building workflows
  I want to merge a sandbox, or promote one workflow, into its parent

  @S01 @pending
  Scenario: Merging from the list updates the parent and retires the sandbox
    # Value: work done in a sandbox reaches the live project in one step, and the sandbox can't drift on afterwards.
    Given I am an owner on project "parent" and its sandbox "test-sandbox"
    And "test-sandbox" changed job "A1" in workflow "Intake"
    And a colleague has the workflows page of "test-sandbox" open
    When I merge "test-sandbox" into "parent" from the sandboxes page
    Then I am on the workflows page of "parent" with "Successfully merged test-sandbox into parent. Sandbox scheduled for deletion."
    And job "A1" in "parent"'s "Intake" has the sandbox's body
    And "test-sandbox" is scheduled for deletion with its triggers off
    And the colleague's page follows shared-project-scope S10
    # index.ex:1162-1205; sandboxes.ex:300-363, :942-973; index_test.exs:1801-1855, :2891-2932; sandboxes_test.exs:964-1008

  @S02 @pending
  Scenario: A colleague with the parent workflow open sees the merged version
    # Value: nobody keeps editing, and later saves over, the version the merge just replaced.
    Given a colleague has "Intake" of "parent" open in the editor
    When "test-sandbox" is merged into "parent"
    Then their editor eventually shows the merged job body without a reload
    # sandboxes.ex:349-355; document_supervisor.ex:204-215; reconcile_workflow_document_test.exs:97-160

  @S03 @pending
  Scenario: A merge that fails part way leaves the parent untouched
    # Value: the live project is never left half-merged.
    Given creating the sandbox's collections in "parent" will fail
    When I merge "test-sandbox" into "parent"
    Then no workflow, credential or collection in "parent" has changed
    And "test-sandbox" is not scheduled for deletion
    # sandboxes.ex:314-348, :357-361; sandboxes_test.exs:1009-1043; index.ex:1181-1193

  @S04 @pending
  Scenario: Project settings stay the parent's
    # Value: a merge carries workflow changes only, so the live project's security, retention, concurrency and team are never overwritten from a sandbox.
    Given "test-sandbox" has a different name, MFA requirement, concurrency, retention and collaborators from "parent"
    When I merge "test-sandbox" into "parent"
    Then "parent" keeps its own name, MFA requirement, concurrency, retention and collaborators
    # merge_projects.ex:30-32; sandboxes_test.exs:1387-1494

  @S05 @pending
  Scenario: After a merge the sandbox is in step with the parent
    # Value: a later promote from the same sandbox doesn't warn about the sandbox's own earlier changes.
    Given I merged "Intake" from "test-sandbox" into "parent"
    When I open the promote dialog for "Intake" in "test-sandbox"
    Then I see no warning that the workflow has changed in "parent"
    # sandboxes.ex:393-420; sandboxes_test.exs:1214-1231; workflow_channel_test.exs:1396-1411

  @S06 @pending @variant:experimental-features
  Scenario: Promoting one workflow updates only that workflow in the parent and keeps it live
    # Value: one fix ships to production without dragging along other sandbox work or interrupting the parent's live workflows.
    Given "parent" has live workflows "alpha" and "beta" with enabled triggers
    And I edited "alpha" in sandbox "sb"
    When I click "Promote" in the editor for "alpha" in "sb"
    Then I see "Save and promote to parent project"
    When I click "Save and promote"
    Then the workflow is saved and then promoted
    And I see "Changes promoted" and "Your changes are now live in the parent project."
    And "alpha" in "parent" has my change and is still live with its triggers enabled
    And "beta" in "parent" is unchanged
    And "sb" is not scheduled for deletion
    # Header.tsx:504-545, :820-834; PromoteDialog.tsx:148-246; workflow_channel.ex:485-498; projects.ex:2452-2486
    # projects_test.exs:4513-4556; workflow_channel_test.exs:1074-1120; Header.sandbox.test.tsx:758-773, :890-922

  @S07 @pending @variant:experimental-features
  Scenario: Promote records where the parent's new version came from
    # Value: the parent's version history shows who promoted a change and from which sandbox.
    When I promote "alpha" from "sb"
    Then "alpha" in "parent" has a new version of kind promote, published by me, from "sb"
    And "beta" in "parent" has no new version
    # sandboxes.ex:367-385; provisioner.ex:514-540; projects_test.exs:4558-4595

  @S08 @pending @variant:experimental-features
  Scenario: The promote dialog warns when the parent workflow has moved on
    # Value: people see that promoting will overwrite live changes before they lose them.
    Given "alpha" in "parent" was changed after "sb" was created
    When I click "Promote" in the editor for "alpha" in "sb"
    Then "Save and promote" is disabled while the check runs
    And I see "This workflow has changed in parent since this sandbox was created. Promoting replaces that version with yours, and anything added there is removed."
    When instead only "beta" in "parent" had changed
    Then I see no warning
    # workflow_channel.ex:409-430; merge_projects.ex:1110-1125; PromoteDialog.tsx:64-89, :162-195, :208
    # workflow_channel_test.exs:1265-1288; Header.sandbox.test.tsx:775-837

  @S09 @pending @variant:experimental-features
  Scenario: Keeping the sandbox after a promote
    # Value: several workflows can be promoted from one sandbox before it is retired.
    Given I promoted "alpha" from "sb"
    When I click "Keep sandbox"
    Then the dialog closes and I see "Workflow promoted"
    And "sb" is not scheduled for deletion
    # Header.tsx:574-581; PromoteDialog.tsx:264-273; Header.sandbox.test.tsx:924-958

  @S10 @pending @variant:experimental-features
  Scenario: Archiving after a promote lands me on the parent's copy of the workflow
    # Value: the person who promoted ends on the live workflow they just changed, and the sandbox stops running.
    Given I am an owner on "sb" and I promoted "alpha" from it
    When I click "Archive sandbox"
    Then "sb" is scheduled for deletion with its triggers off
    And my editor follows shared-project-scope S11 to "alpha" in "parent"
    And I see "Promoted to parent project" with "This workflow was merged into the parent project. The sandbox has been archived."
    # Header.tsx:547-572; promoteHandoff.ts:5-25; workflow_channel.ex:501-513; hooks.ex:378-411; PromotedNotice.tsx:14-38
    # workflow_channel_test.exs:1452-1466; Header.sandbox.test.tsx:960-995; PromotedNotice.test.tsx:48-58; deletion_teardown_test.exs:73-105

  @S11 @pending @variant:experimental-features
  Scenario: A colleague in the archived sandbox is told why they moved
    # Value: someone whose sandbox was archived under them knows they are now on the live project.
    Given a colleague has "alpha" open in "sb"
    When I archive "sb" after promoting
    Then their editor follows shared-project-scope S11
    And they see "Sandbox archived" with "You are now on the parent project's workflow."
    # PromotedNotice.tsx:22-32; PromotedNotice.test.tsx:36-46, :67-80

  @S12 @pending @variant:experimental-features
  Scenario: An editor can promote but not archive
    # Value: editors ship their fix without being able to delete a sandbox others may share.
    Given I am an editor on "parent" and on "sb"
    When I promote "alpha" from "sb"
    Then "alpha" in "parent" has my change
    And I see "Ask an admin to archive this sandbox." with only a "Done" button
    And "sb" is not scheduled for deletion
    # workflow_channel.ex:1526-1527, :2003-2012; PromoteDialog.tsx:257-296
    # workflow_channel_test.exs:1122-1164, :1473-1486; Header.sandbox.test.tsx:1032-1060

  @S13 @pending @variant:experimental-features
  Scenario: Promote is refused when I can't edit the parent
    # Value: a sandbox can't be used to change a live project the person isn't trusted to edit.
    Given I am an editor on "sb" and a viewer on "parent"
    When I click "Save and promote" for "alpha"
    Then I see "Could not promote" with "You don't have permission to promote this workflow"
    And the dialog stays on its confirm step
    And "alpha" in "parent" is unchanged
    # workflow_channel.ex:490-496, :1991-2000; Header.tsx:527-545; workflow_channel_test.exs:1166-1184; Header.sandbox.test.tsx:1105-1127

  @S14 @pending @variant:experimental-features
  Scenario: A failed save stops the promote
    # Value: what reaches the parent is always what was on screen, never an older saved version.
    Given saving "alpha" in "sb" will fail
    When I click "Save and promote"
    Then I see "Could not save before promoting"
    And nothing is promoted
    # Header.tsx:505-523; Header.sandbox.test.tsx:1082-1103

  @S15 @pending @variant:experimental-features
  Scenario: A failed promote says so and changes nothing
    # Value: people know the live workflow did not change, and can try again.
    Given the merge of "alpha" will fail validation
    When I click "Save and promote"
    Then I see "Could not promote" with "Could not promote this workflow. Please try again."
    And "alpha" in "parent" is unchanged
    # workflow_channel.ex:1634-1640; sandboxes.ex:357-361; workflow_channel_test.exs:1186-1199; Header.sandbox.test.tsx:1105-1127
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Promote never passes `selected_credential_ids`, so a job in the promoted workflow that uses a credential only the sandbox has arrives in the parent with no credential, silently | `projects.ex:2463-2466`; `sandboxes.ex:306`, `:520`; `merge_projects.ex:626-628`; `sandboxes_test.exs:1672-1701` | "Changes promoted", then a live job that fails for lack of a credential | decide |
| Promote passes no `skip_collections`, so every sandbox-only collection is created in the parent, including ones unrelated to the promoted workflow | `projects.ex:2463-2466`; `sandboxes.ex:310-312`, `:344` | empty collections appearing in the live project after promoting one workflow | decide |
| Promote dialog says "The parent stays live and starts processing data with these changes", but a workflow new to the parent arrives `draft` with its triggers off | `PromoteDialog.tsx:156-160`; `merge_projects.ex:952-1007`; `trigger.ex:49`; `workflow.ex:64` | a promoted new workflow that never runs | fix |
| The list merge commits to GitHub before and after and fires the "sandbox merged" metric; promote does neither | `index.ex:1128-1160`, `:1170`; `workflow_channel.ex:485-498`; `projects.ex:2452-2486` | a synced parent whose repository doesn't get the promoted change until the next sync | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The two entries judge divergence differently: the list uses `diverged_workflows/2` (skips names the sandbox has no history for), promote uses `workflow_diverged?/3` (counts them) | `index.ex:247`; `merge_projects.ex:1067-1125` | decide |
| Merge imports with `allow_stale: true`; a concurrent edit in the parent is overwritten, and the open parent editor is reset to the merged content | `sandboxes.ex:339`, `:349-355` | decide |
| The archive reply carries `parent_project_id`, but the dialog ignores it and waits for the `ProjectDeletionScheduled` broadcast to move the tab | `Header.tsx:547-572`; `workflow_channel.ex:509`; `Header.sandbox.test.tsx:960-995` | preserve |
| `request_promote_check` answers "not diverged" to someone who can't merge into the parent, so the dialog shows no warning before the promote is refused | `workflow_channel.ex:420-428`; `workflow_channel_test.exs:1347-1371` | preserve |
| "You just promoted" crosses the navigation in `sessionStorage`; a stale marker is dropped on the next ordinary editor visit | `promoteHandoff.ts:3-25`; `PromotedNotice.tsx:15-18`; `PromotedNotice.test.tsx:67-80` | preserve |
| Without the experimental flag, archiving sends colleagues to `/projects` with "Project deleted." instead of the parent | `hooks.ex:296-308`; `deletion_teardown_test.exs:106-126` | decide |
| Workflows match by name between sandbox and parent; a promoted rename lands as a new parent workflow and the old one stays | `merge_projects.ex:96-97`, `:856-872`; `projects.ex:2469-2475` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `workflow_id` and `parent_project_id` in the promote reply | `workflow_channel.ex:493`; `projects.ex:2478-2484` | `handleConfirmPromote` awaits `promote()` and discards the result (`Header.tsx:527-529`) |
| `{:error, :not_a_sandbox}` from `promote_workflow/2` | `projects.ex:2455-2457` | the channel already returns it when `fetch_parent_project/1` is nil (`workflow_channel.ex:490`, `:495`); reached directly only from tests |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `promote` runs the whole merge synchronously in the channel process, unlike `request_promote_check`, which uses `async_task` | `workflow_channel.ex:485-498`, `:419` | yes, "Promoting..." on large projects, and other channel messages wait | decide |
| Each merged workflow triggers one reconcile broadcast; every open parent editor resets in place | `sandboxes.ex:349-355`; `workflow_reconciler.ex:99-120` | no | preserve |

### 6.5 Things seen but not understood

- When the merging user is on the sandboxes page of the sandbox being merged, the list's `push_navigate` to the parent and the `ProjectDeletionScheduled` broadcast to that same LiveView race; which one wins was not established (`index.ex:1162-1205`; `hooks.ex:294-317`).
- If the archive broadcast is missed (socket reconnecting), the dialog stays on "Archiving..." with no timeout; not followed further (`PromoteDialog.tsx:118-124`).
- The Promote button is enabled for viewers on the sandbox; the save fails first with "Could not save before promoting", not with a permission message. Not tested end to end (`Header.tsx:820-834`, `:505-523`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should promote offer the sandbox-only credentials and collections the promoted workflow uses, as the list merge does (6.1)?
- Should promote commit to GitHub when the parent is synced, as the list merge does (6.1)?
- Should both entry points use the same divergence rule (6.2)?
- What should the promote dialog say about a workflow that is new to the parent and will arrive as a draft (6.1)?

## Proposed flows

none. References flow-sandbox-scheduled-deletion (archive half), flow-delete-open-workflow (merged deletions), flow-github-sync-actions (list merge), and shared-project-scope S10, S11, S12.

## Proposed shared

none

## Summary

- Scenarios: 15 (S01 to S15), all `@pending`; S06 to S15 tagged `@variant:experimental-features`.
- Section 6: 6.1 has 4, 6.2 has 7, 6.3 has 2, 6.4 has 2, 6.5 has 3.
- Flows: none proposed; references flow-sandbox-scheduled-deletion, flow-delete-open-workflow, flow-github-sync-actions, and shared-project-scope S10, S11, S12.
- Shared: inherits shared-project-scope and shared-authenticated-session; none proposed.
- Unsure: workflow-editor-versions-and-promote, workflow-editor-canvas and workflows-index should list this flow; S04 relies on context tests, and S10's landing combines a Vitest mock with a LiveView redirect test, so nothing covers it end to end.
