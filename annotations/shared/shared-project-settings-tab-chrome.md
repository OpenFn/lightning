---
id: shared-project-settings-tab-chrome
type: shared
title: Project settings tab chrome
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings (ProjectLive.Settings :index), every tab
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the page renders `Tabbed.container id="project-settings-container"` (settings.html.heex:25-29, :1101)
    - sandbox banners only when `Project.sandbox?/1` is true, i.e. the project has a `parent_id` (project.ex:228-229, settings.ex:108-110)

inherits: []                                  # the views that inherit this also inherit shared-project-scope, shared-usage-limits-banner, shared-authenticated-session

url_params:
  - name: "#<tab> (URL fragment: project, credentials, collections, webhook_security, collaboration, security, vcs, data-storage, history-exports)"
    set_by: >-
      the tab strip itself; GitHub sync redirects (#vcs, github_sync_component.ex:46-90, settings.ex:695);
      collaborator add/remove and limit redirects (#collaboration, new_collaborator_component.ex:54,
      invite_collaborator_component.ex:74, settings.ex:675, live_helpers.ex:223); dashboard (#collaboration,
      dashboard_live/components.ex:128); credential error links (#credentials, error_formatter.ex:46,
      channel_live/form_component.ex:156); channel form (#webhook_security, channel_live/form_component.ex:187);
      dataclip and run viewers (#data-storage, viewers.ex:334, :343, run_live/components.ex:563);
      retention change email (#data-storage, user_notifier.ex:195); GitHubSyncModal (#vcs, GitHubSyncModal.tsx:139)
    effect: client-side only; the TabbedContainer hook shows that tab's panel on mount, falling back to "project" when there is no fragment (TabbedContainer.ts:13-28). The server never sees it (settings.ex:233).

config_variants:
  default: {}                                 # read under this one; nothing here is config-dependent
  sandbox: { project.parent_id: <parent project id> }   # data state rather than config, named so banner scenarios can be tagged

inventory:
  routes: []                                  # owns no route; the host route is catalogued by project-settings-setup
  events: []
  js_hooks:
    - TabbedContainer                         # assets/js/hooks/TabbedContainer.ts, tabbed.ex:72
    - lv-keep-class / lv-keep-aria DOM patch rules (assets/js/app.js:69-104)
  policies:
    - Lightning.Policies.ProjectUsers (:edit_project, :create_project_credential, :write_webhook_auth_method, :write_github_connection, :initiate_github_sync, :edit_data_retention) as read for the notice only
    - Lightning.Policies.Collections (:manage_collection) as read for the notice only
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Tabbed.container horizontal orientation (tabbed.ex:25-58); used only by run_live/show.ex:228
    - Tabbed disabled tab with Tooltip (tabbed.ex:108-123); no settings tab passes `disabled`
    - TabbedContainer `push-hash` server event (TabbedContainer.ts:16-19); nothing pushes it (see 6.3)
    - section_header attrs `options` and `role` (layout_components.ex:578-579); never read

related:
  - project-settings-setup
  - project-settings-credentials
  - project-settings-collections
  - project-settings-webhook-security
  - project-settings-collaborators
  - project-settings-security
  - project-settings-github-sync
  - project-settings-data-storage
  - project-settings-history-exports
flows: []
---

## 1. Purpose

Project settings is one page with nine tabs, and every tab opens the same way: a heading, a
notice when the viewer's role doesn't let them change that tab, and, in a sandbox, a banner saying
whether changes made there reach the parent project on merge. Members use the tabs to find a
setting, often by following a link straight to it. Without this chrome a read-only member would
face disabled controls with no reason given, and someone working in a sandbox could change a
setting believing it will merge back when it won't, or the reverse.

## 2. What it does

- Opening project settings shows the Setup tab
- A link to a tab opens that tab, and the address bar names the open tab
- The open tab stays open while the page updates
- Every member who can open the project sees all nine tabs
- Members whose role can't change a tab are told so at the top of it
- In a sandbox, each tab says whether its changes stay local, sync to the parent on merge, or are inherited from the parent
- Outside a sandbox, no sandbox banner shows

## 3. Who can do what

Notice shown at the top of each tab ("Role based permissions: You cannot modify this project's
..."). The notice is display only; each tab's own view disables its controls and re-checks on
submit. Sources: `lib/lightning/policies/project_users.ex:29-49`, `:134`, `:160-172`;
`lib/lightning/policies/collections.ex:73-75`; `lib/lightning/projects/scope.ex:139-147`; flags
computed at `lib/lightning_web/live/project_live/settings.ex:118-188`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab strip and all nine tabs | yes | yes | yes | yes | no (cannot open the project) | yes |
| See sandbox banners (sandbox only) | yes | yes | yes | yes | no | yes |
| Notice on Setup ("basic settings, but you can export a copy.") | yes | yes | no | no | n/a | yes |
| Notice on Credentials ("available credentials.") | yes | no | no | no | n/a | no |
| Notice on Collections ("available collections.") | yes | yes | no | no | n/a | yes |
| Notice on Webhook security, not a sandbox ("webhook auth methods.") | yes | yes | no | no | n/a | yes |
| Notice on Collaboration ("collaboration settings, but you can change your notification preferences.") | yes | yes | no | no | n/a | yes |
| Notice on Security, not a sandbox ("multi-factor authentication settings.") | yes | yes | no | no | n/a | yes |
| Notice on Sync to GitHub ("version control configuration.") | yes | no | no | no | n/a | no |
| Notice on Sync to GitHub ("version control configuration but you can initiate a sync.") | no | yes | no | no | n/a | yes |
| Notice on Data storage ("data storage settings.") | yes | yes | no | no | n/a | yes |
| Notice on History exports | no | no | no | no | n/a | no |
| Notice on Security or Webhook security in a sandbox | no | no | no | no | n/a | no |

Template sources per row: `settings.html.heex:68-79`, `:316-321`, `collections_component.ex:278-283`,
`settings.html.heex:378-383`, `:405-409`, `:571-575`, `:682-689`, `:759-764`, `:863-868`, `:1056-1061`.

**Preconditions beyond role**
- A member who hasn't met the project's MFA requirement never reaches this page (shared-project-scope S05); the policies also deny every action in that state (`project_users.ex:134`).
- Support standing fills editor actions only when the user has no membership row (`project_users.ex:167-169`); Collections asks for a real admin or owner row, so support users always see its notice (`scope.ex:139-147`).
- The sandbox banner depends only on the project having a parent, not on the viewer (`settings.ex:109`).

## 4. What it touches

**Reads**: `projects` (the project and, for a sandbox, its parent via preload, `settings.ex:108-110`); `projects` and `project_users` again for each permission flag (`scope.ex:112-117`, `:166-190`)

**Writes**: none

**Immediate side effects**
- none

**Deferred side effects**
- none; permission flags are fixed at mount and refreshed only when shared-project-scope re-mounts the page on a membership change (shared-project-scope S08)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Project settings tab chrome
  In order to find a setting and know whether I can change it
  As anyone on a project
  I want every settings tab to open the same way and tell me where I stand

  @S01 @pending
  Scenario: Project settings opens on the Setup tab
    # Value: someone arriving from the sidebar lands on the project's basic details, not a blank page.
    Given I am an editor on project "Malawi HIV"
    When I visit "/projects/<project_id>/settings" with no fragment
    Then the "Setup" tab is selected
    And I see "Project setup"
    And no other tab's panel is visible
    # settings.html.heex:28, tabbed.ex:71-72, :145-159; TabbedContainer.ts:13-14, :28, :46-62

  @S02 @pending
  Scenario: A link to a tab opens that tab
    # Value: alerts, emails, flashes and other pages that point at a setting put the user on it, not on Setup.
    Given I am an admin on project "Malawi HIV"
    When I visit "/projects/<project_id>/settings#data-storage"
    Then the "Data Storage" tab is selected
    And I see "Data storage"
    And the "Setup" panel is not visible
    # TabbedContainer.ts:28, :34-62; test/lightning_web/live/project_live_test.exs:3221-3229 loads this URL

  @S03 @pending
  Scenario: Choosing a tab puts it in the address bar
    # Value: a user can bookmark or share the exact tab, and a reload keeps them on it.
    Given I am on project "Malawi HIV" settings on the "Setup" tab
    When I click the "Collaboration" tab
    Then the URL ends in "#collaboration"
    And I see "Project collaboration"
    When I reload the page
    Then the "Collaboration" tab is still selected
    # tabbed.ex:125-133 (href "#<hash>"), TabbedContainer.ts:21-28

  @S04 @pending
  Scenario: The open tab survives a server update
    # Value: saving or validating a form on one tab doesn't throw the user back to Setup mid-task.
    Given I am an admin on project "Malawi HIV" settings on the "Data Storage" tab
    When I change a data storage setting and the page re-renders
    Then the "Data Storage" tab is still selected
    And the "Setup" panel is still hidden
    # tabbed.ex:120, :133, :156 (lv-keep-aria, lv-keep-class); app.js:80-85, :101-107; TabbedContainer.ts:30-32

  @S05 @pending
  Scenario: Read-only members still see every tab
    # Value: viewers can check how a project is set up (who is on it, which credentials and limits it has) without asking an admin.
    Given I am a viewer on project "Malawi HIV"
    When I open the project's settings
    Then I see the tabs "Setup", "Credentials", "Collections", "Webhook Security", "Collaboration", "Security", "Sync to GitHub", "Data Storage" and "History Exports"
    And none of them is disabled
    # settings.html.heex:30-65; no :tab passes disabled (tabbed.ex:108-123)

  @S06 @pending
  Scenario Outline: Members who can't change a tab are told why
    # Value: someone facing disabled controls learns it is their role, not a broken page, and what they can still do.
    Given I am a <role> on project "Malawi HIV"
    When I open the project's settings on the "<tab>" tab
    Then I see "Role based permissions: You cannot modify this project's <message>"
    # layout_components.ex:590-592, :620-627; per-tab sources in section 3
    # project_live_test.exs:3217-3229 (editor) and :3243-3255 (viewer) assert the data storage notice

    Examples:
      | role   | tab              | message                                                                    |
      | viewer | Setup            | basic settings, but you can export a copy.                                 |
      | viewer | Credentials      | available credentials.                                                     |
      | editor | Collections      | available collections.                                                     |
      | editor | Webhook Security | webhook auth methods.                                                      |
      | editor | Collaboration    | collaboration settings, but you can change your notification preferences. |
      | editor | Security         | multi-factor authentication settings.                                      |
      | viewer | Sync to GitHub   | version control configuration.                                             |
      | editor | Sync to GitHub   | version control configuration but you can initiate a sync.                 |
      | editor | Data Storage     | data storage settings.                                                     |

  @S07 @pending
  Scenario: Members who can change a tab see no notice
    # Value: people with the right to act aren't told they can't.
    Given I am an admin on project "Malawi HIV"
    When I open the project's settings
    Then I do not see "Role based permissions" on any tab
    # layout_components.ex:590; admin passes every flag in section 3

  @S08 @pending @variant:sandbox
  Scenario Outline: Sandbox tabs say whether changes reach the parent
    # Value: someone experimenting in a sandbox knows before they change a setting whether merging will carry it to the live project.
    Given I am an owner of sandbox "dev" of project "Malawi HIV"
    When I open the settings of sandbox "dev" on the "<tab>" tab
    Then I see "<copy>"
    # sandbox_settings_banner.ex:30-48; settings.html.heex:80-84, :352-356, :590-594, :765-769, :869-873, :1062-1066; collections_component.ex:290-294
    # test/lightning_web/live/project_live/sandbox_settings_test.exs:105-126

    Examples:
      | tab             | copy                                                                                                   |
      | Setup           | Changes you make here only apply to this sandbox and do not sync to the parent project on merge.       |
      | Collaboration   | Changes you make here only apply to this sandbox and do not sync to the parent project on merge.       |
      | Sync to GitHub  | Changes you make here only apply to this sandbox and do not sync to the parent project on merge.       |
      | Data Storage    | Changes you make here only apply to this sandbox and do not sync to the parent project on merge.       |
      | History Exports | Changes you make here only apply to this sandbox and do not sync to the parent project on merge.       |
      | Credentials     | Changes you make here will sync to the parent project on merge.                                        |
      | Collections     | Changes you make here will sync to the parent project on merge.                                        |

  @S09 @pending @variant:sandbox
  Scenario: Inherited settings point to the parent that owns them
    # Value: a sandbox user who needs a security setting changed is sent to the project where it can be changed.
    Given I am an owner of sandbox "dev" of project "Malawi HIV"
    When I open the settings of sandbox "dev" on the "Security" tab
    Then I see "These settings are inherited from the parent project (Malawi HIV) and cannot be changed here."
    And "Malawi HIV" links to "/projects/<parent_id>/settings"
    # sandbox_settings_banner.ex:50-71; settings.html.heex:690-695; sandbox_settings_test.exs:129-136

  @S10 @pending
  Scenario: A project that isn't a sandbox shows no sandbox banner
    # Value: people in the live project aren't told their changes stay local or merge somewhere.
    Given I am an owner of project "Malawi HIV", which has no parent
    When I open the project's settings
    Then I see no sandbox banner on any tab
    # settings.html.heex:81 and siblings (`:if={@sandbox?}`); sandbox_settings_test.exs:38-43
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A fragment that names no tab (a typo, or an old link) selects nothing: every panel keeps its server-rendered `hidden` class and no tab is highlighted | `TabbedContainer.ts:28`, `:38-44`; `tabbed.ex:147` | the settings page with a tab strip and an empty body until they click a tab | fix |
| The editable banner on Credentials and Collections says changes "will sync to the parent project on merge", but merge only attaches the credentials the merger selects and syncs collections by name, and never deletes a parent collection | `sandbox_settings_banner.ex:40-48`; `lib/lightning/projects/sandboxes.ex:283-289`, `:306-312`, `:344` | a credential or collection removed in the sandbox is still in the parent after merge, despite the banner; not followed into the merge flow | decide |
| The inherited banner on Security says the settings are inherited from the parent, but `requires_mfa` is copied once when the sandbox is created and the parent's MFA toggle updates only the parent | `sandbox_settings_banner.ex:50-60`; `sandboxes.ex:104-107`; `settings.ex:411-427` | turning on MFA in the parent afterwards does not apply to the sandbox, which still reads "inherited"; propagation was not found but not traced exhaustively | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| All nine panels are rendered for every viewer on every mount; tab switching only toggles a CSS class in the browser, and the server never learns which tab is open | `tabbed.ex:145-159`; `TabbedContainer.ts:34-62`; `settings.ex:233` | decide |
| Tabs are plain `#hash` links, so each tab change adds a browser history entry and Back steps through tabs | `tabbed.ex:125-133` | preserve |
| Tabs carry `role="tab"` and `aria-selected`, but there is no arrow-key navigation, and no tab is marked selected until the hook runs | `tabbed.ex:125-133`; `TabbedContainer.ts:46-56` | decide |
| History exports passes `can_perform_action={true}`, so its notice ("history exports.") can never show | `settings.html.heex:1056-1061` | preserve |
| In a sandbox, Security passes a nil message and Webhook security renders its header with no message and no sandbox banner (it shows its own "managed in the parent project" notice instead), so read-only members get no role notice there | `settings.html.heex:682-689`, `:378-401`; `sandbox_settings_test.exs:274-279` | preserve |
| Collections renders its own header and banner inside `CollectionsComponent`, not the settings template | `collections_component.ex:278-294` | preserve |
| Tab labels are title case ("Webhook Security", "Data Storage", "History Exports") while section headings are sentence case ("Webhook security", "Data storage") | `settings.html.heex:46-64` vs `:381`, `:864`, `:1057` | decide |
| The Sync to GitHub notice is built with `&&`/`||` and has no comma: "version control configuration but you can initiate a sync." | `settings.html.heex:762` | preserve |
| The notice is red helper text only; it disables nothing, and each tab gates its own controls and handlers | `layout_components.ex:620-627` | preserve |
| The inherited banner's parent link is skipped when there is no parent loaded, leaving "inherited from the parent project and cannot..." with no name | `sandbox_settings_banner.ex:55` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `push-hash` handler in TabbedContainer | `TabbedContainer.ts:16-19` | no `push_event(..., "push-hash", ...)` anywhere in `lib/` |
| Disabled tab rendering with tooltip | `tabbed.ex:108-123` | no settings `:tab` passes `disabled` |
| Horizontal orientation | `tabbed.ex:25-58` | settings uses `orientation="vertical"` (`settings.html.heex:27`); only `run_live/show.ex:228` uses horizontal |
| `section_header` attrs `options` and `role` | `layout_components.ex:578-579` | declared, never read by the template |
| `section_header` with `action_button_text` but no `action_button_id` renders an empty wrapper | `layout_components.ex:596-613` | every caller that passes text also passes an id |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Eleven permission flags are computed on mount, each calling `Scope.fetch`, which reloads the project and the viewer's membership row | `settings.ex:118-188`; `scope.ex:112-117`, `:166-190` | no | preserve |

### 6.5 Things seen but not understood

- `sandbox_settings_test.exs:274-279` asserts the notice is absent on the sandbox Security and Webhook security tabs, but logs in as owner, who never sees a notice on any tab; the assertion would pass whether or not those tabs pass a message. Not a behaviour; recorded so nobody cites it as coverage.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the editable and inherited banner copy be changed to match what merge actually does (6.1), or should merge and MFA propagation change to match the copy? Product (Brandon's team) owns the intended behaviour.
- In the rebuild each tab gets its own route (`/settings/<tab>`); should the old `#<tab>` fragments redirect to those routes, given how many emails and pages link to them (url_params)?
- Should a tab that renders nothing useful for a role (none today) be hidden, or keep the "see everything, change some" model of S05?
- `Tabbed.container` is also used by the run page (`run_live/show.ex:228`). Does its tab behaviour (S01 to S04) need its own shared annotation, or does the run view catalogue it?

## Proposed flows

none. Inbound links to a tab (url_params) belong to the flows of the pages and emails that send them; this file only asserts the landing (S02).

## Proposed shared

none
