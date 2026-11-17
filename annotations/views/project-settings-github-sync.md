---
id: project-settings-github-sync
type: view
title: Project settings › Sync
owner:

trigger:
  old_route: /projects/:project_id/settings#vcs
  new_route: /projects/:project_id/settings/github-sync
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "vcs", labelled "Sync" (settings.html.heex:55-58, :743; TabbedContainer, see shared-project-settings-tab-chrome)
    - the GitHub app is configured (cert, app_id, client_id and client_secret all set); otherwise only a "not configured" notice renders (settings.html.heex:762, :838-848; version_control.ex:905-915)
    - with no connection, the connect UI renders only for admins and owners; other roles see a "Role based permissions" box (settings.html.heex:780-799)
    - with no connection, the connect form renders only when the viewer's own GitHub OAuth token is valid; otherwise a "Connect your GitHub Account" prompt renders (settings.html.heex:803, :819-836; settings.ex:909-912)
    - the Export project and Sync with CLI cards render under every state of the tab (settings.html.heex:853-925)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA, membership remount
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52); the GitHub-specific limit banner is this view's own (see S27)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation; sandbox banner (S08 row "Sync"). The role notice for this tab is rendered inside the connect box (S15), not by the chrome
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#vcs (URL fragment)"
    set_by: >-
      every redirect in this view (github_sync_component.ex:63, :79, :84, :110, :123, :359, :369, :419, :426, :439, :449, :463, :470;
      settings.ex:695); collaborative editor GitHubSyncModal "Modify connection" link (assets/js/collaborative-editor/components/GitHubSyncModal.tsx:139)
    effect: opens this tab client-side; the server never sees it (settings.ex:233)

config_variants:
  default: { github_app: { app_id, app_name, client_id, client_secret, cert all set }, usage_limiter: Lightning.Extensions.UsageLimiter }   # config/test.exs:168; read under this one
  github-disabled: { github_app: { cert: nil, app_id: nil, client_id: nil, client_secret: nil } }   # version_control.ex:562-568; project_live_test.exs:4670-4695
  github-sync-limited: { usage_limiter: <adapter returning {:error, _, %{function: ..., attrs: ...}} for %Action{type: :github_sync}> }   # hooks.ex:204-212; version_control_usage_limiter.ex:11-21; read from tests with MockUsageLimiter
  sandbox: { project.parent_id: <parent project id> }   # data state, named so the family branch guard scenario can be tagged

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # catalogued by project-settings-setup
  events:
    - ProjectLive.GithubSyncComponent#validate               # github_sync_component.ex:45-54
    - ProjectLive.GithubSyncComponent#save                   # :56-65, :351-372
    - ProjectLive.GithubSyncComponent#delete-connection      # :67-86 (carries preserve_files)
    - ProjectLive.GithubSyncComponent#open-reconnect         # :88-90 (checks the workspace)
    - ProjectLive.GithubSyncComponent#validate-reconnect     # :94-101
    - ProjectLive.GithubSyncComponent#reconnect              # :103-112, :407-452
    - ProjectLive.GithubSyncComponent#initiate-sync          # :114-125, :454-473
    - ProjectLive.GithubSyncComponent#toggle-legacy-format   # :127-143
    - ProjectLive.GithubSyncComponent#toggle-advanced        # :145-147
    - ProjectLive.GithubSyncComponent#show-advanced          # :149-151
    - ProjectLive.GithubSyncComponent#refresh-status         # :153-161
    - ProjectLive.GithubSyncComponent#refresh-installations  # :163-174
    - ProjectLive.GithubSyncComponent#refresh-branches       # :176-184
    - ProjectLive.GithubSyncComponent#update %{poll: gen}    # :10-20 (status poll every 10 s for 5 min)
    - ProjectLive.Settings#handle_info OauthTokenAdded       # settings.ex:688-696 (handoff only; flow-github-connect)
    - ProjectLive.Settings#handle_info OauthTokenFailed      # settings.ex:698-708 (handoff only; flow-github-connect)
  js_hooks:
    - Tooltip (disabled-button tooltips via `.button tooltip`; connect link when a token exists, github_components.ex:22-23)
    - "Advanced settings" disclosure (server toggled, github_sync_component.html.heex:160-200)
    - SearchableSelect (filter box in the repository and branch dropdowns; assets/js/hooks/SearchableSelect.ts)
    - Copy (the CLI command copy buttons, settings.html.heex:902-918)
    - custom-select listbox show/hide (new_inputs.ex:528-583)
  policies:
    - Lightning.Policies.ProjectUsers :write_github_connection (admin action; project_users.ex:29-37, :160-161; flag settings.ex:152-158)
    - Lightning.Policies.ProjectUsers :initiate_github_sync (editor action; project_users.ex:39-49, :167-172; flag settings.ex:159-165)
  workers: []
  api_endpoints: []                        # /api/provision is called by the GitHub Action, not this view; see proposed flow-github-sync-actions
  emails: []
  config:
    - :lightning, :github_app (cert, app_id, app_name, client_id, client_secret; bootstrap.ex:117, :975-1015; GITHUB_APP_* env)
    - Lightning.Config.repo_connection_token_signer (project_repo_connection.ex:215-223)
    - :lightning, Lightning.Extensions, :usage_limiter (action :github_sync; usage_limiting.ex:20)
  not_reachable_here:
    - LightningWeb.VersionControlController#index (/setup_vcs, router.ex:242; version_control_controller.ex:1-17); GitHub App post-install redirect, see proposed flow-github-app-install
    - LightningWeb.OauthController#new (/oauth/:provider/callback, router.ex:106; oauth_controller.ex:7-29); see proposed flow-github-connect
    - VersionControl.delete_github_oauth_grant/1 (version_control.ex:833-862); profile-github only
    - VersionControl.get_repo_connection_for_token/1 (version_control.ex:457-459); API provisioning path
    - GithubComponents.connect_to_github_link `github_query_params` override (github_components.ex:8-13); only profile can pass it

related:
  - project-settings-setup                # owns the host route and mount
  - profile-github                        # the other home of the connect-account link (inventory row, no annotation yet)
  - lib/lightning/version_control/version_control.ex
  - lib/lightning/version_control/project_repo_connection.ex
  - lib/lightning/version_control/github_client.ex
  - lib/lightning/version_control/audit.ex
  - assets/js/collaborative-editor/components/GitHubSyncModal.tsx   # links here
flows:
  - flow-github-connect
  - flow-github-app-install
  - flow-github-sync-actions
---

## 1. Purpose

Project admins link a project to a branch of a GitHub repository so the
project's workflows are kept under version control, and editors push the current
project to that branch on demand. Teams use it to review changes, keep history,
and promote work between environments. Without it, a project has no audited
off-platform copy, and connecting the wrong branch or overwriting a project by
accident could destroy work in GitHub or in OpenFn.

## 2. What it does

- **Connect a project to a branch** (admins)
  - Admins connect their own GitHub account first, then pick an installation, a
    repository and a branch, refreshing the lists on demand and filtering the
    repository and branch lists by typing
  - New connections use the v2 (CLI workspace) format; a switch under Advanced
    settings keeps the legacy format, and v2 can name a workspace folder and a
    local alias
  - Admins choose the first sync direction: export this project to GitHub, or
    import from GitHub and overwrite this project
  - The branch's workspace is checked as they choose: alias clashes block the
    connection, and folders another project syncs to or a pull workflow of the
    other format get a warning
  - Admins confirm the files that will be written (and, for import, that the
    project will be destroyed) before connecting
- **See the connection**
  - Everyone on the project sees the saved connection, and a sync health panel
    with the repository setup, branch tracking and the last pull and deploy runs
  - Everyone on the project can also export the project as YAML and see the CLI
    commands for it, on the same tab
  - Admins are told when they have no installations or GitHub can't be reached;
    everyone is told when the instance has no GitHub app set up
