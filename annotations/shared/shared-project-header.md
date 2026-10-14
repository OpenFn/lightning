---
id: shared-project-header
type: shared
title: Project page header and project picker
status: not-started
owner:

trigger:
  old_route: any project LiveView that renders `LayoutComponents.header` with `breadcrumb_project_picker`, inside the live layout
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (see shared-project-scope), which assigns `project` and `project_label` (`lib/lightning_web/hooks.ex:103-120`)
    - the page is not first setup (`lib/lightning_web/components/layouts/live.html.heex:42`, `:109`)

inherits:
  - shared-authenticated-session    # owns the unconfirmed-account warning itself (its S06), sidebar toggle, Ctrl/Cmd+M, hover expand, GDPR and book-a-demo banners
  - shared-project-scope            # owns who may mount the page; this file only covers what the header shows once mounted

url_params: []

config_variants:
  default: {}                                                                       # read under this one unless a scenario is tagged
  require-email-verification: { lightning.require_email_verification: true }       # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389
  experimental-features: { user.preferences.experimental_features: true }           # accounts.ex:1446-1448
  support-user: { current_user.support_user: true }                                 # projects.ex:1349-1365
  custom-menus: { lightning.menu_items: %{component, assigns_keys}, lightning.user_menu_items: %{component, assigns_keys} }   # layout_components.ex:54-58, :207-231; not set anywhere in this repo

inventory:
  routes: []
  events: []
  js_hooks:
    - ReactComponent PickerButton (breadcrumb trigger, layout_components.ex:395-420, assets/js/picker/PickerButton.tsx)
    - ReactComponent Picker (global project picker modal, layout_components.ex:461-497, assets/js/picker/Picker.tsx)
    - OpenProjectPickerViaCtrlP (exported, never mounted; see 6.3)
  policies: []                    # picker contents come from a membership query, not a policy module
  workers: []
  api_endpoints: []
  emails: []                      # the resend email belongs to the proposed flow
  config:
    - :lightning, :require_email_verification (banner gate, layout_components.ex:263)
    - :lightning, :menu_items
    - :lightning, :user_menu_items
    - :lightning, :emails, :admin_email (Support link, live.html.heex:69)
  not_reachable_here:
    - header `:title` slot and `<h1>` branch (layout_components.ex:283-296); every project view passes breadcrumbs
    - header `:period` and `:description` slots, declared but never rendered (layout_components.ex:255-256); the `:period` gap is recorded in workflows-index 6.1
    - Menu.profile_items (menu.ex:89-110) and the settings layout menu (layouts/settings.html.heex:39-91); non-project pages only
    - the collaborative editor's own header and EmailVerificationBanner (assets/js/collaborative-editor/CollaborativeEditor.tsx:241-252, components/EmailVerificationBanner.tsx); it reuses PickerButton and the global Picker but not `LayoutComponents.header`

related:
  - workflows-index
  - history-work-orders              # also /history/channels (RunLive.Index :channel_logs)
  - project-settings-setup
  - project-settings-collaborators
  # Not yet annotated, render the same header and picker:
  #   RunLive.Show (run_live/show.ex:65-91), DataclipLive.Show (dataclip_live/show.ex:49-66),
  #   ChannelRequestLive.Show (channel_request_live/show.ex:55-76), WorkflowLive.Health (workflow_live/health.ex:30-46),
  #   ChannelLive.Index (channel_live/index.ex:28-40), SandboxLive.Index (sandbox_live/index.ex:564-576),
  #   the other ProjectLive.Settings panels (project_live/settings.html.heex:9-22)
  # Get the side menu and global picker but not this header: WorkflowLive.Collaborate (workflow editor)
flows:
  - flow-resend-account-confirmation   # proposed, see end of file
---

## 1. Purpose

Every project page opens with the same frame: a header that says which project you are in and how
you got to this page, a menu of the project's areas, and a picker for jumping to another project or
sandbox. People who work across many projects and sandboxes rely on it to avoid acting in the wrong
one, and to move between them without losing their place.

## 2. What it does

