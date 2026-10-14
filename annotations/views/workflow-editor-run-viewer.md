---
id: workflow-editor-run-viewer
type: view
title: Workflow editor › Run viewer (?run=)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id?run=<run id> (WorkflowLive.Collaborate), with optional panel=editor, job=<job id>, step=<step id>
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - everything shared-editor-session lists (project scope gate, workflow belongs to the project and is not deleted, collaboration channel joined)
    - the workflow is not a new, unsaved one; the server preload and the canvas history are skipped for :new (collaborate.ex:100-104; CollaborativeWorkflowDiagram.tsx:236-240)
    - the steps and logs panel (RunViewerPanel) renders only inside the full-screen IDE, when run=<id> is set (FullScreenIDE.tsx:195-197, :1285-1293); on the canvas the run shows only as node and edge painting (CollaborativeWorkflowDiagram.tsx:171, :298-305)
    - the run channel join succeeds: the run exists and the user has :access_project on the run's own project (run_channel.ex:67-95)
    - following waits for the workflow channel to be connected (useHistory.ts:155-162, :325-334)

inherits:
  - shared-authenticated-session    # live_session :default; the steps endpoint sits behind :require_authenticated_user (router.ex:219-221; workflow_controller_test.exs:371-382)
  - shared-project-scope            # S03 non-member, S05 MFA, S07 removal: who can open the editor that hosts this view
  - shared-editor-session           # channel join, connection state, read-only views, teardown (its S11 to S16); not restated here
  - shared-log-viewer               # the "Logs" tab body: ordering, JSON, level filter, step marking, "No logs were received for this run." (its S01, S02, S03, S05, S06); this file owns only the waiting overlay
  - shared-dataclip-body-viewer     # the "Input" and "Output" tab bodies once a step has a dataclip id (its S01, S02, S04)
  - shared-run-retry-controls       # Retry for the loaded run reads the followed run and the selected job's step (its S02, S04); not restated here
  - shared-run-components
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: run
    set_by: flow-open-run-in-editor (run-show, history-work-orders, legacy redirect), flow-manual-run-live-follow (useRunRetry.ts:311; FullScreenIDE.tsx:207-210), shared-run-retry-controls after a retry, MiniHistory run selection (workflow-editor-versions-and-promote; CollaborativeWorkflowDiagram.tsx:192-227; FullScreenIDE.tsx:266-273)
    effect: server preloads that run's steps into data-initial-run-data when it belongs to the mounted project (collaborate.ex:94-142, :282-286); the client joins run:<id>, paints the canvas and, in the IDE, opens the run viewer panel (useHistory.ts:150-171; FullScreenIDE.tsx:554-562); removed by the run chip's close (FullScreenIDE.tsx:227-238)
  - name: step
    set_by: this view's step list (StepItem.tsx:32-52), the IDE when the job changes while a run is loaded (FullScreenIDE.tsx:570-578), step inspect links (flow-open-run-in-editor S02)
    effect: selects that step for the Input, Output and Logs tabs (FullScreenIDE.tsx:564-568; createHistoryStore.ts:571-584); see 6.1 for when it is ignored
  - name: job
    set_by: this view's step list (StepItem.tsx:40-44), plus the entry points workflow-editor-ide lists
    effect: the IDE switches to that job's code (owned by workflow-editor-ide)
  - name: panel
    set_by: workflow-editor-ide
    effect: preserved by the step list when present, never added (StepItem.tsx:37-49)

config_variants:
  default: {}                       # read under this variant; nothing in the panel or the painting reads config. The experimental-features rewriting of run/as_run is owned by flow-open-run-in-editor

