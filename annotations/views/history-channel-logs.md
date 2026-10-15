---
id: history-channel-logs
type: view
title: History › Channel logs
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/history/channels
  new_route: /projects/:project_id/history/channels
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; index.ex:67)
    - live_action is :channel_logs (router.ex:295); the same LiveView serves /history as history-work-orders
    - the tab bar that links here renders only with experimental features on (index.ex:142-143, index.html.heex:22-38); the route itself has no experimental check (see 6.1)

inherits:
  - shared-authenticated-session    # live_session :default with InitAssigns (router.ex:288)
  - shared-project-scope            # index.ex:67
  - shared-usage-limits-banner      # index.ex:68, index.html.heex:2-8 (the banner slot renders on both tabs)
  - shared-project-header           # index.html.heex:10-21, side menu marked History (index.ex:144)
  - shared-run-components           # channel_state_pill (components.ex:140-160) in the Status column (channel_logs_component.ex:179)
  - shared-local-datetime
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: filters[channel_id]
    set_by: history-channel-logs (channel dropdown and row channel-name link, channel_logs_component.ex:82-120, :166-173), channels-index (request count and last activity links, channel_live/index.ex:367, :377)
    effect: lists only that channel's requests and shows "Channel is <name>" on the chip; a non-UUID is silently ignored and every request is listed (search_params.ex:23-39, channels.ex:120-124)
  - name: page
    set_by: pagination bar (pagination.ex:159-213, channel_logs_component.ex:215-226)
    effect: Scrivener page of 10; the filter is carried on page links
  - name: page_size
    set_by: none
    effect: ignored; only "page" is passed to the query (channel_logs_component.ex:25)

config_variants:
  default: {}                                                                        # read under this one too; the list renders without the flag (6.1)
  experimental-features: { user.preferences.experimental_features: true }            # accounts.ex:1446-1448; verified against this

inventory:
  routes:
    - live /projects/:project_id/history/channels  RunLive.Index :channel_logs
  events:
    - ChannelLogsComponent#apply_filters
    - RunLive.Index handle_params (live_action :channel_logs clause, index.ex:172-179)
    - RunLive.Index handle_info {:channel_logs_filter, filters} (index.ex:350-357)
    - RunLive.Index handle_info Events.RunCreated, RunUpdated, WorkOrderCreated, WorkOrderUpdated (live_action :channel_logs ignore clause, index.ex:359-368)
  js_hooks:
    - LocalTimeConverter            # Common.datetime in the Started at column (common.ex:455, :478)
    - Copy                          # click-to-copy timestamp inside Common.datetime (common.ex:466, :489)
    - Tooltip                       # Common.wrapper_tooltip around the timestamp (common.ex:382)
  policies: []                      # none checked on this tab; mount computes :run_workflow and :edit_data_retention for the work orders tab only (index.ex:88-102)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features (index.ex:142-143)
  not_reachable_here:
    - every RunLive.Index handle_event clause (rerun, bulk-rerun, toggle_selection, toggle_all_selections, apply_filters, sort, bulk-cancel, cancel, cancel-run, show-export-modal, close-export-modal, confirm-export), owned by history-work-orders; their controls render only when live_action is :index (index.html.heex:47)
    - RunLive.Index handle_async :load_workorders (index.ex:226-247), started only by the :index handle_params clause
    - RunLive.Components.state_pill/1, step_icon/1, elapsed_indicator/1 and CancelHelper, owned by shared-run-components and not rendered here
    - LightningWeb.Pagination async_page and help_text branches (pagination.ex:108-118); this table passes neither

related:
  - history-work-orders
  - channel-request-show
  - channels-index
flows:
  - flow-zero-persistence-channel-requests
  - flow-channel-proxy-request   # added by lead (link lint)
---

## 1. Purpose

People running a Channel (a proxy that forwards a client system's HTTP requests to a destination
API) use this tab to see every request that passed through it: when it started, which path it hit,
and whether the destination answered, refused, timed out or errored. Without it, a client
reporting "my request didn't arrive" could only be answered from server logs, and a failing
destination would go unnoticed until someone complained.

## 2. What it does

- **See requests**
  - Members see the project's channel requests, newest first, ten per page, with each one's ID, path, channel, start time, status and error message
  - Members never see requests from another project's channels
  - Members see a placeholder where the project keeps no request data