- **Sync and maintain it**
  - Editors and above start a sync to the branch
  - Admins reconnect a broken or older-format connection when their own GitHub
    account can reach its installation, and can move it to another workspace
    folder
  - Admins remove the connection, even when GitHub cleanup fails; a v2 removal
    deletes the project's files from the branch unless they ask to preserve them
- **What stops a connect or sync**
  - Sandboxes can't reuse a branch already linked elsewhere in the same project
    family
  - Workflows whose names collide stop a connect or sync before anything is
    pushed, and the message names them
  - A GitHub sync usage limit blocks connecting and syncing, and says why

**Straightforwardness: 2 of 5.** Every action here writes files and secrets into
someone's GitHub repo, and what's left behind when things go wrong, or who is
allowed to fix it, takes real thought.

### Most surprising behaviours

- **(2)** If connecting fails partway, the project ends up with no connection,
  but the workflow files, config and an API secret it already wrote stay in the
  GitHub repo, with nothing on the page saying so. (6.1, 8)
- **(2)** Cleanup on removal uses the remover's own GitHub account and runs
  after the connection is removed, so without it the files and secret stay in
  GitHub, and the pull workflow file always stays. (S26, S46, 6.2)
- **(3)** Only sandboxes of the same project are stopped from sharing a branch.
  Two unrelated projects can connect to the same repo and branch, and each sync
  writes to that branch. (6.2, 8)
- **(3)** The branch and installation lists only show GitHub's first page, so in
  a busy repo the branch you want may simply not be there. (6.1)
- **(3)** Whether you can repair a broken connection depends on your personal
  GitHub access, not just your role, so an owner can be shown the problem with
  no way to fix it. Reconnecting in the import direction can also silently do
  nothing. (S20, 6.1)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-49`, `:134`, `:160-172`;
flags computed at `lib/lightning_web/live/project_live/settings.ex:152-165`;
template gates at `settings.html.heex:762-836` and
`github_sync_component.html.heex:260-266`, `:330-358`; handler checks at
`github_sync_component.ex:57`, `:68`, `:104`, `:115`.

| Action                                                                        | Viewer | Editor | Admin | Owner | Superuser (no row)           | Support (no row, access on) |
| ----------------------------------------------------------------------------- | ------ | ------ | ----- | ----- | ---------------------------- | --------------------------- |
| See the tab, the saved connection and its verification status                 | yes    | yes    | yes   | yes   | no (cannot open the project) | yes                         |
| See the "not configured for this Lightning instance" notice (github-disabled) | yes    | yes    | yes   | yes   | n/a                          | yes                         |
| See the connect-account prompt or the connect form (no connection yet)        | no     | no     | yes   | yes   | n/a                          | no                          |
| See the "Role based permissions" box (no connection yet)                      | yes    | yes    | no    | no    | n/a                          | yes                         |
| See the Export project and Sync with CLI cards                                | yes    | yes    | yes   | yes   | no (cannot open the project) | yes                         |
| Create a connection                                                           | no     | no     | yes   | yes   | n/a                          | no                          |
| Initiate a sync                                                               | no     | yes    | yes   | yes   | n/a                          | yes                         |
| Reconnect a broken connection                                                 | no     | no     | yes   | yes   | n/a                          | no                          |
| Remove the connection                                                         | no     | no     | yes   | yes   | n/a                          | no                          |

**Preconditions beyond role**

- Creating a connection needs the actor's own valid GitHub OAuth token
  (`settings.html.heex:803`; `version_control.ex:762-782`, `:784-812`); syncing
  does not.
- Listing branches, and checking a branch's workspace, needs the selected
  installation to be one the actor's GitHub account can see
  (`version_control.ex:244-254`, `:664-700`).
- Reconnecting needs the connection's installation to be in the actor's GitHub
  installation list (`github_sync_component.ex:475-480`;
  `github_sync_component.html.heex:260-266`).
- One connection per project (`project_repo_connection.ex:78-80`); a
  `(repo, branch)` pair is unique within a project family
  (`project_repo_connection.ex:81-87`, `:170-253`).
- A legacy import needs a config path; a v2 import needs none
  (`project_repo_connection.ex:237-253`).
- Workspace folders and config paths stay inside the repository, and a local
  alias is lowercase letters, numbers, "-" and "\_"
  (`project_repo_connection.ex:94-106`, `:135-139`).
- Connect is disabled while the workspace check runs and while an alias clash or
  a second copy of this project would result, for an export
  (`github_sync_component.ex:1452-1467`).
- Connect, reconnect and sync are refused while the `:github_sync` usage limit
  applies (`version_control.ex:55-58`, `:87-90`, `:474-477`).
- Removing GitHub files and the repo secret on disconnect needs the remover's
  own valid GitHub token; without it only the Lightning row is removed
  (`version_control.ex:1110-1140`).
- A member who hasn't met the project's MFA requirement never reaches this page
  (shared-project-scope); the policy also denies every action then
  (`decision.ex:59-66`).

## 4. What it touches

**Reads**: `projects` (via scope and `Projects.root_id/1`), `project_users`,
`project_repo_connections` (`version_control.ex:453-455`; tree conflict check
`project_repo_connection.ex:201-224`), `users.github_oauth_token`, `workflows`
and `workflow_snapshots` for the sync snapshot list and export pre-flight
(`version_control.ex:563-598`)

**Writes**:

- `project_repo_connections` insert on connect, with a signed `access_token`,
  `root_project_id` and, for v2, an optional `workspace_path`
  (`version_control.ex:45-63`; `project_repo_connection.ex:75-152`, `:255-264`)
- `project_repo_connections` delete on remove (`version_control.ex:436-451`)
- `audit_events` `repo_connection_created` / `repo_connection_removed`
  (`audit.ex:5-56`; `version_control.ex:51-54`, `:439-442`), and
  `repo_connection_updated` when a reconnect moves the workspace folder
  (`audit.ex:58-66`; `version_control.ex:104-112`)
- `users.github_oauth_token` when a refresh token is used to mint a new access
  token during any GitHub call (`version_control.ex:813-832`)
- Reconnect writes to the database only when it changes the workspace folder
  (`version_control.ex:83-115`); the local alias is never stored, it is passed
  to the first pull (`version_control.ex:547-561`)

**Immediate side effects**

- PubSub subscribe to `version_control_events:<user_id>` on connected mount
  (`settings.ex:104-106`; `events.ex:28-32`); handled in flow-github-connect
- Flash and `push_navigate` back to `#vcs` after every mutating action
  (component lines in url_params)

**Deferred side effects**

- A GitHub Actions `workflow_dispatch` of `openfn-pull.yml` on the default
  branch, which calls back into Lightning and commits to the connected branch;
  v2 connections use the `@v2` pull action, legacy ones `@v1`
  (`version_control.ex:473-561`); see flow-github-sync-actions
- The `openfn-<project_id>-deploy.yml` workflow pushes repo changes back into
  the project on commits to the branch (`version_control.ex:1050-1065`); see
  flow-github-sync-actions
- While the first sync is setting up, the panel re-checks GitHub every 10
  seconds for up to 5 minutes (`github_sync_component.ex:7-20`, `:242-259`)

**External, non-transactional effects**

- Connect and reconnect push `.github/workflows/openfn-pull.yml` to the default
  branch, write repo secret `OPENFN_<project_id>_API_KEY`, then push
  `openfn-<project_id>-deploy.yml` (and, for legacy with no config path, a
  config file) to the chosen branch; v2 commits no config file, and the secret
  goes in before the deploy workflow (`version_control.ex:917-1013`,
  `:1264-1285`). On connect these run inside the DB transaction
  (`version_control.ex:49-62`), so a GitHub failure late in the chain rolls back
  the row but leaves the earlier commits and secret in the repo (see 6.1).
