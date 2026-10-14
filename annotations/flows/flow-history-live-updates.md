---
id: flow-history-live-updates
type: flow
title: Run and work order changes reaching an open history page
status: not-started
owner:

trigger:
  entry: controller:webhooks                 # any of the sources below can start it
  exit: history-work-orders
  surfaces:
    - controller:webhooks                    # POST /i/*path, WebhooksController.create (router.ex:332-336, webhooks_controller.ex:39-69)
    - controller:worker-channel             # "claim" on worker:queue (worker_channel.ex:45-49); the hop that removes the cancel button
    - controller:run-channel                # "run:start", "run:complete" on run:<id> (run_channel.ex:112-130)
    - oban:RetryManyWorkOrdersJob           # retry_many_workorders_job.ex:1-26
    - oban:CancelManyWorkOrdersJob          # cancel_many_work_orders_job.ex:1-43
    - history-work-orders                   # a second tab: cancel, cancel run, rerun from a step
    - pubsub:project:<project_id>           # Lightning.WorkOrders.Events (workorders/events.ex:24-60)
    - history-work-orders                   # the open page that receives the events
    - workflow-editor-manual-run   # added by lead
  reachable_when:
    - the receiving page is history-work-orders with live_action :index (index.ex:275, :306-309, :325-328); the channel logs tab ignores these events (index.ex:360-368)
    - the receiving page passed the project scope gate (shared-project-scope); it subscribes in mount (index.ex:82)

inherits:
  - shared-project-scope            # who can open the receiving page, membership remount; not repeated here

url_params: []                      # the page's filters decide whether a new work order is admitted; owned by history-work-orders

config_variants:
  default: {}                                                         # read under this variant
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action returns {:error, :too_many_runs, _}> }

