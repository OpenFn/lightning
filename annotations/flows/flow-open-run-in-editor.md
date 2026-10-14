---
id: flow-open-run-in-editor
type: flow
title: Open a run in the workflow editor
status: not-started
owner:

trigger:
  entry: run-show                                   # or history-work-orders; both build the same link
  exit: workflow-editor-run-viewer
  surfaces:
    - run-show                                      # "Workflow" link and each step's inspect link (show.ex:111-118, :212-224)
    - history-work-orders                           # workflow name in a work order row, and each step's inspect link (workorder_component.ex:190-209; components.ex:477-488)
    - controller:legacy-redirect                    # old /w/:id/legacy bookmarks, a -> run (legacy_redirect_controller.ex:21-45)
    - workflow-editor-versions-and-promote          # the pinned version (v=) or as-executed view (as_run=) the editor opens on
    - workflow-editor-ide                           # step inspect links carry panel=editor and job=<job id>
    - workflow-editor-run-viewer
    - workflow-editor-canvas   # added by lead (link lint)
  reachable_when:
    - the run's workflow has not been deleted (hooks.ex:139-157, query.ex:35-40)
    - the run belongs to the project in the URL, for the run to be loaded (collaborate.ex:106-114; runs.ex:73-84)

inherits:
  - shared-project-scope            # login, MFA and membership gates on both ends
  - shared-run-components           # S07 and S08 own the link shape; this file owns what happens after it is followed

url_params:
  - name: run
    set_by: run-show, history-work-orders, controller:legacy-redirect (from a)
    effect: the editor loads that run into the run viewer and follows it live
  - name: v
    set_by: run-show, history-work-orders (default variant, when the run's snapshot is not the workflow's current version)
    effect: the editor joins the read-only room for that snapshot lock_version
  - name: as_run
    set_by: run-show, history-work-orders (experimental-features variant); the editor itself on a locked live workflow
    effect: the editor joins the read-only room for the snapshot that run executed
  - name: panel
    set_by: step inspect links (value editor)
    effect: opens the full-screen IDE
  - name: job
    set_by: step inspect links
    effect: selects that job; the IDE then selects the run's step for it
  - name: a
    set_by: old bookmarks of the retired editor
    effect: remapped to run by the legacy redirect

config_variants:
  default: {}                                                                 # read under this variant
  experimental-features: { user.preferences.experimental_features: true }    # accounts.ex:1446-1448; as_run links and the content lock

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit      # router.ex:303
    - get /projects/:project_id/w/:id/legacy  LegacyRedirectController :edit # router.ex:311
    - get /projects/:project_id/w/new/legacy  LegacyRedirectController :new  # router.ex:310
  events: []                                                                # navigation only; WorkflowLive.Collaborate#handle_params is the hop
  js_hooks:
    - ReactComponent (CollaborativeEditor, data-initial-run-data)           # collaborate.ex:252-287
  policies:
    - Lightning.Policies.Workflows (:access_read)                           # workflows.ex:14-22, via workflow_channel.ex:2255-2305
    - Lightning.Policies.ProjectUsers (:access_project)                     # run_channel.ex:67-77
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features
  not_reachable_here:
    - release=<n> pinned views (pinnedView.ts:9, workflow_channel.ex:2162-2172); no run link sets them, owned by workflow-editor-versions-and-promote
    - LegacyRedirectController :new carries no run; listed because it shares the module

related:
  - lib/lightning_web/live/run_live/components.ex
  - lib/lightning_web/live/run_live/show.ex
  - lib/lightning_web/live/run_live/workorder_component.ex
  - lib/lightning_web/controllers/legacy_redirect_controller.ex
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/hooks.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning/runs.ex
  - lib/lightning/work_orders.ex
  - assets/js/collaborative-editor/lib/pinnedView.ts
  - assets/js/collaborative-editor/components/diagram/CollaborativeWorkflowDiagram.tsx
  - assets/js/collaborative-editor/components/ide/FullScreenIDE.tsx
  - assets/js/collaborative-editor/stores/createHistoryStore.ts
  - assets/js/collaborative-editor/hooks/useWorkflow.tsx
  - assets/js/collaborative-editor/hooks/useVersionMismatch.ts
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/controllers/legacy_redirect_controller_test.exs
  - test/lightning_web/live/run_live/show_test.exs
  - test/lightning_web/live/work_order_live_test.exs