- Sync dispatches a GitHub Actions workflow (`version_control.ex:473-513`).
- Remove deletes the deploy workflow file, the config file (legacy only) and the
  repo secret from GitHub after the row is deleted, best effort
  (`version_control.ex:1110-1140`); `openfn-pull.yml` is left in place. A v2
  removal without "Preserve project files" instead deletes this project's
  `.projects` copies, its checkout when the branch tracks it, and the deploy
  workflow in one commit "[skip actions] Disconnect OpenFn"
  (`version_control.ex:1142-1219`); other projects' files and `openfn.yaml`
  stay.
- Verification on every load of a connected tab reads the repo, the workflow
  files and the secret from GitHub, and for v2 also the workspace's tracking,
  `.projects` copies and the latest pull and deploy runs
  (`version_control.ex:119-212`, `:299-425`).

**Depends on config**

- `:lightning, :github_app` decides whether the tab offers anything
  (github-disabled variant) and supplies the app link
  (`github_sync_component.ex:611-613`; `github_sync_component.html.heex:48`,
  `:121`) and the OAuth client id (`github_components.ex:53-60`)
- Usage limiter `:github_sync` action (github-sync-limited variant)

**Product limits**

- One GitHub connection per project (`project_repo_connection.ex:78-80`)

## 5. Scenarios