- **Narrow to one channel**
  - Members filter by channel from a dropdown or by clicking a channel name in a row, and clear the filter from the chip
  - Members arriving from the channels page see that channel's requests
  - Members page through requests without losing the channel filter
- Members open a request's detail page from its ID
- Members with experimental features move between the work orders and channel logs tabs

**Straightforwardness: 4 of 5.** A plain filtered list; the surprises are about when it hides things or quietly shows the wrong state.

### Most surprising behaviours

- **(3)** Anyone with the link can open this list without experimental features, but every request link then sends them back to the work orders tab, which looks broken. (6.1)
- **(3)** A request that failed before reaching the destination shows "—" for its path, the same placeholder used when a project keeps no data, even though the path was recorded. (6.1)
- **(3)** A link to a channel that isn't in this project shows an empty list while the chip says "Channel is any", so it looks like nothing has ever come through. (6.1)
- **(4)** The list doesn't update by itself. New requests and changes in status only appear when you reload, change the filter or page. (6.2)

## 3. Who can do what

Source: the project scope gate only (`lib/lightning/policies/project_users.ex:136`, `:193`, via
shared-project-scope). This tab checks no policy of its own.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the tab and its requests | yes | yes | yes | yes | no | yes, when support access is on |
| Filter by channel and paginate | yes | yes | yes | yes | no | yes, when support access is on |
| Follow a row to the request detail page | yes | yes | yes | yes | no | yes, when support access is on |
| See the tab bar linking here | yes, with experimental features | yes, with experimental features | yes, with experimental features | yes, with experimental features | no | yes, with experimental features |

**Preconditions beyond role**
- The tab bar needs the viewer's own `experimental_features` preference (`index.ex:142-143`, `index.html.heex:22-38`).
- The request detail page the rows link to also needs that preference; without it the viewer is sent back to `/history` (`channel_request_live/show.ex:23`, `:45-46`).
- Only requests on channels whose `project_id` is the current project are listed (`channels.ex:110-115`).

## 4. What it touches

**Reads**: `channel_requests` joined to `channels` on `project_id`, with `channel_events` of type `destination_response` and `error` preloaded (`channels.ex:99-118`); `channels` for the dropdown (`channels.ex:28-34`). Mount also reads `workflows` and the viewer's project role for the other tab (`index.ex:84-102`).

**Writes**: none

**Immediate side effects**
- Subscribes to the project's work order PubSub topic on mount; every event is dropped on this tab (`index.ex:82`, `:359-368`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `user.preferences.experimental_features` shows the tab bar (`index.ex:142-143`)
- The project's retention policy decides at proxy time whether the request path is stored (`persistence_policy.ex:12-16`, `:21`, `:35-37`); this tab only renders the result

**Product limits**
- Ten requests per page; the page size cannot be changed from the URL (`repo.ex:6`, `channel_logs_component.ex:25`)

## 5. Scenarios

