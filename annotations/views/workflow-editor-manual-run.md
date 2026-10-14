---
id: workflow-editor-manual-run
type: view
title: Workflow editor › Manual run panel (run or retry from a step or trigger with a chosen input)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id?panel=run with job=<id> or trigger=<id> (optionally runMode=custom-input, dataclip=<id>, run=<id>)
  new_route:                                  # open question 1
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (collaborate.ex:25, see shared-project-scope)
    - the page is an existing workflow; on /new the URL cannot open the panel (WorkflowEditor.tsx:116-119)
    - the panel replaces the inspector slot while open (WorkflowEditor.tsx:333-349, :352-370)
    - inside the full-screen code editor the same component renders in embedded mode, hosted by workflow-editor-ide (FullScreenIDE.tsx:1312-1334)

inherits:
  - shared-authenticated-session      # the JSON endpoints sit behind :require_authenticated_user (router.ex:189-225)
  - shared-project-scope              # LiveView mount gate; the endpoints re-check through Lightning.Projects.Scope via Permissions.can
  - shared-dataclip-body-viewer       # preview of a selected existing input (manual-run/SelectedDataclipView.tsx:168-170)
  - shared-usage-limits-banner        # the page banner; run-limit refusal in this panel is S19 and S21 here
  - shared-editor-session
  - shared-run-retry-controls

url_params:
  - name: panel=run
    set_by: this view (open), Header "Run with custom input" (Header.tsx:493-502), Switch to draft dialog (Header.tsx:946-956), EditInSandboxPicker (EditInSandboxPicker.tsx:355-364)
    effect: opens the panel; with no job or trigger it falls back to the selected node, then to the first trigger with the custom input title (WorkflowEditor.tsx:121-155)
  - name: job / trigger
    set_by: this view (WorkflowEditor.tsx:80-95), workflow-editor-inspectors (JobInspector.tsx:133-137), workflow-editor-canvas (node selection while open, WorkflowEditor.tsx:184-198)
    effect: the step or trigger the run starts from (ManualRunPanel.tsx:169-186)
  - name: runMode=custom-input
    set_by: this view, mirroring the store entry point (WorkflowEditor.tsx:67-72)
    effect: title "Pick a custom input" survives reload (WorkflowEditor.tsx:128-131; ManualRunPanel.tsx:189-190)
  - name: dataclip
    set_by: Header Switch to draft (Header.tsx:956), EditInSandboxPicker (EditInSandboxPicker.tsx:363)
    effect: preselects that input once if it is in the first page of results, then is removed from the URL (ManualRunPanel.tsx:317-337)
  - name: run
    set_by: this view after a run or retry (useRunRetry.ts:311, :406-416), workflow-editor-run-viewer, flow-open-run-in-editor
    effect: the run being followed; enables retry and auto-selects that run's input for the step (ManualRunPanel.tsx:159-165, :265-296; useRunRetry.ts:204-213)

config_variants:
  default: {}                                                              # read under this variant; MAX_DATACLIP_SIZE_MB unset, so 10 MB
  experimental-features: { user.preferences.experimental_features: true }  # named inputs from the whole project in the list; retry from a pinned view; live workflow content lock
  run-limit-reached: { Lightning.Extensions.UsageLimiter: "limit_action(%{type: :new_run}) returns {:error, _, %Message{}}" }

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit    # owned by workflow-editor-canvas; this panel is query params on it
  events: []                                                             # no LiveView events; all traffic is JSON over fetch
  js_hooks:
    - CollaborativeEditor ManualRunPanel (components/ManualRunPanel.tsx)
    - CollaborativeEditor ManualRunPanelErrorBoundary (components/ManualRunPanelErrorBoundary.tsx)
    - CollaborativeEditor SelectedDataclipView (components/manual-run/SelectedDataclipView.tsx)
    - CollaborativeEditor NewRunButton (components/NewRunButton.tsx)
    - CollaborativeEditor RunRetryButton (components/RunRetryButton.tsx)
    - hooks useRunRetry, useRunRetryShortcuts, useSaveBeforeRun, useCanRun (hooks/useRunRetry.ts, useRunRetryShortcuts.ts, useSaveBeforeRun.ts, useWorkflow.tsx:951-1004)
    - manual-run-panel CustomView, EmptyView, ExistingView, FileUploader, DataclipTypePill (assets/js/manual-run-panel/)
    - Header run, retry and run with custom input handlers (Header.tsx:385-502, :587-625, :863-879)
  policies:
    - Lightning.Policies.ProjectUsers :edit_workflow       # workflow_controller.ex:71-77; dataclip_controller.ex:158-164, :267-272
    - Lightning.Policies.ProjectUsers :run_workflow        # workflow_controller.ex:79-85, :228-234
    - Lightning.Policies.ProjectUsers :access_project      # workflow_controller.ex:220-226; dataclip_controller.ex:117-123
    - Lightning.Policies.Dataclips :view_dataclip          # dataclip_controller.ex:273-279
  workers: []                                              # runs go to the run queue for external workers, not Oban (runs.ex:28-30)
  api_endpoints:
    - post /projects/:project_id/workflows/:workflow_id/runs   WorkflowController :create_run   # router.ex:215-217; workflow_controller.ex:26-143
    - post /projects/:project_id/runs/:run_id/retry            WorkflowController :retry_run    # router.ex:223-225; workflow_controller.ex:208-282
    - get /projects/:project_id/jobs/:job_id/dataclips         DataclipController :search       # router.ex:203-205; dataclip_controller.ex:114-198
    - patch /projects/:project_id/dataclips/:dataclip_id       DataclipController :update_name  # router.ex:211-213; dataclip_controller.ex:254-292
  emails: []
  config:
    - max_dataclip_size_bytes (MAX_DATACLIP_SIZE_MB)       # bootstrap.ex:367-369; plug_configs.ex:14; workflow_channel.ex:1413
  not_reachable_here:
    - get /projects/:project_id/runs/:run_id/dataclip DataclipController :show_for_run (dataclip_controller.ex:211-244); called by FullScreenIDE.tsx:351 and EditInSandboxPicker.tsx:649, owned by workflow-editor-ide and workflow-editor-versions-and-promote
    - get /projects/:project_id/runs/:run_id/steps WorkflowController :get_run_steps (workflow_controller.ex:154-198); owned by workflow-editor-run-viewer per the inventory row
    - get /dataclip/body/:id DataclipController :show; owned by shared-dataclip-body-viewer
    - getDataclipBody (api/dataclips.ts:175-183); owned by workflow-editor-versions-and-promote
    - embedded render mode chrome (Custom tab label, close panel button, IDE run button and shortcuts at priority 50); owned by workflow-editor-ide (ManualRunPanel.tsx:626-671; FullScreenIDE.tsx:925-960)