inventory:
  routes:
    - get /projects/:project_id/runs/:run_id/steps  WorkflowController :get_run_steps   # router.ex:219-221; workflow_controller.ex:145-198; no client caller (6.3)
  events:
    - WorkflowLive.Collaborate#handle_params run preload (collaborate.ex:93-142)       # the live route itself is owned by shared-editor-session / workflow-editor-canvas
    - WorkflowChannel#request_run_steps (workflow_channel.ex:267-287, :1268-1271, :1294-1296, :2389-2415)
    - RunChannel browser join "run:<id>" (run_channel.ex:67-99)
    - RunChannel#fetch:run (run_channel.ex:261-275)
    - RunChannel#fetch:logs (run_channel.ex:277-293)                                   # listed by shared-log-viewer too; called from LogTabPanel.tsx:270-285
  js_hooks:
    - ReactComponent CollaborativeEditor data-initial-run-data attribute (collaborate.ex:282-286; CollaborativeEditor.tsx:427, :453; StoreProvider.tsx:122-131)   # the hook itself is owned by shared-editor-session
  react_components:
    - collaborative-editor/components/run-viewer/RunViewerPanel.tsx
    - collaborative-editor/components/run-viewer/RunTabPanel.tsx
    - collaborative-editor/components/run-viewer/StepList.tsx
    - collaborative-editor/components/run-viewer/StepItem.tsx
    - collaborative-editor/components/run-viewer/StatePill.tsx
    - collaborative-editor/components/run-viewer/StepIcon.tsx
    - collaborative-editor/components/run-viewer/ElapsedIndicator.tsx
    - collaborative-editor/components/run-viewer/RunSkeleton.tsx
    - collaborative-editor/components/run-viewer/RunViewerErrorBoundary.tsx
    - collaborative-editor/components/run-viewer/InputTabPanel.tsx
    - collaborative-editor/components/run-viewer/OutputTabPanel.tsx
    - collaborative-editor/components/run-viewer/LogTabPanel.tsx (waiting overlay only; the viewer body is shared-log-viewer)
    - collaborative-editor/components/common/RunBadge.tsx (run chip in the IDE right panel)
    - FullScreenIDE right panel in run-viewer state: chip, "Logs" / "Input" / "Output" tabs, collapse and expand (FullScreenIDE.tsx:1144-1293)
    - collaborative-editor/stores/createHistoryStore.ts active run and run steps cache (:144-205, :358-521, :571-584, :704-842, :891-1049)
    - collaborative-editor/hooks/useHistory.ts (useFollowRun, useActiveRun*, useSelectedStep*, useJobMatchesRun, useRunSteps)
    - collaborative-editor/utils/runStepsTransformer.ts
    - workflow-diagram/util/from-workflow.tsx run painting (:56-80, :113-125, :153-165), workflow-diagram/nodes/Node.tsx (:95-117, :176-235)
  policies:
    - Lightning.Policies.ProjectUsers :access_project   # run channel join (run_channel.ex:76) and re-check on membership events (:333-370); get_run_steps (workflow_controller.ex:165-171)
  workers: []
  api_endpoints:
    - get /projects/:project_id/runs/:run_id/steps  WorkflowController :get_run_steps
    - channel run:<id> join, "fetch:run", "fetch:logs" (browser side)
    - channel workflow:collaborate:<id> "request_run_steps"
  emails: []
  config: []
  not_reachable_here:
    - RunChannel handle_info RunUpdated, StepStarted, StepCompleted, LogAppended forwarders and the client handlers (run_channel.ex:296-318; createHistoryStore.ts:391-521); owned by flow-manual-run-live-follow
    - RunChannel push "dataclip:updated" (run_channel.ex:320-323); no editor listener, owned by flow-zero-persistence-runs
    - RunChannel membership teardown (run_channel.ex:333-370); owned by flow-manual-run-live-follow S08
    - MiniHistory (run list, run chip on the canvas, version mismatch banner), VersionMismatchBanner, request_history; owned by workflow-editor-versions-and-promote (CollaborativeWorkflowDiagram.tsx:307-324; FullScreenIDE.tsx:1225-1232, :1294-1310)
    - Ctrl/Cmd+H history toggle (CollaborativeWorkflowDiagram.tsx:84-93); owned by workflow-editor-canvas
    - LogLevelFilter, log-viewer/store.ts, log-viewer/component.tsx; owned by shared-log-viewer
    - DataclipViewer and GET /dataclip/body/:id; owned by shared-dataclip-body-viewer
    - Header Retry and run shortcuts; owned by shared-run-retry-controls
    - the remembered right panel tab (localStorage lightning.ide-run-viewer-tab, FullScreenIDE.tsx:373-390); owned by workflow-editor-ide (its 6.1)
    - createHistoryStore test helpers _setActiveRunForTesting, _setActiveRunIdForTesting, _populateCacheForTesting, _triggerStepUpdateForTesting (createHistoryStore.ts:1051-1116); test only (6.3)