```gherkin
Feature: Sync a project to GitHub
  In order to keep a project's workflows under version control
  As a project admin or editor
  I want to link the project to a GitHub branch and sync it on demand

  @S01
  Scenario: Admin connects a branch and exports the project to GitHub
    # Value: a team gets an off-platform, reviewable copy of the project without leaving OpenFn.
    Given I am an admin on project "Malawi HIV" with a connected GitHub account
    And my GitHub installation "User: amara" can see repository "amara/hiv-sync" with branch "main"
    When I select installation "User: amara", repository "amara/hiv-sync" and branch "main"
    And I leave "OpenFn --> GitHub: Export to GitHub (default, non-destructive)" selected
    And I tick the confirmation checkbox
    And I click "Connect Branch & Initiate First Sync"
    Then I see "Connection made successfully"
    And the connected panel shows "Repository:" "amara/hiv-sync" and "Branch:" "main"
    And the connection uses the v2 format
    And an audit event "repo_connection_created" is recorded for the project
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:56-65, :186-205, :351-372; version_control.ex:45-63, :1264-1285
    # github_sync_component.html.heex:2-246; project_live_test.exs:5313-5488

  @S02
  Scenario: Admin connects a branch to import an existing project from GitHub
    # Value: a team whose project already lives in a repo can make that repo the source without exporting over it first.
    Given I am an admin on project "Malawi HIV" with a connected GitHub account
    When I select an installation, repository "amara/hiv-sync" and branch "main"
    And I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    And I tick the confirmation checkbox
    And I click "Connect Branch & Initiate First Sync"
    Then I see "Connection made successfully"
    And no sync to GitHub is started
    # a v2 import needs no path to config: the workspace's openfn.yaml is used (project_repo_connection.ex:237-253)
    # github_sync_component.html.heex:157-199; version_control.ex:1279-1284; project_live_test.exs:5490-5608

  @S03
  Scenario: Importing in the legacy format needs a config path
    # Value: a legacy import can't be set up against a file that doesn't exist, which would leave the project overwritten by nothing.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    When I open "Advanced settings" and switch on "Use legacy formats (config.json)"
    And I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    And I leave "Path to config (required)" empty
    Then "Connect Branch & Initiate First Sync" stays disabled
    And with the legacy switch off, a v2 import shows no "Path to config" field
    # project_repo_connection.ex:237-253; github_sync_component.html.heex:186-199, :226-244
    # github_sync_ui_test.exs:148-205

  @S04
  Scenario Outline: The connect confirmation spells out what will be overwritten
    # Value: nobody overwrites workflow files in a repo, or their OpenFn project, without being told first.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    And I have selected repository "amara/hiv-sync" and branch "main"
    When I choose "<direction>"
    Then I see "I understand that" followed by the files ".github/workflows/openfn-pull.yml", ".github/workflows/openfn-<project_id>-deploy.yml"
    And I <see_or_not> "my current OpenFn project will be destroyed"
    And "Connect Branch & Initiate First Sync" stays disabled until I tick the box
    And no config file is listed, since v2 commits none (a legacy export with no path also lists "openfn-<project_id>-config.json")
    # github_sync_component.ex:1797-1864; github_sync_component.html.heex:209-244; project_repo_connection.ex:108-123
    # github_sync_ui_test.exs:207-225

    Examples:
      | direction                                                            | see_or_not |
      | OpenFn --> GitHub: Export to GitHub (default, non-destructive)       | do not see |
      | GitHub --> OpenFn: Import from GitHub (overwrite this project)       | see        |

  @S05
  Scenario: Connect stays disabled until installation, repository and branch are chosen
    # Value: an incomplete connection never reaches GitHub.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    When I have not chosen a branch
    Then "Connect Branch & Initiate First Sync" is disabled
    And if the form is submitted anyway I see "This field can't be blank"
    # project_repo_connection.ex:75-92; github_sync_component.html.heex:226-244; project_live_test.exs:5313-5488

  @S06
  Scenario: Repository and branch lists follow the choice above them
    # Value: an admin can only pick a repository and branch that the chosen installation actually exposes.
    Given I am an admin with access to installation "User: amara" holding repository "amara/hiv-sync"
    When I select installation "User: amara"
    Then "Repository" lists "amara/hiv-sync"
    When I select repository "amara/hiv-sync"
    Then "Branch" lists that repository's branches
    When I clear the installation
    Then no repository and no branch is selected
    # github_sync_component.ex:45-54, :176-184, :482-512, :567-586; github_sync_component.html.heex:63-156
    # project_live_test.exs:5052-5222

  @S07
  Scenario: Refreshing installations picks up a newly installed GitHub App
    # Value: an admin who installs the app in GitHub mid-setup can continue without reloading and losing the form.
    Given I am an admin on the connect form and my installations failed to load
    When the GitHub App is now installed on my account
    And I click the refresh button next to "GitHub Installation"
    Then "GitHub Installation" lists the new installation
    # github_sync_component.ex:163-174; github_sync_component.html.heex:65-98; project_live_test.exs:4896-4954

  @S08
  Scenario: Refreshing branches picks up a branch created after the page loaded
    # Value: an admin who just created a branch for OpenFn can select it without starting over.
    Given I am an admin with repository "amara/hiv-sync" selected, listing branch "main"
    When branch "openfn" is created in GitHub
    And I click the refresh button next to "Branch"
    Then "Branch" lists "main" and "openfn"
    And no branch is selected
    # github_sync_component.ex:176-184; github_sync_component.html.heex:126-154; project_live_test.exs:5052-5222

  @S09
  Scenario: Branches are never listed for an installation the user can't access
    # Value: an admin only sees branches of installations their own GitHub account can access.
    Given I am an admin whose GitHub account can access installation "1234" only
    When the form is submitted with installation "9999" and a repository in it
    Then "Branch" lists no branches
    And clicking the refresh button next to "Branch" still lists no branches
    # version_control.ex:664-700; project_live_test.exs:5224-5311

  @S10 @variant:sandbox
  Scenario: A sandbox can't claim a branch already linked in its project family
    # Value: two projects in one family never sync to the same branch and overwrite each other's files.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main"
    And I am an admin of its sandbox "dev"
    When I select "amara/hiv-sync" and branch "main" on the sandbox's connect form
    Then I see "this branch is already linked to another project in the same project family; use a different branch"
    And "Connect Branch & Initiate First Sync" is disabled
    When I select branch "dev"
    Then that message is gone
    # project_repo_connection.ex:13, :170-199; github_sync_component.ex:335-349
    # test/lightning_web/live/project_live/github_sync_component_test.exs:20-179

  @S11
  Scenario: Admin without installations is told to install the GitHub App
    # Value: an admin facing an empty list learns the fix instead of assuming GitHub is broken.
    Given I am an admin with a connected GitHub account and no GitHub App installations
    When I open the "Sync" tab
    Then I see "No GitHub installations found"
    And I see "You haven't installed the OpenFn GitHub App yet, or you may have uninstalled it."
    And "Install or manage GitHub app installations" opens the app's GitHub page in a new tab
    # github_sync_component.ex:624-626; github_sync_component.html.heex:35-53; project_live_test.exs:4987-5006

  @S12
  Scenario: A GitHub outage while loading installations is reported
    # Value: admins know the problem is on GitHub's side and that refreshing may fix it.
    Given I am an admin with a connected GitHub account
    And GitHub returns an error when listing my installations
    When I open the "Sync" tab
    Then I see "Unable to load GitHub installations"
    And I see "There was a problem connecting to GitHub. Refresh the page or contact support if the problem persists."
    And "GitHub Installation" is disabled
    # github_sync_component.ex:628-635; github_sync_component.html.heex:54-62, :73-76; project_live_test.exs:5031-5050

  @S13
  Scenario: Admin without a GitHub account is asked to connect one
    # Value: the admin learns the one prerequisite they are missing, and can fix it from here.
    Given I am an admin on project "Malawi HIV" with no GitHub account connected
    And the project has no GitHub connection
    When I open the "Sync" tab
    Then I see "Connect your OpenFn account to GitHub" and "You need to do this before you can set up sync."
    And I see a "Connect your GitHub Account" button that opens GitHub in a new tab
    And I see the docs banner pointing to docs.openfn.org
    And the flow "flow-github-connect" can start from this button
    # settings.html.heex:819-836; github_components.ex:11-28; project_live_test.exs:4745-4780

  @S14
  Scenario: Admin with an expired GitHub token is asked to reconnect it
    # Value: an admin whose access lapsed isn't shown a form that would fail on every call.
    Given I am an admin whose GitHub refresh token has expired
    And the project has no GitHub connection
    When I open the "Sync" tab
    Then I see "Reconnect your GitHub Account"
    And I do not see the connect form
    # settings.html.heex:803, :819-836; version_control.ex:762-782; github_components.ex:11-28
    # project_live_test.exs:5008-5029

  @S15
  Scenario Outline: Only admins see how to connect a project; others are told their role
    # Value: only people trusted with access decisions can link a project's data to an outside repository, and everyone else learns why.
    Given I am a <role> on project "Malawi HIV", which has no GitHub connection
    And I have a connected GitHub account
    When I open the "Sync" tab
    Then I see "Configure two-way sync to GitHub" with "Role based permissions: You cannot modify this project's version control configuration<ending>"
    And I do not see "Connect your OpenFn account to GitHub"
    And I do not see "Create/update GitHub installations or modify permissions."
    # settings.html.heex:780-798; github_sync_ui_test.exs:309-388; project_live_test.exs:4745-4780

    Examples:
      | role   | ending                       |
      | viewer | .                            |
      | editor |  but you can initiate a sync. |

  @S16 @variant:github-disabled
  Scenario: An instance without a GitHub app says so
    # Value: members know sync is unavailable on this instance rather than hidden from them, and who to ask.
    Given the instance has no GitHub app configured
    And I am a viewer on project "Malawi HIV"
    When I open the "Sync" tab
    Then I see "Connect to GitHub" and "Version Control is not configured for this Lightning instance. Contact the superuser for more information."
    And I see the docs banner pointing to docs.openfn.org
    # settings.html.heex:779, :838-848; version_control.ex:905-915; project_live_test.exs:4718-4743
    # github_sync_ui_test.exs:247-264

  @S17
  Scenario: Everyone on the project sees the saved connection
    # Value: any member can find which repository and branch hold the project's history.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main" through installation "1234" in the v2 format
    And I am a viewer on the project
    When I open the "Sync" tab
    Then I see "Repository:" linking to "https://www.github.com/amara/hiv-sync"
    And I see "Branch:" "main", "GitHub Installation ID:" "1234" and "Workspace:" (the folder, or "<root>")
    And once the first pull has filed the project I see "Local alias:" with its alias
    And I do not see "Path to config:" or the legacy note
    And I do not see the connect form
    # github_sync_component.html.heex:247-328; github_sync_component.ex:1238-1250
    # project_live_test.exs:5973-6007, :6587-6599; github_sync_ui_test.exs:390-411

  @S18
  Scenario: A healthy connection is confirmed
    # Value: members can trust a sync will work before they start one.
    Given project "Malawi HIV" is connected and the repo has its workflow files and API secret
    When I open the "Sync" tab
    Then I eventually see "Sync healthy" with "Repository configured (workflow files and secret)" ticked
    And I do not see "Reconnect"
    # version_control.ex:119-147; github_sync_component.ex:813-832, :897-988; project_live_test.exs:7039-7173

  @S19
  Scenario: A broken connection is flagged and admins can reconnect
    # Value: when someone deletes the workflow files or secret in GitHub, the team finds out here and can repair it in place.
    Given project "Malawi HIV" was connected more than two minutes ago but the deploy workflow file is missing on the branch
    And I am an admin whose GitHub account can access the connection's installation
    When I open the "Sync" tab
    Then I eventually see "Needs attention"
    And I see "Your GitHub repository is not properly connected with Lightning."
    And I see "GitHub Error: <deploy workflow file> does not exist in the main branch"
    And I see a "Reconnect" button
    And "Initiate Sync to Branch" is disabled
    # a connection under two minutes old shows "Setting up" instead, as GitHub can lag a pushed file (S39)
    # github_sync_component.ex:672-682, :1016-1049; github_sync_component.html.heex:330-349
    # project_live_test.exs:6601-6629

  @S20
  Scenario Outline: Reconnect is offered only to admins who can reach the installation
    # Value: a repair is attempted only by someone with both the authority and the GitHub access to complete it.
    Given project "Malawi HIV" has a broken GitHub connection
    And I am a <role> who <access> the connection's installation
    When I open the "Sync" tab
    Then I do not see "Reconnect"
    # github_sync_component.html.heex:251-266; github_sync_component.ex:475-480
    # project_live_test.exs:6631-6708 (viewer, editor), :6710-6747 (admin, owner without access)

    Examples:
      | role   | access              |
      | viewer | can access          |
      | editor | can access          |
      | admin  | cannot access       |
      | owner  | cannot access       |

  @S21
  Scenario: Admin reconnects a broken connection
    # Value: a damaged repo setup is restored without removing and recreating the connection.
    Given project "Malawi HIV" has a broken GitHub connection
    And I am an admin whose GitHub account can access its installation
    When I click "Reconnect"
    And in "Reconnect to GitHub" I keep "OpenFn --> GitHub" selected, tick the confirmation and click "Reconnect"
    Then I see "Connected to GitHub"
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:103-112, :407-452, :1570-1638; version_control.ex:83-101; project_live_test.exs:6749-6872

  @S22
  Scenario: Editor starts a sync
    # Value: the people who change workflows can push them to GitHub without waiting on an admin.
    Given project "Malawi HIV" is connected and verified
    And I am an editor with no GitHub account connected
    When I click "Initiate Sync to Branch"
    Then I see "GitHub sync initiated"
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:114-125, :454-473; version_control.ex:473-513; project_live_test.exs:7514-7636

  @S23
  Scenario: Viewers can't start a sync and are told who can
    # Value: read-only members can't push changes out, and know whom to ask.
    Given project "Malawi HIV" is connected
    And I am a viewer on the project
    When I open the "Sync" tab
    Then "Initiate Sync to Branch" is disabled with the tooltip "Contact an editor or admin to sync."
    And I do not see "Remove integration"
    # github_sync_component.html.heex:330-358; github_sync_ui_test.exs:413-432; project_live_test.exs:7423-7464

  @S24
  Scenario Outline: The server checks the role for each action, not just the control
    # Value: the role is checked on the server for each action, so read-only members cannot change the project's GitHub link.
    Given project "Malawi HIV" is connected
    And I am a <role> on the project
    When a "<event>" event reaches the GitHub sync component
    Then I see "You are not authorized to perform this action"
    And the connection is unchanged
    # github_sync_component.ex:56-125; project_live_test.exs:6631-6708 (reconnect), :7175-7236 (delete-connection), :7423-7464 (initiate-sync)

    Examples:
      | role   | event             |
      | viewer | initiate-sync     |
      | viewer | reconnect         |
      | editor | reconnect         |
      | viewer | delete-connection |
      | editor | delete-connection |
      | editor | save              |

  @S25
  Scenario: Admin removes the integration after confirming
    # Value: a project can be unlinked from a repository it should no longer write to, with a record of who did it.
    Given project "Malawi HIV" is connected to "amara/hiv-sync"
    And I am an admin on the project
    When I click "Remove integration"
    Then I see "Remove Integration?" and "You are about to disconnect this project from GitHub, disabling two-way sync. You can reconnect at any time."
    When I click "Disconnect"
    Then I see "Connection removed successfully"
    And the project has no GitHub connection
    And an audit event "repo_connection_removed" is recorded for the project
    # github_sync_component.html.heex:350-366; github_sync_component.ex:67-86, :1499-1561; version_control.ex:436-451
    # project_live_test.exs:7339-7421

  @S26
  Scenario: Removal succeeds even when GitHub cleanup can't
    # Value: an admin can always cut a project's link to a repo, even if they never connected GitHub themselves or GitHub refuses the cleanup.
    Given project "Malawi HIV" is connected
    And I am an admin with no GitHub account connected
    When I remove the integration
    Then I see "Connection removed successfully"
    And the project has no GitHub connection
    # version_control.ex:436-451, :1110-1140; project_live_test.exs:7238-7296, :7339-7421

  @S27 @variant:github-sync-limited
  Scenario: A GitHub sync usage limit blocks connecting and syncing and says why
    # Value: a project over its limit learns why sync is unavailable instead of hitting a failure after filling in the form.
    Given the usage limiter refuses GitHub sync for project "Malawi HIV" with a banner message
    And I am an admin on the project
    When I open the "Sync" tab
    Then I see the limiter's banner message
    And "Connect Branch & Initiate First Sync" is disabled
    # hooks.ex:204-212; settings.html.heex:757-766, :776, :815; github_sync_component.html.heex:231-243
    # project_live_test.exs:5903-5971, :7773-7808 (banner for viewer, editor, admin, owner)

  @S28 @variant:github-sync-limited
  Scenario: The limit is checked again when the action runs
    # Value: a limit that starts applying after the page loaded still stops the connection, sync or reconnect.
    Given I am an admin on the connect form of project "Malawi HIV"
    And the usage limiter starts refusing GitHub sync with "Plan limit reached"
    When I submit the connect form
    Then I see "Plan limit reached"
    And the project has no GitHub connection
    # version_control.ex:55-58, :87-90, :474-477; github_sync_component.ex:351-372, :407-452
    # project_live_test.exs:5610-5707 (connect), :6947-7037 (reconnect)

  @S29
  Scenario: Colliding names stop a sync before anything reaches GitHub
    # Value: a sync never silently drops one of two workflows whose names map to the same key, and the user knows which to rename.
    Given project "Malawi HIV" is connected
    And it has workflows "My Flow" and "My-Flow"
    And I am an admin on the project
    When I click "Initiate Sync to Branch"
    Then I see an error naming "My Flow" and "My-Flow"
    And no workflow is dispatched in GitHub
    # version_control.ex:478-486, :1269; export_utils/duplicate_key_error.ex:22-26; github_sync_component.ex:395-400, :432-440
    # project_live_test.exs:7466-7512 (sync), :6874-6945 (reconnect, nothing written to the repo)

  @S30
  Scenario: GitHub's own error message is shown when a connect fails
    # Value: an admin can act on what GitHub said (permissions, protected branch) instead of a generic failure.
    Given I am an admin submitting the connect form on project "Malawi HIV"
    And GitHub refuses a file write with message "Resource not accessible by integration"
    When the connect runs
    Then I see "GitHub Error: Resource not accessible by integration"
    And the project has no GitHub connection
    # github_sync_component.ex:365-405; project_live_test.exs:5709-5804, :5806-5901
  @S31
  Scenario: A new connection defaults to the v2 format, with a legacy switch under Advanced settings
    # Value: new connections use the CLI workspace format unless the team already has a legacy repo and chooses to keep it.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    Then "Advanced settings" is collapsed and "Use legacy formats (config.json)" inside it is off
    When I switch on "Use legacy formats (config.json)"
    Then "Path to config" appears and "Workspace folder" disappears
    When I change a dropdown
    Then the legacy choice is kept
    And the switch stays visible when I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    # github_sync_component.ex:127-143, :186-205, :1646-1689; github_sync_component.html.heex:157-200
    # github_sync_ui_test.exs:101-205

  @S32
  Scenario: A v2 connection can name a workspace folder and a local alias
    # Value: several projects can share one repository, each in its own folder and under its own name.
    Given I am an admin filling in the connect form on project "Malawi HIV" in the v2 format
    When I open "Advanced settings"
    Then I see "Workspace folder" (placeholder "repository root") for the folder holding openfn.yaml
    And I see "Local alias" (placeholder "main") for the name this project is saved under from the next pull
    When I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    Then "Local alias" is hidden
    And a folder or alias with characters outside letters, numbers, ".", "_", "-" (and "/" in a folder) is refused
    # github_sync_component.ex:1693-1723; project_repo_connection.ex:75-140
    # github_sync_ui_test.exs:101-205; project_live_test.exs:6009-6089

  @S33
  Scenario: Choosing a branch checks the workspace on GitHub and says what the project will be saved as
    # Value: before connecting, an admin sees which name the first pull will use in the workspace.
    Given I am an admin filling in the connect form on project "Malawi HIV" in the v2 format
    When I select installation, repository and branch
    Then I briefly see "Checking the workspace on GitHub..." and "Connect Branch & Initiate First Sync" is disabled
    And then I see "This project will be saved in the workspace as main"
    When I choose the import direction and the workspace holds a project
    Then I see the alias it holds and that it "will be imported"
    # github_sync_component.ex:45-54, :263-295, :1260-1313, :1422-1426; version_control.ex:244-254
    # project_live_test.exs:6009-6089

  @S34
  Scenario: An alias another project already uses blocks the connection
    # Value: a first pull that would fail because the workspace can't tell two projects apart is stopped before anything is written.
    Given the branch's workspace holds "main@<host>.yaml" belonging to another project
    And I am an admin on the connect form for an export
    Then I see "Another project in this folder is already saved as "main"" listing that copy
    And "Connect Branch & Initiate First Sync" is disabled with the tooltip "Set a different local alias under Advanced settings first"
    When I set "Local alias" to "demo"
    Then the warning goes and the button is enabled
    # github_sync_component.ex:736-744, :1315-1428, :1434-1463; github_sync_component.html.heex:226-244
    # project_live_test.exs:6009-6089

  @S35
  Scenario: Saving this project a second time under another alias blocks the connection
    # Value: one project is never filed twice in a workspace, which the CLI can't resolve.
    Given the branch's workspace already holds this project's own copy under "main" on this host
    And I am an admin on the connect form for an export with "Local alias" "demo"
    Then I see "This project is already saved in this workspace as "main"" and the copy's path
    And "Connect Branch & Initiate First Sync" is disabled
    When I clear "Local alias"
    Then the warning goes and the button is enabled
    # github_sync_component.ex:746-758, :1384-1399, :1457-1461; project_live_test.exs:6091-6155

  @S36
  Scenario: A copy whose project can't be read is a warning, not a block
    # Value: a very large project copy that GitHub can't return in full doesn't stop its own project from connecting.
    Given the workspace holds "main@<host>.yaml" on this host whose project id can't be read
    And I am an admin on the connect form for an export
    Then I see "Couldn't check what's saved as "main"" listing the copy
    And I do not see an alias clash
    And "Connect Branch & Initiate First Sync" is enabled
    And I am pointed to "Advanced settings" to set a local alias
    # version_control.ex:299-355; github_sync_component.ex:736-763, :1400-1413
    # project_live_test.exs:6157-6207; version_control_test.exs:764-980

  @S37
  Scenario: Connecting an export to a folder another project syncs to asks for confirmation
    # Value: nobody replaces another project's files in a shared folder without being told, with pointers to keep them apart.
    Given the branch's checkout belongs to project "Other"
    And I am an admin on the connect form for an export
    Then I see ""Other" already syncs to this folder" with the other project's id and the advice to pick a different branch or workspace folder
    And the confirmation reads ""Other"'s files in this folder will be replaced"
    When I choose the import direction
    Then neither the warning nor that sentence is shown
    # github_sync_component.ex:1222-1236, :1326-1383, :1817-1819; project_live_test.exs:6209-6286

  @S38
  Scenario: Connecting warns when it replaces the repository's pull workflow with the other format
    # Value: one project's choice of format doesn't quietly stop syncs for the other projects in the repository.
    Given the repository's "openfn-pull.yml" is set up for the legacy format
    And I am an admin on the connect form in the v2 format (or the reverse)
    When I tick the confirmation
    Then under ".github/workflows/openfn-pull.yml" I see "This file is set up for the legacy format. Replacing it stops syncs from OpenFn for every project connected to this repository with that format."
    # version_control.ex:244-280; github_sync_component.ex:1207-1218, :1830-1838
    # project_live_test.exs:6288-6343

  @S39
  Scenario: A v2 connection shows its sync health
    # Value: members see in one place whether the repository, the branch and the last runs are in order.
    Given project "Malawi HIV" is connected in the v2 format
    When I open the "Sync" tab
    Then I see a "Sync health" panel titled "Sync healthy" or "Needs attention" with rows "Repository configured (workflow files and secret)", "Branch tracks this project", "Last sync: OpenFn --> GitHub" and "Last deploy: GitHub --> OpenFn"
    And each run row shows its time, a "View run" link and a pill, or "No runs yet"
    And a failed last run makes the title "Needs attention"
    And a legacy connection shows only the repository row
    # version_control.ex:173-212; github_sync_component.ex:655-670, :813-832, :897-988, :1184-1203
    # project_live_test.exs:6345-6375; github_sync_ui_test.exs:434-442

  @S40
  Scenario: A first sync that is still running is "Setting up"; a failed one shows its run
    # Value: a team waiting on the first sync isn't told something is wrong, and one that failed is pointed at its log.
    Given project "Malawi HIV" was just connected and nothing has been committed to the branch yet
    When the first pull run is in progress
    Then I see "Setting up" and "First sync running..." with a "View run" link
    And the status refreshes by itself every ten seconds for up to five minutes
    When that run ends in failure
    Then I see "The first sync failure" and "Nothing has been committed for this project yet." with "See the run log on GitHub"
    # version_control.ex:357-384; github_sync_component.ex:242-259, :768-776, :1058-1090
    # project_live_test.exs:6411-6437, :6439-6463

  @S41
  Scenario: A branch that tracks another project is flagged
    # Value: two projects syncing to one branch are told, with the other project's name, before they overwrite each other.
    Given the branch's checkout belongs to project "Other"
    When I open the "Sync" tab of "Malawi HIV"
    Then "Branch tracks this project" shows "This branch tracks another project:" with "Other" and its id
    And I am told to reconnect with a different workspace folder or use a separate branch
    # version_control.ex:357-384; github_sync_component.ex:696-697, :1091-1106
    # project_live_test.exs:6465-6474

  @S42
  Scenario: Alias clashes and double copies in the workspace are flagged on a connected project
    # Value: the team learns why syncs would fail, and which files to remove.
    Given project "Malawi HIV" is connected in the v2 format
    When another project's copy uses this project's alias
    Then "Branch tracks this project" shows "Another project in this workspace also uses the alias" listing the copy
    When this project is instead saved twice on this host under two aliases
    Then I see "This project is saved in the workspace more than once" listing both
    And copies from other hosts are not counted
    # github_sync_component.ex:688-717, :736-758, :1107-1140; project_live_test.exs:6476-6531

  @S43
  Scenario: A repository with the old workflow files offers admins to reconnect
    # Value: connections made before the v2 workflow files existed keep syncing, and the team is told how to get the full sync status.
    Given project "Malawi HIV" is connected in the v2 format and the repository's workflow files are the legacy ones
    When I open the "Sync" tab
    Then I see "This repository has the old OpenFn GitHub workflows" and "Reconnect to update the workflow files and get full sync status."
    And I can start a sync, which dispatches the legacy workflow's inputs
    And a viewer or an editor sees the notice without a "Reconnect" button
    And with current workflow files I see no notice
    # version_control.ex:214-228, :515-543; github_sync_component.ex:990-1010
    # project_live_test.exs:6377-6409

  @S44
  Scenario: Reconnecting checks the workspace like connecting, and can move the workspace folder
    # Value: a repair can't create the clashes that the connect form prevents, and a project can be moved to another folder.
    Given project "Malawi HIV" is connected in the v2 format and I am an admin who can reach its installation
    When I click "Reconnect"
    Then the workspace is checked straight away and "This project will be saved in the workspace as main" is shown
    And "Reconnect" stays disabled until I tick the confirmation
    When I enter a "Local alias" that would file this project twice
    Then I see the stray-copy warning and "Reconnect" is disabled
    When I change "Workspace folder" and reconnect
    Then the new folder is saved, files are pushed to it, and an audit event "repo_connection_updated" records the old and new folder
    # github_sync_component.ex:88-101, :1570-1638; version_control.ex:83-115; audit.ex:58-66
    # project_live_test.exs:6533-6585; version_control_test.exs:627-762

  @S45
  Scenario: Only runs from after the connection are shown
    # Value: the status describes this connection, not a previous one on the same repository and branch.
    Given project "Malawi HIV" was connected on 14 October
    And an earlier connection to the same repository ran a deploy on 1 October
    When I open the "Sync" tab
    Then "Last deploy: GitHub --> OpenFn" shows "No runs yet"
    # version_control.ex:173-204

  @S46
  Scenario Outline: Removing a v2 connection deletes this project's files from the branch unless they are preserved
    # Value: disconnecting cleans up after itself by default, and a team that wants a working copy left in the repo can keep it.
    Given project "Malawi HIV" is connected in the v2 format and the branch tracks it
    And I am an admin with a connected GitHub account
    When I click "Remove integration"
    Then "Preserve project files" is unticked, with "Select this option to leave a working copy of the project in your GitHub repo, including all workflows and state files created by the sync."
    When I <choice> and click "Disconnect"
    Then I see "Connection removed successfully"
    And the project's files are <result>
    # github_sync_component.ex:67-86, :1526-1539; version_control.ex:436-451, :1110-1194
    # project_live_test.exs:7298-7337; version_control_test.exs:446-502

    Examples:
      | choice                              | result                                                                                                                                                    |
      | leave "Preserve project files" off  | deleted from the branch in one commit "[skip actions] Disconnect OpenFn": its copies under ".projects", the checkout when the branch tracks it, the deploy workflow |
      | tick "Preserve project files"       | left in the repository; the deploy workflow and API secret are still removed                                                                              |

  @S47
  Scenario: Removing a connection leaves files other projects in the workspace use
    # Value: disconnecting one project never breaks the others that share the repository.
    Given the workspace holds "openfn.yaml", this project's copy and another project's copy and checkout
    When an admin removes the integration with "Preserve project files" off
    Then only this project's copies are deleted
    And "openfn.yaml" and the other project's files stay
    And the checkout stays when the branch tracks another project
    # version_control.ex:1142-1219; version_control_test.exs:416-445, :503-599

  @S48
  Scenario: Removing a legacy connection says which files stay in the repository
    # Value: the team knows what to clean up by hand after disconnecting.
    Given project "Malawi HIV" is connected in the legacy format to "amara/hiv-sync" branch "main"
    And I am an admin
    When I click "Remove integration"
    Then I see "This removes the deploy workflow and API secret from amara/hiv-sync. Any other files the sync committed to main, like the project and workflow files, stay in the repo. Delete them yourself if you no longer need them."
    And there is no "Preserve project files" option
    # github_sync_component.ex:1540-1544; version_control.ex:1117-1138

  @S49
  Scenario: The Sync tab offers a project export for every member
    # Value: anyone on the project can take a copy of it as code from the one tab about syncing and portability.
    Given I am a viewer on project "Malawi HIV"
    When I open the "Sync" tab
    Then I see "Export your project" with "Save your project as a YAML file to be edited locally, backed up, or deployed elsewhere."
    And "Export project" links to "/download/yaml?id=<project_id>" in a new tab
    And clicking it starts the flow "flow-export-project-yaml"
    # settings.html.heex:853-867; the Setup tab no longer carries this card (project-settings-setup S11)

  @S50
  Scenario: The Sync tab shows how to work on the project with the CLI
    # Value: people who prefer the command line find the exact commands for their project here.
    Given I am a member of project "Malawi HIV"
    When I open the "Sync" tab
    Then I see "Sync with CLI" with a note that a Personal Access Token is needed, linking to the authorization docs
    And I see the commands "openfn project pull <project_id>", "openfn project deploy" and "openfn <workflow-name>", each with a copy button
    And I see a "See more CLI commands" link
    # settings.html.heex:868-925; github_sync_ui_test.exs:282-307

  @S51
  Scenario: Each state of the GitHub panel links to the sync docs
    # Value: people stuck at any step of the setup can find the documentation.
    Given I open the "Sync" tab
    Then the panel shows a blue banner "Learn more about synchronizing your project with GitHub at docs.openfn.org" in the connect form, the connect-account prompt, the not-configured notice and the connected panel
    # github_components.ex:30-51; settings.html.heex:828, :847; github_sync_component.html.heex:15, :250
    # github_sync_ui_test.exs:227-280

  @S52
  Scenario: Repository and branch dropdowns can be filtered
    # Value: an account with many repositories or branches can find the right one by typing.
    Given I am an admin on the connect form with several repositories and branches
    When I open "Repository" or "Branch"
    Then I see a "Filter…" box that narrows the options as I type
    And "GitHub Installation" has no filter box
    # new_inputs.ex:401-403, :531-583; assets/js/hooks/SearchableSelect.ts; github_sync_ui_test.exs:84-99

  @S53
  Scenario: The sync status can be refreshed by hand
    # Value: someone waiting on a run does not have to reload the page to see it.
    Given project "Malawi HIV" is connected in the v2 format
    When I click the refresh button on the sync health panel
    Then the status is checked again, the button is disabled and spins while it loads
    And the five-minute window for automatic refreshes restarts
    # github_sync_component.ex:153-161, :229-259, :897-931
```

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                                                                                                                                                                                                                                            | Where                                                                                  | What a user sees                                                                                                                   | Disposition |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| Connect writes to GitHub inside the DB transaction, after the insert and audit; if a later step fails (secret write, first sync dispatch, usage limit already passed), the row rolls back but pull.yml, the secret and possibly the deploy workflow (and a legacy config file) stay in the repo | `version_control.ex:49-62`, `:1264-1285`                                               | an error flash, no connection, and a repo that now has OpenFn workflow files and a secret pointing at a token that was never saved | fix         |
| A lost race on the family branch index returns `{:error, :branch_used_in_project_tree}`, an atom, which `error_message/1` doesn't match                                                                                                                                                         | `version_control.ex:65-77`; `github_sync_component.ex:374-405`                         | "Oops! An error occurred while connecting to GitHub. Please try again later" instead of the branch-in-use message                  | fix         |
| Reconnect with "Import from GitHub" on a legacy connection with no config path fails `validate_sync_direction` on `config_path`, but the reconnect modal has no config path field to show the error on (v2 connections need no path)                                                            | `project_repo_connection.ex:125-133`, `:237-253`; `github_sync_component.ex:1589-1620` | clicking "Reconnect" does nothing visible                                                                                          | fix         |
| `delete-connection` pattern-matches `{:ok, _}`; a failed or stale delete (removed in another tab) crashes the component                                                                                                                                                                         | `github_sync_component.ex:69-74`; `version_control.ex:436-451`                         | the LiveView crashes and reloads                                                                                                   | fix         |
| The branch refresh icon spins on `@installations.loading`, not `@branches.loading`                                                                                                                                                                                                              | `github_sync_component.html.heex:148-151`                                              | no spinner while branches reload; a spinner on the branch button while installations reload                                        | fix         |
| `on_mount :limit_github_sync` matches only `{:error, %{function: f}}`; a limiter returning `{:error, _, %{text: ...}}` (the shape the connect path handles) raises a CaseClauseError                                                                                                            | `hooks.ex:204-212`; `github_sync_component.ex:218-219`                                 | the whole settings page fails to mount for that project                                                                            | decide      |
| Branch list calls `/repos/:repo/branches` with no pagination                                                                                                                                                                                                                                    | `github_client.ex:52-54`; `version_control.ex:664-676`                                 | repositories with more than GitHub's default page of branches (30) list only the first page; the wanted branch may be missing      | fix         |
| Installation list calls `/user/installations` with no pagination, and branch authorization reuses that list                                                                                                                                                                                     | `github_client.ex:38-40`; `version_control.ex:600-612`, `:677-700`                     | an account with more than one page of installations can't see or use the later ones                                                | fix         |

