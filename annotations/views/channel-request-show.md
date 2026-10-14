---
id: channel-request-show
type: view
title: History › Channel logs › Channel request
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/history/channels/:id
  new_route: /projects/:project_id/history/channels/:id
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; show.ex:16)
    - the viewing user has experimental features on, otherwise the page redirects to History (show.ex:23, :45-46; accounts.ex:1446-1448)
    - the id is a UUID of a channel request whose channel belongs to this project, otherwise the page redirects to History (show.ex:24-26; channels.ex:561-581)

inherits:
  - shared-authenticated-session    # live_session :default with InitAssigns (router.ex:288)
  - shared-project-scope            # show.ex:16
  - shared-project-header           # show.ex:55-76 (project picker plus "History" and "Channels" breadcrumbs); side menu marked History via active_menu_item :runs (show.ex:31)
  - shared-run-components           # channel_state_pill (run_live/components.ex:140-160) via state_pill_with_tooltip (components.ex:182-195, :189, :192)
  - shared-local-datetime
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: project_id
    set_by: every project link
    effect: owned by shared-project-scope
  - name: id
    set_by: history-channel-logs (row link on the request id, channel_logs_component.ex:154-160)
    effect: the channel request to show (the database id, not the proxy's request_id); another project's request or a non-UUID redirects to History (S19)

config_variants:
  default: {}                                                                  # experimental features off; the page redirects (S20)
  experimental-features: { user.preferences.experimental_features: true }      # accounts.ex:1446-1448; every other scenario read and verified under this one

inventory:
  routes:
    - live /projects/:project_id/history/channels/:id  ChannelRequestLive.Show :show   # router.ex:296
  events: []                        # no handle_event, handle_info or handle_params; mount only (show.ex:19-48)
  js_hooks:
    - Copy                          # copy_icon_button for request id, body and hash (components.ex:344-359); also Common.datetime click-to-copy (common.ex:466, :489)
    - Tooltip                       # timeout pill tooltip via Common.wrapper_tooltip (components.ex:185-190, common.ex:382); admin contacts in the wiped viewer (viewers.ex:352-357)
    - LocalTimeConverter            # Common.datetime for Started and Completed (show.ex:228, :236; common.ex:455, :478)
    - "JS.toggle disclosure sections (inline phx-click, components.ex:30-33, :69-72)"
  policies:
    - Lightning.Policies.ProjectUsers :edit_data_retention   # show.ex:36-42
    - Lightning.Policies.ProjectUsers :access_project        # via shared-project-scope
  workers: []
  api_endpoints: []
  emails: []
  config:
    - user.preferences.experimental_features (show.ex:23)
  not_reachable_here:
    - RunLive.Components state_pill, step_icon, elapsed_indicator, CancelHelper and the rest of shared-run-components; only channel_state_pill is imported (components.ex:12)
    - Viewers.wiped_data_viewer :input and :output branches (viewers.ex:341-349, :385-386); this page passes :request_response only (show.ex:97)
    - Helpers.format_content_type_label/1 nil clause (helpers.ex:194); body_viewer only calls it with a content type present (components.ex:270-273, :294-297)

related:
  - history-channel-logs
  - channels-index
  - project-settings-data-storage
flows:
  - flow-zero-persistence-channel-requests
  - flow-channel-proxy-request
---

## 1. Purpose

People running a Channel (a proxy that forwards a client system's HTTP requests to a destination
API) open this page from the channel logs to find out what happened to one request: what the
client sent, what the destination answered, how long each phase took, which credentials were used
and whether the channel's config has changed since. Without it, a failed or slow request could
only be diagnosed from server logs, and nobody could tell a destination outage from a broken
credential or a client sending the wrong payload.

## 2. What it does

- Anyone on the project sees a request's method, path, query, status code, state and channel
- Anyone sees the request and response headers, with secrets redacted
- Anyone sees the request and response bodies, or why a body isn't shown
- Anyone sees why a request failed when the destination never answered or the request was never sent
- Anyone sees how long the request took, broken into phases when the data exists
- Anyone sees which client auth method and destination credential the request used, even after they are deleted
- Anyone sees the channel config the request ran on and whether it has changed since
- Anyone sees that a request's data was not kept; admins get a link to the retention setting, others whom to ask
- Anyone copies the request id, a body or a body hash
- Anyone goes back to the channel logs, or on to the channel's settings
- Nobody sees another project's channel requests
- Users without experimental features are sent to History

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_data_retention` is an admin
action), `:132-136`, `:166-178`, `:193-194`. The page checks no other policy.

| Action | Viewer | Editor | Admin | Owner | Superuser | Support |
|--------|--------|--------|-------|-------|-----------|---------|
| See the page | yes | yes | yes | yes | no | yes, when support access is on |
| Copy request id, bodies and hashes | yes | yes | yes | yes | no | yes, when support access is on |
| Get the "this policy" retention link on a wiped request | no | no | yes | yes | no | no |
| See the admin contacts tooltip on a wiped request | yes | yes | no | no | no | yes, when support access is on |

**Preconditions beyond role**
- The viewing user must have experimental features on (`show.ex:23`, `:45-46`).
- The request's channel must belong to the current project (`channels.ex:564-567`).
- The id must be a valid UUID (`channels.ex:562`, `:578-579`).
- Project MFA requirement and membership gates are owned by shared-project-scope.

## 4. What it touches

**Reads**: `channel_requests` joined to `channels` on `project_id`, with `channel_events`, `channels`, `channel_snapshots`, `webhook_auth_methods`, `project_credentials` and `credentials` preloaded (`channels.ex:561-581`); `project_users` joined to `users` for admin and owner emails (`projects.ex:541-548`); `users.preferences` (`accounts.ex:1446-1448`)

**Writes**: none

**Immediate side effects**
- none

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `user.preferences.experimental_features` (`show.ex:23`)

**Product limits**
- Body previews scroll inside a box capped at `max-h-80` (`components.ex:307`); the preview size itself is set by the proxy, not here (see 6.5)

## 5. Scenarios

```gherkin
Feature: Channel request detail
  In order to diagnose one request that passed through a channel
  As anyone working in a project
  I want to see what was sent, what came back, how long it took and with which credentials

  @S01 @pending @variant:experimental-features
  Scenario: A successful request shows its summary
    # Value: people confirm at a glance what was called and how the destination answered.
    Given a channel "orders-proxy" in my project
    And a successful request "POST /api/v1/data?format=json" that got status 200 after 350 ms
    When I open the request
    Then I see "POST", "/api/v1/data", "?format=json" and "200"
    And the state pill reads "Success" (labels owned by shared-run-components channel_state_pill)
    And I see "orders-proxy", the client IP, the destination URL, the start and completed times and "350 ms"
    # show.ex:85-90, :122-254; components.ex:98-158, :182-195; helpers.ex:91-95, :153-161
    # test/lightning_web/live/channel_request_live/show_test.exs:67-98

  @S02 @pending @variant:experimental-features
  Scenario: Secret headers are shown redacted
    # Value: anyone on the project can debug headers without seeing API keys or tokens.
    Given a request whose "authorization" header was stored as "[REDACTED]"
    When I open the request
    Then the request headers list "authorization" with the value "[REDACTED]" shown in italics
    And other headers such as "content-type" show their values
    # components.ex:225-246; redaction happens at the proxy (handler.ex:50, :189-197)
    # test/lightning_web/live/channel_request_live/show_test.exs:100-103

  @S03 @pending @variant:experimental-features
  Scenario: Text bodies are shown with their type, size and hash
    # Value: people see exactly what payload went out and came back, and can prove it with the hash.
    Given a request with a JSON request body and a JSON response body
    When I open the request
    Then each body shows its text, a "JSON" label, its size, a copy button and the first 16 characters of its SHA256 hash
    # components.ex:248-336 (true branch :289-333); show.ex:258-311, :315-380; helpers.ex:165-194
    # test/lightning_web/live/channel_request_live/show_test.exs:105-109

  @S04 @pending @variant:experimental-features
  Scenario: A truncated body says it is a preview
    # Value: people don't mistake a cut-off preview for the whole payload.
    Given a response body of 10 KB of which a 2 KB preview was stored
    When I open the request
    Then below the body I see "Preview: 2.0 KB of 10.0 KB"
    # components.ex:323-332; helpers.ex:142-151

  @S05 @pending @variant:experimental-features
  Scenario: Binary bodies show metadata only
    # Value: people can confirm a file or image passed through without the page dumping unreadable bytes.
    Given a response with content type "application/octet-stream", size 4096 bytes and hash "binaryhash123"
    When I open the request
    Then the response body shows "application/octet-stream", "4.0 KB" and "SHA256: binaryhash123"
    And no body text is shown
    # components.ex:249-250, :270-281; helpers.ex:176-182
    # test/lightning_web/live/channel_request_live/show_test.exs:431-453

  @S06 @pending @variant:experimental-features
  Scenario: A body that was sized but not stored says so
    # Value: people know a body existed even though its content wasn't kept, rather than thinking it was empty.
    Given a request body of 2048 bytes with no preview stored
    When I open the request
    Then the request body reads "Body not captured (2.0 KB)"
    And an empty body with size 0 reads "No body"
    # components.ex:252-269, :282-288; show.ex:261-264
    # test/lightning_web/live/channel_request_live/show_test.exs:392-409 (Body not captured), :411-429 (section hidden when preview and size are both missing)

  @S07 @pending @variant:experimental-features
  Scenario: A transport error explains why there was no response
    # Value: people can tell a destination that is down or unreachable from one that answered with an error.
    Given a request in state "error" whose error is "econnrefused"
    When I open the request
    Then the response section reads "No response received"
    And it explains "Connection refused" in plain words and shows the code "econnrefused"
    And the timing section shows a single "Total" bar
    # show.ex:82-83, :343-348; components.ex:197-221; helpers.ex:12-29, :47-63, :69-83
    # test/lightning_web/live/channel_request_live/show_test.exs:117-135, :320-334

  @S08 @pending @variant:experimental-features
  Scenario: A credential error says the request was never sent
    # Value: people fix the destination credential instead of chasing the destination server.
    Given a request in state "error" whose error is "credential_missing_auth_fields"
    When I open the request
    Then the response section reads "Request not sent — credential error"
    And it says the configured credential "is missing required authentication fields" and shows the code
    And there is no timing section
    # show.ex:92, :343-348; components.ex:203-204; helpers.ex:31-40, :52-56, :74-79
    # test/lightning_web/live/channel_request_live/show_test.exs:137-154, :336-347

  @S09 @pending @variant:experimental-features
  Scenario: A timed-out request explains the timeout on its state pill
    # Value: people can tell a slow destination from one that never accepted the connection.
    Given a request in state "timeout" whose error is "response_timeout"
    When I hover its "Timeout" state pill
    Then the tooltip says the destination "accepted the connection but did not send a response in time"
    # components.ex:182-195; helpers.ex:26-27, :47-63

  @S10 @pending @variant:experimental-features
  Scenario: Timing is broken into phases when the proxy recorded them
    # Value: people can see whether time went to queueing, connecting, the destination's processing or the download.
    Given a request with queue 2 ms, connect 15 ms, send 5 ms, time to first byte 180 ms, receive 65 ms and total 260 ms
    When I open the request
    Then the timing bar has segments titled "Queue: 2 ms", "Connect: 15 ms", "Send: 5 ms", "Processing: 158 ms" and "Recv: 65 ms"
    And it reads "0 ms" to "260 ms" with a "TTFB: 180 ms" marker
    And the legend includes "Proxy overhead"
    # timing.ex:18-40, :53-164, :179-220, :224-302
    # test/lightning_web/live/channel_request_live/show_test.exs:161-194, :216-233; marker position :275-318

  @S11 @pending @variant:experimental-features
  Scenario: A reused connection is marked instead of showing a connect time
    # Value: people don't read a zero connect time as a missing measurement.
    Given a request that reused an open connection to the destination
    When I open the request
    Then the timing bar shows a "Connect" segment badged "(reused)"
    # timing.ex:260-262, :272, :368-379
    # test/lightning_web/live/channel_request_live/show_test.exs:196-214

  @S12 @pending @variant:experimental-features
  Scenario: Timing degrades when fewer measurements exist
    # Value: older or partial records still show how long the request took, without inventing phases.
    Given a request with only time to first byte 280 ms and total 350 ms
    When I open the request
    Then the timing bar has "TTFB: 280 ms" and "Download: 70 ms" segments and no "Proxy overhead"
    And a request with only a total of 420 ms shows a single "Total: 420 ms" segment
    # timing.ex:224-238, :304-350
    # test/lightning_web/live/channel_request_live/show_test.exs:236-273

  @S13 @pending @variant:experimental-features
  Scenario: The request shows which client key and destination credential it used
    # Value: when a key leaks or a credential breaks, people can tell which requests it affected.
    Given client auth method "Prod API key" of type API key matched the request
    And the channel sent it with destination credential "Destination API"
    When I open the request
    Then client auth reads "Prod API key (API key)"
    And destination auth reads "Destination API"
    And a request with no client auth configured reads "None"
    And the flow "flow-channel-proxy-request" is what recorded the matched method
    # show.ex:176-186, :203-214; helpers.ex:99-140
    # test/lightning_web/live/channel_request_live/show_test.exs:591-661

  @S14 @pending @variant:experimental-features
  Scenario: A deleted auth method or credential is labelled deleted
    # Value: request history stays readable after keys are rotated, and a deleted key isn't mistaken for no auth.
    Given a request whose client auth method has since been deleted
    And whose destination credential has since been deleted
    When I open the request
    Then client auth reads "(deleted) (API key)"
    And destination auth reads "(deleted)"
    # helpers.ex:112-124, :133-140
    # test/lightning_web/live/channel_request_live/show_test.exs:706-724 (helper only); :663-704 shows the database nilifies the id, so the page reads "None" (see 6.1)

  @S15 @pending @variant:experimental-features
  Scenario: Context shows the config the request ran on and flags later changes
    # Value: people know whether the channel has been changed since the request, so they don't debug the wrong config.
    Given a request made on channel config version 1
    And the channel has since been renamed, making it version 2
    When I open the request and expand "Context"
    Then I see the destination URL, channel name and config version 1 from that time
    And a "Config changed" badge
    # show.ex:109-113, :384-424; Context is collapsed by default (show.ex:391)
    # test/lightning_web/live/channel_request_live/show_test.exs:355-385 (its last assertion also passes without the badge, see 6.5)

  @S16 @pending @variant:experimental-features
  Scenario: Admin sees that request data was not kept and where to change that
    # Value: admins learn why data is missing and can change the policy for future requests.
    Given I am an admin and the project keeps no request or response data
    And a request was recorded as wiped by the flow "flow-zero-persistence-channel-requests"
    When I open the request
    Then instead of the request and response sections I see "No Request/Response Data here!"
    And "Request/Response data for this channel request has not been retained"
    And a "this policy" link to "/projects/<project_id>/settings#data-storage" "for future requests"
    And I do not see "rerun this work order"
    # show.ex:94-101; viewers.ex:309-339, :385-389
    # test/lightning_web/live/channel_request_live/show_test.exs:461-499

  @S17 @pending @variant:experimental-features
  Scenario: Non-admin on a wiped request is told whom to ask
    # Value: people who can't change retention know who can.
    Given I am an editor and "admin@example.com" is an admin on the project
    And a wiped request
    When I open the request
    Then I see "Contact one of your project admins for more information."
    And hovering "project admins" shows "admin@example.com"
    And there is no link to the data storage settings
    # show.ex:35-42, :99-100; viewers.ex:350-361; projects.ex:541-548
    # test/lightning_web/live/channel_request_live/show_test.exs:501-542

  @S18 @pending @variant:experimental-features
  Scenario: A request from another project cannot be opened
    # Value: one project's members never see another project's traffic, headers or payloads.
    Given a channel request belonging to another project
    When I open "/projects/<my project>/history/channels/<that request id>"
    Then I am redirected to "/projects/<my project>/history"
    And I am also redirected there for "/projects/<my project>/history/channels/not-a-uuid"
    # show.ex:24-26; channels.ex:561-581
    # test/lightning_web/live/channel_request_live/show_test.exs:568-584

  @S19 @pending @variant:default
  Scenario: Without experimental features the page is not available
    # Value: an unfinished feature stays hidden from users who haven't opted in.
    Given I have not enabled experimental features
    When I open a channel request in my project
    Then I am redirected to "/projects/<project_id>/history"
    # show.ex:23, :45-46
    # test/lightning_web/live/channel_request_live/show_test.exs:52-60

  @S20 @pending @variant:experimental-features
  Scenario: Breadcrumbs lead back to the channel logs and the channel name to its settings
    # Value: people move from one request back to the list, or on to fix the channel, without hunting.
    Given a request on channel "orders-proxy"
    When I open the request
    Then the breadcrumbs read "History", "Channels" and "Channel Request" with the request's short id
    And "Channels" links to "/projects/<project_id>/history/channels"
    And "orders-proxy" links to "/projects/<project_id>/channels/<channel_id>/edit"
    # show.ex:57-74, :137-144
    # test/lightning_web/live/channel_request_live/show_test.exs:731-741 (breadcrumb text only); arrival from the list :743-767

  @S21 @pending @variant:experimental-features
  Scenario: The request id, bodies and hashes can be copied
    # Value: people can paste the exact payload or id into a ticket or a replay without retyping.
    Given a request with a JSON response body
    When I click "Copy request ID", "Copy body" or "Copy hash"
    Then the full request id, the body preview or the full hash is copied to the clipboard
    # components.ex:151-156 (via show.ex), :299-305, :316-321, :344-359
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The summary's channel name and destination URL come from the channel's current config, while Context shows the snapshot the request ran on | `show.ex:137-144`, `:199-201` vs `:397-405` | after a config change, the summary shows a destination URL the request never went to; the right one is only in the collapsed Context section | fix |
| An error code the helpers don't know (the proxy falls back to `inspect(error)`) gets no category, so the error message renders nowhere unless the state is timeout | `handler.ex:218`; `show.ex:82-83`, `:343-377`; `components.ex:184` | a red "Error" pill and an empty Response section with no reason | fix |
| The page shows the database id; the channel logs list and the `x-request-id` header the proxy sends to the destination use `request_id`, which this page never shows | `show.ex:70`, `:149-155`; `channel_logs_component.ex:154-160`; `channel_proxy_plug.ex:158-159`, `:273` | the id clicked in the list is not on the detail page, and an id quoted from destination logs can't be matched here | fix |
| Text types not in the allow list (form-urlencoded, `application/yaml`, `text`-less vendor types) are treated as binary, hiding a stored UTF-8 preview | `helpers.ex:176-182`; `components.ex:249-250`, `:270-281` | a form post shows only type, size and hash though its body was captured | fix |
| Segment widths have a 0.5% and 20px minimum, so segments can sum past 100% and be clipped; the TTFB marker is placed on the unclamped scale and inside the padded bar | `timing.ex:63-77`, `:99`, `:108`, `:117`, `:135-140` | with tiny phases, "Recv" can be cut off and the marker no longer lines up with the end of "Processing" | fix |
| "(deleted)" can't appear through the database: deleting the credential nilifies the id, so the page reads "None", the same as never configured | `helpers.ex:112-124`, `:133-140`; `show_test.exs:663-704` | a request sent with a since-deleted credential looks like it was sent with no auth | decide |
| A request with no event yet (state pending) renders empty Request and Response cards with no explanation | `show.ex:282-308`, `:350-376`; `helpers.ex:91-95` | two blank cards under an "In Progress" pill | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| No PubSub subscription or refresh: a pending request never updates until reload | `show.ex:19-48` (no `handle_info`) | decide |
| Not-found and experimental-off both redirect to the work orders tab (`/history`), not the channel logs, with no flash | `show.ex:26`, `:46` | decide |
| Title-case labels: page title "Channel Request", breadcrumb "Channel Request", Context "Channel Name", "Config Version", "Destination URL" | `show.ex:32`, `:68`, `:395`, `:403`, `:409` | decide |
| "Config changed" sits inside Context, which is collapsed by default | `show.ex:391`, `:413-418` | decide |
| Primary event prefers `destination_response` over `error`; among several of one type the first in preload order wins, which is unordered | `helpers.ex:91-95`; `channels.ex:569` | preserve |
| Durations are microseconds shown as ms with no thousands separator ("30000 ms"), while segment labels switch to seconds at 1000 ms ("30.0s") | `helpers.ex:153-161`; `timing.ex:166-175` | decide |
| The text body hash is truncated to 16 characters; the binary body hash is shown in full | `components.ex:278-280`, `:313-315` | decide |
| A body with unknown size and an empty-string preview falls through to an empty `<pre>` with a copy button | `components.ex:252-254`, `:289-307` | decide |
| On a wiped request the summary still shows method, status and timing; the path is blank because the proxy dropped it | `show.ex:85-92`; `persistence_policy.ex:12-16` | preserve |
| Disclosure sections toggle client-side with `JS.toggle`; no server state | `components.ex:30-33`, `:69-72` | preserve |
| Admin and owner emails are loaded on every mount and exposed in the tooltip to any member, including viewers | `show.ex:35`; `viewers.ex:350-357` | decide |
| Status code colours use two near-duplicate components (`status_code_display` in the summary, `status_code_badge` on the Response header) | `components.ex:140-180` | preserve |
| The tooltip on the state pill renders only for state timeout with an error message; other error states rely on the Response section | `components.ex:184-193` | preserve |
| The timing bar background is a hatch when all Finch phases exist ("Proxy overhead") and plain grey otherwise, regardless of whether any overhead was measured | `timing.ex:80`, `:98-106`, `:204-211` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `overhead_left_pct` and `overhead_right_pct` and `compute_overhead/2` | `timing.ex:257-258`, `:297-298`, `:326-327`, `:346-347`, `:352-361` | computed for every tier and never read by the bar or the legend |
| `Helpers.format_content_type_label/1` nil clause | `helpers.ex:194` | both callers render it only when a content type is present |
| Viewers.wiped_data_viewer `:input` and `:output` branches | `viewers.ex:341-349` | this page passes `:request_response` only |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The request, its events and associations are queried twice per visit (dead render and connected mount), plus the admin email query each time | `show.ex:24`, `:35` | no | preserve |
| Body preview box capped at `max-h-80` with internal scroll | `components.ex:307` | yes | preserve |
| Every `channel_events` row for the request is preloaded, though only one is shown | `channels.ex:569`; `helpers.ex:91-95` | no | preserve |

### 6.5 Things seen but not understood

- The show test for "Config changed" ends with `assert html2 =~ "changed" or html2 =~ "Config"` (`show_test.exs:384`); "Config Version" always matches, so the badge itself is untested.
- The preview size limit the proxy applies to bodies was not traced; `handler.ex:120`, `:125` read it from `request_observation`/`response_observation`, which come from outside `lib/lightning/channels`.
- `format_client_auth` with a matched method but a nil `client_auth_type` would read "<name> (None)" (`helpers.ex:116-120`); whether the proxy can record that combination was not checked.
- The success-state test asserts `html =~ "api"` for client auth (`show_test.exs:91`), which would match many strings; the "API key" label is only asserted in the auth attribution test.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the summary show the snapshot's destination URL and name rather than the current channel's? (6.1)
- Should the page show the proxy `request_id` that clients and destinations see? (6.1)
- Should a pending request update live, and should the empty cards explain themselves? (6.1, 6.2)
- history-channel-logs S05 owns the channel state pill labels; should it move to shared-run-components so both channel views inherit it?

## Proposed flows

- **flow-zero-persistence-channel-requests** (already proposed by flow-zero-persistence-runs; referenced here, not created): when the project keeps no data, the proxy drops paths, headers, bodies and client IP before insert and marks the request wiped; this page shows the combined wiped viewer (S16, S17). Surfaces: project-settings-data-storage, controller:channel-proxy-plug (`channel_proxy_plug.ex`, `persistence_policy.ex:12-38`), history-channel-logs, channel-request-show.
- **flow-channel-proxy-request** (already proposed by flow-webhook-auth-method-enforcement; referenced here, not created): the proxy checks the client's credentials against the channel's webhook auth methods and records which one matched; this page shows the recorded method and type (S13, S14). Surfaces: channels-index, controller:channel-proxy-plug, history-channel-logs, channel-request-show.

## Proposed shared

- **shared-local-datetime** (already proposed by project-settings-history-exports; referenced here, not created): the `Common.datetime` component with LocalTimeConverter, Copy and Tooltip hooks (`common.ex:422-492`), used here for Started and Completed (`show.ex:228`, `:236`). Surfaces: channel-request-show, history-channel-logs, project-settings-history-exports and other views rendering timestamps.

## Lead resolution (batch 3)

- `flow-zero-persistence-channel-requests` and `shared-local-datetime` created. `flow-channel-proxy-request` is held for the channels-index batch.
