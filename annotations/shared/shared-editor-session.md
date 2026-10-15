---
id: shared-editor-session
type: shared
title: Collaborative editor session
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id and /projects/:project_id/w/new (WorkflowLive.Collaborate), plus the workflow:collaborate:<id> channel it opens
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; collaborate.ex:25)
    - for :edit, the workflow belongs to the project and is not deleted (collaborate.ex:26; hooks.ex:138-158)
    - the user socket token resolves to a live session (user_socket.ex:30-51)

inherits:
  - shared-authenticated-session    # live_session :default (router.ex:303); socket token minted by the same session
  - shared-project-scope            # S07 to S12 are the LiveView half of every teardown below
  - shared-usage-limits-banner      # :check_limits on_mount and the banner slot (collaborate.ex:27, :238-242)

url_params:
  - name: v / release / as_run
    set_by: version pickers and run links (workflow-editor-versions-and-promote, flow-open-run-in-editor)
    effect: joins a read-only room `workflow:collaborate:<id>:v<n>`, `:release<n>` or `:run:<run_id>` instead of the live one (pinnedView.ts:56; SessionProvider.tsx:84-87; workflow_channel.ex:2152-2160)

config_variants:
  default: {}                                                                  # read under this variant unless tagged
  experimental-features: { user.preferences.experimental_features: true }      # unload warning (useUnloadWarning.ts:16-18); lifecycle content lock (workflow_channel.ex:1507-1510)

inventory:
  routes:
    - live /projects/:project_id/w/:id   WorkflowLive.Collaborate :edit      # router.ex:303; mount plumbing only, panels own the rest
    - live /projects/:project_id/w/new   WorkflowLive.Collaborate :new       # router.ex:302; creation itself owned by workflow-editor-new
  events:
    - WorkflowChannel#join                          # workflow_channel.ex:43-116
    - WorkflowChannel#yjs                           # workflow_channel.ex:218-231
    - WorkflowChannel#yjs_sync                      # workflow_channel.ex:202-216
    - WorkflowChannel#get_context                   # workflow_channel.ex:183-185, :1309-1384
    - WorkflowChannel#get_limits                    # workflow_channel.ex:188-199 (6.1)
    - WorkflowChannel#save_workflow                 # workflow_channel.ex:300-313, :852-883
    - WorkflowChannel#<unknown event>               # workflow_channel.ex:834-837
    - WorkflowChannel handle_info ProjectDeletionScheduled, WorkflowDeleted, ProjectUserRemoved, SupportAccessUpdated, ProjectUserAdded, ProjectUserRoleChanged   # workflow_channel.ex:1081-1150
    - WorkflowChannel handle_info credentials_updated, adaptors_updated, webhook_auth_methods_updated forwarders   # workflow_channel.ex:950-969; payloads owned by workflow-editor-inspectors
    - WorkflowChannel handle_out workflow_saved     # workflow_channel.ex:1170-1198
  js_hooks:
    - ReactComponent CollaborativeEditor (collaborate.ex:252-287); providers at CollaborativeEditor.tsx:442-514
    - KeyboardProvider (keyboard/KeyboardProvider.tsx)
    - beforeunload listener (useUnloadWarning.ts:20-30)
  policies:
    - Lightning.Policies.Workflows (:access_read at join; workflow_channel.ex:2197, :2245, :2256, :2290)
    - Lightning.Policies.ProjectUsers (:create_workflow on a "new" join, workflow_channel.ex:2225; :edit_workflow, :run_workflow, :write_webhook_auth_method resolved at join and on membership events, :1516-1541; :edit_workflow re-read per save, :1950-1977)
    - Lightning.Policies.Sandboxes (:provision_sandbox, :delete_sandbox resolved into the context only; buttons owned by workflow-editor-canvas)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features
    - Lightning.Adaptors.Config.first_load_timeout (save waits on it; session.ex:244-250)
  not_reachable_here:
    - Save and sync (Ctrl/Cmd+Shift+S opens the modal here; the sync itself is workflow-editor-versions-and-promote)
    - Run and retry shortcuts Ctrl/Cmd+Enter, Ctrl/Cmd+Shift+Enter (Header.tsx:587-625); owned by shared-run-retry-controls
    - Ctrl/Cmd+E, Ctrl/Cmd+H, Ctrl/Cmd+Z/Y (WorkflowEditor.tsx:318-326; CollaborativeWorkflowDiagram.tsx:84-93; WorkflowDiagram.tsx:887-910); owned by workflow-editor-canvas and workflow-editor-ide
    - Cursors.tsx (Monaco remote selections); owned by workflow-editor-ide
    - go_live, switch_to_draft and the content lock UI; owned by workflow-editor-canvas

