---
id: admin-live-dashboard
type: view
title: System dashboard (Phoenix LiveDashboard)
status: not-started
owner:

trigger:
  old_route: /dashboard (redirects to /dashboard/home; pages at /dashboard/:page and /dashboard/:node/:page)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the HTTP request passes `[:browser, :require_authenticated_user, :require_superuser]` (`lib/lightning_web/router.ex:358-361`; `controllers/user_auth.ex:288-311`, `:415-438`)
    - the socket mount passes `{LightningWeb.InitAssigns, :default}` then `{LightningWeb.Hooks, :ensure_admin}` (`router.ex:365-368`; `init_assigns.ex:17-35`; `hooks.ex:40-53`)
    - entered from "Sys Info" in the project side menu, shown to superusers only (`components/layouts/live.html.heex:45-58`; shared-project-header S17); the admin settings layout has no link to it (shared-admin-space 6.2)

inherits:
  - shared-admin-space               # gate scenarios S04 (HTTP refusal) and S05 (socket mount hooks) only; this page does not use the settings layout or admin menu
  - shared-authenticated-session     # S01 (signed-out visitor to log in; asserted for /dashboard at live_dashboard_test.exs:6-11), S02, S03 and the lockout gate; no layout, sidebar or banners render here (see 6.2)

url_params:
  - name: request_logger              # query param on ANY Lightning URL, read by the endpoint plug (endpoint.ex:65-67)
    set_by: admin-live-dashboard      # the signed link shown on /dashboard/request_logger (pld:pages/request_logger_page.ex:104-119)
    effect: streams that request's log lines to the dashboard tab that generated the token, for 1 hour (pld:request_logger.ex:9, :48-56)
  - name: stream                      # /dashboard/request_logger?stream=<id>
    set_by: admin-live-dashboard      # the page redirects to itself with a fresh stream id (pld:pages/request_logger_page.ex:38-41)
    effect: subscribes the page to that stream's log topic (pld:pages/request_logger_page.ex:8-30, :58-59)
  - name: ":node path segment"
    set_by: admin-live-dashboard      # the library's node selector
    effect: shows the chosen page for another connected cluster node (pld:router.ex live "/:node/:page"; application.ex:103-123)

config_variants:
  default: {}                         # read under this one; prod logger level :info (config/prod.exs:16), LOG_LEVEL override in bootstrap.ex:487-505

inventory:
  routes:
    - live_dashboard /dashboard  Phoenix.LiveDashboard.PageLive   # router.ex:363-369; expands to live "/", "/:page", "/:node/:page" and GET "/css-:md5", "/js-:md5" in live_session :live_dashboard (pld:router.ex macro, :325-333)
  events:
    - Phoenix.LiveDashboard.RequestLoggerPage#toggle_cookie       # pld:pages/request_logger_page.ex:63-69
    - Phoenix.LiveDashboard.RequestLoggerPage#toggle_autoscroll   # pld:pages/request_logger_page.ex:71-72
    - library table sort, search, limit and modal events on every page (third party, not catalogued per event)
  js_hooks:
    - PhxRequestLoggerMessages       # pld:pages/request_logger_page.ex:82 (library bundle)
    - PhxRequestLoggerQueryParameter # pld:pages/request_logger_page.ex:111
    - PhxRequestLoggerCookie         # pld:pages/request_logger_page.ex:154
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), via LightningWeb.Hooks :ensure_admin (hooks.ex:40-53)
    - LightningWeb.UserAuth.require_superuser plug (user_auth.ex:415-438)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - live_dashboard option metrics: LightningWeb.Telemetry (router.ex:364; telemetry.ex:27-98)
    - live_dashboard option on_mount (router.ex:365-368)
    - endpoint plug Phoenix.LiveDashboard.RequestLogger, param_key "request_logger", cookie_key "request_logger" (endpoint.ex:65-67)
    - :lightning, :ecto_repos [Lightning.Repo] (config/config.exs:11), used by Ecto stats auto-discovery
    - extra_applications :os_mon (mix.exs:65), enables the OS data page
    - dependency ecto_psql_extras (mix.exs:115), enables Ecto stats for Postgres
    - :logger level (config/prod.exs:16; bootstrap.ex:487-505), bounds what the request logger can stream
    - :phoenix, :filter_parameters (config/prod.exs:19-30)
    - options NOT passed, so library defaults apply: allow_destructive_actions (false), env_keys (none), metrics_history (none), additional_pages (none), home_app ({"Dashboard", :phoenix_live_dashboard}), ecto_repos (auto), request_logger (enabled), request_logger_cookie_domain (current host), csp_nonce_assign_key (none), live_session_name (:live_dashboard)
  not_reachable_here:
    - Phoenix.LiveDashboard.ProcessInfoComponent#kill and its "Kill process" button (pld:info/process_info_component.ex:61-63, :82-84); allow_destructive_actions is not set (see S05)
    - EctoPSQLExtras kill_all and mandelbrot tables (pld:pages/ecto_stats_page.ex:191-195); filtered by the library (see S06)
    - Home page environment variables card (pld:system_info.ex:753); env_keys is not set (see S04)
    - Hooks :ensure_admin nil-user clause and require_superuser JSON branch; owned by shared-admin-space 6.3
    - InitAssigns sidebar_toggle hook and banner assigns; attached on mount but nothing on this page renders or sends them (6.2)

