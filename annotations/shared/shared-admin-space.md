---
id: shared-admin-space
type: shared
title: Superuser admin space
status: not-started
owner:

trigger:
  old_route: every /settings/* admin LiveView (the `:settings` live_session plus the config-injected /settings/users) and the LiveDashboard at /dashboard
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session (`lib/lightning_web/router.ex:189-190` for `:settings`, `:349` for `:services`, `:361` for `/dashboard`)
    - the module declares `on_mount {LightningWeb.Hooks, :ensure_admin}` (`lib/lightning_web/live/user_live/index.ex:7`, `user_live/edit.ex:8`, `project_live/index.ex:7`, `audit_live/index.ex:7`, `auth_providers/index.ex:7`, `collection_live/index.ex:4`), or for /dashboard the route declares it (`router.ex:363-369`); MaintenanceLive.Index checks the same policy itself (`maintenance_live/index.ex:16-29`, `:91-98`)
    - the viewer passes `Lightning.Policies.Users :access_admin_space`, which is role `:superuser` only (`lib/lightning/policies/users.ex:19-21`)

inherits:
  - shared-authenticated-session    # login redirect (S01), revoked sessions, TOTP and lockout gates, sidebar collapse (S07); S08 to S10 never render on the settings layout (its 6.2)
  - shared-project-header           # no-project parts only: account menu (S18), global picker by keyboard (S04, S06, S08, S10 to S12), experimental indicator (S16, sidebar part), version chip (its 6.2)

url_params: []

config_variants:
  default: {}                                                                                  # read under this one unless a scenario is tagged
  settings-menu-extension: { lightning.settings_menu_items_extension: "%{component, assigns_keys}" }   # layout_components.ex:188-205; not set anywhere in config/

inventory:
  routes: []                        # owns no route; each admin view owns its own (router.ex:268-286, config/config.exs:60, router.ex:358-369)
  events: []
  js_hooks:
    - ToggleSidebarViaCtrlM         # settings.html.heex:3-8; owned by shared-authenticated-session
    - SidebarHoverDelay             # settings.html.heex:18-23; owned by shared-authenticated-session
    - ReactComponent Picker         # settings.html.heex:104-106; owned by shared-project-header
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), via LightningWeb.Hooks :ensure_admin (hooks.ex:31-53) and MaintenanceLive.Index.superuser?/1 (maintenance_live/index.ex:91-98)
    - LightningWeb.UserAuth.require_superuser plug (user_auth.ex:415-438), /dashboard only
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :settings_menu_items_extension (layout_components.ex:188-205)
  not_reachable_here:
    - LiveHelpers.live_nav_block: the settings layout does not render it (settings.html.heex:98-102); the "No Access" card shows on /projects, in the live layout (live.html.heex:94-96)
    - GDPR banner and book-a-demo banner (shared-authenticated-session S08 to S10); absent from settings.html.heex:1-107
    - Menu.project_items and the "Admin Menu" / "Sys Info" links (live.html.heex:45-58); live layout only, owned by shared-project-header S15, S17
    - Hooks :ensure_admin nil-user clause (hooks.ex:31-38), see 6.3
    - require_superuser JSON branch (user_auth.ex:424-429), see 6.3

related:
  - admin-users
  - admin-user-edit
  - admin-projects
  - admin-audit
  - admin-maintenance               # own policy check instead of the hook (S02 row, 6.2)
  - admin-auth-providers
  - admin-collections
  - admin-live-dashboard            # gate only (S04, S05); own layout, no admin menu
  # Not inheritors, but where the gate hands off:
  #   projects-dashboard renders the "No Access" card after a refusal (live_helpers.ex:78-150)
  #   first-setup creates the first superuser, the only role that opens this space
flows:
  - flow-account-revocation-teardown   # demotion from superuser drops open admin pages (S06); owned there
---

## 1. Purpose

Superusers run the instance: they manage every user account and project, configure the login
provider, read the audit trail, inspect collections, refresh adaptors and watch the system
dashboard. Every one of those pages sits behind the same gate and opens in the same admin frame.
Without the gate, any signed-in account could read or change instance-wide data; without the frame,
admins would have no single place to move between these jobs and back to their own projects.

## 2. What it does

- **Work in the admin space** (superusers)
  - Open any admin page
  - Move between admin areas from one side menu and see which one they are in
  - Leave the admin space back to their projects
- **Keep everyone else out**
  - Non-superusers who reach an admin page are sent to their projects and told they have no access
  - Non-superusers can't reach the system dashboard, whether by loading the page or by reconnecting to it directly
  - A superuser who is demoted loses the admin pages they already have open
- **Extend the menu**
  - Deployments add their own items to the admin menu

**Straightforwardness: 4 of 5.** It's one gate and one menu, and it behaves as you'd expect; the oddities are small inconsistencies between admin pages.

### Most surprising behaviours

- **(3)** The gate is set up page by page rather than once for the whole admin space, so a new admin page added without it would open to every signed-in user. (6.2)
- **(3)** The "Authentication" menu item opens an empty new-provider form even when a login provider is already set up, rather than showing the existing one. (6.2)
- **(3)** While a superuser edits a project in the admin space, the project picker at the top marks that project as the one they're "in". (6.2)
- **(4)** The system dashboard has none of the admin frame: no side menu, no Back link, and a refused user there gets a slightly different message from the other admin pages. (S04, 6.2)

## 3. Who can do what

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| Open an admin page under /settings | no | no | no | yes |
| Open /settings/maintenance and run its actions | no | no | no | yes |
| Open /dashboard (LiveDashboard) | no | no | no | yes |
| See the admin side menu | n/a | no | no | yes |

Sources: `policies/users.ex:19-21`; `hooks.ex:40-53`; `maintenance_live/index.ex:16-29`, `:32-66`, `:91-98`; `user_auth.ex:415-438`; roles are only `:user` and `:superuser` (`lib/lightning/accounts/user.ex:16-19`); `support_user` is a separate flag the policy ignores. Tests: `test/lightning/policies/user_permissions_test.exs:62`, `:82`.

**Preconditions beyond role**
- Signed-out, revoked, TOTP-pending and locked-out sessions are refused first by shared-authenticated-session; `InitAssigns` runs before `:ensure_admin` on every admin route (`init_assigns.ex:17-35`, `router.ex:268`, `:365-368`).
- /dashboard is also gated by the `:require_superuser` plug on the HTTP request (`router.ex:360-361`, `user_auth.ex:415-438`).

## 4. What it touches

**Reads**: `users.role` of the session user (loaded by shared-authenticated-session); `projects` and `project_users` for the global picker on every admin page (`settings.html.heex:104-106`, `layout_components.ex:461-497`, `projects.ex:1210`). /dashboard additionally reads BEAM, OS (`os_mon`, `mix.exs:65`) and Postgres statistics (`ecto_psql_extras`, `mix.exs:115`) through Phoenix LiveDashboard 0.8.7 (`mix.lock:103`).

**Writes**: none

**Immediate side effects**
- A refusal sets flash `:nav` to `:no_access` (hook and maintenance) or `:no_access_no_back` (/dashboard plug) and redirects to `/projects` (`hooks.ex:48-51`, `maintenance_live/index.ex:24-27`, `user_auth.ex:431-435`, `:514`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `:settings_menu_items_extension` (`layout_components.ex:188-205`)
- `Lightning.Extensions.Routing` decides whether /settings/users exists (`config/config.exs:50-61`, `router.ex:340-356`); recorded on admin-users

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Superuser admin space
  In order to run the instance safely
  As a superuser
  I want every admin page behind one gate and inside one admin frame

  @S01 @pending
  Scenario: The admin side menu leads to each admin area and marks the current one
    # Value: instance admins move between users, projects, login, audit, collections and maintenance in one click, can see where they are, and can get back to their own work.
    Given I am a superuser
    When I open "/settings/audit"
    Then the side menu shows "Projects", "Users", "Authentication", "Audit", "Collections", "Maintenance" and "Back"
    And "Audit" is marked as current
    When I click "Back"
    Then I am on "/projects"
    # settings.html.heex:41-91; menu.ex:119-157 (aria-current on the active item); audit_live/index.ex:16, :23
    # active items per view: user_live/index.ex:13, user_live/edit.ex:15, project_live/index.ex:48, auth_providers/index.ex:15, collection_live/index.ex:19, maintenance_live/index.ex:20

  @S02 @pending
  Scenario Outline: A non-superuser is turned away from every admin page
    # Value: only instance admins can read or change instance-wide accounts, projects, login settings, audit history, collections and adaptor maintenance.
    Given I am signed in as a regular user
    When I visit "<path>"
    Then I am on "/projects"
    And I see "No Access" and "Sorry, you don't have access to that."
    And I see a "Back" button

    Examples:
      | path                     |
      | /settings/users          |
      | /settings/users/<my id>  |
      | /settings/projects       |
      | /settings/audit          |
      | /settings/authentication |
      | /settings/collections    |
      | /settings/maintenance    |
    # hooks.ex:40-53 (maintenance: maintenance_live/index.ex:23-28); live_helpers.ex:89-95, :133-137; live.html.heex:94-96
    # user_live_test.exs:729-749, project_live_test.exs:34-40, audit_live_test.exs:13-20,
    # auth_providers_live_test.exs:25-34, collection_live_test.exs:7-16, maintenance_live/index_test.exs:12-21, hooks_test.exs:47-54, :65-71

  @S03 @pending
  Scenario: An admin page refuses a non-superuser websocket mount
    # Value: admin event handlers can't be invoked by a socket that never went through an HTTP check, such as a reconnecting client.
    Given I am signed in as a regular user
    When my browser mounts "/settings/projects" over the live socket
    Then the mount is halted before the page renders
    And I am redirected to "/projects" with "No Access"
    # hooks.ex:28-30 (comment), :45-52; hooks_test.exs:65-71 (asserts :redirect or :live_redirect)

  @S04 @pending
  Scenario: A non-superuser is turned away from the system dashboard
    # Value: process, memory and database internals of the instance are visible only to the people who run it.
    Given I am signed in as a regular user
    When I visit "/dashboard"
    Then I am on "/projects"
    And I see "Sorry, you don't have access to that."
    And I do not see a "Back" button
    # router.ex:360-361; user_auth.ex:415-418, :431-435, :514; live_helpers.ex:97-103
    # test/lightning_web/controllers/live_dashboard_test.exs:14-31 (asserts the redirect and the message, not the missing button)

  @S05 @pending
  Scenario: The system dashboard also checks the socket mount
    # Value: a client that reconnects straight to the dashboard socket, skipping the HTTP plugs, still can't see it unless it is a superuser.
    Given the "/dashboard" route
    Then its socket mount runs "InitAssigns" and then "ensure_admin"
    Given I am a superuser
    When I visit "/dashboard"
    Then I am on "/dashboard/home"
    # router.ex:363-369; live_dashboard_test.exs:33-47, :49-69

  @S06 @pending
  Scenario: Demoting a superuser hands off to the revocation flow
    # Value: taking away superuser rights takes effect on admin pages the person already has open.
    Given "amara@example.org" is a superuser with "/settings/users" open
    When another superuser changes her role to user and saves
    Then the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    # accounts.ex:177-201, :204-216 (role change revokes "session" tokens and disconnects sockets);
    # on reconnect the session gate and S02 refuse her

  @S07 @pending @variant:settings-menu-extension
  Scenario: A deployment adds its own items to the admin menu
    # Value: hosted deployments can put their own admin pages in the same menu as the built-in ones.
    Given the instance configures a settings menu extension component
    When I open "/settings/projects" as a superuser
    Then the side menu shows the extension's items after "Maintenance" and before "Back"
    And an extension item matching the current page is marked as current
    # settings.html.heex:83-86; layout_components.ex:188-205; test/lightning_web/components/layout_components_test.exs:277-320
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The project delete route sets `active_menu_item: :settings`, which matches no admin menu item | `project_live/index.ex:82-93` (line 86), `settings.html.heex:41-82` | on `/settings/projects/:id/delete` nothing in the side menu is marked current, though the list behind the modal is Projects | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The gate is declared per LiveView module, not on the `:settings` live_session, which mounts only `InitAssigns`; an admin LiveView added to the session without the hook would open to every signed-in user | `router.ex:268`; module lines in `reachable_when` | decide |
| MaintenanceLive.Index does not use the hook; it checks the policy itself in `mount` and in each `handle_event`, and refuses with `push_navigate` instead of `redirect` | `maintenance_live/index.ex:16-29`, `:32-66`, `:91-98` | decide |
| The hook refuses with a full `redirect`; maintenance with `push_navigate`. Both land on `/projects` with the same card; the test accepts either | `hooks.ex:48-51`, `maintenance_live/index.ex:24-27`, `hooks_test.exs:65-71` | preserve |
| /dashboard refused over HTTP gets `:no_access_no_back` (no Back button); refused over the socket by the hook it gets `:no_access` (Back button) | `user_auth.ex:433`, `hooks.ex:50` | decide |
| `/settings/users` sits in the `:services` live_session (config-injected) while every other admin route is in `:settings`; menu links use `navigate`, so moving to or from Users is a full page load. UserLive.Index is mounted in both sessions (`/settings/users/:id/delete` is in `:settings`) | `router.ex:268-271`, `:340-356`; `config/config.exs:60`; `menu.ex:148` | decide |
| The settings layout defaults `side_menu_theme` to `"sudo-variant"`, so the admin sidebar and picker are coloured differently from the project sidebar (`"primary-theme"`) | `layouts.ex:11`, `:15`; `settings.html.heex:27`, `:35`; `layout_components.ex:493` | preserve |
| The "Authentication" item links to `/settings/authentication/new`; that route renders an empty provider form even when one exists, while `/settings/authentication` shows the existing provider and only redirects to `/new` when there is none | `settings.html.heex:55-61`; `auth_providers/index.ex:24-49` | decide |
| On `/settings/projects/:id` and its delete route the global picker marks the project being edited as the current project, because ProjectLive.Index assigns `project` and the picker reads `assigns[:project]` | `layout_components.ex:476`; `project_live/index.ex:61`, `:88` | decide |
| The settings layout shows info and error flashes as bottom toasts (`live_info_block`, `live_error_block`) rather than `Common.flash`, and has no `live_nav_block` | `settings.html.heex:98-102`; `live_helpers.ex:18-73`; `live.html.heex:92-96` | preserve |
| /dashboard renders Phoenix LiveDashboard's own page with no app sidebar, admin menu or Back link | `router.ex:363-369` | decide |
| LiveDashboard destructive actions (killing processes) are off, since `allow_destructive_actions` is not passed | `router.ex:363-369`; phoenix_live_dashboard 0.8.7 default | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `on_mount(:ensure_admin, ...)` clause for `current_user: nil` | `hooks.ex:31-38` | every route using the hook runs `InitAssigns` first, which halts to `/users/log_in` when there is no user (`init_assigns.ex:23-24`; `router.ex:268`, `:365-368`; `config/config.exs:51`); only the unit test reaches it (`hooks_test.exs:56-63`) |
| Non-superuser branches of `handle_event("refresh_adaptors")` and `handle_event("refresh_icons")` | `maintenance_live/index.ex:44-49`, `:60-65` | `current_user` is fixed for the socket's life and `mount` already refused a non-superuser; a role change disconnects the socket (`accounts.ex:192`, `:212-216`) |
| JSON branch of `require_superuser` (403) | `user_auth.ex:424-429` | /dashboard pipes through `:browser`, which accepts only `html` (`router.ex:22`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The settings layout calls `global_project_picker` with the whole `assigns`, so the project tree query and JSON encoding can re-run on every render of an admin page; same issue as the live layout in shared-project-header 6.4 | `settings.html.heex:104-106`; `layout_components.ex:461-475` | no | decide |

### 6.5 Things seen but not understood

- "Admin Menu" in the project sidebar lands on `/settings/projects` (shared-project-header S17); it is not clear whether Projects is meant to be the admin home or just the first menu item.
- Whether every admin view renders `LayoutComponents.header`, and so the confirmation banner from shared-project-header S13 and S14, is a per-view question; admin-users says it does. Each admin view should confirm.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the admin gate move to the live_session (or a router-level plug) so a new admin page can't ship ungated (6.2 row 1), and should maintenance join it? (owner: security)
- Should /dashboard keep its own layout, or sit inside the admin frame with the menu and a Back link (6.2)? (owner: product)
- Should the "Authentication" menu item open the existing provider instead of an empty form (6.2)? (owner: product)
- Should refusals from /dashboard and the admin pages show the same card, with or without Back (6.2)? (owner: product)

## Proposed flows

none; references flow-account-revocation-teardown (S06).

## Proposed shared

none

## Summary

- Scenarios: 7 (S01 to S07), all `@pending`; S07 tagged `@variant:settings-menu-extension`.
- Section 6: 6.1 has 1, 6.2 has 11, 6.3 has 3, 6.4 has 1, 6.5 has 2.
- Flows: none proposed; references flow-account-revocation-teardown (S06 handoff).
- Shared: none proposed; inherits shared-authenticated-session and shared-project-header (no-project parts).
- Unsure: LiveDashboard's destructive-actions default is read from the 0.8.7 library default, not from code in this repo; S03 is asserted through `live/2`, which does an HTTP request first, so a socket-only mount is not directly tested for admin pages; signed-out handling is left to shared-authenticated-session S01 because the hook's own nil clause is unreachable.
