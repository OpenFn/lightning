---
id: workflow-editor-ide
type: view
title: Workflow editor › Full-screen code editor (IDE)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id?panel=editor&job=<job id>
  new_route: /projects/:project_id/w/:id?panel=editor&job=<job id>
  old_route_disposition: unchanged
  reachable_when:
    - everything workflow-editor-canvas lists under reachable_when (project scope, workflow belongs to the project, channel joined and synced)
    - the workflow is not a new, unsaved one (WorkflowEditor.tsx:274)
    - both panel=editor and a job param are present; panel=editor alone renders nothing (WorkflowEditor.tsx:373-380)
    - the job exists in the loaded version, otherwise the IDE opens with a "didn't exist in this version" message (FullScreenIDE.tsx:769-773, :1007-1019)

inherits:
  - shared-authenticated-session    # live_session :default mounts InitAssigns (router.ex:303 sits in it)
  - shared-project-scope            # login, MFA, membership, live revocation (collaborate.ex:25)
  - shared-log-viewer               # hosted through RunViewerPanel in the IDE's right panel (FullScreenIDE.tsx:1285-1293); the log viewer's own behaviour is not repeated here
  - shared-editor-session
  - shared-adaptor-credential-config
  - shared-run-retry-controls
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: panel
    set_by: job inspector "Code" button (JobInspector.tsx:105-107), Ctrl/Cmd+E on the canvas (WorkflowEditor.tsx:318-326), AI assistant "open step" (AIAssistantPanelWrapper.tsx:211-231), step inspect links (flow-open-run-in-editor)
    effect: value editor opens the IDE; closing sets it to null and keeps job (WorkflowEditor.tsx:277-279)
  - name: job
    set_by: the same entry points, and the IDE's job selector (FullScreenIDE.tsx:508-519)
    effect: selects the job whose code, adaptor, docs and metadata the IDE shows (FullScreenIDE.tsx:526-530)
  - name: run
    set_by: run-show and history-work-orders step links (flow-open-run-in-editor), the IDE's history list and run submission (FullScreenIDE.tsx:207-225, :266-273)
    effect: follows that run in the right panel (FullScreenIDE.tsx:554-562); cleared by the run chip's close and by History (FullScreenIDE.tsx:227-245)
  - name: step
    set_by: step inspect links; the IDE itself when the job changes while a run is loaded (FullScreenIDE.tsx:570-578)
    effect: selects that step in the run viewer (FullScreenIDE.tsx:564-568)
  - name: v / release / as_run
    set_by: version pickers and run links (owned by workflow-editor-versions-and-promote and flow-open-run-in-editor)
    effect: the IDE opens read-only on that version (S06)

config_variants:
  default: {}                                                                  # read under this variant unless tagged
  experimental-features: { user.preferences.experimental_features: true }     # accounts.ex:1446-1448; changes the version-mismatch banner (FullScreenIDE.tsx:1220-1232) and adds the live content lock
  sandbox: { project.parent_id: <root project id> }                           # data state, not config; SandboxIndicatorBanner (FullScreenIDE.tsx:824-829); metadata reads the sandbox's own credential environment (workflow_channel.ex:152-160)
  ai-assistant-enabled: { Lightning.Config.apollo(:endpoint): <url>, Lightning.Config.apollo(:ai_assistant_api_key): <key> }   # ai_assistant.ex:80-84; collaborate.ex:84

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit       # router.ex:303; owned by workflow-editor-canvas, this view is a URL state of it
  events:
    - WorkflowChannel#request_metadata                                       # workflow_channel.ex:135-170; S11
    - WorkflowLive.Collaborate#open_credential_modal                         # handoff only, owned by workflow-editor-inspectors; pushed with source "ide" (FullScreenIDE.tsx:599-605; CredentialModalContext.tsx:121-135)
  js_hooks: []                                                               # the ReactComponent hook is owned by workflow-editor-canvas; the IDE adds no LiveView hook
  react_components:
    - components/ide/FullScreenIDE.tsx
    - components/CollaborativeMonaco.tsx
    - components/Cursors.tsx                                                 # Monaco remote selections (CollaborativeMonaco.tsx:447)
    - components/JobSelector.tsx
    - components/AdaptorDisplay.tsx (size sm, IDE header)
    - components/SandboxIndicatorBanner.tsx (position relative, full variant)
    - adaptor-docs/Docs.tsx, adaptor-docs/components/DocsPanel.tsx, adaptor-docs/components/render/Function.tsx, adaptor-docs/hooks/useDocs.tsx
    - metadata-explorer/Explorer.tsx, Empty.tsx, Entity.tsx
    - collaborative-editor/utils/loadDTS.ts, collaborative-editor/utils/magic-completion.ts
    - monaco/keyboard-overrides.ts
    - hooks/useMetadata.ts, stores/createMetadataStore.ts
  policies:
    - Lightning.Policies.ProjectUsers (:edit_workflow, :run_workflow resolved at join into channel assigns; workflow_channel.ex:1516-1549, project_users.ex:160-172)
    - Lightning.Policies.Workflows (:access_read at join; via shared-editor-session)
    - Lightning.Policies.ProjectUsers (:access_project in DataclipController.show_for_run; dataclip_controller.ex:217-223; owned by workflow-editor-manual-run)
  workers: []                                                                # Lightning.TaskWorker :cli_task_worker runs the metadata CLI; not an Oban worker (application.ex:189)
  api_endpoints:
    - GET /projects/:project_id/runs/:run_id/dataclip  DataclipController :show_for_run   # router.ex:207-209; called from FullScreenIDE.tsx:349-366; owned by workflow-editor-manual-run
  emails: []
  config:
    - user.preferences.experimental_features
    - Lightning.Config.apollo(:endpoint), Lightning.Config.apollo(:ai_assistant_api_key)   # AI assistant handoff only
    - :lightning, :adaptor_service, :adaptors_path                                        # adaptor install for the metadata CLI (cli.ex:173-178; metadata_service.ex:125-145)
  not_reachable_here:
    - ManualRunPanel, NewRunButton, RunRetryButton, useRunRetry inside the IDE; owned by workflow-editor-manual-run (FullScreenIDE.tsx:927-970, :1311-1334)
    - RunViewerPanel, RunBadge, run viewer tabs; owned by workflow-editor-run-viewer (FullScreenIDE.tsx:1159-1293)
    - MiniHistory (panel variant), VersionMismatchBanner, the two DiscardChangesDialogs for version switching; owned by workflow-editor-versions-and-promote (FullScreenIDE.tsx:1225-1232, :1295-1310, :1391-1404)
    - ConfigureAdaptorModal, AdaptorSelector, credential modal; owned by workflow-editor-inspectors (FullScreenIDE.tsx:1344-1389); see Proposed shared
    - CollaborativeMonaco showDiff / clearDiff and the "Close diff preview" button; driven only by the AI assistant (useAIWorkflowApplications.ts:527-552), owned by workflow-editor-ai-assistant
    - Explorer error messages ("Metadata can only be loaded once you've added a valid credential.", "isn't returning any metadata"); unreachable from the IDE (6.1, 6.3)

