---
id: flow-zero-persistence-runs
type: flow
title: Runs on a project that keeps no input or output
status: not-started
owner:

trigger:
  entry: project-settings-data-storage
  exit: run-show                                  # also history-work-orders and workflow-editor-run-viewer
  surfaces:
    - project-settings-data-storage               # admin saves "Never retain" (project-settings-data-storage S06)
    - capability:run-dataclip-persistence         # run options fixed at run creation (work_orders.ex:228-245, :261-273, :284-288, :879-891; runs.ex:111-125; usage_limiter.ex:17-21; projects.ex:425-435)
    - controller:webhook                          # stores the request body in full (webhooks_controller.ex:51-60)
    - controller:run-channel                      # fetch:dataclip wipes the input; step:complete and run:complete write wiped rows (run_channel.ex:122, :184-191, :218-224; handlers.ex:103, :192-204, :513-532)
    - pubsub:run_events:<run_id>                  # Runs.Events.DataclipUpdated after the wipe (runs.ex:182-196; events.ex:57-62)
    - run-show                                    # wiped data viewer on the Input and Output tabs (show.ex:263-295; viewers.ex:241-250, :309-361)
    - history-work-orders                         # wiped work order input: retry and select disabled (history-work-orders S21, S22)
    - workflow-editor-run-viewer                  # Input and Output tabs (InputTabPanel.tsx, OutputTabPanel.tsx)
    - project-settings-data-storage               # admins follow "this policy" back to the tab (viewers.ex:333-347)
    - dataclip-show   # added by lead
  reachable_when:
    - the actor passes `:edit_data_retention` on the entry view (project_users.ex:29-37; settings.ex:366-378)
    - project.retention_policy is `:erase_all` when the run is created, not when it executes (run.ex:169, :185; work_orders.ex:228-245)
    - the viewer of run-show, history-work-orders or the editor passed shared-project-scope

inherits:
  - shared-project-scope            # who can open run-show, history and the editor; not repeated here
  - shared-run-components           # S13: retention tooltip on the step rerun icon; not repeated here

url_params:
  - name: "#data-storage (URL fragment)"
    set_by: run-show wiped data viewer "this policy" link (viewers.ex:333-347)
    effect: opens the data storage tab client-side (owned by project-settings-data-storage)

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # save_dataclips comes from retention_policy (usage_limiter.ex:17-21); read under this one
  limiter-run-options: { Lightning.Extensions.usage_limiter: <adapter whose get_run_options sets save_dataclips itself> }   # usage_limiting.ex:88-92; run_channel_test.exs:409-443. Not read in depth; an adapter could ignore retention_policy

inventory:
  routes:
    - live /projects/:project_id/runs/:id  RunLive.Show :show       # router.ex:297; no run-show view annotation yet
    - get /dataclip/body/:id  DataclipController :show               # router.ex:201; editor run viewer reads bodies here
    - post /projects/:project_id/runs/:run_id/retry  WorkflowController :retry_run   # router.ex:223-225; editor header Retry (6.1)
  events:
    - ProjectLive.Settings#save_retention_settings                   # entry, owned by project-settings-data-storage
    - RunLive.Show handle_info Runs.Events.DataclipUpdated           # show.ex:407-409, a no-op (6.1)
    - RunChannel#fetch:dataclip                                      # run_channel.ex:184-191
    - RunChannel#step:complete                                       # run_channel.ex:218-224
    - RunChannel#run:complete                                        # run_channel.ex:122
    - RunChannel handle_info Runs.Events.DataclipUpdated             # run_channel.ex:320-323, pushes "dataclip:updated" (6.3)
  js_hooks:
    - Tooltip                                                        # admin contacts on the wiped data viewer (viewers.ex:351-357); listed by shared-run-components
  policies:
    - Lightning.Policies.ProjectUsers :edit_data_retention            # entry and the run page's policy link (show.ex:335-343)
    - Lightning.Policies.Dataclips :view_dataclip                     # editor body fetch (dataclip_controller.ex:16-30)
  workers: []                                                        # nothing deferred; the retention cleanup job does not wipe under never retain (section 4)
  api_endpoints: []
  emails: []                                                         # a policy-only change sends none (flow-data-retention-change-email 6.1)
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (get_run_options; usage_limiter.ex:17-21)
  not_reachable_here:
    - channel request wiping (persistence_policy.ex:20-37; channels.ex:605-621; handler.ex:75, :146), see Proposed flows
    - Viewers.wiped_data_viewer :request_response branch (viewers.ex:333-339), channel requests only

