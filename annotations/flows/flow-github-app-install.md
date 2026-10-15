---
id: flow-github-app-install
type: flow
title: Install the GitHub app for a project
status: not-started
owner:

trigger:
  entry: project-settings-github-sync       # connect form only (action :new); github_sync_component.html.heex:2
  exit: project-settings-github-sync        # the original tab, after the admin clicks the installations refresh button
  surfaces:
    - project-settings-github-sync          # "Install or manage GitHub app installations" (github_sync_component.html.heex:40-47) or "Create/update GitHub installations or modify permissions." (:95-101)
    - external:github-app-install           # https://github.com/apps/<app_name>, opened with target="_blank"
    - controller:setup-vcs                  # GET /setup_vcs, VersionControlController.index (router.ex:194; version_control_controller.ex:4-16)
    - project-settings-github-sync          # refresh-installations (github_sync_component.ex:94-105)
  reachable_when:
    - the GitHub app is configured on this instance (settings.html.heex:779; version_control.ex:562-568)
    - the project has no GitHub connection (settings.html.heex:780, :797)
    - the viewer may write the GitHub connection, i.e. admin or owner (settings.html.heex:797; settings.ex:152-158; project_users.ex:29-37)
    - the viewer's own GitHub OAuth token is valid, so the connect form renders (settings.html.heex:800; settings.ex:915-917); otherwise flow-github-connect comes first
    - the GitHub App's "Setup URL" points at <instance>/setup_vcs with "Redirect on update" ticked, which is set in GitHub, not in Lightning (DEPLOYMENT.md:89-90)

inherits:
  - shared-authenticated-session            # /setup_vcs is piped through [:browser, :require_authenticated_user] (router.ex:189-190); login redirect and TOTP gate live there
  - shared-project-scope                    # entry and exit tab only

url_params:
  - name: installation_id
    set_by: external:github-app-install
    effect: none; the controller ignores all params (version_control_controller.ex:4)
  - name: setup_action
    set_by: external:github-app-install ("install" or "update")
    effect: none; ignored (version_control_controller.ex:4; version_control_controller_test.exs:14)

config_variants:
  default: { github_app: { app_id, app_name, client_id, client_secret, cert all set } }   # config/test.exs:168; read under this one
  github-disabled: { github_app: { cert: nil, app_id: nil, client_id: nil, client_secret: nil } }   # flow unreachable; project-settings-github-sync S16
  github-sync-limited: { usage_limiter: <refuses %Action{type: :github_sync}> }   # refresh button disabled (github_sync_component.html.heex:78-81; settings.html.heex:812)

inventory:
  routes:
    - get /setup_vcs  VersionControlController :index   # router.ex:194
  events:
    - ProjectLive.GithubSyncComponent#refresh-installations   # exit handoff; also listed by project-settings-github-sync
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers :write_github_connection   # gates the entry links (settings.ex:152-158)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :github_app, :app_name    # builds the install link (github_sync_component.html.heex:44, :98; bootstrap.ex:997; GITHUB_APP_NAME)
  not_reachable_here: []

related:
  - lib/lightning_web/controllers/version_control_controller.ex
  - lib/lightning_web/live/project_live/github_sync_component.ex
  - lib/lightning_web/live/project_live/github_sync_component.html.heex
  - lib/lightning/version_control/version_control.ex
  - lib/lightning/version_control/github_client.ex
  - DEPLOYMENT.md
  - test/lightning_web/controllers/version_control_controller_test.exs
  - test/lightning_web/live/project_live_test.exs
flows:
  - flow-github-connect                     # must precede this flow when the admin has no valid GitHub token
---

## 1. Purpose

A project admin setting up GitHub sync can only pick repositories that the OpenFn GitHub App has been
installed on. This flow sends them to GitHub to install the app or widen its repository access, then
brings them back to the connect form with the new installation or repository selectable. Without it,
an admin facing an empty or incomplete list has no route from Lightning to the fix.

## 2. What it does

1. On a project's GitHub sync connect form, an admin or owner with a linked GitHub account clicks a link to install or manage the OpenFn GitHub App, which opens GitHub in a new tab.
2. In GitHub they install the app on a user or organisation, or give it access to more repositories.
3. GitHub sends that tab back to OpenFn, which tries to close it.
4. Back on the original tab, the admin clicks the refresh button next to "GitHub Installation" to see the new installation and its repositories, and carries on connecting.

**Straightforwardness: 3 of 5.** It's a familiar "go to GitHub and come back" journey, but the way back relies on the user knowing to click a small refresh icon, and doing so throws away what they'd already picked.

