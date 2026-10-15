---
id: flow-dashboard-request-logger
type: flow
title: Request logger on the LiveDashboard
status: not-started
owner:

trigger:
  entry: admin-live-dashboard                   # /dashboard/request_logger mints a stream id and signs a token (admin-live-dashboard S07)
  exit: admin-live-dashboard                    # the same tab shows the captured lines
  surfaces:
    - admin-live-dashboard                      # superuser opens /dashboard/request_logger, gets ?stream=<id>, a signed link and an "Enable cookie" button (pld:pages/request_logger_page.ex:8-41, :104-185)
    - external:any-http-request                 # any browser or HTTP client, signed in or not, hitting any non-static, non-socket path with the token in ?request_logger= or the request_logger cookie
    - controller:endpoint-request-logger-plug   # Phoenix.LiveDashboard.RequestLogger, before session, auth and routing (endpoint.ex:65-67)
    - pubsub:phx_dashboard:request_logger:<stream>  # every log line the request process emits is broadcast here (pld:logger_pubsub_backend.ex:5-11)
    - admin-live-dashboard                      # the subscribed tab appends each line (pld:pages/request_logger_page.ex:58-59)
  reachable_when:
    - entry and exit need a superuser on /dashboard (shared-admin-space S04, S05; router.ex:358-369)
    - the request hop needs only a token signed with the endpoint's secret_key_base under salt "request_logger" and less than 3600 seconds old (pld:request_logger.ex:9, :48-56); no session, role or project membership is checked (endpoint.ex:65-67 runs before endpoint.ex:99 Plug.Session and :109 Router)
    - the request is not served by Plug.Static (endpoint.ex:43-50) and is not a socket upgrade (/live, /worker, /socket are dispatched before any endpoint plug: endpoint.ex:18-36; phx:endpoint.ex:493, :683)

inherits:
  - shared-admin-space              # who can open the entry and exit page (S04, S05); not repeated here
  - shared-authenticated-session    # signed-out and locked-out visitors to /dashboard (S01 to S03); does not apply to the request hop

url_params:
  - name: request_logger
    set_by: admin-live-dashboard (the "Query Parameter" text box, pld:pages/request_logger_page.ex:107-131)
    effect: on any path of the endpoint, streams that request's log lines to the stream the token names (pld:request_logger.ex:32-38, :48-56)
  - name: stream
    set_by: admin-live-dashboard (redirect to a fresh id, pld:pages/request_logger_page.ex:38-41)
    effect: subscribes the page to phx_dashboard:request_logger:<stream> (pld:pages/request_logger_page.ex:8-19)

config_variants:
  default: {}                                   # read under this one: prod logger level :info (config/prod.exs:16)
  debug-logging: { LOG_LEVEL: debug }           # bootstrap.ex:487-505; lets Phoenix "Parameters" and Ecto "QUERY" lines through

inventory:
  routes:
    - "endpoint plug Phoenix.LiveDashboard.RequestLogger param_key: request_logger, cookie_key: request_logger"   # endpoint.ex:65-67; not in the router
  events:
    - Phoenix.LiveDashboard.RequestLoggerPage#toggle_cookie        # owned by admin-live-dashboard; pld:pages/request_logger_page.ex:63-69
    - Phoenix.LiveDashboard.RequestLoggerPage#toggle_autoscroll    # owned by admin-live-dashboard; pld:pages/request_logger_page.ex:71-72
    - Phoenix.LiveDashboard.RequestLoggerPage#handle_info({:logger, level, message})  # pld:pages/request_logger_page.ex:58-59
  js_hooks:
    - PhxRequestLoggerMessages        # pld:pages/request_logger_page.ex:82
    - PhxRequestLoggerQueryParameter  # pld:pages/request_logger_page.ex:111 (copy to clipboard)
    - PhxRequestLoggerCookie          # pld:pages/request_logger_page.ex:153-160; sets and clears document.cookie (pld:dist/js/app.js, line 15)
  policies: []                        # the request hop checks none; the entry page's gate is shared-admin-space
  workers: []
  api_endpoints: []
  emails: []
  config:
    - ":logger level (config/prod.exs:16; config/test.exs:139; bootstrap.ex:487-505)"
    - ":phoenix, :filter_parameters (config/prod.exs:19-30)"
    - "Lightning.Repo log: :debug (config/config.exs:22-24)"
    - ":logger, :console format and metadata (config/config.exs:162-181)"
    - "endpoint pubsub_server Lightning.PubSub (config/config.exs:38; application.ex:176)"
    - "live_dashboard options request_logger and request_logger_cookie_domain not passed, so enabled and scoped to the current host (router.ex:363-369; pld:router.ex:51-59, :218-248)"
  not_reachable_here:
    - "pld:pages/request_logger_page.ex:49-51 disabled menu link; the plug is installed, so param_key(conn) is never nil (pld:router.ex:426-432)"
    - "pld:pages/request_logger_page.ex:203-205 :parent cookie domain; option not passed"
    - "pld:application.ex:28-30 gen_event backend; Elixir 1.18 (.tool-versions) takes the :logger handler branch at :18-26"

