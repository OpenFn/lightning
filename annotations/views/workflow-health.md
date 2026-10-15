---
id: workflow-health
type: view
title: Workflow health
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id/health
  new_route: /projects/:project_id/w/:id/health
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; health.ex:10)
    - the workflow belongs to the project and is not deleted, otherwise the page redirects to the workflow list with "Workflow not found" (health.ex:11; hooks.ex:138-158; workflows.ex:1330-1336; query.ex:35-40)
    - the React component's three data requests pass the API controller's own check, which repeats the project and workflow test (workflow_health_controller.ex:110-133)

inherits:
  - shared-authenticated-session    # router.ex:189-190 (require_authenticated_user), :288 (live_session :default, InitAssigns)
  - shared-project-scope            # health.ex:10; its S12 is the deleted-workflow redirect, which this page takes via health.ex:11
  - shared-project-header           # health.ex:28-46 (project picker, "Workflows" and workflow crumbs, "Health")
  - shared-flash-messages   # added by lead (final pass)
  # Not inherited: shared-usage-limits-banner (no :check_limits on_mount, no :banner slot; health.ex:10-11, :28-63),
  # shared-local-datetime and shared-run-components (nothing on this page renders Common.datetime or run components).

url_params:
  - name: project_id
    set_by: every project link
    effect: owned by shared-project-scope
  - name: id
    set_by: workflows-index "Health" link (dashboard_components.ex:282-289), email:failure-alert (failure_alerter.ex:81-85, failure_alert.html.heex:19-21), email:project-digest (user_notifier.ex:373-379)
    effect: the workflow whose health is shown; another project's or a deleted workflow redirects to the workflow list (S03)
  # The page itself takes no query params. The range (days) and tab live in React state only (WorkflowHealth.tsx:42, :78-91),
  # so a reload or a shared link always opens on "Last 7 days" and "Work orders" (6.2).

config_variants:
  default: {}                                                   # read under this one; project.history_retention_period nil (history kept forever), so every range is enabled
  history-retention-14: { project.history_retention_period: 14 }   # project setting; data_retention_options are 7, 14, 30, 90, 180, 365 (project.ex:65-68), so only "Last 30 days" can ever be disabled

inventory:
  routes:
    - live /projects/:project_id/w/:id/health  WorkflowLive.Health :show                                  # router.ex:304
    - get /api/projects/:project_id/workflows/:workflow_id/health/outcomes  API.WorkflowHealthController :outcomes           # router.ex:142-144
    - get /api/projects/:project_id/workflows/:workflow_id/health/failures  API.WorkflowHealthController :error_signatures   # router.ex:146-148
    - get /api/projects/:project_id/workflows/:workflow_id/health/runs  API.WorkflowHealthController :runs                   # router.ex:150-152
  events: []                         # WorkflowLive.Health has no handle_event, handle_info or handle_params (health.ex:1-66)
  # handle_info Projects.Events.WorkflowDeleted arrives through the project-scope hook (hooks.ex:325-335); owned by shared-project-scope S12
  js_hooks:
    - ReactComponent WorkflowHealth  # health.ex:50-60; assets/js/health/WorkflowHealth.tsx
    # The component also uses the React Tooltip (RangePicker.tsx:3, :40-46) and Recharts tooltips (ChartTooltip.tsx); neither is a LiveView hook
  policies:
    - Lightning.Policies.ProjectUsers :access_project   # workflow_health_controller.ex:121; project_users.ex:134, :136, :193-194
    # The LiveView itself evaluates no policy beyond shared-project-scope
  workers: []
  api_endpoints:
    - GET .../health/outcomes   (Workflows.Stats.outcomes/2; workflow_health_controller.ex:24-29; stats.ex:45-67)
    - GET .../health/failures   (Workflows.Stats.error_signatures/2; workflow_health_controller.ex:31-39; stats.ex:80-93, :360-573)
    - GET .../health/runs       (Workflows.Stats.runs/3, x-timezone header; workflow_health_controller.ex:43-53, :85-108; stats.ex:154-291)
  emails: []                         # inbound only: email:failure-alert and email:project-digest link here
  config:
    - Cachex :workflow_stats child (application.ex:71-73, :180)
    - project.history_retention_period (health.ex:59; RangePicker.tsx:34-35)
  not_reachable_here:
    - Hooks.on_mount(:ensure_workflow_belongs_to_project) fallback clause with no "id" param (hooks.ex:160-167); this route always has :id (6.3)
    - Workflows.Stats default days_back 30 (stats.ex:29, :45, :80); the controller always passes 1, 7 or 30 (6.3)
    - Workflows.Stats.boundaries/3 is public for the stats test only (stats.ex:182-192; stats_test.exs:762)

