---
id: workflow-editor-canvas
type: view
title: Workflow editor › Canvas and header
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id
  new_route: /projects/:project_id/w/:id
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; collaborate.ex:25)
    - the workflow belongs to the project and is not deleted, otherwise redirect to /projects/:project_id/w with "Workflow not found" (collaborate.ex:26; hooks.ex:138-158)
    - the collaboration channel join succeeds (workflow_channel.ex:43-111), and the shared document has synced, otherwise "Loading workflow" (LoadingBoundary.tsx:284-330; part of shared-editor-session)

inherits:
  - shared-authenticated-session    # live_session :default mounts InitAssigns (router.ex:288, :303)
  - shared-project-scope            # login, MFA, membership, live revocation (collaborate.ex:25); S10, S11, S12 are the receiving ends of project deletion, sandbox archive and workflow deletion
  - shared-usage-limits-banner      # :check_limits on_mount and the banner render (collaborate.ex:27, :238-242)
  - shared-project-header           # picker modal only (S04 to S12): the editor draws its own React header (Header.tsx) with a PickerButton that opens the layout's global picker (CollaborativeEditor.tsx:244-252; live.html.heex:109-113)
  - shared-editor-session
  - shared-run-retry-controls
  - shared-adaptor-credential-config

url_params:
  - name: run
    set_by: run-show, history-work-orders, the editor itself (flow-open-run-in-editor)
    effect: server preloads the run's steps into data-initial-run-data when the run belongs to this project (collaborate.ex:100-116); owned by workflow-editor-run-viewer
  - name: v / release / as_run
    set_by: version pickers, run links (workflow-editor-versions-and-promote, flow-open-run-in-editor)
    effect: joins a read-only room for that version (SessionProvider.tsx:84-87; workflow_channel.ex:2152-2161); the canvas shows it read-only (S11)
  - name: panel, job, trigger, edge, step, runMode
    set_by: canvas selection, inspectors, IDE, run panel
    effect: which side panel is open; the title click clears them all (S21; CollaborativeEditor.tsx:210-222)
  - name: archived
    set_by: shared-project-scope S11 after a sandbox archive
    effect: one-off "Promoted to parent project" or "Sandbox archived" toast (PromotedNotice.tsx; owned by flow-sandbox-merge)

config_variants:
  default: {}                                                                              # read under this variant unless tagged
  experimental-features: { user.preferences.experimental_features: true }                  # accounts.ex:1446-1448; collaborate.ex:86-89; workflow_channel.ex:1507-1510; read under this variant for S14 to S18
  require-email-verification: { lightning.require_email_verification: true }               # workflow_channel.ex:1409-1415
  activation-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(:activate_workflow) returns {:error, _, %Message{}}> }
  stale-build: { the static assets digest changed since the tab loaded }                    # Phoenix.LiveView.static_changed?/1 at collaborate.ex:85
  sandbox: { project.parent_id: <parent project id> }                                      # data state, not config; collaborate.ex:64, :74-76

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit       # router.ex:303
  events:
    # LiveView handle_event clauses in this module are the credential and webhook auth modals, owned by workflow-editor-inspectors:
    - WorkflowLive.Collaborate#open_credential_modal              # collaborate.ex:145-187; owned by workflow-editor-inspectors
    - WorkflowLive.Collaborate#close_credential_modal             # collaborate.ex:189-196; owned by workflow-editor-inspectors
    - WorkflowLive.Collaborate#credential_modal_closed            # collaborate.ex:198-209; owned by workflow-editor-inspectors
    - WorkflowLive.Collaborate#open_webhook_auth_modal            # collaborate.ex:211-223; owned by workflow-editor-inspectors
    - WorkflowLive.Collaborate#close_webhook_auth_modal_complete  # collaborate.ex:225-233; owned by workflow-editor-inspectors
    # Channel events this view owns (canvas and header), or that belong to the proposed shared-editor-session:
    - WorkflowChannel#join                                        # workflow_channel.ex:43-116; shared-editor-session
    - WorkflowChannel#yjs                                         # workflow_channel.ex:218-231; shared-editor-session
    - WorkflowChannel#yjs_sync                                    # workflow_channel.ex:202-216; shared-editor-session
    - WorkflowChannel#get_context                                 # workflow_channel.ex:183-185; shared-editor-session
    - WorkflowChannel#get_limits                                  # workflow_channel.ex:188-199; shared-editor-session
    - WorkflowChannel#save_workflow                               # workflow_channel.ex:299-313; shared-editor-session
    - WorkflowChannel#go_live                                     # workflow_channel.ex:315-318; S14 to S17
    - WorkflowChannel#switch_to_draft                             # workflow_channel.ex:320-323; S16
    - WorkflowChannel#archive_sandbox                             # workflow_channel.ex:501-513; handoff only, owned by flow-sandbox-merge / flow-sandbox-scheduled-deletion
    - WorkflowChannel#request_current_user                        # workflow_channel.ex:172-180; no client caller (6.3)
    - WorkflowChannel#set_suppress_enable_trigger_warning         # workflow_channel.ex:325-340; no UI reaches it (6.3)
    - WorkflowChannel#<unknown event>                             # workflow_channel.ex:834-837; shared-editor-session
    # Channel events owned by other editor panels (listed so the lint does not count them here):
    # request_credentials, check_custom_path, reset_workflow, request_trigger_auth_methods, update_trigger_auth_methods, publish_template -> workflow-editor-inspectors
    # request_metadata -> workflow-editor-ide; request_run_steps, request_history -> workflow-editor-run-viewer and workflow-editor-versions-and-promote
    # request_releases, request_versions, request_restore_check, restore_version, save_and_sync, list_sandboxes, edit_in_sandbox, request_promote_check, promote -> workflow-editor-versions-and-promote
    # validate_workflow_name, list_templates -> workflow-editor-new; start/done_applying_workflow, start/done_applying_job_code -> workflow-editor-ai-assistant
  js_hooks:
    - ReactComponent CollaborativeEditor (collaborate.ex:252-287)
    - ReactComponent-embedded PickerButton (CollaborativeEditor.tsx:244-252; picker modal owned by shared-project-header)
    - phx-track-static modulepreload link (collaborate.ex:245-251)
    - phx-connected / phx-disconnected signal icon (Header.tsx:729-735)
  policies:
    - Lightning.Policies.Workflows (:access_read at join; workflows.ex:14-22, workflow_channel.ex:2197)
    - Lightning.Policies.ProjectUsers (:edit_workflow, :run_workflow, :write_webhook_auth_method via Scope at join and per save/transition; workflow_channel.ex:1516-1549, :1950-1977)
    - Lightning.Policies.Sandboxes (:provision_sandbox, :delete_sandbox for the header buttons; workflow_channel.ex:1525-1528)
  workers: []
  api_endpoints: []
  emails: []                       # "Resend confirmation email" is a link into the proposed flow-resend-account-confirmation
  config:
    - user.preferences.experimental_features
    - :lightning, :require_email_verification
    - :lightning, Lightning.Extensions, :usage_limiter (limit_action :activate_workflow)
    - Lightning.Adaptors.Config.first_load_timeout (save waits on the adaptor catalogue; session.ex:244-250)
  not_reachable_here:
    - SandboxIndicatorBanner.tsx is rendered only inside the full-screen IDE (FullScreenIDE.tsx:77, :824), not on the canvas; owned by workflow-editor-ide
    - Cursors.tsx (Monaco remote selections) is rendered only by CollaborativeMonaco.tsx:447; owned by workflow-editor-ide
    - components/diagram/MiniHistory.tsx and VersionMismatchBanner.tsx; owned by workflow-editor-versions-and-promote
    - LandingScreen, TemplateBrowserModal, YAMLImportModal in CollaborativeEditor.tsx:361-407; owned by workflow-editor-new
    - ConnectionStatusContext.useConnectionStatus (ConnectionStatusContext.tsx:72-82); no consumer (6.3)

