---
id: shared-run-retry-controls
type: shared
title: Run and retry controls
status: not-started
owner:

trigger:
  old_route: any workflow editor surface that renders NewRunButton or RunRetryButton, or calls useRunRetry, useRunRetryShortcuts, useSaveBeforeRun or useCanRun (all under /projects/:project_id/w/:id, WorkflowLive.Collaborate)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host surface passed the project scope gate (shared-project-scope; collaborate.ex:25)
    - the editor session has delivered permissions and limits in the session context (shared-editor-session; workflow_channel.ex:1381, :1516-1541)
    - header Run shows only when the workflow has a trigger, or, with experimental features, when a finished run is loaded (Header.tsx:861-881)
    - panel and IDE controls render only while their host panel is in a run state (ManualRunPanel.tsx:680-703; FullScreenIDE.tsx:924-970)

inherits:
  - shared-authenticated-session    # both run endpoints sit behind :require_authenticated_user (router.ex:215-225)
  - shared-project-scope            # who can open the editor at all; MFA and scheduled-deletion refusals on the endpoints
  - shared-editor-session           # sync state, can_edit_workflow / can_run_workflow, limits delivery, saveWorkflow, content lock, KeyboardProvider

url_params:
  - name: run
    set_by: these controls after a run or retry (useRunRetry.ts:311, :406-416; Header.tsx:404, :463-473; FullScreenIDE.tsx:210), workflow-editor-run-viewer, flow-open-run-in-editor
    effect: the followed run; decides whether the control offers Retry (useRunRetry.ts:151, :204-213; Header.tsx:292-297)
  - name: release / v / as_run / step
    set_by: workflow-editor-versions-and-promote, flow-open-run-in-editor
    effect: a pinned view; refuses a fresh run, allows a retry with experimental features (useWorkflow.tsx:992-994); cleared by a retry with experimental features (useRunRetry.ts:406-416; Header.tsx:463-473)

config_variants:
  default: {}                                                              # read under this variant unless tagged
  experimental-features: { user.preferences.experimental_features: true }  # retry from a pinned view; live content lock skips the save; header Retry without a trigger
  run-limit-reached: { Lightning.Extensions.UsageLimiter: "limit_action(%{type: :new_run}) returns {:error, _, %Message{text: ...}}" }

inventory:
  routes: []
  events:
    - WorkflowChannel#get_limits    # pushed after every run or retry (useRunRetry.ts:299-301, :402-404; Header.tsx:402, :462); owned by shared-editor-session
  js_hooks:
    - CollaborativeEditor NewRunButton (components/NewRunButton.tsx)
    - CollaborativeEditor RunRetryButton (components/RunRetryButton.tsx)
    - hooks useRunRetry (hooks/useRunRetry.ts), useRunRetryShortcuts (hooks/useRunRetryShortcuts.ts), useSaveBeforeRun (hooks/useSaveBeforeRun.ts), useCanRun (hooks/useWorkflow.tsx:951-1004)
    - Header quick run, header retry and their shortcuts (Header.tsx:385-491, :587-608, :861-881)
  policies:
    - Lightning.Policies.ProjectUsers :run_workflow     # workflow_controller.ex:79-85, :228-234; session context workflow_channel.ex:1521
    - Lightning.Policies.ProjectUsers :edit_workflow    # workflow_controller.ex:71-77; session context workflow_channel.ex:1520
    - Lightning.Policies.ProjectUsers :access_project   # workflow_controller.ex:220-226
  workers: []                                           # runs go to the run queue for external workers, not Oban
  api_endpoints:
    - post /projects/:project_id/workflows/:workflow_id/runs   WorkflowController :create_run   # router.ex:215-217; inputs and writes owned by workflow-editor-manual-run
    - post /projects/:project_id/runs/:run_id/retry            WorkflowController :retry_run    # router.ex:223-225
  emails: []
  config:
    - user.preferences.experimental_features
    - Lightning.Extensions.UsageLimiter (:new_run)      # work_orders.ex:84-91; workflow_channel.ex:2417-2419
  not_reachable_here:
    - input choice, size and JSON checks inside useRunRetry (useRunRetry.ts:215-243); owned by workflow-editor-manual-run (S03, S09, S13 there)
    - IDE job-not-in-run gate passed into RunRetryButton (FullScreenIDE.tsx:939-968); owned by workflow-editor-ide S18
    - "Run with custom input" menu item and Ctrl/Cmd+Shift+Enter in the header (Header.tsx:493-502, :610-625); owned by workflow-editor-manual-run S11
    - getLimits refresh handling (createSessionContextStore.ts:605-661, :721-737); owned by shared-editor-session 6.1

