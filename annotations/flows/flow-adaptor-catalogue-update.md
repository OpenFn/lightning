---
id: flow-adaptor-catalogue-update
type: flow
title: Adaptor catalogue refresh reaching editors
status: not-started
owner:

trigger:
  entry: admin-maintenance                     # "Run" on either card (maintenance_live/index.ex:32-66); the scheduled tick is the other entry
  exit: workflow-editor-inspectors             # and workflow-editor-ide; both read the catalogue through shared-adaptor-credential-config's pickers
  surfaces:
    - admin-maintenance                        # registry refresh (index.ex:32-50 -> adaptors.ex:321-333) or icon refresh (index.ex:52-89 -> adaptors.ex:359-364)
    - oban:adaptor-scheduler                   # id as set by the lead; there is no Oban job: a cluster-singleton GenServer timer under HighlanderPG (scheduler.ex:1-21, :247-261; supervisor.ex:124-131); see 6.5
    - pubsub:adaptors:<instance>               # {:changed, name, source} per changed row (scheduler.ex:685-689, :784-788; supervisor.ex:220-221)
    - capability:adaptor-node-caches           # Invalidator on every node (invalidator.ex:41-49); NodeMonitor re-warm on :nodeup (node_monitor.ex:41-44)
    - pubsub:adaptors:client_update:<instance> # ChannelBroadcaster, 250 ms coalesce (channel_broadcaster.ex:18, :59-79; supervisor.ex:227-228)
    - capability:credential-schema-reconciler  # rewrites short credential schema names (schema_reconciler.ex:48-90; credentials.ex:608-645)
    - controller:workflow-channel              # WorkflowChannel pushes adaptors_updated (workflow_channel.ex:86, :957-960)
    - controller:adaptor-catalogue             # GET /adaptors/catalogue, ETag and 304 (router.ex:155-160; adaptor_controller.ex:21-54)
    - controller:adaptor-icons                 # GET /adaptors/icons/:name/:filename, 200 or 302 to the current sha (router.ex:81-83; adaptor_icon_controller.ex:64-156)
    - workflow-editor-inspectors               # store refetches and re-renders pickers, version list and icons (createAdaptorStore.ts:272-321)
    - workflow-editor-ide                      # same store, IDE header pickers
    - workflow-editor-canvas   # added by lead: picker and node icons
  reachable_when:
    - operator entry: the viewer is a superuser on /settings/maintenance (admin-maintenance section 3)
    - scheduled entry: `refresh_interval` > 0; the first tick is one interval after the newest `checked_at`, or at once on an empty catalogue (scheduler.ex:179-211, :835-841)
    - a Scheduler is reachable somewhere in the cluster, through `:global` (supervisor.ex:209-210; adaptors.ex:330-332, :361-363)
    - receiving side: a WorkflowChannel joined on any view of any workflow; the subscribe in `join` does not depend on the view (workflow_channel.ex:44-86)

inherits:
  - shared-admin-space                 # entry page gate and layout
  - shared-editor-session              # channel join, reconnect, the adaptors_updated forwarder (workflow_channel.ex:957-960)
  - shared-adaptor-credential-config   # the pickers this flow refreshes; catalogue retry (its S09) and deprecated filtering (its S10) are owned there

url_params: []

config_variants:
  default: { Lightning.Adaptors.strategy: Lightning.Adaptors.NPM, refresh_interval: 3600000 }   # read under this one (config.ex:12-16; bootstrap.ex:1059-1110)
  local-adaptors: { ADAPTORS_STRATEGY: local }                                                 # bootstrap.ex:1067-1068; local.ex:45-100
  refresh-disabled: { ADAPTORS_REFRESH_INTERVAL_SECONDS: 0 }                                  # scheduler.ex:8-11, :197-208, :247-250
  clustered: { more than one node joined by libcluster }                                      # application.ex:120-133, :166; the Scheduler runs on one node, caches on all (supervisor.ex:114-131)
  reconciler-disabled: { Lightning.Credentials.SchemaReconciler.enabled: false }             # application.ex:135-143; set only by config/test.exs:119

