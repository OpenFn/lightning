---
id: flow-dashboard-history-drilldown
type: flow
title: From a dashboard number to the work orders behind it
status: not-started
owner:

trigger:
  entry: workflows-index
  exit: history-work-orders
  surfaces:
    - workflows-index
    - history-work-orders
  reachable_when:
    - the project scope gate admits the viewer on both pages (shared-project-scope; index.ex:15 on the dashboard, run_live/index.ex:67 on history)
    - a row link renders only when its count is above zero (dashboard_components.ex:209, :236; workflows-index S25); the two card links always render (dashboard_components.ex:507-514, :534-543)

inherits:
  - shared-project-scope            # both pages; the link is a live navigate inside live_session :default (router.ex:288, :294, :301)
  - shared-usage-limits-banner      # both pages mount :check_limits

url_params:
  - name: filters[workflow_id]
    set_by: workflows-index row links (dashboard_components.ex:214, :241)
    effect: workflow chip reads "Workflow is <name>"; only that workflow's work orders are listed (index.html.heex:62-73, invocation.ex:713-717)
  - name: filters[date_after]
    set_by: workflows-index, every drill-down link, from DashboardStats.window_start/0 at render (dashboard_components.ex:84-91, :119-122, :494-499; dashboard_stats.ex:226-228)
    effect: last activity chip reads "Last activity after <D-Mon>"; work orders with last_activity >= that instant are listed (index.html.heex:206-226, index.ex:839-879, invocation.ex:741-747)
  - name: filters[failed|crashed|killed|exception|lost|rejected]=true
    set_by: workflows-index failed count and "View all" (dashboard_components.ex:84-91, :241, :537), from WorkOrder.failure_states/0
    effect: status chip reads "Status in Failed, Crashed, Killed, Exception, Lost, Rejected" (index.ex:104-115, index.html.heex:116-135, search_params.ex:134-136, invocation.ex:719-723)
  - name: filters[pending]=true, filters[running]=true
    set_by: workflows-index "N pending" on the Work Orders card (dashboard_components.ex:494-499, :509)
    effect: status chip reads "Status in Enqueued, Running"
  - name: filters[log]=true
    set_by: every drill-down link, via SearchParams.to_uri_params/1 (search_params.ex:157-175)
    effect: the "Include run logs" search toggle is on; no search term is sent, so nothing is filtered by it

config_variants:
  default: {}                       # read under this variant; neither hop reads config on this path

inventory:
  routes:
    - live /projects/:project_id/w  WorkflowLive.Index :index           # entry, owned by workflows-index (router.ex:301)
    - live /projects/:project_id/history  RunLive.Index :index          # exit, owned by history-work-orders (router.ex:294)
  events: []                        # every hop is a <.link navigate>; no handle_event on the path
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:access_project, via shared-project-scope on landing)
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - the "Runs" and "Successful Runs" cards carry no link (dashboard_components.ex:517-528); see 6.2

related:
  - lib/lightning_web/live/workflow_live/index.ex
  - lib/lightning_web/live/workflow_live/dashboard_components.ex
  - lib/lightning/dashboard_stats.ex
  - lib/lightning/workorders/workorder.ex
  - lib/lightning/workorders/search_params.ex
  - lib/lightning/workflows.ex
  - lib/lightning/invocation.ex
  - lib/lightning_web/live/run_live/index.ex
  - lib/lightning_web/live/run_live/index.html.heex
  - lib/lightning_web/pagination.ex
  - test/lightning_web/live/workflow_live/index_test.exs
  - test/lightning/dashboard_stats_test.exs
  - test/lightning/invocation_test.exs
  - test/lightning_web/live/run_live/index_test.exs
flows: []
---

## 1. Purpose

Project members read the workflows page to judge how each workflow did over the last 30 days, then
click a number to see the work orders behind it. The number and the list must agree: if the
failed count says 3 and History shows 2, or shows cancelled work orders as failures, people either
miss a failure that needs a retry or chase one that isn't there.

## 2. What it does

