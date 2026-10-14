---
id: flow-workflow-health-drilldown
type: flow
title: From the workflow health page to the work orders behind it
status: not-started
owner:

trigger:
  entry: workflow-health
  exit: history-work-orders
  surfaces:
    - workflow-health                             # live /projects/:project_id/w/:id/health, WorkflowLive.Health + React WorkflowHealth (health.ex:10-11, :50-60)
    - controller:workflow-health-api              # API.WorkflowHealthController, GET .../health/outcomes, .../health/failures and .../health/runs (router.ex:142-152)
    - capability:workflow-stats                   # Lightning.Workflows.Stats, cached in Cachex :workflow_stats (stats.ex:45-67, :80-93, :154-170)
    - history-work-orders                         # opened in a new tab with the drill-down filters
    - oban:RetryManyWorkOrdersJob                 # bulk retry from that tab (work_orders.ex:454-486)
  reachable_when:
    - the viewer passes shared-project-scope on the health page and the workflow belongs to the project (hooks.ex:139-158)
    - the stats endpoints admit the viewer: signed in and `:access_project` on the workflow's project (workflow_health_controller.ex:110-133)
    - a triage row has an exit reason (TriageTable.tsx:130-137), or a runs-chart band has a bar to click (VolumeBars.tsx:182-191)
    - or the window has at least one finished work order, so the donuts draw their legend and wedges (Donut.tsx:51-56); a failure breakdown slice and the Outcomes "Cancelled" row exist only when non-zero (FailureBreakdownDonut.tsx:61; OutcomesDonut.tsx:66-79)

inherits:
  - shared-project-scope            # both pages mount {LightningWeb.Hooks, :project_scope} (health.ex:10; history-work-orders)
  - shared-usage-limits-banner      # history landing, and the limiter on bulk retry (work_orders.ex:84-92, :461)

url_params:
  - name: filters[workflow_id], filters[log]=true
    set_by: workflow-health, every drill-down link (historyUrl.ts:13-36)
    effect: scopes History to this workflow; `log` keeps History's search toggles in step with what it searches (search_params.ex:140-175)
  - name: filters[date_after]
    set_by: workflow-health triage row, the `window.from` of the failures reply (TriageTable.tsx:177-196); Outcomes and Failure breakdown legend rows and wedges, the `window.from` of the outcomes reply (WorkflowHealth.tsx:101-125; historyUrl.ts:47-56)
    effect: last activity on or after the start of the health window (invocation.ex:741-747)
  - name: filters[success|failed|crashed|killed|exception|lost|rejected|cancelled]=true
    set_by: workflow-health Outcomes legend rows and wedges (one flag for "Success" and "Cancelled", all six failure states for "Failed"; OutcomesDonut.tsx:57, :64, :76; types.ts:14-21) and Failure breakdown slices (one flag each; FailureBreakdownDonut.tsx:66)
    effect: History's own status chip and work order state filter, by current state (search_params.ex:134-136, :153-155; invocation.ex:641-655, :719-723); chip owned by history-work-orders S04
  - name: filters[error_signature_exit_reason], filters[error_signature_error_type], filters[error_signature_job_id]
    set_by: workflow-health triage row (TriageTable.tsx:190-195)
    effect: only failed work orders whose latest run carries that signature (invocation.ex:799-899); chip owned by history-work-orders S39
  - name: filters[rejected]=true
    set_by: workflow-health triage row for rejected work orders (TriageTable.tsx:183-188)
    effect: History's own rejected status filter
  - name: filters[run_status][], filters[run_date_after], filters[run_date_before]
    set_by: workflow-health runs-chart band (VolumeBars.tsx:249-265)
    effect: work orders with a run created in [after, before) in one of those run states (invocation.ex:757-791); chips owned by history-work-orders S38

config_variants:
  default: {}                       # read under this
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(:new_run) returns {:error, _, %{text: _}}> }