related:
  - workflow-editor-canvas            # hosts the panel; header Run button lives in Header.tsx
  - workflow-editor-inspectors        # "Run From Here" in the step inspector opens this panel (inspectors S19)
  - workflow-editor-ide               # hosts the embedded render mode
  - workflow-editor-run-viewer        # takes over once ?run=<id> is set
  - workflow-editor-versions-and-promote   # Edit in sandbox and Switch to draft deep-link here with dataclip=
  - lib/lightning_web/controllers/workflow_controller.ex
  - lib/lightning_web/controllers/dataclip_controller.ex
  - lib/lightning_web/live/workflow_live/helpers.ex
  - lib/lightning_web/live/workflow_live/new_manual_run.ex
  - lib/lightning/workorders/manual.ex
  - lib/lightning/work_orders.ex
flows:
  - flow-manual-run-live-follow
  - flow-history-live-updates         # referenced; this view publishes work order and run events to it but is not yet in its surfaces (see Proposed flows)
---

## 1. Purpose

Workflow builders use this panel to try a workflow, or one step of it, against data they choose:
nothing, a JSON payload they type or upload, or an input the step really received before. They do
this to test a change before going live and to re-run a failed step after fixing it. Without it
they would have to push data through the real webhook or wait for the next cron tick to find out
whether their code works, and a failed run could only be repeated from the History page.

## 2. What it does

- Editors start a run from a step or a trigger with an empty input
- Editors start a run with a custom JSON object they type or upload
- Editors start a run with an input the step received before, chosen from a searchable list
- Anyone who can open the workflow browses, searches, filters and previews earlier inputs for a step
- Editors name or unname an earlier input
- Cron-triggered steps default to the input the next scheduled run will use
- Editors retry a followed run from a step with the same input, or force a new work order instead
- Editors start a quick run from the first trigger from the header without opening the panel
- The editor saves the workflow before any run or retry
- Run and retry are refused, with a reason, when the person or the workflow cannot run
- The panel opens from, and survives, a URL

## 3. Who can do what

Source: `Lightning.Policies.ProjectUsers` (`project_users.ex:28-49`, `:162-185`) through
`Lightning.Projects.Scope`; `:edit_workflow` and `:run_workflow` are both in `@editor_actions`, so
they grant the same set of people. Client gate: `useCanRun` (`useWorkflow.tsx:951-1004`), which
reads `can_edit_workflow` or `can_run_workflow` from the session context.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the panel (visibility) | yes, via URL only; Run disabled | yes | yes | yes | no | yes, when project support access is on |
| List, search and preview earlier inputs | yes | yes | yes | yes | no | yes, when project support access is on |
| Start a run (create_run) | no | yes | yes | yes | no | yes, when project support access is on |
| Retry a run (retry_run) | no | yes | yes | yes | no | yes, when project support access is on |
| Name or unname an input | no | yes | yes | yes | no | yes, when project support access is on |

**Preconditions beyond role**
- The workflow must belong to the project in the URL (`workflow_controller.ex:87-92`); the run must belong to it for a retry (`workflow_controller.ex:227`, `:284-294`).
- A chosen existing input must belong to the same project (`manual.ex:72-84`); a renamed input must belong to the project in the URL (`dataclip_controller.ex:200-203`, `:265`).
- A retry needs the step's input not to be wiped (`work_orders.ex:327-352`) and the workflow not deleted (`work_orders.ex:334-340`); a run needs the workflow not deleted (`work_orders.ex:129-135`).
- Every endpoint refuses when the project requires MFA and the user has not enrolled, or the project is scheduled for deletion (owned by shared-project-scope; `project_users.ex:136`).
- Run and retry are refused when the usage limiter refuses `:new_run` (`helpers.ex:51-53`; `workflow_controller.ex:235`).
- The client also refuses while disconnected, on a deleted workflow, on a pinned version (retry allowed there with experimental features), and on an unsaved new workflow (`useWorkflow.tsx:983-1001`).

## 4. What it touches

**Reads**
- `workflows`, `jobs`, `triggers`, `edges` for the start node (`workflow_controller.ex:32-35`, `:95-128`)
- `dataclips` without body for the list: inputs to this step's past steps, newest first, not wiped; with experimental features also every named dataclip in the project (`invocation.ex:87-104`; `query.ex:286-335`)
- For a cron-triggered step, the next cron input: the last successful run's final dataclip, or the cursor job's last successful output, not wiped (`invocation.ex:283-334`, `:1342-1378`)
- `runs`, `steps`, `work_orders` for a retry (`work_orders.ex:312-352`, `:810-835`)
- `workflow_snapshots` for the latest snapshot the run executes against (`work_orders.ex:163-174`, `:206-212`)
- `projects`, `project_users`, `users` for the policy (owned by shared-project-scope)

