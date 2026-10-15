---
id: flow-zero-persistence-channel-requests
type: flow
title: Channel requests on a project that keeps no request or response data
status: not-started
owner:

trigger:
  entry: project-settings-data-storage          # channels have no retention setting of their own; the project's retention_policy decides (persistence_policy.ex:20-21)
  exit: channel-request-show                    # also history-channel-logs
  surfaces:
    - project-settings-data-storage             # admin saves "Never retain input/output data (zero-persistence)" (project-settings-data-storage S06; settings.html.heex:956-959; settings.ex:366-378)
    - external:channel-client                   # a client system sends a request to /channels/<channel_id>/... (endpoint.ex:76; channel_proxy_plug.ex:72-80)
    - controller:channel-proxy-plug             # reads the policy once per request (channel_proxy_plug.ex:212-225) or records a credential error (:364-398)
    - capability:channel-persistence-policy     # drops payload fields before insert and marks the request wiped (persistence_policy.ex:12-37; handler.ex:72-75, :143-148; channels.ex:599-625)
    - external:channel-destination              # receives and answers the request as usual (channel_proxy_plug.ex:238-246)
    - history-channel-logs                      # path cell reads "—" (channel_logs_component.ex:163, :200-201)
    - channel-request-show                      # request/response wiped viewer (show.ex:94-101; viewers.ex:309-339)
    - project-settings-data-storage             # admins follow "this policy" back to the tab (viewers.ex:331-339)
    - channels-index   # added by lead
  reachable_when:
    - the actor passes `:edit_data_retention` on the entry view (project_users.ex:29-37; settings.ex:366-378)
    - project.retention_policy is `:erase_all` when the proxy receives the request (channel_proxy_plug.ex:223-224; projects.ex:425-435)
    - the channel is enabled and the client passes its client auth (channel_proxy_plug.ex:115-121, :318-323); owned by the channel proxy, not here
    - the viewer of history-channel-logs and channel-request-show passed shared-project-scope and has experimental features on (channel_request_live/show.ex:23, :45-46)

inherits:
  - shared-project-scope            # who can open the two exit views; not repeated here
  - shared-run-components           # channel_state_pill labels on both exit views; not repeated here

url_params:
  - name: "#data-storage (URL fragment)"
    set_by: channel-request-show wiped viewer "this policy" link (viewers.ex:331-339)
    effect: opens the data storage tab client-side (owned by project-settings-data-storage)

config_variants:
  default: {}                                                                  # the proxy hop behaves the same; the detail page redirects to History, so the exit views are not reachable as designed
  experimental-features: { user.preferences.experimental_features: true }      # accounts.ex:1446-1448; every UI step read under this one

inventory:
  routes:
    - "endpoint plug /channels/:channel_id/*  LightningWeb.ChannelProxyPlug"    # endpoint.ex:76; not in the router
  events:
    - ProjectLive.Settings#save_retention_settings          # entry, owned by project-settings-data-storage
    - Lightning.Channels.Handler.handle_request_started/2    # handler.ex:57-91
    - Lightning.Channels.Handler.handle_response_finished/2   # handler.ex:103-173
    - Lightning.Channels.record_destination_credential_error/3   # channels.ex:599-638
  js_hooks:
    - Tooltip                       # admin contacts on the wiped viewer (viewers.ex:351-357); listed by channel-request-show
  policies:
    - Lightning.Policies.ProjectUsers :edit_data_retention   # entry, and the detail page's policy link (show.ex:36-42)
  workers: []                       # nothing deferred; the data_retention job deletes channel requests by history period only (section 4)
  api_endpoints: []
  emails: []                        # a policy-only change sends none (flow-data-retention-change-email 6.1)
  config:
    - user.preferences.experimental_features (show.ex:23)
  not_reachable_here:
    - Viewers.wiped_data_viewer :input and :output branches (viewers.ex:340-349), owned by flow-zero-persistence-runs
    - run dataclip wiping (run_channel.ex:184-191; handlers.ex:513-532), owned by flow-zero-persistence-runs