related:
  - workflow-editor-canvas
  - workflow-editor-new
  - workflow-editor-inspectors
  - workflow-editor-ide
  - workflow-editor-manual-run
  - workflow-editor-run-viewer
  - workflow-editor-ai-assistant
  - workflow-editor-versions-and-promote
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/collaboration.ex
  - lib/lightning/collaboration/session.ex
  - lib/lightning/collaboration/persistence.ex
  - lib/lightning/collaboration/persistence_writer.ex
  - lib/lightning/collaboration/workflow_resolver.ex
  - assets/js/collaborative-editor/contexts/SessionProvider.tsx
  - assets/js/collaborative-editor/contexts/StoreProvider.tsx
  - assets/js/collaborative-editor/stores/createSessionStore.ts
  - assets/js/collaborative-editor/stores/createSessionContextStore.ts
  - assets/js/collaborative-editor/stores/createAwarenessStore.ts
  - assets/js/collaborative-editor/hooks/useWorkflow.tsx
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/channels/workflow_channel_broadcast_test.exs
flows:
  - flow-delete-open-workflow             # editor channel end (S16)
  - flow-schedule-project-deletion        # its S04 and S05, editor channel part, now live here as S15
  - flow-toggle-workflow-open-editor      # saves made outside the editor reach the open document through WorkflowReconciler
  - flow-workflow-api-edit-conflict       # Session.init tracks presence that blocks API writes (session.ex:127-133)
  - flow-account-revocation-teardown      # proposed by shared-authenticated-session; drops the user socket this session rides on
---

## 1. Purpose

Every editor panel works on one shared copy of the workflow that all collaborators edit at once and
that only reaches production when someone saves. This session is what keeps that copy in step
between people, keeps it safe across dropped connections and reloads, stops people who may only read
from changing it, and makes sure a save is either committed for everyone or clearly refused. Without
it, collaborators would overwrite each other, lose work to a flaky connection, or keep editing after
their access was taken away.

## 2. What it does

- **Work on one live, shared copy**
  - Members open a workflow and see it once the shared copy has fully loaded
  - Collaborators see each other's edits as they make them, without saving
  - Members see who else has the workflow open, and where their pointer is on the canvas
- **Keep unsaved work safe**
  - Unsaved edits survive a reload and are there for the next person, unless the workflow has been saved since, in which case the saved version wins
  - A dropped connection keeps the workflow on screen, blocks saving and resyncs on reconnect; a tab left open across a deploy stays connected
  - Editors see when they have unsaved changes, and (experimental) are warned before leaving with them
- **Save** (editors)
  - Editors save with the button or Ctrl/Cmd+S from anywhere on the page, and everyone in the room learns the new saved version
  - A save that fails says why, shows field errors to everyone, and offers a retry
- **Control who can change it and who can stay**
  - Viewers, people on older versions and demoted users cannot change the shared copy, even with a modified browser
  - Non-members and members of MFA projects who haven't enrolled cannot join
  - Removal, revoked support access, project deletion and workflow deletion close the session

**Straightforwardness: 2 of 5.** "Unsaved" here means shared and stored but not yet live, which takes some explaining, and the failure cases around simultaneous saves, lost connections and refused access don't behave the way you'd expect.

### Most surprising behaviours

- **(2)** When two people save the same workflow at nearly the same moment, the second may get "An internal error occurred" and their editor drops and reconnects, rather than being told someone else just saved. (6.1)
- **(2)** "Unsaved" doesn't mean private or at risk: your half-finished edits are stored and shown to the next person who opens the workflow, and the leave-page warning only exists with experimental features on. (S03, 6.2)
- **(3)** Someone who can't join the workflow, or whose session fails to start, may just see "Loading workflow" forever with no reason given. (6.1, 6.2)
- **(3)** After a run pushes the project over its run limit, the run button stays enabled and the next run is simply refused, instead of the limit being explained up front. (6.1)
- **(3)** While disconnected, the unsaved-changes marker disappears even though there are unsaved edits, and Ctrl/Cmd+S can try a save the disabled Save button wouldn't allow. (6.2)

