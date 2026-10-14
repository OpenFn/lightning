---
id: workflows-index
type: view
title: Workflows (project dashboard)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w
  new_route: /projects/:project_id/w
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (see shared-project-scope)

inherits:
  - shared-project-scope            # login, MFA, membership, live revocation (index.ex:15)
  - shared-usage-limits-banner      # :check_limits on_mount and the :banner slot (index.ex:16, :38-44)
  - shared-authenticated-session
  - shared-project-header

url_params:
  - name: q
    set_by: workflows-index (search box, clear search)
    effect: filters the list to workflows whose name contains the term, case-insensitive (index.ex:116, workflows.ex:836-841)
  - name: sort
    set_by: workflows-index (column headers)
    effect: one of name, last_workorder_updated_at, workorders_count, failed_workorders_count, enabled; anything else falls back to name (index.ex:23-24, :118, :139)
  - name: dir
    set_by: workflows-index (column headers)
    effect: "desc" sorts descending, anything else ascending (index.ex:119, :140, table_helpers.ex:93-94)

config_variants:
  default: {}
  experimental-features: { user.preferences.experimental_features: true }      # read at index.ex:104-105
  activation-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(:activate_workflow) returns {:error, _, %Message{}}> }

inventory:
  routes:
    - live /projects/:project_id/w  WorkflowLive.Index :index
  events:
    - WorkflowLive.Index#search_workflows
    - WorkflowLive.Index#clear_search
    - WorkflowLive.Index#sort
    - WorkflowLive.Index#toggle_workflow_state
    - WorkflowLive.Index#delete_workflow
  js_hooks:
    - Tooltip (toggle container, disabled create button, workflow name tooltip)
    - ReactComponent PickerButton (breadcrumb project picker, layout_components.ex:395-420)
    - data-confirm on Delete (dashboard_components.ex:296)
  policies:
    - Lightning.Policies.ProjectUsers (:create_workflow, :edit_workflow, :delete_workflow)
  workers:
    - Lightning.Workflows (Oban, type purge_deleted) # deferred effect of delete, workflows.ex:1023-1063
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features
    - :lightning, Lightning.Extensions, :usage_limiter (limit_action :activate_workflow)
    - purge_deleted_after_days
  not_reachable_here:
    - LightningWeb.WorkflowLive.Components.webhook_auth_methods_table (components.ex:31)
    - LightningWeb.WorkflowLive.Components.linked_usage_for_webhook_auth_method_modal (components.ex:57 in file)
    - LightningWeb.WorkflowLive.Helpers.save_workflow/2 (helpers.ex:19)
    - LightningWeb.WorkflowLive.Helpers.run_workflow/3 (helpers.ex:46)

related:
  - lib/lightning_web/live/workflow_live/index.ex
  - lib/lightning_web/live/workflow_live/dashboard_components.ex
  - lib/lightning_web/live/workflow_live/helpers.ex
  - lib/lightning/dashboard_stats.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflows/workflow_usage_limiter.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning_web/live/helpers/table_helpers.ex
  - test/lightning_web/live/workflow_live/index_test.exs
flows:
  - flow-delete-open-workflow
  - flow-toggle-workflow-open-editor
  - flow-dashboard-history-drilldown
---

## 1. Purpose

This is a project's home page. Everyone on a project uses it to see which workflows exist, whether
each one is switched on, and how it has behaved over the last 30 days, then jump into a workflow,
its health page or the work order history behind a number. Editors also use it to switch workflows
on and off and delete them. Without it, nobody would notice a workflow that has started failing
or been left off, and switching a workflow off in a hurry would mean opening the editor.

## 2. What it does