### 6.2 Quirks and implementation details

| What                                                                                                                                                                                    | Where                                                                                           | Disposition |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ----------- |
| Only sandboxes of the same project are stopped from sharing a branch. Two unrelated projects can connect to the same repo and branch, and each sync writes to that branch.              | `project_repo_connection.ex:170-199`; `github_sync_component_test.exs:181-247`                  | decide      |
| Disconnect removes the deploy workflow, the legacy config file and the secret but leaves `openfn-pull.yml` on the default branch, which other projects in the repository share          | `version_control.ex:1110-1140`                                                                  | preserve    |
| Disconnect cleanup runs after the row is removed, with the remover's own GitHub token; the removal flash does not report what the cleanup did                                           | `version_control.ex:436-451`, `:1110-1140`                                                      | decide      |
| The manual sync commit message embeds the user's email ("user <email> initiated a sync from Lightning"); the first sync on connect passes the bare email as the commit message          | `github_sync_component.ex:456`; `version_control.ex:1280`                                       | decide      |
| The disabled connect button's tooltip reads `:text` from the limiter's banner map, which the function-component shape doesn't carry, so the tooltip is empty                            | `settings.html.heex:770-775`, `:805-818`; `project_live_test.exs:5903-5971`                     | fix         |
| Only "GitHub Installation" and the connect button honour the limit banner; repository, branch, refresh-branches and "Remove integration" stay active                                    | `github_sync_component.html.heex:73-76`, `:110-114`, `:135-136`, `:144`, `:350-358`             | decide      |
| With `github_enabled?` false, an existing connection is hidden behind the "not configured" notice                                                                                       | `settings.html.heex:762-848`                                                                    | preserve    |
| The connected view loads the viewer's own installation list on every mount, for every role, just to decide whether to show reconnect                                                    | `github_sync_component.ex:217-220`, `:475-480`                                                  | decide      |
| "Path to config" placeholder suggests `./openfn-<project_id>-config.json`, the default path for a legacy export, on a field that is "(required)" for import and "(optional)" for export | `github_sync_component.html.heex:186-199`; `project_repo_connection.ex:266-272`                 | decide      |
| Collision errors come from export and end "Rename one of them and export again.", and start lowercase in the flash                                                                      | `export_utils/duplicate_key_error.ex:22-26`; `github_sync_component.ex:395-400`                 | decide      |
| Labels in title case and arrow glyphs: "Connect Branch & Initiate First Sync", "Initiate Sync to Branch", "OpenFn --> GitHub"                                                           | `github_sync_component.html.heex:242`, `:348`, `:357`; `github_sync_component.ex:1756`, `:1777` | decide      |
| "Syncing.." uses two dots                                                                                                                                                               | `github_sync_component.html.heex:345`                                                           | preserve    |
| Every action ends in a full `push_navigate` to `#vcs` rather than a patch                                                                                                               | `github_sync_component.ex:63-470`; `settings.ex:695`                                            | preserve    |
| The repository link uses `https://www.github.com/`                                                                                                                                      | `github_sync_component.html.heex:272`                                                           | preserve    |
| The accept checkbox appears only once a branch is chosen                                                                                                                                | `github_sync_component.html.heex:209-224`                                                       | preserve    |
| `reconfigure_changeset` requires `accept`; only `configure_changeset` also validates that it is true                                                                                    | `project_repo_connection.ex:108-133`                                                            | preserve    |
| The verify banner prints raw GitHub error text inside `<code>`                                                                                                                          | `github_sync_component.ex:1036-1043`                                                            | decide      |
| A legacy connection shows "This connection uses the legacy sync format (config.json). Reconnect to update to v2 sync formats" in place of a "Sync version" row                          | `github_sync_component.html.heex:316-328`                                                       | preserve    |
| `user_has_valid_oauth_token` treats a token with a still-valid refresh token as valid even if the access token has expired; the refresh happens on the first GitHub call                | `settings.ex:909-912`; `version_control.ex:762-812`                                             | preserve    |