related:
  - workflow-editor-manual-run          # RunRetryButton in the panel footer (ManualRunPanel.tsx:683-700), shortcuts at priority 25 (:504-512)
  - workflow-editor-canvas              # header Run / Retry split button and global shortcuts at priority 0 (Header.tsx:587-608, :861-881)
  - workflow-editor-inspectors          # "Run From Here" NewRunButton in the step inspector (JobInspector.tsx:133-138)
  - workflow-editor-ide                 # NewRunButton and RunRetryButton in the IDE header, shortcuts at priority 50 (FullScreenIDE.tsx:464-485, :924-970)
  - workflow-editor-run-viewer          # takes over once run=<id> is set
flows:
  - flow-manual-run-live-follow         # every run or retry started here hands off to it
  - flow-history-live-updates           # runs and retries publish run and work order events on the project topic
---

## 1. Purpose

Workflow builders run and re-run their workflow from four places in the editor: the header, the step
inspector, the run panel and the full-screen code editor. These controls decide who may start a run,
save the workflow first so the run executes what is on screen, choose between retrying a run on its
existing work order and starting a new one, and refuse with a reason when a run can't happen. If they
got this wrong, people would test code they didn't save, stack duplicate work orders, retry with an
input they didn't mean, or click a button that silently does nothing.

## 2. What it does

- Editors start a quick run of the whole workflow from the header
- Editors retry a loaded, finished run from the header
- Editors retry a followed run from a step, but only with the input that run used
- Editors choose between retrying on the same work order and starting a new work order
- Editors run and retry from the keyboard, and the key acts on the innermost open surface
- The editor saves the workflow before a run or retry, and doesn't run if the save fails
- A live workflow or a pinned view runs or retries without saving (experimental)
- Retrying from a pinned version says it runs on the latest version (experimental)
- Everyone sees why a run control is disabled
- Run limits refuse a run up front and on the server
- The server only runs or retries for people allowed to run, within the project
- A control starts at most one run per click and stays busy while that run is processing

## 3. Who can do what

