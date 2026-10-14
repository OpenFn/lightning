---
id: flow-run-show-live-updates
type: flow
title: A running run updating on its page
status: not-started
owner:

trigger:
  entry: controller:run-channel              # the worker's run:<id> channel; the claim arrives one hop earlier on worker:queue
  exit: run-show
  surfaces:
    - controller:worker-channel              # "claim" on worker:queue (worker_channel.ex:45-49); moves the run to claimed
    - controller:run-channel                 # "run:start", "step:start", "step:complete", "run:log", "run:batch_logs", "run:complete" on run:<id> (run_channel.ex:112-258)
    - pubsub:run_events:<run_id>             # Lightning.Runs.Events (runs/events.ex:29-68)
    - run-show                               # the open page that receives the events (streaming.ex:110-151)
  reachable_when:
    - the receiving page is run-show and its async run load has completed; it subscribes only then (streaming.ex:165-168)
    - the receiving page passed the project scope gate and the run belongs to the project (shared-project-scope; hooks.ex:169-183; streaming.ex:15-27)

inherits:
  - shared-project-scope            # who can open the receiving page, membership remount; not repeated here
  - shared-run-components           # state pill labels, step icons, elapsed time, cancel; this flow only says when they change

url_params: []                      # the page's `step` param decides which step's output is loaded; owned by run-show

config_variants:
  default: {}                       # read under this variant

inventory:
  routes: []
  events:
    - RunLive.Show handle_info Runs.Events.RunUpdated (streaming.ex:120-127)                   # owned by run-show; the exit hop
    - RunLive.Show handle_info Runs.Events.StepStarted, StepCompleted (streaming.ex:129-138)
    - RunLive.Show handle_info Runs.Events.LogAppended (streaming.ex:140-150)
    - RunLive.Show handle_async :run, subscribe (streaming.ex:165-168)
  js_hooks:
    - LogViewer                      # receives "logs-<run_id>" push events (log-viewer/index.ts:35-44); owned by run-show
    - ElapsedIndicator               # re-reads start and finish times on patch (ElapsedIndicator.ts:22-24); owned by shared-run-components
  policies: []                       # the receiving side does no per-event check; the topic is the run id loaded under project scope
  workers: []
  api_endpoints:
    - channel worker:queue "claim"
    - channel run:<id> "run:start", "step:start", "step:complete", "run:log", "run:batch_logs", "run:complete"
  emails: []                         # run:complete starts flow-failure-alert-email; owned there
  config: []
  not_reachable_here:
    - RunChannel browser join and its forwarders "fetch:run", "fetch:logs", "run:updated", "step:started", "step:completed", "logs", "dataclip:updated" (run_channel.ex:67-95, :260-323); used by workflow-editor-run-viewer, not run-show
    - Runs.Events.DataclipUpdated, ignored by run-show (show.ex:406-409); owned by flow-zero-persistence-runs
    - WorkOrders.Events run_updated on project:<project_id> (runs.ex:286); owned by flow-history-live-updates
    - RunChannel "fetch:plan", "fetch:credential", "fetch:dataclip" (run_channel.ex:102-191); no page event follows except DataclipUpdated

related:
  - lib/lightning/runs.ex
  - lib/lightning/runs/events.ex
  - lib/lightning/runs/handlers.ex
  - lib/lightning/runs/queue.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning_web/channels/worker_channel.ex
  - lib/lightning_web/live/run_live/streaming.ex
  - lib/lightning_web/live/run_live/show.ex
  - lib/lightning_web/components/viewers.ex
  - assets/js/log-viewer/index.ts
  - assets/js/log-viewer/store.ts
  - test/lightning_web/live/run_live/show_test.exs
flows:
  - flow-history-live-updates        # the same worker hops reach open history pages through the project topic
  - flow-failure-alert-email         # started by the run:complete hop
---

## 1. Purpose

People who start a run, or open one a colleague or an alert pointed them to, often watch it while
it executes to see whether data is getting through. The run page has to follow the worker as it
picks the run up, works through each step and writes logs, so they can spot a failing step as it
happens instead of reloading or guessing from a stale "Enqueued".

## 2. What it does