related:
  - assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
  - assets/js/collaborative-editor/components/CollaborativeMonaco.tsx
  - assets/js/collaborative-editor/components/WorkflowEditor.tsx
  - assets/js/collaborative-editor/components/inspector/JobInspector.tsx
  - assets/js/collaborative-editor/components/JobSelector.tsx
  - assets/js/collaborative-editor/components/AdaptorDisplay.tsx
  - assets/js/collaborative-editor/components/Cursors.tsx
  - assets/js/collaborative-editor/components/SandboxIndicatorBanner.tsx
  - assets/js/collaborative-editor/hooks/useMetadata.ts
  - assets/js/collaborative-editor/stores/createMetadataStore.ts
  - assets/js/collaborative-editor/hooks/useWorkflow.tsx
  - assets/js/collaborative-editor/hooks/useRunRetryShortcuts.ts
  - assets/js/collaborative-editor/hooks/useAIMode.ts
  - assets/js/collaborative-editor/contexts/CredentialModalContext.tsx
  - assets/js/collaborative-editor/contexts/MonacoRefContext.tsx
  - assets/js/collaborative-editor/utils/loadDTS.ts
  - assets/js/collaborative-editor/utils/magic-completion.ts
  - assets/js/collaborative-editor/utils/workflowGraph.ts
  - assets/js/adaptor-docs/
  - assets/js/metadata-explorer/
  - assets/js/monaco/keyboard-overrides.ts
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/jobs.ex
  - lib/lightning/metadata_service.ex
  - lib/lightning/cli.ex
  - lib/lightning/credentials.ex
  - lib/lightning/projects/environment.ex
  - lib/lightning/task_worker.ex
  - lib/lightning_web/controllers/dataclip_controller.ex
  - assets/test/collaborative-editor/components/ide/FullScreenIDE.test.tsx
  - assets/test/collaborative-editor/components/ide/FullScreenIDE.keyboard.test.tsx
  - assets/test/collaborative-editor/components/ide/FullScreenIDE.docs-panel.test.tsx
  - assets/test/collaborative-editor/components/ide/FullScreenIDE.integration.test.tsx
  - assets/test/collaborative-editor/components/CollaborativeMonaco.diff.test.tsx
  - assets/test/collaborative-editor/components/JobSelector.test.tsx
  - assets/test/collaborative-editor/components/CollaborativeEditor.keyboard.test.tsx
  - assets/test/e2e/specs/collaborative/job-step-sync.spec.ts
  - assets/test/e2e/specs/collaborative/run-retry-keyboard-shortcuts.spec.ts
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning/metadata_service_test.exs
  - workflow-editor-canvas
  - workflow-editor-inspectors
  - workflow-editor-manual-run
  - workflow-editor-run-viewer
  - workflow-editor-versions-and-promote
  - workflow-editor-ai-assistant
flows:
  - flow-oauth-credential-authorize         # "Connect" in the IDE header leads to the credential modal; S16 asserts the handoff
  - flow-open-run-in-editor                 # step inspect links land here (flow S02); S19 asserts the landing
  - flow-workflow-api-edit-conflict
  - flow-restore-version-open-editor
  - flow-editor-credentials-broadcast
  - flow-adaptor-catalogue-update
---

## 1. Purpose

People who write and fix job code use the IDE to work on one step's JavaScript with the whole screen,
with the adaptor's documentation, their system's metadata and the step's last run beside the code.
Several people can type in the same job at once. Without it, writing a job means a cramped inspector
box with no docs or run context, and fixing a failing step means switching between the run page and
the editor, guessing which input and which version of the code actually ran.

## 2. What it does