inventory:
  routes:
    - get /adaptors/catalogue  AdaptorController :index                  # router.ex:155-160
    - get /adaptors/icons/:name/:filename  AdaptorIconController :show   # router.ex:81-83, in the :browser scope (router.ex:66-67)
  events:
    - MaintenanceLive.Index#refresh_adaptors, #refresh_icons              # owned by admin-maintenance; handoff only
    - Lightning.Adaptors.Scheduler handle_info(:tick), handle_call(:refresh_now | :refresh_icons | {:await_refresh, _} | {:refresh_package, _})   # scheduler.ex:247-261, :362-399
    - Lightning.Adaptors.Invalidator handle_info({:changed, _, _})       # invalidator.ex:41-49
    - Lightning.Adaptors.ChannelBroadcaster handle_info({:changed, _, _}, :flush)   # channel_broadcaster.ex:59-79
    - Lightning.Adaptors.NodeMonitor handle_info({:nodeup | :nodedown, _, _})       # node_monitor.ex:41-49
    - Lightning.Credentials.SchemaReconciler handle_info(:reconcile | adaptors_updated)   # schema_reconciler.ex:62-71
    - WorkflowChannel handle_info adaptors_updated                       # workflow_channel.ex:957-960
  js_hooks:
    - createAdaptorStore channel.on("adaptors_updated") and requestAdaptors on connect   # createAdaptorStore.ts:272-321
  policies:
    - Lightning.Policies.Users :access_admin_space                       # operator entry only (policies/users.ex:19-21); owned by admin-maintenance
    - none on the receiving side; every joined channel is pushed, and /adaptors/catalogue needs only a signed-in user (router.ex:155-160)
  workers: []                                                            # no Oban; see oban:adaptor-scheduler note above
  api_endpoints:
    - get /adaptors/catalogue
  emails: []
  config:
    - :lightning, Lightning.Adaptors :strategy, :refresh_interval, :icon_path, :cache_timeout_ms   # config.ex:14-16, :33-35, :66-68, :84-100
    - :lightning, Lightning.Credentials.SchemaReconciler :enabled        # application.ex:135-143
  not_reachable_here:
    - mix lightning.adaptors.refresh and its --name branch (lightning.adaptors.refresh.ex:30-75); a third entry the lead did not list (6.2)
    - Lightning.Adaptors.seed_from_file broadcast (seed.ex:55-79); a fourth entry (6.2)
    - Store.ensure_loaded first-load wait used by the workflow save (store.ex:242-294; session.ex:422); owned by shared-editor-session

related:
  - lib/lightning/adaptors/scheduler.ex
  - lib/lightning/adaptors/supervisor.ex
  - lib/lightning/adaptors/invalidator.ex
  - lib/lightning/adaptors/channel_broadcaster.ex
  - lib/lightning/adaptors/node_monitor.ex
  - lib/lightning/adaptors/store.ex
  - lib/lightning/adaptors/catalogue.ex
  - lib/lightning/credentials/schema_reconciler.ex
  - lib/lightning_web/controllers/adaptor_controller.ex
  - lib/lightning_web/controllers/adaptor_icon_controller.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - assets/js/collaborative-editor/stores/createAdaptorStore.ts
  - test/lightning/adaptors/scheduler_test.exs
  - test/lightning/adaptors/end_to_end_broadcast_test.exs
  - test/lightning/adaptors/channel_broadcaster_test.exs
  - test/lightning/adaptors/invalidator_test.exs
  - test/lightning/credentials/schema_reconciler_test.exs
  - test/lightning_web/controllers/adaptor_icon_controller_test.exs
  - assets/test/collaborative-editor/createAdaptorStore.test.ts
flows:
  - flow-editor-credentials-broadcast   # sibling forwarder on the same channel; the reconciler does not use it (6.1)
---

## 1. Purpose