related:
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/collaboration/session.ex
  - lib/lightning/collaboration/persistence.ex
  - lib/lightning/collaboration/persistence_writer.ex
  - lib/lightning/collaboration.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflows/presence.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/policies/sandboxes.ex
  - lib/lightning_web/hooks.ex
  - assets/js/collaborative-editor/CollaborativeEditor.tsx
  - assets/js/collaborative-editor/components/Header.tsx
  - assets/js/collaborative-editor/components/WorkflowEditor.tsx
  - assets/js/collaborative-editor/components/diagram/WorkflowDiagram.tsx
  - assets/js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.tsx
  - assets/js/collaborative-editor/hooks/useConnect.ts
  - assets/js/collaborative-editor/hooks/useWorkflow.tsx
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts
  - assets/js/workflow-diagram/useConnect.ts
  - assets/js/workflow-diagram/util/from-workflow.tsx
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/channels/workflow_channel_broadcast_test.exs
  - assets/test/collaborative-editor/components/Header.test.tsx
  - assets/test/collaborative-editor/components/Header.sandbox.test.tsx
  - assets/test/collaborative-editor/components/diagram/WorkflowDiagram.undo-redo.test.tsx
  - assets/test/e2e/specs/collaborative/edge-validation.spec.ts
  - assets/test/e2e/specs/collaborative/collaborative-editor-node-addition.spec.ts
flows:
  - flow-delete-open-workflow               # receiving end: S26
  - flow-toggle-workflow-open-editor        # receiving end: S27
  - flow-sandbox-scheduled-deletion         # archive_sandbox entry: S25
  - flow-sandbox-merge                      # Promote button and archive: S25
  - flow-open-run-in-editor                 # ?run=, ?v=, ?as_run= land on this route (collaborate.ex:94-116)
  - flow-resend-account-confirmation
  - flow-workflow-api-edit-conflict
  - flow-legacy-editor-redirect
---

## 1. Purpose

Editors use the canvas to build and change a workflow: add steps, connect them, arrange them, switch
the workflow on or off and save. Everyone on the project, viewers included, uses it to see how a
workflow is put together before they inspect a step, a run or a version. Without it nobody could
change a workflow in the app, and without its read-only and lifecycle states people could edit a
version that isn't the current one, or change a workflow that is live in production without meaning to.

## 2. What it does