### Most surprising behaviours

- **(3)** The original tab isn't told anything happened. The new installation only appears after the admin finds and clicks the refresh icon, and it isn't preselected when it does. (6.2)
- **(3)** Clicking refresh clears the whole form: installation, repository, branch and sync direction all have to be chosen again. (6.2)
- **(3)** The tab GitHub sends back may not close, since browsers often refuse, leaving a blank page with no message or link back. (6.1)
- **(3)** Once a project is connected, neither link is shown, so there's no route from OpenFn to give the app access to more repositories. (6.2)
- **(4)** The list only shows installations the admin's own GitHub account can see, not every installation of the app. (3)

## 3. Who can do what

Sources: `project_users.ex:29-37`, `:160-161`; flag `settings.ex:152-158`; template gates `settings.html.heex:779-800`; route `router.ex:189-194`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the install links on the connect form | no | no | yes | yes | no (cannot open the project) | no |
| Install or reconfigure the app in GitHub | outside Lightning; decided by the GitHub account's rights on the org or user | same | same | same | same | same |
| Load `/setup_vcs` | yes (any signed-in user) | yes | yes | yes | yes | yes |
| Refresh installations | not shown (no form) | not shown | yes | yes | n/a | n/a |

**Preconditions beyond role**
- The connect form, and with it both links and the refresh button, renders only when the admin's own GitHub OAuth token is valid (`settings.html.heex:800`).
- `/setup_vcs` needs a signed-in session; a signed-out request redirects to login (`user_auth.ex:288-299`; `version_control_controller_test.exs:22-31`). It is not tied to a project.
- The installations listed after refresh are those visible to the admin's GitHub account (`version_control.ex:257-268`), not every installation of the app.
- Under the github-sync-limited variant the refresh button and the installation select are disabled (`github_sync_component.html.heex:67-70`, `:78-81`), so the exit cannot complete without the limit lifting.

## 4. What it touches

**Hop 1, project-settings-github-sync (entry)**
- Reads: none beyond what the tab already loaded
- Writes: none
- The links are plain anchors with `target="_blank"` to `https://github.com/apps/<app_name>` (`github_sync_component.html.heex:40-47`, `:95-101`); no server event

**Hop 2, external:github-app-install**
- The admin installs the app on a user or organisation, or changes which repositories it can reach
- GitHub redirects the same tab to the app's Setup URL with `installation_id` and `setup_action` (`DEPLOYMENT.md:89-90`; `version_control_controller_test.exs:14`)

**Hop 3, controller:setup-vcs**
- Reads: session only (`require_authenticated_user`, `user_auth.ex:288-311`)
- Writes: none; params ignored (`version_control_controller.ex:4-16`)
- Responds 200 with a page whose `window.onload` calls `window.close()` (`version_control_controller.ex:5-15`; `version_control_controller_test.exs:7-18`)
- No PubSub broadcast; nothing tells the original tab that an install happened

**Hop 4, project-settings-github-sync (exit)**
- `refresh-installations` resets the form changeset, re-fetches installations and every installation's repositories, and empties the branch list (`github_sync_component.ex:94-105`, `:356-377`)
- Reads from GitHub: `GET /user/installations` with the admin's token, an installation token and `GET /installation/repositories` per installation (`version_control.ex:257-306`; `github_client.ex:30-32`)
- Writes: `users.github_oauth_token` when a refresh token is used to mint a new access token (`version_control.ex:470-484`)

**Immediate side effects**
- none in Lightning

**Deferred side effects**
- none

**External, non-transactional effects**
- The app installation and its repository grants are created or changed in GitHub; Lightning keeps no record of them and cannot undo them