related:
  - shared-admin-space
  - shared-project-header            # "Sys Info" entry point (S17)
  - workflow-health                  # not a surface; the history page emits the lightning.ui.history metric charted here (run_live/index.ex:204-215)
flows:
  - flow-account-revocation-teardown # demotion drops the open dashboard socket (S08); this view should be added to its surfaces
  - flow-dashboard-request-logger
---

## 1. Purpose

Superusers who run a Lightning instance use the system dashboard to see how the running server is
doing: memory, processes, request and database timings, the Postgres statistics and the logs of
specific requests. It is the only in-app view of the BEAM and the database, so without it an
operator chasing a slowdown or memory growth needs shell access to the host. Because it exposes
internals of the whole instance, the value is equally in what it hides and refuses: secrets in the
environment, and actions that could take the instance down.

## 2. What it does

- Superusers open the dashboard and see a summary of the running system
- Superusers browse OS, memory, application, process, port, socket, ETS and Postgres statistics
- Superusers watch Lightning's chosen request, database, VM and page-load metrics live
- Superusers capture the server log lines of chosen requests
- Superusers inspect other nodes in the cluster
- Environment variables are not shown
- Processes and database connections cannot be killed from the page
- Non-superusers and signed-out visitors can't open it (inherited)
- A superuser who is demoted loses the open dashboard

## 3. Who can do what

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| Open /dashboard and its pages | no (to log in) | no (to /projects) | no (to /projects) | yes |
| See "Sys Info" link in the project side menu | n/a | no | no | yes |
| Browse system, process and database statistics | no | no | no | yes |
| Watch metrics | no | no | no | yes |
| Generate a request logger link or cookie | no | no | no | yes |
| Kill a process | no | no | no | no |
| Kill database connections | no | no | no | no |
| See environment variables | no | no | no | no |

Sources: `router.ex:358-369`; `user_auth.ex:288-311`, `:415-438`; `hooks.ex:40-53`; `policies/users.ex:19-21`; `live.html.heex:45-58`; `pld:router.ex:307`, `pld:info/process_info_component.ex:61-63`; `pld:pages/ecto_stats_page.ex:191-195`; `pld:router.ex:29-31`. Support access is a separate flag the policy ignores (shared-admin-space section 3).

**Preconditions beyond role**
- Revoked, TOTP-pending and locked-out sessions are refused first by shared-authenticated-session (`user_auth.ex:302-306`; `init_assigns.ex:22-30`).
- Two checks: the HTTP plug (`router.ex:361`) and the socket mount hooks (`router.ex:365-368`); see shared-admin-space S04, S05.
- A request logger link works for whoever opens it, signed in or not, for 1 hour after it is generated; the token, not the opener's role, is the gate (`endpoint.ex:65-67`; `pld:request_logger.ex:9`, `:48-56`). See 6.2 and section 8.

`pld:` = `phoenix_live_dashboard` 0.8.7 (`mix.lock:103`), `lib/phoenix/live_dashboard/`. The dependency is not checked out in this repo; lines were read from the hex.pm tarball of that version.

## 4. What it touches

**Reads**: session user and `users.preferences` via InitAssigns (`init_assigns.ex:18-20`, `:38-39`); BEAM process, port, socket, ETS, allocator and application info (library); OS data through `os_mon` (`mix.exs:65`); Postgres catalogue and statistics views for `Lightning.Repo` through `ecto_psql_extras` (`mix.exs:115`, `config/config.exs:11`); telemetry events listed in `telemetry.ex:27-98`

