---
id: run-show
type: view
title: Run
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/runs/:id
  new_route: /projects/:project_id/runs/:id
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; show.ex:16)
    - the run belongs to a workflow of this project, otherwise the page redirects to History with "Run not found" (hooks.ex:169-183; show.ex:17)

inherits:
  - shared-authenticated-session    # router.ex:189-190 (require_authenticated_user), :288 (live_session :default)
  - shared-project-scope            # show.ex:16
  - shared-usage-limits-banner      # show.ex:18, :57-63
  - shared-project-header           # show.ex:65-91 (project picker, "History" breadcrumb)
  - shared-run-components           # state pill, step icons, elapsed time, clone markers, version links, cancel (show.ex:104-225, :370-404)
  - shared-local-datetime
  - shared-hash-tabs
  - shared-log-viewer
  - shared-dataclip-body-viewer
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: project_id
    set_by: every project link
    effect: owned by shared-project-scope
  - name: id
    set_by: history-work-orders (workorder_component.ex:343-349), email:failure-alert (failure_alerter.ex:69-73, failure_alert.html.heex:7), workflow-editor (MiniHistory.tsx:629 via navigation.ts:73-78; run viewer RunTabPanel.tsx:78-80)
    effect: the run to show; another project's run or an unknown id redirects to History (S06)
  - name: step
    set_by: run-show (step list, show.ex:212), history-work-orders (step name link, components.ex:436-439), workflow-editor-run-viewer (RunTabPanel.tsx:79)
    effect: selects that step, enabling the Input and Output tabs and highlighting its log lines (streaming.ex:235-246; show.ex:363-367)
  - name: "#log, #input, #output (URL fragment)"
    set_by: run-show tab links (tabbed.ex:125-136)
    effect: client-side only; the TabbedContainer hook shows that panel, "log" when there is no fragment (show.ex:231; TabbedContainer.ts:13-14, :27)

config_variants:
  default: {}                                                                  # read under this one
  experimental-features: { user.preferences.experimental_features: true }      # link shape only (show.ex:113, :216, :327-328); owned by shared-run-components S08
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter whose check_limits returns {:error, _, %{position: :banner}}> }   # owned by shared-usage-limits-banner

inventory:
  routes:
    - live /projects/:project_id/runs/:id  RunLive.Show :show          # router.ex:297
  events:
    - RunLive.Show#cancel-run                                          # show.ex:370-404 (behaviour owned by shared-run-components)
    - RunLive.Show#save-log-filter                                     # injected by RunLive.Streaming, streaming.ex:214-227
    - RunLive.Show handle_params step                                  # show.ex:363-367
    - RunLive.Show handle_async :run                                   # streaming.ex:156-208
    - RunLive.Show handle_info {:log_line_chunk, _}                    # streaming.ex:113-118
    - RunLive.Show handle_info Runs.Events.RunUpdated                  # streaming.ex:120-127
    - RunLive.Show handle_info Runs.Events.StepStarted, StepCompleted  # streaming.ex:129-138
    - RunLive.Show handle_info Runs.Events.LogAppended                 # streaming.ex:140-150
    - RunLive.Show handle_info Runs.Events.DataclipUpdated             # show.ex:406-409, a no-op (flow-zero-persistence-runs 6.1)
  js_hooks:
    - TabbedContainer                    # assets/js/hooks/TabbedContainer.ts; tabbed.ex:37
    - LogViewer                          # assets/js/log-viewer/index.ts, component.tsx, store.ts; viewers.ex:95
    - ReactComponent DataclipViewer      # assets/js/react/components/DataclipViewer.tsx; viewers.ex:203-210
    - Tooltip                            # disabled tabs (tabbed.ex:117), version chip (common.ex:298); also listed by shared-run-components
    - ElapsedIndicator                   # owned by shared-run-components
    - LocalTimeConverter                 # Common.datetime for Started and Finished (common.ex:455, :478)
    - Copy                               # Common.datetime click-to-copy (common.ex:466, :489)
  policies:
    - Lightning.Policies.ProjectUsers :run_workflow          # show.ex:311-317
    - Lightning.Policies.ProjectUsers :edit_data_retention   # show.ex:335-343
    - Lightning.Policies.Dataclips :view_dataclip            # body fetch by the DataclipViewer (dataclip_controller.ex:16-30)
  workers: []
  api_endpoints:
    - get /dataclip/body/:id  DataclipController :show       # router.ex:201; fetched by DataclipViewer.tsx:10-30
  emails: []                                                 # inbound only: email:failure-alert links here (flow-failure-alert-email)
  config:
    - user.preferences.experimental_features
    - user.preferences.desired_log_level                     # viewers.ex:53-59; streaming.ex:219-224
    - :lightning, Lightning.Extensions, :usage_limiter (check_limits banner)
  not_reachable_here:
    - TabbedContainer `push-hash` handler (TabbedContainer.ts:16-19); nothing on this page pushes it
    - Viewers.wiped_data_viewer :request_response branch (viewers.ex:333-339), channel requests only
    - RunLive.Components.step_list_item/1, step_rerun_tag, bulk modals, async_filler (components.ex:347-640), rendered by history-work-orders
    - RunLive.Components.step_item `job_id` attr (components.ex:199, :256); this page never passes it (shared-run-components 6.3)