related:
  - workflows-index                  # "Health" link on each row (its S23)
  - history-work-orders              # every drill-down link lands there
  - lib/lightning_web/live/workflow_live/health.ex
  - lib/lightning_web/controllers/api/workflow_health_controller.ex
  - lib/lightning/workflows/stats.ex
  - assets/js/health/
  - test/lightning_web/live/workflow_live/health_test.exs
  - test/lightning_web/controllers/api/workflow_health_controller_test.exs
  - test/lightning/workflows/stats_test.exs
  - assets/test/health/
flows:
  - flow-workflow-health-drilldown            # entry: triage "View history" and runs-chart bands
  - flow-failure-alert-email                  # alternate exit: the email's health link lands here
  - flow-digest-email                         # its S06: the digest's health link lands here
  - flow-delete-open-workflow                 # its S01 "the health page" row: this page also leaves
  - flow-login-return-to
---

## 1. Purpose

People who look after a workflow open its health page to answer "is this workflow delivering,
and if not, what is breaking and where?" without scrolling through History. It shows how the
workflow's work orders ended over the last day, week or month, which errors and steps account
for the failures, and when runs succeeded or failed, with each number leading to the work orders
behind it. Without it, a team would only see failures one alert or one History row at a time,
and could not tell a single recurring fault from many unrelated ones, or see whether a fix is
bringing failures down.

## 2. What it does

- **Get to the page and away from it** (anyone on the project)
  - Open a workflow's health page from the workflow list, a failure alert or a digest email
  - Go back to the workflow's editor from the page
  - Get moved to the workflow list if the workflow is deleted while the page is open
- **See how the work ended**
  - How the window's finished work orders ended, with the success rate
  - The failed work orders broken down by the state they ended in
  - Runs over time, stacked by outcome, on the viewer's own clock
- **See what's breaking**
  - Which steps the failures land on, heaviest first
  - The failures grouped by error, heaviest first, with a suggestion for each error type
- **Drill into History**
  - Open History filtered to one error group, one outcome or failure state, or one band of one bar of the runs chart
- **Choose the window and keep it reliable**
  - Pick the last 24 hours, 7 days or 30 days, but never a window longer than the project keeps history
  - Numbers update without reloading, and charts that loaded stay up when another one fails
  - Nobody reads another project's workflow health, through the page or the data behind it

**Straightforwardness: 3 of 5.** The charts are easy to read, but what gets counted (retries, failures in two branches, which window an old work order falls into) takes some explaining.

### Most surprising behaviours

- **(2)** If the automatic refresh starts failing, for example after your session expires, the page keeps showing the old numbers with nothing to say they've stopped updating. Someone watching after a fix could wait for a drop that never shows. (6.1, S23)
- **(3)** Counting follows the latest attempt: a work order that failed and was retried to success counts as a success, and an old work order retried today counts in today's window. Good for seeing a fix work, but the numbers can move for work that happened weeks ago. (S05, S11, 6.2)
- **(3)** A work order that broke in two branches shows up twice in the triage table, so the triage rows can add up to more than the failure total in the charts beside it. (S12, 6.2)
- **(3)** If the server doesn't recognise the browser's timezone (a very new one), the runs chart never loads and tells the person to refresh, which won't help. (6.1)
- **(4)** The chosen window and tab aren't kept in the link, so a reload, a shared link or a link from an email always opens on the last 7 days. (6.2)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:134` (MFA unsatisfied denies everything), `:136`
and `:193-194` (`:access_project` is a membership row or support access),
`workflow_health_controller.ex:110-133`. The page shows the same thing to every role; there is no
role-dependent control on it. Page gate is shared-project-scope; endpoint gate is the controller
plug, which applies the same policy.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the page | yes | yes | yes | yes | no | yes |
| Read the outcomes, failures and runs data | yes | yes | yes | yes | no | yes |
| Change the range or the tab | yes | yes | yes | yes | no | yes |
| Follow a drill-down link (History applies its own gate) | yes | yes | yes | yes | no | yes |

**Preconditions beyond role**
- Signed in; an anonymous data request is a 401, not a redirect (`router.ex:137-138`; `user_auth.ex:288-293`; `workflow_health_controller_test.exs:63-75`).
- The workflow must belong to the project in the URL and not be deleted, on the page (`hooks.ex:138-158`) and on every endpoint (`workflow_health_controller.ex:113-120`; `workflows.ex:151-157`).
- Every endpoint refusal is a 404, including MFA not enrolled on an MFA-required project and a project scheduled for deletion (`workflow_health_controller.ex:124-131`; `workflow_health_controller_test.exs:149-203`).
- Support users need the project's support access switched on (`workflow_health_controller_test.exs:123-147`).
- A range longer than the project's history retention cannot be picked in the UI (`RangePicker.tsx:34-35`, `:50`); the endpoint does not check retention (6.2).

## 4. What it touches

