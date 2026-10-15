---
id: flow-channel-proxy-request
type: flow
title: A request through a channel
status: not-started
owner:

trigger:
  entry: channels-index                         # configuration: destination URL, destination credential, client credentials, enabled (channels-index S08, S12, S13, S21)
  exit: channel-request-show                    # also history-channel-logs
  surfaces:
    - channels-index                            # editor sets up the channel and copies its proxy URL (channels-index S04)
    - external:channel-client                   # a client system sends any method to /channels/<channel_id>/<path> (endpoint.ex:76; channel_proxy_plug.ex:72-80)
    - controller:channel-proxy-plug             # 404 / 401 / credential resolution / forward (channel_proxy_plug.ex:84-148)
    - capability:channel-persistence-policy     # decides what the stored record keeps (channel_proxy_plug.ex:223-224); owned by flow-zero-persistence-channel-requests
    - external:channel-destination              # receives the forwarded request with the destination credential (channel_proxy_plug.ex:238-246)
    - external:channel-client                   # receives the destination's response, with Lightning's security headers (channel_proxy_plug.ex:302-308)
    - history-channel-logs                      # the request is listed (history-channel-logs S01, S04, S13)
    - channel-request-show                      # the request's detail, including client auth and destination credential used (channel-request-show S13)
    - project-settings-webhook-security   # added by lead (link lint)
  reachable_when:
    - any HTTP client holding the proxy URL; no Lightning session is needed and none is checked (endpoint.ex:76; channel_proxy_plug.ex:72-131)
    - the channel exists and is enabled (channel_proxy_plug.ex:318-323)
    - the exit views need shared-project-scope and the viewer's experimental features preference (channel_request_live/show.ex:23, :45-46)

inherits:
  - shared-project-scope            # who can open the entry and exit views; not repeated here
  - shared-run-components           # channel_state_pill labels on both exit views; not repeated here

url_params:
  - name: channel_id (first path segment after /channels/)
    set_by: channels-index proxy URL copy (helpers.ex:7-9, :52-72)
    effect: selects the channel; a non-UUID, unknown or disabled channel answers 404 (S05)
  - name: rest of the path and the query string
    set_by: the client system
    effect: appended to the destination URL unchanged; the query string passes through (channel_proxy_plug.ex:240-241, :325-326; channel_proxy_plug_test.exs:117-190)

config_variants:
  default: {}                                                                  # read under this; private and reserved destinations are blocked (config.exs:214-216)
  sandbox: { project.parent_id: <parent project id>, project.env: <env name> } # destination credential body resolved for the sandbox's own environment (environment.ex:71-77)
  egress-relaxed: { CHANNEL_BLOCK_PRIVATE_NETWORKS: false }                    # or CHANNEL_ALLOWED_HOSTS set (bootstrap.ex:607-618)
  experimental-features: { user.preferences.experimental_features: true }      # needed only to see the exit views; the proxy itself never checks it

inventory:
  routes:
    - "endpoint plug /channels/:channel_id/*  LightningWeb.ChannelProxyPlug"    # endpoint.ex:76; not in the router
  events:
    - Lightning.Channels.Handler.handle_request_started/2      # handler.ex:57-91
    - Lightning.Channels.Handler.handle_response_started/2     # handler.ex:93-101
    - Lightning.Channels.Handler.handle_response_finished/2    # handler.ex:103-173
    - Lightning.Channels.get_channel_with_auth/1               # channels.ex:161-177
    - Lightning.Channels.get_or_create_current_snapshot/1      # channels.ex:369-411
    - Lightning.Channels.record_destination_credential_error/3 # channels.ex:599-638
    - Lightning.Channels.DestinationAuth.build_auth_header/2   # destination_auth.ex:24-64
  js_hooks: []
  policies: []                      # the proxy checks no project role; client auth is LightningWeb.Auth (auth.ex:21-79)
  workers: []
  api_endpoints:
    - plug LightningWeb.ChannelProxyPlug (channel_proxy_plug.ex:1-435)
    - module LightningWeb.Auth valid_key?/2, valid_user?/2 (auth.ex:21-31, :42-79)
  emails: []
  config:
    - ":philter block_private_networks / allowed_hosts (config.exs:214-216; bootstrap.ex:607-618; CHANNEL_BLOCK_PRIVATE_NETWORKS, CHANNEL_ALLOWED_HOSTS)"
  not_reachable_here:
    - LightningWeb.Auth.has_credentials?/1 (auth.ex:37-40); used only by the webhook plug (flow-webhook-auth-method-enforcement)
    - Lightning.Channels.PromExPlugin metrics (prom_ex_plugin.ex:41-70); operational, fed by this plug's telemetry spans

