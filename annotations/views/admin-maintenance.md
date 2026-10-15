---
id: admin-maintenance
type: view
title: Admin settings › Maintenance
status: not-started
owner:

trigger:
  old_route: /settings/maintenance
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session; the route sits in the `:settings` live_session, which mounts `InitAssigns` (`lib/lightning_web/router.ex:268`, `:280`)
    - the viewer passes `Users :access_admin_space` (superuser only); unlike the other admin views this module does not use the `:ensure_admin` hook and checks the policy itself in `mount` and in each `handle_event` (`lib/lightning_web/live/maintenance_live/index.ex:16-29`, `:32-66`, `:91-98`); the refusal is owned by shared-admin-space S02 (its 6.2 row "MaintenanceLive.Index does not use the hook")
    - entered from the "Maintenance" item in the admin side menu (`lib/lightning_web/components/layouts/settings.html.heex:76-82`; shared-admin-space S01)

inherits:
  - shared-admin-space                # gate (S02; this page is the exception that checks the policy itself, see its 6.2 and 6.3), settings layout and side menu (S01), active item :maintenance (index.ex:20)
  - shared-authenticated-session      # login redirect, revoked sessions, TOTP and lockout gates, sidebar; banners not on the settings layout
  - shared-flash-messages             # every result on this page is a flash; bottom toasts on the settings layout that stay until clicked (S07)
  - shared-project-header             # no-project parts only, as admin-projects: LayoutComponents.header (index.html.heex:2-4) carries the confirmation banner (S13, S14), account menu (S18), global picker (S04, S06, S08, S10 to S12)

url_params: []

config_variants:
  default: { lightning.Lightning.Adaptors.strategy: Lightning.Adaptors.NPM, refresh_interval: 3600000 }   # read under this one (config.ex:12-13, bootstrap.ex:1059-1078); tests run under StrategyMock (config/test.exs:109-123)
  local-adaptors: { ADAPTORS_STRATEGY: local, ADAPTORS_LOCAL_REPO: <path> }                                # bootstrap.ex:1067-1068, :1084-1114; local.ex:45-100
  refresh-disabled: { ADAPTORS_REFRESH_INTERVAL_SECONDS: 0 }                                              # bootstrap.ex:1106-1108; scheduler.ex:8-11, :247-250; this page and the mix task become the only way to refresh

inventory:
  routes:
    - live /settings/maintenance  MaintenanceLive.Index :index     # router.ex:280
  events:
    - MaintenanceLive.Index#refresh_adaptors                       # index.ex:32-50
    - MaintenanceLive.Index#refresh_icons                          # index.ex:52-66
    - MaintenanceLive.Index handle_async(:refresh_icons)           # index.ex:68-89 (not an event; async result)
  js_hooks: []
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), via MaintenanceLive.Index.superuser?/1 (index.ex:91-98)
  workers: []                                                      # no Oban; work runs on the cluster-singleton Lightning.Adaptors.Scheduler GenServer (scheduler.ex:1-21, supervisor.ex:95-131)
  api_endpoints: []
  emails: []
  config:
    - :lightning, Lightning.Adaptors :strategy (config.ex:33-35; ADAPTORS_STRATEGY, bootstrap.ex:1059-1078)
    - :lightning, Lightning.Adaptors :refresh_interval (config.ex:66-68; ADAPTORS_REFRESH_INTERVAL_SECONDS)
    - :lightning, Lightning.Adaptors :icon_path (config.ex:94-100; ADAPTORS_ICONS_PATH)
    - :lightning, Lightning.Adaptors :first_load_timeout (config.ex:107-110); not used by this page (refresh/2 without await)
    - :lightning, Lightning.Adaptors.Local :paths (bootstrap.ex:1114)
  not_reachable_here:
    - Lightning.Adaptors.refresh/2 `await: true` branch (adaptors.ex:324-326); only the mix task uses it (lib/mix/tasks/lightning.adaptors.refresh.ex:42)
    - Lightning.Adaptors.refresh_package/2 (adaptors.ex:341-350); only the mix task `--name` (lightning.adaptors.refresh.ex:66)
    - non-superuser branches of both handle_event clauses (index.ex:44-49, :60-65); see 6.3, already listed by shared-admin-space 6.3