inventory:
  routes:
    - live /projects/:project_id/w/:id/health  WorkflowLive.Health :show   # entry (router.ex:304)
    - get /api/projects/:project_id/workflows/:workflow_id/health/outcomes  API.WorkflowHealthController :outcomes   # router.ex:142-144
    - get /api/projects/:project_id/workflows/:workflow_id/health/failures  API.WorkflowHealthController :error_signatures   # router.ex:146-148
    - get /api/projects/:project_id/workflows/:workflow_id/health/runs  API.WorkflowHealthController :runs   # router.ex:150-152
    - live /projects/:project_id/history  RunLive.Index :index   # exit, owned by history-work-orders
  events:
    - RunLive.Index#bulk-rerun      # owned by history-work-orders; exercised here with drill-down filters
  js_hooks:
    - ReactComponent                # mounts WorkflowHealth (health.ex:52)
  policies:
    - Lightning.Policies.ProjectUsers :access_project (workflow_health_controller.ex:121, project_users.ex:136)
    - Lightning.Policies.ProjectUsers :run_workflow (index.ex:694-708; project_users.ex:43)
  workers:
    - Lightning.WorkOrders.RetryManyWorkOrdersJob (queue scheduler, 5 attempts; retry_many_workorders_job.ex:5-7)
  api_endpoints:
    - controller:workflow-health-api (outcomes, failures, runs)
  emails: []
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (WorkOrders.limit_run_creation)
  not_reachable_here:
    - StepFailureBars, which draws the same failures reply but links nowhere (WorkflowHealth.tsx:133-142)

related:
  - lib/lightning_web/live/workflow_live/health.ex
  - lib/lightning_web/controllers/api/workflow_health_controller.ex
  - lib/lightning/workflows/stats.ex
  - assets/js/health/WorkflowHealth.tsx
  - assets/js/health/historyUrl.ts
  - assets/js/health/charts/TriageTable.tsx
  - assets/js/health/charts/VolumeBars.tsx
  - assets/js/health/charts/Donut.tsx
  - assets/js/health/charts/OutcomesDonut.tsx
  - assets/js/health/charts/FailureBreakdownDonut.tsx
  - workflow-health                 # view annotation; its S14 and S15 assert the handoff into this flow
  - history-work-orders             # view annotation; owns the landing chips and bulk retry
  - lib/lightning/invocation.ex
  - lib/lightning/workorders/search_params.ex
  - lib/lightning_web/live/run_live/index.ex
  - lib/lightning/work_orders.ex
flows: []
---

## 1. Purpose

People who look after a workflow use its health page to see what is failing and how much. This
flow turns a number on that page into the list of work orders it counted, so they can inspect and
retry exactly those, without rebuilding the filter by hand. If the link were wider than the count,
a bulk retry from History would resend data for work orders nobody meant to touch; if narrower,
some failures would be silently left behind. The same holds for the outcome donuts: a "Failed"
link that also caught cancelled work would resend work someone stopped on purpose.

## 2. What it does

A member clicks a triage row's "View history", a band of a runs-chart bar, or a legend row or wedge of the "Outcomes" or "Failure breakdown" donut on the health page; History opens in a new tab filtered to the work orders that row, band or slice counted; an editor selects all and retries, and only those work orders get new runs.

## 3. Who can do what

Source: `workflow_health_controller.ex:110-133` (`:access_project`), `project_users.ex:136`,
`index.ex:694-708` (`:run_workflow`), `project_users.ex:29-49`. Both page loads are governed by
shared-project-scope.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the health page and its outcomes, triage and runs data | yes | yes | yes | yes | no | yes |
| Follow a drill-down link and see the filtered list | yes | yes | yes | yes | no | yes |
| Bulk retry the filtered work orders | no | yes | yes | yes | no | yes |

**Preconditions beyond role**
- The workflow must belong to the project in the URL, on the page (`hooks.ex:139-158`) and on each endpoint (`workflow_health_controller.ex:113-120`); every refusal on the endpoints is a 404 (`:124-131`).
- MFA enrolment where the project requires it, and the project not scheduled for deletion (`project_users.ex:136`; `workflow_health_controller_test.exs:149-189`).
- Retry skips work orders whose input was wiped and work orders of deleted workflows (`invocation.ex:596-604`, `:669-673`; `work_orders.ex:961-967`).
- New runs pass the usage limiter (`work_orders.ex:461`).

## 4. What it touches

**Reads**
- Hop 1 (health page): `workflows`, `projects` (`health.ex:15`, `hooks.ex:144-145`); `work_orders`, `runs`, `steps`, `run_steps`, `workflow_snapshots` for the triage table (`stats.ex:367-466`, `:477-488`) and `work_orders`, `runs` for the runs chart (`stats.ex:263-291`); `work_orders` grouped by final state for both donuts (`stats.ex:45-67`); the change marker on `work_orders` (`stats.ex:351-358`)
- Hop 2 (History with drill-down filters): `work_orders` by current state for a donut link (`invocation.ex:641-655`, `:719-723`); `work_orders`, `runs`, `steps`, `run_steps` (`invocation.ex:757-899`); `jobs` for the signature chip's job name (`index.ex:192-193`, `jobs.ex:172-185`)
- Hop 3 (bulk retry): matching work orders without wiped inputs (`invocation.ex:596-604`), retriable work orders (`work_orders.ex:961-975`)