- Everyone on the project sees a breadcrumb trail ending in the current page, with links back up
- Everyone sees the current project's name on the picker button, and sandboxes stand out in their colour
- Everyone opens the picker by button or Ctrl/Cmd+P and sees only the projects and sandboxes they can reach
- Everyone searches the picker by project path
- Everyone switches project and lands on the same section, or the nearest page that exists
- Everyone reaches the full projects list from the picker
- Unconfirmed users on verifying instances can ask for a new confirmation email from the header
- Everyone moves between the project's areas from the side menu, with the current one marked
- Users with experimental features on see Channels in the menu and are told the mode is on
- Superusers reach the admin pages from the menu; everyone else reaches documentation, community and support
- Everyone reaches their profile, credentials, API tokens and log out from the account menu

## 3. Who can do what

| Action | Viewer | Editor | Admin | Owner | Superuser (with a role) | Support user |
|--------|--------|--------|-------|-------|-------------------------|--------------|
| See the header, breadcrumbs and picker button | yes | yes | yes | yes | yes | yes |
| See a project in the picker | if member | if member | if member | if member | if member | if member, or project allows support access |
| See project menu items | yes | yes | yes | yes | yes | yes |
| See Admin menu and Sys info | no | no | no | no | yes | no |
| See Documentation, Community, Support | yes | yes | yes | yes | no | yes |

Sources: `lib/lightning/projects.ex:1349-1372`, `:1519-1536` (picker membership); `lib/lightning_web/components/layouts/live.html.heex:45-79` (superuser branch). Project role plays no part in the header itself.

**Preconditions beyond role**
- Picker rows exclude projects scheduled for deletion (`projects.ex:1361`, `:1370`, `:1295`, `:1303`).
- Authority does not cascade: a parent membership does not list its sandboxes unless the user has a row on them (`projects.ex:1199-1202`, `:1535-1536`).
- Channels menu item requires experimental features on the viewer (`lib/lightning_web/live/components/menu.ex:54-61`).
- The resend banner requires `require_email_verification`, a signed-in user and `confirmed_at` nil (`layout_components.ex:261-266`).

## 4. What it touches

**Reads**: `projects` and `project_users` (picker tree, `projects.ex:1210-1220`; label via ancestor walk, `projects.ex:1456-1505`); `users.preferences.experimental_features` (`accounts.ex:1446-1448`); `users.inserted_at`, `users.confirmed_at` (banner, `layout_components.ex:265-270`)

**Writes**: none