## 3. Who can do what

Source: `lib/lightning/policies/workflows.ex:14-22` (`:access_read` is `:access_project`);
`lib/lightning/policies/project_users.ex:39-49`, `:160-172` (editor actions: owner, admin, editor;
support with no row when support access is on), `:134`, `:186-188` (MFA); channel resolution
`workflow_channel.ex:1516-1541`; client gate `StoreProvider.tsx:144-147`, `createSessionContextStore.ts:106-107`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Join the room, see the workflow and collaborators | yes | yes | yes | yes | no | yes, when support access is on |
| Change the shared copy | no | yes | yes | yes | no | yes, when support access is on |
| Save | no | yes | yes | yes | no | yes, when support access is on |
| Join a "new" room | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- A read-only room (`v`, `release`, `as_run`) accepts no document changes and no save from anyone (`workflow_channel.ex:1776-1785`; `session.ex:498-505`).
- With experimental features, a live workflow outside a sandbox is locked for that user (`workflow_channel.ex:1507-1510`); the lock's UI is workflow-editor-canvas.
- Save re-reads the user's role from the database; document changes use the permissions resolved at join and refreshed on membership events (`workflow_channel.ex:1119-1135`, `:1966-1977`).
- A project with MFA required refuses the join to unenrolled members (`workflow_channel_test.exs:1771-1840`).
- The project must not be scheduled for deletion (`workflow_channel_test.exs:1592-1643`, `:3595-3636`).

## 4. What it touches

**Reads**: `users`, `user_tokens`, `projects`, `project_users`, `workflows`, `jobs`, `triggers`, `workflow_edges`, `workflow_snapshots`, `workflow_releases`, `runs` (as-run room only), `collaboration_document_states`, `project_repo_connections`, `webhook_auth_methods`, `workflow_templates`

**Writes**
- `collaboration_document_states`: every document update, saved or not (`persistence.ex:63-81`; `persistence_writer.ex:29-37`), flushed when the last person leaves (`persistence.ex:84-92`)
- On save, through `Workflows.save_workflow/3` with `skip_reconcile: true`: `workflows`, `jobs`, `triggers`, `workflow_edges`, `workflow_snapshots`, `audit_events` (`session.ex:507-534`); `ai_chat_sessions` meta for newly saved jobs and workflows (`session.ex:524-529`; `ai_assistant.ex:297`, `:379`)

**Immediate side effects**
- Presence tracked for the workflow while the session lives (`session.ex:127-133`, `:152-156`)
- `workflow_saved` to everyone else in the room with the new `lock_version` and workflow (`workflow_channel.ex:852-878`)
- `WorkflowUpdated` on the project's workflow events after every committed save (`workflows.ex:513-514`)
- Saved trigger states and `lock_version` written back into the shared document; validation errors written into it on failure (`session.ex:621-664`, `:715-770`)

**Deferred side effects**
- Triggers start or stop starting work orders once a save commits

**External, non-transactional effects**
- none

**Depends on config**
- `experimental_features` user preference: unload warning, content lock
- Adaptor catalogue first-load timeout bounds how long a save waits

**Product limits**
- none (the limits delivered in the session context are consumed by shared-run-retry-controls, workflow-editor-canvas and workflow-editor-ai-assistant)

## 5. Scenarios

Verified against `default` unless tagged. All read from code and tests; nothing was run.