related:
  - lib/lightning_web/endpoint.ex
  - lib/lightning_web/router.ex
  - config/prod.exs
  - lib/lightning/config/bootstrap.ex
  - lib/lightning_web/controllers/webhooks_controller.ex   # stores the query string, token included (6.2)
  - lib/lightning_web/plugs/channel_proxy_plug.ex         # forwards the query string, token included (6.2)
  - flow-channel-proxy-request
flows: []
---

`pld:` = `phoenix_live_dashboard` 0.8.7 (`mix.lock:103`), `lib/phoenix/live_dashboard/` and `dist/js/app.js`.
`phx:` = `phoenix` 1.7.24 (`mix.lock:99`), `lib/phoenix/`. `ecto_sql:` = `ecto_sql` 3.13.2 (`mix.lock:32`),
`lib/ecto/adapters/sql.ex`. None is checked out in this repo; lines were read from the hex.pm tarballs of
those versions. No Lightning test exercises the request logger (no match for `request_logger` under `test/`).

## 1. Purpose

Superusers chasing a misbehaving request (a failing page, a webhook an external system says it sent)
need the server-side log of that one request without shell access to the host. The request logger
lets them mint a short-lived token on the dashboard and see, live in that tab, every log line of any
request that carries it. Because the token, not the requester's identity, is the only gate, it is
also a way to watch other users' and anonymous callers' requests, so what the stream carries and how
long a token lives are the security surface.

## 2. What it does

1. A superuser opens the request logger on the admin dashboard and gets a live stream and a token that lasts one hour, as a link or as a cookie set in their own browser.
2. Any request to the instance carrying that token, from anyone, signed in or not, including an outside system calling a webhook, has its server log lines sent to the stream; requests without a valid token, or with an expired one, are never sent.
3. The superuser's tab shows the lines as they arrive, for as long as the tab stays open and the token is under an hour old.
4. On a normal production instance the lines show what was called and how it ended, not the values sent; with extra logging switched on, form fields like passwords are masked.

**Straightforwardness: 3 of 5.** The idea is simple once explained, but the token is the only gate, it travels further than the dashboard, and switching it off doesn't do quite what it says.

### Most surprising behaviours

- **(2)** With extra logging switched on, the stream also shows database queries with their real values, so a superuser can see other people's emails, credential values and data in plain text; only form fields are masked. (6.1)
- **(2)** A token sent on a webhook or channel request is saved with the incoming data, and on a channel request it is passed on to the outside system, so the link keeps working for its hour wherever it ends up. (6.2)
- **(3)** "Disable cookie" may not actually remove the cookie, so the button says capture is off while requests are still being captured until the hour runs out. (6.1)
- **(3)** Tokens can't be revoked. Starting a new stream gives a new token but every earlier link keeps working for its full hour. (6.2)
- **(3)** Only the first load of a page is captured. Clicks on that page afterwards, the workflow editor, and background work started by the request never appear, and nothing is kept once the tab reloads. (6.2)

## 3. Who can do what

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| Open the request logger page and mint a stream and token | no | no | no | yes |
| Subscribe to an existing stream by its id | no | no | no | yes |
| Have a request streamed, by carrying a valid token | yes | yes | yes | yes |
| See streamed lines | no | no | no | yes, in a tab on that stream |
| Revoke a token before its hour | no | no | no | no |

Sources: `router.ex:358-369`; shared-admin-space S04, S05; `endpoint.ex:65-67`, `:99`, `:109`;
`pld:request_logger.ex:25-56`; `pld:pages/request_logger_page.ex:8-41`.

**Preconditions beyond role**
- The token must verify against the endpoint's `secret_key_base` with salt `"request_logger"` and be under 3600 seconds old (`pld:request_logger.ex:9`, `:50`, `:69-71`).
- The request must reach `endpoint.ex:65`: static files (`:43-50`) and socket traffic (`:18-36`; `phx:endpoint.ex:493`) never do.
- Only lines logged by the request's own process are carried, since the routing is per-process Logger metadata (`pld:request_logger.ex:54`; `pld:logger_pubsub_backend.ex:5-11`).
- Only lines at or above the primary logger level pass: `:info` in prod unless `LOG_LEVEL` is set (`config/prod.exs:16`; `bootstrap.ex:487-505`).