related:
  - project-settings-data-storage
  - history-work-orders
  - shared-run-components
  - flow-data-retention-change-email
  - lib/lightning/runs/handlers.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning_web/components/viewers.ex
flows: []
---

## 1. Purpose

Projects bound by a data protection agreement switch to "Never retain" so that the health records
passing through their workflows are not kept at rest. This flow is the promise behind that radio
button: runs created afterwards store no input or output, and anyone who later opens those runs
sees that the data was withheld on purpose rather than lost, and knows who can change it. Without
it, an admin would have no way to confirm the setting took effect, and an investigator would read
an empty step as a platform fault.

## 2. What it does

1. A project admin chooses "Never retain" on the data storage tab of project settings.
2. Every run created after that, by webhook, schedule, manual run or retry, keeps no input or output.
   - The worker still gets the input, and then the stored copy is erased.
   - Step outputs and the run's final output are stored empty.
   - Saved inputs someone deliberately named are never erased, and webhook callers waiting for a reply still get it.
3. Anyone who opens one of those runs is told the data wasn't kept because of the project's policy, not lost.
   - Admins and owners get a link back to the data storage tab to change it for future runs.
   - Everyone else is told to contact an admin, with the admins' and owners' emails in a tooltip.
4. The history page won't retry a work order whose input was erased, and the step rerun button is disabled.
5. Switching back to keeping data only affects runs created from then on; older runs stay empty.

**Straightforwardness: 2 of 5.** "Keep nothing" sounds absolute, but what gets kept depends on when each run was created and whether a worker ever picked it up, and several screens don't know the data is gone.

### Most surprising behaviours