related:
  - flow-zero-persistence-runs
  - project-settings-data-storage
  - history-channel-logs
  - channel-request-show
  - flow-data-retention-change-email
  - lib/lightning/channels/persistence_policy.ex
  - lib/lightning/channels/handler.ex
  - lib/lightning_web/plugs/channel_proxy_plug.ex
flows:
  - flow-zero-persistence-runs
---

## 1. Purpose

Projects bound by a data protection agreement choose "Never retain" so that the health records
passing through their Channels are not kept at rest, just as for runs (flow-zero-persistence-runs).
This flow is that promise for the proxy: requests arriving afterwards are forwarded as usual but
stored without their path, query, headers, bodies, body hashes or client IP, and anyone who opens
them later sees that the data was withheld on purpose rather than lost. Without it, an admin could
not confirm the setting covers channels, and someone debugging a channel would read the missing
payload as a proxy fault.

## 2. What it does

1. A project admin chooses "Never retain" on the data storage tab of project settings; channels have no setting of their own.
2. Channel requests that arrive afterwards are forwarded and answered exactly as before, so client systems keep working.
3. Each of those requests is stored without its contents: no path, query, headers, bodies or client IP.
   - What's kept is the method, status, state, sizes, timing and any error, so failures still show up.
   - A request that fails because of a broken destination credential is recorded the same way.
4. People with experimental features on see what was withheld.
   - The channel logs show "—" for the request's path.
   - The request's page says its request and response data wasn't kept because of the project's policy; admins and owners get a link back to the setting, everyone else is told to contact an admin.
5. The setting only affects requests from that moment on, in both directions; switching back stores contents again for new requests only.

**Straightforwardness: 3 of 5.** It mirrors the same setting for runs and mostly does what it says, but it only reaches forward in time and it hides a little more than it should on the request page.

### Most surprising behaviours