**Depends on config**
- `:lightning, :github_app, :app_name` forms the link (`github_sync_component.html.heex:44`, `:98`)
- The GitHub App's Setup URL and "Redirect on update" setting, held in GitHub (`DEPLOYMENT.md:89-90`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Install the GitHub app for a project
  In order to connect a project to a repository the OpenFn GitHub App can't reach yet
  As a project admin
  I want to install or reconfigure the app in GitHub and pick it up on the connect form

  @S01 @pending
  Scenario: Admin with no installations installs the app and continues setup
    # Value: an admin whose GitHub account has never had the app can get to a usable connect form without support.
    Given I am an admin on project "Malawi HIV" with a connected GitHub account
    And the project has no GitHub connection
    And my GitHub account has no installations of the OpenFn GitHub App
    And I see "No GitHub installations found" on the "Sync to GitHub" tab
    When I click "Install or manage GitHub app installations"
    Then a new tab opens on the OpenFn GitHub App page
    When I install the app on account "amara" in that tab
    Then that tab is redirected to "/setup_vcs" and asked to close
    When I click the refresh button next to "GitHub Installation" in the original tab
    Then "GitHub Installation" lists "User: amara"
    And I do not see "No GitHub installations found"
    # github_sync_component.html.heex:32-49, :72-89; github_sync_component.ex:94-105, :356-377, :409-415, :466-468
    # version_control_controller.ex:4-16; router.ex:189-194; DEPLOYMENT.md:89-90
    # project_live_test.exs:4939-4958 (banner), :4848-4906 (refresh lists the new installation); version_control_controller_test.exs:7-18 (window.close)

  @S02 @pending
  Scenario: Admin grants the app access to another repository and selects it
    # Value: an admin can widen the app's access to the repository they need without abandoning the connect form for good.
    Given I am an admin on the connect form of project "Malawi HIV"
    And installation "User: amara" lists repository "amara/hiv-sync" but not "amara/tb-sync"
    When I click "Create/update GitHub installations or modify permissions."
    And in the new tab I add "amara/tb-sync" to the app's repository access
    Then that tab is redirected to "/setup_vcs" and asked to close
    When I click the refresh button next to "GitHub Installation" in the original tab
    And I select installation "User: amara"
    Then "Repository" lists "amara/tb-sync"
    # github_sync_component.html.heex:93-101, :104-117; github_sync_component.ex:94-105, :356-377, :417-428
    # version_control.ex:270-306; DEPLOYMENT.md:89-90 ("Redirect on update")
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `window.close()` only works on a tab the browser considers script-closable; a tab opened by a `target="_blank"` link that has since navigated through several GitHub pages usually is not, so the close is ignored. Read, not run | `version_control_controller.ex:5-15`; `github_sync_component.html.heex:40-47`, `:95-101` | a blank page left open on `/setup_vcs` with no message or link back | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The original tab is never told an install happened: no PubSub, no focus or visibility listener; the admin must find and click the refresh icon. The lead's scope ("the sync tab picks up the new installation") holds only after that click | `version_control_controller.ex:4-16`; `github_sync_component.ex:94-105` | decide |
| `/setup_vcs` ignores `installation_id` and `setup_action`, so the new installation is not preselected after refresh | `version_control_controller.ex:4` | decide |
| Refreshing installations resets the whole form changeset to an empty connection, clearing installation, repository, branch and sync direction choices | `github_sync_component.ex:95`, `:150-162` | decide |
| `/setup_vcs` is not project-scoped and sits outside any live_session; any signed-in user can load it | `router.ex:189-194` | preserve |
| A signed-out request to `/setup_vcs` stores it as the return path, so after login the user lands on a page that tries to close itself | `user_auth.ex:295-299`; `version_control_controller_test.exs:22-31` | decide |
| "Install or manage GitHub app installations" has `rel="noopener noreferrer"`; "Create/update GitHub installations or modify permissions." has neither | `github_sync_component.html.heex:41-42`, `:95-97` | fix |
| Neither entry link is shown on a connected project, so adding repositories to an installation after connecting has no link from Lightning | `github_sync_component.html.heex:2`, `:206-286` | decide |
| Title case in "Create/update GitHub installations or modify permissions." and "Install or manage GitHub app installations" is owned by project-settings-github-sync 6.2 | `github_sync_component.html.heex:46`, `:100` | decide |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Refresh re-fetches repositories for every installation, not just the new one, with the 30 s per-installation timeout and pagination behaviour catalogued in project-settings-github-sync 6.4 | `github_sync_component.ex:356-377`; `version_control.ex:270-306` | yes, a spinner and possibly missing repositories | preserve |

### 6.5 Things seen but not understood

- Whether GitHub redirects to the Setup URL after "Configure" on an existing installation (S02) depends on "Redirect on update" being ticked in the app's GitHub settings (`DEPLOYMENT.md:89-90`); nothing in Lightning checks or tests it.
- The lead's scope cites `router.ex:220` for `/setup_vcs`; the route is at `router.ex:194`.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the original tab pick up a new installation without a manual refresh (6.2), for example by `/setup_vcs` broadcasting to the user's `version_control_events` topic as flow-github-connect does?
- Should `/setup_vcs` show a "you can close this tab" message, or redirect back to the project, when `window.close()` is ignored (6.1)?
- Should the rebuild preselect the installation GitHub returns in `installation_id` (6.2)?

## Proposed flows

none

## Proposed shared

none