**Writes**
- Hop 1: Cachex `:workflow_stats` entries, keyed by slice, workflow, days and change marker (outcomes, failures) or timezone (runs) (`stats.ex:47`, `:317-339`, `:165-169`)
- Hop 2: none
- Hop 3: `oban_jobs` insert, one `RetryManyWorkOrdersJob` per 100 work orders (`work_orders.ex:466-476`); the job inserts `runs` and updates `work_orders.state` and `last_activity` (`work_orders.ex:767-818`)

**Immediate side effects**
- Hop 1: three cookie-authenticated GETs with an `x-timezone` header, repeated every 30 seconds while the tab is visible and on returning to it (`WorkflowHealth.tsx:50-56`, `useHealthQuery.ts:59-65`, `:103-130`); the runs reply carries `vary: x-timezone` (`workflow_health_controller.ex:43-53`)
- Hop 2: the link opens in a new tab and the health page stays where it was (`TriageTable.tsx:158-167`, `VolumeBars.tsx:190`; donut legend rows `Donut.tsx:131-134`, wedges `Donut.tsx:89-90`); History subscribes to project work order events (history-work-orders)
- Hop 3: flash "New runs enqueued for N workorders", then a full navigate back to History with the same filters (`index.ex:410-430`)

**Deferred side effects**
- `RetryManyWorkOrdersJob` creates the runs and broadcasts `work_order_updated` and `run_created` on the project topic (`work_orders.ex:811-814`, `:907-925`), which reach the open History tab (flow-history-live-updates)
- The health page's outcome and triage counts move only when a work order settles (marker) or the 5-minute TTL expires; the runs chart refreshes on a 2-minute TTL (`stats.ex:33-37`, `:341-358`)

**External, non-transactional effects**
- none

**Depends on config**
- Usage limiter adapter for `:new_run` (variant `usage-limited`; behaviour owned by history-work-orders S33, S34)

**Product limits**
- Health windows are 24 hours, 7 days or 30 days; anything else is a 400 (`workflow_health_controller.ex:56-75`)
- A retry from "all matching" is queued 100 work orders per job (`work_orders.ex:73`)

## 5. Scenarios

