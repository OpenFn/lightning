---
id: history-work-orders
type: view
title: History › Work orders
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/history
  new_route: /projects/:project_id/history
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope)
    - live_action is :index (the same LiveView also serves /history/channels, catalogued as history-channel-logs)

inherits:
  - shared-project-scope            # index.ex:67
  - shared-usage-limits-banner      # index.ex:68, index.html.heex:2-8
  - shared-authenticated-session
  - shared-project-header
  - shared-run-components
  - shared-local-datetime

url_params:
  - name: filters
    set_by: none (bare visit from the side menu, menu.ex:72)
    effect: when the whole `filters` param is absent, the page applies a 30-day last-activity window and searches logs only (index.ex:133, :157-169, :183)
  - name: filters[workorder_id]
    set_by: history-work-orders (row id link, workorder_component.ex:181), run-show (run_live/show.ex:126), workflow-editor-run-viewer (RunTabPanel.tsx:66), email:failure-alert (pipeline/failure_alerter.ex:78)
    effect: lists only that work order, shows a "Work order: <short id>" chip, and expands its row with every run visible (index.ex:930-942, index.html.heex:288-296)
  - name: filters[workflow_id]
    set_by: workflows-index (dashboard_components.ex:214, :241), workflow-editor (collaborative-editor/utils/navigation.ts:24), email:digest (accounts/user_notifier.ex:330-341)
    effect: workflow chip shows that workflow
  - name: filters[date_after], filters[date_before]
    set_by: email:digest (user_notifier.ex:330-341), workflows-index (dashboard_components.ex:509, :537)
    effect: last activity window
  - name: filters[<status>]=true (pending, running, success, failed, crashed, cancelled, killed, exception, lost, rejected)
    set_by: workflows-index (dashboard_components.ex:241, :537)
    effect: status chip and work order state filter (search_params.ex:136, invocation.ex:719-723)
  - name: filters[run_status][], filters[run_date_after], filters[run_date_before]
    set_by: workflow-health (assets/js/health/charts/VolumeBars.tsx:261-263)
    effect: "Run status" and "Run created … UTC" chips; only work orders with a matching run are listed (invocation.ex:757-791)
  - name: filters[error_signature_exit_reason], filters[error_signature_error_type], filters[error_signature_job_id]
    set_by: workflow-health (assets/js/health/charts/TriageTable.tsx:192)
    effect: error signature chip; lists only failed work orders whose latest run carries that signature (invocation.ex:801-876)
  - name: filters[search_term], filters[id|body|log|dataclip_name]
    set_by: history-work-orders
    effect: text search over the chosen fields
  - name: filters[sort_by], filters[sort_direction]
    set_by: history-work-orders
    effect: sorts by created or last activity
  - name: page, page_size
    set_by: pagination bar (pagination.ex:159-213)
    effect: Scrivener page; page_size defaults to 10, capped at 100 (repo.ex:6)

config_variants:
  default: {}                                                    # verified against this
  experimental-features: { user.preferences.experimental_features: true }
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action returns {:error, _, %{text: _}}> }

inventory:
  routes:
    - live /projects/:project_id/history  RunLive.Index :index
  events:
    - RunLive.Index#rerun
    - RunLive.Index#bulk-rerun
    - RunLive.Index#toggle_selection
    - RunLive.Index#toggle_all_selections
    - RunLive.Index#apply_filters
    - RunLive.Index#sort
    - RunLive.Index#invalid-rerun:<message>
    - RunLive.Index#bulk-cancel
    - RunLive.Index#cancel
    - RunLive.Index#cancel-run
    - RunLive.Index#show-export-modal
    - RunLive.Index#close-export-modal
    - RunLive.Index#confirm-export
    - RunLive.Index handle_info Events.RunCreated, Events.RunUpdated, Events.WorkOrderCreated, Events.WorkOrderUpdated (live_action :index)
    - RunLive.Index handle_async :load_workorders
    - WorkOrderComponent#toggle_details
    - WorkOrderComponent#toggle_runs
    - RerunJobComponent#select_job
  js_hooks:
    - Tooltip
    - CheckboxIndeterminate          # assets/js/hooks/index.ts:862
    - ElapsedIndicator               # assets/js/hooks/ElapsedIndicator.ts
  policies:
    - Lightning.Policies.ProjectUsers :run_workflow
    - Lightning.Policies.ProjectUsers :edit_data_retention
  workers:
    - Lightning.WorkOrders.RetryManyWorkOrdersJob
    - Lightning.WorkOrders.CancelManyWorkOrdersJob
    - Lightning.WorkOrders.ExportWorker
  api_endpoints: []
  emails:
    - email:history-export-complete   # sent later by ExportWorker; owned by flow-history-export
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (via WorkOrders.limit_run_creation)
    - user.preferences.experimental_features
  not_reachable_here:
    - RunLive.Index handle_info {:channel_logs_filter, _} and the :channel_logs ignore clause (index.ex:350-368), owned by history-channel-logs
    - RunLive.Index handle_params :channel_logs clause (index.ex:172-179), owned by history-channel-logs
    - RunLive.Components.step_item/1, step_list/1, detail_list/1, list_item/1, loading_filler/1, channel_state_pill/1 (components.ex:52-89, :140-160, :176-278, :316-345), used by run-show and history-channel-logs