**Writes**
- `dataclips` insert, type `saved_input`, for every run that does not use an existing input, including Empty, whose body is `{}` (`workflow_controller.ex:131-134`; `work_orders.ex:176-190`)
- `work_orders` insert with the job, no trigger, priority immediate, queue `manual`, and `runs` insert (`work_orders.ex:127-149`, `:248-275`)
- Retry: `runs` insert on the existing work order with the upstream steps attached, and `work_orders` update of state and `last_activity` (`work_orders.ex:355-401`, `:870-905`)
- `dataclips.name` update (`invocation.ex:403-416`)
- The workflow itself, through the editor's save before a run (owned by shared-editor-session)

**Immediate side effects**
- PubSub on the project topic: `run_created` and `work_order_created` for a run; `work_order_updated` and `run_created` for a retry (`work_orders.ex:151-157`, `:391-394`; `workorders/events.ex:24-46`)
- Audit `label_created` or `label_deleted` on a dataclip rename (`dataclip_audit.ex:18-29`)
- Toasts "Run started", "Retry started", "Failed to submit run", "Retry failed" (`useRunRetry.ts:291-296`, `:318-322`, `:394-399`, `:431-434`)
- The client asks the session for fresh limits after a run or retry (`useRunRetry.ts:298-301`, `:401-404`)

**Deferred side effects**
- An external worker claims the run from the `manual` queue and executes it; progress reaches the page through the run channel (proposed flow-manual-run-live-follow)

**External, non-transactional effects**
- none at request time; the job code the worker runs may call external systems

**Depends on config**
- `max_dataclip_size_bytes` from `MAX_DATACLIP_SIZE_MB`, default 10 MB, enforced in the client and as the JSON parser length limit (`bootstrap.ex:367-369`; `plug_configs.ex:14`; `CustomView.tsx:12`, `:41-44`)
- the usage limiter extension (`work_orders.ex:84-91`)
- `user.preferences.experimental_features` (`dataclip_controller.ex:147-150`; `useRunRetry.ts:243`, `:406-416`; `useWorkflow.tsx:992`)

**Product limits**
- A custom input is capped at the configured dataclip size, 10 MB by default
- The earlier-inputs list shows at most 10 results per search (`api/dataclips.ts:54`; `ExistingView.tsx:311-316`)
- Usage limits on new runs, where the limiter is configured

## 5. Scenarios