```gherkin
Feature: Drill down from workflow health to history
  In order to fix the failures the health page is showing me
  As a member of a project
  I want each triage row, runs-chart band and donut slice to open exactly the work orders it counted, and to retry only those

  Background:
    Given I am an editor on project "Malawi HIV"
    And workflow "Daily sync" has jobs "Fetch" and "Load"

  @S01 @pending
  Scenario: A triage row opens only the work orders it counted
    # Value: the person triaging one error lands on that error's work orders, not on every failure.
    Given in the last 7 days two work orders failed with "fail:RuntimeError" at "Load"
    And one work order failed with "fail:RuntimeError" at "Fetch"
    And one work order failed with "fail:CompileError" at "Load"
    And one work order failed with "fail:RuntimeError" at "Load" 10 days ago
    When I open the health page of "Daily sync" with the 7-day range
    Then the triage row "fail:RuntimeError @ Load" shows 2
    When I click "View history" on that row
    Then History opens in a new tab with a workflow chip for "Daily sync" and an error signature chip
    And I see exactly those 2 work orders
    And the health page is still open in the first tab
    # TriageTable.tsx:121-137, :154-196; historyUrl.ts:13-36; stats.ex:80-93, :403-423, :551-556
    # invocation.ex:741-747, :816-844; TriageTable.test.tsx:144-162; invocation_test.exs:1191-1215

  @S02 @pending
  Scenario: A triage row for runs that never reached a step opens only those work orders
    # Value: a run-level failure (lost, crashed before any step) is triaged apart from step failures of the same kind.
    Given one work order's latest run was lost before reaching a step
    And another work order's latest run was lost with a failing step "Fetch"
    When I click "View history" on the triage row for runs lost before reaching a step
    Then I see only the first work order
    # stats.ex:513-533; TriageTable.tsx:190-195 (no job id); invocation.ex:846-878
    # TriageTable.test.tsx:167-190; invocation_test.exs:1211-1214

  @S03 @pending
  Scenario: The rejected row opens the rejected work orders
    # Value: payloads refused by the run limit can be found and retried once the limit allows.
    Given two webhook requests to "Daily sync" were rejected over the run limit in the last 7 days
    When I click "View history" on the triage row "rejected:RunLimitExceeded"
    Then History lists only those 2 rejected work orders
    # stats.ex:494-503; TriageTable.tsx:169-188; TriageTable.test.tsx:193-215

  @S04 @pending
  Scenario: A successful work order is never in a triage drill-down
    # Value: a bulk retry from a triage row cannot resend data for work orders that already succeeded.
    Given a work order succeeded although its latest run has a failing step "Load" with "fail:RuntimeError" handled by an on-failure path
    When I follow the triage link for "fail:RuntimeError @ Load"
    Then that work order is not listed
    # stats.ex:403-411 (failure states only); invocation.ex:801-809, :833; invocation_test.exs:1304-1314

  @S05 @pending
  Scenario: Retrying all matching from a triage drill-down retries only that row's work orders
    # Value: one click recovers every failure of one kind and touches nothing else.
    Given 12 work orders failed with "fail:RuntimeError" at "Load" and 3 failed with "fail:CompileError" at "Load"
    And I followed the triage link for "fail:RuntimeError @ Load"
    When I select all, click "Retry" and confirm "Rerun all 12 matching work orders from start"
    Then I see "New runs enqueued for 12 workorders"
    And each of the 12 work orders has a new run
    And none of the 3 "CompileError" work orders has a new run
    # index.ex:410-430, :751-760; invocation.ex:596-604, :816-844; work_orders.ex:454-486, :767-818
    # invocation_test.exs:1277-1293 (search_workorders_for_retry scoped to the signature)

  @S06 @pending
  Scenario: Retried work orders drop out of the triage drill-down while they run
    # Value: a second click on the same page cannot queue the same work orders twice.
    Given I retried all matching work orders from a triage drill-down
    When History reloads with the same filters
    Then the retried work orders are not listed while their new runs are pending or running
    # index.ex:427-430 (navigate keeps filters); invocation.ex:833 (failure states only); work_orders.ex:798-805

  @S07 @pending
  Scenario: A runs-chart band opens the work orders whose runs it counted, including ones retried since
    # Value: the failures a bar shows can all be reached, even after some were fixed.
    Given in the 2-hour bar starting 02:00 UTC work order "A" had a failed run and was later retried to success
    And work order "B" had a crashed run and is still crashed
    And work order "C" had a successful run
    When I open the health page with the 24-hour range and click the Failed band of that bar
    Then History opens in a new tab with chips "Run status" and "Run created" for that bar
    And I see "A" and "B" and not "C"
    # VolumeBars.tsx:65-74, :171-191, :249-265; stats.ex:263-291; invocation.ex:757-791
    # VolumeBars.test.tsx:213-221; invocation_test.exs:1839-1885

  @S08 @pending
  Scenario: A run on a bar boundary belongs to the later bar on both pages
    # Value: a work order is never counted under one bar and listed under its neighbour.
    Given a run of "Daily sync" was created exactly at 04:00 UTC, the start of a bar
    When I click the band of the bar ending at 04:00
    Then that run's work order is not listed
    When I click the same band of the bar starting at 04:00
    Then it is listed
    # stats.ex:258-262 (width_bucket, lower edge inclusive); VolumeBars.tsx:240-262; invocation.ex:780-786
    # stats_test.exs:759; VolumeBars.test.tsx:189-198; invocation_test.exs:1787-1834

  @S09 @pending
  Scenario: The health data of a workflow in another project is not served
    # Value: someone who can't open a project can't read its failure counts or learn that its workflow exists.
    Given workflow "Kenya sync" belongs to project "Kenya TB", which I am not on
    When my browser requests its outcomes, failures or runs with either project's id
    Then the response is 404
    # workflow_health_controller.ex:110-133; workflow_health_controller_test.exs:77-121, :218-230

  @S10 @pending
  Scenario Outline: An Outcomes legend row opens exactly the work orders it counts
    # Value: the list matches the number beside it, so work that went through or was stopped on purpose is never mixed in with the failures.
    Given in the last 7 days "Daily sync" had 9 successful, 2 failed, 1 lost, 1 rejected and 2 cancelled work orders
    And 1 failed work order of "Daily sync" was last active 10 days ago
    And 1 work order is still running
    When I open the health page of "Daily sync" with the 7-day range
    And I click "<row>" in the "Outcomes" legend
    Then History opens in a new tab with a workflow chip for "Daily sync", a "Last activity" chip from the window start, and the chip "<status chip>"
    And I see exactly <count> work orders
    And the health page is still open in the first tab
    Examples:
      | row         | status chip                                                    | count |
      | Success 9   | Status is Success                                              | 9     |
      | Failed 4    | Status in Failed, Crashed, Killed, Exception, Lost, Rejected   | 4     |
      | Cancelled 2 | Status is Cancelled                                            | 2     |
    # OutcomesDonut.tsx:50-80; types.ts:14-21, :35-36; historyUrl.ts:13-56; Donut.tsx:128-152
    # stats.ex:45-67; workorder.ex:48-58; search_params.ex:35, :134-136, :153-155; invocation.ex:641-655, :719-723, :741-747
    # index.ex:104-115; index.html.heex:116-135, :205-224
    # OutcomesDonut.test.tsx:154-195; stats_test.exs:94-133; invocation_test.exs:1380-1411

  @S11 @pending
  Scenario: A failure breakdown slice opens only the work orders that ended in that state
    # Value: lost runs, crashes and payloads refused over the run limit have different fixes, so each can be picked out and handled on its own.
    Given in the last 7 days "Daily sync" had 3 failed, 1 lost and 2 rejected work orders
    When I click "lost 1" in the "Failure breakdown" legend
    Then History opens in a new tab with the chip "Status is Lost"
    And I see only the lost work order
    # FailureBreakdownDonut.tsx:51-74; historyUrl.ts:47-56; invocation.ex:719-723
    # FailureBreakdownDonut.test.tsx:133-150

  @S12 @pending
  Scenario: Retrying all matching from the "Failed" drill-down leaves cancelled and successful work orders alone
    # Value: one click recovers every failure in the window without resending work someone stopped on purpose or that already went through, and nothing is queued twice.
    Given in the last 7 days "Daily sync" had 10 failed and 2 crashed work orders, 3 cancelled and 5 successful ones
    And I followed the "Failed 12" link in the "Outcomes" legend
    When I select all, click "Retry" and confirm "Rerun all 12 matching work orders from start"
    Then I see "New runs enqueued for 12 workorders"
    And each of the 12 work orders has a new run
    And none of the cancelled or successful work orders has a new run
    And when History reloads with the same filters the retried work orders are not listed while their new runs are pending or running
    And a retried work order that then succeeds is not listed
    # OutcomesDonut.tsx:64; index.ex:410-430, :751-760; invocation.ex:596-604, :719-723
    # work_orders.ex:454-486, :767-818; workorder.ex:50-58
```