related:
  - history-channel-logs
  - run-show
  - dataclip-show
  - workflow-health
  - workflows-index
  - project-settings-data-storage
  - project-settings-history-exports
flows:
  - flow-history-export
  - flow-history-live-updates
  - flow-workflow-health-drilldown
  - flow-failure-alert-email
  - flow-digest-email
  - flow-dashboard-history-drilldown
  - flow-webhook-auth-method-enforcement
  - flow-zero-persistence-runs
  - flow-open-run-in-editor
---

## 1. Purpose

Everyone on a project uses History to find out what happened to the data their workflows
received: which work orders arrived, how each run went, and which steps failed. Editors use it to
recover from failures by retrying work orders, rerunning from a failed step, cancelling runs that
haven't started, and exporting the record. Without it, a failed delivery of health data would go
unnoticed or could only be repaired by someone with database access.

## 2. What it does

- Members see the project's work orders, newest activity first, for the last 30 days by default
- Members filter by workflow, status, received date and last activity, and clear any filter chip
- Members search work orders by run logs, inputs, IDs and dataclip names
- Members sort by created or last activity
- Members expand a work order to see its runs and steps, and open the run, input, workflow version or step
- Members arriving from another page see that page's filters as chips (work order, health drill-down)
- Editors retry a work order from the start, singly or in bulk
- Editors rerun a run from a chosen step, singly or for many work orders
- Editors cancel work orders, individual runs, or all matching work orders, when the runs are not yet claimed
- Editors export the matching history (finishes by email)
- Anyone sees why a work order whose input was wiped by retention can't be retried, and admins get a link to change retention
- Users with experimental features see a tab for channel logs

## 3. Who can do what