related:
  - shared-admin-space
  - workflow-editor-canvas            # receives the adaptors_updated push (workflow_channel.ex:86, :957-958)
  - project-settings-credentials      # credential schema names rewritten by SchemaReconciler (credentials.ex:609-628)
  # capability, not yet annotated: the periodic adaptor refresh (Lightning.Adaptors.Scheduler :tick, scheduler.ex:247-261)
  # capability, not yet annotated: mix lightning.adaptors.refresh (lib/mix/tasks/lightning.adaptors.refresh.ex)
flows:
  - flow-adaptor-catalogue-update
---

## 1. Purpose

Superusers who run an instance use this page to pull the adaptor catalogue and adaptor icons up to
date on demand, instead of waiting for the hourly poll, restarting the app or opening a shell. Without
it, a newly published adaptor or version stays invisible to every workflow author on the instance
until the next poll, and a broken or outdated icon stays broken everywhere until someone with server
access intervenes.

## 2. What it does

- Superusers see the two maintenance actions on one page
- **Refresh the adaptor registry**
  - Superusers start a registry refresh and are told it was queued, or that it could not be started
  - A refresh started while another is running joins it instead of starting a second
- **Refresh adaptor icons**
  - Superusers start an icon refresh and see its result, with counts, or an error if it fails
  - An icon refresh changes icons only, never adaptor versions or metadata
  - Under the local adaptors strategy, icons are read from the local adaptors repo
- **Effects across the instance**
  - Changes from either refresh reach open workflow editors, node caches and credentials elsewhere on the instance

**Straightforwardness: 3 of 5.** Two buttons, but what each one reports doesn't always match what actually happened, and the effects land on every open editor on the instance.

### Most surprising behaviours

- **(2)** "Adaptor refresh queued." is the only message the registry refresh ever gives. If the refresh then fails upstream, the page says nothing, so the admin believes it worked. (6.1)
- **(2)** An icon refresh that takes over two minutes is reported as failed, but it keeps running and may still change the icons shortly after. On failure the "started" message also stays up beside the error. (6.1)
- **(3)** The registry card says "Re-fetch", but it only refetches adaptors whose version changed or whose schema is still missing; it can't force a fix for an adaptor that looks current. (6.2, 6.5)
- **(3)** Neither button is disabled while it runs, and each extra icon click starts another full refetch of every icon. Neither action leaves an audit record of who ran it. (6.2, 4)

## 3. Who can do what

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| See the page | no | no | no | yes |
| Refresh adaptor registry | no | no | no | yes |
| Refresh adaptor icons | no | no | no | yes |

Sources: `maintenance_live/index.ex:16-29`, `:32-35`, `:52-53`, `:91-98`; `policies/users.ex:19-21`; refusal and roles as in shared-admin-space section 3. Test: `test/lightning_web/live/maintenance_live/index_test.exs:12-21`.

**Preconditions beyond role**
- The policy is checked again on every click, not only on mount (`index.ex:33`, `:53`); the refusal branch is unreachable in practice (6.3).
- Both actions need the adaptors Scheduler to be reachable somewhere in the cluster; it is a `:global` singleton held through a Postgres advisory lock (`supervisor.ex:95-131`, `:209-210`), and an unreachable or timed-out Scheduler returns `{:error, :unavailable}` or `{:error, :timeout}` (`adaptors.ex:330-332`, `:361-363`).
- No re-auth, sudo window or confirmation step before either action.

## 4. What it touches

**Reads**: `adaptors` rows for the active source (`catalogue.ex:102-104`, schema `catalogue_adaptor.ex:70`), including stored icon etags (`scheduler.ex:806-822`); the session user's role.