related:
  - workflow-editor-ide                     # hosts RunViewerPanel; its S09, S14, S19 land here
  - workflow-editor-canvas                  # hosts the run painting; lists ?run= as owned here
  - workflow-editor-manual-run              # its S01, S14 hand off here
  - workflow-editor-versions-and-promote    # MiniHistory and the version mismatch banner
  - shared-run-components                   # the LiveView originals of StatePill, StepIcon, ElapsedIndicator and the clone marker
  - run-show                                # "Run" link target
  - history-work-orders                     # "Work Order" link target
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/controllers/workflow_controller.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning/invocation.ex
  - lib/lightning/runs.ex
  - assets/js/collaborative-editor/components/run-viewer/
  - assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
  - assets/js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.tsx
  - assets/js/collaborative-editor/stores/createHistoryStore.ts
  - assets/js/collaborative-editor/hooks/useHistory.ts
  - assets/js/collaborative-editor/types/history.ts
  - assets/js/workflow-diagram/util/from-workflow.tsx
  - assets/js/workflow-diagram/nodes/Node.tsx
  - test/lightning_web/controllers/workflow_controller_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/channels/run_channel_test.exs
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - assets/test/collaborative-editor/components/run-viewer/
  - assets/test/collaborative-editor/stores/createHistoryStore.test.ts
flows:
  - flow-manual-run-live-follow             # exit here: a run started from the panel is followed in this view (its S01, S02, S04, S05, S07)
  - flow-open-run-in-editor                 # exit here: run links land with run=<id> (its S01 to S05, S07)
  - flow-zero-persistence-runs              # Input and Output tabs show a raw null for wiped dataclips (its 6.1); no scenario here until fixed
  - flow-workflow-api-edit-conflict         # opening a run on a pinned version starts a view-only session that still holds the API edit lock (its 6.2)
  - flow-account-revocation-teardown
  - flow-legacy-editor-redirect   # added by lead (link lint)
---

## 1. Purpose

Workflow builders open a run inside the editor to see how it went next to the workflow that ran
it: which steps ran and how each ended, what data each step received and produced, and what the
job logged. They use it right after a manual run and when they arrive from a failed run elsewhere.
Without it they would bounce between the run page and the editor, and could not tell which step
of the graph to fix.

## 2. What it does