From `lib/lightning/policies/project_users.ex:29-49`, `:134`, `:160-172`, and the
`require_run_workflow/2` gate (`index.ex:694-708`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the page, filter, search, sort, expand | yes | yes | yes | yes | no | yes, when support access is on |
| Retry from start (single or bulk) | no | yes | yes | yes | no | yes, when support access is on |
| Rerun from a step (single or bulk) | no | yes | yes | yes | no | yes, when support access is on |
| Cancel a work order, a run, or in bulk | no | yes | yes | yes | no | yes, when support access is on |
| Export history | no | yes | yes | yes | no | yes, when support access is on |
| Get the data storage settings link in retention tooltips | no | no | yes | yes | no | no |

**Preconditions beyond role**
- The project's MFA requirement must be met; otherwise every action above is denied (`project_users.ex:134`).
- Retry and select need the work order's input dataclip not to be wiped (`workorder_component.ex:120`, `:270`, `:481-483`; `work_orders.ex:969-975`).
- Rerun from a step needs the step's input dataclip not to be wiped and its job to still exist (`components.ex:506-514`; `work_orders.ex:331-357`).
- Retries need the workflow not to be deleted (`work_orders.ex:339-345`, `:961-967`).
- Rerun and run cancel need the run to belong to this project (`index.ex:383-386`, `cancel_helper.ex:310-315`, `runs.ex:74-84`).
- Cancel only reaches runs in state `available` (`runs.ex:466-492`, `:506-527`).
- Bulk cancel needs every selected work order to be pending; bulk retry needs every selected work order to be finished (`index.ex:789-817`).
- Rerun from a step in bulk needs every selected work order to belong to one workflow (`index.html.heex:548`, `:704-713`).
- New runs are subject to the usage limiter (`work_orders.ex:84-92`).

## 4. What it touches

**Reads**: `work_orders`, `workflows`, `runs`, `steps`, `run_steps`, `dataclips`, `log_lines`, `jobs`, `workflow_snapshots`, `triggers`, `webhook_auth_methods`, `edges`, `projects`, `project_users`, `users`

**Writes**
- `runs` insert on retry (`work_orders.ex:366-392`, `:767-828`); `runs.state` to `cancelled` (`runs.ex:466-527`)
- `run_steps` insert for steps carried into a retry (`work_orders.ex:404-425`, `:883`)
- `work_orders.state` and `last_activity` (`work_orders.ex:895-905`, `runs.ex:261-265`)
- `project_files` insert, status `enqueued` (`invocation.ex:1323-1331`)
- `audit_events` insert, item `history_export`, event `requested` (`invocation.ex:1313-1322`, `workorders/export_audit.ex:5-8`)
- `oban_jobs` insert: `RetryManyWorkOrdersJob`, `CancelManyWorkOrdersJob`, `ExportWorker`

**Immediate side effects**
- Broadcasts `WorkOrders.Events.work_order_updated` and `run_created` on the project topic after a step rerun (`work_orders.ex:385-388`)
- Broadcasts `Runs.Events.run_updated` and `WorkOrders.Events.run_updated` after a cancel (`runs.ex:269-287`)
- Subscribes the page to the project's work order events (`index.ex:82`)

**Deferred side effects**
- `RetryManyWorkOrdersJob` (queue `scheduler`, 5 attempts) creates one run per work order in chunks of 100 and broadcasts per work order (`work_orders.ex:454-486`, `:767-828`, `retry_many_workorders_job.ex:1-26`)
- `CancelManyWorkOrdersJob` (queue `scheduler`, 5 attempts) cancels available runs 100 at a time until none remain (`cancel_many_work_orders_job.ex:1-43`)
- `ExportWorker` (queue `history_exports`, 1 attempt) builds a zip and emails the requester (`export_worker.ex:55-95`); see flow-history-export

**External, non-transactional effects**
- Rendering a step killed with an unrecognised error type logs a warning and sends a Sentry message (`components.ex:592`, `:627-636`)

**Depends on config**
- Usage limiter adapter (`work_orders.ex:84-92`)
- The viewer's `experimental_features` preference (`index.ex:142-143`, `index.html.heex:649-653`)

**Product limits**
- With a search term, the count stops at 50 and shows "50+" with "(try more specific filters)"; only those 50 are reachable (`invocation.ex:44`, `:580-582`, `query_paginater.ex:65-81`, `index.html.heex:436-447`)
- The default view covers 30 days of last activity (`index.ex:162-163`)
- Ten work orders per page (`repo.ex:6`)
- The search query times out after 30 seconds and the list shows a load error (`invocation.ex:43`, `:577`, `index.html.heex:634-640`)
- Inputs larger than about 1MB may not match text search, as the input toggle's tooltip says (`index.ex:124-129`)

## 5. Scenarios

```gherkin
Feature: Work order history
  In order to know what happened to the data my workflows received, and to recover from failures
  As a member of a project
  I want to find work orders, inspect their runs, and retry, cancel or export them

  @S01 @pending
  Scenario: A bare visit shows the last 30 days of activity
    # Value: people land on recent work, and the chip tells them older work is filtered out.
    Given I am a viewer on project "Malawi HIV"
    And work order "A" had activity 5 days ago and work order "B" had activity 40 days ago
    When I visit "/projects/<project_id>/history"
    Then I see "A"
    And I do not see "B"
    And the last activity chip reads "Last activity after" a date 30 days ago
    # index.ex:133, :157-169, index.html.heex:207-224, invocation.ex:741-747

  @S02 @pending
  Scenario: Work orders from other projects never appear
    # Value: one project's health data is never shown to another project's members.
    Given I am an editor on project "Malawi HIV"
    And project "Kenya TB" has a work order "K"
    When I open the history page of "Malawi HIV"
    Then I do not see "K"
    # invocation.ex:675-685

  @S03 @pending
  Scenario: Filter by workflow
    # Value: people investigating one integration only see its work orders.
    Given project "Malawi HIV" has workflows "Intake" and "Sync" with work orders
    When I choose "Intake" from the workflow chip
    Then the chip reads "Workflow is Intake"
    And I only see work orders of "Intake"
    # index.html.heex:61-113, invocation.ex:713-717
    # test/lightning_web/live/run_live/index_test.exs:814-841

  @S04 @pending
  Scenario: Filter by several statuses
    # Value: people can pull up every kind of failure at once.
    Given project "Malawi HIV" has failed, crashed and successful work orders
    When I tick "Failed" and "Crashed" in the status chip
    Then the chip reads "Status in Failed, Crashed"
    And I see only failed and crashed work orders
    # index.html.heex:116-159, invocation.ex:719-723, search_params.ex:130-136
    # test/lightning_web/live/run_live/index_test.exs:895-912

  @S05 @pending
  Scenario: Filter by when the work order was received
    # Value: people can find the data that arrived during an incident window.
    Given work orders received on 1 March and 10 March
    When I set "Received after" to 5 March
    Then the received chip shows the range
    And I see only the 10 March work order
    # index.html.heex:161-203, invocation.ex:725-739

  @S06 @pending
  Scenario: Clearing a filter chip removes that filter
    # Value: people can widen a search without starting over.
    Given I have filtered by workflow "Intake"
    When I clear the workflow chip
    Then the chip reads "Workflow is any"
    And I see work orders of every workflow
    # pills.ex:119-176, index.ex:510-523
    # test/lightning_web/live/run_live/index_test.exs:842-869

  @S07 @pending
  Scenario: Search work orders by inputs and logs
    # Value: people can find the work order that carried a particular record or produced a particular log line.
    Given work order "A" has an input containing "eliaswalyba"
    And work order "B" has a log line containing "qassim"
    When I search for "eliaswalyba" with inputs and logs included
    Then I see "A" and not "B"
    When I search for "qassim" with inputs and logs included
    Then I see "B" and not "A"
    # index.html.heex:325-434, invocation.ex:901-973
    # test/lightning_web/live/work_order_live_test.exs:1063-1205

  @S08 @pending
  Scenario: A broad search tells me to narrow it
    # Value: people know the result count is partial and how to get a complete answer.
    Given 60 work orders have logs containing "error"
    When I search for "error" in run logs
    Then I see '50+ work orders with runs matching "error"'
    And I see "(try more specific filters)"
    # index.html.heex:436-447, invocation.ex:44, :580-582

  @S09 @pending
  Scenario: Sort by created date and toggle direction
    # Value: people can read history in arrival order when reconstructing what happened.
    Given work orders created on 1, 2 and 3 March
    When I click the "Created" column header
    Then the newest is first
    When I click it again
    Then the oldest is first
    # index.ex:525-550, index.html.heex:597-612, invocation.ex:1502-1525

  @S10 @pending
  Scenario: A link to one work order opens it expanded
    # Value: an alert or a run page takes people straight to the work order in question with its full retry history.
    Given work order "W" has two runs
    When I visit the history page with "filters[workorder_id]" set to "W"
    Then I see only "W"
    And I see a chip "Work order: <short id of W>"
    And both runs of "W" are shown
    # index.ex:930-942, index.html.heex:288-296, invocation.ex:706-711
    # test/lightning_web/live/work_order_live_test.exs:1503-1618

  @S11 @pending
  Scenario: Expanding a work order shows its latest run, and earlier runs on request
    # Value: people see the current outcome first and can still trace every retry.
    Given work order "W" has three runs
    When I click its row
    Then I see the latest run labelled "(3/3"
    And I do not see the earlier runs
    When I click "show previous"
    Then I see all three runs
    # workorder_component.ex:78-95, :330-367
    # test/lightning_web/live/work_order_live_test.exs:1381-1500

  @S12 @pending
  Scenario: Steps carried over from an earlier run are marked
    # Value: after a rerun from a step, people can tell which steps actually ran again.
    Given a run that was rerun from its second step
    When I expand its work order
    Then its first step is faded with a paperclip whose tooltip says it "was originally executed in a previous run"
    # components.ex:405-461

  @S13 @pending
  Scenario: The workflow link opens the version the run executed
    # Value: people inspect the code that actually ran, not code changed since.
    Given work order "W" ran on workflow version 3 and the workflow is now on version 5
    When I look at the workflow name in the row
    Then it links to the workflow editor with "run=<latest run id>" and "v=3"
    # workorder_component.ex:190-209, components.ex:298-314
    # test/lightning_web/live/work_order_live_test.exs:189-231

  @S14 @pending @variant:experimental-features
  Scenario: With experimental features the workflow link pins the run itself
    # Value: runs on versions that were never released can still be opened at the code that ran.
    Given I have experimental features enabled
    And work order "W" ran on an older workflow version
    When I look at the workflow name in the row
    Then it links with "run=<latest run id>" and "as_run=<latest run id>"
    # components.ex:308-309
    # test/lightning_web/live/work_order_live_test.exs:189-231

  @S15 @pending
  Scenario: Editor retries a finished work order from the start
    # Value: a failure caused by a downstream outage is fixed in one click once the outage is over.
    Given I am an editor and work order "W" has failed
    When I click its retry button
    Then I see "New run enqueued for 1 workorder"
    And a retry of "W" is queued
    # workorder_component.ex:269-289, index.ex:410-443, :729-741, work_orders.ex:454-486

  @S16 @pending
  Scenario: Editor reruns a run from a failed step
    # Value: after fixing a job, people resume from that step without reprocessing the steps before it.
    Given I am an editor and a run of work order "W" failed at step "Load"
    When I expand "W" and click the rerun icon on "Load"
    Then a new run for "W" is created starting at "Load"
    And the steps before "Load" are carried over from the original run
    # components.ex:474-476, :501-547, index.ex:370-408, work_orders.ex:312-359, :404-425
    # test/lightning_web/live/work_order_live_test.exs:1915-1928

  @S17 @pending
  Scenario: A run from another project cannot be rerun
    # Value: an editor of one project cannot execute another project's runs or read its data.
    Given I am an editor on project "Malawi HIV"
    And run "R" belongs to project "Kenya TB"
    When I send "rerun" for run "R"
    Then I see "Run not found."
    And no new run is created for "R"'s work order
    # index.ex:379-393
    # test/lightning_web/live/run_live/index_test.exs:259-308, :310-328

  @S18 @pending
  Scenario: Runs of a deleted workflow cannot be retried
    # Value: a retired integration does not start sending data again.
    Given work order "W" belongs to a deleted workflow
    When I rerun a step of its run
    Then I see "Runs for deleted workflows cannot be retried"
    # index.ex:398-401, work_orders.ex:339-345

  @S19 @pending
  Scenario: Viewers see no retry, cancel or export controls
    # Value: read-only members can investigate without being able to trigger reprocessing.
    Given I am a viewer on project "Malawi HIV" with a failed and a pending work order
    When I open the history page
    Then the retry icon is disabled with the tooltip "You are not authorized to start runs for this project."
    And I do not see a cancel button
    And I do not see the export button
    # workorder_component.ex:252-313, components.ex:474-476, index.html.heex:664-674
    # test/lightning_web/live/run_live/index_test.exs:1568-1591

  @S20 @pending
  Scenario: Forged actions from a viewer are refused
    # Value: hiding a button is not the only thing stopping a viewer from running or cancelling work.
    Given I am a viewer on project "Malawi HIV"
    When I send "bulk-rerun", "rerun", "cancel", "cancel-run", "bulk-cancel", "show-export-modal" or "confirm-export"
    Then I see "You are not authorized to perform this action."
    And no run, cancellation or export is created
    # index.ex:694-708
    # test/lightning_web/live/run_live/index_test.exs:167-197, :1303-1325, :1498-1511, :1568-1591

  @S21 @pending
  Scenario: A work order whose input was wiped cannot be selected or retried
    # Value: nobody retries with missing data and gets a misleading empty run.
    Given work order "W" has an input dataclip wiped by the retention policy
    When I open the history page
    Then the selection checkbox for "W" is disabled
    And its input id is not a link
    And its retry icon is disabled with a tooltip saying "no input data has been stored due to the data retention policy"
    And selecting all work orders on the page leaves "W" unselected
    # workorder_component.ex:120-176, :290-313, :448-493, index.ex:488-498
    # test/lightning_web/live/work_order_live_test.exs:265-400, :401-535, :2194-2249

  @S22 @pending
  Scenario: Retention tooltips point admins to the setting and others to an admin
    # Value: the person who can change retention can get there, and everyone else knows whom to ask.
    Given work order "W" has a wiped input
    When an admin hovers the disabled retry icon
    Then the tooltip has a "Go to data storage settings" link to "/projects/<project_id>/settings#data-storage"
    When an editor hovers it
    Then the tooltip says "For more information, contact one of your project admins."
    # components.ex:549-570, index.ex:96-102

  @S23 @pending
  Scenario: Selecting a whole page offers to retry every matching work order
    # Value: people can reprocess an entire incident's worth of work orders without paging through them.
    Given 25 failed work orders match my filters
    When I select all on the first page and click "Retry"
    Then I see "Rerun 10 selected work orders from start"
    And I see "Rerun all 25 matching work orders from start"
    # index.html.heex:453-480, :692-702, components.ex:808-866
    # test/lightning_web/live/run_live/index_test.exs:495-560, test/lightning_web/live/work_order_live_test.exs:2115-2192, :2251-2286

  @S24 @pending
  Scenario: Bulk retry reports how many work orders were queued and how many were skipped
    # Value: people know when some of what they asked to retry was not retried.
    Given I selected three finished work orders, one of which belongs to a deleted workflow
    When I confirm "Rerun 3 selected work orders from start"
    Then I see "New runs enqueued for 2 workorders (1 were discarded due to wiped dataclip/workflow being deleted)"
    And the page reloads with my filters
    # index.ex:410-443, :743-749, work_orders.ex:454-486, :961-967

  @S25 @pending
  Scenario: Rerun from a step is only offered for one workflow at a time
    # Value: a step choice is only meaningful within a single workflow.
    Given I selected finished work orders from workflows "Intake" and "Sync"
    Then I do not see "Retry from"
    When I unselect the "Sync" work orders
    Then I see "Retry from"
    # index.html.heex:548-584, :704-713
    # test/lightning_web/live/run_live/index_test.exs:89-165

  @S26 @pending
  Scenario: Steps with nothing to rerun are disabled in the rerun-from modal
    # Value: people can't pick a step that would rerun nothing.
    Given the selected work orders' latest runs only have a usable input for job "Load"
    When I open "Retry from"
    Then every job of the workflow is listed
    And every job except "Load" is disabled
    When I choose "Load" and confirm
    Then the selected work orders are rerun from "Load"
    # rerun_job_component.ex:14-55, :112-138, work_orders.ex:438-444, :721-765
    # test/lightning_web/live/run_live/index_test.exs:199-257, :407-493

  @S27 @pending
  Scenario: A mixed selection disables both bulk actions and says why
    # Value: people aren't offered an action that would only apply to part of what they selected.
    Given I selected one pending and one failed work order
    Then the bulk "Cancel" button is disabled with "Cancel is only available when all selected work orders are pending"
    And the bulk "Retry" button is disabled with "Retry is only available when all selected work orders have finished running"
    # index.ex:789-817, index.html.heex:485-547
    # test/lightning_web/live/run_live/index_test.exs:1326-1363

  @S28 @pending
  Scenario: Editor cancels a pending work order
    # Value: data queued by mistake, or that would hit a broken system, is stopped before it is sent.
    Given I am an editor and work order "W" is pending
    When I click its cancel button
    Then I see "Work order cancelled."
    And its unclaimed run is cancelled
    # workorder_component.ex:252-268, index.ex:587-620, runs.ex:506-527
    # test/lightning_web/live/run_live/index_test.exs:1135-1175, :1222-1256

  @S29 @pending
  Scenario: Cancelling never stops a run a worker has already claimed
    # Value: a run part way through delivering data is never cut off from this page.
    Given work order "W" was pending when I loaded the page
    And its run has since been claimed by a worker
    When I click its cancel button
    Then I see "Work order could not be cancelled"
    And the run keeps its state
    # index.ex:602-609, runs.ex:506-516, components.ex:680-683
    # test/lightning_web/live/run_live/index_test.exs:1365-1401

  @S30 @pending
  Scenario: Editor cancels one enqueued run of a work order
    # Value: people can stop a single queued retry without touching the rest of the work order.
    Given work order "W" has an enqueued run "R"
    When I expand "W" and click "Cancel this run" on "R"
    Then I see "Run cancelled."
    When I try the same on a run that has been claimed
    Then I see "it is no longer available"
    # workorder_component.ex:412-425, index.ex:622-649, cancel_helper.ex:310-315, runs.ex:466-492
    # test/lightning_web/live/run_live/index_test.exs:1258-1301, :1445-1496

  @S31 @pending
  Scenario: Editor cancels selected pending work orders
    # Value: a batch of queued work can be stopped in one action.
    Given I selected two pending work orders
    When I click "Cancel" and confirm "Cancel up to 2 selected"
    Then I see "Cancelled 2 runs"
    # index.ex:558-585, :762-765, components.ex:648-760
    # test/lightning_web/live/run_live/index_test.exs:1177-1220

  @S32 @pending
  Scenario: Cancelling all matching work orders runs in the background
    # Value: a large backlog can be cancelled without the page timing out.
    Given 3 pending work orders match my filters and I selected all of them
    When I choose "Cancel up to 3 matching"
    Then I see "Cancelling runs for 3 work orders in the background..."
    And a background cancellation job is queued for those work orders
    # index.ex:571-576, :767-787, work_orders.ex:540-551
    # test/lightning_web/live/run_live/index_test.exs:1513-1554

  @S33 @pending @variant:usage-limited
  Scenario: Reruns over the plan limit are refused with the limiter's message
    # Value: people learn a plan limit is blocking retries instead of wondering why nothing ran.
    Given the usage limiter refuses new runs with "Runs limit exceeded"
    When I rerun a step
    Then I see the error "Runs limit exceeded"
    And no run is created
    # index.ex:387, :395-396, work_orders.ex:84-92
    # test/lightning_web/live/work_order_live_test.exs:1930-1952

  @S34 @pending @variant:usage-limited
  Scenario: The bulk retry button reports the plan limit instead of opening the modal
    # Value: people are told before choosing options that the retry cannot go ahead.
    Given the usage limiter refuses the number of runs my selection would create, with "Runs limit exceeded"
    When I click "Retry" for my selection
    Then I see the error "Runs limit exceeded"
    And the retry modal does not open
    # index.html.heex:513-530, index.ex:552-556, :944-952

  @S35 @pending
  Scenario: Editor starts a history export
    # Value: people can hand the full record of an incident to someone outside Lightning.
    Given I am an editor and 12 work orders match my filters
    When I click the export button and confirm "Export history"
    Then I see "History export started successfully. You will be notified by email after completion."
    And the flow "flow-history-export" has started for my filters
    # index.html.heex:41-46, :664-674, export_confirmation_modal.ex:1-55, index.ex:651-684, invocation.ex:1311-1340
    # test/lightning_web/live/run_live/index_test.exs:1593-1608

  @S36 @pending
  Scenario: No export is offered when nothing matches
    # Value: nobody waits on an email for an empty export.
    Given I am an editor and no work orders match my filters
    Then I do not see the export button
    # index.html.heex:665

  @S37 @pending
  Scenario: A failed search says so
    # Value: people don't mistake a failed or timed-out search for "nothing happened".
    Given the work order search fails or times out
    When I open the history page
    Then I see "There was an error loading the work orders"
    # index.ex:238-247, index.html.heex:634-640, invocation.ex:577
    # test/lightning_web/live/work_order_live_test.exs:1620-1642

  @S38 @pending
  Scenario: Filters from the health page show as chips that can be dropped
    # Value: people arriving from a chart can see what slice they are looking at and widen it.
    Given I arrive with "run_status[]=failed", "run_date_after" and "run_date_before" set
    Then I see a chip "Run status: Failed"
    And I see a chip starting "Run created" and ending "UTC"
    When I clear the run status chip
    Then the run created chip remains
    # index.html.heex:249-285, index.ex:850-863
    # test/lightning_web/live/run_live/index_test.exs:1057-1131

  @S39 @pending
  Scenario: The error signature chip doesn't reveal another project's job name
    # Value: a crafted link cannot be used to read job names from a project the viewer is not on.
    Given a link with "error_signature_job_id" set to a job in another project
    When I open it
    Then the error signature chip shows the short job id, not the job's name
    # index.ex:192-193, index.html.heex:298-320, jobs.ex:172-185
    # test/lightning_web/live/run_live/index_test.exs:975-1055

  @S40 @pending
  Scenario: An unrecognised error signature matches nothing
    # Value: a bulk retry from a stale or edited link can never widen to every failed work order.
    Given a link with "error_signature_exit_reason" set to "rejected" and no job id
    When I open it
    Then I see no work orders
    # invocation.ex:793-799, :871-874

  @S41 @pending @variant:experimental-features
  Scenario: The channel logs tab appears only with experimental features
    # Value: an unfinished feature stays out of the way of people who haven't opted in.
    Given I have experimental features enabled
    When I open the history page
    Then I see tabs "Work orders" and "Channel logs"
    And without experimental features I see no tabs
    # index.ex:142-143, index.html.heex:22-38
    # test/lightning_web/live/run_live/index_test.exs:563-595

  @S42 @pending
  Scenario: The page listens for work order changes in the project
    # Value: people watching an incident see retries and new arrivals without reloading.
    Given I have the history page open
    When a work order or run in the project changes
    Then the flow "flow-history-live-updates" ends on this page
    # index.ex:82, :274-348
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Rerun from a step that matches no work orders reports "New run enqueued for 0 workorder" (singular, zero, and phrased as success) | `index.ex:418`, `work_orders.ex:506-508`; asserted in `test/lightning_web/live/run_live/index_test.exs:252-253` | a success flash for an action that did nothing | fix |
| Rerun-from modal preselects the first job by name even when that job is disabled, so the button reads "Rerun  selected work orders from selected job" with no number | `rerun_job_component.ex:53`, `:229-241`, `:158-161`; `utils.ex:16-17` (nil sorts above 1) | a blank count and a confirm button for a job that can't be rerun | fix |
| Rerun-from modal crashes when the selected work orders' workflow has no jobs | `rerun_job_component.ex:53` (`hd([])`) | the page crashes after selecting such work orders | fix |
| Rerun-from modal text tells people to use the "Rerun" button, not "Rerun from", but the buttons are labelled "Retry" and "Retry from" | `rerun_job_component.ex:102`; `index.html.heex:529`, `:565` | copy that names controls that don't exist | fix |
| Counts in the export modal, export tooltip, "Rerun all N matching" and "Cancel up to N matching" come from `page.total_entries`, which stops at 50 when there is a search term, while the action covers every match | `index.html.heex:45`, `:671`, `:695`; `components.ex:710`, `:846`; `invocation.ex:580-582`; `index.ex:718-727`, `:767-787`; `export_worker.ex` | "Export all 50" or "Rerun all 50" that then exports or retries more | fix |
| "Rerun all N matching work orders from selected job" counts every matching work order, though only those whose latest run has that job are rerun | `rerun_job_component.ex:173`, `index.ex:710-727`, `work_orders.ex:438-444` | a larger number on the button than the flash reports | fix |
| Selection is not cleared when filters or the page change, so "selected" bulk actions act on work orders no longer on screen and the select-all box compares counts across pages | `index.ex:181-201` (no reset), `:819-830` | "Rerun 3 selected" with one row ticked on screen | fix |
| Turning off all four search toggles searches all four: `apply_filters` drops `"false"`, so the URL names none and `SearchParams` falls back to its default of every field, while the toggles render all off | `index.ex:513-515`, `search_params.ex:76-79`, `:140-151`, `index.html.heex:411` | results matching fields the user switched off | fix |
| Bulk retry modal summary puts dates the wrong way round ("received between <before> and <after>") and calls last activity "last run" | `components.ex:920-921`, `:936-937` | a summary that contradicts the chips | fix |
| When any work order on the page has a wiped input, select all can never count as "all selected", so the "Rerun all N matching" and "Cancel up to N matching" options never appear | `index.ex:488-498` vs `:819-821`; `components.ex:687`, `:820` | the all-matching options disappear for no visible reason | fix |
| A malformed filter in the URL (bad date, unknown sort) raises during render, because the template calls `SearchParams.new/1` for the modals; the code comment says failing loud is deliberate | `index.html.heex:688`, `:699`; `search_params.ex:110-119` | a crashed page instead of an error message | decide |
| Forged `cancel` with a non-UUID id, `cancel-run` with a non-UUID id, or `bulk-rerun` type `single` for a work order not on the page crash the LiveView, unlike `rerun`, which validates | `index.ex:593-598`, `:733-740`; `cancel_helper.ex:311`; `runs.ex:74-84` | the page reconnects; nothing is cancelled | fix |
| Step rerun icons use the step id as the DOM id, and a step carried into a retry appears under both runs once "show previous" is on | `components.ex:508`, `:527`, `workorder_component.ex:334-335` | duplicate ids; tooltips can attach to the wrong element | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The 30-day window and "logs only" search default apply only when the URL has no `filters` at all, so any incoming link (alert email, health page, run page) shows all time | `index.ex:133`, `:157-169`, `:183` | decide |
| "Last activity" descending puts work orders with no activity first; ascending puts them last | `invocation.ex:1514-1523`, `:1527-1530` | preserve |
| Received and last activity bounds are inclusive; the run created upper bound is exclusive | `invocation.ex:727-755` vs `:785-786` | decide |
| Received and last activity date pickers are `datetime-local` values cast as UTC, while only the run created chip says UTC | `index.ex:35-40`, `index.html.heex:195-243`, `:850-863` | decide |
| Work orders created while the page is open are put at the top of whatever page and sort is showing, and the page grows past its size | `index.ex:306-322`, `:881-896` | decide |
| Live updates to a listed work order replace it even if it no longer matches the filters | `index.ex:325-348`, `:898-919` | decide |
| Bulk retry and bulk cancel do a full navigate, not a patch, which also clears selection and collapses rows | `index.ex:427-430`, `:560-582` | preserve |
| The single-row retry button also toggles the row open, which the navigate immediately throws away | `workorder_component.ex:274-283` | decide |
| Retry from start is queued as background jobs; rerun from a step runs synchronously, one retry per work order | `work_orders.ex:454-486` vs `:488-504` | preserve |
| The rerun-from job list is the workflow's current jobs sorted by name, not the version that ran | `rerun_job_component.ex:22-23`, `jobs.ex:250-258` | decide |
| Work orders of deleted workflows are still listed, but the workflow chip doesn't offer deleted workflows | `invocation.ex:675-685`, `workflows.ex:826-834`, `index.ex:84-86` | decide |
| State labels differ from state names: pending and available show "Enqueued", claimed shows "Starting", started shows "Running" | `components.ex:162-174`, `index.ex:104-115` | preserve |
| Error flashes say "Oops! an error occured" (spelling) | `index.ex:405`, `:435` | fix |
| The bulk retry button's click is chosen at render time: either opening the modal or pushing an `invalid-rerun:<limiter text>` event, which shows whatever text follows the colon as an error flash | `index.html.heex:520-527`, `:556-563`; `index.ex:552-556`, `:944-952` | decide |
| Rejected work orders have no runs, so their rows can't be expanded and show no run count | `workorder_component.ex:113-117`, `:250` | preserve |
| Workflow name falls back to the snapshot name, then the workflow name, then "Untitled" | `workorder_component.ex:51-61`, `index.ex:86` | preserve |
| Search is wrapped in a telemetry span `[:lightning, :ui, :projects, :history]` | `index.ex:204-223` | preserve |
| A step killed with an unknown error type logs a warning and sends a Sentry message every time it renders | `components.ex:592`, `:627-636` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `show_bulk_rerun_modal` and `show_bulk_rerun_from_job_modal` assigns | `index.html.heex:701`, `:712` | never assigned, so `show` is always false |
| `page_number`, `filters` and `workflows` attrs of `bulk_cancel_modal` | `components.ex:640`, `:645-646` | declared and passed but never rendered |
| `step: %Step{}` assign | `index.ex:190` | not read by the template or components |
| `filters` and `pagination_path` assigned in `mount` | `index.ex:151-152` | always overwritten by `handle_params` |
| `channel_logs_filter` handle_info and the channel-logs event ignore clause | `index.ex:350-368` | belong to history-channel-logs |
| `step_item`, `step_list`, `detail_list`, `list_item`, `loading_filler`, `channel_state_pill` | `components.ex:52-89`, `:140-160`, `:176-278`, `:316-345` | not rendered by this view |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Count stops at 50 when there is a search term ("50+"); results past 50 can't be paged to | `invocation.ex:44`, `:580-582`, `query_paginater.ex:21-29`, `:65-81` | yes | preserve |
| Search query timeout 30 seconds | `invocation.ex:43`, `:577` | yes, as the load error | preserve |
| Page size 10, `page_size` param up to 100 | `repo.ex:6` | yes | preserve |
| Every `WorkOrderCreated` event re-runs the search for every open history page | `index.ex:306-322` | no | decide |
| Every run event reloads the full work order graph with preloads | `index.ex:275-298`, `:325-348` | no | preserve |
| The usage limiter is called on every render while bulk retry is available | `index.html.heex:521-527`, `:557-562` | no | decide |
| The rerun-from modal re-queries the workflow, its jobs and retriable steps on every parent render | `rerun_job_component.ex:14-55` | no | decide |
| "All matching" retry and cancel load every matching work order into memory | `invocation.ex:596-626` | no | decide |
| Retry from start is chunked 100 work orders per job; cancel is 100 runs per update | `work_orders.ex:73`, `runs.ex:506`, `cancel_many_work_orders_job.ex:17` | no | preserve |
| Inputs over about 1MB may not match text search (Postgres tsvector limit), stated in the toggle's tooltip | `index.ex:124-129` | yes | preserve |

### 6.5 Things seen but not understood

- The base query uses `distinct: true` and the body-and-log search wraps a `union` in a subquery (`invocation.ex:675-685`, `:917-931`); whether sort order survives the union in every combination was not checked.
- `toggle_selection` uses `String.to_existing_atom/1` on a browser value (`index.ex:455`); harmless for "true"/"false", unclear why atoms are needed.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should selection persist across pages and filter changes (cross-page selection), or reset? (6.1)
- Should a malformed filter in the URL crash the page, as the code comment intends, or show an error and refuse bulk actions? (6.1)
- Which timezone do the received and last activity filters mean? (6.2)
- Should incoming links keep the 30-day default window? (6.2)
- Should the rerun-from job list come from the version that ran rather than the current workflow? (6.2)

## Proposed flows

- **flow-history-export**: an editor confirms an export here; `ExportWorker` builds the zip and the requester gets an email; the file is downloaded from project settings. Surfaces: history-work-orders, oban:ExportWorker, email:history-export-complete, project-settings-history-exports, controller:project-file-download.
- **flow-history-live-updates**: run and work order changes made elsewhere (worker run channel, webhook intake, background retry and cancel jobs, another tab) reach an open history page and update its rows, including removing the cancel button once a run is claimed (`test/lightning_web/live/run_live/index_test.exs:1403-1443`). Surfaces: controller:run-channel or webhook, oban:RetryManyWorkOrdersJob, oban:CancelManyWorkOrdersJob, pubsub:WorkOrders.Events project topic, history-work-orders.
- **flow-workflow-health-drilldown**: a runs-chart band or triage row on the health page opens History filtered to exactly the work orders it counted, and a bulk retry from there retries only those. Surfaces: workflow-health, history-work-orders.
- **flow-alert-email-to-history**: a failure alert opens History on the failed work order, expanded; a digest email opens History on the digest's workflow and date range. Surfaces: email:failure-alert, email:digest, history-work-orders.

## Proposed shared

- **shared-run-components**: `LightningWeb.RunLive.Components` (state pill, step icon, elapsed indicator with its `ElapsedIndicator` hook, version-pinning link builder, retention tooltips) and `RunLive.CancelHelper`, rendered by both History and the run page. Surfaces: history-work-orders, run-show, history-channel-logs.
- **shared-tooltip-hook**: the `Tooltip` JS hook, including its HTML and interactive modes used for the retention links here. Surfaces: history-work-orders and most project views.
- **shared-filter-chip**: the `filter_chip` component (`pills.ex:119-176`) that clears its fields by pushing `apply_filters`. Surfaces: history-work-orders, history-channel-logs.

## Lead resolution (batch 1)

- `flow-history-export`, `flow-history-live-updates` and `flow-workflow-health-drilldown` created as proposed. `flow-alert-email-to-history` split into `flow-failure-alert-email` and `flow-digest-email`, each covering preference, email and landing.
- `shared-run-components` created. `shared-tooltip-hook` and `shared-filter-chip` declined: each view lists the hook in `js_hooks`, and the filter chip is only used by the two history views.
