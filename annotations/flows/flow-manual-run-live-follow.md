---
id: flow-manual-run-live-follow
type: flow
title: Following a manual run as it executes
status: not-started
owner:

trigger:
  entry: workflow-editor-manual-run
  exit: workflow-editor-run-viewer
  surfaces:
    - workflow-editor-manual-run             # "Run From Here" in the panel, standalone over the canvas or embedded in the IDE (ManualRunPanel.tsx:683-692; FullScreenIDE.tsx:1312-1334)
    - controller:workflow-create-run         # POST /projects/:project_id/workflows/:workflow_id/runs (router.ex:215-217; workflow_controller.ex:26-66)
    - pubsub:project:<project_id>            # RunCreated, WorkOrderCreated, then RunUpdated (workorders/events.ex:24-49); reaches the editor as "history_updated" on the workflow channel (workflow_channel.ex:79, :980-1073)
    - controller:worker-channel              # "claim" on worker:queue (worker_channel.ex:44-49); manual runs sit in queue "manual"
    - controller:run-channel                 # worker side "run:start", "step:start", "step:complete", "run:log", "run:batch_logs", "run:complete"; browser side join, "fetch:run", "fetch:logs" and the forwarders (run_channel.ex:67-95, :112-258, :261-323)
    - pubsub:run_events:<run_id>             # Lightning.Runs.Events (runs/events.ex:29-68)
    - workflow-editor-run-viewer             # the editor following run=<id>: canvas step painting and the run history list, or the IDE's run viewer panel
    - workflow-editor-versions-and-promote   # added by lead
  reachable_when:
    - the editor is on an existing workflow and the person can run it (shared-run-retry-controls S10; workflow_controller.ex:68-93)
    - the editor's workflow channel is connected; following waits for it (useHistory.ts:155-162, :325-334)
    - the run belongs to a project the person can access, for the run channel join (run_channel.ex:72-76)

inherits:
  - shared-project-scope            # who can open the editor; membership and support access teardown of the LiveView
  - shared-editor-session           # workflow channel, connection state, save before run
  - shared-run-retry-controls       # "Processing" state, toasts, the 30 s confirmation timeout (S13 there)
  - shared-log-viewer               # how log lines are stored, filtered and ordered once they reach LogTabPanel

url_params:
  - name: run
    set_by: this flow after a successful create_run (useRunRetry.ts:311; FullScreenIDE.tsx:207-210)
    effect: the run the editor follows; joins run:<id> and paints its steps (CollaborativeWorkflowDiagram.tsx:77-78, :114, :171; FullScreenIDE.tsx:205)
  - name: panel
    set_by: workflow-editor-manual-run
    effect: removed after a successful run from the standalone panel, so the panel does not reopen (ManualRunPanel.tsx:496-501)

config_variants:
  default: {}                       # read under this variant; experimental-features content lock and as_run rewriting are owned by flow-open-run-in-editor

inventory:
  routes: []
  events:
    - WorkflowChannel request_history, request_run_steps (workflow_channel.ex:252-286)                      # owned by shared-editor-session; listed as the hops that load the new run
    - WorkflowChannel handle_info WorkOrderCreated, WorkOrderUpdated, RunCreated, RunUpdated (workflow_channel.ex:980-1073)
    - RunChannel browser join, fetch:run, fetch:logs (run_channel.ex:67-95, :261-293)
    - RunChannel handle_info RunUpdated, StepStarted, StepCompleted, LogAppended (run_channel.ex:296-318)
    - RunChannel handle_info ProjectDeletionScheduled, ProjectUserRemoved, SupportAccessUpdated (run_channel.ex:333-345)
  js_hooks:
    - HistoryStore _viewRun, _switchingFromRun, handleRunReceived, handleRunUpdated, handleStepUpdate, handleHistoryUpdated (stores/createHistoryStore.ts:277-521, :897-1024)
    - hooks useFollowRun, useRunSteps (hooks/useHistory.ts:150-171, :298-368)
    - LogTabPanel run channel subscription (components/run-viewer/LogTabPanel.tsx:247-301)
  policies:
    - Lightning.Policies.ProjectUsers :edit_workflow, :run_workflow    # workflow_controller.ex:68-93; owned by workflow-editor-manual-run S20
    - Lightning.Policies.ProjectUsers :access_project                  # run channel join and teardown (run_channel.ex:76, :363-370)
  workers: []                       # runs go to the run queue for external workers (fifo_run_queue.ex:14), not Oban
  api_endpoints:
    - post /projects/:project_id/workflows/:workflow_id/runs  WorkflowController :create_run
    - channel worker:queue "claim"
    - channel run:<id> "run:start", "step:start", "step:complete", "run:log", "run:batch_logs", "run:complete"
  emails: []                        # run:complete on a non-success run starts flow-failure-alert-email; owned there
  config: []
  not_reachable_here:
    - post /projects/:project_id/runs/:run_id/retry WorkflowController :retry_run; a retry follows the same path from run=<id> onward but its entry is owned by shared-run-retry-controls (6.5)
    - RunChannel push "dataclip:updated" (run_channel.ex:320-323); no editor listener (6.3), owned by flow-zero-persistence-runs
    - the "all_events" copy of RunCreated (workorders/events.ex:41), consumed by WorkListener; owned by flow-history-live-updates
    - RunChannel "fetch:plan", "fetch:credential", "fetch:dataclip" (run_channel.ex:102-191); worker-only, no editor event follows