related:
  - lib/lightning_web/plugs/channel_proxy_plug.ex
  - lib/lightning/channels/handler.ex
  - lib/lightning/channels/destination_auth.ex
  - lib/lightning_web/auth.ex
  - lib/lightning/projects/environment.ex
  - test/lightning_web/plugs/channel_proxy_plug_test.exs
  - test/lightning_web/plugs/channel_proxy_egress_test.exs
  - project-settings-webhook-security       # where the client credentials are created
  - project-settings-credentials            # where the destination credential is created
flows:
  - flow-zero-persistence-channel-requests  # what is stored when the project keeps no request data
  - flow-webhook-auth-method-enforcement    # same LightningWeb.Auth checks on webhook triggers
---

## 1. Purpose

A channel lets a partner system call a destination API (a DHIS2 instance, a lab system) through
OpenFn without ever holding the destination's secret: the partner presents a client credential the
project gave it, and OpenFn swaps it for the project's destination credential on the way out. Every
call is logged so people running the integration can see what arrived and how the destination
answered. If the checks fail open, anyone with the URL spends the project's secret against the
destination; if logging fails, a partner's "my request never arrived" can't be answered.

## 2. What it does

1. An editor sets up a channel on the channels page (where it sends to, the credential to send with, and which client credentials may call it) and hands its address to a partner system.
2. The partner system sends a request to that address.
   - A switched-off, unknown or malformed channel answers "Not Found".
   - A request without a matching client credential answers "Unauthorized"; any one of the channel's credentials is enough, and a deleted one stops working at once.
   - Destinations on the internal network are blocked unless the hosting operator allows them.
3. Otherwise the request is passed on unchanged, with the partner's own credential and any Lightning sign-in cookie removed and the project's destination credential added in the form that destination expects.
   - A sandbox uses its own credential values, never the parent project's.
   - A destination credential that can't be used stops the request before it's sent and records why.
4. The destination's answer goes back to the partner, with protections added so it can't run scripts or set cookies on Lightning's site.
5. Project members with experimental features on see each forwarded request in the channel logs and on its own page: timing, outcome, which credentials were used, and secrets blanked out.

**Straightforwardness: 3 of 5.** A proxy that swaps one key for another is easy to explain, but whether a channel is actually locked, and what you can see when things go wrong, both need spelling out.

### Most surprising behaviours

- **(2)** A channel with no client credentials lets anyone with the address call the destination as the project, with no warning. Deleting a channel's only client credential, for example to cut off a leaked key, turns it into exactly that kind of open channel. (6.1, S04)
- **(3)** Refused requests, from a wrong key or a switched-off channel, aren't recorded anywhere a project member can see, so "my request never arrived" can't be answered. (6.1)
- **(3)** A partner that retries with the same request id gets "Service Unavailable" and nothing is logged. (6.1)
- **(3)** The client address shown on the request page is whatever the caller claims it is. (6.1)
- **(3)** There's no rate limit, usage limit or size limit on channel traffic, and turning off experimental features only hides the pages; the channels keep working. (6.2)

## 3. Who can do what

Configuration roles are owned by channels-index (section 3; `project_users.ex:39-49`). The proxy
hop checks no project role: the caller is an external system identified only by the channel's
client auth methods (`channel_proxy_plug.ex:176-197`).

| Action | Viewer | Editor | Admin | Owner | Anonymous caller with the URL | Caller with a matching client credential |
|--------|--------|--------|-------|-------|-------------------------------|------------------------------------------|
| Configure the channel (entry) | no | yes | yes | yes | n/a | n/a |
| Send a request through a channel with client auth | n/a | n/a | n/a | n/a | no, 401 | yes |
| Send a request through a channel with no client auth | n/a | n/a | n/a | n/a | yes (6.1) | yes |
| Send a request through a disabled channel | n/a | n/a | n/a | n/a | no, 404 | no, 404 |
| See the request in channel logs and on its page (exit) | yes | yes | yes | yes | n/a | n/a |

