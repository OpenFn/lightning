---
id: shared-run-components
type: shared
title: Run display components
status: not-started
owner:

trigger:
  old_route: any LiveView that imports LightningWeb.RunLive.Components or calls RunLive.CancelHelper, and the collaborative editor's run viewer (React ports under assets/js/collaborative-editor/components/run-viewer/)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host page passed the project scope gate (shared-project-scope)
    - the host page supplies `can_run_workflow`, `can_edit_data_retention` and `experimental_features` itself; nothing in this module computes them (`index.ex:90-102`, `show.ex:311-344`)
    - React ports only, when the editor has loaded a run that passed `RunDetailSchema` (`createHistoryStore.ts:362-386`); the run viewer's own gates are owned by workflow-editor-run-viewer

inherits:
  - shared-project-scope            # who can open the host page; not repeated here

url_params: []                      # the module sets params on outbound links (`v`, `as_run`, `step`); it reads none

config_variants:
  default: {}                                                    # verified against this
  experimental-features: { user.preferences.experimental_features: true }   # accounts.ex:1446-1448

inventory:
  routes: []
  events:
    - "<host>#cancel-run (handled by each host, delegates to CancelHelper.cancel_run/2: index.ex:622-649, show.ex:370-404)"
  js_hooks:
    - ElapsedIndicator               # assets/js/hooks/ElapsedIndicator.ts
    - Tooltip                        # used by clone markers, rerun tag and retention tooltips; each view also lists it
  react_components:                  # React ports rendered by workflow-editor-run-viewer (RunTabPanel.tsx:13-15, :91, :98-101, :167; StepItem.tsx:8-9, :69, :93-96)
    - collaborative-editor/components/run-viewer/StatePill.tsx          # port of state_pill/1 and display_text_from_state/1
    - collaborative-editor/components/run-viewer/StepIcon.tsx           # port of step_icon/1
    - collaborative-editor/components/run-viewer/ElapsedIndicator.tsx   # port of the ElapsedIndicator hook
    - collaborative-editor/components/run-viewer/StepItem.tsx clone marker only (StepItem.tsx:54-90); the row's click, job name and selection are owned by workflow-editor-run-viewer
  policies:
    - Lightning.Policies.ProjectUsers :run_workflow          # evaluated by the host, read here as can_run_workflow
    - Lightning.Policies.ProjectUsers :edit_data_retention   # evaluated by the host, read here as can_edit_data_retention
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features (passed in as experimental_features)
  not_reachable_here:
    - RunLive.Components.bulk_cancel_modal/1, bulk_rerun_modal/1 and the humanize_* helpers (components.ex:638-1000), rendered only by history-work-orders, which owns them
    - RunLive.Components.async_filler/1 (components.ex:347-356), rendered only by history-work-orders
    - "workflow-editor-run-viewer: cancel, the step rerun icon, retention tooltips and the version and inspect links have no React port (no cancel in collaborative-editor/; StepItem.tsx:57-98 renders none of them); S07 to S14 do not apply there"
    - MiniHistory's own StatePill and StatusIndicator (MiniHistory.tsx:75-133), a separate copy owned by workflow-editor-versions-and-promote; see 6.1

related:
  - history-work-orders
  - run-show
  - history-channel-logs
  - workflow-editor-run-viewer
flows:
  - flow-history-live-updates
---

## 1. Purpose

People investigating a failed or slow integration read the same run vocabulary on History and on
the run page: a state pill, a per-step outcome icon, a live duration, a link back to the workflow
as it was when the run executed, and a cancel action for runs not yet picked up. Getting these
wrong means misreading what happened to health data (a crash shown as a failure, a kill shown as
success), inspecting code that didn't run, or cancelling work that is already executing. The
collaborative editor's run viewer renders React copies of the pill, the step icon, the duration
and the clone marker; they must read the same as History and the run page, or a builder looking at
a run next to its code sees a different story from the person who sent them the link.

## 2. What it does