related:
  - lib/lightning_web/controllers/workflow_controller.ex
  - lib/lightning_web/live/workflow_live/helpers.ex
  - lib/lightning/work_orders.ex
  - lib/lightning/workorders/events.ex
  - lib/lightning/runs.ex
  - lib/lightning/runs/events.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - assets/js/collaborative-editor/hooks/useRunRetry.ts
  - assets/js/collaborative-editor/hooks/useHistory.ts
  - assets/js/collaborative-editor/stores/createHistoryStore.ts
  - assets/js/collaborative-editor/components/ManualRunPanel.tsx
  - assets/js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.tsx
  - assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
  - assets/js/collaborative-editor/components/run-viewer/RunViewerPanel.tsx
  - assets/js/collaborative-editor/components/run-viewer/LogTabPanel.tsx
  - test/lightning_web/channels/run_channel_test.exs
  - test/lightning_web/controllers/workflow_controller_test.exs
  - assets/test/collaborative-editor/stores/createHistoryStore.test.ts
  - assets/test/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.realtime.test.tsx
flows:
  - flow-run-show-live-updates      # the same worker hops and run topic, received by run-show instead of the editor
  - flow-history-live-updates       # the same project topic events, received by an open History page
  - flow-failure-alert-email        # started by the run:complete hop when the run does not succeed
  - flow-open-run-in-editor         # the other way into workflow-editor-run-viewer; owns the run=<id> link shape and cross-project refusal
---

## 1. Purpose

Workflow builders start manual runs to find out whether the step they just changed works. Once
they click run, the editor has to pick up that exact run and show it moving: the worker claiming
it, each step starting and finishing, the logs, and how it ended. Without this they would have to
go to History or the run page and reload, losing the code they were editing, and they could not
tell a slow queue from a failing step.

## 2. What it does

1. An editor clicks "Run From Here" in the run panel, either over the canvas or inside the code editor, and the run is created and queued for a worker.
2. The editor switches to following that run straight away.
   - Over the canvas, the panel closes and the new run is selected at the top of the run history list.
   - In the code editor, the right-hand panel switches to the run viewer.
   - A custom input typed into the panel is saved, so it becomes the input to retry with.
3. A worker picks the run up, runs each step and sends its logs.
4. The editor shows the progress live, without a reload, until the run finishes.
   - The canvas marks each step as it runs and how it ended; the code editor shows log lines as they arrive.
   - Anything that happened before the editor connected is caught up, so a fast run never looks stuck in the queue.
   - When the run ends, the history list shows the outcome, the run controls free up, and a failed run sets off the failure alert email.
5. Other people stay on their own run.
   - Collaborators with the workflow open see the new run appear in their history list, but are not moved to it.
   - Another run's steps and logs never show on the run you're following.
   - Someone removed from the project stops receiving the run's data at once, even mid-run.

**Straightforwardness: 3 of 5.** Watching your own run is easy to picture, but the updates come in over two separate routes and several of the rough edges only show up when the timing is unlucky.

### Most surprising behaviours