**Immediate side effects**
- none; the picker navigates in the browser with a LiveView redirect link (`assets/js/picker/Picker.tsx:212-222`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none here; "Resend confirmation email" is a plain link to a controller that sends email (see Proposed flows)

**Depends on config**
- `require_email_verification` (`layout_components.ex:263`), `menu_items` and `user_menu_items` (`layout_components.ex:54-58`, `:207-231`), `emails.admin_email` (`live.html.heex:69`, default `lightning@example.com` at `bootstrap.ex:462-467`), `max_sandbox_nesting_depth` bounds the tree walks (`projects.ex:50-52`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Project page header and project picker
  In order to know which project I am acting in and move between projects and their areas
  As anyone working in a project
  I want every project page to show the same header, picker and menu

  @S01 @pending
  Scenario: Breadcrumbs show where I am and link back up
    # Value: people see how they reached a page and get back to the list in one click.
    Given I am an editor on project "Malawi HIV"
    When I open a run's page in project "Malawi HIV"
    Then the breadcrumbs show the project picker, then "History" as a link to the project's history, then the run's title
    And the last crumb is not a link
    # layout_components.ex:369-388, :427-449; run_live/show.ex:67-89
    # test/lightning_web/components/layout_components_test.exs:320-337

  @S02 @pending
  Scenario: The picker button names the current project
    # Value: people know which project they are about to change before they change anything.
    Given I am an editor on project "Malawi HIV"
    When I open the project's workflows page
    Then the project picker button reads "Malawi HIV"
    # hooks.ex:103-119, layout_components.ex:395-420
    # test/lightning_web/live/project_live_test.exs:853-857

  @S03 @pending
  Scenario: A sandbox is labelled and coloured as a sandbox
    # Value: someone working in a sandbox can't mistake it for the live project.
    Given project "Malawi HIV" has a sandbox "dev" with colour "#E33D63"
    And I am an editor on both
    When I open the workflows page of sandbox "dev"
    Then the picker button reads "Malawi HIV:dev" on a "#E33D63" background with a beaker icon
    # hooks.ex:103-111, projects.ex:1495-1505, layout_components.ex:399-417, PickerButton.tsx:37-83
    # layout_components_test.exs:106-131 asserts data-label "parent-project/my-sandbox", data-is-sandbox "true", data-color

  @S04 @pending
  Scenario: The picker lists only projects I can reach, with the current one marked
    # Value: switching projects never reveals a project someone isn't on.
    Given I am a member of "project-1" and "project-2"
    And "project-3" exists with other members only
    When I open "project-1" and open the project picker
    Then I see "project-1" marked as current and "project-2"
    And I do not see "project-3"
    # layout_components.ex:461-497, projects.ex:1367-1372, Picker.tsx:330, :373-387
    # project_live_test.exs:826-880

  @S05 @pending
  Scenario: Sandboxes nest under the nearest project I can see
    # Value: a collaborator invited only to a sandbox can still switch to it, without seeing projects above it.
    Given project "Malawi HIV" has sandbox "dev", which has sandbox "feature"
    And I am a member of "Malawi HIV" and "feature" but not "dev"
    When I open the project picker
    Then "feature" is listed directly under "Malawi HIV"
    And "dev" is not listed
    And if I am a member of "feature" only, "feature" is listed at the top level
    # projects.ex:1189-1220, :1260-1288, layout_components.ex:500-532
    # layout_components_test.exs:144-245

  @S06 @pending
  Scenario: Projects scheduled for deletion are not offered
    # Value: nobody switches into a project that is being wound down.
    Given I am a member of "Malawi HIV" and "Old pilot"
    And "Old pilot" is scheduled for deletion
    When I open the project picker
    Then I do not see "Old pilot"
    # projects.ex:1361, :1370, :1295, :1303

  @S07 @pending @variant:support-user
  Scenario: Support users see projects that allow support access
    # Value: support staff can reach a customer project that granted access without being added to it.
    Given I am a support user with no role on project "Malawi HIV"
    And "Malawi HIV" allows support access
    When I open the project picker
    Then I see "Malawi HIV"
    # projects.ex:1349-1365, :1519-1529

  @S08 @pending
  Scenario: Searching matches the full path and keeps parents in view
    # Value: in a long list, people find a sandbox by its parent's name and can tell same-named sandboxes apart.
    Given I can reach "Malawi HIV" with sandbox "dev" and "Kenya TB" with sandbox "dev"
    When I open the project picker and type "malawi/d"
    Then I see "Malawi HIV" and its "dev"
    And I do not see "Kenya TB"
    # layout_components.ex:513-521 (searchLabel), Picker.tsx:104-131

  @S09 @pending
  Scenario: Switching project keeps me in the same section and tab
    # Value: people compare the same page across projects, such as production and a sandbox, in one step.
    Given I am a member of "Malawi HIV" and "Kenya TB"
    And I am on the collaborators tab of "Malawi HIV" settings
    When I pick "Kenya TB" in the project picker
    Then I am on the collaborators tab of "Kenya TB" settings
    # layout_components.ex:544-563, Picker.tsx:212-222
    # test/lightning_web/project_picker_sections_test.exs:46-58

  @S10 @pending
  Scenario Outline: Switching from a page that has no equivalent lands on one that does
    # Value: a switch never lands on a missing page for an id that only exists in the first project.
    Given I am a member of "Kenya TB"
    And I am on <page>
    When I pick "Kenya TB" in the project picker
    Then I am on <landing> of "Kenya TB"
    Examples:
      | page                                  | landing             |
      | a run's page                          | the history page    |
      | a dataclip's page                     | the history page    |
      | a workflow's editor                   | the workflows page  |
      | the projects list or my profile       | the workflows page  |
    # layout_components.ex:544-563
    # project_picker_sections_test.exs:55-91

  @S11 @pending
  Scenario: The picker opens from the keyboard
    # Value: people who switch projects often can do it without reaching for the mouse.
    Given I am on any page in the live layout
    When I press Ctrl+P, or Cmd+P on a Mac
    Then the project picker opens with the search box focused
    When I press the down arrow and Enter
    Then I am taken to the highlighted project
    # Picker.tsx:142-167, :224-248; live.html.heex:109-113

  @S12 @pending
  Scenario: The picker leads to the full projects list
    # Value: people can reach every project, and create one, from wherever they are.
    When I open the project picker
    And I choose "View all projects"
    Then I am on "/projects"
    # layout_components.ex:490-491, Picker.tsx:292-321

  @S13 @pending @variant:require-email-verification
  Scenario: Confirmed users and non-verifying instances show no confirmation banner
    # Value: people with nothing left to do are not nagged on every page.
    Given my email is confirmed, or the instance does not require email verification
    When I open any page with the header
    Then I do not see the account confirmation banner
    # layout_components.ex:261-266
    # test/lightning_web/live/accounts_confirmation_live_test.exs:16-24, :41-58, :76-97 (asserted on /projects, same component)

  @S14 @pending @variant:require-email-verification
  Scenario: Asking for a new confirmation email hands off to the resend flow
    # Value: an unconfirmed user can get a fresh link from wherever they are working, before the deadline locks them out.
    Given my account was created 2 hours ago and my email is unconfirmed
    And I am on the project's workflows page
    When I click "Resend confirmation email"
    Then the flow "flow-resend-account-confirmation" has started
    # layout_components.ex:271-276, common.ex:266-271 (plain link), router.ex:236
    # The warning text itself is shared-authenticated-session S06

  @S15 @pending
  Scenario: The side menu leads to each area of the project and marks the current one
    # Value: people move between a project's areas in one click and can see which one they are in.
    Given I am a viewer on project "Malawi HIV"
    When I open the project's settings
    Then the side menu shows "Workflows", "Sandboxes", "History" and "Settings" for "Malawi HIV"
    And "Settings" is marked as current
    # layout_components.ex:207-231, menu.ex:44-87, project_live/settings.ex:197
    # test/lightning_web/components/menu_test.exs:60-99

  @S16 @pending @variant:experimental-features
  Scenario: Experimental features add Channels and say so
    # Value: unfinished features stay out of the way of people who haven't opted in, and people who have can tell.
    Given I have experimental features turned on
    When I open project "Malawi HIV"
    Then the side menu shows "Channels"
    And the side menu shows "Experimental"
    And the account menu says "Experimental features on" with a link "Turn off in your profile"
    When I turn experimental features off
    Then none of these appear
    # menu.ex:18-37, :54-61; layout_components.ex:111-134
    # menu_test.exs:33-57, layout_components_test.exs:11-31

  @S17 @pending
  Scenario: Superusers reach administration; everyone else reaches help
    # Value: instance admins get to user and project administration from any project, and other users always have a route to help.
    Given I am a superuser with a role on project "Malawi HIV"
    When I open the project's workflows page
    Then the side menu shows "Admin Menu" linking to "/settings/projects" and "Sys Info" linking to "/dashboard"
    Given I am an editor who is not a superuser
    When I open the project's workflows page
    Then the side menu shows "Documentation", "Community" and "Support"
    # live.html.heex:45-79

  @S18 @pending
  Scenario: The account menu shows who I am and where my account settings are
    # Value: people sharing a machine can see which account is signed in, and reach account settings or log out from any project.
    Given I am signed in as "amara@example.org"
    When I open the account menu
    Then I see "Signed in as" and "amara@example.org"
    And I see "Projects", "User Profile", "Credentials", "API Tokens" and "Log out"
    # layout_components.ex:50-185, live.html.heex:29-31
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Every breadcrumb link carries `aria-current="page"`, though each one points to a different page from the current one | `layout_components.ex:436-439` | screen readers announce "History" or "Workflows" as the current page on a run or health page | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Breadcrumb links use `patch` even when the target is another LiveView (run page to History, health to Workflows); LiveView then falls back to a full page load | `layout_components.ex:435-441`, `run_live/show.ex:72-74`, `workflow_live/health.ex:37-40` | decide |
| Picker items and current project are rendered into a `phx-update="ignore"` container, so an open page does not pick up being added to, or removed from, another project until it navigates | `layout_components.ex:482-485` | decide |
| Switching from channel logs (`/history/channels`) lands on the target's work orders tab, not its channel logs | `layout_components.ex:553-555` | decide |
| The URL hash is carried over on same-section switches, so a workflow editor hash is applied to the target's workflow list | `Picker.tsx:212-213`, `layout_components.ex:553-555` | preserve |
| Sandboxes deeper than two levels show only the last two names on the button, with "…" and a tooltip of the full path joined by " > " | `PickerButton.tsx:46-96` | preserve |
| Picker rows sort by name within each level; search matches anywhere in the path, case-insensitive | `layout_components.ex:508`, `Picker.tsx:106-111` | preserve |
| Escape and a click outside close the picker; Ctrl/Cmd+P toggles it and overrides the browser's print shortcut | `Picker.tsx:153-185`, `:256-262` | preserve |
| Superusers do not get the Documentation, Community and Support links | `live.html.heex:45-79` | decide |
| "Support" is a mailto to `emails.admin_email`, which defaults to `lightning@example.com` when `EMAIL_ADMIN` is unset | `live.html.heex:68-77`, `bootstrap.ex:462-467` | decide |
| Documentation and Community open in a new tab (`menu_item` defaults `target` to `_blank`); Support overrides to `_self` | `menu.ex:115`, `live.html.heex:68-70` | preserve |
| `DataclipLive.Show` sets `active_menu_item: :dataclip`, which matches no menu item, so nothing is marked current on a dataclip page | `dataclip_live/show.ex:16`, `menu.ex:44-87` | decide |
| The sidebar's experimental indicator doc says it links to the profile; it renders no link (the account menu's version does) | `menu.ex:11-16`, `menu_test.exs:45` | preserve |
| The confirmation deadline in the banner is formatted in UTC regardless of the viewer's time zone | `layout_components.ex:270` | decide |
| "Resend confirmation email" is a GET that sends mail, and returns to the referring path without its query string | `common.ex:267`, `user_confirmation_controller.ex:51-86` | decide |
| Sidebar footer shows the release version chip | `layout_components.ex:630-650` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `OpenProjectPickerViaCtrlP` hook | `assets/js/hooks/KeyHandlers.ts:392-421`, exported at `hooks/index.ts:24`, `:45` | no template mounts it; the Picker's own key listener handles Ctrl/Cmd+P. It would also click the wrapper `div`, not the button |
| `jobs` section in `project_picker_target/2` | `layout_components.ex:554`, `project_picker_sections_test.exs:15` | the only `/projects/:project_id/jobs` route is a controller endpoint (`router.ex:203`), not a page the picker is opened from |
| `global_picker` layout attr | `layouts.ex:12`, `:16`; `live.html.heex:110` | nothing in this repo passes it; an extension point for downstream deployments |
| Custom `menu_items` and `user_menu_items` components | `layout_components.ex:54-58`, `:135-140`, `:207-218` | not configured in this repo; variant `custom-menus` replaces the project menu and the account menu entirely |
| Header `:period`, `:description` slots and the `socket` attr | `layout_components.ex:251-256` | declared, never rendered |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The live layout calls `global_project_picker` with the whole `assigns`, which defeats change tracking, so the project tree queries and JSON encoding can re-run on every render of a project page | `live.html.heex:110-112`, `layout_components.ex:464-475`, `projects.ex:1210-1220` | no | decide |
| Picker list is not paginated or capped; every reachable project and sandbox is shipped in `data-items` | `layout_components.ex:464-476` | yes, on accounts with very many projects | preserve |

### 6.5 Things seen but not understood

- `hooks.ex:88` and `:120` still load and assign `:projects` on every project mount. The picker no longer reads it (it calls `get_project_tree_for_user/1`); in project views only the credential components use it. shared-project-scope 6.4 describes it as "for the picker", which is now out of date.
- After the picker's LiveView redirect to another project, it is not clear whether the `phx-update="ignore"` picker container keeps the previous project's `data-current-id` and hrefs or is replaced. Needs an old-app run.
- `project_picker_sections_test.exs` refers to `project_picker_href/2`, which no longer exists; the assertions call `project_picker_target/2`.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should superusers keep losing the help links (6.2), and should the Support link ship with a placeholder address?
- Should the picker refresh while a page is open (6.2), now that membership changes elsewhere already re-mount the current project?
- Should switching from channel logs keep the channel logs tab?

## Proposed flows

- `flow-resend-account-confirmation`: "Resend confirmation email" in the header is a GET to `/users/send-confirmation-email` (`router.ex:236`). The controller sends only when `confirmed_at` is nil (`user_confirmation_controller.ex:51-77`), rate limits to 3 per 15 minutes per account (`accounts.ex:758-782`, `:1197-1206`), inserts a `user_tokens` confirm token (`accounts.ex:1135-1142`), sends "Confirm your OpenFn account" (`user_notifier.ex:121-133`), and redirects back to the referring path with "Confirmation email sent successfully", the throttle message (`confirmation_lockout.ex:12-14`) or an error flash. Surfaces: any view inheriting this header, controller:user-confirmation-send-email, email:remind-account-confirmation, the original view. This file asserts only the handoff (S14).

## Proposed shared

none