## 4. What it touches

**Reads**: the request's query string and cookies, parsed for every request before anything else (`pld:request_logger.ex:35`, `:43`); the endpoint secret to verify the token

**Writes**: none in the database by the flow itself. The cookie mode writes a `request_logger` cookie in the superuser's browser from JavaScript: `path=/`, `samesite=strict` only over https, no expiry, not HttpOnly (`pld:dist/js/app.js` line 15, function `hu`)

**Immediate side effects**
- Hop 1 (dashboard): `Phoenix.PubSub.subscribe` to `phx_dashboard:request_logger:<stream>` on a connected mount (`pld:pages/request_logger_page.ex:14-19`); a 3-byte random stream id (`:39`)
- Hop 2 (any request): `Logger.metadata(logger_pubsub_backend: {Lightning.PubSub, topic})` in the request process (`pld:request_logger.ex:52-54`; `config/config.exs:38`)
- Hop 3 (every log event in that process): the node-wide `:logger` handler formats the event and `Phoenix.PubSub.broadcast`s it (`pld:application.ex:18-26`; `pld:logger_pubsub_backend.ex:5-11`)
- Hop 4 (dashboard): each message is appended to the page's stream (`pld:pages/request_logger_page.ex:58-59`)

**Deferred side effects**
- A webhook called with `?request_logger=<token>` stores the token in the dataclip's `request.query_params` (`webhooks_controller.ex:53-55`, `:233-238`)
- A channel request stores the query string, token included, as `request_query_string` (`channel_proxy_plug.ex:221`; `handler.ex:118`)

**External, non-transactional effects**
- A channel request forwards the query string, token included, to the tenant's destination (`channel_proxy_plug.ex:238-246`; flow-channel-proxy-request url_params). The cookie is stripped (`channel_proxy_plug.ex:283-287`)

**Depends on config**
- Logger level decides which lines exist to stream (`config/prod.exs:16`; `bootstrap.ex:487-505`)
- `:phoenix, :filter_parameters` masks Phoenix's "Parameters" line only (S06; 6.1)
- `Lightning.Repo` logs queries at `:debug` (`config/config.exs:22-24`), so SQL with bind values reaches the stream only under debug-logging

**Product limits**
- A token captures for one hour from signing (`pld:request_logger.ex:9`)
- LiveView events after connect, the collaborative editor, worker traffic and background jobs are not captured (6.2)
- Lines are shown only to a tab subscribed at the time; nothing is kept (6.2)

## 5. Scenarios

Steps on the dashboard page itself (the redirect to `?stream=`, the link and the button) are
admin-live-dashboard S07. Who can open the page is shared-admin-space S04, S05.