- Anyone on the project sees each run and work order state as a labelled pill
- Anyone sees each step's outcome as an icon, including why a step was killed
- Anyone sees how long a run or step has taken, counting up while it runs
- Anyone sees which steps were carried over from an earlier run
- Anyone following a run or step link to the workflow lands on the version that ran
- Editors cancel a run that no worker has claimed yet
- Editors cannot cancel a run outside the current project
- Anyone sees why a step whose input was not kept can't be rerun, and admins get a link to change retention
- Anyone sees that a step whose job was deleted can't be rerun
- Anyone viewing a run in the workflow editor sees the same state labels, step icons, durations and clone markers

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-50`, `:157-168`. The module itself checks no
policy; each host evaluates it and passes booleans in.

| Action | Viewer | Editor | Admin | Owner | Superuser | Support |
|--------|--------|--------|-------|-------|-----------|---------|
| See state pills, step icons, durations, clone markers, version links | yes | yes | yes | yes | no | yes, when support access is on |
| See the step rerun icon (enabled or disabled) | no | yes | yes | yes | no | yes, when support access is on |
| Cancel an available run | no | yes | yes | yes | no | yes, when support access is on |
| Get the data storage settings link in retention tooltips | no | no | yes | yes | no | no |
| See the React ports in the editor run viewer (`:access_project` on run channel join, `run_channel.ex:76`) | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Cancel needs the run to belong to the current project (`cancel_helper.ex:12-16`, `runs.ex:74-84`).
- Cancel needs the run to be in state `available` at the moment of the update (`runs.ex:466-492`).
- The step rerun icon renders only for a step that has finished (`components.ex:474`).
- The step rerun icon is only clickable when the step's input dataclip exists and is not wiped and its job still exists (`components.ex:503-514`).
- Experimental features change the version link shape (`components.ex:304-313`).
- The React ports read no policy and no config; their host has already joined the run channel (`StatePill.tsx:8-51`, `StepIcon.tsx:7-62`, `ElapsedIndicator.tsx:21-55`).

## 4. What it touches

**Reads**: `runs` joined through `work_orders` and `workflows` to scope by project (`runs.ex:74-84`); everything else is preloaded by the host (steps with `job`, `input_dataclip`, `snapshot`: `invocation.ex:688-703`, `index.ex:280-291`, `streaming.ex:19-22`)

React ports read only props: the run and steps from `fetch:run` on the run channel (`run_channel.ex:261-275`), encoded by `Step`'s `Jason.Encoder` (`invocation/step.ex:37-49`) and parsed by `RunDetailSchema` (`types/history.ts:99-150`, `createHistoryStore.ts:362-386`)

**Writes**: React ports write nothing. `runs.state` to `cancelled` with `updated_at` (`runs.ex:466-492`); `work_orders.state` recomputed (`runs.ex:261-265`, `work_orders.ex:830-839`)

**Immediate side effects**
- Broadcast `Runs.Events.RunUpdated` on the run topic and `WorkOrders.Events` run updated on the project topic after a cancel (`runs.ex:269-287`)
- Broadcast `WorkOrders.Events` work order updated on the project topic (`work_orders.ex:836`)
- Rendering a step killed with an unrecognised error type logs a warning and sends a Sentry message (`components.ex:592`, `:627-636`); the React port only writes a browser console warning (`StepIcon.tsx:44-47`)

**Deferred side effects**
- none

**External, non-transactional effects**
- The Sentry message above, sent during render

**Depends on config**
- `user.preferences.experimental_features` (`components.ex:308-309`, `show.ex:327-328`)

**Product limits**
- Durations are shown in whole ms, s or m only; there is no hour unit (`ElapsedIndicator.ts:3-13`, ported unchanged at `ElapsedIndicator.tsx:9-19`)

## 5. Scenarios

```gherkin
Feature: Run display components
  In order to understand and control what happened to a run
  As anyone working in a project
  I want consistent run states, step outcomes, durations, version links and cancel

  @S01 @pending
  Scenario: States show as labelled pills
    # Value: people can tell queued work from work in progress without knowing internal state names.
    Given a run in state "available" and another in state "claimed"
    When I see their status pills
    Then the first reads "Enqueued" and the second reads "Starting"
    And a run in state "started" reads "Running" and a failed run reads "Failed"
    # components.ex:110-138, :162-174
    # test/lightning_web/live/run_live/show_test.exs:541-569 asserts "Cancelled" after a cancel

  @S02 @pending
  Scenario: Step icons distinguish success, failure, crash and pending
    # Value: people find the failing step at a glance and don't mistake a crash for a handled failure.
    Given a run with a pending step, a successful step and a failed step
    When I look at the step list
    Then the pending step shows a grey icon, the successful one a green check and the failed one a red cross
    # components.ex:579-625
    # test/lightning_web/live/run_live/components_test.exs:59-214 asserts the gray-400, green-500 and red-500 icon classes

  @S03 @pending
  Scenario: A killed step says why it was killed
    # Value: people can tell a timeout from a memory or security limit and fix the right thing.
    Given a step with exit reason "kill" and error type "TimeoutError"
    And another with exit reason "kill" and error type "SecurityError"
    When I look at the step list
    Then the first shows a clock icon and the second a shield icon
    And a step killed with "OOMError" or "StateTooLargeError" shows an exclamation icon
    # components.ex:587-591
    # test/lightning_web/live/run_live/components_test.exs:380-400

  @S04 @pending
  Scenario: A running item's duration counts up
    # Value: someone watching a long job can see it is still going and for how long, without refreshing.
    Given a step that started 5 seconds ago and has not finished
    When I look at its duration
    Then it reads "5 s"
    And a second later it reads "6 s"
    # components.ex:24-33, ElapsedIndicator.ts:16-41

  @S05 @pending
  Scenario: A finished item shows its final duration and an unstarted one says so
    # Value: people compare run times to spot slow jobs, and can tell a queued run from a fast one.
    Given a step that ran for 90 seconds
    And a run that has not started
    Then the step's duration reads "1 m"
    And the run's duration reads "Not started"
    # ElapsedIndicator.ts:3-13, :32-40

  @S06 @pending
  Scenario: Steps carried over from an earlier run are marked
    # Value: after a rerun from a step, people can tell which steps actually ran again.
    Given run "R2" was rerun from the last step of run "R1"
    When I look at "R2"'s steps
    Then the steps reused from "R1" are faded with a paperclip whose tooltip says it "was originally executed in a previous run"
    And the step that ran in "R2" has no paperclip
    # components.ex:236-253, :411-418, :445-460; show.ex:217-219
    # test/lightning_web/live/run_live/components_test.exs:215-288

  @S07 @pending
  Scenario: Links to the workflow open the version the run executed
    # Value: people inspect the code that actually ran, not code changed since.
    Given a run executed on workflow version 1 and the workflow is now on version 2
    When I look at the run's workflow link or a step's inspect link
    Then the link carries "run=<run id>" and "v=1"
    And when the run executed on the current version the link carries no version
    # components.ex:298-314, :256-270, :477-488; show.ex:111-118
    # test/lightning_web/live/run_live/components_test.exs:122-155, :330-345; show_test.exs:329-392

  @S08 @pending @variant:experimental-features
  Scenario: With experimental features the link pins the run itself
    # Value: runs on versions that were never released can still be opened at the code that ran.
    Given I have experimental features enabled
    And a run executed on an older workflow version
    When I look at its workflow or step inspect link
    Then the link carries "as_run=<run id>" and no "v"
    And the flow "flow-open-run-in-editor" starts when I follow it
    # components.ex:283-287, :308-309
    # test/lightning_web/live/run_live/components_test.exs:157-182, :347-375; show_test.exs:394-428

  @S09 @pending
  Scenario: Editor cancels a run no worker has claimed
    # Value: people stop work queued by mistake before it sends data anywhere.
    Given I am an editor and run "R" is in state "available"
    When I click "Cancel" for "R"
    Then I see "Run cancelled."
    And "R" is in state "cancelled"
    And a run updated event is broadcast for "R"
    # cancel_helper.ex:12-16, runs.ex:466-492, :269-287; show.ex:191-203, :370-374; index.ex:622-626
    # test/lightning_web/live/run_live/show_test.exs:541-569, index_test.exs:1280-1300

  @S10 @pending
  Scenario: Cancelling never stops a run a worker has already claimed
    # Value: a run that is already executing is never marked cancelled while it carries on sending data.
    Given I am an editor with run "R" open while it is "available"
    And a worker claims "R"
    When I click "Cancel" for "R"
    Then I see that the run could not be cancelled
    And "R" stays in state "claimed"
    # runs.ex:466-492 (state guard and SKIP LOCKED in the UPDATE), show.ex:379-386, index.ex:631-638
    # test/lightning_web/live/run_live/show_test.exs:571-600 asserts "already been claimed"; index_test.exs:1462-1495 asserts "no longer available"

  @S11 @pending
  Scenario: A run from another project cannot be cancelled
    # Value: an editor of one project cannot stop another project's work.
    Given I am an editor on project "Malawi HIV"
    And run "R" is "available" in project "Kenya TB"
    When I send "cancel-run" for "R" from a "Malawi HIV" page
    Then I see "Run not found."
    And "R" stays "available"
    # cancel_helper.ex:13-14, runs.ex:74-84
    # show_test.exs:602-626 and index_test.exs:1445-1459 cover only a random id, not a foreign run

  @S12 @pending
  Scenario: Cancel is only offered on available runs to people who can run workflows
    # Value: viewers can investigate without being able to stop work, and nobody is offered a cancel that can't succeed.
    Given run "R" is "available"
    When a viewer opens the run page
    Then there is no cancel button
    And when "R" is "claimed", "started" or finished, no one sees a cancel button
    # show.ex:191, workorder_component.ex:413
    # test/lightning_web/live/run_live/show_test.exs:457-539

  @S13 @pending
  Scenario: Retention tooltips point admins to the setting and others to an admin
    # Value: the person who can change retention can get there, and everyone else knows whom to ask.
    Given a finished step whose input was not stored because of the project's retention policy
    When an admin hovers its disabled rerun icon
    Then the tooltip says "This work order cannot be rerun since no input data has been stored"
    And it has a "Go to data storage settings" link to "/projects/<project_id>/settings#data-storage"
    When an editor hovers it
    Then the tooltip says "For more information, contact one of your project admins."
    # components.ex:525-545, :549-570
    # test/lightning_web/live/run_live/components_test.exs:507-606, :608-707

  @S14 @pending
  Scenario: A step whose job was deleted cannot be rerun
    # Value: nobody tries to rerun a job that no longer exists in the workflow.
    Given a finished step whose job has since been deleted
    And its input is still stored
    When an editor hovers its rerun icon
    Then the icon is greyed out and not clickable
    And the tooltip says "This step has been deleted and cannot be retried"
    # components.ex:503, :510-522

  # S15 to S18: the React ports in the editor run viewer. Each restates a LiveView scenario above
  # for the editor so the two cannot drift; differences are in 6.1 and 6.2.

  @S15 @pending
  Scenario: The editor run viewer labels run states as History does
    # Value: a builder opening a run in the editor reads the same state as the person who sent them the link.
    Given run "R" is in state "available"
    When I view "R" in the workflow editor's run viewer
    Then its status pill reads "Enqueued"
    And in state "claimed" it reads "Starting", in "started" "Running" and in "failed" "Failed"
    And each pill has the same colour as on the run page
    # StatePill.tsx:9-38 (port of components.ex:110-138, :162-174); RunTabPanel.tsx:88-93
    # no test renders StatePill

  @S16 @pending
  Scenario: The editor run viewer shows the same step outcome icons
    # Value: the failing step, and why a step was killed, look the same in the editor as on the run page.
    Given a run with a pending, a successful, a failed and a crashed step
    And a step killed with "TimeoutError", one with "SecurityError" and one with "OOMError"
    When I view the run in the editor's run viewer
    Then they show a grey icon, a green check, a red cross, an orange cross, a clock, a shield and an exclamation icon
    # StepIcon.tsx:14-54 (port of components.ex:579-625); StepItem.tsx:69
    # StepIcon.test.tsx:11-26 asserts only the exclamation icon and yellow-800 class for OOMError, StateTooLargeError and an unknown type

  @S17 @pending
  Scenario: Editor durations count up while running and settle when finished
    # Value: someone watching a run from the editor sees it is still going, and the final time once it ends.
    Given step "Fetch" started 5 seconds ago and has not finished
    When I view its run in the editor's run viewer
    Then "Fetch" reads "5 s" and a second later "6 s"
    When "Fetch" finishes after 90 seconds
    Then it reads "1 m" and stops changing
    And a run that has not started reads "Not started" as its duration
    # ElapsedIndicator.tsx:21-55 (port of ElapsedIndicator.ts:3-41); StepItem.tsx:92-97; RunTabPanel.tsx:95-103
    # no test renders ElapsedIndicator.tsx

  @S18 @pending
  Scenario: The editor run viewer marks steps carried over from an earlier run
    # Value: after a rerun from a step, a builder in the editor can tell which steps actually ran again.
    Given run "R2" was rerun from the last step of run "R1"
    When I view "R2" in the editor's run viewer
    Then the steps reused from "R1" are faded with a paperclip labelled "Cloned from previous run"
    And its tooltip says it "was originally executed in a previous run"
    And the step that ran in "R2" has no paperclip
    # StepItem.tsx:54-90 (port of components.ex:236-253, :411-418); StepList.tsx:24-28
    # no test covers the clone marker
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `step_icon` has no clause for `exception` with a non-empty or nil error type, nor for any exit reason outside its list, so it raises `CaseClauseError`; the worker's step reason is a free string (`handlers.ex:419`, `:500`) | `components.ex:581-595` | the history row or run page crashes for that run | fix |
| `channel_state_pill` uses `Map.fetch!`, so any channel request state added to the enum without a config entry raises | `components.ex:154`; `channel_request.ex:34-35` | channel logs page crashes | decide |
| `cancel-run` with a non-UUID `run_id` raises `Ecto.Query.CastError` in `Runs.get_for_project/2`, unlike `rerun`, which validates first | `cancel_helper.ex:13`, `runs.ex:74-84` | the page crashes and reconnects; nothing is cancelled | fix |
| On the run page, `step_item` (which contains an inspect `<a>`) is wrapped in another `<.link patch>`, giving nested anchors; the inner link is a `patch` to the workflow editor, a different LiveView | `show.ex:212-224`, `components.ex:257-269` | clicking the inspect icon may also select the step, or fall back to a full page load | decide |
| The step rerun icon's DOM id is the bare step id, and a step carried into a rerun is listed under both runs | `components.ex:508`, `:527` | duplicate ids; a tooltip can attach to the wrong icon | fix |
| `step_item` assigns a fresh random tooltip id on every render (`assign_new` never sees a passed value) | `components.ex:213-215` | the clone tooltip element is replaced on each update, so an open tooltip can vanish | fix |
| The step-level retention tooltip says "This work order cannot be rerun" on a per-step rerun icon | `components.ex:552` | copy that names the wrong thing | fix |
| MiniHistory carries a third pill copy that capitalises the raw state instead of using these labels | `MiniHistory.tsx:93-114`, `:260`, `:429` | in the editor the same run reads "Available" or "Claimed" in the history list and "Enqueued" or "Starting" in the run viewer | fix |
| React port: `StepIcon` falls back to the grey pending icon for any unrecognised exit reason, where the LiveView raises (row 1) | `StepIcon.tsx:55-59` | a finished step with a new worker reason looks as if it has not run yet | decide |
| React port: the run's state must be one of `ALL_RUN_STATES`, or `RunDetailSchema` rejects the whole payload | `types/history.ts:63-74`, `:124`; `createHistoryStore.ts:379-384`; `runs/run.ex:44-56` | a state added to `Run` without the client list turns the editor run viewer into "Invalid run data" | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Run and work order labels differ from state names: pending and available read "Enqueued", claimed "Starting", started "Running"; others are capitalised atoms | `components.ex:162-174` | preserve |
| Channel request pill says "In Progress" for `pending`, where the run pill says "Enqueued" | `components.ex:147` vs `:166` | decide |
| `cancelled` pill is `bg-gray-500 text-gray-800`, low contrast compared with the others (ported as is) | `components.ex:123`, `StatePill.tsx:18` | decide |
| The not-claimed flash differs by host: "it has already been claimed by a worker" on the run page, "it is no longer available" on History, both as info flashes | `show.ex:379-386`, `index.ex:631-638` | decide |
| CancelHelper does no authorization; each host checks `can_run_workflow` itself before calling it | `cancel_helper.ex:12-17`, `show.ex:371`, `index.ex:623` | preserve |
| A run that a worker is locking at the instant of cancel is skipped (`SKIP LOCKED`) and reported as not available | `runs.ex:471` | preserve |
| The running duration is computed from the browser clock against the server start time, so clock skew shows | `ElapsedIndicator.ts:34` | decide |
| The duration interval keeps ticking every second after the item has finished | `ElapsedIndicator.ts:18-20` | decide |
| History hides the duration for available and cancelled runs; the run page shows "Not started" | `workorder_component.ex:405-409`, `show.ex:184` | decide |
| Retention tooltips carry HTML in `aria-label` and rely on the Tooltip hook's `allowHTML`, so screen readers read raw markup | `components.ex:531-537`, `index.ts:583-590` | fix |
| The retention link is a plain `href` (full page load) to the settings hash | `components.ex:563` | preserve |
| The step list item shows the raw exit reason and error type in monospace (`fail:TimeoutError`) next to the icon | `components.ex:492-494` | preserve |
| A carried-over step is detected by `step.inserted_at < run.inserted_at`, not by an explicit flag; the React port compares the JSON timestamps in the browser | `components.ex:411-413`, `show.ex:217-219`, `StepItem.tsx:55` | decide |
| React port: `StepIcon` shows the triangle for `exception` with any error type; the LiveView matches only an empty one | `StepIcon.tsx:48-51` vs `components.ex:593` | decide |
| React port: an unknown kill error type only writes a browser console warning; nothing reaches Logger or Sentry | `StepIcon.tsx:44-47` vs `components.ex:627-636`; `StepIcon.test.tsx:28-40` | decide |
| React port: the duration timer stops once the item has finished, unlike the hook, which keeps ticking | `ElapsedIndicator.tsx:45-51` vs `ElapsedIndicator.ts:18-20` | preserve |
| React port: the duration parses ISO timestamps from the run channel, with the same browser clock skew as the hook | `ElapsedIndicator.tsx:33-37` | decide |
| React port: `StatePill` covers run states only; the work order labels (`rejected`, `pending`, `running`) are not ported | `StatePill.tsx:9-35` vs `components.ex:112-115`, `:164-167` | preserve |
| React port: the clone marker uses the Radix `Tooltip` component, so the LiveView id problems (6.1) don't apply; its accessible name is "Cloned from previous run", where the LiveView puts the whole sentence in `aria-label` | `StepItem.tsx:77-88` vs `components.ex:236-253` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `run_id` branch of the elapsed indicator id | `components.ex:40-43` | neither `Step` nor `Run` has a `run_id` field, so `Map.get` is always nil |
| `job_id` attr of `step_item` (hides the inspect link for the current job) | `components.ex:199`, `:256` | no caller passes it; run page uses the default nil |
| React `StatePill` fallback class for an unknown state | `StatePill.tsx:37` | `RunDetailSchema` rejects any state outside `ALL_RUN_STATES` before the pill renders (`types/history.ts:124`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every rendered duration runs its own 1-second timer (React port: only while unfinished) | `ElapsedIndicator.ts:18-20`, `ElapsedIndicator.tsx:45-49` | no | preserve |
| An unknown kill error type sends a Sentry message on every render, not once | `components.ex:627-636` | no | decide |

### 6.5 Things seen but not understood

- Runs use worker reason "ok" for success (`run.ex:80-88`), while `step_icon` matches step reason "success" (`components.ex:583`). Tests use "success" for steps; the worker's actual step vocabulary was not checked in this repo. The React port copies the same match (`StepIcon.tsx:17`).
- `step_icon` matches `{"exception", ""}` only (`components.ex:593`); unclear whether the worker ever sends an empty error type, or why that was chosen over a wildcard.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a step with an unrecognised exit reason render a fallback icon rather than crash? (6.1)
- Should the two hosts use one not-claimed message? (6.2)
- history-work-orders S13, S14 and S22 restate S07, S08 and S13 here; should they be reduced to inheritance?
- Should the LiveView and React copies share one behaviour for an unrecognised exit reason and an unknown kill type (6.1, 6.2)?
- workflow-editor-run-viewer S02 to S04 restate S15 to S18 here; should they be reduced to inheritance?

## Proposed flows

No new flows for the React ports; their live updates are owned by flow-manual-run-live-follow, and run links into the editor by flow-open-run-in-editor (both referenced, not proposed here).

- **flow-open-run-in-editor**: a workflow or step inspect link from History or the run page opens the collaborative editor on the run's snapshot (`v=`) or the run itself (`as_run=`), with the run panel and job selected. This file asserts only the link. Surfaces: history-work-orders, run-show, workflow-editor.
- **flow-run-show-live-updates**: after a cancel (or any run change), `Runs.Events` on the run topic updates an open run page's state pill and removes the cancel button (`show_test.exs:563-568`). History's half is owned by flow-history-live-updates. Surfaces: run-show (or history-work-orders), pubsub:run:<run_id>, run-show.

## Proposed shared

- none