- **(2)** The live connection for the run seems likely to break every time the run changes state, so the status and the "Processing" button lag by a second or more and some step updates go missing until the run finishes. This is read from the code, not seen in a browser. (6.1)
- **(3)** If you lose access to the project mid-run, the updates stop but the editor says nothing; the run viewer just freezes on its last state, as if the run had stalled. (6.1, S08)
- **(3)** Right after starting a second run, a step from the new run can briefly show under the old one, and the run controls read the old run's state. (6.1)
- **(3)** Over the canvas the button stops saying "Processing" as soon as the request comes back, but in the code editor it waits until the run actually arrives, or 30 seconds. Same action, two different signals. (6.2)
- **(4)** In the code editor no step is selected for a freshly started run, so the log shows every step's lines together. (6.2)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:39-49`, `:134-185` via `workflow_controller.ex:68-93`
(start) and `run_channel.ex:72-76` (follow). Worker hops need a worker token and a run token, not a role.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start a run that the editor then follows | no | yes | yes | yes | no | yes, when support access is on |
| Receive the followed run's live updates | yes (runs reached through flow-open-run-in-editor) | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The workflow must belong to the project in the URL and not be deleted (`workflow_controller.ex:87-92`; `work_orders.ex:129-135`); refusals are owned by workflow-editor-manual-run S19 to S22.
- The run channel admits a browser only with `:access_project` on the run's own project (`run_channel.ex:72-76`), and stops when that access is lost (`run_channel.ex:333-345`, `:363-370`).
- Run steps are loaded through the workflow channel only for a run in the channel's project (`workflow_channel.ex:279-283`).

## 4. What it touches

**Hop 1, create_run** (`workflow_controller.ex:26-66`, `:130-143`; `helpers.ex:46-64`)
- Reads: `projects`, `workflows`, `jobs`, `triggers`, `workflow_edges` (`workflow_controller.ex:30-35`); latest `workflow_snapshots` (`work_orders.ex:207-212`)
- Writes, in one transaction: `dataclips` insert unless an existing input was chosen, `work_orders` insert with priority `immediate` and queue `manual`, `runs` insert (`work_orders.ex:127-149`, `:176-190`; `fifo_run_queue.ex:14`)
- Immediate: `RunCreated` then `WorkOrderCreated` on `project:<project_id>`, sent before the outer transaction commits (`work_orders.ex:151-157`; `helpers.ex:47`); 201 with `run_id` (`workflow_controller.ex:56-64`)

**Hop 2, the editor switches to the run** (`useRunRetry.ts:289-313`; `ManualRunPanel.tsx:496-501`, `:687-689`; `FullScreenIDE.tsx:207-225`)
- Toast "Run started"; `get_limits` pushed (owned by shared-run-retry-controls)
- `run=<id>` in the URL; the standalone panel closes and drops `panel`; the IDE switches its right panel to the run viewer
- Reads: `run:<id>` join reads `runs` with `workflow` and `project` (`run_channel.ex:72-76`), then `fetch:run` reads the run with `created_by`, `starting_trigger`, `work_order` and `steps` (`run_channel.ex:261-275`); `request_run_steps` reads the run with steps on the workflow channel (`workflow_channel.ex:267-286`); `request_history` if the history list was never loaded (`CollaborativeWorkflowDiagram.tsx:234-256`); in the IDE, `fetch:logs` reads `log_lines` (`run_channel.ex:277-293`; `LogTabPanel.tsx:270-285`)
- Immediate: the run channel subscribes to `run_events:<run_id>` and `Projects.Events` (`run_channel.ex:78-79`)

**Hops 3 and 4, worker claim and execution** (writes and broadcasts owned by flow-run-show-live-updates section 4)
- Claim, `run:start`, `run:complete`: `RunUpdated` on `run_events:<run_id>` and `project:<project_id>` (`runs.ex:269-289`)
- `step:start`, `step:complete`: `StepStarted`, `StepCompleted` on the run topic only (`runs/events.ex:29-41`)
- `run:log`, `run:batch_logs`: one `LogAppended` per line (`runs.ex:308-311`, `:336-338`)