```gherkin
Feature: Collaborative editor session
  In order to work on a workflow with my team without losing or clobbering anyone's changes
  As a member of a project
  I want one shared, live copy of the workflow that only people allowed to change it can change

  @S01 @pending
  Scenario: The editor waits for the shared copy before showing the workflow
    # Value: nobody edits or saves against a half-loaded workflow (steps piled in one spot, or a stale saved version).
    Given I am a viewer on project "Malawi HIV" with workflow "Intake"
    When I open "Intake"
    Then I see "Loading workflow" until the document has synced and the session context has loaded
    And then I see "Intake"
    # collaborate.ex:252-287; CollaborativeEditor.tsx:442-514; StoreProvider.tsx:229-266
    # LoadingBoundary.tsx:23-71; createSessionStore.ts:396-470; LoadingBoundary.test.tsx:65-160, :639-660

  @S02 @pending
  Scenario: Collaborators see each other's edits without saving
    # Value: two people working on the same workflow never build on different copies.
    Given editors "Amara" and "Ben" both have "Intake" open
    When "Amara" renames step "Fetch" to "Fetch patients"
    Then "Ben" eventually sees "Fetch patients" without reloading
    # workflow_channel.ex:202-231, :840-844; session.ex:439-450
    # workflow_channel_test.exs:1941-1954 (an editor's frame mutates the shared doc)

  @S03 @pending
  Scenario: Unsaved edits survive a reload
    # Value: a closed tab, crashed browser or redeploy doesn't throw away work in progress.
    Given I am an editor with "Intake" open
    When I add a step and do not save
    And I reload the page
    Then the new step is still there, and Save shows unsaved changes
    # persistence.ex:18-58, :63-92; persistence_writer.ex:29-37
    # e2e collaborative-editor-node-addition.spec.ts:94-125

  @S04 @pending
  Scenario: A shared draft older than the last save is replaced by the saved workflow
    # Value: nobody resumes a draft built on a version that has since been superseded.
    Given "Intake" has a stored shared draft from lock version 3
    And "Intake" was since saved to lock version 5
    When I open "Intake"
    Then I see the workflow as saved at lock version 5
    # persistence.ex:114-149; persistence_test.exs:281-320

  @S05 @pending
  Scenario: A dropped connection keeps the workflow on screen and blocks saving
    # Value: a flaky connection costs nothing: edits are kept and sent when it returns, and nothing half-synced is committed.
    Given I am an editor with "Intake" open
    When my connection drops
    Then I still see "Intake"
    And "Save" is disabled with "You are disconnected. Reconnecting..."
    And "Ctrl+S" does nothing
    When I make an edit and the connection returns
    Then my edit reaches the other collaborators
    # createSessionStore.ts:205-238 (document reused across reconnects), :447-461; LoadingBoundary.tsx:40-53
    # useWorkflow.tsx:850-871, :886-910; Header.tsx:627-634
    # LoadingBoundary.test.tsx:455-637; Header.keyboard.test.tsx:355-402

  @S06 @pending
  Scenario: Editor saves the workflow
    # Value: changes only reach production when an editor deliberately commits them, and they know when that happened.
    Given I am an editor with "Intake" open and unsaved changes
    When I click "Save"
    Then I see "Workflow saved" with "Last saved at <time>"
    And the unsaved changes marker is gone
    # workflow_channel.ex:300-313, :852-878; session.ex:352-369, :432-436, :507-534
    # useWorkflow.tsx:421-480, :572-584; workflow_channel_test.exs:3330-3357
    # useWorkflow.saveWorkflow.test.tsx:106-136

  @S07 @pending
  Scenario: Everyone in the room learns about a save
    # Value: collaborators don't think they still have to save a change someone else has already committed.
    Given editors "Amara" and "Ben" have "Intake" open with the same unsaved change
    When "Amara" saves
    Then "Ben" eventually sees no unsaved changes marker
    And "Ben"'s session knows the new saved version
    # workflow_channel.ex:855-858, :1170-1177; createSessionContextStore.ts:556-576; useUnsavedChanges.ts:9-56
    # workflow_channel_broadcast_test.exs:70-110, :154-192, :296-325

  @S08 @pending
  Scenario: An invalid workflow is refused and its errors are shown to everyone
    # Value: a broken workflow never reaches production, and every collaborator can see what to fix.
    Given editors "Amara" and "Ben" have "Intake" open
    And "Amara" has cleared the workflow name
    When "Amara" saves
    Then "Amara" sees "Save failed: invalid workflow"
    And both see the name field flagged as invalid
    And nothing is broadcast as saved
    When "Amara" fixes the name and saves
    Then the error is gone for both
    # session.ex:577-591, :621-664, :715-770; workflow_channel.ex:1696-1702; useWorkflow.tsx:512-520
    # workflow_channel_test.exs:3378-3399, :3781-3838; workflow_channel_broadcast_test.exs:244-264

  @S09 @pending
  Scenario: A failed save says so and can be retried
    # Value: a save that didn't happen is never mistaken for one that did, and the edits are still there to retry.
    Given I am an editor with "Intake" open
    When my save fails for a reason other than validation or permission
    Then I see "Failed to save workflow" with the reason and a "Retry" button
    And repeated failures reuse the same message rather than stacking
    When I click "Retry" and the save succeeds
    Then the failure message is replaced by "Workflow saved"
    # useWorkflow.tsx:490-570, :464-468; workflow_channel.ex:1229-1252, :1616-1622
    # useWorkflow.saveWorkflow.test.tsx:153-168, :234-330; workflow_channel_test.exs:3359-3376

  @S10 @pending
  Scenario Outline: The shared copy can't be changed by someone who may only read it
    # Value: a viewer, or anyone reading an older version, can't alter what collaborators are working on, even with a modified browser.
    Given <who> with "Intake" open
    Then the editor is read-only with "<tooltip>"
    And "Save" is disabled
    And any document change sent from my browser is dropped by the server
    And a save request is refused
    Examples:
      | who                                     | tooltip                                            |
      | I am a viewer                           | You do not have permission to edit this workflow   |
      | I am an editor reading an older version | You are viewing a pinned version of this workflow  |
    # workflow_channel.ex:1771-1801, :1587-1598, :1950-1956; session.ex:498-505
    # useWorkflow.tsx:886-930, :1036-1121; createWorkflowStore.ts:268-299; StoreProvider.tsx:144-147
    # workflow_channel_test.exs:1860-1940, :3567-3593; useWorkflowReadOnly.test.tsx; createWorkflowStore.permissions.test.ts

  @S11 @pending
  Scenario: Demoting an editor stops their changes straight away
    # Value: taking edit rights away takes effect before the demoted person can make one more change.
    Given I am an editor with "Intake" open
    When an owner changes my role to viewer in another session
    Then my further document changes are dropped by the server
    And a save I send is refused with "You don't have permission to edit this workflow"
    And my page reloads with viewer permissions (shared-project-scope S08)
    # workflow_channel.ex:1119-1135, :1966-1977
    # workflow_channel_test.exs:1972-2002, :3668-3709

  @S12 @pending
  Scenario: Removing a member closes their session on the workflow
    # Value: a removed person's edits stop reaching the people still on the project immediately.
    Given I am an editor with "Intake" open
    When an admin removes me from the project
    Then my editor session closes
    And my page leaves the project (shared-project-scope S07)
    And other collaborators' sessions stay open
    # workflow_channel.ex:1093-1100, :1140-1150; workflow_channel_test.exs:2004-2056

  @S13 @pending
  Scenario: Revoking support access closes a support user's session but not a member's
    # Value: a customer who withdraws support access knows support can no longer change their workflow.
    Given a support user with no role and an editor both have "Intake" open
    When an owner disables support access on the project
    Then the support user's editor session closes
    And the editor's session stays open
    # workflow_channel.ex:1102-1112; workflow_channel_test.exs:2111-2178; LiveView side: shared-project-scope S09

  @S14 @pending
  Scenario: Non-members and unenrolled members can't join the room
    # Value: the shared copy, including unsaved job code, can't be read by going around the page.
    Given workflow "Intake" in project "Malawi HIV"
    When <who> joins the collaboration room for "Intake"
    Then the join is refused with "unauthorized"
    And asking for an existing and a non-existent older version gives the same refusal
    Examples:
      | who                                                         |
      | a registered user not on "Malawi HIV"                       |
      | an editor who has not enrolled in MFA, on an MFA project    |
    # workflow_channel.ex:2196-2212, :2244-2273; workflow_channel_test.exs:1490-1503, :1645-1673, :1771-1815

  @S15 @pending
  Scenario: Scheduling a project for deletion closes its editor sessions only
    # Value: nobody keeps changing a project that is being wound down, and people in other projects are not interrupted.
    Given I have "Intake" open in "project-1" and another member has a workflow open in "project-2"
    When "project-1" is scheduled for deletion
    Then my editor session closes
    And the session in "project-2" stays open
    # workflow_channel.ex:1073-1083; workflow_channel_test.exs:2193-2255
    # absorbs the editor-channel part of flow-schedule-project-deletion S04 and S05; LiveView side: shared-project-scope S10

  @S16 @pending
  Scenario: Deleting the open workflow closes only that workflow's sessions
    # Value: nobody keeps editing a workflow that no longer exists.
    Given I have "Intake" open
    When another member deletes "Intake"
    Then the flow "flow-delete-open-workflow" ends here: my editor session for "Intake" closes
    And sessions on other workflows in the project stay open
    # workflow_channel.ex:1085-1091; workflow_channel_test.exs:2258-2296

  @S17 @pending
  Scenario: Members see who else has the workflow open
    # Value: people know someone else is working before they change the same thing.
    Given "Amara Banda" and I both have "Intake" open
    Then I see an avatar "AB" in the header with tooltip "Amara Banda (amara@example.org)"
    And it has a green border while she has been active in the last 12 seconds
    When she opens "Intake" in a second tab
    Then I still see one avatar, with " - 2 tabs" in the tooltip
    When she closes every tab
    Then her avatar stays for up to a minute and then disappears
    # ActiveCollaborators.tsx:17-62; useAwareness.ts:318-370; createAwarenessStore.ts:136, :300-340, :596-680; StoreProvider.tsx:194-226
    # ActiveCollaborators.test.tsx:59-160, :163-300, :424-510

  @S18 @pending
  Scenario: Members see where others are pointing on the canvas
    # Value: collaborators can talk about "this step" and avoid working on the same spot.
    Given "Amara Banda" and I both have "Intake" open
    When she moves her pointer over the canvas
    Then I see a cursor labelled "Amara Banda" in her colour following it
    When her pointer leaves the canvas
    Then her cursor disappears
    # PointerTrackerViewer.tsx:10-63; RemoteCursor.tsx; PointerTrackerViewer.test.tsx; RemoteCursor.test.tsx

  @S19 @pending
  Scenario: Save shows when I have unsaved changes
    # Value: editors know there is work that has not reached production yet.
    Given I am an editor with "Intake" open and nothing changed
    Then "Save" shows no unsaved changes marker
    When I change the workflow's name, a step, a path, a trigger or a step's position
    Then "Save" shows the unsaved changes marker
    # useUnsavedChanges.ts:9-141; Header.tsx:371, :893-899; Header.test.tsx:1013-1195

  @S20 @pending @variant:experimental-features
  Scenario: Leaving with unsaved changes asks for confirmation
    # Value: nobody closes the tab believing changes are live when they were never saved.
    Given I am an editor with experimental features and unsaved changes in "Intake"
    When I close the tab
    Then the browser asks me to confirm leaving
    When I instead leave by choosing a sandbox from "Edit in sandbox"
    Then I am not asked
    # useUnloadWarning.ts:11-32; unloadGuard.ts:1-19; EditInSandboxPicker.tsx:372; CollaborativeEditor.tsx:134
    # useUnloadWarning.test.tsx:52-117

  @S21 @pending
  Scenario: Editor saves with the keyboard from anywhere on the page
    # Value: people mid-edit, including inside a form field or code editor, can commit without reaching for the mouse.
    Given I am an editor with "Intake" open and my cursor in a form field
    When I press Ctrl+S, or Cmd+S on a Mac
    Then the workflow is saved, and the browser's own save dialog does not open
    When I am a viewer and press Ctrl+S
    Then nothing is saved
    # Header.tsx:627-634; keyboard/KeyboardProvider.tsx:79-120; Header.keyboard.test.tsx:262-330, :432-590

  @S22 @pending
  Scenario: A tab left open across a deploy keeps its connection
    # Value: a long-lived editing session isn't dropped because the server was updated underneath it.
    Given I have "Intake" open from before a deploy that removed an event my tab still sends
    When my tab sends that event
    Then it gets an error reply and my session stays connected
    # workflow_channel.ex:831-837, :1155-1168; workflow_channel_test.exs:4903-4935
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Two saves of the same workflow that overlap (two editors, or an editor and a lifecycle change) raise `Ecto.StaleEntryError` inside the second user's `Session`, which is deliberately not rescued. The session dies, the deferred reply becomes `internal_error`, and that user's next document frame calls a dead process, crashing their channel. Read from code; the only test accepts any outcome. Moved from workflow-editor-canvas 6.1 | `workflows.ex:216-219`; `workflow.ex:98`; `session.ex:432-436`, `:507-523`; `workflow_channel.ex:218-231`, `:1229-1252`; `session.ex:198-200`; `workflow_channel_test.exs:3401-3434` | "Failed to save workflow: An internal error occurred", then the editor reconnects and rejoins | fix |
| `getLimits` pushes `get_limits` and listens for a `get_limits` event, but the server answers with a reply, never an event, and `await push(...)` reads nothing from the Push. Limits only change when the session context is fetched again (join, reconnect, membership or lifecycle change) | `createSessionContextStore.ts:605-661`, `:721-737`; `workflow_channel.ex:188-199`, `:1273-1288`; callers `Header.tsx:402`, `:462`, `useRunRetry.ts:300`, `:403` | after a run tips the project over its run limit, the run button stays enabled and the next run is refused by the server instead of being explained up front | fix |
| The Save button and Ctrl/Cmd+S call `void saveWorkflow()` on a function that rethrows after toasting, so every failed save is also an unhandled promise rejection. Moved from workflow-editor-canvas 6.1 | `Header.tsx:630`, `:892`; `useWorkflow.tsx:572-584` | nothing visible; console and Sentry noise | fix |
| Join pattern-matches `{:ok, session_pid} = Collaborate.start(...)`; if the document or session fails to start (for example `:shared_doc_not_found`) the join raises instead of refusing. Read from code | `workflow_channel.ex:66-71`; `collaboration.ex:55-72`; `session.ex:117-120` | "Loading workflow" while the client keeps retrying the join | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Unsaved" means not committed to the workflow, not at risk: the shared draft is persisted anyway (S03), and the unload warning (S20) guards against the misunderstanding rather than data loss | `persistence.ex:63-81`; `useUnloadWarning.ts:11-32` | preserve |
| The unload warning exists only with experimental features | `useUnloadWarning.ts:16-18` | decide |
| The unsaved changes marker is hidden whenever Save is disabled, so a disconnected editor with unsaved edits sees no marker. Moved from workflow-editor-canvas 6.2 | `Header.tsx:371`; `Header.test.tsx:1067-1095` | decide |
| Save is disabled by settings errors but Ctrl/Cmd+S is not, so the shortcut sends a save the button would not and gets "Save failed: invalid workflow" | `Header.tsx:627-634`, `:890` | decide |
| `read_only_view` and `workflow_deleted` save errors fall into the generic "Failed to save workflow" toast, whose "Retry" can never succeed | `useWorkflow.tsx:506-545`; `workflow_channel.ex:1587-1606` | decide |
| The client write guard checks only edit permission and the content lock, not a pinned view; on an older version the server drops the frames instead, so any control that escapes `useWorkflowReadOnly` changes the screen and snaps back on reload (workflow-editor-canvas 6.1 has the one known case) | `StoreProvider.tsx:144-147`; `createSessionContextStore.ts:106-107`; `workflow_channel.ex:1776-1785` | decide |
| A role change is answered twice: the channel refreshes permissions in place, and the LiveView remounts the whole editor (shared-project-scope S08), which rebuilds the session anyway | `workflow_channel.ex:1119-1135`; `hooks.ex:361-368` | preserve |
| "Disconnected" for Save and Run is the document's sync state, not the socket state | `useWorkflow.tsx:850-858` | preserve |
| The header's connection-lost icon follows the LiveView socket, not the collaboration channel. Moved from workflow-editor-canvas 6.2 | `Header.tsx:729-735` | decide |
| The join resolves the workflow by id without checking `deleted_at`; only the LiveView mount refuses a deleted workflow, and the save path refuses it afterwards with "This workflow has been deleted" | `workflow_resolver.ex:109-120`, `:248-262`; `workflows.ex:132-142`; `hooks.ex:138-158`; `workflow_channel_test.exs:3543-3557` | decide |
| A refused join never reaches the UI (the provider registers only an "ok" receiver, per the module comment; `y-phoenix-channel` itself was not inspected) | `collaborate.ex:48-53` | decide |
| Ctrl/Cmd+S fires inside inputs, textareas, selects and content-editable areas and suppresses the browser's own save | `KeyboardProvider.tsx:79-120`; `Header.keyboard.test.tsx:432-590` | preserve |
| The channel subscribes to project, work order and adaptor topics before it knows the join will succeed; a refused join exits the process, so nothing leaks | `workflow_channel.ex:54-55`, `:74-85` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `getLimitsHandler` listening for a `get_limits` event | `createSessionContextStore.ts:605-661` | the server never pushes that event (6.1) |
| `determine_error_type` returning `optimistic_lock_error` | `workflow_channel.ex:1763-1769` | `Workflow.changeset` sets no `stale_error_field`, so a lock conflict raises instead (6.1) |
| `handle_info({:DOWN, ...})` stopping with "remote process crash" | `workflow_channel.ex:971-976` | the channel module monitors nothing |
| `useConnectionStatus` | `ConnectionStatusContext.tsx:72-82` | no consumer |
| `user_presences_test.exs` non-skipped tests | `test/lightning_web/live/workflow_live/user_presences_test.exs:16-99` | they only refute legacy presence elements (`#canvas-online-users`, `#canvas-banner`) that nothing in `lib/` renders; the positive tests are `@tag skip` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Shared draft persisted after 2 s idle, every 100 updates or 30 s at most; checkpoint every 500 updates; flushed within 10 s when the last person leaves | `persistence_writer.ex:29-37`; `persistence.ex:84-92` | no | preserve |
| Save waits up to the adaptor catalogue's first-load timeout plus 10 s; the client gives up at 75 s | `session.ex:244-250`, `:352-369`; `createWorkflowStore.ts:157` | yes, "The adaptor catalogue is still loading. Try again shortly." | preserve |
| Presence: `lastSeen` every 10 s, frozen while the tab is hidden; green within 12 s; departed users kept 60 s | `createAwarenessStore.ts:136`, `:596-680`; `ActiveCollaborators.tsx:7-11`, `:47` | yes | preserve |
| Canvas pointer shared at most every 50 ms | `PointerTrackerViewer.tsx:10` | no | preserve |