Worker claims the run, starts it, starts and completes steps, sends log lines and completes the run → Runs.Events on `run_events:<run_id>` → the open run page updates its state pill, cancel action, timestamps and duration, step list, the selected step's output and the log, without a reload.

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-50`, `:160-169` via `show.ex:311-317` (receiving
side); worker and run tokens for the sending side.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See live updates on an open run page | yes | yes | yes | yes | no | yes, when support access is on |
| See the cancel action disappear when the run is claimed | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Worker hops are not user actions: the claim needs a worker token on `worker:queue` (`worker_channel.ex:18-42`), every run hop needs a run token for that run id (`run_channel.ex:36-65`).
- Only a page showing this run receives the events: the topic is `run_events:<run_id>` (`runs/events.ex:64-68`), and the page subscribes with the run it loaded under project scope (`streaming.ex:15-27`, `:168`).
- A step start is accepted only when its job is reachable in the run's snapshot and its dataclip and credential are in the run's project (`handlers.ex:266-267`, `:340-373`); a log line's step must belong to the run (`runs.ex:294-306`).
- `can_run_workflow` is read once at mount (`show.ex:311-317`); a role change mid-session is handled by the shared-project-scope remount.

## 4. What it touches

**Reads**
- Worker hops: `runs` (`run_channel.ex:43`), `run_steps` for log validation (`runs.ex:298-299`, `:326`)
- Receiving page: `jobs` per step event (`streaming.ex:33`), the selected step's `dataclips` when it has none loaded or the id changed (`streaming.ex:55-77`); otherwise renders from the event payload

**Writes, by hop**
- Claim: `runs.state` to `claimed`, `claimed_at`, `worker_name` (`queue.ex:35-69`); `work_orders.state` (`runs.ex:261-265`)
- `run:start`: `runs.started_at`, `state` to `started` (`handlers.ex:27-33`; `runs.ex:226-250`)
- `step:start`: `steps` and `run_steps` insert (`handlers.ex:270-277`)
- `step:complete`: output `dataclips` insert, `steps` exit reason, error and `finished_at` (`handlers.ex:475-501`, `:541-556`)
- `run:log`, `run:batch_logs`: `log_lines` insert, one or many (`runs.ex:292-341`)
- `run:complete`: final `dataclips` insert when the worker sends a final state, then `runs` final state and `finished_at` (`handlers.ex:92-115`, `:171-213`); `work_orders.state`
- Receiving page: none

**Immediate side effects** (broadcasts on `run_events:<run_id>`)
- Claim, start and complete: `RunUpdated`, after preloading snapshot, creator, starting trigger and workflow (`runs.ex:269-289`); the same call sends `WorkOrders.Events` on the project topic (flow-history-live-updates)
- `step:start`: `StepStarted` with the snapshot preloaded (`handlers.ex:238-246`)
- `step:complete`: `StepCompleted` with the snapshot preloaded (`handlers.ex:464-473`)
- `run:log`: one `LogAppended` (`runs.ex:308-311`); `run:batch_logs`: one `LogAppended` per line (`runs.ex:336-338`)
- `run:complete`: the failure alert is evaluated in the channel process (`run_channel.ex:127-132`), starting flow-failure-alert-email for a non-success run (`failure_alerter.ex:12-17`)
- Receiving page: replaces the run (`streaming.ex:120-127`), adds or replaces a step and re-sorts by start time (`streaming.ex:30-46`, `:89-94`), reloads the selected step's dataclips (`show.ex:349-360`), pushes `logs-<run_id>` to the LogViewer hook (`streaming.ex:140-150`)

**Deferred side effects**
- none

**External, non-transactional effects**
- PubSub broadcasts are cluster-wide (`lightning.ex:25-27`) and are not rolled back with the transaction that sent them (6.2)
- The failure alert email on `run:complete` (owned by flow-failure-alert-email)

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: The run page follows a run as it executes
  In order to see whether my data is getting through
  As anyone on the project watching a run
  I want the run page to update as the worker reports progress

  @S01 @pending
  Scenario: A claimed run shows it is starting and is no longer cancellable
    # Value: people know a worker has picked the run up, and are not offered a cancel that can no longer succeed.
    Given I am an editor with run "R" of workflow "Intake" open
    And "R" is "Enqueued" with a "Cancel" action
    When a worker claims "R"
    Then eventually the status reads "Starting"
    And the "Cancel" action is gone
    # worker_channel.ex:45-49; queue.ex:35-69; runs.ex:252-289; streaming.ex:120-127; show.ex:189-203
    # shared-run-components S01 owns the labels, S10 owns clicking cancel after the claim
    # show_test.exs:103-110 claims with Repo.update!, which broadcasts nothing (6.5)

  @S02 @pending
  Scenario: A started run shows when it started and counts its duration
    # Value: people can see the run is executing and for how long, without refreshing.
    Given I have run "R" open while it is "Starting"
    When the worker sends "run:start" for "R"
    Then eventually the status reads "Running"
    And "Started" shows the start time
    And "Duration" counts up from the start time
    # run_channel.ex:112-120; handlers.ex:27-33; runs.ex:226-250, :269-289; streaming.ex:120-127
    # show.ex:150-157, :181-186; components.ex:24-33; ElapsedIndicator.ts:22-41
    # show_test.exs:112-117 asserts "Running"

  @S03 @pending
  Scenario: A step appears in the list when it starts
    # Value: people see which job is executing right now.
    Given I have run "R" open while it is "Running" with no steps
    When the worker starts step "Fetch" and then step "Transform"
    Then eventually the step list shows "Fetch" then "Transform", in the order they started
    And each step's duration counts up from its start time
    # run_channel.ex:193-216; handlers.ex:238-246, :270-277; streaming.ex:30-46, :89-94, :129-138; show.ex:206-225
    # show_test.exs:119-135, :182-199 assert the job name and data-start-time

  @S04 @pending
  Scenario: A completed step shows its outcome
    # Value: people spot the failing step the moment it fails.
    Given I have run "R" open with step "Fetch" running
    When the worker completes "Fetch" with reason "fail"
    Then eventually "Fetch" shows a failure icon and its final duration
    And when another step completes with reason "success" it shows a success icon
    # run_channel.ex:218-234; handlers.ex:464-501; streaming.ex:30-46, :129-138
    # shared-run-components S02 owns the icons
    # show_test.exs:189-192 asserts "text-green-500" after a successful completion

  @S05 @pending
  Scenario: The selected step's output appears when it completes
    # Value: people watching a step see the data it produced as soon as it exists, without reselecting it.
    Given I have run "R" open with step "Fetch" running and selected
    And the "Output" tab shows "Nothing yet"
    When the worker completes "Fetch" with an output
    Then eventually the "Output" tab shows that output
    # handlers.ex:464-473, :541-556; streaming.ex:67-77, :129-138; show.ex:349-360; viewers.ex:271-288
    # show_test.exs:158-180, :201-222

  @S06 @pending
  Scenario: Log lines appear as the worker sends them
    # Value: people read what the job is printing while it runs, which is where a failure first shows.
    Given I have run "R" open while it is "Running" and nothing has been logged
    When the worker sends the log line "Fetched 12 patients"
    And then sends "Posted batch 1" and "Posted batch 2" in one batch
    Then eventually the "Log" tab shows all three lines in time order
    # run_channel.ex:236-258; runs.ex:292-341; streaming.ex:140-150; log-viewer/index.ts:35-44; store.ts:158-173
    # show_test.exs:137-144 asserts one push event per line (single lines only)

  @S07 @pending
  Scenario: Lines logged while the existing log is loading appear once, in order
    # Value: people never read a duplicated or out-of-order log while a long run is still writing to it.
    Given run "R" has already logged 500 lines and is still running
    When I open the run page while the worker keeps logging
    Then the "Log" tab shows every line exactly once, in time order
    # streaming.ex:165-196 (subscribe before streaming the stored lines), :140-150; store.ts:158-173 (dedupe by id, sort by timestamp)
    # assets/test/log-viewer/store.test.ts:40 deduplicates by id

  @S08 @pending
  Scenario: A completed run shows its outcome, finish time and final output
    # Value: people watching a run learn how it ended and can open what it produced, without reloading.
    Given I have run "R" open while it is "Running"
    When the worker completes "R" with state "success" and a final output
    Then eventually the status reads "Success"
    And "Finished" shows the finish time and "Duration" stops counting
    And "Final Output" links to the stored output
    And when "R" completes with state "failed" instead, the flow "flow-failure-alert-email" starts
    And open history pages are updated through "flow-history-live-updates"
    # run_channel.ex:122-142; handlers.ex:92-115, :171-213; runs.ex:269-289; streaming.ex:120-127
    # show.ex:158-190; ElapsedIndicator.ts:28-34
    # show_test.exs:236-245 asserts "Failed" with no final output link; :248-327 covers the link on load

  @S09 @pending
  Scenario: A run that finishes without logging says so
    # Value: people can tell a run that logged nothing from a log that is still loading.
    Given I have run "R" open while it is "Starting" and nothing has been logged
    When "R" completes with state "crashed" without sending any log line
    Then eventually the "Log" tab says "No logs were received for this run."
    # streaming.ex:120-127; viewers.ex:70-77; runs/run.ex:46-54

  @S10 @pending
  Scenario: Another run's progress never reaches this page
    # Value: one run's logs and data, possibly from another project, never appear on a page about a different run.
    Given I have run "R" open
    When a worker starts a step and logs a line for run "S"
    Then nothing on the page changes
    # runs/events.ex:29-68 (topic run_events:<run_id>); streaming.ex:168
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The waiting message sits inside the `phx-update="ignore"` log container, so it is never re-rendered after the first paint | `viewers.ex:61-66`, `:92-113` | a run opened while "Enqueued" keeps saying "Waiting for worker" after it is claimed and started, until its first log line arrives (same row as run-show 6.1). Inferred from code | fix |
| The page subscribes only after the async load has read the run, so events sent between that read and the subscribe are lost | `streaming.ex:15-27`, `:165-168` | a run that changes state in that window keeps its old state until its next change; one that completes in it shows "Running" with a counting duration until reload. A missed step start heals on that step's completion (`streaming.ex:30-46`); logs are not lost because they are streamed after the subscribe. Inferred, not run | fix |
| A lost run's unfinished steps are marked lost with `update_all` and no step event | `runs.ex:412-435`, `:530-539`; `janitor.ex:36-48` | the run reads "Lost" but its running step keeps a pending icon and a counting duration until reload. Inferred from code | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `RunUpdated` is broadcast from inside an outer transaction for a claim, a completion and a lost-run sweep; the run page renders the payload, so it is not exposed to the stale-read problem in flow-history-live-updates 6.1, but would show a state that is later rolled back | `queue.ex:35-69`; `handlers.ex:101-114`; `runs.ex:422-435`, `:269-289` | decide |
| `RunUpdated` replaces the run but not `@workflow`, so the version chip stays as computed at mount (owned by run-show 6.2) | `streaming.ex:120-127` | decide |
| Live log lines are filtered by the viewer's saved level like stored ones | `store.ts:158-173` | preserve |
| Steps are re-sorted by `started_at` on each event; a step whose start the page missed is inserted in order when it completes | `streaming.ex:30-46`, `:89-94` | preserve |
| No per-event permission check; losing access is handled by the shared-project-scope remount | `streaming.ex:110-151` | preserve |
| Broadcasts are cluster-wide, so a page on another node is updated too | `lightning.ex:25-27` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| RunChannel browser join and its event forwarders | `run_channel.ex:67-95`, `:260-323` | joined by the workflow editor's run viewer, not run-show; that half belongs to workflow-editor-run-viewer |
| `DataclipUpdated` handler | `show.ex:406-409` | a no-op on this page (flow-zero-persistence-runs 6.1) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Stored log lines are streamed inside `Repo.transaction` with the default timeout; a stream that outlasts it fails the async silently while live lines keep arriving | `streaming.ex:181-195` | yes, the start of a long log can be missing while new lines show. Inferred, not run | decide |
| A batch of N log lines sends N broadcasts and N push events, each re-sorting and reformatting the whole log in the browser | `runs.ex:336-338`; `streaming.ex:140-150`; `store.ts:158-173` | possibly, on chatty jobs | decide |
| Each step event preloads `:job` again, and while the selected step has no output, each step event re-queries both its dataclips | `streaming.ex:30-34`, `:55-77`; `show.ex:349-360` | no | preserve |
| The worker's `run:complete` reply waits for the failure alert to be evaluated in the channel process | `run_channel.ex:125-132` | no | preserve |

### 6.5 Things seen but not understood

- No test drives the worker channels through to the open page: `show_test.exs:67-246` calls `Runs` functions directly, and sets the claim with `Repo.update!`, which broadcasts nothing (`show_test.exs:103-110`), so S01 and S09 have no coverage.
- The claim arrives on `worker:queue`, not the run channel; it is listed as a surface ahead of the lead's entry.
- The janitor's lost-run sweep (`janitor.ex:36-48`) and a cancel from another tab (`runs.ex:466-492`) reach the page through the same `RunUpdated` handler but are not in the lead's surfaces; shared-run-components proposed this flow for the cancel case.
- Whether the first `logs-<run_id>` event reaches a LogViewer hook created in the same patch (a finished run switching from "No logs were received" to the viewer) was not verified (run-show 6.5).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the page subscribe before loading the run, so no event is missed between the two (6.1)?
- Should a lost-run sweep broadcast its step changes (6.1)?
- Should the janitor and cross-tab cancel be listed as surfaces of this flow (6.5)?
- Should long logs be streamed outside a single transaction, or paged (6.4)?

## Proposed flows

none (referenced: flow-history-live-updates, flow-failure-alert-email, flow-zero-persistence-runs)

## Proposed shared

none (referenced: shared-project-scope, shared-run-components; the LogViewer store behaviour cited in S06 and S07 belongs to shared-log-viewer, proposed by run-show and not yet in annotations/shared/)