**Preconditions beyond role**
- A caller matches if any of the channel's client methods matches: an `x-api-key` equal to an API method's key, or Basic credentials equal to a basic method's username and password, compared in constant time (`channel_proxy_plug.ex:189-196`; `auth.ex:21-31`, `:42-79`).
- A method scheduled for deletion never matches (`auth.ex:47`, `:62`), and scheduling it removes it from every channel (`webhook_auth_methods.ex:700-703`).
- Logged-in Lightning users get nothing extra: their session cookie is stripped before forwarding (`channel_proxy_plug.ex:282-289`).
- The exit views need experimental features; the proxy does not (`channel_request_live/show.ex:23`).

## 4. What it touches

**Reads, by hop**
- Proxy: `channels` with `channel_auth_methods`, `webhook_auth_methods`, `project_credentials`, `credentials` in one query (`channels.ex:161-177`); `channel_snapshots` for the current `lock_version` (`channels.ex:378-381`); `projects` for the environment when a destination credential is set (`environment.ex:50-55`) and for the retention policy (`channel_proxy_plug.ex:223-224`); `credential_bodies` for that environment (`credentials.ex:1237-1257`)
- Exit views: owned by history-channel-logs and channel-request-show

**Writes, by hop**
- Proxy, first request after a config change: `channel_snapshots` insert, `ON CONFLICT DO NOTHING` (`channels.ex:383-410`)
- Proxy, before forwarding: `channel_requests` insert in state `pending` with snapshot, `request_id`, client IP, matched client method and type, destination credential (`handler.ex:58-77`); a failed insert rejects the request with 503 (`handler.ex:86-89`)
- Proxy, after the response or transport error: `channel_events` insert with method, path, query, redacted headers, body previews, hashes, sizes, status, timing and error code; `channel_requests` state and `completed_at` updated (`handler.ex:109-157`)
- Proxy, credential error instead: `channel_requests` (state `error`) and `channel_events` (type `error`) in one transaction (`channels.ex:605-625`)
- Proxy, OAuth destination credential with an expired token: `credential_bodies` updated and an audit event recorded (`credentials.ex:1243-1253`, `:1282-1286`, `:1305-1320`)
- What is dropped from these writes under "Never retain": owned by flow-zero-persistence-channel-requests
- 404 and 401: no writes (`channel_proxy_plug.ex:96-104`, `:119-120`)

**Immediate side effects**
- Response to the client: the destination's status, headers and body, plus `content-security-policy` (sandboxed, `frame-ancestors 'none'`), `x-content-type-options`, `x-frame-options`, `referrer-policy`, with `set-cookie` removed; the same headers on 404 and 401 (`channel_proxy_plug.ex:39-45`, `:73`, `:302-308`)
- Headers added to the forwarded request: `x-forwarded-for`, `x-forwarded-host`, `x-forwarded-proto`, `x-request-id`, and `authorization` when a destination credential is set (`channel_proxy_plug.ex:262-280`)
- Telemetry spans `inbound`, `fetch_channel`, `request`, `upstream` (`channel_proxy_plug.ex:75-79`, `:108-130`, `:202-209`, `:234-250`), counted by `prom_ex_plugin.ex:41-70`
- No PubSub broadcast; neither exit view updates live (history-channel-logs 6.2, channel-request-show 6.2)

**Deferred side effects**
- none. Expired requests are deleted by history period by the retention job (owned by flow-zero-persistence-channel-requests section 4).

**External, non-transactional effects**
- The forwarded request reaches the destination before the outcome is stored; if the event insert then fails, the request is marked `error` though the client got the destination's answer (`handler.ex:150-172`; 6.1)
- An OAuth token refresh calls the provider during the request (`credentials.ex:1260-1266`)