inventory:
  routes:
    - post /i/*path  WebhooksController :create        # owned by its own capability annotation; listed as the entry hop
  events:
    - RunLive.Index handle_info Events.RunCreated, Events.RunUpdated (index.ex:275-298)       # owned by history-work-orders; the exit hop
    - RunLive.Index handle_info Events.WorkOrderCreated (index.ex:306-322)
    - RunLive.Index handle_info Events.WorkOrderUpdated (index.ex:325-348)
  js_hooks: []
  policies: []                      # the receiving side has no policy check; the topic is the project boundary
  workers:
    - Lightning.WorkOrders.RetryManyWorkOrdersJob
    - Lightning.WorkOrders.CancelManyWorkOrdersJob
  api_endpoints:
    - channel worker:queue "claim"
    - channel run:<id> "run:start", "run:complete"
  emails: []
  config:
    - :lightning, Lightning.Extensions, :run_queue (config.exs:44, FifoRunQueue)
    - :lightning, Lightning.Extensions, :usage_limiter (via WorkOrders.limit_run_creation)
  not_reachable_here:
    - WorkOrders.Events.subscribe/0 and the "all_events" copy of RunCreated (workorders/events.ex:41, :51-53), consumed by WorkListener (work_listener.ex:36, :48)
    - WorkflowChannel's handlers for the same project topic (workflow_channel.ex:79, :981-1050), used by the editor's run panel
    - Runs.Events step_started / step_completed (handlers.ex:242, :469), published on the run topic, not the project topic

related:
  - lib/lightning/workorders/events.ex
  - lib/lightning/work_orders.ex
  - lib/lightning/runs.ex
  - lib/lightning/runs/queue.ex
  - lib/lightning/runs/handlers.ex
  - lib/lightning_web/live/run_live/index.ex
  - lib/lightning_web/live/run_live/workorder_component.ex
  - lib/lightning_web/controllers/webhooks_controller.ex
  - lib/lightning_web/channels/worker_channel.ex
  - lib/lightning_web/channels/run_channel.ex
  - test/lightning_web/live/run_live/index_test.exs
  - test/lightning_web/live/work_order_live_test.exs
flows: []
---

## 1. Purpose

People watching History during an incident need it to reflect what is happening now: new data
arriving, runs being picked up by a worker, runs finishing, and the retries or cancellations they
or a colleague started. Without live updates they act on stale rows, for example trying to cancel
a run a worker is already delivering, or retrying a work order that is already being retried.

## 2. What it does

A webhook arrival, a worker claiming, starting or finishing a run, a background retry or cancel job, or an action in another tab → WorkOrders event on the project topic → every open history page on that project adds the new work order (if its filters admit it) or refreshes the changed row, including its state, runs and cancel and retry buttons.

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-49`, `:160-172` via `index.ex:88-93` (receiving
side); each source's own gate for the starting side.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See live updates on an open history page | yes | yes | yes | yes | no | yes, when support access is on |
| See the row cancel button appear or disappear with state | no | yes | yes | yes | no | yes, when support access is on |
| Start the flow from another tab (cancel, cancel run, rerun) | no | yes | yes | yes | no | yes, when support access is on |
| Start the flow by bulk retry or "cancel all matching" (Oban jobs) | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Webhook and worker hops are not user actions: the webhook needs an enabled trigger and passes the trigger's auth and rate limit (`webhooks_controller.ex:39-48`); worker hops need a worker token and a run token (`worker_channel.ex:18-42`, `run_channel.ex:36-97`).
- Only pages on the same project receive the event: the topic is `project:<project_id>` (`workorders/events.ex:60`, `index.ex:82`).
- `can_run_workflow` is read once at mount (`index.ex:88-93`); a role change mid-session is handled by the shared-project-scope remount.

## 4. What it touches

**Reads**
- Receiving page: `work_orders`, `runs`, `steps`, `jobs`, `dataclips`, `workflows`, `workflow_snapshots`, `triggers`, `webhook_auth_methods` (forced preload per event, `index.ex:277-295`, `:329-345`); a filtered search per new work order (`index.ex:311-321`)

**Writes, by hop**
- Webhook: `dataclips`, `work_orders`, `runs` in one transaction (`work_orders.ex:104-129`); with no run when the limiter refuses (`webhooks_controller.ex:221-231`, `work_orders.ex:108-119`)
- Worker claim: `runs.state` to `claimed`, `claimed_at`, `worker_name` (`queue.ex:35-69`); `work_orders.state`, `last_activity` (`runs.ex:259-265`, `work_orders.ex:830-838`, `:895-905`)
- Run channel start and complete: `runs` state and timestamps, then `work_orders.state` the same way (`handlers.ex:27-33`, `:92-117`, `runs.ex:226-289`)
- RetryManyWorkOrdersJob: `runs` insert and `work_orders.state`, `last_activity` per work order (`work_orders.ex:767-828`)
- CancelManyWorkOrdersJob: `runs.state` to `cancelled`, 100 at a time, then `work_orders.state` (`runs.ex:500-527`)
- Another tab: cancel (`runs.ex:466-492`, `work_orders.ex:520-530`), rerun from a step (`work_orders.ex:361-400`)
- Receiving page: none

**Immediate side effects** (broadcasts on `project:<project_id>`)
- Webhook: `RunCreated` per run, then `WorkOrderCreated` (`work_orders.ex:151-157`); `RunCreated` also goes to `all_events` (`workorders/events.ex:38-42`)
- Any run state change through `update_runs/2`: `WorkOrderUpdated` per run from inside the transaction (`runs.ex:259-265`, `work_orders.ex:833-837`), then `Runs.Events.run_updated` on the run topic and `WorkOrders.Events.run_updated` on the project topic after it (`runs.ex:266-289`)
- Retry from start: `WorkOrderUpdated` per work order, then `RunCreated` per run (`work_orders.ex:907-923`)
- Rerun from a step: `WorkOrderUpdated` and `RunCreated` (`work_orders.ex:393-397`)
- Receiving page: replaces the matching row (`index.ex:898-919`) or prepends the new work order (`index.ex:881-896`); the row component re-derives its last run and buttons (`workorder_component.ex:16-75`, `:250-289`)

**Deferred side effects**
- Bulk retry and "cancel all matching" from History insert the Oban jobs on queue `scheduler` (`work_orders.ex:454-486`, `:540-551`); their broadcasts reach pages open when the job runs, including the page the acting tab navigated to (`index.ex:427-430`, `:560-582`)

**External, non-transactional effects**
- PubSub broadcasts are cluster-wide (`lightning.ex:25-27`) and are not rolled back with the transaction that sent them (see 6.1)

**Depends on config**
- `usage-limited`: a webhook still creates a rejected work order with no run, and it is broadcast like any other (`webhooks_controller.ex:217-231`, `work_orders.ex:108-119`)
- Run queue adapter: the default `FifoRunQueue` claims through `Runs.Queue.claim/4` (`config.exs:44`, `fifo_run_queue.ex:20-24`); another adapter would have to call `update_runs/2` for the claim to reach the page

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: History stays current while it is open
  In order to act on what is actually happening to my project's data
  As a member watching the history page
  I want new work orders and run changes to appear without reloading

  @S01 @pending
  Scenario: A webhook arrival that matches my filters appears at the top
    # Value: people watching an incident see new data arrive as it is received.
    Given I have the history page of project "Malawi HIV" open, filtered to workflow "Intake"
    When a request is posted to the webhook of "Intake"
    Then eventually the new work order appears at the top of the list
    # webhooks_controller.ex:39-69; work_orders.ex:104-129, :151-157; workorders/events.ex:24-29
    # index.ex:306-322, :881-896
    # test/lightning_web/live/work_order_live_test.exs:1750-1825 (broadcast sent by hand, not through the controller)

  @S02 @pending
  Scenario: A webhook arrival that doesn't match my filters is not added
    # Value: a filtered investigation is not interrupted by unrelated traffic.
    Given I have the history page open, filtered to workflow "Intake"
    When a request is posted to the webhook of workflow "Sync"
    Then the list does not change
    # index.ex:311-321
    # test/lightning_web/live/work_order_live_test.exs:1827-1837

  @S03 @pending
  Scenario: The cancel button disappears once a worker claims the run
    # Value: people are not offered a cancel for a run a worker is already delivering.
    Given I am an editor with the history page open
    And work order "W" is pending with an available run, showing a cancel button
    When a worker claims the run
    Then eventually "W" shows as running
    And "W" has no cancel button
    # worker_channel.ex:45-49; fifo_run_queue.ex:20-24; queue.ex:35-69; runs.ex:252-289; work_orders.ex:830-838
    # index.ex:325-348, :898-907; workorder_component.ex:250-268; workorders/query.ex:17-21, :78-79
    # test/lightning_web/live/run_live/index_test.exs:1403-1443 (sets the run to claimed and calls update_state directly)

  @S04 @pending
  Scenario: A finished run shows its outcome and offers a retry
    # Value: people learn a delivery failed as soon as it does, and can retry without reloading.
    Given I am an editor with the history page open
    And work order "W" is running
    When the worker reports the run complete with state "failed"
    Then eventually "W" shows "Failed"
    And "W" shows its retry button
    # run_channel.ex:122-130; handlers.ex:92-117; runs.ex:252-289
    # index.ex:275-298, :325-348; workorder_component.ex:269-289
    # test/lightning_web/live/work_order_live_test.exs:1684-1748 (RunUpdated refreshes the expanded row's steps)

  @S05 @pending
  Scenario: A background retry shows each work order going back to the queue
    # Value: after a bulk retry people can see the retries were actually created and follow them.
    Given I am an editor and I retried all 25 matching failed work orders from the start
    When the background retry job runs
    Then eventually each of those work orders shows "Enqueued" with a new latest run
    And each shows a cancel button
    # work_orders.ex:454-486, :767-828, :907-923; retry_many_workorders_job.ex:20-26
    # index.ex:275-298, :325-348; components.ex:162-174
    # test/lightning_web/live/work_order_live_test.exs:1645-1682 (RunCreated adds the run to an expanded row)

  @S06 @pending
  Scenario: A background cancel shows the work orders as cancelled
    # Value: people see that the backlog they asked to stop was actually stopped.
    Given I am an editor and I chose "Cancel up to 3 matching"
    When the background cancel job runs
    Then eventually the 3 work orders show "Cancelled"
    And none of them has a cancel button
    # cancel_many_work_orders_job.ex:19-42; runs.ex:500-527, :252-289; index.ex:325-348

  @S07 @pending
  Scenario: An action in another tab shows in this one
    # Value: two people working the same incident don't act on rows the other has already changed.
    Given "amara@example.org" and I both have the history page of "Malawi HIV" open
    And work order "W" is pending
    When "amara@example.org" cancels "W"
    Then eventually my tab shows "W" as cancelled without a cancel button
    When "amara@example.org" reruns a failed work order "F" from a step
    Then eventually my tab shows a new latest run for "F"
    # index.ex:587-620 (acting tab); work_orders.ex:520-530, :361-400; runs.ex:466-492
    # index.ex:275-298, :325-348 (this tab)

  @S08 @pending
  Scenario: Changes in another project never reach this page
    # Value: one project's work orders are never shown to another project's members.
    Given I have the history page of "Malawi HIV" open
    When a request is posted to a webhook of project "Kenya TB"
    Then the list does not change
    # workorders/events.ex:24-29, :55-60; index.ex:82; runs.ex:500-515 (background cancel is also scoped by project)

  @S09 @pending @variant:usage-limited
  Scenario: A payload refused a run by the plan limit still appears, as rejected
    # Value: people can see data that was received but not processed because of the plan limit.
    Given the usage limiter refuses new runs
    And I have the history page open
    When a request is posted to the webhook of "Intake"
    Then eventually a work order with state "Rejected" appears at the top
    And it has no runs to expand
    # webhooks_controller.ex:217-231, :39-60; work_orders.ex:108-119, :151-157; index.ex:306-322; workorder_component.ex:250
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `WorkOrderUpdated` is broadcast from inside the run update transaction, and for a claim, a run completion and the janitor's lost-run sweep `RunUpdated` is too, because `update_runs/2`'s transaction is nested in an outer one. The page reloads the row on its own connection and can read the state from before the commit; no later event corrects it until the run changes again. A rolled-back change is still broadcast | `runs.ex:257-289`; `work_orders.ex:830-838`; `queue.ex:35-69`; `handlers.ex:101`; `janitor.ex:41-60` | a cancel button that stays after a claim, or a row stuck on "Running" after the run finished, until something else changes; the S03 test calls `update_state` outside a transaction so it doesn't see this | fix |
| Selected work orders keep the state they had when ticked; live updates refresh rows but not `selected_work_orders`, so bulk actions are gated on old states | `index.ex:453-478`, `:486-500`, `:789-817`, `:898-907` | bulk "Cancel" stays enabled after the selection was claimed (then "Cancelled 0 runs"); bulk "Retry" stays disabled after the selection finished | fix |
| `WorkOrderCreated` is appended without checking the work order is already listed, and while the first load is still running it is appended to the empty page | `index.ex:194-199`, `:228-237`, `:306-322`, `:881-896`; `index.html.heex:642-644` | if the work order lands between the search and the event, a duplicate row with the same component id (likely a crash and remount); during loading the list briefly shows only the new work order | fix |
| `RetryManyWorkOrdersJob` logs a failed chunk and returns `:ok`, so Oban never retries it and no event is broadcast, after the page already reported every work order as enqueued | `retry_many_workorders_job.ex:20-26`; `work_orders.ex:454-486`, `:811-818` | up to 100 work orders never retried and never updated on the page, with a success flash | fix |

### 6.2 Quirks and implementation details

Prepending new work orders regardless of page and sort, and replacing rows that no longer match
the filters, are owned by history-work-orders 6.2 (`index.ex:306-322`, `:325-348`) and not repeated here.

| What | Where | Disposition |
|------|-------|-------------|
| Step progress is not live: step started and completed events go to the run topic only, so an expanded row gets new steps only when the run's state next changes | `handlers.ex:242`, `:469`; `index.ex:275-298` | decide |
| A webhook emits `RunCreated` before `WorkOrderCreated`, so the run event finds no row and is a no-op; the work order arrives with its run on the second event | `work_orders.ex:151-157`; `index.ex:898-919` | preserve |
| Event payloads are only used for their ids: each handler re-preloads the whole work order with `force: true` | `index.ex:277-295`, `:329-345` | preserve |
| The page subscribes in `mount` without a `connected?` guard, so the static render's request process subscribes too | `index.ex:82` | decide |
| The channel logs tab receives the same events and drops them | `index.ex:360-368` | preserve |
| Broadcasts are cluster-wide, so a page on another node is updated too | `lightning.ex:25-27` | preserve |
| `RunCreated` is also sent to `all_events` to nudge workers that work is available | `workorders/events.ex:38-42`; `work_listener.ex:36`, `:48` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `project_id` on `WorkOrderCreated` and `RunCreated`, `from_rejected_workorder` on `RunCreated` | `workorders/events.ex:6`, `:16` | not read by the history page; whether another subscriber reads them is out of this flow |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No batching or debounce: a retry chunk of 100 sends 100 `WorkOrderUpdated` and 100 `RunCreated`, and each open page reloads a full work order graph for each, in its own process | `work_orders.ex:907-923`; `index.ex:275-298`, `:325-348` | possibly, as a sluggish page during bulk retries | decide |
| Background cancel works 100 runs per update, each update broadcasting per run | `cancel_many_work_orders_job.ex:17`, `:30-42`; `runs.ex:276-289` | no | preserve |

### 6.5 Things seen but not understood

- Whether a duplicate live component id crashes the LiveView in production or only warns in dev and test was not checked (6.1, `index.html.heex:642-644`).
- The cron scheduler (`scheduler.ex:90`, `:106`), manual runs from the editor (`workflow_live/helpers.ex:59`) and the janitor (`janitor.ex:41-60`) publish to the same topic and reach the page the same way, but are not in the lead's surfaces.
- No test drives any real source (webhook, channel, Oban job) through to the open page; every live update test broadcasts or calls `update_state` by hand.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should broadcasts move after commit so the page can't read pre-commit state (6.1)?
- Should step progress reach the history page live, or only the run page (6.2)?
- Should live updates refresh the selection, or clear it when a selected work order changes state (6.1)?
- Should the scheduler, manual runs and the janitor be listed as surfaces of this flow (6.5)?

## Proposed flows

none

## Proposed shared

none