- Members see the workflow as a diagram of its triggers, steps and paths
- Editors add a step from a step's plus button or by dragging a path onto empty canvas
- Editors connect two steps with a path
- Editors cannot draw a path to themselves, to a trigger, back up the workflow or twice between the same steps
- Members select a step or path to open its inspector, and click empty canvas to close it
- Editors undo and redo canvas edits
- Editors switch between automatic and manual layout, drag steps in manual layout and re-run automatic layout
- Members fit the diagram to the screen
- Viewers, readers of an older version and (with experimental features) editors of a live workflow get a read-only canvas
- Editors switch the workflow on or off from the header (without experimental features)
- With experimental features, editors see a Live or Draft badge and go live or switch to draft with confirmation
- With experimental features in a sandbox, editors turn the sandbox's copy on or off
- Members see the project path, environment and workflow name in the header, and the title returns them to the bare canvas
- Members open workflow settings from the header, which turns red when settings are invalid
- Members are told when a newer build of Lightning has been deployed
- Unconfirmed users are told to confirm their account (require-email-verification)
- The editor follows a workflow switched, deleted or archived elsewhere (flows)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-49` (`:edit_workflow`, `:run_workflow` are editor
actions), `:160-172` (editor actions: owner, admin, editor; support with no row when support access is
on), `:134` (MFA unsatisfied denies everything); `lib/lightning/policies/workflows.ex:14-22` (join needs
`:access_project`); `lib/lightning/policies/sandboxes.ex:94-119`; channel resolution at
`workflow_channel.ex:1516-1549`; client gate `StoreProvider.tsx:144-147`, `createSessionContextStore.ts:106-107`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the canvas and header | yes | yes | yes | yes | no | yes, when support access is on |
| Select steps and paths, fit view, open settings | yes | yes | yes | yes | no | yes, when support access is on |
| Add, connect, move steps; undo, redo; change layout mode | no | yes | yes | yes | no | yes, when support access is on |
| Switch the workflow on or off (default variant) | no | yes | yes | yes | no | yes, when support access is on |
| Go live, switch to draft (experimental) | no | yes | yes | yes | no | yes, when support access is on |
| Turn a sandbox on or off (experimental, sandbox) | no | yes | yes | yes | no | yes, when support access is on |
| Edit in sandbox button enabled (experimental, live) | no | yes on the project | yes | yes | no | no |
| Archive sandbox after promote (handoff) | no | no | yes on the sandbox or its root | yes on the sandbox or its root | no | no |

**Preconditions beyond role**
- An older version (`v`, `release`, `as_run`) is read-only for everyone; the server drops document writes and refuses save and reset (`workflow_channel.ex:1771-1801`; `session.ex:377-385`, `:498-505`).
- With experimental features, a live workflow outside a sandbox is read-only for that user; the lock is computed from the user's own flag (`workflow_channel.ex:1507-1510`, `workflows.ex:167-170`; see 6.2).
- Permissions are resolved at join and refreshed when the user's membership changes; a removed member's channel stops (`workflow_channel.ex:1096-1135`).
- A project scheduled for deletion or a deleted workflow ends the channel (`workflow_channel.ex:1081-1091`).
- Edit in sandbox needs `:provision_sandbox` on the current project; archive needs `:delete_sandbox` on the sandbox (`workflow_channel.ex:1525-1528`; `Header.tsx:261-262`, `:840-853`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `users` (preferences), `workflows`, `jobs`, `triggers`, `workflow_edges`, `workflow_snapshots`, `workflow_releases`, `collaboration_document_states`, `project_repo_connections`, `webhook_auth_methods`, `workflow_templates`, `runs` and `steps` (only for `?run=`; collaborate.ex:106-114)

**Writes** (all through the shared session; canvas actions only change the shared document until saved)
- Save, go live, switch to draft: `workflows` (name, concurrency, positions, `lock_version`, `state`), `jobs`, `triggers` (`enabled`), `workflow_edges`; `workflow_snapshots`; `workflow_versions`; `workflow_releases` on go live; `audit_events` `snapshot_created` and, when a trigger's enabled flag changes, `enabled`/`disabled` (`session.ex:507-534`, `workflows.ex:330-395`, `:707-764`)
- `ai_chat_sessions` meta linked to newly saved jobs and workflows (`session.ex:524-529`; `ai_assistant.ex:297-335`)
- `collaboration_document_states`: every document update, saved or not, debounced (`persistence.ex:62-81`; `persistence_writer.ex:29-37`)

**Immediate side effects** (in the same request)
- `workflow_saved` to the other sockets in the room, carrying the new `lock_version` and workflow (`workflow_channel.ex:852-878`, `:1890-1901`)
- `WorkflowUpdated` on `workflow_events:<project_id>` after every committed save (`workflows.ex:513-527`, `workflows/events.ex:9-14`)
- After go live or switch to draft: `session_context_updated` and, for others, `lifecycle_changed` (`workflow_channel.ex:1861-1888`, `:1184-1196`)
- Saved trigger enabled states and the new `lock_version` written back into the shared document; validation errors written into it on failure (`session.ex:621-664`, `:715-770`)

**Deferred side effects** (later, elsewhere)
- Webhook and cron triggers start or stop starting work orders once a save, go live or switch to draft commits

**External, non-transactional effects**
- none on this view (Save and sync is workflow-editor-versions-and-promote)

**Depends on config**
- `experimental_features` user preference: lifecycle badge and buttons, content lock, unload warning
- `require_email_verification`: account banner
- usage limiter `:activate_workflow`: switching on, going live

**Product limits**
- Workflow activation limit from the usage limiter (S13, S17)
- Zoom between 0.2 and 1 (`WorkflowDiagram.tsx:917`, `:932`)

## 5. Scenarios

Verified against `default` unless tagged. Save, presence, cursors, connection state, read-only
computation, unsaved-changes guard and teardown belong to the proposed `shared-editor-session`; these
scenarios cover what the canvas and header do with them.

```gherkin
Feature: Workflow editor canvas and header
  In order to build and change a workflow, and see how it is put together
  As a member of a project
  I want a diagram I can edit when I am allowed to, and that tells me when I am not

  @S01 @pending
  Scenario: A member opens a workflow and sees its diagram
    # Value: everyone on a project can see how a workflow is wired before touching a step, run or version.
    Given project "Malawi HIV" has workflow "Intake" with a webhook trigger and steps "Fetch" and "Load"
    And I am a viewer on "Malawi HIV"
    When I open "/projects/<project id>/w/<workflow id>"
    Then I see "Loading workflow" until the document has synced
    And I see the trigger, "Fetch" and "Load" connected by their paths
    And I see the fit view, layout, undo and redo controls and a minimap
    # collaborate.ex:252-287; CollaborativeEditor.tsx:490-498; LoadingBoundary.tsx:297-330
    # WorkflowDiagram.tsx:914-1013; from-workflow.tsx:46-199; LoadingBoundary.test.tsx:65-160

  @S02 @pending
  Scenario: Editor adds a step from a step's plus button
    # Value: building a workflow is one click and a choice of adaptor, and the new step is already wired in.
    Given I am an editor with "Intake" open
    When I click the plus button on "Fetch"
    Then the adaptor picker opens
    When I choose the HTTP adaptor
    Then a step "Http" appears below "Fetch", connected by an "on success" path
    And "Http" is selected and its inspector is open
    When I add another HTTP step the same way
    Then it is named "Http 1"
    # Job.tsx:18-24; WorkflowDiagram.tsx:833-849, :747-813, :1016-1021; from-workflow.tsx:53-54
    # e2e collaborative-editor-node-addition.spec.ts:260-311; collaborative-editor-credentials.spec.ts:387

  @S03 @pending
  Scenario: Editor adds a step by dragging a path onto empty canvas
    # Value: editors can place a new step where they want it as they draw the path.
    Given I am an editor with "Intake" open
    When I drag from the plus button on "Load" and release over empty canvas
    Then the adaptor picker opens
    When I choose an adaptor
    Then a new step appears connected from "Load"
    When I instead release over an existing step that is not a valid target
    Then nothing is added
    # useConnect.ts:124-160 (collaborative-editor/hooks); WorkflowDiagram.tsx:815-831, :873-882
    # e2e collaborative-editor-node-addition.spec.ts:220-258; job-inspector-configuration.spec.ts:188

  @S04 @pending
  Scenario: Editor connects two steps
    # Value: editors can add a branch between existing steps without rebuilding them.
    Given I am an editor with "Intake" open, where "Fetch" and "Load" are not connected
    When I drag a path from "Fetch" and drop it on "Load"
    Then an "on success" path from "Fetch" to "Load" appears
    # useConnect.ts:69-94 (collaborative-editor/hooks); createWorkflowStore.ts:1050-1070

  @S05 @pending
  Scenario Outline: The canvas refuses paths that would break the workflow
    # Value: a workflow can never be drawn with a loop or a duplicate path that the runtime could not execute.
    Given I am an editor with a workflow open
    When I drag a path from <source> and drop it on <target>
    Then while dragging, <target> is marked as an invalid target with "<reason>"
    And no path is added
    Examples:
      | source                    | target                     | reason                          |
      | a step                    | the same step              |                                 |
      | a step                    | the trigger                | Cannot connect to a trigger     |
      | a step                    | one of its ancestors       | Cannot create circular workflow |
      | a step                    | a step it already leads to | Already connected to this step  |
    # workflow-diagram/useConnect.ts:58-95; collaborative-editor/hooks/useConnect.ts:101-108, :182-188
    # e2e edge-validation.spec.ts:121-148, :150-194, :196-232, :234-307, :309-340

  @S06 @pending
  Scenario: Selecting a step opens its inspector and empty canvas closes it
    # Value: people get from the picture to a step's details in one click, and back.
    Given I have "Intake" open
    When I click "Fetch"
    Then the URL has "job=<Fetch id>" and the flow hands off to workflow-editor-inspectors
    When I click an empty part of the canvas
    Then the inspector closes
    # WorkflowDiagram.tsx:639-645, :833-849, :873-882; collaborative-editor/hooks/useConnect.ts:109-120
    # WorkflowEditor.tsx:281-292, :333-349

  @S07 @pending
  Scenario: Editor undoes and redoes canvas edits
    # Value: a misplaced step or path can be taken back without rebuilding it by hand.
    Given I am an editor with "Intake" open
    When I add a step
    And I click "Undo"
    Then the step is gone
    When I press Ctrl+Y, or Cmd+Shift+Z on a Mac
    Then the step is back
    And "Undo" and "Redo" say "Nothing to undo" and "Nothing to redo" when there is nothing to take back
    # WorkflowDiagram.tsx:128-135, :162-196, :887-910, :973-1001; createWorkflowStore.ts:2145-2168
    # WorkflowDiagram.undo-redo.test.tsx:63-260

  @S08 @pending
  Scenario: Editor arranges steps by hand in manual layout
    # Value: editors can lay a large workflow out the way their team reads it, and it stays that way for everyone.
    Given I am an editor with "Intake" open in automatic layout
    When I click "Switch to manual layout mode"
    And I drag "Load" to a new spot
    And I save
    Then "Load" is in the new spot after a reload, for me and for other members
    When I click "Switch to auto layout mode"
    Then the steps are laid out automatically again
    # WorkflowDiagram.tsx:155, :719-725, :852-871, :924, :950-965; createWorkflowStore positions map
    # useUnsavedChanges.ts:16, :87 (positions count as unsaved changes); e2e collaborative-editor-node-addition.spec.ts:173-218

  @S09 @pending
  Scenario: Editor re-runs automatic layout over manual positions
    # Value: a cluttered hand layout can be tidied in one step.
    Given I am an editor with "Intake" open in manual layout
    When I click "Run auto layout (override manual positions)"
    Then the steps move to the automatic layout and those positions become the manual ones
    # WorkflowDiagram.tsx:335-350, :966-972

  @S10 @pending
  Scenario: Member fits the diagram to the screen
    # Value: people never lose a workflow off the edge of the canvas.
    Given I have "Intake" open and have panned away from it
    When I click "Fit view"
    Then every step is in view
    And the diagram refits when the canvas is resized, for example when a side panel opens
    # WorkflowDiagram.tsx:648-717, :727-735, :945-947

  @S11 @pending
  Scenario Outline: The canvas is read-only when I can't change what is on screen
    # Value: nobody edits a version that isn't current, a workflow they aren't trusted to change, or (with the lifecycle lock) a workflow that is live in production.
    Given <who> with "Intake" open
    Then I see "Read-only" in the header, with "<tooltip>" on hover
    And steps show no plus button and cannot be dragged
    And "Undo", "Redo" and the layout mode switch are disabled
    And the workflow switch, if shown, is disabled
    Examples:
      | who                                                         | tooltip                                                                       |
      | I am a viewer                                               | You do not have permission to edit this workflow                              |
      | I am an editor reading an older version                     | You are viewing a pinned version of this workflow                             |
      | I am an editor viewing the workflow as a past run executed it | You are viewing this workflow as a past run executed it                     |
    # useWorkflow.tsx:1036-1121; ReadOnlyWarning.tsx:22-46; Header.tsx:654-666, :701-709
    # from-workflow.tsx:53-54; WorkflowDiagram.tsx:143-153, :924, :950-1001
    # useWorkflowReadOnly.test.tsx:278-298, :419-489; ReadOnlyWarning.test.tsx:311-368; Header.test.tsx:559-640

  @S12 @pending
  Scenario: Editor switches the workflow off from the header and saves
    # Value: an editor who spots a misbehaving workflow can stop its triggers from where they are looking at it.
    Given experimental features are off for me
    And I am an editor with "Intake" open, whose triggers are enabled
    When I turn the workflow switch off
    Then every trigger in the workflow is disabled in the draft and the save button shows unsaved changes
    When I save
    Then I see "Workflow saved"
    And "Intake" no longer starts work orders from its triggers
    # Header.tsx:239, :697-709; createWorkflowStore.ts:160-162, :1138-1149
    # session.ex:507-534, :621-664; workflows.ex:741-764 (audit enabled/disabled)
    # Header.sandbox.test.tsx:338-347

  @S13 @pending @variant:activation-limited
  Scenario: Switching a workflow on beyond the plan's limit is refused on save
    # Value: plan limits on active workflows hold even when the switch is flipped inside the editor.
    Given the usage limiter refuses workflow activation with "Your plan is at its limit."
    And "Intake" is saved with its triggers disabled
    When I turn the workflow switch on and save
    Then I see "Failed to save workflow" with "Your plan is at its limit."
    And "Intake" still has its triggers disabled
    # session.ex:510-519, :934-950; workflow_channel.ex:1688-1694; useWorkflow.tsx:490-570

  @S14 @pending @variant:experimental-features
  Scenario: Editor takes a draft workflow live after confirming
    # Value: putting a workflow into production is a deliberate act, never a slip of the mouse.
    Given I am an editor with draft workflow "Intake" open
    Then I see a "Draft" badge and a "Go live" button, and no workflow switch
    When I click "Go live"
    Then I see "This puts the workflow into production. Its triggers will be turned on and it will start processing real data."
    When I confirm "Go live"
    Then the badge says "Live", the triggers are enabled, and a release is recorded
    # Header.tsx:255-258, :667-691, :697-709, :738-761, :912-936
    # workflow_channel.ex:315-318, :1861-1888; session.ex:260-269, :596-605; workflows.ex:381-386
    # workflow_channel_test.exs:69-80; Header.sandbox.test.tsx:326-357, :497-516

  @S15 @pending @variant:experimental-features
  Scenario: Going live saves what is on screen
    # Value: what goes into production is exactly the version the editor was looking at, not an older save.
    Given I am an editor with draft workflow "Intake" open
    And I have renamed "Fetch" to "Fetch patients" without saving
    When I go live
    Then the live workflow has a step named "Fetch patients"
    # session.ex:371-374, :507-523 (set_state saves the shared document); workflow_channel.ex:1837-1843
    # no direct test; workflow_channel_test.exs:216-290 covers a transition from an older version acting on the current workflow

  @S16 @pending @variant:experimental-features
  Scenario: A live workflow is locked until it is switched to draft
    # Value: production workflows can't be changed in place by accident; changes go through draft or a sandbox.
    Given I am an editor with live workflow "Intake" open
    Then I see a "Live" badge and no "Read-only" pill, no "Save" button, and "Switch to draft" and "Edit in sandbox" buttons
    And the canvas is read-only with "This workflow is live. Switch to draft or edit in a sandbox to make changes."
    When I click "Switch to draft" and confirm
    Then the badge says "Draft", the triggers are disabled and I can edit again
    # Header.tsx:375-376, :654-666, :762-779, :836-860, :882-900, :938-965; useWorkflow.tsx:78-79, :1097-1103
    # workflow_channel.ex:1507-1510, :1915-1938; workflow_channel_test.exs:493-528; Header.sandbox.test.tsx:467-476, :517-537
    # "Edit in sandbox" itself belongs to workflow-editor-versions-and-promote

  @S17 @pending @variant:experimental-features @variant:activation-limited
  Scenario: Going live beyond the plan's limit says so and leaves the workflow in draft
    # Value: plan limits are enforced at the point of going live, with the reason shown.
    Given the usage limiter refuses workflow activation with "Your plan is at its limit."
    And I am an editor with draft workflow "Intake" open, whose triggers are disabled
    When I go live
    Then I see "Could not go live" with "Your plan is at its limit."
    And "Intake" is still a draft
    # workflow_channel.ex:1845-1859; session.ex:934-950; Header.tsx:315-339; lib/errors.ts describeLifecycleError
    # workflow_channel_test.exs:82-123 (from an older version)

  @S18 @pending @variant:experimental-features @variant:sandbox
  Scenario: Editor turns a sandbox's copy of a workflow on and off
    # Value: people can exercise a sandbox's own webhook and cron triggers without touching the parent's live workflow.
    Given I am an editor with "Intake" open in sandbox "dev"
    Then I see "Turn on" and "Promote", and no "Go live" or lifecycle badge
    When I click "Turn on"
    Then the sandbox's "Intake" triggers are enabled and the button says "Turn off"
    # Header.tsx:259, :780-819, :820-835; Header.sandbox.test.tsx:648-700
    # "Promote" hands off to flow-sandbox-merge

  @S19 @pending @variant:sandbox
  Scenario: The header shows the sandbox path from the highest project I can reach
    # Value: people always know which sandbox they are editing, without being shown projects they have no access to.
    Given "Root" has sandbox "a", which has sandbox "b"
    And I am an owner on "a" and "b" but not on "Root"
    When I open a workflow in "b"
    Then the project picker button says "a/b" and is marked as a sandbox
    # collaborate.ex:64-76, :269-274; CollaborativeEditor.tsx:227-229, :244-252
    # collaborate_test.exs:120-195

  @S20 @pending
  Scenario: The header shows the project's environment
    # Value: people can tell a production project from a staging one before they change it.
    Given project "Malawi HIV" has environment "production"
    When I open one of its workflows
    Then I see a "production" badge after the workflow name, titled "Project environment is production"
    # collaborate.ex:275; CollaborativeEditor.tsx:226, :282-295; no test found

  @S21 @pending
  Scenario: Clicking the workflow name returns to the bare canvas
    # Value: one click gets people out of any panel, selection or run view back to the whole workflow.
    Given I have "Intake" open with a step selected, the run panel open and a run loaded
    When I click "Intake" in the header
    Then no panel is open, nothing is selected and no run is loaded
    And the back button returns me to where I was
    # CollaborativeEditor.tsx:199-222, :256-259; CollaborativeEditor.breadcrumbTitle.test.tsx:144-200

  @S22 @pending
  Scenario: Workflow settings open from the header and flag errors
    # Value: a workflow-level problem that blocks saving is visible without hunting for it.
    Given I have "Intake" open and its name is blank in the draft
    Then the settings button in the header is red
    When I click it
    Then the workflow settings panel opens and the flow hands off to workflow-editor-inspectors
    When I click it again
    Then the panel closes
    # Header.tsx:244, :711-727, :890; useWorkflow.tsx:1123-1131; Header.test.tsx:418-557

  @S23 @pending @variant:stale-build
  Scenario: People are told when a newer build has been deployed
    # Value: nobody keeps working for hours in a client that no longer matches the server.
    Given I opened "Intake" before a deploy changed the editor's assets
    When my page reconnects
    Then I see "A new version of Lightning is available" with "Save any changes, then reload to update." and a "Reload" button
    And the message stays until I reload
    # collaborate.ex:85, :243-251, :281; StaleBuildNotice.tsx:8-33; CollaborativeEditor.tsx:461
    # StaleBuildNotice.test.tsx:15-40

  @S24 @pending @variant:require-email-verification
  Scenario: An unconfirmed user is warned in the editor and can ask for a new link
    # Value: people working in the editor learn their deadline and can act on it without leaving the workflow.
    Given my account was created 2 hours ago and my email is unconfirmed
    When I open "Intake"
    Then I see "Please confirm your account before" followed by the deadline 48 hours after sign-up, above the header
    When I click "Resend confirmation email"
    Then the flow "flow-resend-account-confirmation" has started
    # EmailVerificationBanner.tsx:16-51; utils/dateFormatting.ts; Header.tsx:647
    # workflow_channel.ex:1388-1398, :1409-1415; EmailVerificationBanner.test.tsx:104-200

  @S25 @pending @variant:experimental-features @variant:sandbox
  Scenario: Archiving a sandbox from the editor hands off to the sandbox flows
    # Value: someone who has promoted their change can retire the sandbox from where they are.
    Given I am an owner on sandbox "sb" and promoted "alpha" from it
    When I click "Archive sandbox"
    Then the flow "flow-sandbox-merge" continues at its S10
    And the flow "flow-sandbox-scheduled-deletion" has started for "sb"
    # Header.tsx:547-572; workflow_channel.ex:501-513; createWorkflowStore.ts:1711-1726

  @S26 @pending
  Scenario: The editor follows a workflow deleted elsewhere
    # Value: nobody keeps editing a workflow that someone else has deleted.
    Given I have "Intake" open
    When another member deletes "Intake" from the workflows list
    Then the flow "flow-delete-open-workflow" ends here at its S01 and S02
    # hooks.ex:325-335; workflow_channel.ex:1086-1091

  @S27 @pending
  Scenario: The editor follows a switch made on the workflows list
    # Value: the editor never shows a workflow as on when it was switched off elsewhere.
    Given I have "Intake" open
    When another member switches "Intake" off on the workflows list
    Then the flow "flow-toggle-workflow-open-editor" ends here at its S01
    # workflow_reconciler.ex:39-61; Header.tsx:239, :701-709

  @S28 @pending
  Scenario: A workflow from another project is not opened
    # Value: a guessed or pasted link never shows a workflow outside the project in the URL.
    Given I am an owner on "Malawi HIV" and not on "Kenya TB"
    When I open "/projects/<Malawi HIV id>/w/<a Kenya TB workflow id>"
    Then I am on "/projects/<Malawi HIV id>/w"
    And I see "Workflow not found"
    # hooks.ex:138-158; collaborate.ex:26; collaborate_test.exs:198-219
    # the channel refuses the same join with "workflow not found" (workflow_channel.ex:2196-2207; workflow_channel_test.exs:1567-1590)

  @S29 @pending
  Scenario: Having a workflow open blocks API writes to it
    # Value: a deploy or script can't overwrite a workflow under someone who is editing it.
    Given I have "Intake" open
    When a client updates "Intake" through the workflows API
    Then the flow "flow-workflow-api-edit-conflict" applies
    # session.ex:129-133 (presence tracked per session); presence.ex:124-129; api/workflows_controller.ex:538-544, :580-592
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A save that races another committed write to the same workflow raises `Ecto.StaleEntryError` inside the session process, which is deliberately not rescued; the session dies and the deferred reply becomes `internal_error`. The `optimistic_lock_error` branch is unreachable because `Workflow.changeset` sets no `stale_error_field`. Read from code; the only test accepts either outcome | `workflows.ex:216-219`; `workflow.ex:98`; `session.ex:432-436`, `:507-523`; `workflow_channel.ex:1229-1252`, `:1762-1768`; `workflow_channel_test.exs:3401-3434` | "Failed to save workflow: An internal error occurred"; later document frames hit a dead session and the channel restarts | fix |
| "Run auto layout (override manual positions)" is not disabled on a read-only canvas, unlike the other layout controls. On a pinned version (client write gate open, server drops frames) the steps move locally and snap back on reload | `WorkflowDiagram.tsx:335-350`, `:966-972`; `StoreProvider.tsx:144-147`; `workflow_channel.ex:1776-1785` | steps rearrange on a read-only view with no effect | fix |
| Ctrl+S and the Save button call `void saveWorkflow()` on a function that rethrows after toasting, so every failed save is also an unhandled promise rejection | `Header.tsx:627-634`, `:892`; `useWorkflow.tsx:572-584` | nothing visible; console and Sentry noise | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The lifecycle lock depends on the viewing user's experimental flag: a collaborator without it can edit and save a live workflow that an experimental collaborator sees as locked, in the same room | `workflow_channel.ex:1507-1510`; `workflow_channel_test.exs:437-491` | decide |
| The client sends the whole document as the `save_workflow` payload; the server ignores it and saves its own copy of the shared document | `createWorkflowStore.ts:1548-1569`; `workflow_channel.ex:300` | preserve |
| The "Workflows" breadcrumb is a plain link, so it is a full page load rather than a live navigation | `CollaborativeEditor.tsx:253-255`; `Breadcrumbs.tsx:99-104` | decide |
| Steps and paths cannot be deleted with the keyboard on the canvas; deletion is only in the inspector | `WorkflowDiagram.tsx:929` | preserve |
| Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z are bound on `window` and call `preventDefault`, so inside any form field on the page they undo the shared document instead of the field | `WorkflowDiagram.tsx:887-910` | decide |
| Every new path from the canvas is `on_job_success`, including one whose source is a trigger, which the edge changeset rejects (must be `always` or `js_expression`). Trigger nodes render no plus button, so this is probably unreachable | `WorkflowDiagram.tsx:787-803`; `collaborative-editor/hooks/useConnect.ts:75-91`; `Trigger.tsx:38-40`; `edge.ex:134-143` | decide |
| The "Read-only" pill is suppressed when the Live badge is shown, but kept for pinned, as-run and deleted views | `Header.tsx:654-666`; `Header.sandbox.test.tsx:467-476` | preserve |
| The on/off switch reads "on" if any trigger is enabled and turns every trigger on or off together; with no triggers it shows off and does nothing | `createWorkflowStore.ts:160-162`, `:1138-1149` | preserve |
| The unsaved-changes dot is hidden whenever save is disabled, so a disconnected user with unsaved edits sees no dot | `Header.tsx:371`, `:898`; `Header.test.tsx:1067-1095` | decide |
| The "deleted" read-only reason only shows in the moment between a delete and the LiveView leaving, since mount refuses deleted workflows | `useWorkflow.tsx:1068-1074`; `hooks.ex:145-157`, `:325-335` | preserve |
| The settings button is an unlabelled icon with no tooltip or accessible name | `Header.tsx:711-727` | decide |
| No chevron separates the project picker from "Workflows" in the breadcrumbs; a right margin does | `Breadcrumbs.tsx:28-46` | preserve |
| Project name, colour, sandbox flag and environment in the header come from LiveView data attributes, not from the channel's session context (which carries no colour or environment) | `CollaborativeEditor.tsx:224-229`; `workflow_channel.ex:1400-1407` | preserve |
| Clicking the plus button opens the adaptor picker first and only then animates the new step in; the older inline name input that the e2e specs still drive no longer appears | `WorkflowDiagram.tsx:815-849`; e2e `collaborative-editor-node-addition.spec.ts:105-109` | decide |
| A connection-lost icon in the header follows the LiveView socket, not the collaboration channel | `Header.tsx:729-735` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_in("request_current_user")` | `workflow_channel.ex:172-180` | no client pushes it (grep of `assets/js`) |
| `handle_in("set_suppress_enable_trigger_warning")` and the `suppress_enable_trigger_warning` context field | `workflow_channel.ex:325-340`, `:1374-1378`; `createSessionContextStore.ts:361`; `useSessionContext.ts:395-409` | the hooks `useSuppressEnableTriggerWarning` and `useMarkEnableTriggerWarningSuppressed` have no caller |
| `determine_error_type` returning `optimistic_lock_error` | `workflow_channel.ex:1763-1769` | no stale_error_field (6.1) |
| `useConnectionStatus` | `ConnectionStatusContext.tsx:72-82` | no consumer |
| `showAiAssistant` drawer refit in the diagram | `WorkflowDiagram.tsx:560-622` | `CollaborativeWorkflowDiagram` always passes `showAiAssistant={false}` (`CollaborativeWorkflowDiagram.tsx:301`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Save waits up to the adaptor catalogue's first-load timeout plus 10 s; the client gives up at 75 s | `session.ex:244-250`; `createWorkflowStore.ts:157` | yes, "The adaptor catalogue is still loading. Try again shortly." | preserve |
| Go live, switch to draft and reset time out at 10 s | `session.ex:260-269`, `:301-303` | yes, as an internal error | preserve |
| Diagram refits 200 ms after the canvas stops resizing; layout animates over 300 ms | `WorkflowDiagram.tsx:653-700`, `:72` | no | preserve |
| Zoom limited to 0.2 to 1 | `WorkflowDiagram.tsx:917`, `:932` | yes | preserve |

### 6.5 Things seen but not understood

- Awareness is only initialised when the user has a first name, last name and email (`StoreProvider.tsx:204-211`). The registration changeset requires both names (`user.ex:103-109`), but whether every path that creates users (SSO, API, admin) does is not checked; a user without a last name would never appear to collaborators. (decide)
- Presence is tracked for every session, including viewers and read-only version rooms (`session.ex:129-133`), so merely viewing an old version blocks API writes (see the proposed flow). Whether that is intended is not established. (decide)
- `session_context` sends `project.is_sandbox` but the header reads the sandbox flag from the LiveView attribute; nothing reconciles them if they differ (`workflow_channel.ex:1400-1407`; `CollaborativeEditor.tsx:229`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the lifecycle lock follow the workflow (or project) rather than each viewer's experimental flag (6.2)?
- Should the stale-entry race on save surface as a reload prompt rather than an internal error (6.1)?
- Should the canvas offer keyboard delete, and should undo stop hijacking form fields (6.2)?
- Is blocking API writes while anyone, including a viewer, has the workflow open the intended contract (6.5, proposed flow)?

## Proposed flows

- `flow-resend-account-confirmation`: "Resend confirmation email" in the editor's React banner (`EmailVerificationBanner.tsx:36-43`) is the same GET to `/users/send-confirmation-email` as the LiveView header's link; already proposed by shared-project-header (its S14 and "Proposed flows"). Surfaces: workflow-editor-canvas, controller:user-confirmation-send-email, email:remind-account-confirmation, back to the editor via the referring path. This file asserts only the handoff (S24).
- `flow-workflow-api-edit-conflict`: while any collaboration session holds a workflow (presence tracked in `Session.init`, `session.ex:129-133`; `presence.ex:124-129`), `PATCH`/`PUT` to that workflow through the workflows API returns 409 with "Cannot save a workflow (<name>) while it is being edited on the App UI" (`api/workflows_controller.ex:311-313`, `:538-544`, `:580-592`); presence is dropped when the session ends (`session.ex:140-158`). Surfaces: workflow-editor-canvas (any editor panel), capability:api-workflows-update, back to the API client. This file asserts only the handoff (S29).

## Proposed shared

- `shared-editor-session`: everything every editor panel relies on and none owns. Surfaces: every `workflow-editor-*` view, `WorkflowChannel`, `Lightning.Collaboration.*`. Describe as:
  - **Mount and handoff to React**: `WorkflowLive.Collaborate` mounts `project_scope`, `ensure_workflow_belongs_to_project`, `check_limits` (`collaborate.ex:25-27`), assigns project display data, AI flag, experimental flag and `static_changed` (`collaborate.ex:63-91`), and renders one `ReactComponent` with `phx-update="ignore"` carrying data attributes (`collaborate.ex:252-287`). `SocketProvider`, `SessionProvider`, `StoreProvider` wrap the app (`CollaborativeEditor.tsx:441-515`).
  - **Join**: topic `workflow:collaborate:<id>` with optional `:v<lock_version>`, `:release<n>` or `:run:<run_id>` suffix (`workflow_channel.ex:2152-2161`; `SessionProvider.tsx:84-87`); params `project_id` and `action` (`new`/`edit`, read lazily so a reconnect after first save rejoins as edit; `SessionProvider.tsx:89-110`). Join requires a user, a project, `:access_read`, and a resolvable workflow; unknown suffix, wrong project, missing snapshot and unauthorized are refused (`workflow_channel.ex:43-116`, `:2164-2300`; tests `workflow_channel_test.exs:47-64`, `:1489-1841`). Join starts or finds the shared document and a `Session` (`collaboration.ex:39-72`), subscribes to project events, work orders, the workflow's PubSub topic and adaptor updates (`workflow_channel.ex:54-87`). The provider registers only an ok receiver, so join refusals never reach the UI (`collaborate.ex:48-53`).
  - **Shared document and persistence**: the document loads from `collaboration_document_states` when its persisted `lock_version` matches the database, otherwise is rebuilt from the database (`persistence.ex:19-58`, `:114-149`); every update is persisted with 2 s debounce, 100-update batches, 30 s max wait, checkpoints every 500 (`persistence_writer.ex:29-37`), so unsaved edits survive a reload and are seen by the next person to open the workflow (e2e `collaborative-editor-node-addition.spec.ts:95-126`).
  - **Write gate**: the server forwards document frames only for a socket with `can_edit_workflow`, not `content_locked`, and not on a version room; read handshakes and awareness always pass (`workflow_channel.ex:1771-1801`; tests `:1843-1955`). The client mirrors it with `withWriteGuard` reading `can_edit_workflow && !contentLocked` lazily (`createWorkflowStore.ts:223-308`; `StoreProvider.tsx:144-147`; `createWorkflowStore.permissions.test.ts:28-170`).
  - **Connection and sync**: `SessionStore` tracks `isConnected`, `isSynced`, `settled`, reuses the Y.Doc across reconnects to keep offline edits (`createSessionStore.ts:205-238`, `:351-460`); `LoadingBoundary` shows "Loading workflow" until settled, synced and context loaded, then keeps showing cached content through disconnects (`LoadingBoundary.tsx:284-330`; `LoadingBoundary.test.tsx:454-660`). Stores connect in order: channel stores on connect, `WorkflowStore` on sync, awareness once user data arrives (`StoreProvider.tsx:193-267`).
  - **Session context and permission refresh**: `get_context` returns user, project, config, permissions, `content_locked`, latest lock version and snapshot id, repo connection, webhook auth methods, template, limits, base workflow (`workflow_channel.ex:1309-1393`). On `ProjectUserAdded` or `ProjectUserRoleChanged` for this user the channel recomputes permissions and pushes `session_context_updated` (`workflow_channel.ex:1119-1135`; test `:1972-2002`); removal, revoked support access, project scheduled for deletion and deletion of this workflow stop the channel with `:normal` (`workflow_channel.ex:1081-1117`; tests `:1956-2323`). The LiveView side of the same events is shared-project-scope S07 to S12.
  - **Save**: `save_workflow` authorises `:edit_workflow` (re-read from the database) and the lifecycle lock, then defers the reply while the session waits for the adaptor catalogue, deserialises the shared document, applies activation limits (new workflows get triggers auto-disabled; existing ones are refused), saves with `skip_reconcile`, writes `lock_version` and trigger states back into the document and clears errors, or writes validation errors into the document for every collaborator (`workflow_channel.ex:299-313`, `:852-883`; `session.ex:352-369`, `:432-436`, `:507-594`, `:621-664`, `:715-770`, `:934-966`; tests `workflow_channel_test.exs:3329-4047`). Errors map to typed replies (`workflow_channel.ex:1555-1716`). Client: success toast "Workflow saved" with "Last saved at <time>", failure toasts "Permission Denied", "Save failed: invalid workflow" or "Failed to save workflow" with Retry, kept open for a brand-new workflow, collapsed into one toast id (`useWorkflow.tsx:419-584`; `useWorkflow.saveWorkflow.test.tsx:96-330`). Others in the room get `workflow_saved` with the new lock version and base workflow, intercepted so lifecycle changes also push `lifecycle_changed` (`workflow_channel.ex:852-878`, `:1170-1198`; `workflow_channel_broadcast_test.exs:52-487`; `workflow_channel_test.exs:298-353`). Save button states and tooltips: disconnected, no permission, deleted, pinned view, live lock, AI applying (`useWorkflow.tsx:886-944`); label "Create" for a new workflow (`Header.tsx:895`). Possible bug to carry: concurrent-save race (this file 6.1).
  - **Read-only computation**: `useWorkflowReadOnly` priority deleted > no permission > as-run > pinned version > live lock > unsaved new workflow, not read-only while permissions load, connection not considered (`useWorkflow.tsx:1027-1121`; `useWorkflowReadOnly.test.tsx:209-960`).
  - **Unsaved changes**: compares the shared document with the last saved base workflow over name, jobs, edges, triggers, positions, concurrency and job logs (`useUnsavedChanges.ts:9-141`); red dot on Save when there are changes and save is allowed (`Header.tsx:371`, `:115-120`; `Header.test.tsx:1012-1195`); with experimental features only, a `beforeunload` warning once synced, suppressible for deliberate navigation (`useUnloadWarning.ts:11-32`; `unloadGuard.ts`; `useUnloadWarning.test.tsx:43-120`).
  - **Presence and cursors**: awareness user is name, email and a colour derived from the user id (`StoreProvider.tsx:193-230`); avatars of remote users in the header, initials from first and last name parts, tooltip "<name> (<email>)" or "- N tabs", green border when seen in the last 12 s (`ActiveCollaborators.tsx:13-61`; `useAwareness.ts:97-140`; `ActiveCollaborators.test.tsx:46-660`); `lastSeen` every 10 s, frozen while the tab is hidden; disconnected users stay 60 s (`createAwarenessStore.ts:136`, `:319-370`, `:600-630`). Canvas pointer shared at most every 50 ms, cleared on leaving the canvas, drawn for others with name and colour (`PointerTrackerViewer.tsx:10-63`; `RemoteCursor.tsx`; tests `PointerTrackerViewer.test.tsx`, `RemoteCursor.test.tsx`). Server-side `Lightning.Workflows.Presence` is tracked per session and used only by the API conflict check (proposed flow above).
  - **Global keyboard shortcuts**: Ctrl/Cmd+S save, Ctrl/Cmd+Shift+S save and sync, Ctrl/Cmd+Enter run or retry, Ctrl/Cmd+Shift+Enter run with custom input (`Header.tsx:587-643`; `Header.keyboard.test.tsx:247-1460`), Ctrl/Cmd+E open the IDE for the selected step (`WorkflowEditor.tsx:318-326`), Ctrl/Cmd+H toggle run history (`CollaborativeWorkflowDiagram.tsx:84-93`), Ctrl/Cmd+Z and Y undo and redo (`WorkflowDiagram.tsx:887-910`), via a priority-based `KeyboardProvider` (`keyboard/KeyboardProvider.tsx`).
  - **Limits refresh**: `getLimits` pushes `get_limits` and listens for a `get_limits` event, but the server answers with a reply, not an event, and the push's reply is never read, so limits only refresh with the session context. Read from code (`createSessionContextStore.ts:605-661`, `:721-737`; `workflow_channel.ex:188-199`, `:1287`). Candidate 6.1 for the shared file.
  - **Resilience**: unknown events reply with an error, unknown broadcasts are logged, async work runs unlinked so a crash becomes an error reply (`workflow_channel.ex:834-837`, `:1151-1168`, `:1200-1290`; tests `:4903-4935`, `:3359-3376`).
  - Inherits shared-authenticated-session and shared-project-scope; treat the proposed `shared-channel-project-scope` as part of this one.

## Lead resolution (batch 5)

- `shared-editor-session` created from this file's Proposed shared entry. `flow-workflow-api-edit-conflict` and `flow-resend-account-confirmation` created.