**Depends on config**
- `default`: Philter refuses private and reserved destinations with 403 (`config.exs:214-216`; `channel_proxy_egress_test.exs`)
- `egress-relaxed`: operators allow internal destinations (`bootstrap.ex:607-618`)
- `sandbox`: destination credential body comes from the sandbox's environment; a sandbox without one gets 502 (`environment.ex:71-77`)

**Product limits**
- none enforced by Lightning on this path: no rate limit, usage limit or body size limit in the plug (6.2)

## 5. Scenarios

```gherkin
Feature: A request through a channel
  In order to let a partner system reach a destination API without holding its secret
  As a project editor running an integration
  I want requests with a valid client credential forwarded with the destination credential, and every forwarded request logged

  @S01 @pending @variant:experimental-features
  Scenario: An authenticated request is forwarded with the destination credential and logged
    # Value: the partner reaches the destination without ever holding its secret, and people running the integration can see the call.
    Given I am an editor on project "Malawi HIV"
    And I created channel "lab-results" to "https://destination.example.com" with client credential "Lab key" (API key "k-123") and destination credential "Dest token" (bearer "dest-xyz")
    And I copied its proxy URL from the channels page
    When a client sends 'POST <proxy URL>/api/v1/data?format=json' with header "x-api-key: k-123" and a JSON body
    Then the destination receives 'POST /api/v1/data?format=json' with the same body and "authorization: Bearer dest-xyz"
    And the client receives the destination's status, headers and body
    When I open the channel logs
    Then the request is listed with path "/api/v1/data" and status "Success"
    When I open the request from its ID
    Then client auth reads "Lab key (API key)" and destination auth reads "Dest token"
    # channel_proxy_plug.ex:115-117, :133-140, :212-251, :262-280; handler.ex:57-91, :103-157
    # channel_proxy_plug_test.exs:32-145, :677-707, :1228-1247, :1627-1656, :1710-1740
    # exit handoffs: history-channel-logs S01, S04, S13; channel-request-show S01, S13. End to end inferred from code.

  @S02 @pending
  Scenario Outline: A request without a matching client credential is refused
    # Value: only systems the project handed a credential to can spend the destination credential.
    Given channel "lab-results" has client credential <method>
    When a client sends a request with <sent>
    Then the client receives 401 with body '{"error":"Unauthorized"}'
    And the destination receives nothing
    And no request is recorded for "lab-results"
    # channel_proxy_plug.ex:119-120, :180-197; auth.ex:42-79
    # channel_proxy_plug_test.exs:793-872; no-record inferred from code (no insert before forward_request), see 6.1

    Examples:
      | method                        | sent                                   |
      | API key "k-123"               | "x-api-key: wrong"                     |
      | API key "k-123"               | no credential                          |
      | basic "user" / "password"     | Basic credentials "user" / "nope"      |
      | basic "user" / "password"     | no authorization header                |

  @S03 @pending
  Scenario: Any one of a channel's client credentials is enough
    # Value: a partner's key can be rotated by adding the new one before removing the old, with no outage.
    Given channel "lab-results" has an API key method "k-old", an API key method "k-new" and a basic method "user" / "password"
    When clients send requests with "x-api-key: k-old", "x-api-key: k-new" and Basic "user" / "password"
    Then each is forwarded
    And each stored request records the method it matched and its type
    # channel_proxy_plug.ex:189-196, :253-260; handler.ex:64-66
    # channel_proxy_plug_test.exs:874-918, :1628-1687

  @S04 @pending
  Scenario: A deleted client credential stops working at once
    # Value: a leaked partner key is cut off as soon as an admin deletes it, while the partner's other key keeps working.
    Given channel "lab-results" has API key methods "k-leaked" and "k-live"
    When an admin deletes "k-leaked" on the webhook security tab
    Then a request with "x-api-key: k-leaked" gets 401
    And a request with "x-api-key: k-live" is forwarded
    # auth.ex:47, :62; webhook_auth_methods.ex:674-703 (schedule_for_deletion removes channel_auth_methods rows)
    # channel_proxy_plug_test.exs:919-998. Deleting the channel's last method: 6.1.

  @S05 @pending
  Scenario Outline: A disabled, unknown or malformed channel answers 404
    # Value: switching a channel off stops its traffic immediately, and callers can't tell a disabled channel from one that never existed.
    Given <channel>
    When a client sends a request to "/channels/<id>/test", with valid client credentials if any
    Then the client receives 404 with body '{"error":"Not Found"}'
    And the destination receives nothing and no request is recorded
    # channel_proxy_plug.ex:84-104, :318-323; channels-index S21 (toggle)
    # channel_proxy_plug_test.exs:461-481

    Examples:
      | channel                                            |
      | channel "lab-results" switched off on the channels page |
      | no channel with that id                            |
      | an id of "not-a-uuid"                              |

  @S06 @pending
  Scenario: The client's own credential and session cookie never reach the destination
    # Value: the partner's key and a Lightning user's session can't be captured by whoever runs the destination.
    Given channel "lab-results" has a basic client method and destination credential "Dest token"
    When a client sends a request with Basic credentials and a Lightning session cookie
    Then the destination receives "authorization: Bearer dest-xyz" and no client Basic credentials
    And the destination receives no "cookie" header
    And with an API key client method, the destination receives no "x-api-key" header
    # channel_proxy_plug.ex:282-289, :310-316
    # channel_proxy_plug_test.exs:330-358, :1076-1180

  @S07 @pending
  Scenario Outline: The destination credential is sent in the form the destination expects
    # Value: a channel works with HTTP, DHIS2 and OAuth credentials the project already holds, without the partner knowing which.
    Given channel "lab-results" has a destination credential of schema <schema> with <fields>
    When an authenticated request is forwarded
    Then the destination receives "authorization: <header>"
    # destination_auth.ex:27-60; channel_proxy_plug.ex:337-360
    # channel_proxy_plug_test.exs:1228-1304

    Examples:
      | schema                  | fields                       | header                     |
      | "@openfn/language-http" | access_token "t"             | Bearer t                   |
      | "@openfn/language-http" | username "u", password "p"   | Basic <base64 of u:p>      |
      | "@openfn/language-dhis2"| pat "p1"                     | ApiToken p1                |
      | "oauth"                 | access_token "o"             | Bearer o                   |
      | none                    |                              | no authorization header added |

  @S08 @pending @variant:experimental-features
  Scenario: A destination credential that can't be used stops the request and says why
    # Value: people fix the credential instead of chasing a destination outage, and the destination is never called with a broken secret.
    Given channel "lab-results" has a destination credential with no access token, username or password
    When an authenticated client sends 'GET /secret-path'
    Then the client receives 502 with body '{"error":"Bad Gateway"}'
    And the destination receives nothing
    And a request in state "error" with error "credential_missing_auth_fields" and the destination credential is recorded
    And the request page shows it as a credential error (channel-request-show S08)
    # channel_proxy_plug.ex:134, :142-143, :337-360, :364-434; channels.ex:599-638
    # channel_proxy_plug_test.exs:1340-1395, :1510-1537, :1741-1787

  @S09 @pending @variant:sandbox
  Scenario: A sandbox's channel uses the sandbox's own credential values
    # Value: a sandbox never sends the parent project's production secret to a test destination.
    Given sandbox "Malawi HIV staging" with environment "staging" has a channel using credential "Dest token"
    And "Dest token" has different values for "main" and "staging"
    When an authenticated request is forwarded
    Then the destination receives the "staging" value
    And a sandbox with no environment set gets 502 and a recorded error "credential_environment_not_configured"
    # channel_proxy_plug.ex:342-349; environment.ex:71-77; channel_proxy_plug.ex:430-431
    # channel_proxy_plug_test.exs:1397-1509

  @S10 @pending @variant:experimental-features
  Scenario: An unreachable destination is recorded as an error or timeout
    # Value: people can tell a destination that is down from one that answered with an error.
    Given channel "lab-results" points at a port with nothing listening
    When an authenticated request is sent
    Then the client receives 502 or 504
    And the request is recorded in state "error" or "timeout" with a transport error code
    And the request page explains it (channel-request-show S07, S09)
    # handler.ex:175-183, :210-218
    # channel_proxy_plug_test.exs:483-498, :709-731

  @S11 @pending @variant:default
  Scenario: A channel can't be pointed at the internal network
    # Value: a project editor can't use a channel to read cloud metadata or reach services inside the hosting network.
    Given channel "probe" has destination "http://169.254.169.254/latest/meta-data/"
    When a request is sent to it
    Then the client receives 403 "Request blocked by egress policy" and the body does not contain the address
    And under "egress-relaxed" with the host allow-listed, the request is forwarded
    # config.exs:214-216; bootstrap.ex:607-618
    # channel_proxy_plug_test.exs:500-555; channel_proxy_egress_test.exs (allowed_hosts escape hatch)

  @S12 @pending
  Scenario: A destination's response can't run script or set cookies on Lightning's origin
    # Value: a tenant-controlled destination can't hijack a logged-in user's session through a proxy response.
    Given the destination answers with "text/html", its own "content-security-policy" and a "set-cookie"
    When the response reaches the client
    Then it carries Lightning's sandboxed "content-security-policy", "x-frame-options: DENY", "x-content-type-options: nosniff" and "referrer-policy: no-referrer"
    And it carries no "set-cookie"
    # channel_proxy_plug.ex:39-45, :73, :302-308
    # channel_proxy_plug_test.exs:360-458

  @S13 @pending
  Scenario: Secrets are redacted in the stored request
    # Value: every project member can read request logs without seeing partner keys or the destination credential.
    When an authenticated request with "x-api-key" is forwarded with a destination credential
    Then the stored request headers show "authorization", "x-api-key" and "cookie" as "[REDACTED]"
    And stored response headers show "set-cookie" as "[REDACTED]"
    # handler.ex:50, :82, :99, :189-197
    # channel_proxy_plug_test.exs:1306-1338; shown by channel-request-show S02

  @S14 @pending
  Scenario: The request id travels to the destination and into the log
    # Value: a request seen in the destination's logs can be matched to the channel log entry.
    When a client sends a request through "lab-results"
    Then the destination receives the same "x-request-id" that the client gets back and that is stored on the request
    # endpoint.ex:68; channel_proxy_plug.ex:159-160, :273; handler.ex:62
    # channel_proxy_plug_test.exs:257-278. The request page does not show it (channel-request-show 6.1).
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A channel with no client credentials forwards any caller's request and attaches the destination credential; nothing warns about it | `channel_proxy_plug.ex:176-178`, `:337-360`; channels-index 6.1 | anyone with the URL calls the destination as the project | decide |
| Deleting a channel's only client credential on the webhook security tab silently turns it into an open proxy; a test pins this with the message "the destination credential is still spent on an unauthenticated caller" | `webhook_auth_methods.ex:700-703`; `channel_proxy_plug.ex:176-178`; `channel_proxy_plug_test.exs:999-1055` | an admin revoking a leaked key opens the channel to everyone instead of closing it | decide |
| Refused requests (404, 401) are not recorded anywhere a project member can see | `channel_proxy_plug.ex:96-104`, `:119-120` | a partner sending a wrong key, or calling a disabled channel, leaves no trace in channel logs | decide |
| A client-supplied `x-request-id` (20-200 chars) is reused as the stored `request_id`, which is unique; a repeat makes the insert fail and the request is rejected with 503 | `channel_proxy_plug.ex:10-16`, `:159-160`; `channel_request.ex:73`; `handler.ex:77-89` | a client retrying with the same request id gets "Service Unavailable" and nothing is logged | fix |
| The client IP stored and shown on the request page is the first `X-Forwarded-For` value, which the caller controls | `channel_proxy_plug.ex:328-333`; `handler.ex:63` | any caller can make its request appear to come from any address | decide |
| The credential-error path stores `conn.request_path` (`/channels/<id>/...`) and no query string, while forwarded requests store the forward path and query | `channel_proxy_plug.ex:385-390` vs `:219-221`; `handler.ex:117-118` | channel logs show two path formats for the same channel | fix |
| If the event insert fails after the destination answered, the request is set to `error` with no event | `handler.ex:150-172` | a successful call shows as "Error" with no reason on the request page | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Wrong client credentials answer 401, unlike webhooks, which answer 404 for wrong credentials | `channel_proxy_plug.ex:119-120`; flow-webhook-auth-method-enforcement section 2 | decide |
| Errors are JSON `{"error": "..."}` with title-case messages | `channel_proxy_plug.ex:409-411` | preserve |
| The plug sits in the endpoint before `Plug.Parsers` and the router, so no rate limit, usage limit or body size limit applies | `endpoint.ex:75-76`; `channel_proxy_plug.ex:72-131` | decide |
| Experimental features gate only the menu link and exit views; the proxy serves every enabled channel | `channel_proxy_plug.ex:72-131`; channels-index 6.2 | decide |
| Client credentials of a configured type are stripped; a client `authorization` header on a channel with no client auth passes through | `channel_proxy_plug.ex:282-289`, `:310-316`; `channel_proxy_plug_test.exs:1182-1196` | preserve |
| A `pending` request row is written before forwarding and completed afterwards | `handler.ex:68`, `:138-157` | preserve |
| The first request after a config change creates the snapshot, not the save | `channels.ex:369-411` | preserve |
| A snapshot lookup failure answers 500 with nothing recorded | `channel_proxy_plug.ex:145-146` | preserve |
| A trailing slash on the destination URL is trimmed; an empty path forwards as "/"; `..` segments are forwarded as-is | `channel_proxy_plug.ex:240`, `:325-326`; `channel_proxy_plug_test.exs:156-233` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `find_matching_auth_method` `_ -> false` clause | `channel_proxy_plug.ex:194` | `auth_type` is an enum of `:basic` and `:api` only (`webhook_auth_method.ex:31-35`) |
| `classify_credential_error(:project_not_found)` | `channel_proxy_plug.ex:433-434`; `environment.ex:57-61`, `:79` | the channel always carries a `project_id`; reachable only if the project is deleted mid-request |
| Snapshot failure branch in `handle_credential_error` | `channel_proxy_plug.ex:400-405` | `get_or_create_current_snapshot/1` returns `{:error, _}` only on a changeset error for attrs copied from a valid channel (`channels.ex:383-410`); no path found that fails it |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| An expired OAuth destination token is refreshed synchronously inside the request | `credentials.ex:1243-1253` | yes, slower first request after expiry | preserve |
| Per request: one joined channel query, one snapshot lookup, one or two project queries, one credential body query, two inserts and an update | `channels.ex:161-177`, `:378-381`; `environment.ex:52`; `channel_proxy_plug.ex:223-224`; `handler.ex:77`, `:150-157` | no | preserve |
| Timeouts, body preview size and connection pooling are Philter's defaults; Lightning sets only `collect_timing` | `channel_proxy_plug.ex:239-246` | yes, a slow destination times out at a limit Lightning does not set | decide |

### 6.5 Things seen but not understood

- Philter is not vendored in this checkout, so whether an egress-blocked request (403) calls the handler and leaves a stored request was not checked (`channel_proxy_plug.ex:239-246`).
- With no client auth configured and a destination credential set, the client's own `authorization` header and the added one both reach Philter; whether `extra_headers` replaces or duplicates it was not checked (`channel_proxy_plug.ex:276-279`, `:282-289`).
- `CORSPlug` runs before the proxy with `CORS_ORIGIN` (default `*`); whether it answers `OPTIONS` preflights itself, so they never reach the destination, was not checked (`endpoint.ex:70`, `:75-76`; `bootstrap.ex:595-597`).
- The `upstream` telemetry span carries the forward path regardless of retention policy (flow-zero-persistence-channel-requests 6.5).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a channel with no client credentials be allowed, warned about, or refused when it has a destination credential (6.1)?
- Should deleting a channel's last client credential disable the channel, or be refused, instead of opening it (6.1)?
- Should refused requests (401, 404) be logged for the project (6.1)?
- Should the proxy apply rate or usage limits (6.2)?

## Proposed flows

- Referenced: flow-zero-persistence-channel-requests (what is stored under "Never retain"), flow-webhook-auth-method-enforcement (same `LightningWeb.Auth` checks on triggers; its `not_reachable_here` points at this plug).
- Handoffs asserted only: channels-index S04, S12, S13, S21 (entry); history-channel-logs S01, S04, S13 and channel-request-show S01, S07, S08, S09, S13 (exit); project-settings-webhook-security (deleting a client credential, S04).

## Proposed shared

- none. Referenced: shared-project-scope, shared-run-components.