```gherkin
Feature: Request logger
  In order to read the server log of one specific request without host access
  As a superuser
  I want requests carrying a token I minted to stream their log lines to my dashboard tab

  @S01 @pending
  Scenario: A superuser captures their own requests with the cookie
    # Value: an operator reproducing a problem in their own browser sees the server side of each step as it happens.
    Given I am a superuser with "/dashboard/request_logger" open
    When I press "Enable cookie"
    And in a second tab of the same browser I visit "/projects"
    Then the first tab eventually shows a line containing "GET /projects"
    And a line containing "Sent 200"
    # pld:pages/request_logger_page.ex:63-65, :136-185; pld:dist/js/app.js line 15 (hu sets the cookie)
    # pld:request_logger.ex:40-56; endpoint.ex:65-73; phx:logger.ex:217-228 (method and request_path), :231-249

  @S02 @pending
  Scenario: A link captures a request from someone who is not signed in, including a webhook
    # Value: an operator can capture the log of a request they cannot make themselves, such as an external system's webhook call.
    Given I am a superuser with "/dashboard/request_logger" open
    And workflow "Intake" has an enabled webhook trigger
    When an HTTP client with no Lightning session sends "POST /i/<trigger id>?request_logger=<token from my page>"
    Then my tab eventually shows a line containing "POST /i/<trigger id>"
    And that line does not contain the token
    # endpoint.ex:65-67 runs before WebhookAuth (:91), Plug.Session (:99) and Router (:109)
    # pld:request_logger.ex:32-38, :48-56; phx:logger.ex:224-225 (request_path only, no query string)

  @S03 @pending
  Scenario: A request without a valid token is not streamed
    # Value: other people's requests reach a superuser's screen only when the request carries a token that superuser minted.
    Given I am a superuser with "/dashboard/request_logger" open
    When another user visits "/projects" with no request_logger parameter or cookie
    And another user visits "/projects?request_logger=tampered"
    Then my tab shows no line for either request
    # pld:request_logger.ex:48-56 (is_binary and Phoenix.Token.verify, else no metadata)

  @S04 @pending
  Scenario: A token stops capturing after an hour
    # Value: a link pasted into a ticket, chat or browser history stops exposing requests to the dashboard after an hour.
    Given I minted a request logger link more than one hour ago
    And I have that stream open on "/dashboard/request_logger?stream=<id>"
    When anyone visits "/projects" with that link's parameter
    Then my tab shows no line for that request
    # pld:request_logger.ex:9, :50 (max_age 3600)

  @S05 @pending
  Scenario: On a default production instance the stream carries no parameters or SQL
    # Value: under the default log level, a captured request shows what was called and how it ended, not the values it carried.
    Given the instance runs with the default production log level
    And I am a superuser with the cookie enabled on "/dashboard/request_logger"
    When I submit a form in a second tab
    Then my tab shows the request line and the "Sent" line
    And no line contains "Parameters:" or "QUERY"
    # config/prod.exs:16; phx:logger.ex:277-305 and phx:router/scope.ex:16 (Parameters at :debug); config/config.exs:22-24 (Repo log :debug)

  @S06 @pending @variant:debug-logging
  Scenario: Under debug logging the parameters line masks filtered fields
    # Value: passwords, tokens and secrets typed into a form are masked even when the stream carries parameter lines.
    Given the instance runs with LOG_LEVEL "debug"
    And I am a superuser with the cookie enabled on "/dashboard/request_logger"
    When I submit a form with a field named "password" in a second tab
    Then my tab shows a "Parameters:" line with "password" => "[FILTERED]"
    # config/prod.exs:19-30; phx:logger.ex:164-167, :307-308; bootstrap.ex:487-505
    # the same request's QUERY lines are not filtered (6.1)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `filter_parameters` is not honoured for SQL: under debug logging Ecto's `QUERY` line prints bind values with `inspect(params)`, so a captured request shows emails, token hashes, credential and dataclip values it reads or writes, for any user's or anonymous request carrying the token | `config/config.exs:22-24`; `ecto_sql:sql.ex:1351-1366`; filter applies only at `phx:logger.ex:307-308` | a superuser's tab showing unmasked values from other people's requests | decide (owner: security) |
| "Disable cookie" probably leaves the cookie in place: the hook sets it with `path=/` but clears it without a path, which the browser scopes to `/dashboard`, so the original cookie is not removed and the browser keeps sending it until the token's hour ends | `pld:dist/js/app.js` line 15 (`hu` vs `du`); `pld:pages/request_logger_page.ex:161-168`; read from code, not tried in a browser | the button reads "Enable cookie" while requests are still being captured | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The plug runs on every request before session, auth and routing, including `/i/*` webhooks, `/channels/*`, the APIs and login; the token is the only gate, so a superuser who hands out a link captures other users' and anonymous requests | `endpoint.ex:65-67`, `:76`, `:91`, `:99`, `:109`; `pld:request_logger.ex:25-56` | decide (owner: security) |
| Enabled by library default; Lightning never passes `request_logger:` | `router.ex:363-369`; `pld:router.ex:235-248` | decide (owner: security) |
| Socket traffic is never captured: `/live`, `/socket` and `/worker` are dispatched before endpoint plugs, so only a LiveView's first HTTP render is streamed, not its events, and worker and editor channel traffic is invisible | `endpoint.ex:18-36`; `phx:endpoint.ex:493`, `:683` | preserve |
| Work handed to another process (Oban jobs, Tasks, GenServer calls) is not captured; Logger metadata is per process and Task does not copy it | `pld:request_logger.ex:54`; `pld:logger_pubsub_backend.ex:6` | preserve |
| Tokens are stateless and cannot be revoked; "Start a new stream" mints a new one but earlier links keep working for their hour | `pld:request_logger.ex:48-56`; `pld:pages/request_logger_page.ex:188-194` | decide (owner: security) |
| Param and cookie tokens use the same salt `"request_logger"`, so either value works in either place | `endpoint.ex:66-67`; `pld:request_logger.ex:50`, `:69-71` | preserve |
| Any superuser who opens `/dashboard/request_logger?stream=<id>` receives that stream; the id is 3 random bytes | `pld:pages/request_logger_page.ex:8-19`, `:39` | preserve |
| Lines are not stored; a broadcast with no subscribed tab is dropped, and a reload starts with an empty list | `pld:logger_pubsub_backend.ex:9`; `pld:pages/request_logger_page.ex:32-33` | preserve |
| The token rides along in data Lightning keeps or forwards: webhook dataclip `request.query_params`, channel `request_query_string`, and the channel destination's URL | `webhooks_controller.ex:233-238`; `channel_proxy_plug.ex:221`, `:238-246`; `handler.ex:118` | decide |
| Every request's query string and cookies are parsed by this plug first, so a malformed query string fails here, before Lightning's own plugs | `pld:request_logger.ex:35`, `:43` | preserve |
| The cookie is a browser-session cookie written by JavaScript: not HttpOnly, `samesite=strict` only over https, scoped to the current host | `pld:dist/js/app.js` line 15; `pld:router.ex:54-59` | preserve |
| Broadcasts go through `Lightning.PubSub`, so a request served by another clustered node should reach a tab on this node; not tried | `config/config.exs:38`; `application.ex:176`; `pld:request_logger.ex:52-54` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Disabled "Request Logger" menu link | `pld:pages/request_logger_page.ex:49-51` | the plug is installed (`endpoint.ex:65-67`), so `param_key(conn)` is never nil (`pld:router.ex:426-432`) |
| `:parent` cookie domain branch | `pld:pages/request_logger_page.ex:203-205` | `request_logger_cookie_domain` not passed (`router.ex:363-369`) |
| `Logger.add_backend` gen_event path | `pld:application.ex:28-30`; `pld:logger_pubsub_backend.ex:13-63` | Elixir 1.18 (`.tool-versions`) exports `Logger.default_formatter/0`, so the `:logger` handler branch at `:18-26` is compiled |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Token max age 3600 seconds | `pld:request_logger.ex:9` | yes, capture stops after an hour (S04) | preserve |
| No cap on lines held in the page; the DOM grows for as long as the tab stays open | `pld:pages/request_logger_page.ex:32-33`, `:58-59`, `:84-88` | yes, a busy cookie session slows the tab | decide |
| Every log event on the node passes through the handler, which checks metadata before formatting | `pld:application.ex:21-25`; `pld:logger_pubsub_backend.ex:5-6` | no | preserve |

### 6.5 Things seen but not understood

- `filter_parameters` (verified): honoured for Phoenix's "Parameters" line in phoenix 1.7.24 (`phx:logger.ex:307-308`); not honoured by ecto_sql 3.13.2 (6.1). Not verified: phoenix_live_view 1.0.19's own debug lines for the first render, Lightning's `Logger` calls in request processes (for example `webhooks_controller.ex:168-171`, `:202-204` log ids only; the rest of `lib/` was not audited), and crash reports from a request process.
- Whether streamed lines use Lightning's console format and metadata (`config/config.exs:162-181`, which includes `user_id` and `project_id`): the handler uses `Logger.default_formatter(colors: [enabled: false])` (`pld:application.ex:24`); whether Elixir 1.18 builds that from `:console` config was not checked.
- The token is signed inside `render` (`pld:pages/request_logger_page.ex:119`, `:157`, `:199-201`). If change tracking re-evaluates it on later renders, the hour counts from the last render, not from opening the page; not checked against LiveView 1.0.19.
- Whether `Sentry.PlugContext` (`endpoint.ex:88-89`) records the full URL, token included, on errors was not checked against sentry 13.2.0.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the request logger stay enabled, and if so should the query-parameter mode go, so only the superuser's own browser can be captured (6.2 rows 1, 2)? (owner: security)
- Should captured streams be limited to info level, or SQL bind values be redacted, given Ecto ignores `filter_parameters` (6.1 row 1)? (owner: security)
- Should tokens be revocable, or end when the dashboard tab closes (6.2 row 5)? (owner: security)
- Should the token be stripped from the query string before webhooks store it and channels forward it (6.2 row 9)? (owner: security)
- Should minting a stream be audited, since it enables watching other users' requests? (owner: security)

## Proposed flows

- none. Referenced: flow-channel-proxy-request (forwards and stores the query string, token included).

## Proposed shared

- none. Referenced: shared-admin-space (S04, S05), shared-authenticated-session (S01 to S03).

Summary
- Scenarios: 6 (S01 to S06, all @pending; S06 @variant:debug-logging).
- Section 6: 6.1 2, 6.2 12, 6.3 3, 6.4 3, 6.5 4.
- Flows: none proposed; referenced flow-channel-proxy-request.
- Shared: none proposed; referenced shared-admin-space, shared-authenticated-session.
- Unsure: "Disable cookie" path bug and token re-signing on render are read from code only; streamed line format and LiveView debug-line filtering not verified.