related:
  - history-work-orders
  - dataclip-show
  - workflow-editor-run-viewer
  - project-settings-data-storage
  - lib/lightning_web/components/viewers.ex
  - lib/lightning_web/live/components/tabbed.ex
flows:
  - flow-failure-alert-email
  - flow-zero-persistence-runs
  - flow-run-show-live-updates
  - flow-open-run-in-editor
  - flow-login-return-to
---

## 1. Purpose

Anyone on a project opens a run to find out exactly what happened to one execution of a
workflow: which steps ran, what each received and produced, what the job logged, and how it ended.
It is where a failure alert, a History row or the workflow editor sends people to diagnose a
broken integration. Without it, people would have to guess from a status pill why health data
failed to arrive, or ask someone with database access.

## 2. What it does

- **Run summary**
  - Anyone on the project sees a run's workflow, work order, who or what started it, when it started and finished, its duration, its status, and whether it used the latest workflow version or an older snapshot
  - Anyone opens the run's final output when one was stored, and goes from the run to its work order in History
  - Anyone follows the workflow or a step's inspect link to the version that ran (shared-run-components, flow-open-run-in-editor)
- **Steps and their data**
  - Anyone selects a step to see its input and output, or lands with it selected when arriving from a step link
  - Anyone is told when a step's output is not there yet
  - Anyone opening a run on a zero-persistence project is told its data was not retained (flow-zero-persistence-runs)
- **Logs**
  - Anyone reads the run's logs, with the selected step's lines highlighted
  - Anyone filters logs by level, and the choice is remembered for their next run
  - Anyone is told when a finished run has no logs, and what an unfinished run is waiting for
- **Follow and act on a run**
  - Anyone watching an unfinished run sees it progress without reloading (flow-run-show-live-updates)
  - Editors cancel a run no worker has claimed yet (shared-run-components)
  - Failure alert recipients land here from the email (flow-failure-alert-email)
- Nobody can open another project's run through this page

**Straightforwardness: 3 of 5.** The page itself is easy to read, but the way steps, tabs and logs tie together has gaps where it can show the wrong lines or an out-of-date message.

### Most surprising behaviours