### 6.3 Unreachable or dead code

| What                                                           | Where                                                                       | Why unreachable                                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Your GitHub authentication has expired or is invalid." banner | `github_sync_component.html.heex:16-34`; `github_sync_component.ex:615-622` | the form renders only when the token is valid (`settings.html.heex:803`), and `:invalid_oauth_token` is raised only for a missing or expired refresh token (`version_control.ex:784-812`); reachable only if the token expires between mount and the async fetch |

### 6.4 Performance and operational limits

| What                                                                                                                                                                                   | Where                                                            | User-visible?                                    | Disposition |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------ | ----------- |
| Repos for every installation are fetched in parallel with a 30 s per-installation timeout; a timed-out installation is silently dropped from the repo map                              | `github_sync_component.ex:514-539`                               | yes, an installation with no repositories listed | decide      |
| Installation repos are paged 100 at a time, later pages fetched 5 at a time with no timeout; a failed page is logged and skipped                                                       | `version_control.ex:613-662`                                     | yes, missing repositories                        | preserve    |
| Every mount of a connected tab makes several GitHub calls to verify (repo, workflow files, secret) plus, for v2, the workspace, the runs and the installation lookup, for every viewer | `version_control.ex:119-212`; `github_sync_component.ex:207-227` | no, beyond the "Verifying connection..." spinner | decide      |
| Each sync runs a full YAML export as a pre-flight and throws it away                                                                                                                   | `version_control.ex:478-486`                                     | no                                               | preserve    |
| Connect holds a DB transaction open across a chain of GitHub HTTP calls                                                                                                                | `version_control.ex:49-62`                                       | no                                               | decide      |