- **(2)** A webhook's data is stored in full when it arrives and only erased when a worker picks the run up. If the run is never picked up (refused by the plan limit, cancelled, or lost), the data seems to stay, possibly forever, on a project that promised to keep nothing. (6.1)
- **(2)** The setting is fixed on each run when it's created, not when it runs. Runs already queued when you switch to "Never retain" still store their data, and retrying an older work order erases its input, so it can only be retried once more. (6.2)
- **(2)** Scheduled workflows that carry state from one run to the next may replay old state from before the switch, one older run at a time, and then start from empty. Read from the code, not run. (6.1)
- **(3)** In the workflow editor the run's Input and Output tabs just show "null" with no explanation, and "Retry" is offered, saves the workflow, then fails. (6.1)
- **(3)** Run logs are still kept, and they may contain whatever data a job printed. (6.5)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_data_retention` is admin), `:134`
(MFA unsatisfied denies everything), `:160-161` (admin actions need an owner or admin row). The
run page computes `can_edit_data_retention` against the membership row at mount
(`show.ex:335-343`) and lists admin and owner emails for everyone else (`show.ex:345`,
`projects.ex:540-548`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| Start the flow by saving "Never retain" | no | no | yes | yes | no | no |
| See that a run's input and output were not retained | yes | yes | yes | yes | no | yes |
| Follow "this policy" to the data storage tab | no | no | yes | yes | no | no |
| See the admin contacts tooltip instead | yes | yes | no | no | no | yes |

**Preconditions beyond role**
- Whether a run stores data is decided by the policy at the moment the run is created, including retries and cron runs (`run.ex:169`, `:185`; `work_orders.ex:228-245`, `:261-273`, `:879-891`). See 6.2.
- Named dataclips and `:global` dataclips are never erased (`query.ex:365-373`).

## 4. What it touches

**Reads**
- Hop 1 (save): owned by project-settings-data-storage.
- Hop 2 (run created by webhook, cron, manual run or retry): `projects.retention_policy` via `Projects.save_dataclips?/1` (`projects.ex:425-435`), `workflows.enable_job_logs` (`runs.ex:115-125`)
- Hop 3 (worker): `runs.options` stored on the run (`run_channel.ex:187`, `:224`; `handlers.ex:103`)
- Hop 4 (run page): run with steps (`streaming.ex:15-27`), step input and output dataclips (`streaming.ex:47-75`), admin and owner emails (`projects.ex:540-548`)
- Hop 5 (editor run viewer): `/dataclip/body/:id` (`dataclip_controller.ex:16-78`)

**Writes**
- Hop 1: `projects.retention_policy = erase_all` (owned by project-settings-data-storage S06)
- Hop 2: `runs.options.save_dataclips = false` (`run.ex:139`, `:169`, `:185`); the webhook body and request headers are still inserted in full as an `http_request` dataclip (`webhooks_controller.ex:51-60`)
- Hop 3a (`fetch:dataclip`): the run's input dataclip has `body` and `request` set to nil and `wiped_at` set, unless it is named or `:global` (`run_channel.ex:184-191`; `runs.ex:182-196`; `query.ex:365-373`)
- Hop 3b (`step:complete`): an output dataclip row with `body` nil and `wiped_at` set, under the id the worker sent; none when no id is sent (`handlers.ex:513-532`); `steps.output_dataclip_id`
- Hop 3c (`run:complete` with `final_state`): a new wiped `step_result` dataclip as the run's final dataclip (`handlers.ex:172-204`)
- Logs are written as usual; the policy does not touch them (`run_with_options.ex:116-123`)

**Immediate side effects**
- The worker is told `output_dataclips: false` in the plan (`run_with_options.ex:116-123`; `run_channel_test.exs:345-391`)
- `Runs.Events.DataclipUpdated` on `run_events:<run_id>` after the input wipe (`runs.ex:189-192`; `events.ex:57-62`); the run channel pushes `dataclip:updated` to browser joins (`run_channel.ex:320-323`); run-show ignores it (`show.ex:407-409`)

**Deferred side effects**
- none. The two-hourly cleanup does not wipe anything here: "Never retain" nulls the I/O period (`project.ex:244-247`) and `wipe_dataclips_for/1` then returns an error (`projects.ex:1787-1789`). History deletion still applies when a history period is set (`projects.ex:223-245`).

**External, non-transactional effects**
- The input body is sent to the worker in the same `fetch:dataclip` reply that wipes it (`run_channel.ex:185-190`). The worker holds it in memory; nothing here can recall it.

**Depends on config**
- `Lightning.Extensions.usage_limiter` `get_run_options` (variant `limiter-run-options`)

**Product limits**
- Stored webhook inputs are erased only when a worker fetches them, not on arrival (S02; 6.1)

## 5. Scenarios

```gherkin
Feature: Runs on a zero-persistence project
  In order to keep health records out of storage
  As a project admin
  I want runs created after I choose "Never retain" to store no input or output, and say so

  @S01 @pending
  Scenario: A run created after the switch shows its input and output as not retained
    # Value: the admin can confirm the policy took effect, and investigators read empty steps as policy, not failure.
    Given I am an admin on project "Malawi HIV"
    And I have saved "Never retain input/output data (zero-persistence)" on the "Data Storage" tab
    And a webhook request then starts workflow "Intake" and it succeeds
    When I open the run page for that run and select its step
    Then the "Input" tab shows "No Input Data here!"
    And it says "Input data for this step has not been retained in accordance with your project's data storage policy."
    And the "Output" tab shows "No Output Data here!"
    # settings.ex:366-378; work_orders.ex:228-245; usage_limiter.ex:17-21; projects.ex:425-435
    # run_channel.ex:184-191; handlers.ex:513-532; show.ex:263-295; viewers.ex:241-250, :309-330, :372-380
    # work_orders_test.exs:40-80 (run options save_dataclips false); run_channel_test.exs:1243-1272 (output stored wiped)
    # viewer_test.exs:118-150 (copy for a wiped dataclip); the end-to-end path is inferred from code

  @S02 @pending
  Scenario: The webhook body is erased once the worker has picked it up
    # Value: payloads that arrive under zero persistence are not kept at rest after the run has them.
    Given project "Malawi HIV" never retains I/O data
    When a webhook request starts a run
    And a worker fetches the run's input
    Then the worker receives the request body
    And the stored input has no body or request and is marked wiped
    # webhooks_controller.ex:51-60; run_channel.ex:184-191; runs.ex:182-196; query.ex:365-373
    # run_channel_test.exs:536-551

  @S03 @pending
  Scenario: Synchronous webhook callers still get their response
    # Value: integrations that wait for a reply keep working on a zero-persistence project.
    Given project "Malawi HIV" never retains I/O data
    And workflow "Intake" replies to its webhook after completion with "ack" true
    When a client posts '{"value": 42}' to the webhook
    Then the client receives status 200 with "ack" true and "received" 42
    And the step's output is stored wiped
    # run_channel.ex:122-138; handlers.ex:513-532
    # test/integration/web_and_worker_test.exs:964-1022

  @S04 @pending
  Scenario Outline: The not retained message tells each reader what they can do
    # Value: the person who can change the policy can get there, and everyone else knows whom to ask.
    Given project "Malawi HIV" never retains I/O data and has a finished run created after the switch
    And I am <role> on project "Malawi HIV"
    When I open the run's "Input" tab
    Then I see <guidance>
    # viewers.ex:331-361; show.ex:335-345
    # viewer_test.exs:118-150 (admin sees "for future runs" and no emails; non-admin sees the contact list)

    Examples:
      | role     | guidance |
      | an admin | "You can't rerun this work order, but you can change this policy for future runs." with "this policy" linking to "/projects/<project_id>/settings#data-storage" |
      | an owner | the same link |
      | an editor | "Contact one of your project admins for more information." with a tooltip listing the project's admins and owners |
      | a viewer | the same contact message |

  @S05 @pending
  Scenario: History won't retry a run whose input was erased
    # Value: nobody retries a work order whose input is gone and gets an empty or misleading run.
    Given project "Malawi HIV" never retains I/O data
    And a webhook run of workflow "Intake" has finished
    When I open the history page
    Then history-work-orders S21 and S22 hold for that work order
    And on the run page the step rerun icon is disabled as in shared-run-components S13
    # run_channel.ex:187-188 (input wiped); workorder_component.ex:120-176, :481-483; components.ex:503-514

  @S06 @pending
  Scenario: Turning storage back on applies to new runs only
    # Value: a project that needs to debug again gets stored data from then on, and nobody is misled about older runs.
    Given project "Malawi HIV" never retains I/O data and run "R1" was created and finished under that policy
    And I am an admin on project "Malawi HIV"
    When I save "Retain all input/output data" on the "Data Storage" tab
    And a webhook request then starts run "R2" and it succeeds
    Then the run page for "R2" shows its input and output
    And the run page for "R1" still shows "No Input Data here!"
    # project-settings-data-storage S07; usage_limiter.ex:17-21; run.ex:169; handlers.ex:541-556
    # run_channel_test.exs:569-581 (retain_all leaves the input unwiped); inferred end to end

  @S07 @pending
  Scenario: Named inputs survive zero persistence
    # Value: inputs people deliberately named and kept for testing are not destroyed by running them.
    Given project "Malawi HIV" never retains I/O data
    And the project has a saved input named "Sample patient"
    When an editor runs workflow "Intake" from "Sample patient"
    And a worker fetches the run's input
    Then "Sample patient" still has its body
    # query.ex:367-368 (named and :global excluded); run_channel_test.exs:553-566 covers :global only, named is inferred from code