- **(2)** Selecting a step seems to highlight one line too early, and can also highlight other steps' lines logged in between, which points people at the wrong output when diagnosing a failure. (6.1)
- **(3)** A run that gets picked up while you're watching may keep saying "Waiting for worker" until its first log line arrives, so it looks stuck when it isn't. (6.1)
- **(3)** A step link that doesn't match this run, or a link straight to the input or output tab, may show "No input state could be saved for this run", which reads like lost data. (6.1)
- **(3)** Very long logs have no limit and may stop loading part way with no message, so the end of the log, often where the error is, can be missing. (6.4)
- **(4)** Lines logged as "success" or "always" show whatever level you filter to, so a filtered log is never fully quiet. (6.2)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-50` (`:edit_data_retention` admin action,
`:run_workflow` editor action), `:134` (MFA unsatisfied denies everything), `:160-169` (support
access fills in editor actions only when there is no membership row). The page evaluates
`:run_workflow` against the project at mount (`show.ex:311-317`) and `:edit_data_retention`
against the membership row (`show.ex:335-343`; a nil row resolves to no project and is refused,
`scope.ex:112-116`, `:166-169`). Mount-time answers are refreshed by the membership remount in
shared-project-scope S08.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Open the run page (visibility) | yes | yes | yes | yes | no | yes, when support access is on |
| See run details, steps, input, output and logs | yes | yes | yes | yes | no | yes, when support access is on |
| Change the log level filter (own preference) | yes | yes | yes | yes | no | yes, when support access is on |
| Cancel an available run | no | yes | yes | yes | no | yes, when support access is on |
| Follow "this policy" from a not-retained panel | no | no | yes | yes | no | no |
| See admin contacts on a not-retained panel instead | yes | yes | no | no | no | yes |

**Preconditions beyond role**
- The run must belong to a workflow in this project (`hooks.ex:169-183`; `runs.ex:74-84`).
- Input and output bodies are fetched from `/dataclip/body/:id`, which re-checks project access on the dataclip itself (`dataclip_controller.ex:16-30`; `policies/dataclips.ex:20-22`).
- Cancel needs the run to be `available` at the moment of the update (shared-run-components section 3).
- The Input and Output tabs are only enabled once a step is selected (`show.ex:53`, `:240-261`).

## 4. What it touches

**Reads**
- `runs` joined through `work_orders` and `workflows` to scope by project, once in the mount hook and again in the async load (`hooks.ex:175`; `streaming.ex:15-27`; `runs.ex:74-84`)
- With the run: `users` (created by), `triggers` (starting trigger), `steps` with `jobs` and `workflow_snapshots`, `workflows`, `projects`, the run's own snapshot (`streaming.ex:18-25`)
- `dataclips` metadata for the selected step's input and output (`streaming.ex:48-77`); bodies through `get /dataclip/body/:id`, credential-scrubbed for `step_result` and `http_request` types (`dataclip_controller.ex:58-80`)
- `log_lines` for the run, streamed in timestamp order (`runs.ex:569-573`; `streaming.ex:181-195`)
- `project_users` joined to `users` for admin and owner emails (`show.ex:345`; `projects.ex:541-548`)
- `users.preferences` for `experimental_features` and `desired_log_level` (`show.ex:327-328`; `viewers.ex:53-59`)

**Writes**
- `users.preferences.desired_log_level` on `save-log-filter` (`streaming.ex:214-227`; `accounts.ex:1417-1424`)
- `runs.state` and `work_orders.state` on cancel (owned by shared-run-components)

**Immediate side effects**
- Subscribes to `run_events:<run_id>` once the run loads (`streaming.ex:168`; `events.ex:64-68`), which starts flow-run-show-live-updates
- Subscribes to the project's events for membership changes (owned by shared-project-scope)
- Cancel broadcasts (owned by shared-run-components)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `user.preferences.experimental_features` (variant `experimental-features`; link shape only)
- usage limiter banner (variant `usage-limited`; owned by shared-usage-limits-banner)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Run page
  In order to diagnose what happened to one execution of a workflow
  As anyone on the project
  I want to see the run's details, steps, data and logs

  @S01 @pending
  Scenario: The run's summary shows what ran, when and how it ended
    # Value: someone investigating a failure sees at a glance which workflow ran, when, for how long and with what result.
    Given workflow "Intake" in project "Malawi HIV" has a run that a webhook request started
    When I open the run page
    Then the breadcrumb reads "Run" followed by the run's short id
    And I see "Workflow" linking to "Intake"
    And I see "Work Order" with the work order's short id
    And I see "Started by" reading "Webhook trigger"
    And I see "Started", "Finished", "Duration" and "Status"
    # show.ex:75-80, :104-190
    # test/lightning_web/live/run_live/show_test.exs:67-93 asserts "Enqueued" and "Webhook trigger"

  @S02 @pending
  Scenario Outline: "Started by" names the person or the trigger
    # Value: people can tell whether a person or an integration started the run, and whom to ask about it.
    Given a run of workflow "Intake" <started>
    When I open the run page
    Then "Started by" reads <label>
    # show.ex:134-149
    # show_test.exs:89-93 asserts the webhook case only

    Examples:
      | started                                   | label                 |
      | started by a webhook request              | "Webhook trigger"     |
      | started by its cron trigger               | "Cron trigger"        |
      | retried by "amara@example.org" from History | "amara@example.org" |

  @S03 @pending
  Scenario: The version chip says whether the run used the latest workflow
    # Value: people know before opening the editor whether the workflow has changed since this run.
    Given a run executed on workflow "Intake" at its current version
    And another run executed on an older snapshot of "Intake"
    When I open the first run
    Then the breadcrumb shows a "latest" chip with tooltip "This run is based on the latest version of this workflow."
    When I open the second run
    Then the chip shows the first seven characters of the snapshot id
    And its tooltip says the run is based on a snapshot taken on that snapshot's date and time
    # show.ex:23-47, :82-86; common.ex:284-305

  @S04 @pending
  Scenario: The final output links to the stored result
    # Value: people can open the data the run produced without hunting for it.
    Given a run of "Intake" finished with a final output
    When I open the run page
    Then "Final Output" shows the output's short id linking to "/projects/<project_id>/dataclips/<dataclip_id>/show"
    And when a run finished without a final output, "Final Output" is empty
    # show.ex:166-180
    # show_test.exs:233-246 (failed run, refute "dataclips/"), :248-327 (short id shown)

  @S05 @pending
  Scenario: The work order link opens that work order in History
    # Value: people go from one run to the work order's full retry history in one click.
    Given a run of work order "W"
    When I click the work order's short id
    Then I am on History with "filters[workorder_id]" set to "W"
    And history-work-orders S10 holds
    # show.ex:121-133

  @S06 @pending
  Scenario: A run from another project cannot be opened
    # Value: a member of one project cannot read another project's runs, data or logs by guessing a run id.
    Given I am an editor on project "Malawi HIV"
    And run "R" belongs to project "Kenya TB"
    When I visit "/projects/<Malawi HIV id>/runs/<R id>"
    Then I am on the "Malawi HIV" history page
    And I see "Run not found"
    And the same happens for a run id that does not exist
    # hooks.ex:169-183; runs.ex:74-84
    # show_test.exs:19-42

  @S07 @pending
  Scenario: Selecting a step shows its input and output
    # Value: people see exactly what data went into and came out of the step that failed.
    Given a run whose steps "Fetch" and "Transform" have finished with stored input and output
    When I select "Fetch" in the step list
    Then the URL carries "step=<Fetch step id>"
    And "Fetch" is marked as selected
    And the "Input" tab shows "Fetch"'s input
    And the "Output" tab shows "Fetch"'s output
    When I select "Transform" and then "Fetch" again
    Then the "Output" tab shows "Fetch"'s output again
    # show.ex:206-225, :262-296, :363-367; streaming.ex:55-77, :235-246; viewers.ex:243-290; DataclipViewer.tsx:32-58
    # show_test.exs:136-147, :167-176, :212-222 assert the dataclip id handed to the viewer

  @S08 @pending
  Scenario: A step link opens the run with that step selected
    # Value: links from History and the workflow editor land on the step in question, not the top of the run.
    Given run "R" has a finished step "Fetch"
    When I open "/projects/<project_id>/runs/<R id>?step=<Fetch step id>"
    Then "Fetch" is marked as selected
    And the "Input" and "Output" tabs are enabled
    # streaming.ex:165-196, :235-246; show.ex:363-367
    # inbound links: components.ex:436-439 (History), RunTabPanel.tsx:79 (editor)

  @S09 @pending
  Scenario: Input and output need a step to be selected
    # Value: people are told why the data tabs are empty instead of reading an empty panel as missing data.
    Given I open a run without selecting a step
    Then the "Log" tab is shown
    And the "Input" tab is disabled with the tooltip "A valid step must be selected to view its input"
    And the "Output" tab is disabled with the tooltip "A valid step (with a readable output) must be selected to view its output"
    # show.ex:53, :228-261; tabbed.ex:106-123; TabbedContainer.ts:13-14, :27

  @S10 @pending
  Scenario: The log tab shows everything the run logged
    # Value: people read what the job printed, which is usually where the cause of a failure is.
    Given a finished run of "Intake" that logged "Fetched 12 patients" and "Posted batch 1"
    When I open the run page
    Then the "Log" tab shows both lines in time order, each prefixed with its source
    # streaming.ex:181-195 (streamed in chunks of 100, show.ex:3), :113-118; viewers.ex:92-113; log-viewer/index.ts:35-44; store.ts:130-144, :158-173
    # store.test.ts:22-38, :72-106, :126-144

  @S11 @pending
  Scenario: Selecting a step highlights its log lines
    # Value: in a long log, people find the failing step's output without scrolling through every step.
    Given a finished run whose steps "Fetch" and "Transform" both logged
    When I select "Transform"
    Then the log scrolls to "Transform"'s first line
    And "Transform"'s lines are marked in the gutter
    And "Fetch"'s lines are not marked
    # viewers.ex:99; log-viewer/index.ts:47-50; store.ts:46-95, :185-197; component.tsx:51-78
    # store.test.ts:215-266 asserts only that ranges exist and clear

  @S12 @pending
  Scenario: The log level filter is remembered
    # Value: people who only care about warnings and errors don't have to re-filter every run they open.
    Given I have never set a log level
    And a finished run logged a "debug" line and an "info" line
    When I open the run page
    Then the filter reads "info" and the "debug" line is hidden
    When I choose "debug"
    Then both lines are shown
    And when I open another run, the filter reads "debug"
    # viewers.ex:52-60, :79-86, :121-197; streaming.ex:214-227; store.ts:26-44, :135-144, :151-153, :199-201
    # store.test.ts:160-207

  @S13 @pending
  Scenario: A finished run with no logs says so
    # Value: people can tell a run that logged nothing from a log that is still loading.
    Given a run that was lost before it logged anything
    When I open the run page
    Then the "Log" tab says "No logs were received for this run."
    # viewers.ex:68-76; Run.final_states (run.ex:46-55)
    # test/lightning_web/live/components/viewer_test.exs:15-38

  @S14 @pending
  Scenario Outline: An unfinished run's log says what it is waiting for
    # Value: people can tell work stuck in the queue from a worker that is still setting up.
    Given a run in state <state> that has not logged anything
    When I open the run page
    Then the "Log" tab shows <message>
    # viewers.ex:61-66, :105-110
    # viewer_test.exs:40-68

    Examples:
      | state     | message                                   |
      | available | "Waiting for worker"                      |
      | claimed   | "Creating runtime & installing adaptors"  |
      | started   | "Nothing yet"                             |

  @S15 @pending
  Scenario: A running step's output says it is not there yet
    # Value: people don't mistake a step that is still running for one that produced nothing.
    Given a started run whose step "Fetch" has not finished
    When I select "Fetch"
    Then the "Output" tab shows "Nothing yet"
    # viewers.ex:277-286; dataclip_wiped? is false for an unfinished step (viewers.ex:372-380)
    # show_test.exs:148, :193 (output_is_empty? looks for "#step-output-<id>-nothing-yet"); viewer_test.exs:169-187

  @S16 @pending
  Scenario: Editors can cancel a queued run from this page
    # Value: people who spot a run queued by mistake can stop it where they found it.
    Given I am an editor and run "R" is "available"
    When I open the run page for "R"
    Then I see a "Cancel" action
    And shared-run-components S09, S10, S11 and S12 hold on this page
    # show.ex:191-203, :311-317, :370-404
    # show_test.exs:435-626

  @S17 @pending
  Scenario: The workflow and step inspect links open the version that ran
    # Value: people inspect the code that actually ran, not code changed since.
    Given a run executed on an older version of "Intake"
    When I look at the "Workflow" link or a step's inspect link
    Then shared-run-components S07 holds, and S08 under experimental features
    And the flow "flow-open-run-in-editor" starts when I follow either
    # show.ex:111-118, :213-223
    # show_test.exs:329-428

  @S18 @pending
  Scenario: An open run page follows the run as it executes
    # Value: someone watching a run sees its state, steps, output and logs arrive without reloading.
    Given I have run "R" open while it is "available"
    When the worker claims, starts and completes steps of "R"
    Then the flow "flow-run-show-live-updates" ends on this page
    # streaming.ex:120-150, :168
    # show_test.exs:67-246 drives the whole lifecycle through the run topic

  @S19 @pending
  Scenario: A failure alert's run link lands on this page
    # Value: the person alerted goes straight to the failing run's logs.
    Given I received a failure alert for run "R" of workflow "Intake"
    When I follow the link to "inspect the run and its logs"
    Then I am on "/projects/<project_id>/runs/<R id>"
    And the flow "flow-failure-alert-email" ends on this page
    And if I was signed out, the flow "flow-login-return-to" starts for that URL
    # failure_alerter.ex:69-73; failure_alert.html.heex:7-8; router.ex:189-190, :297

  @S20 @pending
  Scenario: A run on a zero-persistence project shows its data as not retained
    # Value: investigators read an empty step as policy, not failure, and know who can change it.
    Given project "Malawi HIV" never retains I/O data and run "R" was created after the switch
    When I open "R" and select its step
    Then the flow "flow-zero-persistence-runs" ends on this page (its S01 and S04)
    # show.ex:262-296, :335-345; viewers.ex:243-252, :309-361
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The log viewer container is `phx-update="ignore"`, so its waiting message is never re-rendered after the first paint | `viewers.ex:61-66`, `:92-113` | a run claimed while the page is open keeps saying "Waiting for worker" until its first log line arrives. Inferred from code | fix |
| A `step` param that names no step of this run still enables the Input and Output tabs; the viewer gets a nil step and dataclip | `streaming.ex:235-246`; `show.ex:53`; `viewers.ex:256-286` | on a finished run, "No input state could be saved for this run." for a step that isn't part of it; on an unfinished run, "Nothing yet" forever | fix |
| `#input` or `#output` in the URL with no step selected opens the panel anyway: the hook selects the tab by `aria-controls`, which the disabled `<span>` also carries | `TabbedContainer.ts:37-63`; `tabbed.ex:108-123` | the disabled tab's panel is shown, reading "No input state could be saved for this run." on a finished run. Inferred from code | fix |
| Highlight ranges start one line early (a 0-based marker is passed to Monaco's 1-based lines) and always extend the previous range (`last.end <= nextMarker` is always true), so a step's range swallows other steps' lines logged in between | `store.ts:67-89`; `component.tsx:61-66` | the line before the step's first log is highlighted, and with interleaved run-level or parallel-branch logs, unrelated lines are highlighted too. Inferred from code | decide |
| A non-UUID run id raises `Ecto.Query.CastError` in the mount hook rather than reaching the "Run not found" redirect | `hooks.ex:175`; `runs.ex:74-84` | an error page instead of being sent back to History | fix |
| `save-log-filter` stores any client-sent string as the preference, and pattern-matches `{:ok, _}` on the update | `streaming.ex:214-227`; `viewers.ex:168-171` | a forged level (for example "verbose") scores as unknown, so only "success" and "always" lines are shown on every run until changed; a failed update crashes the page | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `RunUpdated` replaces the run but not `@workflow`, so the "latest" chip and the version link are computed against the workflow version loaded at mount | `streaming.ex:120-127`; `show.ex:23-31`, `:113` | decide |
| The run page ignores `DataclipUpdated` (recorded as a bug in flow-zero-persistence-runs 6.1) | `show.ex:406-409` | preserve |
| The version chip tooltip formats the snapshot time as `%F at %T` with no timezone (it is UTC) | `show.ex:44` | decide |
| "Started by" is hidden when the run has neither a creator nor a starting trigger | `show.ex:134-149` | preserve |
| "Started" and "Finished" are empty, not "--", when unset, because the page skips `Common.datetime` rather than passing nil | `show.ex:153-155`, `:161-163`; `common.ex:444-445` | decide |
| Labels are title case: "Work Order", "Final Output" | `show.ex:122`, `:167` | decide |
| The async load replaces the `project` assign set by the scope hook with `run.workflow.project` | `streaming.ex:178` | preserve |
| The side menu marks History (`active_menu_item: :runs`) | `show.ex:322` | preserve |
| Log lines whose level is `success` or `always` (or anything unrecognised) score above "error" and are shown whatever the filter | `store.ts:26-44`; `log_line.ex:38-40` | decide |
| JSON-looking log messages are pretty-printed across several lines | `store.ts:106-133`; `store.test.ts:270-305` | preserve |
| A fragment that names no tab (`#foo`) hides every panel and highlights no tab (same as shared-project-settings-tab-chrome 6.2) | `TabbedContainer.ts:32-43`; `tabbed.ex:145-159` | decide |
| "No input state could be saved for this run." appears only for a finished step whose dataclip id is set but whose row isn't loaded, or for no step at all; a missing id reads as "not retained" instead (flow-zero-persistence-runs 6.1) | `viewers.ex:256-275`, `:372-380` | decide |
| A failed async load shows the raw text "there was an error loading the run" | `show.ex:99-101` | decide |
| Started and Finished use `Common.datetime` (relative time, UTC tooltip, click to copy) | `show.ex:154`, `:162`; `common.ex:422-497` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_async(:run, {:ok, nil})` marking the run not found | `streaming.ex:156-163` | the mount hook already redirected unless the run existed; only a delete between the two queries reaches it |
| The `log_lines` async result | `show.ex:333`; `streaming.ex:181-195` | assigned but never read; logs arrive through `push_event` |
| The highlight event dispatch in `LogViewer.updated` | `log-viewer/index.ts:50-54` | commented out |
| `cond` fallthrough `true ->` in "Started by" | `show.ex:145` | the enclosing `if` already requires a creator or a trigger |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The run is fetched by the mount hook and again by the async load, on both the dead and the connected mount | `hooks.ex:175`; `streaming.ex:15-27` | no | decide |
| Logs are pushed to the browser in chunks of 100 with no overall cap; the browser keeps and re-sorts every line on each push | `show.ex:3`; `streaming.ex:184-191`; `store.ts:158-173` | yes, on very long logs | decide |
| Log streaming runs inside `Repo.transaction` with the default timeout; a stream that outlasts it fails the async silently | `streaming.ex:184-191` | yes, logs stop part way. Inferred, not run | decide |
| Admin and owner emails are loaded on every mount, though only the not-retained panel uses them | `show.ex:345` | no | preserve |

### 6.5 Things seen but not understood

- Patching to `?step=<id>` (`show.ex:212`) replaces the URL, and the fragment may be dropped; whether a reload after selecting a step keeps the Input or Output tab was not checked in a browser.
- On a finished run the first render shows "No logs were received for this run." until the first log chunk flips `log_lines_empty?` (`streaming.ex:113-118`; `viewers.ex:68`); the `LogViewer` hook is created in the same patch that carries the first `push_event`. Whether the hook always mounts before the event is dispatched was not verified; the lifecycle test only covers an enqueued run (`show_test.exs:95-98`).
- `flow-failure-alert-email` lists the run link as an exit it does not cover (its section 6.5 and `inventory.not_reachable_here`); S19 assumes the flow will be extended to own it.
- `starting_trigger` is a live `triggers` row, not the snapshot's; what "Started by" shows after the trigger is deleted depends on the foreign key's `on_delete`, which was not checked.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should flow-failure-alert-email own the run link exit, or should a separate flow cover it (6.5)?
- Should an unknown `step` param, or `#input` without a step, fall back to the log with tabs disabled (6.1)?
- Should log level be validated against the four offered levels (6.1)?
- Should step log highlighting be exact, and should run-level lines between a step's lines be highlighted (6.1)?
- Should very long logs be capped or paged (6.4)?

## Proposed flows

- **flow-run-show-live-updates** (referenced; proposed by shared-run-components): an open run page subscribes to `run_events:<run_id>` (`streaming.ex:168`); `RunUpdated` updates the summary, state pill and cancel button (`streaming.ex:120-127`; `runs.ex:269-287`), `StepStarted` and `StepCompleted` add or update steps and load the selected step's output (`streaming.ex:129-138`; `handlers.ex:242`, `:469`), and `LogAppended` streams new log lines (`streaming.ex:140-150`; `runs.ex:310`, `:337`). Test: `show_test.exs:67-246`. Surfaces: controller:run-channel (worker joins and events), pubsub:run_events:<run_id>, run-show.
- **flow-open-run-in-editor** (referenced; proposed by shared-run-components): the "Workflow" link and each step's inspect link open the collaborative editor on the run's snapshot (`v=`) or the run itself (`as_run=`), with the run panel and job selected (`show.ex:111-118`; `components.ex:256-270`). Surfaces: run-show, history-work-orders, workflow-editor.
- **flow-login-return-to** (referenced; proposed by shared-authenticated-session): a signed-out visitor following a failure alert's run link is sent to log in and returned to the run afterwards (`router.ex:189-190`). Surfaces: email:failure-alert, controller:user-session, run-show.
- Referenced, existing: flow-failure-alert-email (S19), flow-zero-persistence-runs (S20).

## Proposed shared

- **shared-local-datetime** (referenced; proposed by project-settings-history-exports): `Common.datetime` with the LocalTimeConverter and Copy hooks (`common.ex:402-497`), used here for "Started" and "Finished". Surfaces: run-show, project-settings-history-exports and other views rendering timestamps.
- **shared-hash-tabs**: the generic `Tabbed.container` component and `TabbedContainer` hook (fragment-driven tabs, default hash, disabled tabs with tooltips; `tabbed.ex:1-162`; `TabbedContainer.ts:1-75`), used by the run page and the project settings page. shared-project-settings-tab-chrome covers only the settings use. Surfaces: run-show, project settings tabs.
- **shared-log-viewer**: `Viewers.log_viewer` with the `LogViewer` hook and its store (level filter saved to the user's preferences, step highlighting, JSON prettifying, waiting messages; `viewers.ex:38-197`; `assets/js/log-viewer/`). Only run-show renders it in LiveView today; the collaborative editor's run viewer has its own LogTabPanel, so promote this only if the rebuild shares one. Surfaces: run-show, workflow-editor-run-viewer.

## Lead resolution (batch 3)

- `flow-run-show-live-updates` and `flow-open-run-in-editor` created. `shared-local-datetime`, `shared-hash-tabs` and `shared-log-viewer` created.
- flow-failure-alert-email now lists run-show as an alternate exit, so S19 has a flow to hand off to.
- `flow-login-return-to` is still proposed; it is created with the auth batch.