- Members open a step's code full screen from the canvas, a run link or the AI assistant, and close it back to the canvas
- Editors type job code; collaborators see each other's text and named cursors live
- Viewers, and anyone on an older version, read the code without being able to change it
- Members switch between the workflow's steps without leaving the IDE
- Members read the adaptor's documentation for the job's adaptor version; editors add an example to the code
- Members browse metadata from the job's credential; editors get metadata and type suggestions while typing
- Members collapse, reopen and re-orient the docs panel
- Editors change the job's adaptor, version and credential from the IDE header, and connect a new credential
- Members open run history, pick a run and read it beside the code
- Editors open the run panel and run or retry from the IDE, including by keyboard
- People in a sandbox see that they are in one
- Members see when the job isn't in the version they opened

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:160-172` (`:edit_workflow`, `:run_workflow` are editor
actions for owner, admin, editor, and for support with no row when support access is on); resolved
once at join into channel assigns (`workflow_channel.ex:1516-1549`) and refreshed by shared-editor-session.
Client gates: code editor read-only when `useCanSave` is false (`FullScreenIDE.tsx:1027`;
`useWorkflow.tsx:886-929`), adaptor and credential controls hidden when `useWorkflowReadOnly` is true
(`FullScreenIDE.tsx:861`; `AdaptorDisplay.tsx:178`, `:259`). Server gate on document writes:
`workflow_channel.ex:1774-1801`. `request_metadata` has no permission check beyond the channel join
(`workflow_channel.ex:135-170`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the IDE: code, job selector, docs, history | yes | yes | yes | yes | no | yes, when support access is on |
| Load metadata (server fetch with the job's credential) | yes | yes | yes | yes | no | yes, when support access is on |
| Type job code, add a docs example | no | yes | yes | yes | no | yes, when support access is on |
| Change adaptor, version or credential from the header | no | yes | yes | yes | no | yes, when support access is on |
| Open the run panel, run or retry (handoff) | no (button disabled) | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- An older version (`v`, `release`, `as_run`) is read-only in the IDE for everyone (`useWorkflow.tsx:914-916`, `:1082-1095`); the server drops document frames there (`workflow_channel.ex:1776-1784`).
- With experimental features, a live workflow outside a sandbox is read-only (content lock) (`useWorkflow.tsx:917-919`, `:1096-1102`).
- The code editor is also read-only while disconnected and while the AI assistant applies code or a workflow (`useWorkflow.tsx:905-907`, `:920-926`); the adaptor controls are not (6.2).
- Metadata resolves the credential body for the project's environment; a sandbox without an environment gets an error, not the parent's credential (`environment.ex:71-77`; `workflow_channel.ex:152-165`; test `workflow_channel_test.exs:2959-3010`).
- Metadata only considers the job as last saved in this workflow; a job in another workflow or project is reported as not found (`jobs.ex:161-164`; `workflow_channel_test.exs:3012-3025`).

## 4. What it touches

**Reads**
- The shared workflow document: job body as Y.Text, adaptor, credential ids, edges for job order (`useWorkflow.tsx:248-261`; `FullScreenIDE.tsx:139-149`, `:499-506`) via shared-editor-session
- `jobs`, `project_credentials`, `credentials`, `credential_bodies`, `projects` for metadata (`jobs.ex:161-164`; `environment.ex:40-79`; `credentials.ex:1237-1258`)
- `runs`, `steps`, `dataclips` for the followed step's input (`dataclip_controller.ex:211-241`; handoff to workflow-editor-manual-run)

**Writes**
- Shared document only: job body (Monaco binding, `CollaborativeMonaco.tsx:153-158`), `adaptor`, `project_credential_id`, `keychain_credential_id` (`FullScreenIDE.tsx:627-680`, `:691-707`). Nothing reaches `jobs` until someone saves (shared-editor-session).
- `credential_bodies` when a metadata fetch finds an expired OAuth token and refreshes it (`credentials.ex:1243-1290`)

**Immediate side effects** (in the same request)
- Metadata: an OpenFn CLI process with the credential body in a temporary `state.json`, removed afterwards (`cli.ex:148-171`); telemetry span `[:lightning, :fetch_metadata]` (`metadata_service.ex:48-56`)
- Audit `oauth_token_refreshed` or `oauth_token_refresh_failed` when the metadata fetch refreshes a token (`credentials.ex:1275-1306`)

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- OAuth provider token refresh during a metadata fetch (`credentials.ex:1260-1265`)
- Adaptor install from npm for the metadata CLI (`metadata_service.ex:125-145`)
- Browser fetches from jsDelivr for adaptor type definitions and docs (`loadDTS.ts:23-123`; `useDocs.tsx:22-32`)

**Depends on config**
- `:lightning, :adaptor_service` adaptors path (`cli.ex:173-178`)
- AI assistant enabled (`ai_assistant.ex:80-84`) for S20

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Full-screen code editor
  In order to write and fix a step's code with docs, metadata and run context at hand
  As someone on the project
  I want a full-screen, collaborative code editor for one job at a time

  @S01 @pending
  Scenario: Opening a step's code from the canvas
    # Value: people get from the diagram to a step's code in one action.
    Given I am an editor on workflow "Intake" and step "Send to DHIS2" is selected
    When I click the "Code" button in the step's inspector
    Then the URL has panel "editor" and job "<Send to DHIS2 id>"
    And the IDE shows "Send to DHIS2" in the job selector and that step's code
    When I return to the canvas and press Ctrl+E with the step selected
    Then the IDE opens on "Send to DHIS2" again
    # JobInspector.tsx:94-112; WorkflowEditor.tsx:274, :318-326, :373-380; FullScreenIDE.tsx:836-844, :1020-1035
    # CollaborativeEditor.keyboard.test.tsx:462-600 (asserts updateSearchParams panel "editor", not for a trigger or nothing selected)
    # FullScreenIDE.test.tsx:674-719 (job name, editor rendered)

  @S02 @pending
  Scenario: Leaving the IDE returns to the same step on the canvas, and Escape in the code does not
    # Value: people can leave the editor without losing their place, and pressing Escape while typing never throws them out.
    Given the IDE is open on "Send to DHIS2" with the cursor in the code
    When I press Escape
    Then the code editor loses focus and the IDE stays open
    When I press Escape again
    Then the IDE closes and the canvas shows "Send to DHIS2" selected in its inspector
    And clicking "Close IDE" from a reopened IDE does the same
    # FullScreenIDE.tsx:521-524, :710-727, :973-981; WorkflowEditor.tsx:277-279, :287-292
    # FullScreenIDE.keyboard.test.tsx:486-545 (blur first, onClose second); FullScreenIDE.test.tsx:695-708

  @S03 @pending
  Scenario: Escape does not close the IDE while a modal is open over it
    # Value: dismissing an adaptor or credential dialog never also discards the person's IDE context.
    Given the IDE is open and the adaptor configuration modal is open
    When I press Escape
    Then the IDE is still open
    # FullScreenIDE.tsx:723-726 (enabled only with no configure, picker or credential modal open)
    # FullScreenIDE.keyboard.test.tsx:547-578 notes the condition but does not open a modal

  @S04 @pending
  Scenario: Two editors type in the same job and see each other
    # Value: collaborators working on one job never overwrite each other's code.
    Given "Amara" and "Joe" are editors with the IDE open on "Send to DHIS2"
    When "Amara" types "fn(state => state);" on line 3
    Then "Joe" eventually sees "fn(state => state);" on line 3 without reloading
    And "Joe" sees a cursor labelled "Amara" in "Amara"'s colour at that position
    # CollaborativeMonaco.tsx:139-167 (MonacoBinding on the job's Y.Text with awareness), :447; Cursors.tsx:53-80; useWorkflow.tsx:248-261
    # no test exercises the binding with two clients

  @S05 @pending
  Scenario: Code typed in the IDE is saved with the workflow
    # Value: job code written in the IDE is what runs after the next save.
    Given I am an editor with the IDE open on "Send to DHIS2"
    When I replace the code with "get('/api/me');"
    And I save the workflow
    Then job "Send to DHIS2" has body "get('/api/me');" after reload
    # handoff: save is owned by shared-editor-session; this file asserts only that the IDE edits the job's body
    # CollaborativeMonaco.tsx:153-158; createWorkflowStore getJobBodyYText via useWorkflow.tsx:255-257

  @S06 @pending
  Scenario Outline: The IDE is read-only for <who>
    # Value: people without edit rights, or looking at the past, can study job code but cannot change it.
    Given <who>
    When I open the IDE on "Send to DHIS2"
    Then I can read the code but typing does not change it
    And the adaptor shows without "Change adaptor" or "Edit" controls
    And clicking "ADD" on a docs example does not change the code
    And "Docs", "Metadata" and "History" are still available
    # FullScreenIDE.tsx:738, :849-862, :1027; CollaborativeMonaco.tsx:177-188; AdaptorDisplay.tsx:178-198, :259
    # server: workflow_channel.ex:1774-1801 drops document frames from these sockets
    # FullScreenIDE.test.tsx:516-528 (History and Run still present on read-only)

    Examples:
      | who                                                                  |
      | I am a viewer on the project                                         |
      | I am an editor viewing version 3 from the version picker             |
      | I am an editor who followed a run link to the version that run used  |

  @S07 @pending
  Scenario: A job that isn't in the opened version is explained, not shown blank
    # Value: people who follow a link into an older version understand why the code is missing and how to proceed.
    Given job "New step" was added after version 3
    When I open the IDE on job "New step" on version 3
    Then I see "The job you're trying to view didn't exist in this version of the workflow."
    And I see "You can change versions or select another job."
    And the job selector still lists the jobs of version 3
    # FullScreenIDE.tsx:769-776, :836-844, :1007-1019

  @S08 @pending
  Scenario: Switching jobs from the job selector, in workflow order
    # Value: people move between steps' code without going back to the canvas, finding them in the order the workflow runs them.
    Given workflow "Intake" runs "Fetch", then "Transform", then "Load"
    And the IDE is open on "Load"
    When I open the job selector
    Then it lists "Fetch", "Transform", "Load" in that order with "Load" marked
    When I pick "Transform"
    Then the URL job becomes "<Transform id>" and the IDE shows "Transform"'s code
    # FullScreenIDE.tsx:499-519, :838-842; workflowGraph.ts:523-565; JobSelector.tsx:24-55
    # JobSelector.test.tsx:55-127 (selected mark, onChange, order as given)

  @S09 @pending
  Scenario: With a run loaded, switching jobs follows the run's step for that job
    # Value: the logs beside the code always belong to the step whose code is on screen.
    Given the IDE is following run "R" which executed "Fetch" and "Transform"
    When I pick "Transform" in the job selector
    Then the URL step becomes "R"'s step for "Transform"
    And the run viewer selects that step
    # FullScreenIDE.tsx:508-519, :570-578, :564-568
    # e2e job-step-sync.spec.ts:50-168 asserts the step param changes (see 6.5 on its selectors)

  @S10 @pending
  Scenario: Adaptor docs for the job's adaptor version, with examples editors can add
    # Value: people write against the API of the adaptor version they will actually run, and copy working examples.
    Given job "Send to DHIS2" uses "@openfn/language-dhis2@latest" and latest is "5.0.1"
    When I open the IDE on it
    Then the docs panel shows "@openfn/language-dhis2 (5.0.1)" with its operations sorted by name
    And external links to docs.openfn.org and the adaptor source
    When I am an editor and click "ADD" on an example with my cursor on line 4
    Then the example is inserted below line 4 and the cursor moves past it
    # FullScreenIDE.tsx:411-428, :1118-1120; Docs.tsx:9-17; DocsPanel.tsx:65-127; Function.tsx:59-92; CollaborativeMonaco.tsx:183-247
    # FullScreenIDE.docs-panel.test.tsx:583-711 (mocked Docs receives the resolved specifier)

  @S11 @pending
  Scenario: Metadata from the job's credential, browsable and suggested while typing
    # Value: people pick real field and org unit ids from their own system instead of guessing them.
    Given job "Send to DHIS2" is saved with a project credential for a DHIS2 instance
    When I open the "Metadata" tab in the IDE
    Then I see "Loading metadata..." and then the datasource's entities with the time they were generated
    When I am an editor and press Ctrl+Space inside a string in the code
    Then suggestions from that metadata appear first
    # useMetadata.ts:39-99; createMetadataStore.ts:258-316; workflow_channel.ex:135-170; metadata_service.ex:47-78
    # Explorer.tsx:19-108; FullScreenIDE.tsx:1121-1126, :1026; CollaborativeMonaco.tsx:273-285; magic-completion.ts
    # workflow_channel_test.exs:2934-3026 (job_not_found, no_credential, sandbox environment, cross-project)

  @S12 @pending
  Scenario: Code suggestions for the job's adaptor
    # Value: people discover adaptor operations and their arguments while typing, for the adaptor the job uses.
    Given job "Send to DHIS2" uses "@openfn/language-dhis2@5.0.1"
    When I open the IDE on it
    Then I see "Loading types" until the adaptor's type definitions load
    And typing "create(" suggests the dhis2 operation's signature
    When I change the job's adaptor to "@openfn/language-http@6.0.0"
    Then suggestions switch to the http adaptor
    # CollaborativeMonaco.tsx:249-271, :442-444; loadDTS.ts:23-123
    # no test

  @S13 @pending
  Scenario: The docs panel can be closed, reopened from the header and turned
    # Value: people give the code the whole width when they need it, with docs one click away.
    Given the IDE is open with the docs panel showing
    When I click "Close docs panel"
    Then the docs panel is hidden and the header "Docs" and "Metadata" buttons are not highlighted
    When I click "Metadata" in the header
    Then the panel reopens on the "Metadata" tab
    When I click "Toggle panel orientation"
    Then the docs panel moves below the code
    # FullScreenIDE.tsx:800-820, :866-894, :1041-1130
    # FullScreenIDE.docs-panel.test.tsx:491-580, :712-981

  @S14 @pending
  Scenario: Run history beside the code
    # Value: people can look at what recent runs of this workflow did without leaving the code they are fixing.
    Given the IDE is open with no run loaded
    When I click "History" or press Ctrl+H
    Then the right panel lists the workflow's recent work orders
    When I pick run "R"
    Then the URL run becomes "R" and the run viewer shows "R"
    When I close "R"'s run chip
    Then the URL has no run and the right panel closes
    # FullScreenIDE.tsx:227-245, :266-273, :487-496, :580-584, :897-922, :1294-1310
    # handoff: the list is owned by workflow-editor-versions-and-promote (MiniHistory), the viewer by workflow-editor-run-viewer
    # FullScreenIDE.test.tsx:596-672, :739-782 (MiniHistory shown, run param cleared)

  @S15 @pending
  Scenario: Running from the IDE opens the run panel first, also by keyboard
    # Value: a keystroke made while typing code never starts a run with an input nobody chose.
    Given I am an editor with the IDE open and no right panel showing
    When I press Ctrl+Enter
    Then the run panel opens and no run is started
    And the canvas header's run button is disabled while the IDE is open
    When I pick an input and press Ctrl+Enter again
    Then a run starts and the IDE follows it in the run viewer
    # FullScreenIDE.tsx:207-225, :464-485, :924-970, :1311-1334; useRunRetryShortcuts.ts:99-113; Header.tsx:597-602, :875
    # handoff: the run panel and submission are owned by workflow-editor-manual-run
    # FullScreenIDE.keyboard.test.tsx:609-704; FullScreenIDE.test.tsx:546-593

  @S16 @pending
  Scenario: Connecting a credential from the IDE assigns it to the job
    # Value: people fix a missing credential without leaving the code they are working on.
    Given I am an editor and job "Send to DHIS2" has no credential
    When I click "Connect" next to the adaptor in the IDE header
    Then the adaptor configuration modal opens
    When I choose to create a new credential
    Then the credential modal opens over the IDE
    And for an OAuth credential the flow "flow-oauth-credential-authorize" starts from that modal
    When I save the new credential
    Then "Send to DHIS2" uses the new credential and the adaptor configuration modal is shown again
    # FullScreenIDE.tsx:599-605, :682-708, :849-862, :1344-1371; AdaptorDisplay.tsx:259-285; CredentialModalContext.tsx:121-203
    # handoff: the modals are owned by workflow-editor-inspectors

  @S17 @pending
  Scenario: Following a run preselects the step's input so it can be retried
    # Value: after fixing a failing step's code, people rerun it on exactly the input that failed.
    Given run "R" failed at "Transform" and I am an editor
    When I open the IDE on "Transform" following "R"
    Then the input "R" gave "Transform" is selected without my choosing it
    And the run button reads "Retry"
    # FullScreenIDE.tsx:316-374, :936-969; dataclip_controller.ex:211-241; useRunRetry.ts:204-213
    # handoff: the retry itself is owned by workflow-editor-manual-run
    # FullScreenIDE.integration.test.tsx:197-390 reimplements this logic rather than rendering it (6.5)

  @S18 @pending
  Scenario: A job that was not part of the loaded run cannot be run against it
    # Value: people don't retry a run on a step that run never reached and misread the result.
    Given the IDE is following finished run "R", which did not execute "Load"
    When I pick "Load" in the job selector
    Then the run chip shows a warning with "Load was not part of this run. Pick another job or deselect the run."
    And "Run" is disabled with "Selected job was not part of this run"
    # FullScreenIDE.tsx:305-309, :936-969, :1238-1253

  @S19 @pending
  Scenario: A step inspect link lands in the IDE with the run loaded
    # Value: from a failing step, people land on that step's code beside its logs.
    When the flow "flow-open-run-in-editor" follows a step's inspect link for run "R" and job "Send to DHIS2"
    Then the IDE is open on "Send to DHIS2"
    And the right panel shows "R" in the run viewer with the log tab
    # FullScreenIDE.tsx:128-131, :205, :554-568, :1285-1293; flow-open-run-in-editor S02

  @S20 @pending @variant:ai-assistant-enabled
  Scenario: The AI assistant works on the job open in the IDE
    # Value: AI help is about the code the person is looking at, not the whole workflow.
    Given the IDE is open on "Send to DHIS2" and the AI assistant panel is open
    Then the assistant's context is job "Send to DHIS2" with its code and adaptor
    And a suggested change can be previewed as a diff over the code and closed with "Close diff preview"
    # useAIMode.ts:42-71; CollaborativeMonaco.tsx:298-403, :462-483; useAIWorkflowApplications.ts:527-552; MonacoRefContext.tsx
    # handoff: owned by workflow-editor-ai-assistant
    # CollaborativeMonaco.diff.test.tsx:167-363

  @S21 @pending @variant:sandbox
  Scenario: The IDE says when it is in a sandbox
    # Value: people never mistake a sandbox's code for the production workflow's.
    Given I am in sandbox "staging-fix" of project "Malawi HIV"
    When I open the IDE
    Then I see "You are currently working in the sandbox staging-fix" above the IDE header
    # FullScreenIDE.tsx:824-829; SandboxIndicatorBanner.tsx:29-67; WorkflowEditor.tsx:374-379

  @S22 @pending
  Scenario: The run panel warns when the run executed a different version
    # Value: people don't read a run's logs against code that is not the code that ran.
    Given the IDE is on version 7 and following run "R", which ran on version 3
    Then the run panel shows "This run took place on version 3."
    # FullScreenIDE.tsx:740-761, :1220-1232
    # handoff: banner and version switch owned by workflow-editor-versions-and-promote
    # FullScreenIDE.test.tsx:838-866 (default variant: alert shown; none when versions match)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The run viewer tab is meant to be remembered, but the save effect runs before the load effect on mount and writes "log" first | `FullScreenIDE.tsx:376-390` | the IDE always reopens on Logs, never on the Input or Output tab last used | fix |
| Metadata errors never reach the explorer: the store sets metadata to null on any server error and the IDE passes only metadata | `createMetadataStore.ts:178-180`; `useMetadata.ts:44-63`; `FullScreenIDE.tsx:1122-1125`; `Explorer.tsx:24-26` | "No metadata found for <adaptor>. This adaptor does not support magic functions yet." for a missing credential, an invalid credential, a CLI failure or a busy server | fix |
| Metadata is fetched for the job as saved in the database, but cached on the client under the unsaved adaptor and credential; an unsaved new job is "job_not_found" | `workflow_channel.ex:137-160`; `jobs.ex:161-164`; `createMetadataStore.ts:269-294`; `useMetadata.ts:66-82` | after changing adaptor or credential without saving, the old adaptor's metadata (or "No metadata found") with no way to refresh | fix |
| A metadata request is skipped while another for the same job is loading, and nothing retries it | `createMetadataStore.ts:272-276`; `useMetadata.ts:66-82` | changing credential quickly after opening the IDE leaves metadata from the previous credential | fix |
| Jobs using a keychain credential get "no_credential": the server only follows `project_credential` | `job.ex:55-58`; `workflow_channel.ex:137-160`; `metadata_service.ex:85-89` | no metadata for keychain credential jobs (shown as "No metadata found") | decide |
| Metadata explorer calls `useState` after early returns; going from "Loading metadata..." to loaded data in the same mounted explorer changes the hook count (suspected crash, not run) | `Explorer.tsx:24-52`; `FullScreenIDE.tsx:1124` | possibly a blank IDE when metadata finishes loading while the Metadata tab is open | fix |
| "ADD" tooltip says "Add this snippet to the end of the code" but the editor inserts at the cursor | `Function.tsx:80-85`; `CollaborativeMonaco.tsx:215-231` | the example lands mid-code, not at the end | fix |
| "ADD" is shown to read-only users and silently does nothing | `Function.tsx:80-86`; `CollaborativeMonaco.tsx:184-188` | a button that has no effect | fix |
| `loadDTS` calls `.replace` on an undefined language-common version when an adaptor's package.json has no such dependency; the promise has no catch and types were already cleared | `loadDTS.ts:35-51`; `CollaborativeMonaco.tsx:250-262` | no suggestions at all for that adaptor, and an unhandled rejection | fix |
| Comment says the job text persists for offline editing, but the editor is read-only while disconnected | `FullScreenIDE.tsx:763-765`, `:1027`; `useWorkflow.tsx:905-907` | cannot type during a reconnect | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| panel=editor without a job param renders nothing and no inspector | `WorkflowEditor.tsx:287-292`, `:373-380` | decide |
| The IDE is blocked on a new, unsaved workflow even with panel=editor in the URL | `WorkflowEditor.tsx:274` | preserve |
| Closing the IDE keeps job in the URL, so the canvas reopens that job's inspector | `WorkflowEditor.tsx:277-279` | preserve |
| Ctrl/Cmd+E is bound with Escape: it closes the IDE, but only blurs when the code has focus; on the canvas it opens the IDE | `FullScreenIDE.tsx:710-727`; `WorkflowEditor.tsx:318-326` | decide |
| Code read-only uses `useCanSave` (includes disconnected and AI applying); adaptor controls use `useWorkflowReadOnly` (does not) | `FullScreenIDE.tsx:137`, `:738`, `:861`, `:1027` | decide |
| The editor gets the raw adaptor string (with "latest") for types; docs and metadata explorer get the resolved version | `FullScreenIDE.tsx:411-428`, `:1025`, `:1119-1123` | decide |
| Job selector order is breadth-first from the last trigger found in the edges; jobs not reachable from it come last in document order | `FullScreenIDE.tsx:499-506`; `workflowGraph.ts:523-565` | decide |
| Docs panel collapsed state and orientation in localStorage (`lightning.ide.docsPanel.collapsed`, `lightning.ide.docsPanel.orientation`); panel sizes via react-resizable-panels `autoSaveId` (`lightning.ide-layout`, `lightning.ide-docs-layout`) | `FullScreenIDE.tsx:162-171`, `:729-735`, `:808-813`, `:989`, `:1000` | preserve |
| Docs tab always starts on "Docs"; header Docs and Metadata buttons switch tab and expand, never close | `FullScreenIDE.tsx:172-174`, `:815-820` | preserve |
| Metadata explorer "Tips" open state in localStorage `lightning.metadata-explorer.settings` | `Explorer.tsx:9`, `:46-57` | preserve |
| Any member who can join, viewers included, makes the server run the metadata CLI with the job's credential | `workflow_channel.ex:135-170` | decide |
| A metadata fetch can refresh an expired OAuth token, writing the credential body and an audit event, on a viewer's page view | `credentials.ex:1237-1306` | decide |
| History button and Ctrl+H do nothing while a run is submitting or processing | `FullScreenIDE.tsx:487-496`, `:906` | preserve |
| Opening History or closing the run clears the run param and resets the chosen input | `FullScreenIDE.tsx:227-245` | preserve |
| Switching jobs resets the chosen input and closes the run panel if it was in create-run | `FullScreenIDE.tsx:532-552` | preserve |
| Ctrl/Cmd+Shift+Enter in the IDE only acts when the loaded run is retryable | `useRunRetryShortcuts.ts:116-125`; `FullScreenIDE.tsx:464-485` | decide |
| Monaco's own Ctrl/Cmd+Enter, Ctrl/Cmd+Shift+Enter and Ctrl/Cmd+K are re-dispatched to the window so app shortcuts fire from inside the code | `keyboard-overrides.ts:31-80`; `CollaborativeMonaco.tsx:125` | preserve |
| IDE shortcuts run at priority 50 over the canvas's 0; the canvas header's run shortcuts and run button are disabled while the IDE is open | `FullScreenIDE.tsx:484`, `:494`, `:722`; `Header.tsx:597-622`, `:875` | preserve |
| Collapsed run panel shows a rotated run badge and vertical "Logs", "Input", "Output" labels that expand it | `FullScreenIDE.tsx:1159-1217` | preserve |
| "Loading IDE" with a pulse while the job is not yet in the store | `FullScreenIDE.tsx:769-798` | preserve |
| Docs fetched with `describePackage` and cached in memory for the page's lifetime, including failures | `useDocs.tsx:9-34` | preserve |
| Docs and examples use uppercase "COPY" and "ADD" labels | `Function.tsx:75-85` | decide |
| Minimap on, word wrap on in the IDE editor | `FullScreenIDE.tsx:1029-1034` | preserve |
| A sandbox with no environment reports "environment_not_configured" for metadata, shown as "No metadata found" | `environment.ex:75-77`; `workflow_channel.ex:153-165` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handleAdaptorChange` (keep version, swap package) | `FullScreenIDE.tsx:607-624` | ConfigureAdaptorModal never calls `onAdaptorChange` (`ConfigureAdaptorModal.tsx:209`) |
| Explorer error messages for `no_credential` and `no_metadata_result` | `Explorer.tsx:30-43` | the IDE never passes an error object (6.1) |
| Explorer `credentialName` row | `Explorer.tsx:77-85` | the IDE does not pass `credentialName` (`FullScreenIDE.tsx:1122-1125`) |
| `jobId` prop of FullScreenIDE | `FullScreenIDE.tsx:105`, `:123-127`; `WorkflowEditor.tsx:375` | ignored; the job comes from the URL |
| `getLanguageFromAdaptor` branches other than javascript | `CollaborativeMonaco.tsx:489-506` | the IDE passes an npm specifier or "common", which always falls to javascript |
| SandboxIndicatorBanner compact variant and the "Switch to root project" link in its doc comment | `SandboxIndicatorBanner.tsx:14-16`, `:54-58` | no caller passes `variant="compact"`; no link is rendered |
| MiniHistory `onCollapseHistory` | `FullScreenIDE.tsx:1299` | no-op in the panel variant |
| `useMetadata().refetch`, `useMetadataCommands`, `useMetadataForJob` | `useMetadata.ts:84-127` | no caller in the IDE (not checked across the editor) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Metadata CLI runs in `:cli_task_worker`, at most `System.schedulers_online()` at once; over that the request fails with "too_many_processes" | `task_worker.ex:25-37`; `metadata_service.ex:47-60`; `application.ex:189` | yes, as "No metadata found" (6.1) | preserve |
| Metadata cached per job by adaptor and credential for the page's lifetime; no refresh control | `createMetadataStore.ts:278-285` | yes | decide |
| Type definitions refetched from jsDelivr on every adaptor change; current suggestions cleared immediately | `CollaborativeMonaco.tsx:249-262`; `loadDTS.ts:23-123` | yes, "Loading types" | preserve |
| Panel minimum sizes: editor 25%, docs 20%, right panel 25%, collapsed run panel 3% | `FullScreenIDE.tsx:993`, `:1004`, `:1056-1059`, `:1148-1153` | yes | preserve |
| Job selector list scrolls past 15rem | `JobSelector.tsx:33-36` | yes | preserve |