```gherkin
Feature: Manual run panel
  In order to test a workflow or a step against data I choose
  As a workflow builder
  I want to start, retry and configure manual runs from the editor

  @S01 @pending
  Scenario: Run a step with an empty input
    # Value: a builder can check a step's code runs at all without needing any data.
    Given I am an editor on project "Malawi HIV" with workflow "Intake" open
    And step "Fetch" is selected
    When I click "Run From Here" in the step inspector
    Then the run panel opens titled "Run from Fetch" on the "Empty" tab
    And it says "Use an empty JSON object as the input for this run."
    When I click "Run From Here" in the panel
    Then the workflow is saved first
    And a work order is created that starts at "Fetch" with input {}
    And I see "Run started" with "Saved latest changes and created new work order"
    And the panel closes and the URL has "run=<new run id>" and no "panel"
    And workflow-editor-run-viewer takes over
    # JobInspector.tsx:133-137; ManualRunPanel.tsx:189-197, :496-501, :515-517, :683-700; EmptyView.tsx:1-9
    # useRunRetry.ts:248-315; api/dataclips.ts:136-173; workflow_controller.ex:26-66, :130-143; helpers.ex:46-64; work_orders.ex:127-149
    # ManualRunPanel.test.tsx:228-240, :292-305, :928-971; useRunRetry.test.tsx:509-538, :872-901; workflow_controller_test.exs:47-59

  @S02 @pending
  Scenario: Run with a custom JSON input
    # Value: a builder can test a step with a hand-written payload that matches a case they need to handle.
    Given the run panel is open for "Fetch"
    When I open the "New" tab and type {"patient": "123"}
    And I click "Run From Here"
    Then a saved input dataclip with body {"patient": "123"} is created in "Malawi HIV"
    And the new work order starts at "Fetch" with that dataclip
    # CustomView.tsx:56-67, :103-128; ManualRunPanel.tsx:518-537; useRunRetry.ts:284-286
    # workflow_controller.ex:131-134; manual.ex:31-48; work_orders.ex:176-190
    # useRunRetry.test.tsx:573-610; workflow_controller_test.exs:22-45

  @S03 @pending
  Scenario Outline: A custom input must be a JSON object within the size limit
    # Value: no run starts with an input the job can't read, and nobody waits on an upload the server will reject.
    Given the run panel is open for "Fetch" on the "New" tab
    When the editor holds <input>
    Then I see <message>
    And "Run From Here" is disabled
    # CustomView.tsx:39-54, :91-101; useRunRetry.ts:215-241; manual.ex:58-70 (server repeats the object check)
    # useRunRetry.test.tsx:272-367; manual_test.exs:53-65

    Examples:
      | input                         | message                                 |
      | {"a": 1                       | "Invalid JSON format"                   |
      | [1, 2]                        | "Must be an object"                     |
      | an object larger than 10 MB   | "Dataclip exceeds the 10 MB size limit" |
      | nothing                       | no message                              |

  @S04 @pending
  Scenario: Upload a JSON file as the custom input
    # Value: builders reuse sample payloads they already have on disk instead of pasting them.
    Given the run panel is open for "Fetch" on the "New" tab
    When I upload "sample.json" containing {"a":1}
    Then the editor shows it indented by two spaces
    When I drop "notes.txt" onto the upload area
    Then I see "Invalid file format. Please only upload: JSON" for a few seconds
    # CustomView.tsx:25-37, :77; FileUploader.tsx:29-64, :112-122; no test found

  @S05 @pending
  Scenario: Run with an input the step received before
    # Value: a builder replays real data that broke a step, without asking the source system to send it again.
    Given step "Fetch" has received inputs in earlier runs
    And the run panel is open for "Fetch"
    When I open the "Existing" tab
    Then I see up to 10 of those inputs, newest first, each with its name or short id, type and created date
    And I see "Search results are limited to the 10 most recent matches for this step."
    When I click one
    Then I see its name or "Unnamed", its type and date
    And the flow hands off to shared-dataclip-body-viewer for its body
    When I click "Run From Here"
    Then the new work order uses that dataclip and no new dataclip is created
    # ManualRunPanel.tsx:298-370, :538-560, :591-599; ExistingView.tsx:263-316; SelectedDataclipView.tsx:60-170
    # dataclip_controller.ex:114-187; new_manual_run.ex:26-58; invocation.ex:87-104; query.ex:326-335; work_orders.ex:177-178
    # ManualRunPanel.test.tsx:524-548, :650-682; SelectedDataclipView.test.tsx:47-107; useRunRetry.test.tsx:540-571; dataclip_controller_test.exs:345-360

  @S06 @pending
  Scenario Outline: Find an earlier input by search and filters
    # Value: a builder finds the one payload behind a failure among many runs.
    Given the run panel is open for "Fetch" on the "Existing" tab
    When I <action>
    Then only matching inputs are listed, refreshed shortly after I stop changing filters
    And active filters show as removable pills
    And when none match I see "No dataclips match the filter."
    # ManualRunPanel.tsx:372-458; ExistingView.tsx:72-96, :98-255, :306-310; new_manual_run.ex:60-104; invocation.ex:1422-1461
    # ManualRunPanel.test.tsx:780-824; new_manual_run_test.exs:7-51; dataclip_controller_test.exs:362-385

    Examples:
      | action                                                    |
      | type part of an input's name and press Enter              |
      | type a full input id                                      |
      | choose type "http request" in the type filter             |
      | set "Created After" and "Created Before"                  |
      | turn on the named only filter                             |

  @S07 @pending
  Scenario: Inputs never cross projects
    # Value: a run in one project can never read another project's data as its input.
    Given step "Other" belongs to project "Kenya TB" where I am not a member
    When the panel asks for earlier inputs of "Other" through project "Malawi HIV"
    Then the list is empty
    When a run is submitted in "Malawi HIV" with a dataclip from "Kenya TB"
    Then no work order is created
    # new_manual_run.ex:34-37, :55-57; manual.ex:72-84
    # dataclip_controller_test.exs:404-417; new_manual_run_test.exs:331-347; manual_test.exs:15-33

  @S08 @pending
  Scenario: A cron step defaults to the input its next scheduled run will use
    # Value: a builder tests with exactly the state the next cron run will receive.
    Given step "Fetch" is reached from a cron trigger
    And the last successful run of "Intake" ended with dataclip "D"
    When I open the run panel for "Fetch" or for that trigger
    Then "D" is selected
    And I see "Default Next Input for Cron" and "This workflow has a "cron" trigger, and by default it will use the input below for its next run. You can override that by starting a manual run with an empty input or a custom input at any time."
    And in the "Existing" list "D" is first, marked with a clock titled "Next state that will be used for cron execution"
    # ManualRunPanel.tsx:339-359, :577; SelectedDataclipView.tsx:149-165; ExistingView.tsx:267-288
    # invocation.ex:283-334, :1342-1378
    # ManualRunPanel.test.tsx:550-624; SelectedDataclipView.test.tsx:131-171; new_manual_run_test.exs:120-249

  @S09 @pending
  Scenario: An input I unselect stays unselected
    # Value: the panel never puts back an input the builder deliberately set aside.
    Given the run panel is open for "Fetch" with an existing input selected
    When I click the close button beside the input's name
    Then the tabs return and "Run From Here" is disabled on the "Existing" tab
    When I switch to "New" and back to "Existing"
    Then no input is selected
    When I switch to "Empty"
    Then "Run From Here" is enabled
    # ManualRunPanel.tsx:108, :123-130, :265-296, :468-470; SelectedDataclipView.tsx:140-145; useRunRetry.ts:236-241
    # ManualRunPanel.test.tsx:1141-1300

  @S10 @pending
  Scenario: Name an earlier input
    # Value: teams label reference payloads ("Malawi edge case") so anyone can find and reuse them.
    Given I am an editor and an existing input "Unnamed" is selected
    When I click the pencil, type "Malawi edge case" and press Enter
    Then the input is shown as "Malawi edge case" here and in the list
    And an audit event "label_created" is recorded for the dataclip
    When I clear the name and save
    Then it shows "Unnamed" and an audit event "label_deleted" is recorded
    And when I am a viewer I see no pencil
    # SelectedDataclipView.tsx:33-58, :60-138; ManualRunPanel.tsx:472-486; api/dataclips.ts:99-131
    # dataclip_controller.ex:157-169, :254-292; invocation.ex:403-416; dataclip_audit.ex:18-29
    # SelectedDataclipView.test.tsx:173-215, :298-370, :598-630, :765-797; dataclip_controller_test.exs:597-624, :637-664

  @S11 @pending
  Scenario: Run the whole workflow with a custom input from the header
    # Value: a builder tests the workflow from its entry point with data they choose.
    Given "Intake" has trigger "Webhook" connected to step "Fetch"
    When I choose "Run with custom input" from the header Run menu
    Then the trigger is selected and the run panel opens titled "Pick a custom input"
    And the URL has "panel=run", "trigger=<Webhook id>" and "runMode=custom-input"
    And the "Existing" list shows inputs received by "Fetch"
    When I reload the page
    Then the panel is still titled "Pick a custom input"
    When I run with the "Empty" tab
    Then the work order starts at "Fetch"
    # NewRunButton.tsx:87-161; Header.tsx:493-502, :610-625; WorkflowEditor.tsx:57-155; ManualRunPanel.tsx:189-208
    # workflow_controller.ex:103-124
    # ManualRunPanel.test.tsx:258-274, :503-522; Header.keyboard.test.tsx:1257-1366; workflow_controller_test.exs:86-106

  @S12 @pending
  Scenario: Quick run from the header
    # Value: one click runs the whole workflow end to end while building it.
    Given "Intake" has a trigger and no run is loaded
    When I click "Run" in the header, or press Ctrl+Enter with no panel open
    Then the workflow is saved and a run starts from the first trigger with an empty input
    And the panel does not open and the URL has "run=<new run id>"
    # Header.tsx:385-420, :587-608, :863-879; NewRunButton.tsx:72-85
    # Header.keyboard.test.tsx:1140-1256; e2e run-retry-keyboard-shortcuts.spec.ts:58-91

  @S13 @pending
  Scenario: A path cannot be a starting point
    # Value: every manual run starts from a node the server can resolve.
    Given the run panel is open for "Fetch"
    When I select the path from "Fetch" to "Post"
    Then the panel says "Select a Step or Trigger to start a Run from"
    And "Run From Here" is disabled
    When I select step "Post"
    Then the panel is titled "Run from Post"
    # WorkflowEditor.tsx:184-198; ManualRunPanel.tsx:585-590; useRunRetry.ts:241-243
    # useRunRetry.test.tsx:221-228

  @S14 @pending
  Scenario: Retry a followed run from a step with the same input
    # Value: after fixing a step, the builder re-runs it on the same input and work order without re-running upstream steps.
    Given run "R" of "Intake" is loaded and its "Fetch" step took input "D", not wiped
    When I open the run panel for "Fetch"
    Then "D" is selected and marked "Current dataclip for this step" in the list
    And the button reads "Retry" with a chevron
    When I click "Retry"
    Then the workflow is saved and a new run is created on R's work order starting at "Fetch" with input "D"
    And steps upstream of "Fetch" are attached to the new run, not executed again
    And I see "Retry started" with "Saved latest changes and re-running with previous input"
    And the URL has "run=<new run id>"
    # ManualRunPanel.tsx:236-296, :683-700; RunRetryButton.tsx:50-290; useRunRetry.ts:168-213, :343-449
    # workflow_controller.ex:208-244; work_orders.ex:296-401, :810-835, :870-905
    # useRunRetry.test.tsx:388-413, :656-705, :903-943; workflow_controller_test.exs:435-449; e2e run-retry-keyboard-shortcuts.spec.ts:93-141

  @S15 @pending
  Scenario: Force a new work order while retry is available
    # Value: a builder can start a fresh, separately tracked run with the same input instead of extending the old work order.
    Given the panel offers "Retry" for run "R"
    When I open the chevron and choose "Run (New Work Order)", or press Ctrl+Shift+Enter
    Then a new work order is created with input "D"
    And R's work order gets no new run
    # RunRetryButton.tsx:128-131, :258-286; useRunRetryShortcuts.ts:115-126
    # RunRetryButton.test.tsx:154-212; ManualRunPanel.keyboard.test.tsx:986-1218; e2e run-retry-keyboard-shortcuts.spec.ts:143-185, :287-331

  @S16 @pending
  Scenario: Run, retry and close from the keyboard
    # Value: builders iterate on a step without reaching for the mouse.
    Given the run panel is open for "Fetch" with a valid input
    When I press Ctrl+Enter, even while typing in the input editor or the search box
    Then a run starts, or a retry when one is offered
    When I press Escape
    Then the panel closes
    # ManualRunPanel.tsx:488-512; useRunRetryShortcuts.ts:90-127
    # ManualRunPanel.keyboard.test.tsx:410-573, :773-984, :1341-1388; e2e run-retry-keyboard-shortcuts.spec.ts:366-395

  @S17 @pending
  Scenario: A run never starts if the workflow can't be saved first
    # Value: a run always executes the version on screen, never an older saved one the builder thinks they changed.
    Given "Intake" has a change the server will not save
    When I click "Run From Here"
    Then no work order is created
    And I see "Failed to submit run" with the save error
    # useRunRetry.ts:264-267, :316-324; useSaveBeforeRun.ts:17-26
    # ManualRunPanel.test.tsx:973-1049; useSaveBeforeRun.test.tsx:19-28

  @S18 @pending @variant:experimental-features
  Scenario: A live workflow runs without saving
    # Value: testing a live workflow never requires taking it out of production.
    Given "Intake" is live and content-locked
    When I start a run from "Fetch"
    Then the workflow is not saved
    And I see "Run started" with "Created new work order"
    # useSaveBeforeRun.ts:21-25; useRunRetry.ts:291-296
    # useSaveBeforeRun.test.tsx:30-50

  @S19 @pending
  Scenario Outline: Run is refused with a reason
    # Value: people see why they can't run instead of clicking a button that silently does nothing.
    Given <state>
    When I look at "Run From Here" in the panel and the header Run button
    Then they are disabled with the tooltip <tooltip>
    # useWorkflow.tsx:951-1004; NewRunButton.tsx:47-59; ManualRunPanel.tsx:685, :699
    # ManualRunPanel.test.tsx:827-925 (mocks useCanRun; asserts disabled only); e2e run-retry-keyboard-shortcuts.spec.ts:225-252

    Examples:
      | state                                              | tooltip                                                 |
      | the editor is disconnected                         | "You are disconnected. Reconnecting..."                 |
      | I am a viewer                                      | "You do not have permission to run workflows"           |
      | "Intake" has been deleted                          | "Workflow has been deleted"                             |
      | I am viewing a pinned version                      | "You are viewing a pinned version of this workflow"     |
      | "Intake" is new and not yet created                | "Create this workflow before running it"                |
      | the project's run limit says "Run limit reached"   | "Run limit reached"                                     |

  @S20 @pending
  Scenario Outline: The server only starts runs for people who may run them
    # Value: only people trusted to execute code against external systems can do so, whatever the client shows.
    Given workflow "Intake" in project "Malawi HIV"
    And <who>
    When a manual run is posted for "Intake" through "Malawi HIV"
    Then the response is <status> and <outcome>
    # workflow_controller.ex:40, :68-93; project_users.ex:173-185
    # workflow_controller_test.exs:108-201

    Examples:
      | who                                                                  | status | outcome                  |
      | I am signed out                                                      | 302    | I am sent to log in      |
      | I am not a member                                                    | 403    | no work order is created |
      | I am a support user and the project has not allowed support access   | 403    | no work order is created |
      | I am a support user and the project allows support access            | 201    | a work order is created  |
      | I am an editor but "Intake" belongs to another project               | 403    | no work order is created |

  @S21 @pending
  Scenario Outline: A retry that can't run says why
    # Value: a builder learns the input is gone or the workflow is deleted instead of assuming a retry happened.
    Given the panel offers "Retry" for run "R"
    And <state>
    When I click "Retry"
    Then no new run is created
    And I see "Retry failed" with <message>
    # useRunRetry.ts:385-388, :429-437; workflow_controller.ex:245-262; work_orders.ex:334-352
    # workflow_controller_test.exs:451-533

    Examples:
      | state                                    | message                                   |
      | R's input to "Fetch" has been wiped      | "Failed to retry run"                     |
      | "Intake" has been deleted                | "Cannot retry run for deleted workflow"   |

  @S22 @pending @variant:run-limit-reached
  Scenario: The server enforces the run limit even when the page allowed the click
    # Value: plan limits hold even if the page's view of the limit is stale.
    Given the usage limiter refuses new runs with "Run limit exceeded for this project"
    When I start a run or a retry from the panel
    Then no run is created
    And I see the toast with "Run limit exceeded for this project"
    # helpers.ex:51-53; workflow_controller.ex:235, :246-249; fallback_controller.ex:55-63; api/dataclips.ts:160-170
    # workflow_controller_test.exs:261-286, :451-476

  @S23 @pending
  Scenario: One click starts one run
    # Value: an impatient double click or a still-running run never stacks duplicate work orders.
    Given the run panel is open for "Fetch"
    When I click "Run From Here" and the save is still in progress
    Then the button reads "Processing" and is disabled
    And clicking it again does not submit a second run
    And while a followed run is still running the button stays "Processing"
    # ManualRunPanel.tsx:686; useRunRetry.ts:136, :174, :178-202, :344-348; RunRetryButton.tsx:133-171, :184-234
    # ManualRunPanel.test.tsx:1086-1138; RunRetryButton.test.tsx:77-108, :888-912; e2e run-retry-keyboard-shortcuts.spec.ts:333-364

  @S24 @pending
  Scenario: A link can open the panel with an input chosen
    # Value: handoffs from other screens land ready to run with the intended input.
    Given step "Fetch" has received input "D" recently
    When I open "/projects/<id>/w/<Intake id>?panel=run&job=<Fetch id>&dataclip=<D id>"
    Then the run panel opens for "Fetch" with "D" selected on the "Existing" tab
    And "dataclip" is removed from the URL
    # WorkflowEditor.tsx:121-136; ManualRunPanel.tsx:317-337
    # ManualRunPanel.test.tsx:408-501

  @S25 @pending
  Scenario: Errors inside the panel don't take down the editor
    # Value: a broken input preview or bad response leaves the canvas and unsaved work usable.
    Given something in the run panel throws while rendering
    Then I see "Error loading run panel" with the error
    And the rest of the editor keeps working
    # ManualRunPanelErrorBoundary.tsx:27-60; WorkflowEditor.tsx:356-368; no test found
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The custom input editor keeps its own text and starts empty on every mount, while the panel keeps the last body in separate state; after leaving the "New" tab (or switching step) and coming back, the editor is blank but the old body is still what Run submits | `CustomView.tsx:23`, `:56-67`, `:106`; `ManualRunPanel.tsx:97`, `:106`, `:518-537`; `useRunRetry.ts:236-241`, `:284-286` | an empty editor with an enabled Run button that starts a run with text they can no longer see. Inferred from code | fix |
| The uploader says "JSON, up to 8MB" but the limit is the configured dataclip size (10 MB by default) and the uploader itself checks no size | `FileUploader.tsx:127-129`; `CustomView.tsx:12`, `:41-44` | copy that does not match the control | fix |
| Each render of the custom view adds another drop listener, and cleanup removes a fresh closure, so listeners pile up | `FileUploader.tsx:66-93`; `CustomView.tsx:25-37` | one drop reads and loads the file several times; mostly invisible. Inferred from code | fix |
| Escape while renaming an input calls `preventDefault` in React, but the panel's Escape shortcut listens on `window` through tinykeys and still fires | `SelectedDataclipView.tsx:81-84`; `ManualRunPanel.tsx:488-494`; `KeyboardProvider.tsx:94-121` | pressing Escape to cancel a rename closes the whole run panel. Inferred from code, not checked in a browser | fix |
| Date filters send the browser's local `datetime-local` value, which the server casts as a naive time and compares with UTC `inserted_at` | `ExistingView.tsx:163-193`; `new_manual_run.ex:65-73`; `invocation.ex:1440-1444` | "Created After 10:00" in Nairobi filters from 10:00 UTC, three hours off. Inferred from code | fix |
| For a cron step, the next cron input is checked against date filters with `DateTime.compare` against a `NaiveDateTime` | `invocation.ex:1393-1397`; `new_manual_run.ex:68-69` | the search request likely fails (500) whenever a date filter is set on a cron step, and the list silently does not change. Inferred from code, not run | fix |
| A hex search term ORs an id-prefix range onto the filters reduced before it, so the id branch escapes the date filters; odd-length prefixes drop their last character, and the post-filter that would fix that reads a key never set | `invocation.ex:1422-1435`, `:1462-1490`, `:1492-1500`; `new_manual_run.ex:94-96` | searching "a3f" lists inputs whose ids start "a3" and ones outside the chosen dates. Inferred from code | fix |
| Debounced searches have no cancellation, so a slower earlier response can overwrite a later one | `ManualRunPanel.tsx:425-458` | the list shows results for the previous filter. Inferred from code | fix |
| A manual run on a workflow deleted after the page loaded returns `{:error, :workflow_deleted}`, which no `FallbackController` clause matches | `work_orders.ex:129-135`, `:159-161`; `helpers.ex:46-64`; `workflow_controller.ex:40-65`; `fallback_controller.ex:10-76` | a 500 and the generic "Failed to submit manual run". Inferred from code | fix |
| A retry with a step id that is not in the run gets a nil `:run` and then calls `Ecto.assoc(nil, :steps)` | `work_orders.ex:314-333` | a 500 and "Retry failed" with a JSON parse error message. Inferred from code | fix |
| HTML error pages (403, 404, 400) from `create_run`, and changeset JSON (`{"errors": ...}`) from both endpoints, are read as `{error}`; the message is lost | `workflow_controller.ex:12`; `fallback_controller.ex:10-53`; `api/dataclips.ts:160-170`, `:119-128`; `useRunRetry.ts:385-388` | "Failed to submit manual run", "Failed to update dataclip name" or a JSON parse error with no reason | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Every run without an existing input, including "Empty", inserts a new `saved_input` dataclip | `workflow_controller.ex:131-134`; `work_orders.ex:179-189` | decide |
| A trigger run resolves the first edge from the trigger, enabled or not; the client falls back to the workflow's first job for the list when the trigger has no edge, but the server answers 404 | `workflow_controller.ex:103-124`; `ManualRunPanel.tsx:201-208`; `workflow_controller_test.exs:233-247` | decide |
| The client allows a run with edit or run permission, the server needs both; the two grant the same roles today | `useWorkflow.tsx:976-977`; `workflow_controller.ex:87-88`; `project_users.ex:39-49` | preserve |
| `retry_run` answers a run in another project or a missing run with 422 and an `inspect`ed atom (`":forbidden"`, `":not_found"`), not 403 or 404 | `workflow_controller.ex:271-274`, `:284-294`; `workflow_controller_test.exs:550-586` | decide |
| A viewer refused by `retry_run` or `update_name` gets 401 "Authorization Error", a non-member on `create_run` gets 403 | `workflow_controller.ex:268-269`; `fallback_controller.ex:24-29`, `:41-46`; `dataclip_controller_test.exs:637-664` | decide |
| A duplicate input name is refused by a unique index, and the user sees only "Failed to update dataclip name" | `invocation.ex:407`; `20250715094846_add_name_to_dataclips.exs:9`; `api/dataclips.ts:119-128` | decide |
| Retry is offered only when the followed run's input for the step is among the 10 inputs fetched on open | `ManualRunPanel.tsx:241-249`, `:265-296`; `useRunRetry.ts:204-213` | decide |
| A `dataclip=` link is honoured only if that input is in the first 10 results for the step; otherwise it is dropped silently | `ManualRunPanel.tsx:317-337`; `ManualRunPanel.test.tsx:479-501` | decide |
| The list for a cron step can show 11 items (next cron input plus 10), under copy that says 10; with experimental features it includes named inputs from other steps under copy that says "for this step" | `invocation.ex:1369-1377`; `query.ex:286-304`; `ExistingView.tsx:311-316` | decide |
| `last_n_for_job` uses `distinct: [desc: inserted_at]`, so two inputs created in the same microsecond show once | `query.ex:326-335` | preserve |
| Client size check counts the raw body; the server limit applies to the whole JSON request, where the body is escaped inside a string, so a body just under the limit can still get 413 "Dataclip is too large. Reduce the size and try again." | `useRunRetry.ts:229-234`; `plug_configs.ex:14`; `api/dataclips.ts:141-162` | decide |
| File type is judged by the browser's MIME type ending in `/json`; a `.json` file with no MIME type is refused | `FileUploader.tsx:43-47` | decide |
| The file input allows multiple files and then refuses more than one with "Only 1 files can be uploaded" | `FileUploader.tsx:56-58`, `:116` | decide |
| Invalid JSON in an uploaded file is loaded raw so the editor flags it | `CustomView.tsx:30-34` | preserve |
| Copy and labels are title case: "Run From Here", "Run Workflow", "Run (New Work Order)", "Filter by Date Created", "Created After", "Default Next Input for Cron" | `ManualRunPanel.tsx:196`, `:694`; `RunRetryButton.tsx:64`, `:282`; `ExistingView.tsx:161-181`; `SelectedDataclipView.tsx:157` | decide |
| The panel title shows the trigger type in lowercase, "Run from Trigger (webhook)"; with no triggers or nodes it falls back to "Run Workflow" | `ManualRunPanel.tsx:191-197` | decide |
| The custom tab is "New" in the canvas panel and "Custom" in the IDE | `ManualRunPanel.tsx:609-612`, `:640-643` | decide |
| Filter pills show raw keys and values: "named_only", "before: 2025-05-14T14:35" | `ExistingView.tsx:72-89` | decide |
| The type pill styles four types; `kafka` renders unstyled | `DataclipTypePill.tsx:3`, `:19-25` | decide |
| A disabled Run with no permission problem (no input chosen, invalid custom body) has no tooltip saying why | `ManualRunPanel.tsx:685`, `:699`; `RunRetryButton.tsx:73-78` | decide |
| The unselect, pencil and save buttons in the selected input header have no accessible label | `SelectedDataclipView.tsx:92-107, :115-122, :140-145` | fix |
| A changed step or trigger resets the selection and filters only when no run is followed; the tab and custom body are kept | `ManualRunPanel.tsx:251-259` | decide |
| The panel's Run and the header's Run show different success copy for retry ("re-running with previous input" against "re-running this input on v3") | `useRunRetry.ts:394-399`; `Header.tsx:450-460` | decide |
| Retry with experimental features clears `release`, `v`, `as_run` and `step` from the URL; without it only `run` changes | `useRunRetry.ts:406-416`; `useRunRetry.test.tsx:903-943` | preserve |
| A retry runs against the latest snapshot, not the one the original run used | `work_orders.ex:355-362`; `Header.tsx:376-381` | preserve |
| The WebSocket confirmation wait resets the submitting state after 30 s if the run never appears | `useRunRetry.ts:34`, `:187-202` | preserve |
| `NewRunButton` documents use in `TriggerInspector`, which no longer renders it (`onOpenRunPanel` is unused there) | `NewRunButton.tsx:23-35`; `TriggerInspector.tsx:15`, `:27` | preserve |
| Input dates show with `toLocaleDateString` in the preview and `formatDate` in the list | `SelectedDataclipView.tsx:133`; `ExistingView.tsx:300-302` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `maybe_filter_uuid_prefix` | `invocation.ex:1492-1500` | reads `:id_prefix`, which `get_dataclips_filters` never sets |
| `SeletableOptions` enum | `manual-run-panel/types.ts:1-5` | no reference found |
| `getRunDataclip` and `show_for_run` from this panel | `api/dataclips.ts:74-94` | the panel never calls them; other views do (see not_reachable_here) |
| `get_run_steps` | `workflow_controller.ex:154-198` | no client caller found; listed under workflow-editor-run-viewer |
| `pushEvent('manual_run_change', ...)` naming in `CustomView` | `CustomView.tsx:59-64`; `ManualRunPanel.tsx:520-533` | a LiveView-era event name; the panel adapts it to a local callback |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Custom input capped at `max_dataclip_size_bytes` (10 MB default) in the client and the JSON parser | `CustomView.tsx:12`, `:41-44`; `plug_configs.ex:14`; `bootstrap.ex:367-369` | yes, the size message and 413 toast | preserve |
| Search page size 10, default and client-set; the server accepts any positive `limit` | `api/dataclips.ts:54`; `dataclip_controller.ex:189-198` | yes | preserve |
| Filter changes and typing are debounced 300 ms | `ManualRunPanel.tsx:430-446` | no | preserve |
| Upload errors vanish after 3.5 s | `FileUploader.tsx:21-28` | yes | preserve |
| Manual runs go to queue `manual` with priority `immediate` | `work_orders.ex:139-145`, `:882` | no | preserve |
| Next cron input queries use `prepare: :unnamed` to avoid a generic plan scan | `invocation.ex:296-334` | no | preserve |

### 6.5 Things seen but not understood

- `saveWorkflow({ notify: 'none' })` before a run: whether a save failure still raises its own toast as well as "Failed to submit run" depends on shared-editor-session's save notifications; not traced.
- The header's quick run (S12) is also part of workflow-editor-canvas's surface; it is written here because it uses this view's endpoint and button. The lead may move it.
- `getLimits('new_run')` after a run: the canvas annotation notes the limits refresh reply is never read; not re-verified here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. What is the new route for the panel, and do `panel=run`, `runMode` and `dataclip` deep links keep working?
2. Should "Empty" runs keep creating a new `saved_input` dataclip each time (6.2)?
3. Should retry and deep-linked inputs work when the input is older than the 10 most recent (6.2)?
4. Should the server tell the client why a run was refused (403, 404, changeset) in a shape the client reads (6.1)?
5. Does the header quick run (S12) belong here or in workflow-editor-canvas?
6. Should a trigger run respect a disabled first edge (6.2)?

## Proposed flows

- `flow-manual-run-live-follow`: a manual run or retry started here is claimed by a worker, and its progress streams back into the open editor, where the run viewer follows it and the panel's button returns from "Processing" to "Retry". Surfaces: workflow-editor-manual-run, controller:workflow-create-run (workflow_controller.ex:26-66) or controller:workflow-retry-run (workflow_controller.ex:208-244), controller:worker-channel (claim), controller:run-channel (run:<id>), workflow-editor-run-viewer. This file asserts only that `run=<id>` is set and the run viewer takes over (S01, S14).
- Extend existing `flow-history-live-updates`: add workflow-editor-manual-run as a source. Manual runs publish `work_order_created` and `run_created`, retries `work_order_updated` and `run_created`, on `project:<id>` (work_orders.ex:151-157, :391-394), which an open History tab receives. Surfaces: workflow-editor-manual-run, pubsub:project:<project_id>, history-work-orders.

## Proposed shared

- `shared-editor-session` (lead to create): this panel relies on connection and sync state for the disconnected refusal (`useWorkflow.tsx:851-871`, `:983-985`), `can_edit_workflow` and `can_run_workflow` from `get_context` (`workflow_channel.ex:1520-1521`), the content lock and pinned view that skip the save (`useSaveBeforeRun.ts:17-26`), `saveWorkflow` (`WorkflowEditor.tsx:46`, `:366`), workflow deletion state, session limits and `getLimits` (`useRunRetry.ts:143-145`), `max_dataclip_size_bytes` in the app config (`workflow_channel.ex:1413`; `ManualRunPanel.tsx:89-91`), the priority `KeyboardProvider` (panel at priority 25), URL state (`useURLState`), and the run-panel open state in the UI store (`types/ui.ts:24-33`, `:64-74`). Surfaces: every workflow-editor-* view.
- `shared-run-retry-controls`: `NewRunButton`, `RunRetryButton`, `useRunRetry`, `useRunRetryShortcuts`, `useSaveBeforeRun` and `useCanRun`, used by this panel, the canvas header, the step inspector and the full-screen IDE. Behaviour: tooltip and disabled reasons (S19), split button with "Run with custom input" or "Run (New Work Order)", "Processing" state, save before run, toasts, limit refresh, retry detection. Surfaces: workflow-editor-manual-run, workflow-editor-canvas (Header.tsx:863-879), workflow-editor-inspectors (JobInspector.tsx:133-137), workflow-editor-ide (FullScreenIDE.tsx:925-960). Until it exists, S12, S15, S16, S19 and S23 here are its scenarios.

## Lead resolution (batch 5)

- `shared-run-retry-controls` and `flow-manual-run-live-follow` created. This view added to flow-history-live-updates surfaces.
- `shared-editor-session` created.