Workflow authors pick adaptors, versions and icons from a catalogue the instance keeps in its own
database. When a new adaptor or release is published, or an icon is fixed, that change has to reach
every node and every open editor, or authors pin steps to a release list that is out of date, look
for an adaptor that is not there yet, or see a broken icon until they reload. Older credentials saved
under a short schema name also need to line up with the adaptor names the catalogue now knows.

## 2. What it does

Superuser clicks "Run" on /settings/maintenance, or the hourly tick fires → the Scheduler fetches
and writes changed `adaptors` rows → `{:changed, name, source}` on `adaptors:<instance>` → every
node drops its cached entries for that adaptor and coalesces a push of `adaptors_updated` →
each node's SchemaReconciler rewrites short credential schema names → every open editor channel
pushes `adaptors_updated` → the editor refetches `/adaptors/catalogue` and its pickers and icons
show the new data, icon URLs that moved redirecting to the current one.

## 3. Who can do what

Starting the flow from the page is superuser only (`policies/users.ex:19-21`; admin-maintenance
section 3). The scheduled tick has no actor. The receiving side checks no role: every joined
WorkflowChannel is pushed (`workflow_channel.ex:957-960`), the catalogue needs only a signed-in user
(`router.ex:155-160`), and icons need no session at all (`router.ex:66-67`, `:81-83`).

| Action | Signed out | Viewer | Editor | Admin | Owner | Superuser |
|--------|-----------|--------|--------|-------|-------|-----------|
| Start a registry or icon refresh | no | no | no | no | no | yes |
| Receive `adaptors_updated` in an open editor | n/a | yes | yes | yes | yes | yes, when on the project |
| Fetch the refreshed catalogue | no | yes | yes | yes | yes | yes |
| Fetch an icon | yes | yes | yes | yes | yes | yes |

**Preconditions beyond role**
- No refresh starts while the Scheduler is unreachable; the page then shows "Refresh failed" (admin-maintenance S03; `adaptors.ex:330-332`).
- Under `refresh-disabled` only the page, the mix task or a seed start the flow (`scheduler.ex:197-208`).
- No audit event is written at any hop (`scheduler.ex:1-842`; `credentials.ex:605-606` says so on purpose for the reconciler).

## 4. What it touches

**Reads**: `adaptors`, `adaptor_versions` for the active source (`catalogue.ex:102-104`, `:271-327`); `credentials.schema` distinct values (`credentials.ex:610-616`).

**Writes**
- Hop 2, Scheduler: `adaptors` and `adaptor_versions` upserted per changed adaptor, versions deleted and reinserted (`scheduler.ex:519-559`, `:604-622`; `catalogue.ex:144-185`); `adaptors.checked_at` for unchanged ones (`scheduler.ex:528-531`; `catalogue.ex:204-214`); icon columns and `updated_at` only for icon changes (`scheduler.ex:660-695`; `catalogue.ex:228-245`); icon files on the Scheduler node's disk (`scheduler.ex:628`, `:724`).
- Hop 4, reconciler: `credentials.schema` from short to full package name, on every node, no `updated_at` (`credentials.ex:617-628`).
- Hop 6, icon controller on another node: icon file written to that node's disk on first request (`store.ex:112-150`).

**Immediate side effects** (in the same request)
- Hop 1: flashes on the maintenance page (admin-maintenance section 4).
- Hop 2: one `{:changed, name, source}` broadcast per written row, cluster-wide (`scheduler.ex:685-689`, `:784-788`); none for touched rows (`scheduler_test.exs:261-303`).