### 6.5 Things seen but not understood

- `FullScreenIDE.integration.test.tsx` re-implements the component's logic inline and asserts on its own copies; it refers to a "landing" state and minimum sizes 10 and 30 that the component does not have (`FullScreenIDE.integration.test.tsx:17-55`, `:851-878`). It is not evidence for S09, S14, S15 or S17.
- The e2e specs open the IDE with `[aria-label="Open fullscreen editor"]` and wait for `[data-testid="monaco-editor"]`; neither appears in `assets/js` (the inspector button is `aria-label="Code"`, `JobInspector.tsx:105`). They cannot be passing as written (`job-step-sync.spec.ts:86-96`; `run-retry-keyboard-shortcuts.spec.ts:191-205`).
- The docs collapsed flag in localStorage and the panel sizes saved by `autoSaveId` are stored separately; whether they can disagree (panel space shown with its content hidden) was not checked (`FullScreenIDE.tsx:162-165`, `:1054-1063`, `:1066-1128`).
- ManualRunPanel's `onClose` collapses the right panel, but the panel is only collapsible in run-viewer state; whether that close does anything in create-run was not traced (`FullScreenIDE.tsx:1152`, `:1312-1322`).
- Whether Escape pressed to dismiss Monaco's suggestion widget also reaches the IDE's Escape handler was not checked (`FullScreenIDE.tsx:710-727`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should viewers be able to trigger metadata fetches that use, and may refresh, a project credential (6.2)?
- Should the editor stay writable while disconnected, as the comment intends (6.1)?
- Should metadata follow the unsaved adaptor and credential, or say that it reflects the saved job (6.1)?
- Is the uppercase "COPY" and "ADD" copy intended to carry over (6.2)?

## Proposed flows

none

## Proposed shared

- `shared-editor-session` (proposed by the lead; referenced in `inherits`). Plumbing this panel relies on: the job body as a Y.Text from the shared document (`useWorkflow.tsx:248-261`) and awareness for remote cursors (`FullScreenIDE.tsx:102`, `:136`); the server write gate that drops viewers' and old versions' edits (`workflow_channel.ex:1774-1801`); `useCanSave` and `useWorkflowReadOnly` (`useWorkflow.tsx:886-929`, `:1036-1110`); save through the header button and Ctrl/Cmd+S, which stay available while the IDE is open (`Header.tsx:626-633`); the priority-based `KeyboardProvider` (`CollaborativeEditor.tsx:441`); the channel provider the metadata store borrows (`createMetadataStore.ts:239-253`); permission refresh and teardown. Surfaces: every `workflow-editor-*` view.
- `shared-adaptor-credential-config` (new). ConfigureAdaptorModal, AdaptorSelector and the credential modal callbacks keyed by source ("ide" or "inspector"): opening the configure modal, opening the picker from it and returning, opening the LiveView credential modal, reopening the configure modal when it closes, assigning a newly saved credential to the job. Rendered by both `components/inspector/JobForm.tsx:187-193`, `:360-400` and `FullScreenIDE.tsx:586-708`, `:1344-1389`; the LiveView side is `collaborate.ex:145-209`. Surfaces: workflow-editor-inspectors, workflow-editor-ide. The inventory currently assigns these components to workflow-editor-inspectors; this file asserts only the handoff (S16).

## Lead resolution (batch 5)

- `shared-configure-adaptor-modal` merged into `shared-adaptor-credential-config`.
- `shared-editor-session` created.