### 6.5 Things seen but not understood

- Awareness is only initialised when the user has a first name, last name and email; a user missing one never appears to collaborators. Whether every user-creation path (SSO, API, admin) guarantees both names was not checked. Moved from workflow-editor-canvas 6.5 (`StoreProvider.tsx:205-212`). (decide)
- Each channel subscribes to `workflow:collaborate:<id>` explicitly as well as through its own join, so sockets in the live room may receive each `workflow_saved` twice; the second is harmless because `handle_out` has already updated the lifecycle state. Not verified against Phoenix's dispatcher (no deps checked out) (`workflow_channel.ex:79-82`, `:1170-1198`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should overlapping saves surface as a reload prompt rather than killing the session (6.1)?
- Should limits refresh after a run, or is the server's refusal enough (6.1)?
- Should the unload warning leave the experimental flag (6.2)?
- Should a refused join say why instead of loading forever (6.2)?
- flow-schedule-project-deletion S04 and S05 should keep only the run log and AI assistant channels and reference S15 here. workflow-editor-canvas 6.1 rows 1 and 3, 6.2 "unsaved dot" and "connection-lost icon", 6.3 `optimistic_lock_error` and `useConnectionStatus`, and 6.5 "awareness names" now live here and can be dropped there.

## Proposed flows