- **(2)** Requests stored before the switch keep their full contents, and nothing ever erases them. With no history period set, they stay visible on the channel logs indefinitely. (6.1, S05)
- **(3)** On a request that failed, the "not retained" message replaces the only part of the page that explains the error, so you see a red "Error" with no reason, even though the list shows the error code. (6.1, S03)
- **(3)** The channel logs list gives no sign that a request's data was withheld; its "—" looks exactly like the one shown for an errored request. (6.1)
- **(3)** "Payloads will not be stored" isn't the whole story: body sizes, timing, the destination address and error messages are still kept, and it hasn't been checked whether an error message can carry payload data. (6.2, 6.5)
- **(4)** Unlike runs, which lock the setting in when they're created, a channel request uses whatever the setting is at the moment it arrives. (6.2)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_data_retention` is admin). The
detail page computes `can_edit_data_retention` at mount (`show.ex:36-42`) and lists admin and
owner emails for everyone else (`show.ex:35`; `projects.ex:541-548`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| Start the flow by saving "Never retain" | no | no | yes | yes | no | no |
| See a wiped request in channel logs and on its page | yes | yes | yes | yes | no | yes |
| Follow "this policy" to the data storage tab | no | no | yes | yes | no | no |
| See the admin contacts tooltip instead | yes | yes | no | no | no | yes |

**Preconditions beyond role**
- The policy is read once per proxied request, before the request is inserted, and held for that request's lifetime (`channel_proxy_plug.ex:223-224`; `handler.ex:72`, `:143`). See 6.2.
- Seeing either exit view needs the viewer's experimental features preference (`show.ex:23`; history-channel-logs reachable_when).
- The client system sending requests is outside the project's roles; it only needs the channel's client auth (`channel_proxy_plug.ex:176-197`).

## 4. What it touches

**Reads**
- Hop 1 (save): owned by project-settings-data-storage.
- Hop 2 (proxy): `projects.retention_policy` via `Projects.save_dataclips?/1` once per request (`persistence_policy.ex:20-21`; `projects.ex:425-435`); the channel, its auth methods and current snapshot (`channel_proxy_plug.ex:133-136`, `:318-323`)
- Hop 3 (channel logs): `channel_requests` with `destination_response` and `error` events (owned by history-channel-logs)
- Hop 4 (detail page): the request with events, snapshot and auth associations, and admin and owner emails (`channels.ex:561-581`; `projects.ex:541-548`)

**Writes**
- Hop 1: `projects.retention_policy = erase_all` (project-settings-data-storage S06)
- Hop 2a (request started): a `channel_requests` row with `client_identity` dropped and `is_wiped = true`; channel, snapshot, `request_id`, auth method, auth type, destination credential, state and `started_at` kept (`handler.ex:58-77`; `persistence_policy.ex:18`, `:26-30`)
- Hop 2b (response finished): a `channel_events` row without `request_path`, `request_query_string`, `request_headers`, `request_body_preview`, `request_body_hash`, `response_headers`, `response_body_preview`, `response_body_hash`; method, status, body sizes, timing and `error_message` kept (`handler.ex:113-153`; `persistence_policy.ex:12-16`, `:35-37`); then the request's `state` and `completed_at` (`handler.ex:138-157`)
- Hop 2c (credential error instead): request and event inserted in one transaction with the same fields dropped (`channels.ex:605-625`)

**Immediate side effects**
- The client receives the destination's response as on any other project (`channel_proxy_plug.ex:238-246`; `channel_proxy_plug_test.exs:1857-1862`)
- Telemetry spans for inbound, request and upstream fire as usual; the upstream span carries the path in its metadata (`channel_proxy_plug.ex:228-250`); see 6.5
- No PubSub broadcast; neither exit view updates live (history-channel-logs 6.2, channel-request-show 6.2)

**Deferred side effects**
- none. The two-hourly `data_retention` job deletes channel requests older than the history period whatever the policy, and never wipes them (`projects.ex:223-231`, `:1892-1900`; `channels.ex:420-439`).

**External, non-transactional effects**
- The request and response bodies stream through the proxy to the destination and back to the client before anything is stored (`channel_proxy_plug.ex:238-246`); the policy governs storage only.

**Depends on config**
- `user.preferences.experimental_features` for the exit views (variant `experimental-features`)

**Product limits**
- Requests already stored when the policy is switched keep their payloads (S05; 6.1)

## 5. Scenarios

```gherkin
Feature: Channel requests on a zero-persistence project
  In order to keep health records that pass through my channels out of storage
  As a project admin
  I want requests proxied after I choose "Never retain" to store no payload, and say so

  @S01 @pending @variant:experimental-features
  Scenario: A request proxied after the switch shows its request and response as not retained
    # Value: the admin can confirm the policy covers channels, and people debugging a channel read the missing payload as policy, not a proxy fault.
    Given I am an admin on project "Malawi HIV" with experimental features enabled
    And I have saved "Never retain input/output data (zero-persistence)" on the "Data Storage" tab
    And channel "orders-proxy" then proxies 'POST /api/v1/data?secret=abc' and the destination answers 200
    When I open the channel logs tab
    Then the request's path cell reads "—"
    When I open the request from its ID
    Then instead of the request and response sections I see "No Request/Response Data here!"
    And "Request/Response data for this channel request has not been retained in accordance with your project's data storage policy."
    And the client IP reads "—"
    # settings.ex:366-378; channel_proxy_plug.ex:223-224; handler.ex:72-75, :143-148; persistence_policy.ex:12-37
    # channel_logs_component.ex:163, :200-201; show.ex:94-101, :172; viewers.ex:309-328, :385-391
    # channel_proxy_plug_test.exs:1836-1905 (stored fields nil, is_wiped true); index_test.exs:765-810 (dash); show_test.exs:460-499 (viewer)
    # the end-to-end path through the settings save is inferred from code

  @S02 @pending
  Scenario: Clients still get the destination's response
    # Value: switching a project to zero persistence doesn't break the integrations that call its channels.
    Given project "Malawi HIV" never retains I/O data
    When a client posts '{"hello":"world"}' to channel "orders-proxy"
    Then the destination receives the request
    And the client receives the destination's status 200
    And the stored request records method "POST", status 200, latency and both body sizes
    # channel_proxy_plug.ex:238-246; handler.ex:113-136
    # channel_proxy_plug_test.exs:1849-1904

  @S03 @pending @variant:experimental-features
  Scenario: A wiped request still shows whether and how it failed
    # Value: people can still tell a destination outage from a success without the payload.
    Given project "Malawi HIV" never retains I/O data
    And a request through "orders-proxy" failed with error "econnrefused"
    When I open the channel logs tab
    Then its status reads "Error" and its error message reads "econnrefused"
    And on the request's page the method and state pill are shown with the wiped viewer
    # handler.ex:135, :175-187; persistence_policy.ex:12-16 (error_message, method, status not dropped)
    # channel_logs_component.ex:179-183, :203-204; show.ex:85-92
    # handler_test.exs:461-488 (error event wiped, error_message kept)
    # the page does not say why it failed: 6.1

  @S04 @pending
  Scenario: A credential error on a zero-persistence project is recorded without its path
    # Value: a broken destination credential is still visible in the logs without storing what the client sent.
    Given project "Malawi HIV" never retains I/O data
    And channel "orders-proxy" uses a destination credential that can't be resolved
    When a client sends 'GET /secret-path' to the channel
    Then the client receives status 502
    And a request in state "error" is stored, marked wiped, with method "GET" and its credential error code but no path or client IP
    # channel_proxy_plug.ex:142-143, :364-398; channels.ex:599-625
    # channel_proxy_plug_test.exs:1965-2028

  @S05 @pending @variant:experimental-features
  Scenario: The policy applies to requests from the switch on, in both directions
    # Value: nobody is misled about which requests kept their payloads, and a project that needs to debug again gets payloads from then on.
    Given channel "orders-proxy" in project "Malawi HIV" proxied request "A" while the project retained all I/O data
    And an admin then saved "Never retain" and the channel proxied request "B"
    And the admin then saved "Retain all input/output data" and the channel proxied request "C"
    When I open each request's page
    Then "A" and "C" show their request and response sections
    And "B" still shows "No Request/Response Data here!"
    # channel_proxy_plug.ex:223-224 (read per request); no code rewrites stored requests (persistence_policy.ex, channels.ex)
    # channel_proxy_plug_test.exs:1907-1963 (retain_all keeps fields); project-settings-data-storage S07; inferred end to end

  @S06 @pending @variant:experimental-features
  Scenario Outline: The not retained message tells each reader what they can do
    # Value: the person who can change the policy can get there, and everyone else knows whom to ask.
    Given project "Malawi HIV" never retains I/O data and has a wiped channel request
    And I am <role> on project "Malawi HIV"
    When I open the request's page
    Then I see <guidance>
    # show.ex:35-42, :95-100; viewers.ex:329-361; projects.ex:541-548
    # show_test.exs:460-499 (admin), :501-542 (editor)

    Examples:
      | role      | guidance |
      | an admin  | "You can change this policy for future requests." with "this policy" linking to "/projects/<project_id>/settings#data-storage", and no "rerun this work order" |
      | an owner  | the same link |
      | an editor | "Contact one of your project admins for more information." with a tooltip listing the project's admins and owners |
      | a viewer  | the same contact message |
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Requests stored before the switch keep their paths, headers, bodies and client IPs; nothing wipes channel requests, and the cleanup job only deletes them by history period | `persistence_policy.ex:1-38` (insert-time only); `projects.ex:1892-1900`; `channels.ex:420-439` | after choosing "Never retain", every earlier request on the channel logs still shows its full payload, indefinitely when no history period is set | decide |
| On a wiped request that errored without a timeout, the wiped viewer replaces the Response section, which is the only place the error is explained, though `error_message` is still stored | `show.ex:82-83`, `:94-107`; `components.ex:182-195` (tooltip only for timeout); `persistence_policy.ex:12-16` | a red "Error" pill and "No Request/Response Data here!" with no reason, while the channel logs list shows the error code | fix |
| The channel logs list never reads `is_wiped`; a wiped request's "—" path is the same as an errored request's (whose path is never read) | `channel_logs_component.ex:163`, `:200-201`; history-channel-logs 6.1 | the list gives no sign a request's data was withheld by policy | decide |
| A crafted `retain_with_errors` policy makes `save_dataclips?/1` raise, so every proxied request on the project crashes in the plug before it is forwarded | `project.ex:28-30`; `projects.ex:432-435`; `persistence_policy.ex:21`; `channel_proxy_plug.ex:223-224`; owned by project-settings-data-storage 6.1 | client systems get a server error on every channel request | fix (owned by project-settings-data-storage) |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The policy is read per request at proxy time (one query per request), unlike runs, which capture it at run creation; a request in flight when the policy changes keeps the value read at its start | `channel_proxy_plug.ex:223-224`; `handler.ex:72`, `:143`; flow-zero-persistence-runs 6.2 | preserve |
| Body sizes, method, status, timing, auth method, destination credential and the snapshot's destination URL are kept; the settings copy says only that "payloads will not be stored" | `handler.ex:113-136`; `persistence_policy.ex:12-18`; project-settings-data-storage S06 | preserve |
| A wiped request's summary shows a blank path area and "—" for client IP rather than a not-retained label; the timing section still renders | `components.ex:124-138`; `show.ex:92`, `:172` | decide |
| The wiped viewer copy is title case "No Request/Response Data here!" | `viewers.ex:321-323`, `:387` | decide |
| Non-admins see admin and owner email addresses in a tooltip | `viewers.ex:350-357`; channel-request-show 6.2 | decide |
| The policy link is a `navigate` to another LiveView's hash, so a full mount | `viewers.ex:333-338` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| One `projects` query per proxied request to read the policy | `channel_proxy_plug.ex:223-224`; `projects.ex:425-431` | no | preserve |

### 6.5 Things seen but not understood

- The `[:lightning, :channel_proxy, :upstream]` telemetry span carries the forward path in its metadata regardless of policy (`channel_proxy_plug.ex:228-232`). The in-repo PromEx plugin tags only outcome and project id (`prom_ex_plugin.ex:56-70`); whether any other attached handler records the path was not checked.
- `error_message` falls back to `inspect(error)` for unknown errors (`handler.ex:218`) and is kept under "Never retain"; whether that string can carry payload data was not checked.
- Whether Philter buffers the body observation in memory beyond the request was not traced; the preview and hash are computed and then dropped before insert (`handler.ex:120-126`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should switching to "Never retain" wipe channel requests already stored, or should the settings copy say it applies to new requests only (6.1)?
- Should a wiped request's page still explain why it failed (6.1)?
- Should the channel logs list mark wiped requests distinctly (6.1)?

## Proposed flows

- Referenced: flow-zero-persistence-runs (run half), project-settings-data-storage S06 and S07 (entry handoffs), history-channel-logs S14 and channel-request-show S16, S17 (exit handoffs), flow-data-retention-change-email (no email on a policy-only change).
- `flow-retention-cleanup` (already proposed by project-settings-data-storage; referenced, not created): owns deletion of channel requests by history period.

## Proposed shared

- none. Referenced: shared-project-scope, shared-run-components.