flows: []
---

## 1. Purpose

Someone investigating a run (on its own page or in History) needs to see it against the workflow
it actually ran: the jobs, code and edges at that moment, with each step's outcome painted on the
canvas and its logs and input at hand. Without this flow they would read today's code next to an
old run's results and fix the wrong thing, or lose the link between a log line and the job that
wrote it.

## 2. What it does

Anyone on the project follows a run's workflow or step link from the run page or History (or an old `?a=` bookmark) → the editor opens on the version that run executed, read-only, with the run loaded in the run viewer and, from a step link, the IDE open on that step's job.

## 3. Who can do what

Source: `lib/lightning/policies/workflows.ex:14-22` (`:access_read` is `:access_project`),
`lib/lightning/policies/project_users.ex:134-136`, checked at `workflow_channel.ex:2196-2198`,
`:2255-2257`, `:2289-2290`; run channel join `run_channel.ex:67-77`. Edit and run rights inside
the editor come from `workflow_channel.ex:1516-1522` and are owned by the editor surfaces.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support |
|--------|--------|--------|-------|-------|--------------------|---------|
| Follow a run link into the editor | yes | yes | yes | yes | no | yes, when support access is on |
| See the run in the run viewer | yes | yes | yes | yes | no | yes, when support access is on |
| Edit the pinned or as-executed view | no | no | no | no | no | no |

**Preconditions beyond role**
- The run must belong to the project in the URL, or the editor opens without it (`collaborate.ex:106-114`, `runs.ex:73-84`).
- An as-executed view needs the run's snapshot to belong to the workflow in the URL (`workflow_channel.ex:2314-2320`).
- The workflow must not be soft-deleted (`hooks.ex:139-157`, `workflows.ex:1330-1336`, `query.ex:35-40`).

## 4. What it touches

**Reads**
- Hop 1, link build: `runs.snapshot.lock_version` (run page) or `work_orders.snapshot.lock_version` (History) against `workflows.lock_version` (`show.ex:113`, `workorder_component.ex:193`, `components.ex:288-314`)
- Hop 2, legacy redirect: query string only (`legacy_redirect_controller.ex:25-45`)
- Hop 3, mount: `workflows` (`hooks.ex:144-145`, `collaborate.ex:445-446`); `runs` joined through `work_orders` and `workflows`, with `steps` (`collaborate.ex:110`, `runs.ex:73-84`)
- Hop 4, workflow channel join: `workflow_snapshots` by lock_version (`v`), or `runs` joined to `workflow_snapshots` (`as_run`) (`workflow_channel.ex:2174-2184`, `:2289-2320`)
- Hop 5, run channel: `runs` with `created_by`, `starting_trigger`, `work_order`, `steps` with `job` and dataclips (`run_channel.ex:261-275`)

**Writes**: none

**Immediate side effects**
- Hop 4: a view-only collaboration session is started for the pinned room (`workflow_channel.ex:66-71`); subscriptions to `Projects.Events`, work order events and `workflow:collaborate:<workflow_id>` (`workflow_channel.ex:54-55`, `:78-84`)
- Hop 5: subscriptions to the run's `Runs.Events` topic and `Projects.Events` (`run_channel.ex:78-79`)

**Deferred side effects**
- Run and step broadcasts on the run topic update the run viewer while the run executes (`createHistoryStore.ts:935-945`); owned by workflow-editor-run-viewer

**External, non-transactional effects**
- none