**Writes**
- Registry refresh: `adaptors` and `adaptor_versions` upserted for each adaptor whose `latest_version` changed or whose schema is still missing inside the 1 hour grace window (`scheduler.ex:519-559`, `:604-622`, `:781-795`; `catalogue.ex:144`; `catalogue_adaptor_version.ex:32`); `adaptors.checked_at` touched for the rest (`scheduler.ex:529-531`, `catalogue.ex:204-214`); icon columns of rows not refetched (`scheduler.ex:478-486`).
- Icon refresh: only the icon columns (`icon_*_ext`, `icon_*_sha256`, `icon_*_etag`) and `updated_at` of rows whose icon bytes or etag changed (`scheduler.ex:401-424`, `:660-717`; `catalogue.ex:228-245`).
- Both: icon files on the local disk of the node running the Scheduler, under `Config.icon_path/0` (`scheduler.ex:628`, `:724`; `icon_cache.ex:1-17`; `config.ex:94-100`).

**Immediate side effects** (in the same request)
- Flash "Adaptor refresh queued." or "Refresh failed: <reason>" (`index.ex:35-41`).
- Flash "Icon refresh started.", then a second flash when the async result arrives (`index.ex:54-59`, `:68-89`).
- Audit: none. Neither action writes an audit event (`index.ex:1-99`; no `Auditing` call on the Scheduler path, `scheduler.ex:1-842`).