**Hop 5, back into the editor**
- Run channel pushes `run:updated`, `step:started`, `step:completed`, `logs` (`run_channel.ex:296-318`); the store merges them into the followed run and its step cache (`createHistoryStore.ts:391-521`)
- Workflow channel pushes `history_updated` for each project topic event on this workflow (`workflow_channel.ex:980-1073`); the store updates the history list and refetches the run's steps once the run is final (`createHistoryStore.ts:277-356`)
- Writes: none

**Deferred side effects**
- A non-success `run:complete` evaluates failure alerts in the run channel process (`run_channel.ex:127-132`; `failure_alerter.ex:17-37`); owned by flow-failure-alert-email

**External, non-transactional effects**
- PubSub broadcasts are cluster-wide and are not rolled back with the transaction that sent them (6.2)
- The job code the worker runs may call external systems

**Depends on config**
- none

**Product limits**
- none beyond workflow-editor-manual-run's (input size, run limits)

## 5. Scenarios

```gherkin
Feature: Following a manual run as it executes
  In order to see whether the step I just changed works
  As a workflow builder
  I want the editor to follow the run I start until it finishes

  @S01 @pending
  Scenario: A run started from the panel is followed on the canvas
    # Value: the builder sees whether the run they just started is working, without leaving the editor or reloading.
    Given I am an editor on project "Malawi HIV" with workflow "Intake" open
    And the run panel is open for step "Fetch" over the canvas
    When I click "Run From Here"
    Then a work order and run "R" are created starting at "Fetch"
    And the panel closes and the URL has "run=<R id>" and no "panel"
    And the run history list shows R's work order at the top with "R" selected
    When the worker starts and then completes "Fetch"
    Then eventually the "Fetch" node shows it ran and how it ended, without a reload
    # ManualRunPanel.tsx:496-501, :687-689; useRunRetry.ts:289-313; workflow_controller.ex:26-66; work_orders.ex:127-157
    # CollaborativeWorkflowDiagram.tsx:77-78, :114, :171, :266-317; useHistory.ts:150-171, :298-368; WorkflowDiagram.tsx:396-404
    # createHistoryStore.ts:277-301, :897-1006, :436-521; run_channel.ex:67-95, :303-313; workflow_channel.ex:980-1000
    # handoff only tested: workflow-editor-manual-run S01; createHistoryStore.test.ts:469-488 (created event), :1206-1275 (step event fills the cache)

  @S02 @pending
  Scenario: A run started in the code editor opens its logs there
    # Value: the builder reads what the job prints while it runs, next to the code that printed it.
    Given I have the IDE open on job "Fetch" with the embedded run panel
    When I click "Run From Here"
    Then the right panel switches to the run viewer for the new run "R"
    And the URL has "run=<R id>"
    When the worker logs "Fetched 12 patients" for "R"
    Then eventually the "Log" tab shows "Fetched 12 patients"
    # FullScreenIDE.tsx:196-225, :1285-1293, :1325; useRunRetry.ts:304-308; RunViewerPanel.tsx:92-115
    # LogTabPanel.tsx:247-301; run_channel.ex:277-293, :315-318; runs.ex:308-311
    # run_channel_test.exs:3365-3377 (LogAppended is forwarded as "logs")

  @S03 @pending
  Scenario: A custom input becomes the input to retry with
    # Value: after fixing the code, the builder retries with exactly the payload they typed, without retyping it.
    Given I have the IDE open on job "Fetch" with the embedded run panel on the "Custom" tab
    When I run with {"patient": "123"}
    Then the run viewer follows the new run
    And the panel's input is the saved input holding {"patient": "123"}, on the existing inputs tab
    And once the run's "Fetch" step has that input, the run button offers "Retry"
    # workflow_controller.ex:53-63; FullScreenIDE.tsx:213-218; useRunRetry.ts:158-171, :204-213; shared-run-retry-controls S04

  @S04 @pending
  Scenario: Progress made before the editor connects is not lost
    # Value: a run a worker picked up instantly never shows as still queued or missing its first step.
    Given a worker claims and starts run "R" before my editor has joined "run:<R id>"
    When the editor joins
    Then the run viewer shows "R" as started with the steps it has already begun
    And later step and state changes are applied on top
    # createHistoryStore.ts:948-976 (fetch:run after join); run_channel.ex:78, :261-275 (subscribe before the read, in one process)
    # workflow_channel.ex:267-286 (request_run_steps after run=<id> is set)

  @S05 @pending
  Scenario: The followed run finishing shows its outcome and frees the controls
    # Value: the builder learns how the run ended and can run again straight away.
    Given the editor is following run "R" while it is running
    When the worker completes "R" with state "failed"
    Then eventually the run history list shows "R" as failed
    And the canvas shows each step's final outcome
    And the run controls stop showing "Processing"
    And the flow "flow-failure-alert-email" starts for "R"
    # run_channel.ex:122-142; runs.ex:269-289; workflow_channel.ex:1048-1073; createHistoryStore.ts:304-355 (final-state refetch), :391-409
    # useRunRetry.ts:173-174; shared-run-retry-controls S13
    # createHistoryStore.test.ts:873-942 (final run_updated refetches subscribed steps)

  @S06 @pending
  Scenario: A collaborator sees the new run without being moved to it
    # Value: one builder's test run never pulls a colleague's canvas onto a run they didn't choose.
    Given "amara@example.org" has "Intake" open, following run "Q"
    When I start run "R" from the panel
    Then eventually her run history list shows R's work order
    And her editor still follows "Q" and her URL is unchanged
    # workflow_channel.ex:79, :980-1000; createHistoryStore.ts:277-301; CollaborativeWorkflowDiagram.tsx:77-78 (followed run comes from her own URL)

  @S07 @pending
  Scenario: Another run's progress never shows on the followed run
    # Value: the steps and logs the builder reads are always from the run they started, never mixed with another.
    Given the editor is following run "R"
    When a worker starts a step and logs a line for run "S" of the same workflow
    Then the run viewer and the canvas still show only R's steps and logs
    And "S" appears only as its own entry in the run history list
    # runs/events.ex:64-68 (topic per run); run_channel.ex:78; createHistoryStore.ts:398 (run:updated checked by id), :460-463

  @S08 @pending
  Scenario: Losing access stops the run's data reaching the editor
    # Value: someone removed from a project stops receiving its run data at once, even mid-run.
    Given I am an editor following run "R" of "Malawi HIV"
    When an admin removes me from "Malawi HIV"
    Then the run channel for "R" is closed
    And log lines written for "R" afterwards are not sent to me
    And removing a different member, or me from another project, leaves it open
    # run_channel.ex:333-370
    # run_channel_test.exs:3409-3480 (removal, other member, other project), :3482-3546 (support access withdrawn, project scheduled for deletion)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `RunUpdated` carries a run preloaded without `work_order`, and the run channel pushes it with only `:steps` added; `Lightning.Run`'s JSON encoder includes `work_order`, and Ecto's encoder for an unloaded association raises. Phoenix encodes a push in the channel process, so every claim, start and completion would crash the editor's run channel. The forwarding test uses the channel test serializer, which does not encode | `runs.ex:273-286`; `run_channel.ex:296-301`; `runs/run.ex:23-42`; `types/history.ts:119-141`; `run_channel_test.exs:3294-3306` | the run's state and the "Processing" button lag by the client's rejoin delay (1 s, then longer), which recovers through `fetch:run`; step events sent while it rejoins are missing until the final-state refetch. Inferred from code, not run | fix |
| The run channel has no close or error handler on the client; when the server stops it after access is lost, nothing is cleared or shown | `createHistoryStore.ts:936-1005`; `run_channel.ex:339-341` | the run viewer keeps the last state it had, as if the run stopped progressing. Whether the editor's own teardown (shared-project-scope, shared-editor-session) covers it first was not traced | fix |
| Following a new run keeps the previous run as the active run until `fetch:run` replies, and step events are applied to the active run without checking which run they belong to | `createHistoryStore.ts:1008-1024`, `:436-457` | for a moment after starting a second run, a step of the new run can be listed under the old one, and the controls read the old run's state. Inferred from code | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `RunCreated` and `WorkOrderCreated` are broadcast inside `run_workflow`'s transaction, before commit; the workflow channel's `RunCreated` handler re-reads the work order and may find nothing, and the client drops a `run_created` for a work order it doesn't list. The new run still arrives inside `WorkOrderCreated`'s work order. Same transaction issue as flow-history-live-updates 6.1 | `helpers.ex:47`; `work_orders.ex:151-157`; `workflow_channel.ex:1023-1046`, `:2360-2370`; `createHistoryStore.ts:309-316` | preserve |
| The canvas gets a run's final step data by refetching when the project topic reports the run final, not from the run channel | `createHistoryStore.ts:339-355`; `workflow_channel.ex:1048-1073` | preserve |
| On the canvas the panel has no `onRunSubmitted`, so it stops "Processing" as soon as the request returns; in the IDE it waits for the run channel to deliver the new run, or 30 s | `useRunRetry.ts:303-313`, `:176-202`; `WorkflowEditor.tsx:357-367`; `FullScreenIDE.tsx:1325` | decide |
| A run followed from creation has no step selected (first-step auto-select only applies to steps present at load), so the IDE log shows every step's lines | `createHistoryStore.ts:372-375`, `:436-457`; `LogTabPanel.tsx:241-244` | decide |
| Following waits for the workflow channel, not the run channel's socket; a run started while the editor is reconnecting is followed once it reconnects | `useHistory.ts:155-162`; `createHistoryStore.ts:913-917` | preserve |
| The run channel authorizes on the run's own project, not the editor's (owned by flow-open-run-in-editor 6.1) | `run_channel.ex:72-76` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `dataclip:updated` push to the editor | `run_channel.ex:320-323` | no editor code listens for it; owned by flow-zero-persistence-runs |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The IDE log subscription depends on the whole run object, so every run or step event refetches the full log with `fetch:logs` and re-registers the listener; duplicates are dropped by id in the log store | `LogTabPanel.tsx:247-301`; `run_channel.ex:277-293` | possibly, on long logs | decide |
| A batch of N log lines is pushed as N `logs` messages | `runs.ex:336-338`; `run_channel.ex:315-318` | no | preserve |
| `fetch:logs` loads every stored line in one transaction | `run_channel.ex:281-290` | possibly, on long logs | decide |
| Each `history_updated` push re-reads release version numbers for the workflow | `workflow_channel.ex:987-990`, `:1028-1031`, `:1054-1057` | no | preserve |

### 6.5 Things seen but not understood

- `CollaborativeWorkflowDiagram.realtime.test.tsx:371-423` expects a run steps refetch on a `started` update, but the store only refetches on a final state (`createHistoryStore.ts:348-352`); the test may stub the store. Not resolved. (decide)
- No test follows a run from create_run through to the editor; the controller, channel and store are tested separately.
- A retry reaches the same `run=<id>` path but through `retry_run`, which is not in the lead's surfaces; it is treated as covered here from the URL onward. (preserve)
- On the canvas, the "run viewer" is the step painting and the run history list rendered by `CollaborativeWorkflowDiagram`; the panel with steps and logs exists only in the IDE (`RunViewerPanel` is rendered only by `FullScreenIDE.tsx:1287`). Which view annotation owns the canvas half is open.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. Should the run channel push a run that encodes, and should a test go through the real serializer (6.1)?
2. Should the editor show something when the run channel is closed by the server (6.1)?
3. Should the canvas panel stay "Processing" until the run channel confirms the run, as the IDE does (6.2)?
4. Does the canvas half of the run viewer belong to workflow-editor-run-viewer or workflow-editor-canvas (6.5)?

## Proposed flows

none (referenced: flow-run-show-live-updates, flow-history-live-updates, flow-failure-alert-email, flow-open-run-in-editor)

## Proposed shared

none (referenced: shared-project-scope, shared-editor-session, shared-run-retry-controls, shared-log-viewer)

## Summary

- Scenarios: 8 (S01 to S08), all `@pending`, default variant.
- Section 6: 6.1 has 3, 6.2 has 6, 6.3 has 1, 6.4 has 4, 6.5 has 4.
- Flows: none proposed; references flow-run-show-live-updates, flow-history-live-updates, flow-failure-alert-email, flow-open-run-in-editor.
- Shared: none proposed; inherits shared-project-scope, shared-editor-session, shared-run-retry-controls, shared-log-viewer.
- Unsure: the `run:updated` encoding crash is inferred from code and Ecto's encoder, not run; workflow-editor-ide and workflow-editor-canvas host halves of this flow but are not in the lead's surfaces.