**Reads**
- Page: `workflows` (`hooks.ex:144-145`; `health.ex:15`), `projects` (`history_retention_period`, `health.ex:59`), plus the project-scope reads (shared-project-scope)
- Endpoints: `workflows` with `projects` (`workflow_health_controller.ex:116-120`), `project_users` via the policy scope
- Outcomes: `work_orders` grouped by state (`stats.ex:57-67`)
- Failures: `work_orders`, `runs`, `steps`, `run_steps`, `workflow_snapshots` jobs JSON (`stats.ex:367-488`)
- Runs: `runs` joined to `work_orders` (`stats.ex:263-291`)
- Change marker: max `last_activity` of the workflow's settled `work_orders`, on every outcomes and failures request (`stats.ex:317-321`, `:351-358`)

**Writes**
- No database writes
- Cachex `:workflow_stats` entries: `{:outcomes | :failures, workflow_id, days, marker}` for 5 minutes, `{:runs, workflow_id, days, timezone}` for 2 minutes (`stats.ex:33-37`, `:47`, `:85`, `:165-169`, `:317-339`)

**Immediate side effects**
- On load, on each range change, every 30 seconds while the tab is visible, and on returning to the tab: three cookie-authenticated GETs, each with an `x-timezone` header (`WorkflowHealth.tsx:48-56`; `useHealthQuery.ts:30-65`, `:103-136`)
- The runs reply carries `vary: x-timezone` (`workflow_health_controller.ex:41-53`)
- Drill-down links open History in a new tab (`TriageTable.tsx:158-167`; `Donut.tsx:87-91`, `:131-134`; `VolumeBars.tsx:182-191`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `project.history_retention_period` disables ranges longer than it (variant `history-retention-14`)
- Tzdata's zone list decides which `x-timezone` values are accepted (`workflow_health_controller.ex:93-96`)

**Product limits**
- Ranges are fixed at 24 hours, 7 days and 30 days, default 7 days; anything else is a 400 (`RangePicker.tsx:7-13`; `workflow_health_controller.ex:56-76`)
- Runs chart bars are 2-hourly over 24 hours, half-daily over 7 days and daily over 30 days (`stats.ex:108`)
- Numbers can lag by up to 5 minutes (outcomes, failures) or 2 minutes (runs) plus one 30-second poll (`stats.ex:33-37`; `useHealthQuery.ts:105`)

## 5. Scenarios

Verified by reading against `default`, and S17 against `history-retention-14`. Login, MFA,
membership and support access on the page itself are shared-project-scope S01 to S10; the
breadcrumbs, picker and side menu are shared-project-header.

```gherkin
Feature: Workflow health
  In order to find out whether a workflow is delivering and what to fix first
  As a member of a project
  I want one page that summarises a workflow's outcomes, failures and run volume over a window I pick

  Background:
    Given I am a viewer on project "Malawi HIV"
    And workflow "Daily sync" has jobs "Fetch" and "Load"

  @S01 @pending
  Scenario: A member opens a workflow's health page from the workflow list
    # Value: someone looking after a workflow gets its state in one place, without building History filters.
    Given I am on the workflows page of "Malawi HIV"
    When I click "Health" on the "Daily sync" row
    Then I am on "/projects/<project_id>/w/<daily_sync_id>/health"
    And I see the heading "Daily sync"
    And the breadcrumbs end "Workflows", "Daily sync", "Health"
    And "Last 7 days" is selected
    And the "Work orders" tab is selected, showing "Outcomes", "Failure breakdown" and "Steps with failures"
    And I see "Triage - grouped by failure type"
    # entry link owned by workflows-index S23 (dashboard_components.ex:282-289)
    # health.ex:14-22, :28-60; WorkflowHealth.tsx:42, :58-189; RangePicker.tsx:13
    # health_test.exs:12-19; WorkflowHealth.test.tsx:292-299, :337-359; index_test.exs:542-554

  @S02 @pending
  Scenario: The workflow crumb leads back to its editor
    # Value: someone who has found the failing step can go straight to fixing it.
    Given I am on the health page of "Daily sync"
    When I click "Daily sync" in the breadcrumbs
    Then I am in the editor for "Daily sync"
    # health.ex:37-40; health_test.exs:21-33

  @S03 @pending
  Scenario Outline: A workflow that is not in this project, or is deleted, is not shown
    # Value: a guessed or stale URL can't show a workflow from another project or one that was deleted.
    Given <workflow>
    When I visit its health page under project "Malawi HIV"
    Then I am on the workflows page of "Malawi HIV"
    And I see "Workflow not found"
    Examples:
      | workflow                                                  |
      | workflow "Kenya sync" belongs to project "Kenya TB"       |
      | workflow "Old intake" in "Malawi HIV" has been deleted     |
    # hooks.ex:138-158; workflows.ex:1330-1336; query.ex:35-40
    # health_test.exs:35-46 (other project only; the deleted row is read from query.ex:37, not tested on the page)

  @S04 @pending
  Scenario: Outcomes count each finished work order once, with the success rate in the middle
    # Value: the share of work that actually got through is visible at a glance and isn't skewed by work still running or stopped on purpose.
    Given in the last 7 days "Daily sync" had 9 successful, 1 failed, 1 crashed and 2 cancelled work orders
    And 1 work order is still running
    When I open its health page
    Then the "Outcomes" card meta reads "13 work orders"
    And the legend reads "Success 9", "Failed 2", "Cancelled 2"
    And the middle of the ring reads "81.8%" and "success"
    # stats.ex:53-67 (final states only); OutcomesDonut.tsx:50-91; types.ts:14-21, :35-36; WorkflowHealth.tsx:97-99, :250-253
    # stats_test.exs:94-133; OutcomesDonut.test.tsx:41-53, :73-98, :126-136; workflow_health_controller_test.exs:233-276

  @S05 @pending
  Scenario: A work order retried to success counts as a success
    # Value: retrying failures makes this page's failure numbers fall, so a team can see a fix working.
    Given a "Daily sync" work order whose first run failed and whose retry succeeded in the last 7 days
    When I open its health page
    Then "Outcomes" shows "Success 1" and "Failed 0"
    And the triage table shows "No failures in the last 7 days"
    # stats.ex:53-61 (work order state, not run state); WorkflowHealth.tsx:20-23
    # stats_test.exs:135-152

  @S06 @pending
  Scenario: A single failure is never rounded away
    # Value: a workflow with any failure never reads as 100% successful.
    Given in the last 7 days "Daily sync" had 2,500 successful and 1 failed work order
    When I open its health page
    Then the middle of the ring reads "<100%"
    # Donut.tsx:40-48; OutcomesDonut.tsx:83-89; OutcomesDonut.test.tsx:56-69

  @S07 @pending
  Scenario: Failures are broken down by the state they ended in
    # Value: people can tell faults in job code from crashes, lost runs and payloads refused over the run limit, which have different fixes.
    Given in the last 7 days "Daily sync" had 3 failed, 1 lost and 2 rejected work orders and 4 cancelled ones
    When I open its health page
    Then "Failure breakdown" lists "failed 3", "lost 1" and "rejected 2" and no other state
    And the middle of its ring reads "6" and "failures"
    And the "Failed" wedge of "Outcomes" also reads 6
    # FailureBreakdownDonut.tsx:51-74; types.ts:14-21; stats.ex:39-40 (rejected is a final state); workorder.ex:48, :50
    # FailureBreakdownDonut.test.tsx:15-131; WorkflowHealth.test.tsx:361-383

  @S08 @pending
  Scenario: Steps with failures shows where failures land, heaviest first
    # Value: the step to look at first is obvious, even when it fails in several different ways.
    Given in the last 7 days 5 work orders failed at "Load", 3 with "RuntimeError" and 2 with "AdaptorError"
    And 2 work orders failed at "Fetch"
    And 1 work order's run was lost before any step reported
    When I open its health page
    Then "Steps with failures" lists "Load 5", then "Fetch 2", then "No failing step 1"
    And each named step shows its adaptor below it
    # StepFailureBars.tsx:46-108, :119-142; adaptorLabel.ts:10-11
    # StepFailureBars.test.tsx:34-48, :56-80

  @S09 @pending
  Scenario: Triage groups failures by error, heaviest first, with a suggestion
    # Value: a team sees the few distinct faults behind many failures and a plain-language hint for each.
    Given in the last 7 days 4 work orders failed with "RuntimeError" at "Load" and 1 with "CompileError" before any step ran
    When I open its health page
    Then the first triage row reads "4", "Failed", "fail:RuntimeError @ Load" and "Job code hit a value it didn't expect, often a missing input field."
    And the second row reads "1", "crash:CompileError" with no step and "Job code couldn't be compiled, so no step ever ran."
    # stats.ex:431-466, :513-556; TriageTable.tsx:20-64, :75-145, :213-250
    # stats_test.exs:306-328, :406-426, :480-503; TriageTable.test.tsx:28-62, :83-122

  @S10 @pending
  Scenario: Work orders refused over the run limit get their own triage row
    # Value: payloads that never ran are not mistaken for job failures, and the reason is named.
    Given in the last 7 days 2 webhook requests to "Daily sync" were rejected over the run limit
    When I open its health page
    Then a triage row reads "2", "rejected:RunLimitExceeded" and "The project was over its run limit, so no run was created for this request."
    # stats.ex:490-503; TriageTable.tsx:61-62; stats_test.exs:427-446; TriageTable.test.tsx:64-81

  @S11 @pending
  Scenario: A retried work order is triaged by its latest attempt only
    # Value: a failure that was retried into a different failure is reported once, as what is wrong now.
    Given a "Daily sync" work order failed with "FirstAttempt" at "Fetch", then its retry failed with "Retry" at "Load"
    When I open its health page
    Then the triage table has one row, "fail:Retry @ Load", with count 1
    # stats.ex:401-423; stats_test.exs:505-534

  @S12 @pending
  Scenario: A work order that broke in two branches is triaged under both
    # Value: a second broken branch is shown as its own fault rather than hidden behind the first.
    Given a "Daily sync" work order whose latest run failed at both "Fetch" and "Load"
    When I open its health page
    Then the triage table has a row for "Fetch" and a row for "Load", each with count 1
    And "Outcomes" counts the work order once
    # stats.ex:8-11, :360-399; StepFailureBars.tsx:16-20; stats_test.exs:536-582

  @S13 @pending
  Scenario: A step is named as it was when it failed
    # Value: a triage row stays recognisable after the job is renamed or deleted.
    Given job "Load" failed in the last 7 days and was then renamed to "Load to DHIS2"
    When I open its health page
    Then the triage row names the step "Load"
    When "Load to DHIS2" then fails with the same error
    Then the two failures are one row, named "Load to DHIS2"
    # stats.ex:425-430, :468-488, :545-573; stats_test.exs:329-387

  @S14 @pending
  Scenario: Triage "View history" starts the drill-down flow
    # Value: the person triaging one error lands on exactly that error's work orders.
    Given the triage row "fail:RuntimeError @ Load" shows 2
    When I click "View history" on that row
    Then the flow "flow-workflow-health-drilldown" has started (its S01)
    And this page stays open in this tab
    # TriageTable.tsx:130-137, :154-196; historyUrl.ts:13-36

  @S15 @pending
  Scenario: An outcome or failure state opens the work orders it counts
    # Value: any slice of the donuts can be inspected without rebuilding the filter in History.
    Given "Outcomes" shows "Failed 6"
    When I click "Failed" in the "Outcomes" legend
    Then the flow "flow-workflow-health-drilldown" has started
    And this page stays open in this tab
    # Donut.tsx:87-91, :128-152; OutcomesDonut.tsx:57-76; FailureBreakdownDonut.tsx:66; historyUrl.ts:47-56
    # OutcomesDonut.test.tsx:154-195; FailureBreakdownDonut.test.tsx:133-150

  @S16 @pending
  Scenario: Runs over time are drawn on my own clock and say so
    # Value: a bar labelled "Mar 3" or "14:00" means the reader's own day and hour, so failures line up with what they know happened locally.
    Given my browser's timezone is "Africa/Nairobi"
    And a run of "Daily sync" failed at 11:30 UTC today
    When I open its health page with "Last 24 hours" and choose the "Runs" tab
    Then I see "Runs over time" with the meta "2-hour buckets · Africa/Nairobi"
    And the failed run is in the bar starting 14:00
    And hovering that bar shows "<today>, 14:00 – 16:00"
    # useHealthQuery.ts:55-65; workflow_health_controller.ex:43-53, :85-101; stats.ex:108, :154-249; VolumeBars.tsx:229-238, :269-328
    # workflow_health_controller_test.exs:410-430; stats_test.exs:722-757, :844-862; VolumeBars.test.tsx:103-110, :148-157

  @S17 @pending
  Scenario: A browser that can't name its timezone gets UTC, and is told
    # Value: the chart never silently uses a clock the reader didn't choose without naming it.
    Given my browser reports its timezone as "Etc/Unknown"
    When I open the "Runs" tab of the health page
    Then the meta ends "Etc/UTC"
    # workflow_health_controller.ex:58-63, :86-91; workflow_health_controller_test.exs:431-462

  @S18 @pending
  Scenario: Changing the range redraws every panel for the new window together
    # Value: numbers from two different windows are never on screen side by side.
    Given I am on the health page of "Daily sync" showing "Last 7 days"
    When I choose "Last 30 days"
    Then every panel shows a loading placeholder until its new numbers arrive
    And no panel shows numbers or an empty message for the 7-day window
    # useHealthQuery.ts:35-46; WorkflowHealth.tsx:50-56, :214-238
    # WorkflowHealth.test.tsx:301-320, :472-541

  @S19 @pending @variant:history-retention-14
  Scenario: A range longer than the project keeps history is not offered
    # Value: nobody reads a 30-day window whose older half has been purged as a quiet month.
    Given project "Malawi HIV" keeps history for 14 days
    When I open the health page of "Daily sync"
    Then "Last 30 days" is disabled
    And hovering it shows "Only 14 days of history are kept for this project."
    And "Last 24 hours" and "Last 7 days" are enabled
    # health.ex:59; RangePicker.tsx:22-60; health_test.exs:48-70
    # WorkflowHealth.test.tsx:543-582

  @S20 @pending
  Scenario: An empty window says so
    # Value: a quiet workflow reads as quiet, not as a broken chart.
    Given "Daily sync" had no finished work orders in the last 24 hours
    When I open its health page with "Last 24 hours"
    Then "Outcomes" reads "No finished work orders in the last 24 hours"
    And "Failure breakdown", "Steps with failures" and the triage table read "No failures in the last 24 hours"
    # Donut.tsx:53-57; StepFailureBars.tsx:52-54; TriageTable.tsx:82-84; VolumeBars.tsx:107-111; WorkflowHealth.tsx:255-270
    # WorkflowHealth.test.tsx:322-335; OutcomesDonut.test.tsx:138-152

  @S21 @pending
  Scenario: An open page updates on its own
    # Value: someone watching after a fix sees failures fall without reloading.
    Given I have the health page of "Daily sync" open and visible
    When a work order of "Daily sync" settles as failed
    Then within a few minutes "Outcomes" counts it without a reload
    And when I switch to another browser tab and back, the page asks for fresh numbers at once
    # useHealthQuery.ts:103-136 (30 s, visible only, and on visibilitychange); stats.ex:317-358 (marker moves when a work order settles)
    # WorkflowHealth.test.tsx:153-257; stats_test.exs:196-228

  @S22 @pending
  Scenario: One failing chart does not take the page with it
    # Value: when one query is slow or broken, people still get the charts that answered.
    Given the failures data cannot be loaded
    When I open the health page of "Daily sync"
    Then "Steps with failures" and the triage table show "Could not load workflow stats. Refresh to try again."
    And "Outcomes" and "Failure breakdown" show their numbers
    And no server error text is shown
    # WorkflowHealth.tsx:214-238; useHealthQuery.ts:8, :27-28, :66-93; stats.ex:323-338
    # WorkflowHealth.test.tsx:401-454

  @S23 @pending
  Scenario: A failed refresh keeps the numbers on screen
    # Value: a momentary error doesn't blank the page someone is reading, and it recovers on the next refresh.
    Given I have the health page of "Daily sync" open with its numbers loaded
    When one automatic refresh fails
    Then the previous numbers stay and no error is shown
    And the next successful refresh replaces them
    # useHealthQuery.ts:87-93; WorkflowHealth.test.tsx:259-290

  @S24 @pending
  Scenario Outline: The page's data is served only to people who can open it
    # Value: the data endpoints behind the page never show a workflow's failure counts to someone the page itself would turn away, or confirm the workflow exists.
    Given <who>
    When the browser requests the outcomes, failures or runs data for "Daily sync"
    Then the response is <status>
    Examples:
      | who                                                                         | status |
      | I am a viewer on "Malawi HIV"                                               | 200    |
      | I am a support user and "Malawi HIV" allows support access                  | 200    |
      | I am not signed in                                                          | 401    |
      | I am signed in but not on "Malawi HIV"                                      | 404    |
      | I am a support user and "Malawi HIV" does not allow support access          | 404    |
      | "Malawi HIV" requires MFA and I have not enrolled                           | 404    |
      | "Malawi HIV" is scheduled for deletion                                      | 404    |
      | "Daily sync" has been deleted                                               | 404    |
      | the request names "Daily sync" under project "Kenya TB", which I am not on  | 404    |
    # workflow_health_controller.ex:1-22, :110-133; router.ex:137-153; project_users.ex:134, :136, :193-194
    # workflow_health_controller_test.exs:53-230; flow-workflow-health-drilldown S09 covers the cross-project case for the drill-down slices

  @S25 @pending
  Scenario: A failure alert's health link lands on this page
    # Value: the person alerted can see at once whether the failure is a one-off or part of a pattern.
    Given I received a failure alert for "Daily sync"
    When I follow "this workflow's health"
    Then I am on the health page of "Daily sync"
    And the flow "flow-failure-alert-email" ends on this page
    And if I was signed out, the flow "flow-login-return-to" starts for that URL
    # failure_alerter.ex:81-85; failure_alert.html.heex:19-22; failure_alert_test.exs:152; router.ex:189-190, :304

  @S26 @pending
  Scenario: A digest's health link lands on this page
    # Value: a member who sees failures in a digest can go straight to triage by cause.
    Given my digest lists failures for "Daily sync"
    When I follow "See this workflow's failures grouped by error"
    Then I am on the health page of "Daily sync"
    And the flow "flow-digest-email" ends on this page (its S06)
    # user_notifier.ex:365-382; user_notifier_test.exs:272

  @S27 @pending
  Scenario: Deleting the workflow sends this page to the workflow list
    # Value: nobody keeps reading the health of a workflow that no longer exists.
    Given I have the health page of "Daily sync" open
    When an editor deletes "Daily sync" in another session
    Then shared-project-scope S12 applies to this page
    And the flow "flow-delete-open-workflow" ends here (its S01, "the health page" row)
    # health.ex:11; hooks.ex:151, :320-335
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A failed refresh keeps the last numbers with no sign they are stale, and refreshes keep failing silently for as long as the tab is open (for example after the session expires, which answers 401). The Panel comment speaks of a "polite stamp above" that would fall silent, but no stamp or "last updated" time is rendered | `useHealthQuery.ts:87-93`, `:103-136`; `WorkflowHealth.tsx:226-227`; `user_auth.ex:288-293` | numbers that look current but stopped updating, with nothing to say so | decide |
| A browser timezone that Tzdata does not know yet (a zone newer than the server's tz database) is refused with a 400, so the "Runs" tab shows "Could not load workflow stats" on every load; the controller says this is deliberate | `workflow_health_controller.ex:78-82`, `:93-108`; `useHealthQuery.ts:55-65` | a runs chart that never loads for readers in that zone, with advice to refresh that cannot help | decide |
| "Steps with failures" labels a job with the name from its heaviest triage row, while the triage table labels each row from that row's newest snapshot, so after a rename the two panels can name the same job differently | `StepFailureBars.tsx:125-136`; `stats.ex:551-573` | "Load" in the step bars beside "Load to DHIS2" in the triage table | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The range and tab are React state only, so a reload, a shared link or an email link always opens on "Last 7 days" and "Work orders" | `WorkflowHealth.tsx:42`, `:78-91` | decide |
| The browser tab title reads "Health Stats for <name>" while the heading reads the bare workflow name and the crumb reads "Health" | `health.ex:21`, `:42`; `WorkflowHealth.tsx:61-63` | decide |
| The side menu highlights "Workflows" on this page | `health.ex:19`; `menu.ex:46-52` | preserve |
| The workflow name and retention period reach React once, at mount, behind `phx-update="ignore"`; a rename or a retention change while the page is open shows only after a reload | `health.ex:50-60` | decide |
| The endpoints accept `days=30` whatever the project's retention; only the UI disables it | `workflow_health_controller.ex:56-76`; `RangePicker.tsx:34-35` | preserve |
| `days` is a closed string set: "007", "7.5", "0" and "36500" are all 400 "days must be one of 1, 7, 30"; an access failure answers 404 before a bad `days` can answer 400 | `workflow_health_controller.ex:19-22`, `:56-76`; `workflow_health_controller_test.exs:89-99`, `:533-555` | preserve |
| `x-timezone` goes to all three endpoints, but only runs reads it; an invalid value answers 400 "x-timezone must be an IANA timezone name" | `useHealthQuery.ts:55-65`; `workflow_health_controller.ex:22`, `:85-108`; `workflow_health_controller_test.exs:476-495` | preserve |
| Outcomes and triage count work orders by `last_activity` strictly after the window start, so an old work order retried today is counted in today's window | `stats.ex:53-61`, `:410`; `stats_test.exs:81-92` | preserve |
| The runs chart's oldest bar reaches back past `now - days` and its window differs from the other two slices'; empty-message wording floors the day count | `stats.ex:95-108`, `:194-205`; `WorkflowHealth.tsx:260-270` | preserve |
| On a spring-forward day the runs grid covers one real hour less than the donuts beside it | `stats.ex:105-107`, `:137-140` | preserve |
| Each slice's `window` is cached with its counts, so the window start (and the date on drill-down links) can be up to 5 minutes old | `stats.ex:298-299`, `:317-321` | preserve |
| Triage rows tied on count sort rows with no step name before named ones (Elixir term order puts `nil` before strings) | `stats.ex:555` | decide |
| Triage rows can sum past the failure total in the donuts, by design | `stats.ex:8-11`, `:75-78`; `StepFailureBars.tsx:16-20` | preserve |
| Donut wedges open History by mouse only; the legend rows carry the same links for keyboard and screen readers | `Donut.tsx:82-91`, `:122-152` | preserve |
| "Cancelled" appears in "Outcomes" and the runs chart only when non-zero; "Success" and "Failed" stay at zero | `OutcomesDonut.tsx:66-79`; `VolumeBars.tsx:100-105` | preserve |
| The disabled range explains itself in a hover tooltip only | `RangePicker.tsx:38-46` | decide |
| The error copy says "Refresh to try again", but the panel also recovers on its own at the next 30-second refresh | `useHealthQuery.ts:8`, `:103-136` | decide |
| Switching projects in the picker from this page lands on the other project's workflow list | `layout_components.ex:543-563` (shared-project-header S09, S10) | preserve |
| The breadcrumb links use `patch` to other LiveViews and carry `aria-current="page"` | owned by shared-project-header 6.1 and 6.2 | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `on_mount(:ensure_workflow_belongs_to_project, _params, ...)` fallback that continues without a check | `hooks.ex:160-167` | both routes that mount it carry `:id` (`router.ex:302-304`) |
| `Stats.outcomes/2` and `Stats.error_signatures/2` default `days_back` of 30 | `stats.ex:29`, `:45`, `:80-83` | the controller always passes 1, 7 or 30 (`workflow_health_controller.ex:27`, `:34-37`); only the stats tests use the default |
| `Stats.boundaries/3` public with `@doc false` | `stats.ex:182-192` | called only by `bucket_window/3` and `stats_test.exs:762` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Three requests per open, visible tab every 30 seconds and on every return to the tab; no timer while a read is in flight | `useHealthQuery.ts:103-136` | no | preserve |
| Outcomes and failures cached 5 minutes keyed on a change marker; runs cached 2 minutes with no marker, per timezone | `stats.ex:33-37`, `:156-169`, `:317-358` | yes, counts lag up to that long | preserve |
| The change-marker query runs on every outcomes and failures request, cache hit or not | `stats.ex:317-321`, `:351-358` | no | preserve |
| A work order that is unsettled while something it holds is final stops counting until it settles or the entry expires | `stats.ex:346-348` | yes, briefly | preserve |
| Cachex `:workflow_stats` is per node; each node computes its own copy | `application.ex:71-73` | no | preserve |
| A computation failure is re-raised, so the request is a 500 and the panel shows the generic error | `stats.ex:330-337`; `stats_test.exs:230-256` | yes | preserve |
| Steps with failures scrolls inside its card past a fixed height | `StepFailureBars.tsx:58-66` | yes | preserve |

### 6.5 Things seen but not understood

- `health.ex:15` loads the workflow again with `Workflows.get_workflow!/1`, which raises on a missing row, after the hook has already checked it (`hooks.ex:144-145`). Only a hard delete between the hook and mount could reach the raise; unclear whether anything hard-deletes workflows on that timescale.
- The `Panel` comment in `WorkflowHealth.tsx:226-227` refers to a "polite stamp above" that is not rendered. It may be left over from a removed "last updated" line (see 6.1).
- Superusers without a membership row are refused by both the page and the endpoints (`project_users.ex:136`, `:193-194`). That matches the rest of the project pages, but nothing here says whether it is intended for a read-only stats page.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the range and tab be in the URL, so links from emails and between people open the same view (6.2)?
- Should the page say when its numbers are stale, or stop refreshing after an authentication failure (6.1)?
- Should an unknown but well-formed browser timezone fall back to UTC like "Etc/Unknown" does (6.1)?
- Should the step bars and the triage table agree on a renamed job's name (6.1; flow-workflow-health-drilldown asks the same about History's chip)?
- Should the outcome and failure-state legend links be their own flow or part of flow-workflow-health-drilldown (S15)?
- Should the tab title match the heading (6.2)?

## Proposed flows

- **flow-workflow-health-drilldown** (new): a legend row or wedge in "Outcomes" or "Failure breakdown" opens History in a new tab with `filters[workflow_id]`, `filters[log]=true`, `filters[date_after]` set to the slice's window start and one `filters[<state>]=true` per state the slice counts (all six failure states for "Failed"); History lists those work orders (`Donut.tsx:87-91`, `:128-152`; `OutcomesDonut.tsx:57-76`; `FailureBreakdownDonut.tsx:61-67`; `historyUrl.ts:13-56`; `OutcomesDonut.test.tsx:154-195`). flow-workflow-health-drilldown lists these links as outside its scope (its 6.5); the lead may fold them in instead. Surfaces: workflow-health, history-work-orders.
- **flow-login-return-to** (referenced; proposed by shared-authenticated-session): a signed-out visitor following the failure alert's or digest's health link is sent to log in and returned to the health page afterwards (`router.ex:189-190`). Surfaces: email:failure-alert, email:project-digest, controller:user-session, workflow-health.
- Referenced, existing: flow-workflow-health-drilldown (S14, entry), flow-failure-alert-email (S25, exit), flow-digest-email (S26, exit of its S06), flow-delete-open-workflow (S27).

## Proposed shared

- none. Referenced: shared-authenticated-session, shared-project-scope (S01 to S10 for the page gate, S12 via S27), shared-project-header (S01, S09, S10). The API controller and `Workflows.Stats` are surfaces `controller:workflow-health-api` and `capability:workflow-stats` in flow-workflow-health-drilldown with no annotation file of their own; their behaviour is annotated here (S04 to S13, S16, S17, S24).

## Lead resolution (batch 4)

- `flow-workflow-health-outcome-drilldown` folded into `flow-workflow-health-drilldown`, which now covers the donut legend and wedge links too.
- `flow-login-return-to` created.
