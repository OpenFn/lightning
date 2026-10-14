---
id: dataclip-show
type: view
title: Dataclip
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/dataclips/:id/show
  new_route: /projects/:project_id/dataclips/:id
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; show.ex:9)
    - the dataclip belongs to this project, otherwise the page redirects to History with "Dataclip not found" (show.ex:20-34; invocation.ex:225-235)

inherits:
  - shared-authenticated-session    # router.ex:288 (live_session :default, LightningWeb.InitAssigns)
  - shared-project-scope            # show.ex:9
  - shared-usage-limits-banner      # show.ex:10, :41-47
  - shared-project-header           # show.ex:48-67 (project picker, "Dataclip" breadcrumb)
  - shared-local-datetime           # show.ex:92-94, :100-102, :109-111 (Created, Updated, Wiped)
  - shared-dataclip-body-viewer
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: project_id
    set_by: every project link
    effect: owned by shared-project-scope
  - name: id
    set_by: run-show "Final Output" link (run_live/show.ex:166-180), history-work-orders input dataclip link (workorder_component.ex:450-462, shown only when the input is not wiped, :481-483)
    effect: the dataclip to show; another project's dataclip, an unknown id or a malformed id redirects to History (S07)

config_variants:
  default: {}                                                                  # read under this one
  usage-limited: { Lightning.Extensions.usage_limiter: <hosted adapter returning {:error, _, %{position: :banner}}> }   # owned by shared-usage-limits-banner

inventory:
  routes:
    - live /projects/:project_id/dataclips/:id/show  DataclipLive.Show :show   # router.ex:299
  events:
    - DataclipLive.Show handle_params id                                       # show.ex:19-35
  js_hooks:
    - ReactComponent DataclipViewer      # assets/js/react/components/DataclipViewer.tsx; viewers.ex:200-210
    - CodeViewer (React, read-only Monaco with copy button)   # assets/js/react/components/CodeViewer.tsx; rendered by DataclipViewer.tsx:58
    - LocalTimeConverter                 # owned by shared-local-datetime
    - Copy                               # Common.datetime click-to-copy, owned by shared-local-datetime
  policies:
    - Lightning.Policies.ProjectUsers :access_project        # via shared-project-scope; and via Dataclips below (policies/dataclips.ex:21)
    - Lightning.Policies.Dataclips :view_dataclip            # body fetch (dataclip_controller.ex:16-30)
  workers: []
  api_endpoints:
    - get /dataclip/body/:id  DataclipController :show       # router.ex:201; fetched by DataclipViewer.tsx:10-30
  emails: []
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (check_limits banner; live_helpers.ex:196-200)
  not_reachable_here:
    - lib/lightning_web/live/dataclip_live/form_component.html.heex (whole template; no module renders it, see 6.3)
    - Viewers.step_dataclip_viewer and wiped_data_viewer (viewers.ex:243-290 and following); run-show only. This page renders its own wiped panel (show.ex:122-138)
    - DataclipController :search, :show_for_run, :update_name (dataclip_controller.ex:114-292); editor only

related:
  - run-show
  - history-work-orders
  - workflow-editor-run-viewer
  - project-settings-data-storage
  - lib/lightning_web/components/viewers.ex
  - lib/lightning_web/controllers/dataclip_controller.ex
  - lib/lightning/dataclip_scrubber.ex
flows:
  - flow-zero-persistence-runs       # referenced (S10); dataclip-show is not yet in its surfaces
---

## 1. Purpose

Anyone on a project opens a dataclip to read one piece of data exactly as Lightning stored it: a
webhook request that arrived, the output of a step, or an input someone saved. People reach it from
a run's final output or a work order's input in History when they need to check what a system sent
or what a job produced. Without it, diagnosing a broken mapping means guessing at the payload, or
asking someone with database access, while credentials inside that payload must stay hidden.

## 2. What it does

- Anyone on the project sees a dataclip's id, type, created and updated times
- Anyone reads the dataclip's body, formatted, in a read-only viewer
- Anyone copies the body to the clipboard
- Anyone sees a webhook request's body and request metadata together, with webhook credentials hidden
- Anyone sees a step's output with the step's credential values hidden
- Anyone opening a wiped dataclip is told its data was erased under the project's retention policy, and when
- Nobody can open another project's dataclip through this page
- Non-members cannot open the page at all (shared-project-scope)
- Anyone opening a zero-persistence run's final output lands on its wiped panel (flow-zero-persistence-runs)

## 3. Who can do what