**Deferred side effects** (later, elsewhere)
- The Scheduler runs the work in a `Task.Supervisor.async_nolink` task, off the LiveView and off the Scheduler loop (`scheduler.ex:362-365`, `:389-399`, `:430-433`; `scheduler_test.exs:1126-1157`).
- Every row change broadcasts `{:changed, name, source}` on `adaptors:<instance>` (`scheduler.ex:685-689`, `:784-788`; `supervisor.ex:220-221`). On every node:
  - `Invalidator` drops the cached schema, icon meta, icon bytes, package list and catalogue for that adaptor (`invalidator.ex:41-47`);
  - `ChannelBroadcaster` coalesces changes for 250 ms and broadcasts `adaptors_updated` on `adaptors:client_update:<instance>` (`channel_broadcaster.ex:18`, `:59-75`; `supervisor.ex:227-228`);
  - every open `WorkflowChannel` (every user's collaborative editor, on every project) pushes `adaptors_updated` and the browser refetches the catalogue (`workflow_channel.ex:86`, `:957-958`; `assets/js/collaborative-editor/stores/createAdaptorStore.ts:276-286`);
  - `Credentials.SchemaReconciler` rewrites short-form `credentials.schema` names to full package names across every project (`schema_reconciler.ex:1-24`, `:56`, `:67-69`; `credentials.ex:609-628`).
- All of the above is handed to flow-adaptor-catalogue-update (proposed).
- Emails: none. Oban jobs: none.

**External, non-transactional effects**
- Default strategy: HTTP to the npm registry for the listing (`npm/registry.ex:35`, `:61`), jsDelivr for schemas (`npm/schema.ex:15`) and raw.githubusercontent.com for icons with `If-None-Match` from stored etags (`npm/github.ex:30`; `npm.ex:91-98`). The icon refresh lists the registry again before fetching icons (`npm.ex:94-97`).
- Local strategy: reads the local adaptors repo from disk (`local.ex:45-100`).
- Icon files written to disk are not rolled back if the row update fails (`scheduler.ex:719-737`).

**Depends on config**
- Adaptor strategy, npm or local (`bootstrap.ex:1059-1078`); variant `local-adaptors`.
- Refresh interval; at `0` the periodic tick is off and only this page or the mix task refreshes (`scheduler.ex:8-11`, `:247-250`); variant `refresh-disabled`.
- Icon cache path (`config.ex:94-100`, `bootstrap.ex:1101-1105`).

**Product limits**
- The icon refresh waits at most 120 seconds for a result, then reports failure (`scheduler.ex:121-123`, `adaptors.ex:361-362`); see 6.1.

## 5. Scenarios

```gherkin
Feature: Admin maintenance
  In order to keep the adaptor catalogue and icons current without shell access
  As a superuser
  I want to run an adaptor registry refresh and an icon refresh from the admin space

  @S01 @pending
  Scenario: A superuser sees both maintenance actions
    # Value: instance admins find the on-demand adaptor fixes in one place, each with a plain description of what it will and won't change.
    Given I am a superuser
    When I open "/settings/maintenance"
    Then I see the title "Maintenance"
    And I see a "Refresh Adaptor Registry" card reading "Re-fetch the list of available adaptors and their versions." with a "Run" button
    And I see a "Refresh Adaptor Icons" card reading "Does not touch adaptor metadata or version history." with a "Run" button
    # index.ex:16-22; index.html.heex:1-53 (titles :15, :36; copy :18, :39-40; buttons :21-27, :43-49)
    # index_test.exs:27-35, :52-58

  @S02 @pending
  Scenario: Refreshing the adaptor registry is queued and confirmed at once
    # Value: a newly published adaptor or version becomes available to workflow authors on the instance without waiting for the hourly poll or a restart, and the admin is not left waiting on the page.
    Given I am a superuser on "/settings/maintenance"
    And a new version of "@openfn/language-http" has been published upstream
    When I click "Run" on the "Refresh Adaptor Registry" card
    Then I see "Adaptor refresh queued."
    And the flow "flow-adaptor-catalogue-update" has started
    # index.ex:32-43; adaptors.ex:321-332; scheduler.ex:64-66, :362-365, :430-433, :519-559
    # index_test.exs:37-50 (asserts the info flash only); adaptors_test.exs:382-413 (refresh/1 starts a tick)

  @S03 @pending
  Scenario: A registry refresh that can't be started is reported as a failure
    # Value: the admin is not told work is underway when nothing was queued, so they know to look at the instance rather than wait.
    Given I am a superuser on "/settings/maintenance"
    And the adaptors scheduler is not reachable
    When I click "Run" on the "Refresh Adaptor Registry" card
    Then I see an error beginning "Refresh failed:"
    And I do not see "Adaptor refresh queued."
    # index.ex:35-41; adaptors.ex:330-332 (exit mapped to :timeout or :unavailable)
    # no LiveView test; adaptors_test.exs:470-488 covers :unavailable for refresh_package and refresh_icons only

  @S04 @pending
  Scenario: A registry refresh during one already running joins it
    # Value: repeated clicks, or a click during the periodic poll, don't start parallel refreshes that hit the registry twice and write the same rows twice.
    Given I am a superuser on "/settings/maintenance"
    And an adaptor registry refresh is already running
    When I click "Run" on the "Refresh Adaptor Registry" card
    Then I see "Adaptor refresh queued."
    And only one registry refresh runs
    # scheduler.ex:362-365, :424-426 (maybe_start_refresh), :252-258 (tick coalesces too)
    # scheduler_test.exs:663-689 waits for refresh == nil "so refresh_now starts a new one instead of coalescing"

  @S05 @pending
  Scenario: Refreshing icons reports its start and then its result
    # Value: an admin can fix stale or broken adaptor icons across the instance, keep using the page while it runs, and learn how many icons actually changed.
    Given I am a superuser on "/settings/maintenance"
    And the upstream icon for "@openfn/language-dhis2" has changed
    When I click "Run" on the "Refresh Adaptor Icons" card
    Then I see "Icon refresh started."
    And eventually I see "Icon refresh complete" with 1 updated and the rest unchanged
    And the flow "flow-adaptor-catalogue-update" has started for "@openfn/language-dhis2"
    # index.ex:52-59, :68-84; adaptors.ex:359-364; scheduler.ex:121-123, :389-424, :660-695
    # index_test.exs:60-83 (asserts "Icon refresh started." then "Icon refresh complete"; not the counts); scheduler_test.exs:1175 onward (rows whose sha256 differs are updated)

  @S06 @pending
  Scenario: A failed icon refresh is reported as an error
    # Value: the admin knows the icons were not updated and can retry or investigate, instead of assuming the fix landed.
    Given I am a superuser on "/settings/maintenance"
    And fetching icons upstream fails
    When I click "Run" on the "Refresh Adaptor Icons" card
    Then eventually I see an error beginning "Icon refresh failed"
    # index.ex:79-80, :86-89; scheduler.ex:417-423, :321-330
    # index_test.exs:85-104; scheduler_test.exs:1159-1173 (a crash in the task replies an error, Scheduler survives)

  @S07 @pending
  Scenario: An icon refresh never changes adaptor versions or metadata
    # Value: fixing icons can't move the adaptor versions or configuration schemas that running workflows and credentials depend on, as the card promises.
    Given "@openfn/language-http" is stored at version "7.0.0" with a configuration schema
    And upstream now lists "@openfn/language-http" at "7.1.0" with a new icon
    When I run the icon refresh as a superuser
    Then "@openfn/language-http" is still stored at "7.0.0" with the same schema and version history
    And its icon is updated
    # index.html.heex:39-40; scheduler.ex:401-408 (no fetch_adaptor), :683; catalogue.ex:216-245 (update_icons sidesteps upsert_adaptor and adaptor_versions)

  @S08 @pending @variant:local-adaptors
  Scenario: Under the local adaptors strategy, icons come from the local repo
    # Value: an adaptor developer running Lightning against a local adaptors checkout sees an icon they changed without restarting.
    Given the instance uses the local adaptors strategy
    And I have replaced the square icon of "@openfn/language-http" in the local adaptors repo
    When I run the icon refresh as a superuser
    Then eventually I see "Icon refresh complete" with 1 updated
    # local.ex:76-100 (reads icons from disk, no etags); bootstrap.ex:1067-1068, :1114
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The icon refresh call times out after 120 s and the page reports failure, but the Scheduler's task keeps running and may still update icons and broadcast | `scheduler.ex:121-123`, `:389-399`; `adaptors.ex:361-362`; `index.ex:79-80` | "Icon refresh failed: :timeout" while icons do change shortly after | fix |
| On failure the "Icon refresh started." info toast is not cleared, so the page shows "started" and "failed" side by side | `index.ex:56`, `:79-80`, `:86-88`; `settings.html.heex:99-100` (separate info and error blocks, sticky per shared-flash-messages S07) | two contradictory toasts until each is clicked | fix |
| "Adaptor refresh queued." is the only outcome ever shown for a registry refresh; a refresh whose listing fails upstream reports nothing on the page | `index.ex:35-37`; `scheduler.ex:362-365`, `:504-515` | a success flash for a refresh that later fails; the result is only in the server log | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Error flashes interpolate `inspect(reason)`, so admins see raw Elixir terms such as `:unavailable` or `{:refresh_failed, ...}` | `index.ex:40`, `:80`, `:88` | decide |
| The completion flash copy uses an em dash and counts rows with no upstream icon, and rows answered 304, as "unchanged" | `index.ex:76`; `scheduler.ex:660-673`, `:701-711` | decide |
| Neither "Run" button is disabled or shows progress while work runs; repeated icon clicks each start a new Scheduler task that refetches every icon (icon refreshes are not coalesced, unlike registry refreshes) | `index.html.heex:21-27`, `:43-49`; `scheduler.ex:389-399` | decide |
| Card titles use title case ("Refresh Adaptor Registry", "Refresh Adaptor Icons") | `index.html.heex:15`, `:36` | decide |
| The page checks the policy itself rather than using `:ensure_admin`, and refuses with `push_navigate`; recorded on shared-admin-space 6.2 | `index.ex:16-29`, `:91-98` | decide |
| The registry refresh only refetches adaptors whose version changed or whose schema is missing within the grace window; it is not a forced refetch, though the copy says "Re-fetch" | `scheduler.ex:519-532`; `index.html.heex:18` | decide |
| The icon refresh lists the npm registry again before fetching icons, so it fails if the registry is down even when GitHub is up | `npm.ex:91-98` | preserve |
| An icon update bumps `updated_at`, which restarts the 1 hour schema grace window for a row still missing its schema | `catalogue.ex:241`; `scheduler.ex:524-525`, `:556-558` | decide |
| Icon bytes are written only to the disk of the node running the Scheduler; other nodes refetch on a cache miss keyed by sha | `scheduler.ex:724`; `icon_cache.ex:8-17` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Non-superuser branches of `handle_event("refresh_adaptors")` and `handle_event("refresh_icons")` | `index.ex:44-49`, `:60-65` | `mount` already refused a non-superuser and a role change disconnects the socket; already listed in shared-admin-space 6.3 |
| `handle_async(:refresh_icons, {:exit, reason})` for a crash inside the Scheduler | `index.ex:86-89` | `Adaptors.refresh_icons/1` catches every exit and returns `{:error, _}` (`adaptors.ex:361-363`), so the async function only exits if the LiveView cancels it |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Icon refresh call timeout 120 s | `scheduler.ex:122` | yes, as a failure flash (6.1) | preserve |
| Registry refresh call uses the default 5 s `GenServer.call` timeout, but only to enqueue | `scheduler.ex:64-66` | yes, "Refresh failed: :timeout" | preserve |
| Registry refresh fetches at most 8 adaptors concurrently, each bounded by the strategy `http_timeout` or 30 s; the icon fetch in a tick is bounded by 60 s | `scheduler.ex:33-35`, `:450-462`, `:576-600` | no | preserve |
| `adaptors_updated` coalesced to one push per 250 ms | `channel_broadcaster.ex:18` | no | preserve |
| Every broadcast triggers a `SELECT DISTINCT schema` over `credentials` on every node | `schema_reconciler.ex:21-24` | no | preserve |

### 6.5 Things seen but not understood

- The comment on `keep_stored_schema/2` says "An operator refresh takes upstream as-is and is where a real removal lands" (`scheduler.ex:562-565`), but the page's refresh goes through the same `do_refresh/1` path that keeps the stored schema; only `refresh_package/2` (mix task `--name`) takes upstream as-is (`scheduler.ex:752-776`). Unclear whether the page was meant to force.
- LiveView 1.0.19 (`mix.lock:105`) behaviour when `start_async(:refresh_icons, ...)` is called while a previous one is in flight was not checked (deps not present); whether the first result is dropped or both flash is unverified.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should instance-wide maintenance actions write an audit event naming the superuser? Today neither does (section 4). (owner: security)
- Should the registry refresh report its outcome (counts or failure) on the page, as the icon refresh does (6.1)? (owner: product)
- Should the "Run" buttons disable while work is in flight, and should icon refreshes coalesce like registry refreshes (6.2)? (owner: product)
- Should the page offer a forced refetch that replaces stored schemas, per the Scheduler comment (6.5)? (owner: product)
- Should raw error terms be replaced by readable messages (6.2)? (owner: product)

## Proposed flows

- `flow-adaptor-catalogue-update`: a catalogue or icon change (from this page, the periodic tick or the mix task) broadcasts `{:changed, name, source}`; each node's Invalidator drops caches, ChannelBroadcaster pushes `adaptors_updated` to every open collaborative editor, which refetches the catalogue and icons, and SchemaReconciler rewrites legacy credential schema names. Surfaces: admin-maintenance, pubsub:adaptors:<instance>, pubsub:adaptors:client_update:<instance>, channel:workflow (workflow-editor-canvas), controller:adaptor-icons (`router.ex:81-82`), project-settings-credentials. This file asserts only the handoff (S02, S05).

## Proposed shared

none

## Summary

- Scenarios: 8 (S01 to S08), all `@pending`; S08 tagged `@variant:local-adaptors`.
- Section 6: 6.1 has 3, 6.2 has 9, 6.3 has 2, 6.4 has 5, 6.5 has 2.
- Flows: proposed flow-adaptor-catalogue-update (S02, S05 handoffs); none existing referenced.
- Shared: none proposed; inherits shared-admin-space (gate exception S02 and its 6.2 and 6.3, menu S01), shared-flash-messages (S07), shared-authenticated-session, shared-project-header (no-project parts).
- Unsure: LiveView start_async re-entry behaviour (deps not installed); S03 and S04 have no page-level test; the `{:exit, _}` handle_async clause is judged unreachable from code reading only.

## Lead resolution (batch 10)

- `flow-adaptor-catalogue-update` created; it absorbs the queued `capability:adaptor-catalogue-refresh`.