**Deferred side effects** (later, elsewhere)
- Hop 3, every node: Invalidator deletes `{:schema,..}`, `{:icon_meta,..}`, both `{:icon_bytes,..}`, `{:packages,..}` and `{:catalogue,..}` (`invalidator.ex:41-49`; `invalidator_test.exs:29-75`).
- Hop 3, every node: ChannelBroadcaster arms a 250 ms timer on the first change and broadcasts `%{event: "adaptors_updated", payload: %{names: [...]}}` on the client topic (`channel_broadcaster.ex:59-79`; `end_to_end_broadcast_test.exs:17-41`).
- Hop 4, every node: SchemaReconciler sweeps on each client-topic message, retries after 5 minutes on a raise (`schema_reconciler.ex:33`, `:62-90`; `schema_reconciler_test.exs:33-73`).
- Hop 5: each WorkflowChannel `push`es `adaptors_updated` (`workflow_channel.ex:957-960`; `workflow_channel_test.exs:4856-4868`).
- Hop 6: the editor calls `GET /adaptors/catalogue`; the ETag stamp is `GREATEST(max updated_at, max version inserted_at)` plus version count, so a write moves it and a touch does not (`catalogue.ex:315-327`; `adaptor_controller.ex:21-54`); unchanged entries keep their object identity so nothing re-renders (`createAdaptorStore.ts:91-110`, `:181-214`).
- Hop 6: new `icon_urls` carry the new sha8; an old URL answers 302 to the current one with `no-store` (`adaptor_icon_controller.ex:17-28`, `:100-109`, `:141-148`).
- On `:nodeup`, NodeMonitor overwrites the package list, icon meta and catalogue cache from the database (`node_monitor.ex:41-44`; `store.ex:300-324`).
- Emails: none. Oban jobs: none.

**External, non-transactional effects**
- npm registry, jsDelivr and raw.githubusercontent.com under `default`; local disk under `local-adaptors` (admin-maintenance section 4).
- Icon files written before the row update are not rolled back (`scheduler.ex:719-737`).

**Depends on config**
- Strategy (`local-adaptors`), interval (`refresh-disabled`), cluster (`clustered`), reconciler switch (`reconciler-disabled`).

**Product limits**
- none beyond admin-maintenance's 120 s icon wait.

## 5. Scenarios

Verified by reading under `default` unless tagged. Page flashes are admin-maintenance S02 to S06;
this file owns what happens after the Scheduler writes.