Source: `Lightning.Policies.ProjectUsers` (`project_users.ex:39-49`, `:134-174`). `:edit_workflow`
and `:run_workflow` are both editor actions, so they admit the same people. The client gate is
`useCanRun` (`useWorkflow.tsx:951-1004`), fed by `can_edit_workflow` and `can_run_workflow` from the
session context (`workflow_channel.ex:1516-1541`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the run controls (visibility) | yes, disabled | yes | yes | yes | no | yes, when support access is on |
| Start a run (create_run) | no | yes | yes | yes | no | yes, when support access is on |
| Retry a run (retry_run) | no | yes | yes | yes | no | yes, when support access is on |
| Force a new work order while retry is offered | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The client refuses while the document is not synced, on a deleted workflow, on a pinned view (except retry with experimental features), on an unsaved new workflow, and when the session's run limit says not allowed (`useWorkflow.tsx:983-1001`).
- `create_run` needs the workflow to belong to the project in the URL and both `:edit_workflow` and `:run_workflow` (`workflow_controller.ex:68-93`).
- `retry_run` needs `:access_project`, the run to belong to the project, and `:run_workflow` (`workflow_controller.ex:219-234`, `:284-294`).
- Both endpoints refuse when the usage limiter refuses `:new_run` (`helpers.ex:51-53`; `workflow_controller.ex:235`).
- A retry needs the step's input not wiped and the workflow not deleted (`work_orders.ex:327-353`).
- MFA and scheduled-deletion refusals come from the policy guard (`project_users.ex:134`; owned by shared-project-scope).

## 4. What it touches

**Reads**
- Client: session permissions and `limits.runs` (`useWorkflow.tsx:850-871`, `:963-965`), workflow `deleted_at`, jobs and triggers (`useWorkflow.tsx:853-859`, `:969-974`), the followed run's state and steps (`useRunRetry.ts:150-174`; `Header.tsx:269`, `:291-297`)
- Server: `projects`, `project_users`, `workflows`, `jobs`, `triggers`, `workflow_edges` (`workflow_controller.ex:30-35`); `runs`, `steps`, `work_orders`, `dataclips` for a retry (`workflow_controller.ex:219`; `work_orders.ex:314-353`)

**Writes**
- Run: `dataclips`, `work_orders`, `runs` (`work_orders.ex:127-149`; detail owned by workflow-editor-manual-run)
- Retry: `runs` insert on the existing work order with upstream steps attached, `work_orders` state update (`work_orders.ex:355-401`)
- The workflow, through the save before a run (`useSaveBeforeRun.ts:17-25`; owned by shared-editor-session)

**Immediate side effects**
- PubSub on the project topic: `run_created` and `work_order_created` for a run, `work_order_updated` and `run_created` for a retry (`work_orders.ex:151-157`, `:394-396`); received by flow-history-live-updates
- Toasts "Run started", "Retry started", "Failed to submit run", "Retry failed", "Cannot run workflow" (`useRunRetry.ts:256-261`, `:291-296`, `:318-322`, `:357-360`, `:394-399`, `:431-434`; `Header.tsx:396-411`, `:455-479`)
- `run=<id>` written to the URL (`useRunRetry.ts:311`, `:406-416`; `Header.tsx:404`, `:463-473`)
- `get_limits` pushed on the editor channel; its reply is never read (shared-editor-session 6.1)

**Deferred side effects**
- A worker claims the run from the `manual` queue and its progress streams back to the editor (flow-manual-run-live-follow)

**External, non-transactional effects**
- none at request time

**Depends on config**
- `user.preferences.experimental_features` (`useWorkflow.tsx:992`; `useRunRetry.ts:243`, `:406-416`; `Header.tsx:861-867`; `useSessionContext` content lock via `workflow_channel.ex:1507-1510`)
- The usage limiter extension; the default implementation always allows (`usage_limiter.ex:11`)

**Product limits**
- Run limits on new runs and retries, where a usage limiter is configured

## 5. Scenarios

```gherkin
Feature: Run and retry controls
  In order to test my workflow against the code on screen
  As a workflow builder
  I want consistent run and retry controls wherever I am in the editor

  @S01 @pending
  Scenario: Quick run from the header
    # Value: one click runs the whole workflow end to end while building it.
    Given I am an editor with "Intake" open, a trigger "Webhook" and no run loaded
    When I click "Run" in the header, or press Ctrl+Enter with no panel or IDE open
    Then the workflow is saved and a run starts from "Webhook" with an empty input
    And I see "Run started" with "Saved latest changes and created new work order"
    And the run panel does not open
    And the URL has "run=<new run id>" and the flow "flow-manual-run-live-follow" has started
    # Header.tsx:385-420, :587-608, :861-881; NewRunButton.tsx:87-105; workflow_controller.ex:26-66, :103-124
    # Header.keyboard.test.tsx:1145-1256

  @S02 @pending
  Scenario: Retry a finished run from the header
    # Value: after fixing a failure, the builder replays the same run on its own work order in one click.
    Given run "R" of "Intake" has finished and is loaded with "run=<R id>"
    When I look at the header
    Then the run button reads "Retry"
    When I click it, or press Ctrl+Enter
    Then the workflow is saved and a new run is created on R's work order from R's first step
    And no new work order is created
    And I see "Retry started" with "Saved latest changes and re-running this input on <version>."
    And the URL has "run=<new run id>"
    # Header.tsx:291-297, :422-491, :587-608, :868-879; workflow_controller.ex:208-244; work_orders.ex:312-401
    # Header.keyboard.test.tsx:1368-1442; workflow_controller_test.exs:435-449

  @S03 @pending @variant:experimental-features
  Scenario: Retrying from an older version runs the latest version and says so
    # Value: nobody believes they re-ran old code when the retry actually executes the current workflow.
    Given I am viewing "Intake" pinned to v2 with finished run "R" loaded, and v3 is current
    Then a fresh run is refused with "You are viewing a pinned version of this workflow"
    But the header offers "Retry" with the tooltip "Runs this input on the latest version (v3), not v2."
    When I click "Retry"
    Then the workflow is not saved
    And the URL loses "release", "v", "as_run" and "step" and has "run=<new run id>"
    # useWorkflow.tsx:992-994; Header.tsx:373-383, :450-473, :861-879; useSaveBeforeRun.ts:21-25; work_orders.ex:355-366
    # useCanRun.test.tsx:54-90; useSaveBeforeRun.test.tsx:41-50

  @S04 @pending
  Scenario: Retry is offered only for the input the run used
    # Value: a retry never quietly replays the run with a different input from the one the builder sees selected.
    Given run "R" is followed and its "Fetch" step took input "D", not wiped
    When the run panel or the IDE is on "Fetch" with "D" selected
    Then the button reads "Retry" with a chevron
    When I select a different input, or "D" has been wiped
    Then the button reads "Run" without a chevron
    # useRunRetry.ts:158-171, :204-213; RunRetryButton.tsx:69-70, :133-172
    # useRunRetry.test.tsx:369-464; RunRetryButton.test.tsx:28-76

  @S05 @pending
  Scenario: Retry continues the work order, the chevron starts a new one
    # Value: builders choose between extending a run's history and a fresh, separately tracked work order with the same input.
    Given the panel or the IDE offers "Retry" for run "R"
    When I click "Retry"
    Then a new run is created on R's work order and the upstream steps are attached, not executed again
    When I instead open the chevron and choose "Run (New Work Order)", or press Ctrl+Shift+Enter
    Then a new work order is created with the same input
    And R's work order gets no new run
    # RunRetryButton.tsx:128-131, :237-286; useRunRetryShortcuts.ts:115-126; useRunRetry.ts:248-315, :343-449; work_orders.ex:355-401
    # RunRetryButton.test.tsx:154-212; ManualRunPanel.keyboard.test.tsx:986-1218

  @S06 @pending
  Scenario: Run and retry from the keyboard while typing
    # Value: builders iterate on a step without leaving the code or input they are editing.
    Given the run panel or the IDE has a valid input and I can run
    When I press Ctrl+Enter, or Cmd+Enter on a Mac, with my cursor in the code or input editor
    Then a run starts, or a retry when one is offered
    And the browser's default action for the keys does not happen
    # useRunRetryShortcuts.ts:99-113; KeyboardProvider.tsx:74-122
    # ManualRunPanel.keyboard.test.tsx:410-573; FullScreenIDE.keyboard.test.tsx:609-704

  @S07 @pending
  Scenario: The shortcut acts on the surface in front of me
    # Value: a keystroke never fires a hidden control, such as a whole-workflow run while the builder is looking at one step.
    Given the run panel for "Fetch" is open over the canvas
    When I press Ctrl+Enter
    Then the run starts from "Fetch", not from the first trigger
    And the header's Run button is disabled
    When the IDE is open instead
    Then Ctrl+Enter is handled by the IDE and the header does nothing
    # useRunRetryShortcuts.ts:32-43; ManualRunPanel.tsx:504-512 (priority 25); FullScreenIDE.tsx:465-485 (priority 50); Header.tsx:587-608, :875 (priority 0)
    # Header.keyboard.test.tsx:1216-1256

  @S08 @pending
  Scenario: A run never starts if the workflow can't be saved first
    # Value: a run always executes the version on screen, never an older saved one the builder thinks they changed.
    Given "Intake" has a change the server will not save
    When I start a run or a retry from any run control
    Then no work order and no run is created
    And I see "Failed to submit run" or "Retry failed" with the save error
    # useSaveBeforeRun.ts:17-25; useRunRetry.ts:264-268, :316-324, :365-368, :429-437; Header.tsx:388-412, :426-481
    # ManualRunPanel.test.tsx:973-1049; useSaveBeforeRun.test.tsx:19-28

  @S09 @pending @variant:experimental-features
  Scenario: A live workflow runs without saving
    # Value: testing a live workflow never requires taking it out of production.
    Given "Intake" is live and content-locked
    When I start a run from any run control
    Then the workflow is not saved
    And I see "Run started" with "Created new work order"
    # useSaveBeforeRun.ts:17-25; useWorkflow.tsx:945 (run deliberately ignores the read-only lock); useRunRetry.ts:291-296; Header.tsx:396-401
    # useSaveBeforeRun.test.tsx:30-40

  @S10 @pending
  Scenario Outline: A disabled run control says why
    # Value: people see why they can't run instead of clicking a button that does nothing.
    Given <state>
    When I look at the header Run, the step inspector's "Run From Here", the panel's run button and the IDE's run button
    Then each is disabled with the reason <reason>
    # useWorkflow.tsx:951-1004; NewRunButton.tsx:47-59; RunRetryButton.tsx:73-78; ManualRunPanel.tsx:685, :699; FullScreenIDE.tsx:939-968; JobInspector.tsx:133-138
    # useCanRun.test.tsx:54-135; NewRunButton.test.tsx:21-58; RunRetryButton.test.tsx:632-668

    Examples:
      | state                                    | reason                                              |
      | the editor is disconnected               | "You are disconnected. Reconnecting..."             |
      | I am a viewer                            | "You do not have permission to run workflows"       |
      | "Intake" has been deleted                | "Workflow has been deleted"                         |
      | I am viewing a pinned version            | "You are viewing a pinned version of this workflow" |
      | "Intake" is new and not yet created      | "Create this workflow before running it"            |

  @S11 @pending @variant:run-limit-reached
  Scenario: Run limits refuse up front and on the server
    # Value: plan limits hold, and people learn about them before they click rather than after.
    Given the usage limiter refuses new runs in "Malawi HIV" with "Run limit reached"
    When I open "Intake"
    Then the run controls are disabled with the reason "Run limit reached"
    When a run or a retry is posted anyway
    Then the response is 400 with "Run limit reached" and no run is created
    And a control that sent it shows the refusal in its failure toast
    # workflow_channel.ex:1381, :2417-2419, :2437-2473; useWorkflow.tsx:963-965, :998-1001
    # helpers.ex:51-53; workflow_controller.ex:235, :246-249; fallback_controller.ex:55-63; useRunRetry.ts:385-388; api/dataclips.ts:160-170
    # workflow_controller_test.exs:261-286, :451-476

  @S12 @pending
  Scenario Outline: The server retries only for people who may run, inside the project
    # Value: only people trusted to execute code against external systems can re-run it, and never across projects.
    Given run "R" belongs to "Intake" in project "Malawi HIV"
    And <who>
    When a retry of "R" is posted through <project>
    Then no new run is created and the response is <status>
    # workflow_controller.ex:219-234, :264-275, :284-294; project_users.ex:167-172; fallback_controller.ex:24-29
    # workflow_controller_test.exs:535-586 (cross-project and missing run only; no viewer test)

    Examples:
      | who                                  | project       | status |
      | I am a viewer on "Malawi HIV"        | "Malawi HIV"  | 401    |
      | I am an editor on "Kenya TB" only    | "Kenya TB"    | 422    |
      | I am signed out                      | "Malawi HIV"  | 302    |

  @S13 @pending
  Scenario: One click starts one run
    # Value: an impatient double click, or a run still in progress, never stacks duplicate work orders.
    Given I start a run or a retry from any run control
    Then while it is being submitted the control reads "Processing" with a spinner and is disabled
    And a second click or Ctrl+Enter starts nothing
    And while the followed run has not finished the control stays "Processing"
    When the run reaches a final state
    Then the control is enabled again
    # NewRunButton.tsx:52-65; RunRetryButton.tsx:133-171, :175-235; useRunRetry.ts:46-62, :174, :178-202, :343-348; Header.tsx:272-291, :602-603, :877
    # RunRetryButton.test.tsx:77-108; useRunRetry.test.tsx:466-500, :945-1005
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The disabled reason is attached by putting the Radix tooltip trigger directly on a disabled `<button>` in the split `NewRunButton` (header) and in every `RunRetryButton` mode; only the single `NewRunButton` wraps it in a `<span>`. Disabled buttons don't fire the pointer events the tooltip listens for in most browsers | `NewRunButton.tsx:72-83` against `:89-105`; `RunRetryButton.tsx:147-170`, `:183-235` | hovering the disabled header Run, panel or IDE button shows no reason, so S10 holds only for the step inspector. Inferred from code, not checked in a browser | fix |
| The step inspector's "Run From Here" advertises Ctrl/Cmd+Enter, but no handler in the inspector opens the panel for that step; the key falls through to the header and runs the whole workflow from the first trigger with an empty input | `JobInspector.tsx:133-138`; `NewRunButton.tsx:57-58`; `Header.tsx:587-608` | pressing the shortcut the tooltip shows starts a different run from the one the button would | fix |
| "Run (New Work Order)" is gated on the retry gate, not the fresh-run gate; on a pinned view with experimental features it is enabled, then refused | `RunRetryButton.tsx:268-283`; `ManualRunPanel.tsx:685`; `useRunRetry.ts:256-262`; `useWorkflow.tsx:992-994` (compare `NewRunButton.tsx:48-53`, which gates its menu separately) | an enabled option, and Ctrl/Cmd+Shift+Enter, that only produce a "Cannot run workflow" toast | fix |
| The IDE builds its own `useRunRetry` without `maxDataclipSizeBytes`, so the size check is skipped for its Run button while the embedded panel shows the size error | `FullScreenIDE.tsx:447-462`; `useRunRetry.ts:229-234`; `ManualRunPanel.tsx:89-91`, `:535` | an enabled Run beside "Dataclip exceeds the 10 MB size limit", then a 413 toast. Inferred from code | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Ctrl/Cmd+Shift+Enter means "Run with custom input" (opens the panel) in the header, and "force a new work order" in the panel and the IDE | `Header.tsx:610-625`; `useRunRetryShortcuts.ts:115-126` | decide |
| Header retry starts from the run's first step and has no client check for a wiped input; panel and IDE retry from the chosen step and only when the selected input matches. The header offers Retry only for a finished run; the panel offers it whatever the run's state and shows "Processing" | `Header.tsx:293-297`, `:422-424`; `useRunRetry.ts:204-213` | decide |
| Retry success copy differs: "Saved latest changes and re-running with previous input" (panel, IDE) against "Saved latest changes and re-running this input on v3." (header). Moved from workflow-editor-manual-run 6.2 | `useRunRetry.ts:394-399`; `Header.tsx:450-460` | decide |
| The client allows a run with edit or run permission; `create_run` needs both, `retry_run` needs only run. The two grant the same roles today | `useWorkflow.tsx:976-977`; `workflow_controller.ex:87-88`, `:228-234`; `project_users.ex:39-49` | preserve |
| A limiter refusal whose message has no text is read as allowed by the client; the server still refuses | `useWorkflow.tsx:998`; `workflow_channel.ex:2461-2473`; `message.ex:7` | decide |
| `handleRetry` guards re-entry with a ref; `handleRun` and the header handlers rely on the control re-rendering as disabled | `useRunRetry.ts:343-348` against `:248-264`; `Header.tsx:385-388` | decide |
| The header's disabled Run (panel or IDE open) still shows the Ctrl/Cmd+Enter shortcut as its tooltip, because the tooltip ignores the `disabled` prop | `NewRunButton.tsx:52`, `:57-59`; `Header.tsx:875` | decide |
| The panel and IDE show the fresh-run reason as the disabled tooltip even when the control is in Retry mode | `ManualRunPanel.tsx:685`, `:699`; `FullScreenIDE.tsx:964-968` | decide |
| A disabled run with no permission problem (no input chosen, invalid custom body) carries no reason. Moved from workflow-editor-manual-run 6.2 | `RunRetryButton.tsx:73-78`; `ManualRunPanel.tsx:699` | decide |
| Labels are title case: "Run Workflow" (default), "Run From Here", "Run (New Work Order)". Moved from workflow-editor-manual-run 6.2 | `RunRetryButton.tsx:64`, `:282`; `ManualRunPanel.tsx:694`; `JobInspector.tsx:136` | decide |
| With experimental features a retry clears `release`, `v`, `as_run` and `step`; without it only `run` changes. Moved from workflow-editor-manual-run 6.2 | `useRunRetry.ts:406-416`; `Header.tsx:463-473`; `useRunRetry.test.tsx:903-943` | preserve |
| With experimental features the header shows its button with no trigger when a run is retryable; without the flag it needs a trigger | `Header.tsx:861-867` | decide |
| A shortcut handler that decides not to act still claims the keypress, so a refused Ctrl/Cmd+Enter in the panel or IDE never reaches a lower-priority handler | `useRunRetryShortcuts.ts:102-110`; `KeyboardProvider.tsx:110-122` | preserve |
| A retry runs against the latest snapshot, not the one the original run used (S03 states it to the user only on a pinned version) | `work_orders.ex:355-366`; `Header.tsx:378-383` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `NewRunButton` doc comment listing `TriggerInspector` | `NewRunButton.tsx:30-35`; `TriggerInspector.tsx:15`, `:27` | TriggerInspector no longer renders it; `onOpenRunPanel` is unused there. Moved from workflow-editor-manual-run 6.2 |
| `getLimits` result handling after a run or retry | `useRunRetry.ts:299-301`, `:402-404`; `Header.tsx:402`, `:462` | the reply is never read; owned by shared-editor-session 6.1 and 6.3 |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| "Processing" ends after 30 s if the new run never appears on the run channel | `useRunRetry.ts:34`, `:187-202`; `Header.tsx:279-290` | yes, the button re-enables | preserve |
| Tooltips open after 200 ms | `components/Tooltip.tsx:20` | no | preserve |

### 6.5 Things seen but not understood

- `useRunRetryShortcuts.test.tsx` re-implements the handler logic in its test component and calls the callbacks directly, so no unit test presses the keys through the hook; "Cmd+Shift+Enter always calls onRun" asserts that nothing was called (`useRunRetryShortcuts.test.tsx:33-63`, `:165-181`). (preserve)
- The e2e spec clicks "Run Workflow Now", a label that does not exist in `assets/js`, so "Run state updates in real-time via WebSocket" cannot be passing as written (`run-retry-keyboard-shortcuts.spec.ts:333-364`). (decide)
- `RunRetryButton` itself calls its handler on every click ("handles rapid clicks" expects three calls); S13 depends on the host's `isSubmitting` re-render (`RunRetryButton.test.tsx:888-912`). (preserve)
- No test covers a viewer posting to `retry_run`; the "requires run_workflow permission" test is a cross-project case (`workflow_controller_test.exs:550-568`). S12's viewer row is read from code. (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. Should Ctrl/Cmd+Shift+Enter mean one thing everywhere (6.2)?
2. Should the header retry from the first step of the run, or follow the panel's per-step rule (6.2)?
3. Should "Run (New Work Order)" follow the fresh-run gate on a pinned view (6.1)?
4. workflow-editor-manual-run S12, S15, S16, S17, S18, S19, S22 and S23 are now S01, S05, S06, S08, S09, S10, S11 and S13 here; its 6.2 rows on retry copy, disabled-without-reason, title case, retry URL clearing, the 30 s timeout and the TriggerInspector comment now live here. Can the lead drop them there? Its S14 stays, as the panel's input preselection.

## Proposed flows

none. Referenced: flow-manual-run-live-follow (S01, S02 hand off once `run=<id>` is set), flow-history-live-updates (project topic events).

## Proposed shared

none. Referenced: shared-authenticated-session, shared-project-scope, shared-editor-session.

## Summary

- Scenarios: 13 (S01 to S13), all `@pending`; S03 and S09 tagged `@variant:experimental-features`, S11 `@variant:run-limit-reached`.
- Section 6: 6.1 has 4, 6.2 has 14, 6.3 has 2, 6.4 has 2, 6.5 has 4.
- Flows: none proposed; references flow-manual-run-live-follow and flow-history-live-updates.
- Shared: none proposed; inherits shared-authenticated-session, shared-project-scope, shared-editor-session.
- Unsure: the disabled-tooltip and IDE size-limit bugs are read from code only; S12's viewer status (401) has no test; the S02 version text in the toast depends on the releases list.