- Members see every workflow in the project with its latest work order, work order count, failed work order count and on/off state for the last 30 days
- Members see project totals for work orders, runs, successful runs and failed work orders
- Members search workflows by name
- Members sort the list by any column
- Members open a workflow, its health page, or the history filtered to a number they clicked
- Editors and above switch a workflow on or off from the list
- Editors and above delete a workflow
- Editors and above start a new workflow
- With experimental features on, members see a Live or Draft badge instead of the switch (except in sandboxes)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-42` (`:create_workflow`, `:edit_workflow`,
`:delete_workflow` are editor actions), `:160-172` (editor actions allow owner, admin, editor, and
support with no row), `:134` (MFA unsatisfied denies everything).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the page | yes | yes | yes | yes | no | yes, when support access is on |
| Search, sort, follow links | yes | yes | yes | yes | no | yes, when support access is on |
| Create new workflow (button enabled) | no | yes | yes | yes | no | yes, when support access is on |
| Switch a workflow on or off | no | yes | yes | yes | no | yes, when support access is on |
| Delete a workflow (link shown) | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Page access is the shared project scope gate (`index.ex:15`, see shared-project-scope).
- The workflow acted on must belong to this project and not be marked for deletion (`index.ex:237-240`, `:290-291`, `workflows.ex:151-157`).
- Switching on is subject to the usage limiter when it would enable a disabled trigger (`index.ex:319-327`).
- Switch permission is checked at click time (`index.ex:236`); delete permission is the value computed at mount (`index.ex:93-99`, `:289`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `users`, `workflows`, `triggers`, `edges`, `jobs` (`workflows.ex:826-845`); `work_orders`, `runs`, `steps` within the last 30 days (`dashboard_stats.ex:234-318`)

**Writes**
- Switch on: `triggers.enabled = true`, `workflows.state = :live`, `workflow_snapshots`, `workflow_releases` (kind go_live), `audit_events` (`snapshot_created`, `enabled`) (`workflows.ex:1437-1443`, `:330-352`, `:388-406`, `:741-761`)
- Switch off: `triggers.enabled = false`, `workflows.state = :draft`, `workflow_snapshots`, `audit_events` (`snapshot_created`, `disabled`) (`workflows.ex:1480-1486`)
- Delete: `workflows.deleted_at` and name renamed to `<name>_del`, all its `triggers` set `enabled = false, custom_path = nil, legacy_bare_path = false`, `audit_events` (`marked_for_deletion`) (`workflows.ex:902-929`, `:939-950`)

**Immediate side effects** (in the same request)
- Usage limiter `limit_action(:activate_workflow)` on switch-on (`workflow_usage_limiter.ex:42-59`)
- PubSub `workflow_events:<project_id>` `WorkflowUpdated` on switch and delete (`workflows.ex:520`, `:923`, `workflows/events.ex:9-14`)
- PubSub project topic `WorkflowDeleted` on delete (`workflows.ex:928`, `projects/events.ex:123-131`); open editors on that workflow leave (handoff, see flow-delete-open-workflow)
- Switch is reconciled into any open collaborative editing session's Y.Doc (`workflows.ex:522-527`, `collaboration/workflow_reconciler.ex:39-54`); see flow-toggle-workflow-open-editor
- Sandbox save telemetry (`workflows.ex:530-536`)

**Deferred side effects** (later, elsewhere)
- A deleted workflow is permanently purged by the nightly Oban `purge_deleted` sweep once `purge_deleted_after_days` have passed and it has no work order history (`workflows.ex:1007-1075`)
- Switching off or deleting stops its webhook and cron triggers from starting work orders (trigger `enabled = false`)

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- A hosted usage limiter adapter may call out on switch-on; the default adapter does not

**Depends on config**
- `user.preferences.experimental_features` (lifecycle column), usage limiter adapter, `purge_deleted_after_days`

**Product limits** (limits a user would notice and that we intend to keep)
- Every figure covers the last 30 days only (`dashboard_stats.ex:15`, `:226-232`; "Nothing last 30 days" at `dashboard_components.ex:421`)

## 5. Scenarios

Verified against the `default` variant unless tagged.

```gherkin
Feature: Project workflows dashboard
  In order to see what my project's workflows are doing and act on them quickly
  As a member of a project
  I want a list of workflows with their recent activity and controls

  Background:
    Given project "Malawi HIV" has workflows "Intake", "Sync DHIS2" and "Weekly report"

  @S01 @pending
  Scenario: Member sees the project's workflows with recent activity
    # Value: anyone on the project can tell at a glance which workflows are busy and which are failing.
    Given I am a viewer on project "Malawi HIV"
    And "Intake" had 4 work orders in the last 30 days, 1 of them failed
    When I open the workflows page
    Then I see "Workflows (3)"
    And the "Intake" row shows its latest work order state and time
    And the "Intake" row shows 4 work orders with its step count and success rate
    And the "Intake" row shows 1 work order in a failed state with the time of the latest failure
    # index.ex:151-170, dashboard_components.ex:93-102, :180-263, dashboard_stats.ex:52-110
    # index_test.exs:113-271

  @S02 @pending
  Scenario: Workflow with no recent activity says so
    # Value: an idle workflow is visibly idle instead of looking like missing data.
    Given "Weekly report" has had no work orders in the last 30 days
    When I open the workflows page
    Then the "Weekly report" row shows "Nothing last 30 days"
    And its work order and failed counts show 0 and "N/A"
    # dashboard_components.ex:224-231, :254-261, :418-421; index_test.exs:266-270

  @S03 @pending
  Scenario: Member sees project totals
    # Value: the project's overall health over the last month is visible without opening any workflow.
    Given the project had 10 work orders in the last 30 days, 6 pending and 2 failed
    And 10 runs, 6 pending and 2 successful out of 4 finished
    When I open the workflows page
    Then the "Work Orders" card shows 10 and "6 pending"
    And the "Runs" card shows 10 and "6 pending"
    And the "Successful Runs" card shows 2 and "50.0%"
    And the "Work Orders in failed state" card shows 2 and "20.0%"
    # dashboard_components.ex:489-547, dashboard_stats.ex:159-218; index_test.exs:134-171

  @S04 @pending
  Scenario: Search narrows the list by name
    # Value: people find one workflow quickly in a project with many.
    When I type "sync" in the search box
    Then I see "Sync DHIS2"
    And I do not see "Intake"
    And the URL query has "q=sync"
    # index.ex:115-129, :175-185, workflows.ex:836-841; index_test.exs:763-774, :789-797

  @S05 @pending
  Scenario: A search with no matches offers to create a workflow
    # Value: a dead-end search still leads somewhere useful.
    When I search for "nonexistent"
    Then I see 'No workflows found matching "nonexistent". Try a different search term or create a new one.'
    And "create a new one" links to "/projects/<project_id>/w/new"
    # dashboard_components.ex:39-45; index_test.exs:799-811

  @S06 @pending
  Scenario: Clearing the search restores the full list
    # Value: getting back to every workflow is one click.
    Given I am on the workflows page with "q=api"
    When I click the clear search button
    Then I see all three workflows
    And the URL is "/projects/<project_id>/w?sort=name&dir=asc"
    # index.ex:187-200, dashboard_components.ex:397-406; index_test.exs:776-787

  @S07 @pending
  Scenario: A project with no workflows invites the first one
    # Value: a new project points its members to the next step.
    Given project "Empty" has no workflows
    When I open its workflows page
    Then I see "No workflows found. Create one to start automating."
    And "Create one" links to the new workflow page
    # dashboard_components.ex:46-51; index_test.exs:948-956

  @S08 @pending
  Scenario Outline: Sorting by a column
    # Value: people can bring the busiest, most failing, most recent or switched-off workflows to the top.
    When I click the "<column>" header
    Then the list is sorted ascending by <column>
    And the URL query has "sort=<key>&dir=asc"
    When I click the "<column>" header again
    Then the list is sorted descending by <column>
    # index.ex:139-161, :202-218, table_helpers.ex:110-118, dashboard_stats.ex:134-157, workflows.ex:847-861
    # index_test.exs:815-929
    Examples:
      | column                        | key                       |
      | Name                          | name                      |
      | Latest Work Order             | last_workorder_updated_at |
      | Work Orders                   | workorders_count          |
      | Work Orders in a failed state | failed_workorders_count   |
      | Enabled                       | enabled                   |

  @S09 @pending
  Scenario: Search and sort combine and survive in the URL
    # Value: a filtered, sorted view can be bookmarked or shared.
    When I open "/projects/<project_id>/w?q=api&sort=name&dir=desc"
    Then I see only workflows matching "api", in reverse name order
    # index.ex:115-129, :335-346; index_test.exs:931-941

  @S10 @pending
  Scenario: Unknown sort parameters fall back to the default
    # Value: a crafted URL can't exhaust the server's atom table and take the instance down.
    When I open "/projects/<project_id>/w?sort=bogus&dir=bogus"
    Then the page loads sorted by name ascending
    # index.ex:21-24, :139-140, table_helpers.ex:84-94; index_test.exs:27-46

  @S11 @pending
  Scenario: Editor switches a workflow on
    # Value: a workflow can be put back into service from the list without opening the editor.
    Given I am an editor on project "Malawi HIV"
    And "Intake" is a draft with its webhook trigger disabled
    When I click the "Intake" switch
    Then I see "Workflow updated"
    And the "Intake" switch is on with tooltip "This workflow is active (webhook trigger enabled)"
    And "Intake" is live with its trigger enabled
    And an audit event "enabled" is recorded
    And the flow "flow-toggle-workflow-open-editor" has started for "Intake"
    # index.ex:220-248, :317-329, workflows.ex:1437-1443, :741-761; index_test.exs:273-343, :371-400

  @S12 @pending
  Scenario: Editor switches a workflow off
    # Value: a misbehaving workflow can be stopped from the list in one click.
    Given I am an editor on project "Malawi HIV"
    And "Intake" is live with its webhook trigger enabled
    When I click the "Intake" switch
    Then I see "Workflow updated"
    And "Intake" is a draft with its trigger disabled
    And the "Intake" switch is off with tooltip "This workflow is inactive (manual runs only)"
    And an audit event "disabled" is recorded
    # index.ex:331-333, workflows.ex:1480-1486, helpers.ex:113-123; index_test.exs:402-413

  @S13 @pending @variant:activation-limited
  Scenario: The plan limit can refuse switching a workflow on
    # Value: a project over its active-workflow allowance learns why instead of silently exceeding it.
    Given I am an editor on project "Malawi HIV"
    And the usage limiter refuses workflow activation with "No more workflows"
    And "Intake" has its trigger disabled
    When I click the "Intake" switch
    Then I see "No more workflows"
    And "Intake" still has its trigger disabled
    # index.ex:250-254, :322-327, workflow_usage_limiter.ex:42-43; index_test.exs:455-505

  @S14 @pending @variant:activation-limited
  Scenario: Re-confirming an already enabled workflow is not counted against the limit
    # Value: a project at its limit can still touch workflows that are already on.
    Given the usage limiter refuses workflow activation
    And "Sync DHIS2" has all its triggers enabled
    When "toggle_workflow_state" is sent for "Sync DHIS2" with state true
    Then I see "Workflow updated"
    And the usage limiter was not consulted
    # index.ex:319-320, workflow_usage_limiter.ex:40; index_test.exs:507-513

  @S15 @pending
  Scenario: Viewer cannot switch a workflow
    # Value: read-only members can't stop or start production integrations.
    Given I am a viewer on project "Malawi HIV"
    And "Intake" has its trigger disabled
    When I click the "Intake" switch
    Then I see "You are not authorized to perform this action."
    And "Intake" still has its trigger disabled
    # index.ex:236, :263-267; index_test.exs:516-540 (asserts only that nothing changed)

  @S16 @pending
  Scenario Outline: Actions on a workflow outside the project are refused
    # Value: a forged id can't switch off or delete another project's workflow.
    Given I am an editor on project "Malawi HIV"
    And workflow "Foreign" belongs to a project I am not on
    When "<event>" is sent with the id of "Foreign"
    Then I see "Workflow not found."
    And "Foreign" is unchanged
    # index.ex:237-240, :269-273, :290-291, :312-313, workflows.ex:151-157
    # index_test.exs:417-453, :738-759
    Examples:
      | event                 |
      | toggle_workflow_state |
      | delete_workflow       |

  @S17 @pending
  Scenario: Editor deletes a workflow
    # Value: retired workflows can be removed, and their triggers stop answering at once.
    Given I am an editor on project "Malawi HIV"
    When I click "Delete" on "Weekly report"
    And I confirm "Are you sure you'd like to delete this workflow?"
    Then I see "Workflow successfully deleted."
    And "Weekly report" is no longer listed
    And every trigger of "Weekly report" is disabled
    And an audit event "marked_for_deletion" is recorded with me as actor
    And the flow "flow-delete-open-workflow" has started for "Weekly report"
    # dashboard_components.ex:290-299, index.ex:277-301, workflows.ex:902-929
    # index_test.exs:699-735

  @S18 @pending
  Scenario: A deleted workflow's name can be reused
    # Value: deleting and recreating a workflow under the same name works.
    Given I deleted "Weekly report"
    Then no active workflow in the project holds the name "Weekly report"
    # workflows.ex:931-950 (renamed to "Weekly report_del")

  @S19 @pending
  Scenario: Viewer cannot delete a workflow
    # Value: read-only members can't remove workflows, even by sending the event directly.
    Given I am a viewer on project "Malawi HIV"
    When I open the workflows page
    Then I see no "Delete" action on any row
    When "delete_workflow" is sent for "Intake"
    Then I see "You are not authorized to perform this action."
    # dashboard_components.ex:291, index.ex:93-99, :289, :307-310; index_test.exs:685-697

  @S20 @pending
  Scenario: Viewer sees the create button disabled with a reason
    # Value: read-only members understand why they can't start a workflow.
    Given I am a viewer on project "Malawi HIV"
    When I open the workflows page
    Then the "Create new workflow" button is disabled
    And it has the tooltip "You are not authorized to perform this action."
    # index.ex:85-91, dashboard_components.ex:350-376, new_inputs.ex:290-300; index_test.exs:622-636

  @S21 @pending
  Scenario: Editor starts a new workflow
    # Value: creating a workflow starts from the project's home page.
    Given I am an editor on project "Malawi HIV"
    When I click "Create new workflow"
    Then I am on "/projects/<project_id>/w/new"
    # dashboard_components.ex:364-368; index_test.exs:638-653 (asserts the button is enabled; navigation not clicked)

  @S22 @pending
  Scenario: Clicking a workflow name opens it in the editor
    # Value: the list is the way into each workflow.
    When I click "Intake"
    Then I am on "/projects/<project_id>/w/<intake_id>"
    # dashboard_components.ex:187-198

  @S23 @pending
  Scenario: Each row links to the workflow's health page
    # Value: someone looking at a failing count can go straight to the workflow's health detail.
    Then the "Intake" row has a "Health" link to "/projects/<project_id>/w/<intake_id>/health"
    # dashboard_components.ex:282-289; index_test.exs:542-554

  @S24 @pending
  Scenario: Counts link to the work orders behind them
    # Value: a number on the dashboard can be inspected without rebuilding the filter by hand.
    Given "Intake" had 4 work orders in the last 30 days, 1 of them failed
    Then the "Intake" work order count links to history filtered by workflow "Intake" and the last 30 days
    And the "Intake" failed count links to history filtered by workflow "Intake", the last 30 days and every failure state
    And the "Work Orders" card's pending link filters pending and running work orders in the last 30 days
    And the failed card's "View all" link filters every failure state in the last 30 days
    And the flow "flow-dashboard-history-drilldown" starts from each link
    # dashboard_components.ex:84-91, :115-126, :209-219, :236-247, :489-543; index_test.exs:144-259

  @S25 @pending
  Scenario: A workflow with no count has no history link
    # Value: people aren't sent to an empty history page.
    Given "Weekly report" has had no work orders in the last 30 days
    Then the "Weekly report" row has no history link
    # dashboard_components.ex:209, :236; index_test.exs:213-217

  @S26 @pending
  Scenario: A workflow with every trigger off is shown as disabled
    # Value: switched-off workflows stand out so nobody assumes they are running.
    Given "Intake" has all its triggers disabled
    When I open the workflows page
    Then the "Intake" name is greyed out with the tooltip "Intake (disabled)"
    And the "Intake" switch is off with tooltip "This workflow is inactive (manual runs only)"
    # dashboard_components.ex:196, :315-345, helpers.ex:102-123; index_test.exs:329-332

  @S27 @pending @variant:experimental-features
  Scenario: Lifecycle mode shows state instead of a switch
    # Value: with the publish lifecycle, people see at a glance which workflows are live and which are drafts.
    Given I have experimental features enabled
    And "Intake" is live
    When I open the workflows page of project "Malawi HIV"
    Then the state column is headed "State"
    And the "Intake" row shows "Live"
    And no row has an on/off switch
    # index.ex:104-105, dashboard_components.ex:265-267, :571-575, :590-602; index_test.exs:569-586

  @S28 @pending @variant:experimental-features
  Scenario: Lifecycle mode keeps the switch inside a sandbox
    # Value: sandbox workflows can still be turned on and off for testing.
    Given I have experimental features enabled
    And I own sandbox "dev" with a workflow
    When I open the workflows page of sandbox "dev"
    Then the state column is headed "Turn on"
    And each row has an on/off switch
    # dashboard_components.ex:265-277, :573-574; index_test.exs:588-603

  @S29 @pending
  Scenario: Without experimental features the column is "Enabled" with a switch
    # Value: the established on/off control stays as it was for everyone not opted in.
    Given I do not have experimental features enabled
    When I open the workflows page
    Then the state column is headed "Enabled"
    And each row has an on/off switch
    # dashboard_components.ex:268-277, :571; index_test.exs:605-618
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Delete's error branch matches `{:error, _changeset}`, but `mark_for_deletion` returns an `Ecto.Multi` transaction result, whose failure is a 4-tuple | `index.ex:303-304`, `workflows.ex:908-916` | a failed delete crashes the LiveView (CaseClauseError) and the page remounts instead of showing "Can't delete workflow" | fix |
| The on/off switch renders, enabled, for viewers; the click is refused only on the server | `dashboard_components.ex:268-277`, `index.ex:263-267` | a viewer can click a working-looking switch and gets "You are not authorized to perform this action." | fix |
| A workflow with no triggers: the switch is checked (`Enum.all?([])` is true) while its tooltip says inactive and the name is greyed "(disabled)" | `helpers.ex:89-91`, `:115-116`, `dashboard_components.ex:196` | an "on" switch next to "This workflow is inactive (no triggers configured)" | fix |
| Three definitions of "enabled": switch uses all triggers enabled, name greying uses any trigger enabled, Enabled sort uses any (`MAX`) | `helpers.ex:90`, `dashboard_components.ex:196`, `workflows.ex:852-857` | a partly enabled workflow shows the switch off, its name not greyed, and sorts with the enabled ones | fix |
| Step count is reported as 0 whenever no step succeeded | `dashboard_stats.ex:174-175` | "(0 steps, 0.0% success)" for a workflow whose steps all failed | fix |
| Project metric cards are aggregated from the searched list, but their links open the whole project's history | `index.ex:163`, `dashboard_components.ex:493-543` | after searching, "Work Orders in failed state" shows 1 but "View all" lists 5 | fix |
| The "last 30 days" period is passed to the header's `:period` slot, which the header never renders | `index.ex:55`, `layout_components.ex:255-300` | counts with no visible time window except "Nothing last 30 days" in idle rows | decide |
| Row has hover styling and `onclick={JS.navigate(...)}` on the `<tr>`; a JS struct in a plain `onclick` attribute renders as JSON, which does nothing (read from code, not run) | `dashboard_components.ex:181-185` | only the name cell navigates; clicking elsewhere in a highlighted row does nothing | decide |
| In a sandbox with lifecycle mode, the switch tooltip reads `workflow.state` while the switch position reads triggers | `dashboard_components.ex:273-274`, `:580-586` | switch off with tooltip "On. Its triggers are answering." when state and triggers disagree | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Search uses `ilike` with the raw term, so `%` and `_` act as wildcards | `workflows.ex:838` | decide |
| "Workflows (n)" counts the filtered list, not the project | `index.ex:60` | decide |
| Stat-column sorts are in memory over a name-ascending list, so ties stay name-ascending in both directions | `index.ex:151-161`, `dashboard_stats.ex:137` | preserve |
| Workflows with no activity sort first on "Latest Work Order" ascending | `dashboard_stats.ex:149` | preserve |
| Latest work order is chosen by `last_activity` but displayed, and sorted, by `updated_at` | `dashboard_stats.ex:146-153`, `:307-312` | decide |
| Run counts fold cancelled, crashed, killed and the rest into "failed"; work order counts keep cancelled separate | `dashboard_stats.ex:262-272` vs `:240-246` | decide |
| Failed % divides by all work orders including pending and cancelled; success rate divides by finished runs only | `dashboard_stats.ex:209-211` | decide |
| Count windows use `> window_start` at query time; history links use `>=` with a window computed at render | `dashboard_stats.ex:226-232`, `invocation.ex:743-745` | preserve |
| Switch permission is re-checked per click; delete uses the mount-time assign (a role change remounts via shared-project-scope) | `index.ex:236`, `:93-99`, `:289` | preserve |
| A failed or refused delete does not patch the URL; every other outcome does | `index.ex:303-313` | preserve |
| `toggle_workflow_state` is still accepted in lifecycle mode, where no switch renders | `index.ex:220`, `dashboard_components.ex:266-267` | decide |
| Switching off also sets `state: :draft` without experimental features, and switching on records a go-live release | `workflows.ex:1437-1443`, `:1480-1486` | preserve |
| Limiter is consulted only when some trigger is disabled; a workflow with no triggers goes live without it | `index.ex:319-320` | preserve |
| A limiter refusal shows its text only if it is a `%Message{}`; anything else gets "Failed to update workflow. Please try again." | `index.ex:250-260` | preserve |
| The list does not live-update: other users' switches and deletes appear only after a reload or patch (`WorkflowDeleted` is ignored here) | `hooks.ex:336-340`; no `handle_info` in `index.ex` | decide |
| An unknown `sort` value stays in the assign and the URL even though the query falls back to name | `index.ex:118-127`, `:139` | preserve |
| History links carry `onclick="event.stopPropagation()"`, which only matters if the row click worked (see 6.1) | `dashboard_components.ex:216`, `:243`, `:286` | decide |
| Page title "Workflows" and sidebar item `:overview` | `index.ex:167-168` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `WorkflowLive.Components` (webhook auth methods table and linked-usage modal) | `components.ex:1-218` | listed in this view's inventory row but rendered only by project settings (`settings.html.heex:461-467`) |
| `Helpers.save_workflow/2`, `Helpers.run_workflow/3` | `helpers.ex:15-83` | used by `controllers/workflow_controller.ex`, not by this view |
| `attr` declarations above the LiveView `render/1` | `index.ex:26-32` | `attr` has no effect on a LiveView's own render; assigns come from mount |
| `@dashboard_period` "TODO - make this configurable" | `index.ex:18-19` | fixed string, no config read |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Figures cover a fixed 30-day window | `dashboard_stats.ex:15` | yes, "Nothing last 30 days" | preserve |
| Search fires 300 ms after the last keystroke, and every search or sort reloads all workflows and re-runs the five stats queries | `dashboard_components.ex:393-394`, `index.ex:151-152`, `dashboard_stats.ex:57-66` | no | preserve |
| No pagination; every workflow is loaded with triggers, edges and jobs preloaded | `workflows.ex:827` | no, until a project has many workflows | decide |
| Workflow names truncate at 200px with the full name in a tooltip | `dashboard_components.ex:319-336` | yes | preserve |