```

The workflow editor's run viewer has no scenario here: what it shows for a zero-persistence run is
a raw `null` and a Retry that fails (6.1). Once fixed, it should carry S01 and S04's assertions.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The editor's run viewer has no wiped state: a wiped dataclip still has an id, so it fetches the body and gets `null` | `InputTabPanel.tsx:28-42`; `OutputTabPanel.tsx:28-42`; `DataclipViewer.tsx:10-58`; `dataclip_controller.ex:77` | the Input and Output tabs show `null`, with no word about the data storage policy | fix |
| The editor header offers "Retry" for any finished run without checking for a wiped input; the click saves the workflow, then the server refuses with "cannot retry run using a wiped dataclip" | `Header.tsx:293-297`, `:422-481`, `:878`; `workflow_controller.ex:251-257`; `work_orders.ex:327-352` | a "Retry failed" toast reading "Failed to retry run" after the workflow was saved. Inferred from code, not run | fix |
| A webhook body is stored in full and only erased when a worker fetches it, and "Never retain" disables the I/O cleanup, so a body whose run is never fetched (rejected by a usage limit, cancelled before claim, lost before fetch) is kept until history deletion, or indefinitely with no history period | `webhooks_controller.ex:42`, `:51-60`; `run_channel.ex:184-191`; `project.ex:244-247`; `projects.ex:1787-1789` | the input stays readable on history for those work orders on a project that promised to keep nothing | fix |
| A finished step with no output id is labelled "has not been retained in accordance with your project's data storage policy" even on a project that retains everything | `viewers.ex:376-380`; asserted in `viewer_test.exs:153-167` | a failed step that produced no output blames a policy the project doesn't have | fix |
| The run page ignores `DataclipUpdated` and only reloads a dataclip when the step's id changes, so an input wiped while the page is open still renders as data | `show.ex:407-409`; `streaming.ex:55-65` | the Input tab keeps the viewer instead of "No Input Data here!" until reload | fix |
| Under "Never retain" a cron trigger's next run picks the last unwiped final state from before the switch, and `fetch:dataclip` then wipes it, so each cron run consumes an older pre-switch state | `invocation.ex:296-313`, `:329`; `scheduler.ex:80-108`; `run_channel.ex:187-188`; `runs.ex:182-187` | cron workflows that carry state replay stale state from before the switch, one older run at a time, then start from `{}`. Inferred from code | decide |
| The step panel copy says "You can't rerun this work order" | `viewers.ex:341` | names the work order on a per-step panel (same wording issue as shared-run-components 6.1) | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The policy is captured on the run at creation: runs queued before the save still store data, and runs queued under "Never retain" stay that way if the policy is switched back before they execute | `run.ex:169`, `:185`; `work_orders.ex:228-245`, `:879-891`; `handlers.ex:103`, `:444`, `:518`; `run_channel.ex:187` | decide |
| Claim recomputes run options from the limiter, but only for the run token's expiry; storage follows the options saved on the run | `worker_channel.ex:54-55`, `:136-145`; `workers.ex:98-110` | preserve |
| Retrying a work order from before the switch runs under the new policy and wipes its stored input on fetch, so it can be retried once more at most | `work_orders.ex:879-891`; `run_channel.ex:187-188` | decide |
| The server still inserts an empty, wiped dataclip row for each step output and the run's final state, so steps point at empty rows rather than at nothing | `handlers.ex:192-204`, `:513-532` | preserve |
| Non-admins see admin and owner email addresses in a tooltip | `viewers.ex:349-357`; `projects.ex:540-548` | decide |
| Title case "No Input Data here!" and "No Output Data here!" | `viewers.ex:321-323` | decide |
| The policy link is a `navigate` to the settings hash; the settings page is a different LiveView, so it is a full mount | `viewers.ex:342-347` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `dataclip:updated` push to browser run channel joins | `run_channel.ex:320-323` | no client registers a handler for it (`createHistoryStore.ts:944` listens for `step:completed` but not this) |
| `{0, []}` branch of `Runs.wipe_dataclips/1` reached for named or `:global` inputs, emits nothing | `runs.ex:194-195` | reachable, but no surface depends on it; listed so the lint doesn't nag |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| none | | | |

### 6.5 Things seen but not understood

- Whether the worker still sends `output_dataclip_id` when told `output_dataclips: false` is decided in the worker repo. The server handles both: with an id it inserts a wiped row, without one the step has no output (`handlers.ex:513-532`). The run page shows "not retained" either way; the editor shows `null` or "No output state could be saved for this run".
- Job logs are kept under "Never retain" (`run_with_options.ex:116-123`) and can contain payload data that a job logs. Unclear whether admins expect that from "zero-persistence".
- Dataclip bodies are served with `cache-control: private, max-age=86400` (`dataclip_controller.ex:73-76`); a browser that loaded an input before the worker wiped it may keep showing it from cache.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a webhook body be erased on arrival or at least when its run ends without a fetch, rather than only when a worker fetches it (6.1)?
- Should the policy apply at execution time rather than at run creation (6.2)?
- Should cron triggers on a zero-persistence project skip pre-switch state rather than consume it (6.1)?
- Should non-admins see admin email addresses on the run page (6.2)?
- Should logs be covered by "Never retain" (6.5)?

## Proposed flows

- `flow-zero-persistence-channel-requests`: the channel half of the original proposal, split out by scope. An admin saves "Never retain"; channel requests drop `client_identity`, events drop their payload fields, requests are marked wiped, and the channel request page shows the request/response wiped viewer. Surfaces: project-settings-data-storage, capability:channel-persistence-policy (`persistence_policy.ex:20-37`; `channels.ex:589-621`; `handler.ex:75`, `:146`; `channel_proxy_plug.ex:224`), channel-request-show (`channel_request_live/show.ex:35`, `:95-101`; `viewers.ex:333-339`).
- Referenced: project-settings-data-storage S06 (entry handoff), history-work-orders S21 and S22, shared-run-components S13, flow-data-retention-change-email (a policy-only change sends no email, its 6.1).

## Proposed shared

- none. Referenced: shared-project-scope, shared-run-components.