Source: the page has no policy check of its own beyond the project scope gate
(`show.ex:9`; `lib/lightning/policies/project_users.ex:134-136`, `:190-191`). The body is fetched
from `/dataclip/body/:id`, which asks `Lightning.Policies.Dataclips :view_dataclip`
(`dataclip_controller.ex:19-30`), which delegates to `:access_project` on the dataclip's own project
(`policies/dataclips.ex:20-22`; `projects/scope.ex:167`, `:149`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Open the dataclip page (visibility) | yes | yes | yes | yes | no | yes, when support access is on |
| See the dataclip's details | yes | yes | yes | yes | no | yes, when support access is on |
| Read and copy the body | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The dataclip must belong to the project in the URL (`show.ex:23`; `invocation.ex:225-235`).
- The body request re-checks access against the dataclip's own project, and refuses it with 403 when the user has no standing there or the project is scheduled for deletion (`dataclip_controller.ex:19-30`; `policies/dataclips.ex:20-22`; `projects/scope.ex:149`; `dataclip_controller_test.exs:241-249`, `:262-288`).
- MFA, deleted projects and membership changes on an open page are owned by shared-project-scope.
- The body viewer only renders when the dataclip has not been wiped (`show.ex:122-144`).

## 4. What it touches

**Reads**
- `dataclips`: an existence check scoped by project (`invocation.ex:225-235`), then the row without `body` and `request`, which are `load_in_query: false` (`invocation.ex:217`; `dataclip.ex:59-60`)
- `dataclips.body` and `dataclips.request` as text through `get /dataclip/body/:id`; `http_request` and `kafka` bodies are wrapped as `{"data": body, "request": request}` (`invocation.ex:128-143`; `query.ex:346-363`)
- For scrubbing a `step_result` body: `steps` whose output is this dataclip, then the credentials used by those steps and the webhook auth methods of their triggers (`dataclip_scrubber.ex:26-38`)
- For scrubbing an `http_request` body: the webhook auth methods behind the work order it started (`dataclip_scrubber.ex:40-41`)
- `projects` and `project_users` for the scope gate (shared-project-scope) and again for the body request (`projects/scope.ex:167`, `:188`)

**Writes**
- none

**Immediate side effects**
- Subscribes to the project's events for membership changes (owned by shared-project-scope)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- usage limiter banner (variant `usage-limited`; owned by shared-usage-limits-banner)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Dataclip page
  In order to check exactly what data arrived or was produced
  As anyone on the project
  I want to read a stored dataclip with its details

  @S01 @pending
  Scenario: The details panel identifies the dataclip
    # Value: people can tell exactly which piece of data they are reading and when it was stored.
    Given project "Malawi HIV" has a step result dataclip with body {"foo": "bar"}
    When I open its dataclip page
    Then the breadcrumb reads "Dataclip" followed by the first eight characters of its id
    And the "Dataclip Details" panel shows "ID" with the full id
    And it shows "Type", "Created" and "Updated"
    And it does not show "Wiped"
    # show.ex:20-28, :56-104; live_helpers.ex:169-171
    # test/lightning_web/live/dataclip_live_test.exs:17-47

  @S02 @pending
  Scenario Outline: The type pill says where the data came from
    # Value: people know whether they are looking at what a system sent, what a job produced, or what someone saved by hand.
    Given a dataclip of type <type>
    When I open its dataclip page
    Then "Type" shows a pill reading <label>
    # show.ex:84-86; common.ex:614-639; dataclip.ex:35-43 (kafka kept so stored inputs stay honestly labelled)

    Examples:
      | type          | label            |
      | http_request  | "http_request"   |
      | step_result   | "step_result"    |
      | saved_input   | "saved_input"    |
      | global        | "global"         |
      | kafka         | "kafka"          |

  @S03 @pending
  Scenario: The body is shown formatted and read-only
    # Value: people read the payload in a form they can scan, without any risk of changing stored data.
    Given a global dataclip whose body is {"patients":[{"id":1}]}
    When I open its dataclip page
    Then the viewer shows the body as JSON indented by two spaces
    And the viewer does not accept typing
    # show.ex:139-144; viewers.ex:200-210; DataclipViewer.tsx:10-58; CodeViewer.tsx:79-99
    # dataclip_live_test.exs:49-52 asserts only that the viewer element is rendered

  @S04 @pending
  Scenario: The body can be copied
    # Value: people lift the payload into a manual run, a test or a bug report without retyping it.
    Given I am on a dataclip page whose body has loaded
    When I click "Copy to clipboard"
    Then the clipboard holds the body as displayed
    And the button reads "Copied!" for two seconds
    # CodeViewer.tsx:11-37, :41-77

  @S05 @pending
  Scenario: A webhook request shows its data and request together, with webhook credentials hidden
    # Value: people see what a source system actually sent without exposing the secret it authenticates with.
    Given workflow "Intake" has a webhook trigger protected by basic auth "webhook_user" with password "webhook_secret_pass"
    And a request to that webhook stored an http_request dataclip with an "authorization" header and data "test payload"
    When I open the dataclip page
    Then the viewer shows "data" and "request" keys
    And it shows "test payload"
    And it does not show "webhook_secret_pass" or its base64 basic auth value
    And it shows "***" in their place
    # query.ex:346-363; dataclip_controller.ex:57-78; dataclip_scrubber.ex:40-41
    # test/lightning_web/controllers/dataclip_controller_test.exs:111-162

  @S06 @pending
  Scenario: A step's output hides the credential values the step used
    # Value: a job that echoes its configuration does not leak credential secrets to everyone who can read the project.
    Given step "Fetch" ran with a credential whose values include the number 1234 and the string "some-secret"
    And "Fetch" produced an output dataclip containing those values
    When I open that output's dataclip page
    Then those values are shown masked with "***"
    And values not in the credential are shown unchanged
    # dataclip_controller.ex:62-70; dataclip_scrubber.ex:26-38
    # dataclip_controller_test.exs:164-178

  @S07 @pending
  Scenario: A dataclip from another project cannot be opened
    # Value: a member of one project cannot read another project's data by guessing a dataclip id.
    Given I am an editor on project "Malawi HIV"
    And dataclip "D" belongs to project "Kenya TB"
    When I visit "/projects/<Malawi HIV id>/dataclips/<D id>/show"
    Then I am on the "Malawi HIV" history page
    And I see "Dataclip not found"
    And the same happens for an id that does not exist or is not a valid id
    # show.ex:20-34; invocation.ex:225-235
    # dataclip_live_test.exs:93-113 (other project only)

  @S08 @pending
  Scenario: A non-member cannot open the page
    # Value: project data stays with the people on the project.
    Given dataclip "D" belongs to project "Kenya TB"
    And I am not on "Kenya TB"
    When I visit "/projects/<Kenya TB id>/dataclips/<D id>/show"
    Then shared-project-scope S03 holds
    # show.ex:9
    # dataclip_live_test.exs:55-91

  @S09 @pending
  Scenario: A wiped dataclip says its data was erased, and when
    # Value: people can tell data deliberately erased under the retention policy from data that failed to arrive.
    Given project "Malawi HIV" has a step result dataclip that the retention policy wiped on 1 March
    When I open its dataclip page
    Then the details panel shows "Wiped" with that time
    And I see "No Data Available"
    And I see "This dataclip's data has been wiped in accordance with the project's data retention policy."
    And no body viewer is shown
    # show.ex:105-138; wiping: projects.ex:224-231, :1734-1785; query.ex:365-373
    # dataclip_live_test.exs:51-52 refutes this panel for an unwiped dataclip; nothing asserts the wiped case

  @S10 @pending
  Scenario: A zero-persistence run's final output opens as wiped
    # Value: people following a run's output on a zero-persistence project are told why there is nothing to read.
    Given project "Malawi HIV" does not retain data
    And a run of "Intake" has finished with a final output
    When I follow "Final Output" on the run page
    Then the flow "flow-zero-persistence-runs" ends on this page with the wiped panel from S09
    # run_live/show.ex:166-180; handlers.ex:172-204 (wiped final dataclip, per flow-zero-persistence-runs section 4)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The viewer re-formats the body with `JSON.parse` and `JSON.stringify`, so integers beyond 2^53 are rounded, and the copy button copies the rounded text | `DataclipViewer.tsx:41-46`; `CodeViewer.tsx:13` | a large id such as 12345678901234567890 shows and copies as 12345678901234567000 | fix |
| The copy button hides only for "Failed to load content"; for "Dataclip not found" it shows and copies that message | `CodeViewer.tsx:41`; `DataclipViewer.tsx:48-50` | a copy button that puts an error message on the clipboard | fix |
| "Updated" does not change when the body is wiped, because the wipe is an `update_all` that never sets `updated_at`; it changes only on rename, which this page does not show | `query.ex:365-373`; `invocation.ex:403-416`; `show.ex:97-104` | "Updated" earlier than "Wiped", or an "Updated" time with no visible change | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `active_menu_item: :dataclip` matches no menu item, so nothing is marked current in the side menu (already recorded in shared-project-header 6.2) | `show.ex:16`; `menu.ex:44-87` | decide |
| The breadcrumb has no link back to History or the run; only the project picker and "Dataclip <short id>" | `show.ex:50-64` | decide |
| The dataclip's name is not shown, though named dataclips are exactly the ones retention never wipes | `show.ex:76-115`; `dataclip.ex:58`; `query.ex:368` | decide |
| The type pill shows the raw type value ("step_result", "http_request"); an unknown type gets no colour | `common.ex:614-639` | decide |
| Headings use title case: "Dataclip Details", "No Data Available" | `show.ex:73`, `:131-133` | decide |
| Body keys appear in Postgres `jsonb` order, not the order the source sent them | `query.ex:346-363` (`jsonb` cast to text) | preserve |
| `saved_input`, `global` and `kafka` bodies are not scrubbed; a `kafka` body is wrapped with its `request` like a webhook, but the request is never scrubbed | `dataclip_controller.ex:62-70`; `query.ex:353`; `dataclip_scrubber.ex:43-44`; `dataclip_controller_test.exs:302-317` | decide |
| The viewer is a fixed `h-96` box; long bodies scroll inside it | `show.ex:121` | preserve |
| While the body is loading the viewer is an empty editor with no loading text; the Monaco "Loading..." shows only while the editor itself loads | `DataclipViewer.tsx:33`; `CodeViewer.tsx:83` | decide |
| A 403 from the body endpoint (access lost, or the project scheduled for deletion, after the page mounted) reads "Failed to load content" with no reason | `DataclipViewer.tsx:18-23`, `:51-52`; `dataclip_controller.ex:26-29` | decide |
| An existence check followed by `get_dataclip!`; a dataclip deleted between the two crashes the page instead of redirecting | `show.ex:23-28`; `invocation.ex:217` | preserve |
| A body of `null` (stored body nil but not wiped) is shown as the text `null` | `dataclip_controller.ex:77`; `dataclip_controller_test.exs:290-300` | preserve |
| The route keeps a trailing `/show` segment, unlike `/runs/:id` | `router.ex:297`, `:299` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `form_component.html.heex` (disabled type select, body textarea, "Back" link to `project_run_index_path`) | `lib/lightning_web/live/dataclip_live/form_component.html.heex:1-41` | no `DataclipLive.FormComponent` module exists and nothing embeds the template; it is never compiled or rendered |
| "Dataclip not found" message in the viewer | `DataclipViewer.tsx:14-16`, `:48-50` | the page has already checked the dataclip exists; reachable only if it is deleted between mount and the body fetch |
| Commented-out `Viewers.dataclip_viewer` in the dev components page | `live/dev/components_live.ex:48` | commented out |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Body responses are cached privately for a day (`max-age=86400`, `Vary: Accept-Encoding, Cookie`) and answer `If-Modified-Since` with 304 against `updated_at` to the second | `dataclip_controller.ex:14`, `:33-45`, `:72-101`; `dataclip_controller_test.exs:180-239` | no | preserve |
| The whole body is sent and loaded into the editor; there is no size cap or truncation | `dataclip_controller.ex:57-78`; `DataclipViewer.tsx:25` | yes, very large dataclips are slow to open | decide |
| The body is selected as text in Postgres to avoid decoding it into an Elixir map | `invocation.ex:128-143` | no | preserve |

### 6.5 Things seen but not understood

- `dataclip_controller_test.exs:255-261` describes `Policies.Dataclips` as asking `Projects.member_of?` about a project built from an id; the policy now delegates to `:access_project` (`policies/dataclips.ex:5-9`, `:20-22`). The comment is out of date, the assertion still holds.
- `viewers.ex:201` declares `attr :dataclipId, :map`, but the value is a string id. It does not seem to matter at runtime.
- Whether the browser cache in 6.4 can serve a body after it is wiped: the wipe does not bump `updated_at` (6.1), so a revalidation would answer 304. This page never fetches a wiped body (`show.ex:122`), but run-show and the editor do. Needs an old-app run.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the page show the dataclip's name, and should it link back to where it came from (6.2)?
- Should `saved_input` and `kafka` request bodies be scrubbed like webhook requests (6.2)?
- Should large bodies be capped or paged (6.4)?
- Should "Updated" reflect the wipe (6.1)?

## Proposed flows

none

Referenced, existing: `flow-zero-persistence-runs` (S10). dataclip-show is not yet in its `surfaces`; the lead should add it (after run-show) or drop S10 to a related note.

## Proposed shared

- **shared-dataclip-body-viewer**: the `DataclipViewer` React component and `CodeViewer` (read-only Monaco, two-space JSON formatting, copy button, "Dataclip not found" and "Failed to load content" states) and the `get /dataclip/body/:id` endpoint behind it (`Policies.Dataclips :view_dataclip`, `http_request` wrapping, credential and webhook auth scrubbing, private one-day caching with 304). S03 to S06 here and the 6.1 rounding bug would move to it. Surfaces: dataclip-show (`show.ex:139-144`), run-show input and output tabs (`viewers.ex:284-288`), workflow-editor-run-viewer (`/dataclip/body/:id`).

## Lead resolution (batch 4)

- `shared-dataclip-body-viewer` created. dataclip-show added to flow-zero-persistence-runs surfaces, so S10 stands.