```gherkin
Feature: Channel logs
  In order to see what happened to requests sent through my project's channels
  As a project member
  I want a filterable, paged list of channel requests with their outcome

  @S01 @pending @variant:experimental-features
  Scenario: Members see the project's channel requests, newest first
    # Value: the most recent traffic, which is what someone debugging a live integration needs, is at the top.
    Given I have experimental features enabled
    And channel "test-channel" in my project received a request on 1 January and another on 2 January
    When I open the channel logs tab
    Then I see both requests
    And the 2 January request is listed first
    And each row shows the channel name "test-channel"
    # channel_logs_component.ex:20-40, :151-184; channels.ex:110-118
    # test/lightning_web/live/run_live/index_test.exs:628-653; test/lightning/channels/channel_requests_test.exs:130-146

  @S02 @pending @variant:experimental-features
  Scenario: A project with no channel requests says so
    # Value: an empty list reads as "nothing has arrived", not as a page that failed to load.
    Given I have experimental features enabled
    And no request has passed through any channel in my project
    When I open the channel logs tab
    Then I see "No channel requests found."
    # channel_logs_component.ex:140-149
    # test/lightning_web/live/run_live/index_test.exs:613-626

  @S03 @pending @variant:experimental-features
  Scenario: Requests from other projects are never listed
    # Value: one project's members never see another project's API traffic, which can name patients or systems.
    Given I have experimental features enabled
    And a channel in project "Kenya TB" has received a request
    And I am a member of "Malawi HIV" but not of "Kenya TB"
    When I open the "Malawi HIV" channel logs tab
    Then I do not see the "Kenya TB" request
    And when I open "Malawi HIV" channel logs with "filters[channel_id]" set to the "Kenya TB" channel's id
    Then I see no requests
    # channels.ex:110-116, :120-124
    # test/lightning/channels/channel_requests_test.exs:31-50 covers the unfiltered case; the foreign channel id case is untested

  @S04 @pending @variant:experimental-features
  Scenario: Each row shows the request's path, status and error message
    # Value: people can tell which endpoint failed and why without opening every request.
    Given I have experimental features enabled
    And request "A" reached the destination at path "/some/upstream/path" and succeeded
    And request "B" failed in the proxy with error message "connect timeout"
    When I open the channel logs tab
    Then row "A" shows path "/some/upstream/path" and status "Success"
    And row "B" shows error message "connect timeout" and status "Error"
    # channel_logs_component.ex:162-164, :181-183, :200-213; channels.ex:104-108
    # test/lightning_web/live/run_live/index_test.exs:723-763 asserts the path cell; channel_requests_test.exs:99-128 asserts both event types are preloaded

  @S05 @pending @variant:experimental-features
  Scenario Outline: Request states show as labelled pills
    # Value: people can tell a destination that refused a request from one that never answered or a proxy fault.
    Given I have experimental features enabled
    And a channel request in state <state>
    When I open the channel logs tab
    Then its status reads <label>
    Examples:
      | state   | label       |
      | pending | In progress |
      | success | Success     |
      | failed  | Failed      |
      | timeout | Timeout     |
      | error   | Error       |
    # components.ex:145-159; states from handler.ex:175-183 (4xx and 5xx are "failed", a timeout is "timeout", other proxy errors are "error")

  @S06 @pending @variant:experimental-features
  Scenario: Filter by channel from the dropdown
    # Value: on a project with several channels, people isolate the one a client is complaining about.
    Given I have experimental features enabled
    And channels "channel-one" and "channel-two" each have a request
    When I open the channel logs tab
    And I open the "Channel is any" chip and choose "channel-one"
    Then the URL carries "filters[channel_id]=<channel-one id>"
    And I see only "channel-one"'s request
    And the chip reads "Channel is channel-one"
    # channel_logs_component.ex:54-71, :100-121, :193-198; index.ex:350-357
    # test/lightning_web/live/run_live/index_test.exs:655-697 covers only loading the filtered URL

  @S07 @pending @variant:experimental-features
  Scenario: Clearing the channel filter lists every channel again
    # Value: people get back to the whole picture in one click.
    Given I have experimental features enabled
    And I am viewing channel logs filtered to "channel-one"
    When I click "Clear filter" on the channel chip
    Then I see requests from every channel in the project
    And the chip reads "Channel is any"
    And choosing "All channels" from the dropdown does the same
    # pills.ex:119-176 (clear button pushes channel_id ""), channel_logs_component.ex:80-99, :193-198

  @S08 @pending @variant:experimental-features
  Scenario: The dropdown lists the project's channels by name
    # Value: people find a channel by name among many without scrolling an arbitrary order.
    Given I have experimental features enabled
    And my project has channels "bravo" and "alpha"
    When I open the channel chip's dropdown
    Then I see "All channels", "alpha", "bravo" in that order
    And no channel from another project
    # channel_logs_component.ex:32-34, :79-121; channels.ex:28-34
    # test/lightning/channels_test.exs:12-27

  @S09 @pending @variant:experimental-features
  Scenario: Clicking a row's channel name filters to that channel
    # Value: from one suspicious request, people see the rest of that channel's traffic in one click.
    Given I have experimental features enabled
    And requests from "channel-one" and "channel-two" are listed
    When I click "channel-one" in a row
    Then I see only "channel-one"'s requests
    # channel_logs_component.ex:165-173

  @S10 @pending @variant:experimental-features
  Scenario: Arriving from the channels page shows that channel's requests
    # Value: the request count on the channels page leads straight to the requests it counted.
    Given I have experimental features enabled
    When I follow a link to channel logs with "filters[channel_id]" set to "channel-one"
    Then I see only "channel-one"'s requests and the chip reads "Channel is channel-one"
    # channel_live/index.ex:367, :377; channel_logs_component.ex:20-40
    # test/lightning_web/live/run_live/index_test.exs:655-697

  @S11 @pending @variant:experimental-features
  Scenario: Paging keeps the channel filter
    # Value: people reading through a busy channel's history don't silently drift into other channels' requests.
    Given I have experimental features enabled
    And "channel-one" has 15 requests and "channel-two" has 5
    And I am viewing channel logs filtered to "channel-one"
    Then I see "Showing 1 to 10 of 15 total results"
    When I go to page 2
    Then I see the remaining 5 "channel-one" requests and no "channel-two" request
    # channel_logs_component.ex:25-28, :39, :215-226; pagination.ex:120-131, :159-213; repo.ex:6

  @S12 @pending @variant:experimental-features
  Scenario: Changing the channel filter returns to page 1
    # Value: a new filter never lands on an empty page past the end of a shorter list.
    Given I have experimental features enabled
    And I am on page 2 of all channel requests
    When I choose a channel from the dropdown
    Then I am on page 1 of that channel's requests
    # index.ex:350-357 (the patch carries only filters)

  @S13 @pending @variant:experimental-features
  Scenario: A request's ID opens its detail page
    # Value: people go from the list to the full request and response for the one that failed.
    Given I have experimental features enabled
    And request "A" is listed
    Then its ID cell shows the first 8 characters of its request ID, with the full ID on hover
    And it links to "/projects/<project_id>/history/channels/<A's id>"
    # channel_logs_component.ex:153-161; live_helpers.ex:169-171; detail page owned by channel-request-show

  @S14 @pending @variant:experimental-features
  Scenario: A request whose path was not kept shows a placeholder
    # Value: people can tell "this project does not keep request data" apart from a broken row.
    Given I have experimental features enabled
    And my project keeps no input or output data
    And a request has passed through one of its channels
    When I open the channel logs tab
    Then its path cell reads "—"
    And the flow "flow-zero-persistence-channel-requests" ends on this tab
    # channel_logs_component.ex:163; persistence_policy.ex:12-16, :35-37
    # test/lightning_web/live/run_live/index_test.exs:765-810

  @S15 @pending @variant:experimental-features
  Scenario: Members move between work orders and channel logs
    # Value: people investigating an incident switch between workflow runs and proxied requests without leaving History.
    Given I have experimental features enabled
    When I open the channel logs tab
    Then the "Channel logs" tab is selected
    And the work orders filters and table are not shown
    When I click "Work orders"
    Then I am on "/projects/<project_id>/history"
    # index.html.heex:22-38, :47, :716-724
    # test/lightning_web/live/run_live/index_test.exs:596-611, :699-712; the tab bar's visibility is history-work-orders S41
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The route has no experimental-features check, unlike the request detail page | `router.ex:295`, `index.ex:172-179` vs `channel_request_live/show.ex:23`, `:45-46` | a user without the flag who has the URL sees the full list with no tab bar, and every row's ID link bounces them back to `/history` | decide |
| The Request path column reads the path only from a `destination_response` event, though `error` events store it too | `channel_logs_component.ex:200-201`; `handler.ex:117`, `:186` | errored requests show "—" for a path the system knows | fix |
| A `channel_id` that is a valid UUID but not one of this project's channels filters to nothing while the chip reads "Channel is any" | `channel_logs_component.ex:54-57`, `channels.ex:120-124` | an empty list with a chip saying no filter is applied | fix |
| `channel_state_pill` raises on a state missing from its map | `components.ex:154`; listed in shared-run-components 6.1 | the tab crashes | decide (owned by shared-run-components) |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The list does not update live; new requests and state changes appear only on reload, filter change or paging | `channel_logs_component.ex:14-44`; no subscription to channel events | decide |
| The channel dropdown is loaded once per component lifetime (`assign_new`), so a channel added or renamed in another tab is missing until the tab is reopened | `channel_logs_component.ex:32-34` | decide |
| A row's channel-name link uses `navigate` to the same LiveView (full remount) where the dropdown uses a patch | `channel_logs_component.ex:166-170` vs `index.ex:353-356` | preserve |
| Choosing "All channels" pushes `channel_id: nil`, which survives the `""` filter and leaves `filters[channel_id]=` in the URL; the chip's clear button pushes `""` and leaves no filter | `channel_logs_component.ex:85`, `:195`; `pills.ex:162-167` | preserve |
| An empty result shows both "No channel requests found." in the table and "No results found" in the pagination bar | `channel_logs_component.ex:143-147`, `pagination.ex:110-111` | decide |
| Old copy is title case ("Channel Logs", "Work Orders", "All Channels", "Request Path", "Channel Name", "Started At", "Error Message", "In Progress"); scenarios here use sentence case | `index.html.heex:30`, `:36`; `channel_logs_component.ex:98`, `:131-136`; `components.ex:147` | decide |
| The breadcrumb reads "History" only, while the detail page's breadcrumb names this tab "Channels" | `index.ex:178`, `channel_request_live/show.ex:63-64` | decide |
| `display_short_uuid` truncates the request ID, which comes from the `x-request-id` response header and is not a UUID | `channel_logs_component.ex:159`; `channel_proxy_plug.ex:158-159` | preserve |
| Started at uses `Common.datetime` in relative format with a UTC tooltip and click-to-copy | `channel_logs_component.ex:176`; `common.ex:399-470` | preserve |
| Sort is `started_at` desc with no tie-breaker | `channels.ex:113` | preserve |
| Switching project from the picker on this tab lands on `/history` (work orders), dropping the channel filter | `layout_components.ex:544-563` | decide |
| The old `/projects/:id/channels/requests` route raises `FunctionClauseError` rather than redirecting | `test/lightning_web/live/run_live/index_test.exs:714-721` | decide |
| Error message cell is truncated to one line with no tooltip | `channel_logs_component.ex:181-183` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `current_user` passed to the component | `index.html.heex:721` | the component never reads it |
| `SearchParams.changeset/1` validation errors on `filters_changeset` | `channel_logs_component.ex:37`, `search_params.ex:23-27` | nothing renders the errors; the chip only reads `get_change` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Page size fixed at 10; `page_size` in the URL is dropped | `channel_logs_component.ex:25`, `repo.ex:6` | yes | preserve |
| Mount on this tab still loads workflows, evaluates two policies, reads the work order count limit and subscribes to work order events that are then dropped | `index.ex:82-102`, `:141`, `:359-368` | no | decide |
| The events preload fetches every `destination_response` and `error` event for each listed request, though only the first of each is shown | `channels.ex:104-108`, `channel_logs_component.ex:206-212` | no | preserve |
| Every filter change re-queries the page and the total count (Scrivener) | `channel_logs_component.ex:27-28` | no | preserve |

### 6.5 Things seen but not understood

- `update/2` re-queries only when `params` changes or the page is unset (`channel_logs_component.ex:16-20`); it was not checked whether a patch to identical params (re-choosing the current channel) is expected to refresh the list.
- The `request_id` comes from the proxy's own `x-request-id` header (`channel_proxy_plug.ex:158-159`); whether two requests can share one (the column is unique, `channel_request.ex:73`) was not checked.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should this tab require experimental features, as the detail page does? (6.1)
- Should channel logs update live, as work orders do? (6.2)
- S05 (channel state pill labels) is the only scenario for `channel_state_pill`, which channel-request-show also renders; should it move to shared-run-components?

## Proposed flows

- **flow-zero-persistence-channel-requests** (already proposed by flow-zero-persistence-runs; referenced here, not created): when the project keeps no data, the proxy drops request paths, headers and bodies before insert and marks the request wiped; this tab shows "—" in the path column and the detail page shows the wiped state. Surfaces: project-settings-data-storage, controller:channel-proxy-plug (`channel_proxy_plug.ex`, `handler.ex:72-75`, `:143-147`), history-channel-logs, channel-request-show.

## Proposed shared

- **shared-local-datetime** (already proposed by project-settings-history-exports; referenced here, not created): the `Common.datetime` component (relative time, UTC tooltip, click-to-copy via the LocalTimeConverter, Copy and Tooltip hooks; `common.ex:399-470`), used here in the Started at column (`channel_logs_component.ex:176`). Surfaces: history-channel-logs, project-settings-history-exports and other views rendering timestamps.

## Lead resolution (batch 3)

- `flow-zero-persistence-channel-requests` and `shared-local-datetime` created.