**Writes**: none in the database. The request logger cookie `request_logger` is written to the superuser's browser by the library hook (`pld:pages/request_logger_page.ex:136-175`)

**Immediate side effects**
- Refusals set flash `:nav` and redirect; owned by shared-admin-space S04, S05
- Generating a request logger stream subscribes the page to PubSub topic `phx_dashboard:request_logger:<stream>` (`pld:request_logger.ex:58-61`; `pld:pages/request_logger_page.ex:8-30`)

**Deferred side effects**
- Every later request carrying a valid `request_logger` param or cookie, on any route of the endpoint, sets Logger metadata so its log lines are broadcast to that topic (`endpoint.ex:65-67`; `pld:request_logger.ex:25-56`); handed to flow-dashboard-request-logger

**External, non-transactional effects**
- none

**Depends on config**
- `:logger` level (`config/prod.exs:16`, `bootstrap.ex:487-505`) decides which log lines a request logger stream can carry
- `:ecto_repos` (`config/config.exs:11`) decides which repo Ecto stats shows
- libcluster topology (`application.ex:103-123`) decides which nodes are selectable

**Product limits**
- Metrics charts start empty and only show data collected while the page is open (no `metrics_history`, `router.ex:363-369`; `pld:router.ex:41-45`)
- A request logger link or cookie expires after 1 hour (`pld:request_logger.ex:9`)

## 5. Scenarios