The landing page's own behaviour with these filters is owned by history-work-orders: the status chip (S04),
the run chips and clearing them (S38), the job name not leaking across projects (S39), an unrecognised
signature matching nothing (S40), viewers seeing no retry controls (S19, S20), and the usage
limiter on bulk retry (S33, S34).

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A band drill-down has no work order state filter, so "Rerun all N matching" from it retries work orders already retried to success, or still running, on later pages | `VolumeBars.tsx:249-265`; `invocation.ex:757-776` (run filter only), `:596-604`; `index.ex:751-760` (no state check in "all" mode); `invocation_test.exs:1839-1885` asserts the retried-to-success match is deliberate for the link | a second retry of data that already went through | decide |
| "Rerun all N matching" counts work orders with wiped inputs, then excludes them before retrying without reporting them as discarded | `index.html.heex:696`; `invocation.ex:596-604`, `:669-673`; `work_orders.ex:476-480`; `index.ex:416-426` | "Rerun all 12" followed by "New runs enqueued for 10 workorders" with no explanation | fix |
| The triage and outcome counts are cached for up to 5 minutes and the link carries only the window start, so History lists work orders that failed after the row was computed; a donut link filters on the work order's state now, so one retried since the count also drops out | `stats.ex:33`, `:47`, `:317-321`; `TriageTable.tsx:154-157` (comment accepts it); `historyUrl.ts:47-56`; `invocation.ex:719-723` | a row of 2 that opens a list of 3, or a "Failed 4" that opens 3 or 5 | decide |
| The usage limiter check on the bulk retry button counts the selected work orders on the page, not all matching ones | `index.html.heex:521-527`, `:557-562`; `index.ex:944-952` | the modal opens, then the "all matching" retry is refused by the limiter | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The runs chart counts runs while History lists work orders, so a band's height and the list length differ when a work order ran more than once in the bar | `VolumeBars.tsx:19-27`; `WorkflowHealth.tsx:145-146` | preserve |
| The newest bar's link has no upper bound, so it also reaches runs created after the chart was drawn | `VolumeBars.tsx:244-247`, `:262`; `VolumeBars.test.tsx:200-205` | preserve |
| Health counts work orders with last activity strictly after the window start; the link's `date_after` is inclusive | `stats.ex:57-60`, `:410`; `invocation.ex:743-747` | preserve |
| "Failed" means all six failure states on the health page and one state in History's status chip; the link spells out the six so the chip reads "Status in Failed, Crashed, Killed, Exception, Lost, Rejected" | `OutcomesDonut.tsx:59-65`; `types.ts:14-21`; `index.ex:104-115`; `index.html.heex:116-135` | decide |
| A wedge and its legend row open the same link; the legend row is a real link with `rel="noopener noreferrer"`, the wedge calls `window.open` with neither (same origin) and is mouse-only | `Donut.tsx:87-91`, `:128-152`; workflow-health 6.2 owns the keyboard point | preserve |
| A "Success" or "Cancelled" drill-down offers History's bulk retry like any other filter, so work that succeeded or was cancelled can be rerun from it | `OutcomesDonut.tsx:57`, `:76`; `index.ex:751-760` | preserve |
| "Success 0" and "Failed 0" stay in the Outcomes legend as live links, while zero failure breakdown slices and a zero "Cancelled" row are dropped | `OutcomesDonut.tsx:51-79`; `FailureBreakdownDonut.tsx:61` | preserve |
| Bars are cut on the reader's timezone; the run created chip shows the same instants in UTC | `stats.ex:213-236`; `index.ex:850-863` | preserve |
| The runs-chart band is a mouse-only link: the chart is `aria-hidden` and the band uses `window.open` | `VolumeBars.tsx:162-191` | decide |
| Triage rows label a job by its newest failing snapshot's name; the History chip names it from the live jobs table | `stats.ex:425-430`, `:558-572`; `index.ex:192-193`, `jobs.ex:172-185` | decide |
| A triage row with no resolved exit reason has no link | `TriageTable.tsx:130-137`; `TriageTable.test.tsx:218-227` | preserve |
| A work order failing in two branches is in two triage rows, and retrying from either retries it | `stats.ex:8-11`, `:75-78` | preserve |
| Every drill-down link sets `filters[log]=true` so History's search toggles match what it searches | `historyUrl.ts:7-12`, `:18-21`; `search_params.ex:163-175` | preserve |
| Any drill-down link carries `filters`, so History's 30-day default window does not apply | `index.ex:133`, `:157-169` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `rejected` exit reason in the signature filter's run-level branch | `invocation.ex:792-799`, `:871-874` | the triage table sends rejected rows to the status filter instead (`TriageTable.tsx:183-188`); only a hand-made link reaches it (history-work-orders S40) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Health page polls every 30 seconds and on tab focus, with no timer while a read is out | `useHealthQuery.ts:103-130` | no | preserve |
| Failures slice cached 5 minutes keyed on a change marker; runs slice cached 2 minutes with no marker | `stats.ex:33-37`, `:156-169`, `:317-358` | yes, counts lag up to that long | preserve |
| "All matching" retry loads every matching work order into memory before chunking | `invocation.ex:596-604`; `work_orders.ex:466-476` | no | decide |

### 6.5 Things seen but not understood

- Resolved: the lead folded the proposed flow-workflow-health-outcome-drilldown into this flow, so the donut legend and wedge links are now S10 to S12 (`OutcomesDonut.tsx:57-76`, `FailureBreakdownDonut.tsx:66`, `historyUrl.ts:47-56`).
- If a job is deleted after its steps failed, it is unclear whether `steps.job_id` survives so that the triage link still matches; `stats.ex:425-427` implies the row is still nameable.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a runs-chart band drill-down restrict "retry all matching" to work orders still in a failure state, or keep reaching work orders retried since? (6.1)
- Should the runs-chart drill-down be reachable by keyboard and screen reader? (6.2)
- Should History and the triage row agree on a job's name? (6.2)
- Should a donut drill-down pin the state the slice counted rather than the state now, or should the page say counts can lag? (6.1)
- Should "Failed" mean the same set of states on the health page and in History? (6.2)

## Proposed flows

- none. Referenced: flow-history-live-updates (retry broadcasts reaching the open History tab).

## Proposed shared

- none. Referenced: shared-project-scope, shared-usage-limits-banner. The workflow-health view annotation lists this flow (its S14 for triage, S15 for the donut legend rows); history-work-orders lists it too.