1. Any project member reads the workflows page, which counts each workflow's work orders over the last 30 days of activity.
2. They click a number to see what it counted.
   - A workflow's work order count, or its failed count.
   - "N pending" on the Work Orders card, or "View all" on the failed work orders card, for the whole project.
3. The history page opens already filtered to match: the workflow (if any), "Last activity after" the start of the 30-day window, and the right statuses.
   - "Failed" covers every failure state (failed, crashed, killed, exception, lost and rejected) but never cancelled work.
   - "Pending" covers enqueued and running.
4. The list shows the same work orders the number counted, judged by last activity rather than when they were received.
5. They can search the narrowed list straight away, including in run logs.

**Straightforwardness: 3 of 5.** Clicking a number to see its list is obvious, but in a few common cases the number and the list don't match, and nothing tells you why.

### Most surprising behaviours

- **(3)** The summary cards are totalled over your dashboard search, but their links open the whole project. Search for "sync" and the failed card may say 1 while "View all" lists 5. (6.1)
- **(3)** The cards leave out deleted workflows, but the history page still lists their work orders, so a failed card of 1 can open a list of 3. (6.1)
- **(3)** The list is worked out when you click, not when the number was counted. Work that arrived since shows up, and pending work that has since finished drops out of the pending list. (6.2)
- **(4)** A big 30-day drill-down can time out on the history page even though the dashboard managed to count it. (6.4)
- **(4)** The "Runs" and "Successful Runs" cards can't be clicked, while the other card links show even at zero and open an empty list. (6.2)

## 3. Who can do what

Source: both pages sit behind the shared project scope gate (`workflow_live/index.ex:15`,
`run_live/index.ex:67`); following a link calls no policy. `lib/lightning/policies/project_users.ex:134`
denies everything when the project's MFA requirement is unmet.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the counts and their links | yes | yes | yes | yes | no | yes, when support access is on |
| Land on the filtered history | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Row links exist only for counts above zero (`dashboard_components.ex:209`, `:236`).
- Retrying or cancelling what was found is history-work-orders' own authorisation, not this flow's.

## 4. What it touches

**Reads**
- Hop 1 (dashboard): `workflows` not deleted, with `triggers`, `edges`, `jobs` (`workflows.ex:826-845`); `work_orders` with `last_activity > window_start`, grouped by workflow and state (`dashboard_stats.ex:230-248`); `runs` and `steps` for the other figures (`dashboard_stats.ex:250-299`)
- Hop 2 (history): `workflows` for the chip (`run_live/index.ex:84-86`); `work_orders` joined to `workflows` of the project, filtered by the link's params, with `runs`, `steps`, `jobs`, `dataclips`, `workflow_snapshots`, `triggers`, `webhook_auth_methods` preloaded (`invocation.ex:567-594`, `:641-704`)

**Writes**
- none on either hop

**Immediate side effects**
- Hop 1: none; the links are built at render (`dashboard_components.ex:115-122`, `:489-500`)
- Hop 2: the page subscribes to the project's work order events (`run_live/index.ex:82`; owned by flow-history-live-updates) and emits a `[:lightning, :ui, :projects, :history]` telemetry span carrying the provided filters (`run_live/index.ex:204-222`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- Every count and every link covers the last 30 days of last activity (`dashboard_stats.ex:15`, `:226-232`)
- History lists ten work orders per page with "Showing 1 to 10 of N total results" (`repo.ex:6`, `pagination.ex:121-131`)

## 5. Scenarios

Verified against `default`. The links' existence and their URLs are workflows-index S24 and S25;
the chips' general behaviour and clearing them are history-work-orders S03 to S05. This flow owns
the agreement between the number clicked and the list that opens.