### 6.5 Things seen but not understood

- `verify_connection/1` (`github_sync_component.ex:604-609`) returns the raw
  `{:error, ...}` from `verify_github_connection/1` to `assign_async`; the
  `:failed` slot matches `{:error, %GithubError{}}` and
  `{:error, %{"message" => _}}`, but some failure shapes
  (`{:error, %Tesla.Env{}}` from `build_installation_client`) fall into the
  generic branch. Which shapes GitHub actually returns was not traced
  (`github_sync_component.ex:604-609`, `:1036-1043`).
- `test "authorized users get an error when initiating github sync if the usage limiter returns an error"`
  (`project_live_test.exs:7638-7771`) asserts only that the button is disabled;
  no test drives the sync-time limiter flash.

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should a failed connect undo what it already wrote to GitHub (6.1), or should
  the GitHub writes move out of the transaction with an explicit cleanup step?
- Should unrelated projects be allowed to share a repo branch (6.2)? Today only
  a sandbox family is guarded.
- Should disconnect tell the admin when GitHub cleanup was skipped or failed?
- Is putting the user's email in GitHub commit messages intended?
- In the rebuild, does the limit banner disable every control on the tab or only
  connect and sync?

## Proposed flows

- `flow-github-connect`: an admin clicks "Connect your GitHub Account" here (or
  on the profile), authorizes in a new GitHub tab, the callback controller saves
  the token and closes the tab, and a PubSub event makes this tab reload with
  "GitHub account linked successfully" and the connect form, or show "Oops!
  GitHub account failed to link. Please try again". Surfaces:
  project-settings-github-sync (`github_components.ex:11-28`),
  external:github-oauth-authorize, controller:oauth-github-callback
  (`oauth_controller.ex:7-29`), pubsub:version_control_events:<user_id>
  (`events.ex:14-32`), back into project-settings-github-sync
  (`settings.ex:688-708`) or profile-github. Tested by
  `project_live_test.exs:4774-4846`.