- Anyone on the project sees the loaded run's work order, id, status, duration, start time and who started it
- Anyone sees the run's steps in start order with their outcome and duration
- Anyone sees which steps were carried over from an earlier run
- Anyone picks a step to open its job's code and see that step's input, output and log lines
- Anyone sees what a queued or starting run is waiting for while no log has arrived
- Anyone is warned when the job open in the code editor did not run in the loaded run
- Anyone follows links from the run to its work order on History and to the full run page
- Anyone sees on the canvas which path the run took and where it failed
- Anyone is told when a run cannot be loaded
- A run from another project is not painted onto this workflow

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:136`, `:190-196` (`:access_project`, via
`run_channel.ex:72-76` and `workflow_controller.ex:165-171`); `policies/workflows.ex:14-22`
(`:access_read` for the editor that hosts the view, via shared-editor-session). Nothing in this
view checks a role beyond project access.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the run viewer and the canvas painting | yes | yes | yes | yes | no | yes, when support access is on |
| Load a run's steps and logs (run channel join) | yes | yes | yes | yes | no | yes, when support access is on |
| Select a step | yes | yes | yes | yes | no | yes, when support access is on |
| Read a step's input and output | yes | yes | yes | yes | no | yes, when support access is on (shared-dataclip-body-viewer) |
| Call `get_run_steps` | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The server preload and `request_run_steps` only return a run whose workflow is in the editor's project (`collaborate.ex:106-114`; `runs.ex:74-84`; `workflow_channel.ex:279-284`). The run channel instead checks the run's own project (`run_channel.ex:72-76`; flow-open-run-in-editor 6.1).
- `request_run_steps` does not check that the run belongs to the open workflow, only to the project (`workflow_channel.ex:280`) (6.2).
- Members of an MFA-required project who have not enrolled cannot join the run channel (`run_channel_test.exs:3100-3112`); shared-project-scope S05 keeps them out of the editor first.
- Losing project access closes the run channel (flow-manual-run-live-follow S08) and the editor (shared-editor-session S12, S13, S15).

## 4. What it touches

**Reads**
- Mount with `?run=`: `runs` joined to `work_orders` and `workflows` for the project, with `steps` (`collaborate.ex:110`; `runs.ex:74-84`)
- `request_run_steps`: `runs` with `steps`, `created_by`, `work_order.workflow.project` (`invocation.ex:1536-1546`)
- Run channel join: `runs` with `workflow.project` (`run_channel.ex:72-73`); `project_users` for `:access_project`
- `fetch:run`: `runs` with `created_by`, `starting_trigger`, `work_order`, and `steps` with `job`, `input_dataclip`, `output_dataclip` (`run_channel.ex:261-275`); steps ordered by `started_at` (`runs/run.ex:135-137`)
- `fetch:logs`: `log_lines` for the run (`run_channel.ex:277-293`)
- `get_run_steps`: `projects`, `runs` with `steps` and `work_order.workflow` (`workflow_controller.ex:162-173`)
- Dataclip bodies through shared-dataclip-body-viewer

**Writes**: none in the database
- Browser storage: panel sizes under `lightning.run-viewer-layout` (`RunViewerPanel.tsx:97`); the tab key is owned by workflow-editor-ide

**Immediate side effects** (in the same request)
- The run channel subscribes to `run_events:<run_id>` and the project's `Projects.Events` topic (`run_channel.ex:78-79`)
- Switching or closing a run leaves the previous `run:<id>` channel (`createHistoryStore.ts:1008-1049`)

**Deferred side effects** (later, elsewhere)
- Run, step and log events then flow into this view (flow-manual-run-live-follow)
- A `?run=` link that opens a pinned version or as-executed view starts a view-only session that holds the workflows API edit lock while open (flow-workflow-api-edit-conflict 6.2)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Workflow editor run viewer
  In order to see how a run went next to the workflow that ran it
  As anyone working in a project
  I want the editor to show a run's steps, data and logs and paint its path on the canvas

  @S01 @pending
  Scenario: The run viewer shows the run's summary and its steps
    # Value: a builder sees how the run went, who started it and which steps ran, next to the code that ran.
    Given run "R" of "Intake" was started manually by "amara@example.org"
    And steps "Fetch" then "Transform" ran in "R", "Fetch" for 3 seconds
    When I open the IDE on "Fetch" with "run=<R id>"
    Then the right panel shows a chip "Run <first 7 characters of R id>" and the tabs "Logs", "Input" and "Output"
    And the run details show "Work Order", "Run", "Status", "Duration", "Started" and "Started by" "amara@example.org"
    And "Run Steps" lists "Fetch" then "Transform", "Fetch" with a duration of "3 s"
    # FullScreenIDE.tsx:195-197, :554-562, :1234-1293; RunBadge.tsx:27-35; RunViewerPanel.tsx:92-115
    # RunTabPanel.tsx:59-125, :152-171; StepList.tsx:16-31; StepItem.tsx:20-30, :89-97
    # run_channel.ex:261-275; runs/run.ex:135-137; createHistoryStore.ts:362-386
    # StepList.test.tsx:91-124 (names render; hooks mocked); run_channel_test.exs:3138-3194 (fetch:run returns steps)

  @S02 @pending
  Scenario Outline: Run state reads in plain words
    # Value: people can tell queued work from work in progress without knowing internal state names.
    Given the loaded run is in state "<state>"
    Then the status pill reads "<label>"
    Examples:
      | state     | label     |
      | available | Enqueued  |
      | claimed   | Starting  |
      | started   | Running   |
      | failed    | Failed    |
    # StatePill.tsx:24-38; parity with shared-run-components S01 (its LiveView original, components.ex:110-138)
    # no test renders StatePill

  @S03 @pending
  Scenario: Step outcome and duration are shown per step
    # Value: people find the failing step at a glance, and can tell a timeout from a handled failure.
    Given the loaded run has a step that succeeded, one that failed, one killed with "TimeoutError" and one still running
    Then the steps show a green check, a red cross, a clock and a grey pending icon
    And the running step's duration counts up each second while the run has not started any step reads "Not started"
    # StepIcon.tsx:14-61; ElapsedIndicator.tsx:21-55; parity with shared-run-components S02 to S05
    # StepIcon.test.tsx:11-40 covers only the kill family

  @S04 @pending
  Scenario: Steps carried over from an earlier run are marked
    # Value: after a rerun from a step, people can tell which steps actually ran again.
    Given run "R2" was retried from "Transform" of run "R1"
    When I load "R2" in the run viewer
    Then "Fetch" is faded with a paperclip whose tooltip says it "was originally executed in a previous run"
    And "Transform" has no paperclip
    # StepItem.tsx:54-90 (step inserted before the run); parity with shared-run-components S06
    # no test covers the clone marker

  @S05 @pending
  Scenario: Picking a step opens its job and shows that step's data and logs
    # Value: from a failed step, people get to the code and the data that failed in one click.
    Given I have the IDE open on "Fetch" with run "R" loaded
    When I click step "Transform" in "Run Steps"
    Then the URL has "job=<Transform id>", "step=<Transform step id>" and still "run=<R id>" and "panel=editor"
    And the IDE shows the code of "Transform"
    And "Transform" is highlighted in the step list
    And the "Input" and "Output" tabs show "Transform"'s data and the "Logs" tab marks its lines (shared-log-viewer S05)
    # StepItem.tsx:32-52, :58-67; FullScreenIDE.tsx:564-578; createHistoryStore.ts:571-584; useHistory.ts:226-238
    # InputTabPanel.tsx:45-58; OutputTabPanel.tsx:45-58; LogTabPanel.tsx:241-244
    # StepList.test.tsx:161-184 asserts the URL update call only (useURLState mocked)

  @S06 @pending
  Scenario Outline: Input and output tabs say why there is no data
    # Value: people can tell data that has not arrived yet from data that was never saved.
    Given the loaded run is "<run state>"
    And the selected step "<step>"
    When I open the "<tab>" tab
    Then I see "<message>"
    Examples:
      | run state | step                   | tab    | message                                       |
      | started   | is not chosen          | Input  | Select a step to view input data              |
      | started   | has no output yet      | Output | Nothing yet                                   |
      | failed    | has no input dataclip  | Input  | No input state could be saved for this run.   |
      | failed    | has no output dataclip | Output | No output state could be saved for this run.  |
    # InputTabPanel.tsx:19-42; OutputTabPanel.tsx:19-42; types/history.ts:76-94
    # when the step has a dataclip id the body is shown by shared-dataclip-body-viewer (its S01, S02, S04)
    # a wiped dataclip still has an id and shows a raw null: flow-zero-persistence-runs 6.1
    # no test renders InputTabPanel or OutputTabPanel

  @S07 @pending
  Scenario Outline: The log says what a run is waiting for before it logs anything
    # Value: a builder can tell a run waiting for a worker from one installing adaptors, and knows nothing is stuck.
    Given the loaded run is in state "<state>" and has no log lines
    When I open the "Logs" tab
    Then "<first message>" is typed out
    And hints about that state cycle below it
    When the first log line arrives
    Then the waiting text disappears and the log is shown
    Examples:
      | state     | first message                                            |
      | available | Waiting for a worker to establish a secure claim...      |
      | claimed   | Creating an isolated runtime and installing adaptors...  |
    # LogTabPanel.tsx:12-48, :92-211, :287-306, :331-360
    # LogTabPanel.test.tsx:534-573, :595-630 (fake timers; channel and log store mocked, so it proves the overlay logic only)
    # a finished run with no lines: shared-log-viewer S06

  @S08 @pending
  Scenario: A job that did not run in the loaded run is flagged
    # Value: people don't read another job's logs and data as if they belonged to the job they are editing.
    Given run "R" has finished and did not run job "Notify"
    When I select "Notify" in the IDE with "R" loaded
    Then the run panel is faded and the run chip turns to its warning style
    And the chip's tooltip reads "Notify was not part of this run. Pick another job or deselect the run."
    But while "R" is still running the panel is not faded
    # RunViewerPanel.tsx:39-41, :95; FullScreenIDE.tsx:306-309, :1178-1182, :1239-1252; useHistory.ts:254-272
    # RunViewerPanel.test.tsx:325-385 (opacity class; useJobMatchesRun mocked, so the match rule itself is untested)

  @S09 @pending
  Scenario: The run links to its work order and to the full run page
    # Value: people can go from the editor to the run's history and its complete record without searching for it.
    Given run "R" of work order "W" is loaded with step "S" selected
    Then "Work Order" links to "/projects/<project id>/history?filters[workorder_id]=<W id>"
    And "Run" links to "/projects/<project id>/runs/<R id>?step=<S id>"
    # RunTabPanel.tsx:62-86; handoff only: history-work-orders reads filters[workorder_id], run-show reads step
    # no test renders RunTabPanel

  @S10 @pending
  Scenario: The canvas shows the path a run took
    # Value: people see at a glance which steps a run reached and where it failed, without opening anything.
    Given run "R" of "Intake" started at job "Fetch" by "amara@example.org", "Fetch" succeeded in 2 seconds and "Transform" failed
    And job "Notify" did not run
    When I open "Intake" on the canvas with "run=<R id>"
    Then "Fetch" shows a success badge and its duration, and "Transform" a failure badge with its error type as tooltip
    And "Notify" and the edge into it are faded
    And "Fetch" carries a start badge whose tooltip reads "Started by amara@example.org"
    And a job that ran three times shows a "3" badge
    # CollaborativeWorkflowDiagram.tsx:114, :171, :298-305; useHistory.ts:298-368; createHistoryStore.ts:781-802, :704-752
    # workflow_channel.ex:267-287, :2389-2415; runStepsTransformer.ts:38-90; from-workflow.tsx:56-80, :113-125, :153-165; Node.tsx:95-117, :176-235
    # workflow_channel_test.exs:5172-5225 (request_run_steps payload); createHistoryStore.test.ts:669-759 (subscribe fetches unless cached)
    # see 6.1 for "Started by unknown" on a URL-loaded run

  @S11 @pending
  Scenario: A run that cannot be loaded says why
    # Value: people learn a link is wrong or they lack access, instead of watching a skeleton forever.
    Given run id "X" does not exist
    When I open the IDE with "run=<X>"
    Then the run panel shows "Error loading run" and "Failed to connect: not_found"
    And for a run in a project I cannot access it shows "Failed to connect: unauthorized"
    # run_channel.ex:67-95; createHistoryStore.ts:996-1005; RunViewerPanel.tsx:63-80
    # run_channel_test.exs:3058-3095 (join refusals); RunViewerPanel.test.tsx:177-212 (error text and Dismiss; store mocked)

  @S12 @pending
  Scenario: A run from another project is not painted onto this workflow
    # Value: a run id pasted into a URL cannot reveal another project's run on this project's canvas.
    Given run "R" belongs to a project other than the editor's
    When I open "Intake" with "run=<R id>"
    Then no step data for "R" is preloaded into the page
    And the canvas paints nothing for "R"
    # collaborate.ex:106-114; workflow_channel.ex:279-284
    # collaborate_test.exs:221-245 (preload nil); workflow_channel_test.exs:5236-5255 ("unauthorized")
    # the IDE run panel still loads it through the run channel when the user can access that project: flow-open-run-in-editor 6.1

  @S13 @pending
  Scenario: A run started or opened elsewhere lands in the run viewer
    # Value: whichever way people reach a run, they arrive at the same view of it.
    When the flow "flow-manual-run-live-follow" starts run "R" from the IDE's run panel
    Then the run viewer follows "R" with the "Logs" tab
    When the flow "flow-open-run-in-editor" follows a step inspect link for "R"
    Then the run viewer shows "R" with that step's job open
    # handoff only: FullScreenIDE.tsx:207-225, :554-568; flow-manual-run-live-follow S02; flow-open-run-in-editor S02; workflow-editor-ide S19
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A `step` param present before the run has loaded is dropped: `selectStep` clears the selection when there is no active run, the effect does not re-run when the run arrives, and the run then auto-selects its first step. Inferred from code | `FullScreenIDE.tsx:564-568`; `createHistoryStore.ts:571-584`, `:372-375` | a step inspect link from the run page opens the right job, but the step list, Input, Output and log marking show the run's first step | fix |
| Clicking a later execution of a job that ran more than once is overridden: the job-sync effect rewrites `step` to the first step for that job, and re-runs on every run update. Inferred from code | `StepItem.tsx:40-51`; `FullScreenIDE.tsx:570-578`; `from-workflow.tsx:75-80` | the second or third execution of a looping job cannot be selected | fix |
| Switching from one run to another keeps the old `selectedStepId`; the new run does not auto-select because a selection already exists | `createHistoryStore.ts:1008-1024`, `:372-375`; `useHistory.ts:226-238` | after picking another run, Input and Output read "Select a step to view input data" until a step is clicked, unless the open job ran in the new run | fix |
| The server preload sets `created_by_email: nil`, and a cached run is never refetched unless it finishes while subscribed | `collaborate.ex:118-129`; `createHistoryStore.ts:793-801`, `:344-355`; `runStepsTransformer.ts:51`, `:61`; `from-workflow.tsx:119-120`; `Node.tsx:207` | opening a finished manual run by URL shows "Started by unknown" on the start badge | fix |
| A `request_run_steps` failure is written to the history list's error and loading state | `createHistoryStore.ts:715-748`; `CollaborativeWorkflowDiagram.tsx:318-323`; `MiniHistory.tsx:696-716` | "Loading history..." while a run's steps load, then "Failed to load history" with the steps error (for example "unauthorized"), and a retry that reloads history, not the steps | fix |
| `fetch:run` preloads each step's `job`, but `Step`'s JSON encoder drops it, so step names always come from the workflow version open in the editor | `run_channel.ex:264-272`; `invocation/step.ex:37-49`; `StepItem.tsx:20-30`; `run_channel_test.exs:3178-3192` (asserts the preload through the test serializer, which does not encode) | a step whose job is not in the open version reads "Unknown Job"; a renamed job shows its new name | fix |
| The canvas node tooltip falls back to "Step completed successfully" for any finished step without an error type, and `kill`, `cancel` and unknown exit reasons are painted as failures | `Node.tsx:176-185`; `runStepsTransformer.ts:72-90` | a cancelled step with no error type shows a failure badge whose tooltip says it completed successfully | fix |
| Waiting hints contain typos: "claimed the order in which", "in parallel once", "how many runs are enqueue" | `LogTabPanel.tsx:25-28` | broken sentences in the waiting text | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The steps and logs panel exists only in the IDE; on the canvas a run is only painted onto nodes and edges, and the list of runs is MiniHistory | `FullScreenIDE.tsx:1285-1293`; `CollaborativeWorkflowDiagram.tsx:298-324` | decide |
| "Dismiss" on the load error clears it and leaves "No run data available" with no retry; only closing the chip or reloading tries again | `RunViewerPanel.tsx:64-89`; `createHistoryStore.ts:564-569` | decide |
| The run chip shows 7 characters of the id, the details 8 | `RunBadge.tsx:33`; `RunTabPanel.tsx:20-22` | decide |
| "Started" uses the browser's `toLocaleString`, not the app's local datetime component | `RunTabPanel.tsx:105-112` | decide |
| "Started by" for a trigger run reads the raw type, "webhook trigger" or "cron trigger"; "Unknown" is unreachable because the row only renders when one of the two is set | `RunTabPanel.tsx:114-124` | preserve |
| Labels are Title Case ("Work Order", "Run Steps", "Run Metadata") | `RunTabPanel.tsx:57`, `:63`, `:150`, `:155` | decide |
| Durations under a second read in milliseconds ("532 ms"); above a minute they round down to whole minutes | `ElapsedIndicator.tsx:9-19` | preserve |
| A node that ran several times keeps a failure over a later success, but a crash is overwritten by a later success | `from-workflow.tsx:58-72` | decide |
| The "ran N times" tooltip points to "the Inspector or History page"; whether the inspector shows other executions was not checked | `Node.tsx:187-199` | decide |
| `request_run_steps` accepts any run in the project, not only runs of the open workflow; another workflow's run paints nothing (no job ids match) but every node fades | `workflow_channel.ex:280`; `from-workflow.tsx:56`, `Node.tsx:101-117` | decide |
| A URL-loaded run is preloaded into the page so the canvas paints before the channel connects (also flow-open-run-in-editor 6.2) | `collaborate.ex:94-142`; `StoreProvider.tsx:122-131`; `createHistoryStore.ts:170-180` | preserve |
| Step events update the canvas cache incrementally; the full step list is refetched only when the run reaches a final state | `createHistoryStore.ts:436-521`, `:344-355` | preserve |
| The run steps cache is never cleared during a page's life | `createHistoryStore.ts:71-74`, `:830-839` | preserve |
| The run viewer has its own error boundary with "Something went wrong" and "Try Again" | `RunViewerErrorBoundary.tsx:10-33`; `FullScreenIDE.tsx:1286` | preserve |
| The collapsed panel's expand button wraps the run chip, whose close control sits inside that button | `FullScreenIDE.tsx:1165-1183` | decide |
| StatePill gives "cancelled" grey text on a grey background (ported as is) | `StatePill.tsx:18` | decide |
| `LogTabPanel` finds the run channel by scanning the socket's channel list for the topic | `LogTabPanel.tsx:260-268` | preserve |
| `StepIcon` logs a console warning for unknown kill error types | `StepIcon.tsx:44-47`; `StepIcon.test.tsx:28-40` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `GET /projects/:project_id/runs/:run_id/steps` (`get_run_steps`) | `router.ex:219-221`; `workflow_controller.ex:145-198` | no client caller; its doc says it decides retry availability, which `useRunRetry` now reads from the run channel. Tests at `workflow_controller_test.exs:289-400`; the "requires project access" test actually exercises the project mismatch branch (`:385-399`) |
| `RunViewerPanel` props `onTabChange` and `onClearFollowRun` | `RunViewerPanel.tsx:23-34` | accepted, never used |
| "No run data available" and RunTabPanel's "No run data" | `RunViewerPanel.tsx:82-89`; `RunTabPanel.tsx:34-36` | reached only after "Dismiss" (6.2) or with no project in the session context |
| `isLoading && !run` skeleton after the first load | `RunViewerPanel.tsx:58-61` | `activeRun` is kept across a switch, so the skeleton shows only for the first run of a page |
| History store test helpers in the production store | `createHistoryStore.ts:1051-1116` | test only |
| LogTabPanel "default" waiting messages ("Nothing yet...", "Hang tight...") for a `started` run with no logs | `LogTabPanel.tsx:36-41` | reachable; listed because `LogTabPanel.test.tsx:575-593` reaches them only with no run, which the panel never renders |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `fetch:run` loads every step's input and output dataclip, bodies included, then the encoder drops them | `run_channel.ex:264-272`; `invocation/step.ex:37-49` | possibly, slow load on runs with large payloads | fix |
| Each ElapsedIndicator ticks every second while unfinished, one per step plus the run | `ElapsedIndicator.tsx:45-49` | no | preserve |
| Waiting overlay types at 30 ms per character, pauses 2 s at the end and 0.5 s before the next hint | `LogTabPanel.tsx:12-14` | yes | preserve |
| Run panel sizes saved per browser under `lightning.run-viewer-layout` | `RunViewerPanel.tsx:97` | yes | preserve |

### 6.5 Things seen but not understood

- Most run-viewer Vitest tests mock every hook and child, so they prove rendering branches, not behaviour: `RunViewerPanel.test.tsx` passes `activeTab="run"`, which is not a valid tab, and its "renders Run tab content" test passes because `RunTabPanel` always renders (`RunViewerPanel.test.tsx:216-231`); `LogTabPanel.test.tsx:165-198`, `:266-314` only assert a container class exists. No test renders RunTabPanel, InputTabPanel, OutputTabPanel or StatePill. No Playwright spec opens the run viewer; `job-step-sync.spec.ts` asserts only the `step` param (workflow-editor-ide 6.5).
- Whether `?run=` on a pinned version (`v=`) paints from the pinned version's job ids or the latest was not traced beyond `useRunSteps` using the open document (`useHistory.ts:298-368`).
- flow-manual-run-live-follow open question 4 asks who owns the canvas half; this file takes the node and edge painting (S10) and leaves MiniHistory with workflow-editor-versions-and-promote.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the steps and logs panel be available on the canvas, not only in the IDE (6.2)?
- Should step deep links and repeated executions be selectable as linked (6.1 rows 1 and 2)?
- Should step names come from the version that ran rather than the version open (6.1)?
- Should the load error offer a retry (6.2)?
- Should the editor's run viewer show "not retained" for wiped dataclips like run-show (flow-zero-persistence-runs 6.1)?
- Should `get_run_steps` be removed or kept as an API (6.3)?
- Should the React ports (StatePill, StepIcon, ElapsedIndicator, clone marker) be held to shared-run-components' scenarios (see Proposed shared)?

## Proposed flows

none. Referenced: flow-manual-run-live-follow (exit here; S13), flow-open-run-in-editor (exit here; S13, S12 note), flow-zero-persistence-runs (Input and Output null, its 6.1), flow-workflow-api-edit-conflict (pinned run views hold the lock, its 6.2).

## Proposed shared

- Extend shared-run-components (not a new id) to cover the React ports this view renders: `StatePill`, `StepIcon`, `ElapsedIndicator` and the clone marker in `StepItem`, which copy `run_live/components.ex` and `hooks/ElapsedIndicator.ts`. Surfaces: run-show, history-work-orders, workflow-editor-run-viewer. Until then S02 to S04 here restate its S01 to S06 for the editor.

## Lead resolution (batch 6)

- shared-run-components is being extended to cover the React ports (StatePill, StepIcon, ElapsedIndicator, clone marker); inherit it.