```gherkin
Feature: From a dashboard number to the work orders behind it
  In order to inspect the work orders behind a number on the workflows page
  As a member of a project
  I want each number to open History showing exactly what it counted

  Background:
    Given I am a viewer on project "Malawi HIV"
    And workflow "Intake" had 4 work orders with activity in the last 30 days: 2 success, 1 crashed, 1 cancelled

  @S01 @pending
  Scenario: A workflow's work order count opens those work orders
    # Value: someone checking a busy or quiet workflow sees the same work orders the number counted, without rebuilding the filter.
    When I click the "4" work order count on the "Intake" row
    Then I am on the history page of "Malawi HIV"
    And the workflow chip reads "Workflow is Intake"
    And the status chip reads "Status is any"
    And the last activity chip reads "Last activity after" the date 30 days ago
    And I see "of 4 total results"
    # dashboard_components.ex:115-122, :209-219; dashboard_stats.ex:52-80, :234-248
    # run_live/index.ex:181-222; index.html.heex:62-73, :116-135, :206-226; invocation.ex:713-723, :741-747; pagination.ex:121-131
    # index_test.exs:219-242 (asserts the URL only)

  @S02 @pending
  Scenario: A failed count opens every failure state and nothing that was stopped on purpose
    # Value: people investigating failures see every work order that needs attention, and a cancelled work order is never presented as a failure.
    Given "Intake" also had 1 rejected and 1 lost work order in the last 30 days
    When I click the "3" failed count on the "Intake" row
    Then the status chip reads "Status in Failed, Crashed, Killed, Exception, Lost, Rejected"
    And I see "of 3 total results"
    And I do not see the cancelled or successful work orders
    # workorder.ex:24-29, :50-67; dashboard_stats.ex:102, :244; dashboard_components.ex:84-91, :236-247
    # run_live/index.ex:104-115; search_params.ex:134-136, :153-155; invocation.ex:645-655, :719-723
    # dashboard_stats_test.exs:102-142 (cancelled not counted as failed); index_test.exs:173-185, :244-259 (URL only)

  @S03 @pending
  Scenario: Count and list use last activity, not the received date
    # Value: an old work order retried this month is counted and listed, and one untouched for a month is in neither, so the two never disagree about what "last 30 days" means.
    Given work order "Old" on "Intake" was received 40 days ago and had activity yesterday
    And work order "Stale" on "Intake" had its last activity 31 days ago
    When I open the workflows page
    Then the "Intake" count includes "Old" and not "Stale"
    When I click that count
    Then I see "Old"
    And I do not see "Stale"
    # dashboard_stats.ex:230-236; invocation.ex:741-747
    # dashboard_stats_test.exs:126-140; invocation_test.exs:1716-1758

  @S04 @pending
  Scenario: The pending link opens the queued and running work orders
    # Value: someone wondering why work is backing up sees what is still waiting or in progress.
    Given the project has 2 enqueued and 1 running work order in the last 30 days, all on workflows that are not deleted
    When I click "3 pending" on the "Work Orders" card
    Then the workflow chip reads "Workflow is any"
    And the status chip reads "Status in Enqueued, Running"
    And I see "of 3 total results"
    # workorder.ex:24, :66; dashboard_stats.ex:159-205; dashboard_components.ex:489-516
    # run_live/index.ex:104-106; invocation.ex:719-723; index_test.exs:144-156 (URL only)

  @S05 @pending
  Scenario: "View all" on the failed card opens every failed work order in the project
    # Value: someone who sees a project-wide failure figure can triage all of it from one list.
    Given workflow "Sync" had 2 failed work orders in the last 30 days
    When I click "View all" on the "Work Orders in failed state" card
    Then the workflow chip reads "Workflow is any"
    And the status chip reads "Status in Failed, Crashed, Killed, Exception, Lost, Rejected"
    And I see "of 3 total results"
    # dashboard_components.ex:84-91, :529-543; dashboard_stats.ex:159-205; index_test.exs:168-185 (URL only)

  @S06 @pending
  Scenario: A search typed after drilling down still finds matches
    # Value: people can narrow the drilled-down list by a log message instead of getting an empty page.
    When I click the "4" work order count on the "Intake" row
    Then the "Include run logs" search toggle is on
    When I search for "timeout"
    Then I see the "Intake" work orders from the last 30 days whose run logs contain "timeout"
    # search_params.ex:140-151, :163-175; index.html.heex:405-415; run_live/index.ex:253-261
    # index_test.exs:148, :227 (assert filters[log]=true in the URL)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Card figures are summed over the searched list, but the card links open the whole project (also workflows-index 6.1) | `workflow_live/index.ex:144-163`, `dashboard_components.ex:494-499`, `:537` | after searching "sync", the failed card shows 1 and "View all" lists 5 | fix |
| Card figures exclude deleted workflows (only listed workflows are counted) while History's project query includes their work orders | `workflows.ex:832`, `dashboard_stats.ex:57`, `invocation.ex:675-685` | after deleting a workflow that failed this month, the failed card shows 1 and "View all" lists 3 | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Counts use `last_activity > window_start` computed at query time; links use `>=` with a second `window_start` computed at render, a few milliseconds later, so a work order whose last activity falls in that gap is counted but not listed | `dashboard_stats.ex:226-232`, `dashboard_components.ex:84-91`, `:119-122`, `:494-499`, `invocation.ex:743-745` | decide (the rebuild could pass one instant to both) |
| Links carry no `date_before`, and the dashboard does not live-update, so History evaluates at click time: work that arrived or finished after the page rendered shows up, and a pending work order that has since finished drops out of the pending list | `dashboard_components.ex:119-122`, `:494-499`; no `handle_info` in `workflow_live/index.ex` | decide |
| The "Runs" and "Successful Runs" cards have no link; they count runs, while History lists work orders | `dashboard_components.ex:517-528`, `dashboard_stats.ex:250-276` | decide |
| Card links render even when their figure is 0 and open an empty History; row links are hidden at 0 | `dashboard_components.ex:507-514`, `:534-543` vs `:209`, `:236` | decide |
| The last activity chip shows only the day ("after 14-Sep"), in UTC, while the window is an exact instant | `run_live/index.ex:839-847`, `:865-879` | preserve |
| Following a link drops the dashboard's `q`, `sort` and `dir`; back navigation restores them from the URL | `dashboard_components.ex:214`, `:241`, `workflow_live/index.ex:115-128` | preserve |
| Links set no `sort_by`, so History falls back to last activity descending, nulls first, without the sort chip naming it | `invocation.ex:1527-1530` | preserve |
| Status flags are expanded from `WorkOrder.failure_states/0` at render, so a new failure state joins both the count and the link without code changes here | `dashboard_components.ex:82-91`, `workorder.ex:50` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The landing search times out after 30 seconds and shows a load error, so a large 30-day drill-down can fail where the count succeeded | `invocation.ex:43`, `:577`, `index.html.heex:634-640` | yes | preserve |
| Every dashboard render runs five stats queries; History runs one paginated search with heavy preloads | `dashboard_stats.ex:57-66`, `invocation.ex:687-704` | no | preserve |

### 6.5 Things seen but not understood

- Every link test asserts only the URL pattern (`index_test.exs:144-259`); nothing checks that History lists the work orders the dashboard counted. (preserve)
- Those tests match the window by `Date.to_string(DashboardStats.window_start())` computed separately from the render, so a run straddling midnight UTC could fail (`index_test.exs:144-149`, `:173-178`, `:223-228`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the card figures and their links both follow the dashboard search, or both cover the whole project (see 6.1)?
- Should work orders of deleted workflows count toward the cards, or be excluded from the card links (see 6.1)?
- Should a drill-down freeze the window at the time the count was taken (`date_before`), or keep showing the live state at click time (see 6.2)?

## Proposed flows

none

## Proposed shared

none

## Summary

- Scenarios: 6 (S01 to S06), all `@pending`.
- Section 6: 6.1 has 2, 6.2 has 8, 6.3 has 0, 6.4 has 2, 6.5 has 2.
- Flows: none proposed; references workflows-index S24 and S25, history-work-orders S03 to S05, flow-history-live-updates for the landing subscription.
- Shared: inherits shared-project-scope and shared-usage-limits-banner; none proposed.
- Unsure: history-work-orders does not list this flow in its `flows:` (flow lint will flag it); S04 and S05 assume no deleted workflows and no dashboard search, because of the 6.1 mismatches.