```gherkin
Feature: System dashboard
  In order to diagnose the running instance without shell access
  As a superuser
  I want a live view of the server, its metrics and its database, that cannot leak secrets or take the instance down

  @S01 @pending
  Scenario: A superuser opens the system dashboard
    # Value: instance operators can check the health of the running server from the browser.
    Given I am a superuser
    When I visit "/dashboard"
    Then I am on "/dashboard/home"
    And I see "Home"
    # router.ex:358-369; live_dashboard_test.exs:33-47 (asserts the redirect and that the page contains "Home")

  @S02 @pending
  Scenario: The dashboard offers the system, process and database pages
    # Value: operators can follow a memory, process or database problem to its source in one place.
    Given I am a superuser
    When I open "/dashboard/home"
    Then the dashboard menu offers "OS Data", "Memory Allocators", "Metrics", "Request Logger", "Applications", "Processes", "Ports", "Sockets", "ETS" and "Ecto Stats"
    When I open "Ecto Stats"
    Then I see statistics for "Lightning.Repo"
    # pld:router.ex:379-395 (page list; no additional_pages passed, router.ex:363-369)
    # OS Data needs os_mon (mix.exs:65); Ecto Stats needs ecto_psql_extras (mix.exs:115) and auto-discovers repos (pld:pages/ecto_stats_page.ex:18, :35-45; config/config.exs:11)

  @S03 @pending
  Scenario: The metrics page charts Lightning's request, database, VM and page-load metrics
    # Value: when the instance is slow, operators can see whether time goes to the router, to waiting for a database connection, or to the query itself.
    Given I am a superuser
    When I open "/dashboard/metrics"
    Then I see charts for "phoenix.endpoint.stop.duration" and "phoenix.router_dispatch.stop.duration" by route
    And I see charts for "lightning.repo.query.total_time", "decode_time", "query_time", "queue_time" and "idle_time"
    And I see charts for "vm.memory.total" and "vm.total_run_queue_lengths" total, cpu and io
    And I see charts for "lightning.ui.history"
    When a user loads a project's history page
    Then eventually the "lightning.ui.history" chart shows a new point
    # telemetry.ex:27-98; router.ex:364; history span emitted at run_live/index.ex:204-215
    # the lightning.api.webhook charts are listed in telemetry.ex:69-84 but never receive data (6.1)

  @S04 @pending
  Scenario: The home page does not show environment variables
    # Value: secrets passed to the instance through the environment (database URL, worker secret, signing keys) are never rendered in a browser, even to a superuser whose session is hijacked.
    Given I am a superuser
    When I open "/dashboard/home"
    Then I do not see an environment variables section
    # env_keys not passed (router.ex:363-369); pld:router.ex:29-31, :164-175; pld:system_info.ex:753

  @S05 @pending
  Scenario: A process cannot be killed from the dashboard
    # Value: nobody, including a superuser or a hijacked superuser session, can crash the scheduler, the worker queue or the database pool from a browser.
    Given I am a superuser
    When I open "/dashboard/processes"
    And I open the details of any process
    Then I see the process details
    And I do not see a "Kill process" button
    # allow_destructive_actions not passed, defaults to false (router.ex:363-369; pld:router.ex:61-66, :307)
    # pld:info/process_info_component.ex:61-63; the kill handler asserts the flag (:82-84)

  @S06 @pending
  Scenario: Ecto stats cannot terminate database connections
    # Value: the database connections that run workflows and serve users cannot be dropped from a browser.
    Given I am a superuser
    When I open "/dashboard/ecto_stats"
    Then I do not see a "Kill all" table
    # pld:pages/ecto_stats_page.ex:191-195 (kill_all and mandelbrot rejected by the library, not by Lightning config)

  @S07 @pending
  Scenario: A superuser starts capturing request logs
    # Value: an operator can see the server-side log of the exact request that is misbehaving, without host access.
    Given I am a superuser
    When I open "/dashboard/request_logger"
    Then I am on a request logger page with a stream id in the URL
    And I see a link with a "request_logger" query parameter
    And I see an "Enable cookie" button
    And the flow "flow-dashboard-request-logger" has started
    # pld:pages/request_logger_page.ex:8-41, :104-175; endpoint.ex:65-67

  @S08 @pending
  Scenario: Demoting a superuser with the dashboard open hands off to the revocation flow
    # Value: removing superuser rights also removes a live view of instance internals that is already open.
    Given "amara@example.org" is a superuser with "/dashboard/processes" open
    When another superuser changes her role to user and saves
    Then the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    # accounts.ex:181-201, :204-216 (role change revokes "session" tokens, then disconnect_user_sockets);
    # the dashboard rides the same /live socket (endpoint.ex:18-21; pld:router.ex:142 live_socket_path defaults to "/live")
    # on reconnect InitAssigns (init_assigns.ex:22-24) and :ensure_admin (hooks.ex:40-53) refuse her
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The `lightning.api.webhook` summary and distribution listen for `[:lightning, :workorder, :webhook, :stop]`, which nothing in `lib/` emits | `telemetry.ex:69-84`; no emitter (grep of `lib/` for the event finds only these lines) | two webhook charts on the metrics page that stay empty however much webhook traffic arrives | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The request logger plug runs on every request to the endpoint, before routing and auth, including `/i/*` webhooks and the APIs; a valid `?request_logger=` link streams that request's logs to the superuser's tab whoever opens it, so a superuser can capture another user's or an anonymous caller's request logs | `endpoint.ex:65-67`; `pld:request_logger.ex:25-56` | decide |
| The request logger is on because the library enables it by default; Lightning never passes `request_logger:` | `router.ex:363-369`; `pld:router.ex:51-52`, `:235-248` | decide |
| The dashboard runs in the library's own live_session `:live_dashboard` with its own root layout: no Lightning sidebar, menu, flash, banners or Back link | `router.ex:363-369`; `pld:router.ex:325-333` | decide |
| InitAssigns on this route reads the `sidebar_collapsed` preference, assigns banners and attaches a `toggle_sidebar` hook, none of which the dashboard renders or sends | `router.ex:366`; `init_assigns.ex:37-57` | preserve |
| HTTP refusal shows the "No Access" card without Back (`:no_access_no_back`); a socket refusal by the hook shows it with Back. Recorded by shared-admin-space 6.2 | `user_auth.ex:433`; `hooks.ex:50` | decide |
| The home page shows "Dashboard" and the LiveDashboard version, not Lightning's name and version, because `home_app` is not passed | `router.ex:363-369`; `pld:router.ex:33-34`, `:177-189` | decide |
| `/dashboard/:node/:page` lets a superuser inspect any node joined through libcluster | `application.ex:103-123`; pld router macro `live "/:node/:page"` | preserve |
| Ecto stats auto-discovers the repo from `:ecto_repos` rather than naming it | `config/config.exs:11`; `pld:pages/ecto_stats_page.ex:18`, `:35-45` | preserve |
| "Sys Info" uses a warning triangle icon for a monitoring page; owned by shared-project-header S17 | `live.html.heex:51-57` | decide |
| The request logger cookie is scoped to the current host (no `request_logger_cookie_domain`) | `router.ex:363-369`; `pld:router.ex:54-59` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `LightningWeb.Telemetry`'s own `:telemetry_poller` child with an empty measurement list | `telemetry.ex:16-22`, `:100-106` | `periodic_measurements/0` returns `[]`, so the poller measures nothing; the `vm.*` charts are fed by telemetry_poller's default poller (see 6.5) |
| `function_exported?(Routes, :live_dashboard_path, 2)` guard around "Sys Info" | `live.html.heex:50` | the `live_dashboard` route is declared unconditionally (`router.ex:358-370`), so the helper always exists |
| Commented-out `ConsoleReporter` child and `count_users` measurement | `telemetry.ex:20-21`, `:102-104` | comments only |
| "Kill process" button and `kill` handler | `pld:info/process_info_component.ex:61-63`, `:82-84` | `allow_destructive_actions` is false (S05) |
| `kill_all` table | `pld:pages/ecto_stats_page.ex:191-195` | rejected by the library (S06) |
| `:ensure_admin` nil-user clause; `require_superuser` JSON branch | `hooks.ex:31-38`; `user_auth.ex:424-429` | owned by shared-admin-space 6.3 |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Metrics hold no history; charts are empty on open and lost on reload | `router.ex:363-369`; `pld:router.ex:41-45` | yes, empty charts | preserve |
| Request logger tokens expire after 3600 seconds | `pld:request_logger.ex:9`, `:50` | yes, a link stops streaming after an hour | preserve |
| Logger level `:info` in prod, so debug lines (including Phoenix's parameter lines) do not reach a request logger stream unless `LOG_LEVEL` is lowered | `config/prod.exs:16`; `bootstrap.ex:487-505` | yes, fewer lines than in dev | preserve |
| Ecto stats runs catalogue and statistics queries against the production database on every page refresh | `pld:pages/ecto_stats_page.ex:193-198` | no | decide |

### 6.5 Things seen but not understood

- The `vm.memory.total` and `vm.total_run_queue_lengths.*` metrics appear to rely on the telemetry_poller application's default poller, since Lightning's own poller measures nothing (`telemetry.ex:16-22`, `:100-106`); not verified against telemetry_poller 1.3.0 (`mix.lock:136`), and no Lightning config disables or enables it.
- Ecto stats tables such as long running queries and outliers show SQL text; whether any Lightning query reaches Postgres with literal values (emails, payload fragments) rather than parameters was not checked.
- Whether the request logger stream honours `:phoenix, :filter_parameters` (`config/prod.exs:19-30`) when `LOG_LEVEL` is set to debug was not checked; the filter applies to Phoenix's own parameter logging, but other log lines a request emits could carry data.
- Other telemetry events Lightning emits (`[:lightning, :fetch_metadata]` at `metadata_service.ex:49-55`, `[:lightning, :accounts, :superuser_changed]` at `accounts.ex:250-258`, `retry.ex`, the PromEx plugins) are not charted here; unclear whether that is deliberate (PromEx at `/metrics` is the intended sink) or an omission.
- `live_dashboard_test.exs:17` is named "routes the user to '/'" but asserts `/projects` (`dashboard_index_path`, `:20`); the behaviour is covered by shared-admin-space S04.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the request logger stay enabled, and if so should the query-parameter mode be disabled so a superuser cannot capture logs of other users' or anonymous requests (6.2 rows 1 and 2)? (owner: security)
- Should the rebuild keep `allow_destructive_actions` off and keep `env_keys` unset, and should that be enforced by a test rather than by the library default (S04, S05)? (owner: security)
- Should Ecto stats be exposed, given it shows live SQL text and runs statistics queries on the production database (6.4, 6.5)? (owner: security)
- Should the dashboard keep LiveDashboard and its own layout, or become a Lightning page inside the admin frame with a Back link (6.2)? (owner: product)
- Should the empty `lightning.api.webhook` metric be wired to the webhook controller or removed (6.1)? (owner: engineering)
- flow-account-revocation-teardown does not list admin-live-dashboard in its surfaces; should it, given S08? (owner: engineering)

## Proposed flows

- flow-dashboard-request-logger: a superuser generates a signed request logger link or enables the cookie on /dashboard/request_logger, then a request in another tab or another person's browser (any route, including webhooks and APIs, signed in or not) carries the token and its log lines appear live on the original dashboard tab until the token expires after an hour. Surfaces: admin-live-dashboard, plug:endpoint-request-logger (`endpoint.ex:65-67`), any Lightning route, pubsub:phx_dashboard:request_logger:<stream>.

Referenced: flow-account-revocation-teardown (S08).

## Proposed shared

none. References shared-admin-space (S04, S05 only) and shared-authenticated-session (S01 to S03, lockout).

## Lead resolution (batch 11)

- `flow-dashboard-request-logger` created. admin-live-dashboard added to flow-account-revocation-teardown surfaces.