none. Referenced: flow-delete-open-workflow (S16), flow-schedule-project-deletion (S15 absorbs its editor-channel half), flow-toggle-workflow-open-editor, flow-workflow-api-edit-conflict, flow-account-revocation-teardown (proposed by shared-authenticated-session).

## Proposed shared

none. Referenced: shared-authenticated-session, shared-project-scope, shared-usage-limits-banner; shared-run-retry-controls and shared-adaptor-credential-config own the run shortcuts and credential forwarder payloads.

## Summary

- Scenarios: 22 (S01 to S22), all `@pending`; S20 tagged `@variant:experimental-features`.
- Section 6: 6.1 has 4, 6.2 has 12, 6.3 has 5, 6.4 has 4, 6.5 has 2.
- Flows: none proposed; references flow-delete-open-workflow, flow-schedule-project-deletion, flow-toggle-workflow-open-editor, flow-workflow-api-edit-conflict, flow-account-revocation-teardown.
- Shared: none proposed; inherits shared-authenticated-session, shared-project-scope, shared-usage-limits-banner.
- Unsure: the save race, the join MatchError and the duplicate `workflow_saved` are read from code only; the "refused join never reaches the UI" claim rests on a code comment because `y-phoenix-channel` was not available to read; the canvas file's `LoadingBoundary.tsx:284-330` citations were wrong (the file is 72 lines) and are corrected here.