```gherkin
Feature: Adaptor catalogue refresh reaching editors
  In order to build workflows against the adaptors that exist today
  As a workflow author with the editor open
  I want catalogue and icon changes to reach me without reloading

  Background:
    Given project "Malawi HIV" has workflow "Intake" with step "Fetch" using "@openfn/language-dhis2"
    And "amara@example.org" has "Intake" open with "Configure connection" showing "Fetch"

  @S01 @pending
  Scenario: A registry refresh from the maintenance page reaches an open editor
    # Value: authors can pin a step to a release published minutes ago without reloading and losing their place.
    Given upstream now lists "@openfn/language-dhis2" at "4.11.0"
    When a superuser clicks "Run" on the "Refresh Adaptor Registry" card
    Then "Adaptor refresh queued." is shown on the maintenance page
    And eventually amara's version list for "Fetch" includes "4.11.0"
    # index.ex:32-37; adaptors.ex:321-329; scheduler.ex:362-365, :430-503, :519-559, :781-790
    # invalidator.ex:41-49; channel_broadcaster.ex:59-79; workflow_channel.ex:86, :957-960
    # createAdaptorStore.ts:278-286, :308-321; adaptor_controller.ex:21-35
    # scheduler_test.exs:430-464; end_to_end_broadcast_test.exs:17-41; workflow_channel_test.exs:4856-4868; createAdaptorStore.test.ts:262-300

  @S02 @pending
  Scenario: A new adaptor published upstream appears on the next scheduled tick
    # Value: the catalogue stays current on its own, without an operator watching npm.
    Given upstream now lists a new adaptor "@openfn/language-gmail"
    When the hourly refresh runs
    Then eventually amara can find "gmail" in the adaptor picker
    # scheduler.ex:247-261, :519-545 (no existing row means fetch); createAdaptorStore.ts:278-281
    # scheduler_test.exs:511-534; createAdaptorStore.test.ts:225-260

  @S03 @pending @variant:refresh-disabled
  Scenario: With the timer off, the catalogue changes only when someone refreshes it
    # Value: an instance run without internet access never reaches out to npm on its own, and an operator can still update it on demand.
    Given the refresh interval is 0
    And upstream now lists "@openfn/language-dhis2" at "4.11.0"
    When an hour passes
    Then amara's version list does not include "4.11.0"
    When a superuser clicks "Run" on the "Refresh Adaptor Registry" card
    Then eventually amara's version list includes "4.11.0"
    # scheduler.ex:8-11, :197-208, :247-250, :362-365; scheduler_test.exs:225-249

  @S04 @pending
  Scenario: An icon refresh changes the icon in an open editor
    # Value: a fixed or rebranded adaptor icon reaches everyone already at work, not only people who reload.
    Given the upstream square icon of "@openfn/language-dhis2" has changed
    When a superuser clicks "Run" on the "Refresh Adaptor Icons" card
    Then eventually amara's "Fetch" step shows the new icon
    # index.ex:52-59; scheduler.ex:389-424, :660-695; catalogue.ex:228-245
    # adaptor_icon_controller.ex:17-28 (URL carries sha8); AdaptorIcon.tsx:20-38; createAdaptorStore.ts:91-110
    # scheduler_test.exs:1175-1225 (rows updated); no test of the editor re-render

  @S05 @pending
  Scenario: An icon link from before the refresh still shows the current icon
    # Value: a tab that missed the update, or a page holding an old link, gets the current icon instead of a broken image.
    Given the square icon of "@openfn/language-dhis2" has been refreshed
    When a browser requests the square icon URL from before the refresh
    Then it is redirected to the current icon URL with "Cache-Control: no-store"
    And the current URL serves the icon with a one-year immutable cache
    # adaptor_icon_controller.ex:55, :100-109, :128-148; adaptor_icon_controller_test.exs:58-87, :268-361

  @S06 @pending
  Scenario: A refresh that finds nothing new does not disturb open editors
    # Value: hourly polling costs open editors nothing when upstream has not changed.
    Given upstream lists every adaptor at the version already stored
    When the hourly refresh runs
    Then no "adaptors_updated" is pushed to amara's editor
    # scheduler.ex:528-531 (touch only, no broadcast); catalogue.ex:204-214 (checked_at does not move the ETag stamp, catalogue.ex:315-327)
    # scheduler_test.exs:261-303

  @S07 @pending
  Scenario: Many adaptors changing at once reach an editor as one update
    # Value: a large upstream release does not flood every open editor with catalogue refetches.
    Given upstream has new versions of "@openfn/language-dhis2" and "@openfn/language-http"
    When a registry refresh writes both within 250 ms
    Then amara's editor receives one "adaptors_updated" naming both
    And it refetches the catalogue once
    # channel_broadcaster.ex:18, :59-79; createAdaptorStore.ts:278-281
    # channel_broadcaster_test.exs:52-83, :117 onward

  @S08 @pending
  Scenario: A failed upstream listing leaves the catalogue as it was
    # Value: an npm outage never empties or rolls back the adaptors authors can choose from.
    Given the npm registry is unreachable
    When a registry refresh runs
    Then no adaptor rows change and no "adaptors_updated" is pushed
    And amara's picker still lists every adaptor it listed before
    # scheduler.ex:505-515; scheduler_test.exs:569-588

  @S09 @pending @variant:clustered
  Scenario: Users on another node see the refreshed catalogue
    # Value: which node a user's browser lands on never decides whether they see the new release.
    Given the instance runs on nodes "a" and "b" and the Scheduler runs on "a"
    And "b" has served the catalogue before the refresh
    When a registry refresh on "a" stores "@openfn/language-dhis2" at "4.11.0"
    Then a catalogue request served by "b" includes "4.11.0"
    # supervisor.ex:114-131 (Invalidator on every node, Scheduler singleton); invalidator.ex:41-49; store.ex:188-204
    # invalidator_test.exs:29-75 (single node only); no multi-node test

  @S10 @pending
  Scenario: An older credential is filed under its adaptor once the catalogue knows it
    # Value: credentials saved under an old short name are offered for the adaptor they were made for, not hidden from "Configure connection".
    Given project "Malawi HIV" has credential "DHIS2 legacy" with schema "dhis2"
    And the catalogue has no "@openfn/language-dhis2" yet
    When a refresh stores "@openfn/language-dhis2"
    Then "DHIS2 legacy" eventually has schema "@openfn/language-dhis2"
    And after amara's editor reloads its credential list, "DHIS2 legacy" is listed for "Fetch"
    # schema_reconciler.ex:48-71; credentials.ex:608-645; adaptors.ex:138-160
    # ConfigureAdaptorModal.tsx:300-319 (exact schema match against the package name)
    # schema_reconciler_test.exs:33-54; the open editor is not told (6.1)

  @S11 @pending
  Scenario: An editor that was offline during a refresh catches up when it reconnects
    # Value: a laptop that slept through an update does not keep offering the old catalogue.
    Given amara's connection drops
    And a registry refresh stores "@openfn/language-dhis2" at "4.11.0"
    When amara's editor reconnects
    Then her version list includes "4.11.0"
    # createAdaptorStore.ts:290-293; createAdaptorStore.test.ts:208-223
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The reconciler rewrites `credentials.schema` but broadcasts nothing, so open editors keep the short name until they reconnect; the short name never matches the package name | `credentials.ex:617-628`; `schema_reconciler.ex:62-71`; `ConfigureAdaptorModal.tsx:300-304`; only `credentials_updated` publisher `collaborate.ex:527-531` | a legacy credential stays missing from "Configure connection" in an open editor after the refresh that fixed it | fix |
| NodeMonitor's re-warm on `:nodeup` overwrites packages, icon meta and catalogue but leaves `{:schema,..}` and `{:icon_bytes,..}`, which have no TTL. Read from code, not run | `node_monitor.ex:1-14`, `:41-44`; `store.ex:300-324`; `invalidator.ex:41-49` | after a partition, a node can keep serving an old credential schema for an adaptor until that adaptor changes again (`clustered`) | fix |
| `{1, _} = Catalogue.update_icons(...)` raises if the row has gone between the list and the write; the whole icon task then fails, after earlier rows were already updated and broadcast | `scheduler.ex:683`; `scheduler.ex:321-329`; `catalogue.ex:191-195` | "Icon refresh failed: {:refresh_failed, ...}" for a partly applied refresh (rare; needs a concurrent seed) | fix |
| Carried from admin-maintenance 6.1: a 120 s icon timeout reports failure while the task keeps writing and broadcasting | `scheduler.ex:121-123`, `:389-399`; `adaptors.ex:361-362` | the admin reads "failed" while editors receive the new icons shortly after | fix |
| Carried from admin-maintenance 6.1: a registry refresh only ever reports "queued" | `index.ex:35-37`; `scheduler.ex:362-365`, `:505-515` | an admin is not told that S08's outage stopped the update from reaching editors | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| On a cluster, every node's ChannelBroadcaster republishes on the cluster-wide client topic, so each editor gets one push per node per burst and each node's reconciler sweeps once per node | `channel_broadcaster.ex:68-77` (`Phoenix.PubSub.broadcast`, not local); `supervisor.ex:120-123`; `schema_reconciler.ex:67` | decide |
| The push names the changed adaptors, but the client ignores the names and refetches the whole catalogue | `channel_broadcaster.ex:72-75`; `createAdaptorStore.ts:273-281` | preserve |
| Pinned versions, releases and run views also subscribe and refetch; unlike `credentials_updated`, the adaptor topic is not per workflow | `workflow_channel.ex:86` | preserve |
| The scheduled tick also re-applies icons to rows it did not refetch, so icon changes land hourly without the icon button | `scheduler.ex:478-486`; `scheduler_test.exs:886-944` | preserve |
| Two more entries reach this flow that the lead's scope does not list: `mix lightning.adaptors.refresh` (with `--name`, a forced refetch that can clear a schema) and `seed_from_file` | `lightning.adaptors.refresh.ex:30-75`; `scheduler.ex:752-776`; `seed.ex:55-79` | decide |
| The catalogue fetch relies on the browser's default HTTP cache to send `If-None-Match`; `fetch` sets no cache mode | `api/adaptors.ts:13-23`; `adaptor_controller.ex:28-33` | preserve |
| Icon bytes exist only on the Scheduler node's disk; other nodes fetch them upstream on first request and verify the sha | `scheduler.ex:724`; `store.ex:112-150` | preserve |
| A failed refetch after a push sets the store error but keeps the old list, so the picker shows no error | `createAdaptorStore.ts:241-247`, `:315-320`; `AdaptorSelectionModal.tsx:39-40` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `adaptorStore.setAdaptors` | `createAdaptorStore.ts:256-263`; exposed at `useAdaptors.ts:70` | no caller found in `assets/js` |
| `NodeMonitor` `:nodedown` clause | `node_monitor.ex:46-49` | deliberate no-op per its moduledoc |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `adaptors_updated` coalesced to one push per 250 ms window, leading edge | `channel_broadcaster.ex:18`, `:59-62` | no | preserve |
| Every client-topic message triggers a `SELECT DISTINCT schema` over unindexed `credentials` on every node | `schema_reconciler.ex:21-24`; `credentials.ex:610-616` | no | preserve |
| Failed reconciler sweep retried after 5 minutes | `schema_reconciler.ex:33`, `:79-90` | no | preserve |
| Cache reads time out after 15 s | `config.ex:14`, `:84-87`; `store.ex:89`, `:121` | no | preserve |
| Every open editor refetches the full catalogue per push (304 when the stamp has not moved) | `createAdaptorStore.ts:278-281`; `adaptor_controller.ex:32-33` | no | preserve |

### 6.5 Things seen but not understood

- The lead's scope names the scheduled entry `oban:adaptor-scheduler`, but no Oban job exists for adaptors; the timer is `Process.send_after` in a HighlanderPG-held GenServer (`scheduler.ex:197-198`, `:247-250`; `supervisor.ex:124-131`). The id is kept as given; whether it should become `capability:adaptor-scheduler` is for the lead. (decide)
- Whether the reconciler running on every node at once can race two `update_all`s on the same short name was not checked; both write the same value, so likely harmless (`credentials.ex:623-626`). (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the reconciler tell open editors that credential schemas changed, through `credentials_updated` or a project-wide event (6.1)? (owner: product)
- Should one cluster node, not every node, publish `adaptors_updated` (6.2)? (owner: engineering)
- Should catalogue and icon refreshes, and the schema rewrite, write audit events (section 3)? (owner: security)
- Should the mix task and seed be listed as entries of this flow (6.2)? (owner: product)

## Proposed flows

none

## Proposed shared

none. References shared-admin-space, shared-editor-session and shared-adaptor-credential-config.

## Summary

- Scenarios: 11 (S01 to S11), all `@pending`; S03 `@variant:refresh-disabled`, S09 `@variant:clustered`.
- Section 6: 6.1 has 5, 6.2 has 8, 6.3 has 2, 6.4 has 5, 6.5 has 2.
- Flows: none proposed; references flow-editor-credentials-broadcast; absorbs shared-adaptor-credential-config's proposed flow-adaptor-catalogue-refresh.
- Shared: none proposed; inherits shared-admin-space, shared-editor-session, shared-adaptor-credential-config.
- Unsure: no Oban job behind `oban:adaptor-scheduler`; multi-node behaviour (S09, double pushes, re-warm gap) read from code only; workflow-editor-canvas also renders the picker and node icons from this store but is not in the lead's surfaces, and none of the three editor views lists this flow yet.