### 6.5 Things seen but not understood

- `index_test.exs:23-24` and `:102` call `element(view, "#workflows-<id>", "No workflows yet")` inside `assert` without `has_element?`; `element/3` returns a struct, so these assertions always pass, and the text "No workflows yet" exists nowhere in the view. These tests do not verify what their names say.
- `index_test.exs:350-369` is named "the toggle, its tooltip and its sort all read the triggers" but asserts only that the switch is unchecked for a partly enabled workflow. Its intent and the 6.1 "three definitions of enabled" row need reconciling.
- `index_test.exs:63-83` expects the limiter's `limit_action` to be called zero times on page load, described as "we allow create but block save"; no code on this page calls the limiter on load, so it is unclear what regression it guards.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- What should "enabled" mean for a workflow with several triggers, and for one with none (see 6.1)?
- Should the project metric cards follow the search filter or always show the whole project (see 6.1)?
- In lifecycle mode, should `toggle_workflow_state` be refused server-side outside sandboxes (see 6.2)?
- Should the list update live when another user switches or deletes a workflow (see 6.2)?

## Proposed flows

- `flow-delete-open-workflow`: deleting a workflow here broadcasts `WorkflowDeleted`, and any session with that workflow open in the editor is sent back to the list with "Workflow deleted." Surfaces: workflows-index, pubsub:project_events:<project_id> (`projects/events.ex:123-131`), workflow-editor-canvas (receiving end in shared-project-scope S12, `hooks.ex:325-335`).
- `flow-toggle-workflow-open-editor`: switching a workflow on or off here is reconciled into an open collaborative editor's Y.Doc, so the other tab shows the new trigger state. Surfaces: workflows-index, `Lightning.Collaboration.WorkflowReconciler` (`workflow_reconciler.ex:39-54`), pubsub:workflow_events:<project_id>, workflow-editor-canvas.
- `flow-dashboard-history-drilldown`: the count and card links open history with workflow, 30-day window and state filters, and history must show the same work orders the count was taken from. Surfaces: workflows-index, history-work-orders (url_params `filters[workflow_id]`, `filters[date_after]`, state flags, `filters[log]`).

## Proposed shared

- `shared-project-header`: the project page header used by every project LiveView: breadcrumb project picker (`ReactComponent` PickerButton, `layout_components.ex:395-420`) and the unconfirmed-account banner with "Resend confirmation email" (`layout_components.ex:259-276`, gated on `require_email_verification`). Surfaces: every view rendering `LayoutComponents.header` with `breadcrumb_project_picker`.
- `shared-sortable-table-header`: `<.th sortable>` emitting `sort` with `phx-value-by`, plus `TableHelpers.toggle_sort_direction/3`, `sort_field/3` and `sort_direction/1` used by several list views. Surfaces: workflows-index, users admin table (`user_live/table_component.ex:48`), any table using `table.ex:223-248`.

## Lead resolution (batch 1)

- All three flows created as proposed.
- `shared-project-header` created. `shared-sortable-table-header` declined: sorting is view behaviour and stays in each view's scenarios.
- The `components.ex` entry in this view's inventory row was a lead error; it belongs to project-settings-webhook-security. The 6.3 row and `not_reachable_here` entries for it can be ignored.