**Depends on config**
- `experimental-features`: links pin `as_run` instead of `v` (`components.ex:308-309`); a live workflow's content is locked and the editor adds `as_run` itself when the run did not execute the current content (`workflow_channel.ex:1507-1510`, `CollaborativeWorkflowDiagram.tsx:137-147`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Open a run in the workflow editor
  In order to read a run against the workflow it actually ran
  As anyone on the project
  I want a run's links to open the editor at that run's version with the run loaded

  @S01 @pending
  Scenario: The run page's workflow link opens the version that ran, with the run loaded
    # Value: people read the run's results against the code that produced them, not code changed since.
    Given run "R" executed on version 1 of "Intake" and "Intake" is now on version 2
    And I am on the run page for "R"
    When I follow the "Workflow" link
    Then I am in the workflow editor for "Intake" at version 1
    And the run viewer shows "R" with its steps
    And the canvas cannot be edited, saying "You are viewing a pinned version of this workflow"
    # show.ex:111-118; components.ex:288-314; collaborate.ex:94-114, :282-286
    # pinnedView.ts:56-67; workflow_channel.ex:43-71, :2152-2184, :2255-2273; useWorkflow.tsx:1089-1094
    # show_test.exs:329-392 (link only); workflow_channel_test.exs:97 (v join)

  @S02 @pending
  Scenario: A step's inspect link opens that step's job in the IDE with the run loaded
    # Value: from a failing step, people land on the code and logs of the job that failed in one click.
    Given run "R" has a failed step for job "Send to DHIS2"
    When I follow that step's inspect link from the run page or from History
    Then the workflow editor opens with the IDE showing "Send to DHIS2"
    And the run viewer has "R"'s step for "Send to DHIS2" selected
    # components.ex:256-270, :477-488; WorkflowEditor.tsx:274; FullScreenIDE.tsx:128-131, :205, :564-578
    # components_test.exs:122-155, :330-345 (link only)

  @S03 @pending
  Scenario: A run on the current version opens the editable workflow
    # Value: people can fix and retry straight from a recent run without first leaving a read-only view.
    Given run "R" executed on the current version of "Intake"
    And I am an editor
    When I follow the work order's workflow name on History
    Then the workflow editor opens on the latest "Intake" with "R" in the run viewer
    And I can edit the workflow
    # components.ex:301-302; workorder_component.ex:190-209; workflow_channel.ex:2196-2207
    # show_test.exs:329-345 asserts no v= on the link

  @S04 @pending @variant:experimental-features
  Scenario: With experimental features the link opens the run as it executed
    # Value: runs on content that was never released can still be read at the code that ran.
    Given I have experimental features enabled
    And run "R" executed on an unreleased draft of "Intake" that has since changed
    When I follow the "Workflow" link on the run page for "R"
    Then the workflow editor shows "Intake" as "R" executed it
    And the run viewer shows "R" with no version mismatch warning
    And the canvas cannot be edited, saying "You are viewing this workflow as a past run executed it"
    # components.ex:308-309; pinnedView.ts:62; workflow_channel.ex:2186-2194, :2289-2320
    # useVersionMismatch.ts:43-44; useWorkflow.tsx:1082-1087
    # workflow_channel_test.exs:2791-2820 (join loads the run's snapshot, including drafts)

  @S05 @pending
  Scenario: A run from another project is not loaded into the editor
    # Value: a run id in a URL cannot be used to read another project's run in this one.
    Given I am an owner on project "Malawi HIV" and not a member of "Kenya TB"
    And run "R" belongs to "Kenya TB"
    When I open "Intake" in "Malawi HIV" with "run=<R id>"
    Then the editor opens with no run data for "R"
    # collaborate.ex:106-114; runs.ex:73-84; run_channel.ex:67-77
    # collaborate_test.exs:222-245 asserts initial_run_data is nil

  @S06 @pending @variant:experimental-features
  Scenario: An as-executed view only accepts a run of the same workflow
    # Value: one workflow's URL cannot be made to display another workflow's code.
    Given run "R" executed workflow "Referrals" in the same project
    When I open "Intake" with "as_run=<R id>"
    Then the editor reports "run not found" and shows no content as executed
    # workflow_channel.ex:2289-2320
    # workflow_channel_test.exs:2822-2845, :2847-2860 (malformed id too)

  @S07 @pending
  Scenario: An old editor bookmark still follows its run
    # Value: run links saved before the editor was replaced keep opening the run.
    Given a bookmark "/projects/<project_id>/w/<Intake id>/legacy?a=<R id>&s=<job id>"
    When I open it
    Then I am redirected to "/projects/<project_id>/w/<Intake id>" with "run=<R id>" and "s=<job id>"
    And the run viewer shows "R"
    # legacy_redirect_controller.ex:21-45; router.ex:310-311
    # legacy_redirect_controller_test.exs:47-80
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The History row pins `v` to the work order's snapshot but loads the last run; a retry runs on the latest snapshot and does not update the work order's snapshot | `workorder_component.ex:193`; `work_orders.ex:361-375`, `:895-904` | a retried work order opens at the original version with the retry's results painted on it, and a version mismatch warning | fix |
| History lists runs of soft-deleted workflows and links them; the editor mount refuses deleted workflows | `workorder_component.ex:190-209`; `hooks.ex:144-157`; `query.ex:35-40` | "Workflow not found" and a redirect to the workflows list | decide |
| `?run=` with a non-UUID reaches `Runs.get_for_project/3` uncast in `handle_params` | `collaborate.ex:106-110`; `runs.ex:73-84` | the editor LiveView crashes on a mistyped or truncated run link | fix |
| The run channel authorizes on the run's own project, not the editor's project, so a foreign run the user can access elsewhere still loads into the viewer once the client asks for it | `run_channel.ex:67-77`; `CollaborativeWorkflowDiagram.tsx:78`, `useHistory.ts:150-162` | another project's run painted onto this workflow's canvas (S05 only covers the server-rendered initial data) | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Step inspect links append `#log`; nothing in the collaborative editor reads the hash | `components.ex:259`, `:484-485`; `use-url-state.ts:14` | decide |
| The run page link is `navigate` (live redirect) but the run-page step link is `patch` across LiveViews, nested inside another patch link | `show.ex:113`, `:212`; `components.ex:258` | decide |
| For a viewer the read-only message is "You do not have permission to edit this workflow", even on a pinned or as-executed view | `useWorkflow.tsx:1075-1094` | preserve |
| `initial_run_data` is server-rendered from `?run=` so the run viewer paints before the run channel joins; the run channel then refetches | `collaborate.ex:94-142`; `createHistoryStore.ts:170-180`, `:897-990` | preserve |
| Under experimental features the editor rewrites the URL itself: adds `as_run` on a locked workflow, or drops `run` when the view changes to one the run does not belong to | `CollaborativeWorkflowDiagram.tsx:104-147` | preserve |
| The legacy redirect forwards other old params (`s`, `m`) unchanged although the new editor names them differently | `legacy_redirect_controller.ex:9-13`, `:39-44` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Each pinned room starts its own view-only collaboration session per workflow version | `workflow_channel.ex:66-71` | no | preserve |

### 6.5 Things seen but not understood

- What the editor shows when the `v` join fails with "snapshot version N not found" (a snapshot removed after the link was built) was not traced on the client (`workflow_channel.ex:2267-2268`).
- No end-to-end test follows a run link into the editor and asserts the run viewer; link tests and join tests are separate.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should History pin the last run's snapshot rather than the work order's (6.1)?
- Should runs of deleted workflows keep a link that cannot open (6.1)?
- Should the run viewer refuse a run outside the editor's project, not just the server-rendered initial data (6.1)?

## Proposed flows

none

## Proposed shared

none