- `flow-github-app-install`: from the "Install or manage GitHub app
  installations" or "Create/update GitHub installations or modify permissions."
  link, the admin installs the GitHub App in a new tab; GitHub redirects to
  `/setup_vcs`, which closes the tab; the admin refreshes installations here
  (S07). Surfaces: project-settings-github-sync
  (`github_sync_component.html.heex:43-52`, `:117-125`),
  external:github-app-install, controller:setup-vcs (`router.ex:242`,
  `version_control_controller.ex:4-16`).
- `flow-github-sync-actions`: a connect (export), reconnect or "Initiate Sync to
  Branch" dispatches `openfn-pull.yml`, which calls Lightning's provisioning API
  with the repo secret and commits the project to the branch; commits to the
  branch run the deploy workflow, which pushes it back into the project.
  Surfaces: project-settings-github-sync, external:github-actions
  (`version_control.ex:473-561`, `priv/github/pull.yml` and `pull_v2.yml`,
  `priv/github/deploy.yml` and `deploy_v2.yml`), api:provision (token lookup
  `version_control.ex:457-459`), workflow-editor GitHubSyncModal
  (`GitHubSyncModal.tsx`) as a second entry.

## Proposed shared

- `shared-github-connect-link`: `GithubComponents.connect_to_github_link`
  (Connect / Reconnect label, expired-token tooltip, OAuth URL built from app
  config) rendered by this tab and by the profile GitHub card. Surfaces:
  project-settings-github-sync (`settings.html.heex:830-834`), profile-github
  (`live/profile_live/github_component.ex`).

## Lead resolution (batch 2)

- `flow-github-connect`, `flow-github-app-install` and
  `flow-github-sync-actions` created as proposed.
- `shared-github-connect-link` folded into `flow-github-connect`, which both
  this tab and profile-github start.
