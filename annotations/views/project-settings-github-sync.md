---
id: project-settings-github-sync
type: view
title: Project settings › Sync to GitHub
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#vcs
  new_route: /projects/:project_id/settings/github-sync
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "vcs" (settings.html.heex:55-58, :758; TabbedContainer, see shared-project-settings-tab-chrome)
    - the GitHub app is configured (cert, app_id, client_id and client_secret all set); otherwise only a "not configured" notice renders (settings.html.heex:779, :838-848; version_control.ex:562-568)
    - with no connection, the connect UI renders only for admins and owners (settings.html.heex:797-798)
    - with no connection, the connect form renders only when the viewer's own GitHub OAuth token is valid; otherwise a "Connect your GitHub Account" prompt renders (settings.html.heex:800, :819-836; settings.ex:915-917)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA, membership remount
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52); the GitHub-specific limit banner is this view's own (see S27)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation; role notice (S06 rows "viewer | Sync to GitHub" and "editor | Sync to GitHub"); sandbox banner (S08 row "Sync to GitHub")
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#vcs (URL fragment)"
    set_by: >-
      every redirect in this view (github_sync_component.ex:46, :61, :66, :77, :90, :201, :211, :261, :268, :281, :291, :305, :312;
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
    - ProjectLive.GithubSyncComponent#validate               # github_sync_component.ex:29-37
    - ProjectLive.GithubSyncComponent#save                   # :39-48, :193-214
    - ProjectLive.GithubSyncComponent#delete-connection      # :50-68
    - ProjectLive.GithubSyncComponent#reconnect              # :70-79, :249-294
    - ProjectLive.GithubSyncComponent#initiate-sync          # :81-92, :296-315
    - ProjectLive.GithubSyncComponent#refresh-installations  # :94-105
    - ProjectLive.GithubSyncComponent#refresh-branches       # :107-115
    - ProjectLive.Settings#handle_info OauthTokenAdded       # settings.ex:688-696 (handoff only; flow-github-connect)
    - ProjectLive.Settings#handle_info OauthTokenFailed      # settings.ex:698-708 (handoff only; flow-github-connect)
  js_hooks:
    - Tooltip (disabled-button tooltips via `.button tooltip`, new_inputs.ex:47, :115; connect link when a token exists, github_components.ex:26)
    - JS.toggle for the "Advanced: use new YAML config format" disclosure (github_sync_component.ex:739-742)
    - JS.hide dismiss on the "properly configured" banner (github_sync_component.ex:607)
    - custom-select listbox show/hide (new_inputs.ex:498-560)
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
    - LightningWeb.VersionControlController#index (/setup_vcs, router.ex:194; version_control_controller.ex:1-17); GitHub App post-install redirect, see proposed flow-github-app-install
    - LightningWeb.OauthController#new (/oauth/:provider/callback, router.ex:79; oauth_controller.ex:7-29); see proposed flow-github-connect
    - VersionControl.delete_github_oauth_grant/1 (version_control.ex:489-513); profile-github only
    - VersionControl.get_repo_connection_for_token/1 (version_control.ex:162-164); API provisioning path
    - GithubComponents.connect_to_github_link `github_query_params` override (github_components.ex:13, :18); only profile can pass it

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

Project admins link a project to a branch of a GitHub repository so the project's workflows are
kept under version control, and editors push the current project to that branch on demand. Teams
use it to review changes, keep history, and promote work between environments. Without it, a
project has no audited off-platform copy, and connecting the wrong branch or overwriting a project
by accident could destroy work in GitHub or in OpenFn.

## 2. What it does

- **Connect a project to a branch** (admins)
  - Admins connect their own GitHub account first, then pick an installation, a repository and a branch, refreshing the lists on demand
  - Admins choose the first sync direction: export this project to GitHub, or import from GitHub and overwrite this project
  - Admins confirm the files that will be written (and, for import, that the project will be destroyed) before connecting
- **See the connection**
  - Everyone on the project sees the saved connection and whether GitHub still has the files and secret it needs
  - Admins are told when they have no installations or GitHub can't be reached; everyone is told when the instance has no GitHub app set up
- **Sync and maintain it**
  - Editors and above start a sync to the branch
  - Admins reconnect a broken connection when their own GitHub account can reach its installation
  - Admins remove the connection, even when GitHub cleanup fails
- **What stops a connect or sync**
  - Sandboxes can't reuse a branch already linked elsewhere in the same project family
  - Workflows whose names collide stop a connect or sync before anything is pushed, and the message names them
  - A plan limit on GitHub sync blocks connecting and syncing, and says why

**Straightforwardness: 2 of 5.** Every action here writes files and secrets into someone's GitHub repo, and what's left behind when things go wrong, or who is allowed to fix it, takes real thought.

### Most surprising behaviours

- **(2)** If connecting fails partway, the project ends up with no connection, but the workflow files, config and an API secret it already wrote stay in the GitHub repo, with nothing on the page saying so. (6.1, 8)
- **(2)** Removing the connection can quietly leave the files and secret in GitHub: cleanup only happens with the remover's own GitHub account, failures aren't reported, and one workflow file is always left behind. (S26, 6.2)
- **(3)** Only sandboxes of the same project are stopped from sharing a branch. Two unrelated projects can both connect to the same repo and branch and overwrite each other's files. (6.2, 8)
- **(3)** The branch and installation lists only show GitHub's first page, so in a busy repo the branch you want may simply not be there. (6.1)
- **(3)** Whether you can repair a broken connection depends on your personal GitHub access, not just your role, so an owner can be shown the problem with no way to fix it. Reconnecting in the import direction can also silently do nothing. (S20, 6.1)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-49`, `:134`, `:160-172`; flags computed at
`lib/lightning_web/live/project_live/settings.ex:152-165`; template gates at
`settings.html.heex:779-836` and `github_sync_component.html.heex:198-204`, `:252-262`, `:272`;
handler checks at `github_sync_component.ex:40`, `:51`, `:71`, `:82`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab, the saved connection and its verification status | yes | yes | yes | yes | no (cannot open the project) | yes |
| See the "not configured for this Lightning instance" notice (github-disabled) | yes | yes | yes | yes | n/a | yes |
| See the connect-account prompt or the connect form (no connection yet) | no | no | yes | yes | n/a | no |
| Create a connection | no | no | yes | yes | n/a | no |
| Initiate a sync | no | yes | yes | yes | n/a | yes |
| Reconnect a broken connection | no | no | yes | yes | n/a | no |
| Remove the connection | no | no | yes | yes | n/a | no |

**Preconditions beyond role**
- Creating a connection needs the actor's own valid GitHub OAuth token (`settings.html.heex:800`; `version_control.ex:418-432`, `:829`); syncing does not (`project_live_test.exs:6809-6812`).
- Listing branches needs the selected installation to be one the actor's GitHub account can see (`version_control.ex:321-351`).
- Reconnecting needs the connection's installation to be in the actor's GitHub installation list (`github_sync_component.ex:317-322`; `github_sync_component.html.heex:198-204`).
- One connection per project (`project_repo_connection.ex:75-77`); a `(repo, branch)` pair is unique within a project family (`project_repo_connection.ex:78-82`, `:136-184`).
- Import from GitHub needs a config path (`project_repo_connection.ex:203-213`).
- Connect, reconnect and sync are refused while the `:github_sync` usage limit applies (`version_control.ex:55-58`, `:87-90`, `:179-182`).
- Removing GitHub files and the repo secret on disconnect needs the remover's own valid GitHub token; without it only the Lightning row is removed (`version_control.ex:757-778`).
- A member who hasn't met the project's MFA requirement never reaches this page (shared-project-scope); the policy also denies every action then (`project_users.ex:134`).

## 4. What it touches

**Reads**: `projects` (via scope and `Projects.root_id/1`), `project_users`, `project_repo_connections` (`version_control.ex:158-160`; tree conflict check `project_repo_connection.ex:167-184`), `users.github_oauth_token`, `workflows` and `workflow_snapshots` for the sync snapshot list and export pre-flight (`version_control.ex:220-247`)

**Writes**:
- `project_repo_connections` insert on connect, with a signed `access_token` and `root_project_id` (`version_control.ex:45-63`; `project_repo_connection.ex:107-134`, `:215-223`)
- `project_repo_connections` delete on remove (`version_control.ex:138-145`)
- `audit_events` `repo_connection_created` / `repo_connection_removed` (`audit.ex:5-56`; `version_control.ex:51-54`, `:141-144`)
- `users.github_oauth_token` when a refresh token is used to mint a new access token during any GitHub call (`version_control.ex:470-484`)
- Reconnect writes nothing to the database (`version_control.ex:83-95`)

**Immediate side effects**
- PubSub subscribe to `version_control_events:<user_id>` on connected mount (`settings.ex:104-106`; `events.ex:28-32`); handled in flow-github-connect
- Flash and `push_navigate` back to `#vcs` after every mutating action (component lines in url_params)

**Deferred side effects**
- A GitHub Actions `workflow_dispatch` of `openfn-pull.yml` on the default branch, which calls back into Lightning's provisioning API and commits to the connected branch (`version_control.ex:192-215`); see proposed flow-github-sync-actions
- The `openfn-<project_id>-deploy.yml` workflow pushes repo changes back into the project on commits to the branch (`version_control.ex:703-714`); see proposed flow-github-sync-actions

**External, non-transactional effects**
- Connect and reconnect push `.github/workflows/openfn-pull.yml` to the default branch, push `openfn-<project_id>-deploy.yml` and (when no config path) a config file to the chosen branch, and write repo secret `OPENFN_<project_id>_API_KEY` (`version_control.ex:574-663`, `:801-842`). On connect these run inside the DB transaction (`version_control.ex:49-62`), so a GitHub failure late in the chain rolls back the row but leaves the earlier commits and secret in the repo (see 6.1).
- Sync dispatches a GitHub Actions workflow (`version_control.ex:198-215`).
- Remove deletes the deploy workflow file, the config file and the repo secret from GitHub after the row is deleted, best effort and unchecked (`version_control.ex:146-155`, `:757-799`); `openfn-pull.yml` is left in place.
- Verification on every load of a connected tab reads the repo, three files and the secret from GitHub (`version_control.ex:97-133`).

**Depends on config**
- `:lightning, :github_app` decides whether the tab offers anything (github-disabled variant) and supplies the app link (`github_sync_component.ex:453-455`; `github_sync_component.html.heex:44`, `:98`) and the OAuth client id (`github_components.ex:33-40`)
- Usage limiter `:github_sync` action (github-sync-limited variant)

**Product limits**
- One GitHub connection per project (`project_repo_connection.ex:75-77`)

## 5. Scenarios

```gherkin
Feature: Sync a project to GitHub
  In order to keep a project's workflows under version control
  As a project admin or editor
  I want to link the project to a GitHub branch and sync it on demand

  @S01 @pending
  Scenario: Admin connects a branch and exports the project to GitHub
    # Value: a team gets an off-platform, reviewable copy of the project without leaving OpenFn.
    Given I am an admin on project "Malawi HIV" with a connected GitHub account
    And my GitHub installation "User: amara" can see repository "amara/hiv-sync" with branch "main"
    When I select installation "User: amara", repository "amara/hiv-sync" and branch "main"
    And I leave "OpenFn --> GitHub: Export to GitHub (default, non-destructive)" selected
    And I tick the confirmation checkbox
    And I click "Connect Branch & Initiate First Sync"
    Then I see "Connection made successfully"
    And I see "Repository: amara/hiv-sync" and branch "main"
    And an audit event "repo_connection_created" is recorded for the project
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:39-41, :193-202; version_control.ex:45-63, :821-842
    # github_sync_component.html.heex:3-188, :206-247; project_live_test.exs:5265-5442

  @S02 @pending
  Scenario: Admin connects a branch to import an existing project from GitHub
    # Value: a team whose project already lives in a repo can make that repo the source without exporting over it first.
    Given I am an admin on project "Malawi HIV" with a connected GitHub account
    When I select an installation, repository "amara/hiv-sync" and branch "main"
    And I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    And I enter "./config.json" in "Path to config (required)"
    And I tick the confirmation checkbox
    And I click "Connect Branch & Initiate First Sync"
    Then I see "Connection made successfully"
    And no sync to GitHub is started
    # github_sync_component.html.heex:150-158; version_control.ex:836-840; project_live_test.exs:5444-5561

  @S03 @pending
  Scenario: Importing from GitHub needs a config path
    # Value: an import can't be set up against a file that doesn't exist, which would leave the project overwritten by nothing.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    When I choose "GitHub --> OpenFn: Import from GitHub (overwrite this project)"
    And I leave "Path to config (required)" empty
    Then "Connect Branch & Initiate First Sync" stays disabled
    And the "Advanced: use new YAML config format" option is not shown
    # project_repo_connection.ex:203-213; github_sync_component.html.heex:150-163, :182

  @S04 @pending
  Scenario Outline: The connect confirmation spells out what will be overwritten
    # Value: nobody overwrites workflow files in a repo, or their OpenFn project, without being told first.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    And I have selected repository "amara/hiv-sync" and branch "main"
    When I choose "<direction>"
    Then I see "I understand that" followed by the files ".github/workflows/openfn-pull.yml", ".github/workflows/openfn-<project_id>-deploy.yml"
    And I <see_or_not> "my current OpenFn project will be destroyed"
    And "Connect Branch & Initiate First Sync" stays disabled until I tick the box
    # github_sync_component.ex:845-893; github_sync_component.html.heex:164-175, :182; project_repo_connection.ex:85-98

    Examples:
      | direction                                                            | see_or_not |
      | OpenFn --> GitHub: Export to GitHub (default, non-destructive)       | do not see |
      | GitHub --> OpenFn: Import from GitHub (overwrite this project)       | see        |

  @S05 @pending
  Scenario: Connect stays disabled until installation, repository and branch are chosen
    # Value: an incomplete connection never reaches GitHub.
    Given I am an admin filling in the connect form on project "Malawi HIV"
    When I have not chosen a branch
    Then "Connect Branch & Initiate First Sync" is disabled
    And if the form is submitted anyway I see "This field can't be blank"
    # project_repo_connection.ex:67-73; github_sync_component.html.heex:182; project_live_test.exs:5376-5386

  @S06 @pending
  Scenario: Repository and branch lists follow the choice above them
    # Value: an admin can only pick a repository and branch that the chosen installation actually exposes.
    Given I am an admin with access to installation "User: amara" holding repository "amara/hiv-sync"
    When I select installation "User: amara"
    Then "Repository" lists "amara/hiv-sync"
    When I select repository "amara/hiv-sync"
    Then "Branch" lists that repository's branches
    When I clear the installation
    Then no repository and no branch is selected
    # github_sync_component.ex:29-37, :150-175, :324-354, :417-428; github_sync_component.html.heex:104-127
    # project_live_test.exs:5004-5115

  @S07 @pending
  Scenario: Refreshing installations picks up a newly installed GitHub App
    # Value: an admin who installs the app in GitHub mid-setup can continue without reloading and losing the form.
    Given I am an admin on the connect form and my installations failed to load
    When the GitHub App is now installed on my account
    And I click the refresh button next to "GitHub Installation"
    Then "GitHub Installation" lists the new installation
    # github_sync_component.ex:94-105; github_sync_component.html.heex:74-90; project_live_test.exs:4848-4906

  @S08 @pending
  Scenario: Refreshing branches picks up a branch created after the page loaded
    # Value: an admin who just created a branch for OpenFn can select it without starting over.
    Given I am an admin with repository "amara/hiv-sync" selected, listing branch "main"
    When branch "openfn" is created in GitHub
    And I click the refresh button next to "Branch"
    Then "Branch" lists "main" and "openfn"
    And no branch is selected
    # github_sync_component.ex:107-115; github_sync_component.html.heex:131-144; project_live_test.exs:5148-5174

  @S09 @pending
  Scenario: Branches are never listed for an installation the user can't access
    # Value: one tenant can't read branch names from another tenant's private repositories through the shared GitHub App.
    Given I am an admin whose GitHub account can access installation "1234" only
    When the form is submitted with installation "9999" and a repository in it
    Then "Branch" lists no branches
    And clicking the refresh button next to "Branch" still lists no branches
    # version_control.ex:310-351; project_live_test.exs:5176-5263

  @S10 @pending @variant:sandbox
  Scenario: A sandbox can't claim a branch already linked in its project family
    # Value: two projects in one family never sync to the same branch and overwrite each other's files.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main"
    And I am an admin of its sandbox "dev"
    When I select "amara/hiv-sync" and branch "main" on the sandbox's connect form
    Then I see "this branch is already linked to another project in the same project family; use a different branch"
    And "Connect Branch & Initiate First Sync" is disabled
    When I select branch "dev"
    Then that message is gone
    # project_repo_connection.ex:13, :136-153; github_sync_component.ex:177-191
    # test/lightning_web/live/project_live/github_sync_component_test.exs:20-179

  @S11 @pending
  Scenario: Admin without installations is told to install the GitHub App
    # Value: an admin facing an empty list learns the fix instead of assuming GitHub is broken.
    Given I am an admin with a connected GitHub account and no GitHub App installations
    When I open the "Sync to GitHub" tab
    Then I see "No GitHub installations found"
    And I see "You haven't installed the OpenFn GitHub App yet, or you may have uninstalled it."
    And "Install or manage GitHub app installations" opens the app's GitHub page in a new tab
    # github_sync_component.ex:466-468; github_sync_component.html.heex:32-49; project_live_test.exs:4939-4958

  @S12 @pending
  Scenario: A GitHub outage while loading installations is reported
    # Value: admins know the problem is on GitHub's side and that refreshing may fix it.
    Given I am an admin with a connected GitHub account
    And GitHub returns an error when listing my installations
    When I open the "Sync to GitHub" tab
    Then I see "Unable to load GitHub installations"
    And I see "There was a problem connecting to GitHub. Refresh the page or contact support if the problem persists."
    And "GitHub Installation" is disabled
    # github_sync_component.ex:470-477; github_sync_component.html.heex:51-58, :67-70; project_live_test.exs:4983-5002

  @S13 @pending
  Scenario: Admin without a GitHub account is asked to connect one
    # Value: the admin learns the one prerequisite they are missing, and can fix it from here.
    Given I am an admin on project "Malawi HIV" with no GitHub account connected
    And the project has no GitHub connection
    When I open the "Sync to GitHub" tab
    Then I see "Connect your OpenFn account to GitHub"
    And I see a "Connect your GitHub Account" link that opens GitHub in a new tab
    And the flow "flow-github-connect" can start from this link
    # settings.html.heex:819-836; github_components.ex:16-31; project_live_test.exs:4697-4732

  @S14 @pending
  Scenario: Admin with an expired GitHub token is asked to reconnect it
    # Value: an admin whose access lapsed isn't shown a form that would fail on every call.
    Given I am an admin whose GitHub refresh token has expired
    And the project has no GitHub connection
    When I open the "Sync to GitHub" tab
    Then I see "Reconnect your GitHub Account"
    And I do not see the connect form
    # settings.html.heex:800, :819-836; version_control.ex:418-432; github_components.ex:26-28
    # project_live_test.exs:4960-4981

  @S15 @pending
  Scenario Outline: Only admins see how to connect a project
    # Value: only people trusted with access decisions can link a project's data to an outside repository.
    Given I am a <role> on project "Malawi HIV", which has no GitHub connection
    And I have a connected GitHub account
    When I open the "Sync to GitHub" tab
    Then I do not see "Connect your OpenFn account to GitHub"
    And I do not see "Create/update GitHub installations or modify permissions."
    # settings.html.heex:797-798; project_live_test.exs:4697-4772

    Examples:
      | role   |
      | viewer |
      | editor |

  @S16 @pending @variant:github-disabled
  Scenario: An instance without a GitHub app says so
    # Value: members know sync is unavailable on this instance rather than hidden from them, and who to ask.
    Given the instance has no GitHub app configured
    And I am a viewer on project "Malawi HIV"
    When I open the "Sync to GitHub" tab
    Then I see "Version Control is not configured for this Lightning instance. Contact the superuser for more information."
    # settings.html.heex:779, :838-848; version_control.ex:562-568; project_live_test.exs:4670-4695

  @S17 @pending
  Scenario: Everyone on the project sees the saved connection
    # Value: any member can find which repository and branch hold the project's history.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main" through installation "1234"
    And I am a viewer on the project
    When I open the "Sync to GitHub" tab
    Then I see "Repository:" linking to "https://www.github.com/amara/hiv-sync"
    And I see "Branch:" "main", "GitHub Installation ID:" "1234", "Path to config:" and "Sync version:"
    And I do not see the connect form
    # github_sync_component.html.heex:206-247; settings.html.heex:780-796; project_live_test.exs:5924-5958

  @S18 @pending
  Scenario: A healthy connection is confirmed
    # Value: members can trust a sync will work before they start one.
    Given project "Malawi HIV" is connected and the repo has its workflow files, config and API secret
    When I open the "Sync to GitHub" tab
    Then I eventually see "Your repository is properly configured."
    And I do not see "Click here to reconnect"
    # version_control.ex:97-133; github_sync_component.ex:145-147, :594-617; project_live_test.exs:6368-6502

  @S19 @pending
  Scenario: A broken connection is flagged and admins can reconnect
    # Value: when someone deletes the workflow files or secret in GitHub, the team finds out here and can repair it in place.
    Given project "Malawi HIV" is connected but the deploy workflow file is missing on the branch
    And I am an admin whose GitHub account can access the connection's installation
    When I open the "Sync to GitHub" tab
    Then I eventually see "Your GitHub project is not properly connected with Lightning."
    And I see "There was a problem connecting to GitHub"
    And I see "Click here to reconnect"
    And "Initiate Sync to Branch" is disabled
    # version_control.ex:844-860; github_sync_component.ex:549-593; github_sync_component.html.heex:191-205, :252-255
    # project_live_test.exs:6078-6201

  @S20 @pending
  Scenario Outline: Reconnect is offered only to admins who can reach the installation
    # Value: a repair is attempted only by someone with both the authority and the GitHub access to complete it.
    Given project "Malawi HIV" has a broken GitHub connection
    And I am a <role> who <access> the connection's installation
    When I open the "Sync to GitHub" tab
    Then I do not see "Click here to reconnect"
    # github_sync_component.html.heex:198-204; github_sync_component.ex:317-322
    # project_live_test.exs:5960-6037 (viewer, editor), :6039-6076 (admin, owner without access)

    Examples:
      | role   | access              |
      | viewer | can access          |
      | editor | can access          |
      | admin  | cannot access       |
      | owner  | cannot access       |

  @S21 @pending
  Scenario: Admin reconnects a broken connection
    # Value: a damaged repo setup is restored without removing and recreating the connection.
    Given project "Malawi HIV" has a broken GitHub connection
    And I am an admin whose GitHub account can access its installation
    When I click "Click here to reconnect"
    And in "Reconnect to GitHub" I keep "OpenFn --> GitHub" selected, tick the confirmation and click "Reconnect"
    Then I see "Connected to GitHub"
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:70-72, :249-262, :673-728; version_control.ex:83-95; project_live_test.exs:6078-6201

  @S22 @pending
  Scenario: Editor starts a sync
    # Value: the people who change workflows can push them to GitHub without waiting on an admin.
    Given project "Malawi HIV" is connected and verified
    And I am an editor with no GitHub account connected
    When I click "Initiate Sync to Branch"
    Then I see "GitHub sync initiated"
    And the flow "flow-github-sync-actions" has started for project "Malawi HIV"
    # github_sync_component.ex:81-83, :296-306; version_control.ex:174-218; project_live_test.exs:6798-6920

  @S23 @pending
  Scenario: Viewers can't start a sync and are told who can
    # Value: read-only members can't push changes out, and know whom to ask.
    Given project "Malawi HIV" is connected
    And I am a viewer on the project
    When I open the "Sync to GitHub" tab
    Then "Initiate Sync to Branch" is disabled with the tooltip "Contact an editor or admin to sync."
    And I do not see "Remove Integration."
    # github_sync_component.html.heex:250-268, :272; project_live_test.exs:6707-6748

  @S24 @pending
  Scenario Outline: The server refuses actions a role isn't allowed, even if the control is bypassed
    # Value: hiding a button is not the only thing standing between a read-only member and the project's GitHub link.
    Given project "Malawi HIV" is connected
    And I am a <role> on the project
    When a "<event>" event reaches the GitHub sync component
    Then I see "You are not authorized to perform this action"
    And the connection is unchanged
    # github_sync_component.ex:39-92; project_live_test.exs:5960-6037 (reconnect), :6504-6565 (delete-connection), :6707-6748 (initiate-sync)

    Examples:
      | role   | event             |
      | viewer | initiate-sync     |
      | viewer | reconnect         |
      | editor | reconnect         |
      | viewer | delete-connection |
      | editor | delete-connection |
      | editor | save              |

  @S25 @pending
  Scenario: Admin removes the integration after confirming
    # Value: a project can be unlinked from a repository it should no longer write to, with a record of who did it.
    Given project "Malawi HIV" is connected to "amara/hiv-sync"
    And I am an admin on the project
    When I click "Remove Integration."
    Then I see "Remove Integration?" and "You are about to disconnect this project from GitHub."
    When I click "Disconnect"
    Then I see "Connection removed successfully"
    And the project has no GitHub connection
    And an audit event "repo_connection_removed" is recorded for the project
    # github_sync_component.html.heex:272-286; github_sync_component.ex:50-61, :623-665; version_control.ex:138-156
    # project_live_test.exs:6567-6621

  @S26 @pending
  Scenario: Removal succeeds even when GitHub cleanup can't
    # Value: an admin can always cut a project's link to a repo, even if they never connected GitHub themselves or GitHub refuses the cleanup.
    Given project "Malawi HIV" is connected
    And I am an admin with no GitHub account connected
    When I remove the integration
    Then I see "Connection removed successfully"
    And the project has no GitHub connection
    # version_control.ex:146-155, :757-778; project_live_test.exs:6567-6621, :6623-6705

  @S27 @pending @variant:github-sync-limited
  Scenario: A GitHub sync plan limit blocks connecting and syncing and says why
    # Value: a project over its plan learns why sync is unavailable instead of hitting a failure after filling in the form.
    Given the usage limiter refuses GitHub sync for project "Malawi HIV" with a banner message
    And I am an admin on the project
    When I open the "Sync to GitHub" tab
    Then I see the limiter's banner message
    And "Connect Branch & Initiate First Sync" is disabled
    # hooks.ex:204-212; settings.html.heex:770-778, :790, :812; github_sync_component.html.heex:182
    # project_live_test.exs:5854-5922, :7057-7091 (banner for viewer, editor, admin, owner)

  @S28 @pending @variant:github-sync-limited
  Scenario: The limit is checked again when the action runs
    # Value: a limit that starts applying after the page loaded still stops the connection, sync or reconnect.
    Given I am an admin on the connect form of project "Malawi HIV"
    And the usage limiter starts refusing GitHub sync with "Plan limit reached"
    When I submit the connect form
    Then I see "Plan limit reached"
    And the project has no GitHub connection
    # version_control.ex:55-58, :87-90, :179-182; github_sync_component.ex:207-212, :216-219
    # project_live_test.exs:5563-5660 (connect), :6276-6366 (reconnect)

  @S29 @pending
  Scenario: Colliding names stop a sync before anything reaches GitHub
    # Value: a sync never silently drops one of two workflows whose names map to the same key, and the user knows which to rename.
    Given project "Malawi HIV" is connected
    And it has workflows "My Flow" and "My-Flow"
    And I am an admin on the project
    When I click "Initiate Sync to Branch"
    Then I see an error naming "My Flow" and "My-Flow"
    And no workflow is dispatched in GitHub
    # version_control.ex:183-191; export_utils/duplicate_key_error.ex:22-26; github_sync_component.ex:241-242
    # project_live_test.exs:6750-6796 (sync), :6203-6274 (reconnect, nothing written to the repo)

  @S30 @pending
  Scenario: GitHub's own error message is shown when a connect fails
    # Value: an admin can act on what GitHub said (permissions, protected branch) instead of a generic failure.
    Given I am an admin submitting the connect form on project "Malawi HIV"
    And GitHub refuses a file write with message "Resource not accessible by integration"
    When the connect runs
    Then I see "GitHub Error: Resource not accessible by integration"
    And the project has no GitHub connection
    # github_sync_component.ex:207-212, :216-246; project_live_test.exs:5662-5760, :5758-5852
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Connect writes to GitHub inside the DB transaction, after the insert and audit; if a later step fails (secret write, first sync dispatch, usage limit already passed), the row rolls back but pull.yml, the deploy workflow, the config file and possibly the secret stay in the repo | `version_control.ex:49-62`, `:821-842` | an error flash, no connection, and a repo that now has OpenFn workflow files and a secret pointing at a token that was never saved | fix |
| A lost race on the family branch index returns `{:error, :branch_used_in_project_tree}`, an atom, which `error_message/1` doesn't match | `version_control.ex:65-77`; `github_sync_component.ex:216-246` | "Oops! An error occurred while connecting to GitHub. Please try again later" instead of the branch-in-use message | fix |
| Reconnect with "Import from GitHub" on a connection with no config path fails `validate_sync_direction` on `config_path`, but the reconnect modal has no config path field to show the error on | `project_repo_connection.ex:100-105`, `:203-213`; `github_sync_component.ex:271-272`, `:692-725` | clicking "Reconnect" does nothing visible | fix |
| `delete-connection` pattern-matches `{:ok, _}`; a failed or stale delete (removed in another tab) crashes the component | `github_sync_component.ex:52-56`; `version_control.ex:138-145` | the LiveView crashes and reloads | fix |
| The "Connect your GitHub Account" link is only restyled when a limit banner disables it; its `href` still opens GitHub OAuth | `github_components.ex:21-25`; `settings.html.heex:833` | a link that looks disabled but works | decide |
| The branch refresh icon spins on `@installations.loading`, not `@branches.loading` | `github_sync_component.html.heex:140-143` | no spinner while branches reload; a spinner on the branch button while installations reload | fix |
| `on_mount :limit_github_sync` matches only `{:error, %{function: f}}`; a limiter returning `{:error, _, %{text: ...}}` (the shape the connect path handles) raises a CaseClauseError | `hooks.ex:204-212`; `github_sync_component.ex:218-219` | the whole settings page fails to mount for that project | decide |
| Branch list calls `/repos/:repo/branches` with no pagination | `github_client.ex:44-46`; `version_control.ex:321-332` | repositories with more than GitHub's default page of branches (30) list only the first page; the wanted branch may be missing | fix |
| Installation list calls `/user/installations` with no pagination, and branch authorization reuses that list | `github_client.ex:30-32`; `version_control.ex:257-268`, `:334-351` | an account with more than one page of installations can't see or use the later ones | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Unrelated projects (no shared root) may connect to the same repo and branch; only a project family is guarded | `project_repo_connection.ex:136-153`; `github_sync_component_test.exs:181-247` | decide |
| Reconnect re-pushes files, rewrites the secret and, for export, dispatches a sync, but records no audit event | `version_control.ex:83-95`; `audit.ex:8-11` | decide |
| Disconnect removes the deploy workflow, config file and secret but leaves `openfn-pull.yml` on the default branch | `version_control.ex:757-778` | preserve |
| Disconnect cleanup runs only with the remover's own GitHub token and its results are ignored, so files and secret can be left behind with no message | `version_control.ex:146-155`, `:757-778` | decide |
| The manual sync commit message embeds the user's email ("user <email> initiated a sync from Lightning"); the first sync on connect passes the bare email as the commit message | `github_sync_component.ex:298`; `version_control.ex:837` | decide |
| The disabled connect button's tooltip reads `:text` from the limiter's banner map, which the function-component shape doesn't carry, so the tooltip is empty | `settings.html.heex:791-794`, `:813-816`; `project_live_test.exs:5854-5922` | fix |
| Only "GitHub Installation" and the connect button honour the limit banner; repository, branch, refresh-branches and "Remove Integration." stay active | `github_sync_component.html.heex:67-70`, `:113-115`, `:127`, `:136`, `:272-281` | decide |
| With `github_enabled?` false, an existing connection is hidden behind the "not configured" notice | `settings.html.heex:779-848` | preserve |
| `validate`, `refresh-installations` and `refresh-branches` have no permission check; any member who sends them to the component calls GitHub with their own token | `github_sync_component.ex:29-37`, `:94-115` | preserve |
| The connected view loads the viewer's own installation list on every mount, for every role, just to decide whether to show reconnect | `github_sync_component.ex:141-144`, `:317-322` | decide |
| "Path to config" placeholder suggests `./openfn-<project_id>-config.json`, the default path for export, on a field shown only for import | `github_sync_component.html.heex:150-157`; `project_repo_connection.ex:225-232` | decide |
| The YAML format toggle is hidden when "Import from GitHub" is chosen, so an import can't be marked v2 | `github_sync_component.html.heex:159-163` | decide |
| Collision errors come from export and end "Rename one of them and export again.", and start lowercase in the flash | `export_utils/duplicate_key_error.ex:22-26`; `github_sync_component.ex:241-242` | decide |
| Labels in title case and arrow glyphs: "Connect Branch & Initiate First Sync", "Initiate Sync to Branch", "Remove Integration.", "OpenFn --> GitHub" | `github_sync_component.html.heex:185`, `:267`, `:280`; `github_sync_component.ex:802`, `:824` | decide |
| "Syncing.." uses two dots | `github_sync_component.html.heex:264` | preserve |
| Every action ends in a full `push_navigate` to `#vcs` rather than a patch | `github_sync_component.ex:46-312`; `settings.ex:695` | preserve |
| The "properly configured" banner's dismiss only hides it client-side; it returns on next load | `github_sync_component.ex:604-614` | preserve |
| The repository link uses `https://www.github.com/` | `github_sync_component.html.heex:211` | preserve |
| The accept checkbox appears only once a branch is chosen | `github_sync_component.html.heex:164-175` | preserve |
| `reconfigure_changeset` requires `accept` but doesn't check it is true, unlike `configure_changeset` | `project_repo_connection.ex:85-105` | preserve |
| The verify banner prints raw GitHub error text inside `<code>` | `github_sync_component.ex:560-569` | decide |
| "Sync version" shows "v2 (new)" or "v1 (legacy)" from a boolean | `github_sync_component.html.heex:240-247` | preserve |
| `user_has_valid_oauth_token` treats a token with a still-valid refresh token as valid even if the access token has expired; the refresh happens on the first GitHub call | `settings.ex:915-917`; `version_control.ex:418-432`, `:470-484` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| "Your GitHub authentication has expired or is invalid." banner | `github_sync_component.html.heex:13-30`; `github_sync_component.ex:457-464` | the form renders only when the token is valid (`settings.html.heex:800`), and `:invalid_oauth_token` is raised only for a missing or expired refresh token (`version_control.ex:440-468`); reachable only if the token expires between mount and the async fetch |
| `phx-target={@myself}` on the "Remove Integration." link | `github_sync_component.html.heex:277-278` | the link's `phx-click` is a JS command; the target has no effect |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Repos for every installation are fetched in parallel with a 30 s per-installation timeout; a timed-out installation is silently dropped from the repo map | `github_sync_component.ex:367-377` | yes, an installation with no repositories listed | decide |
| Installation repos are paged 100 at a time, later pages fetched 5 at a time with no timeout; a failed page is logged and skipped | `version_control.ex:270-306` | yes, missing repositories | preserve |
| Every mount of a connected tab makes about six GitHub calls to verify (repo, three files, secret) plus the installation lookup, for every viewer | `version_control.ex:97-133`; `github_sync_component.ex:141-147` | no, beyond the "Verifying connection..." spinner | decide |
| Each sync runs a full YAML export as a pre-flight and throws it away | `version_control.ex:166-191` | no | preserve |
| Connect holds a DB transaction open across a chain of GitHub HTTP calls | `version_control.ex:49-62` | no | decide |

### 6.5 Things seen but not understood

- The "Remove Integration." link has `href="#"` alongside a JS `phx-click`; whether LiveView prevents the default navigation (which would change the fragment to `#` and, through TabbedContainer, drop the open tab) was not verified (`github_sync_component.html.heex:274-278`).
- `verify_connection/1` returns the raw `{:error, ...}` from `verify_github_connection/1` to `assign_async`; the `:failed` slot matches `{:error, %GithubError{}}` and `{:error, %{"message" => _}}`, but some failure shapes (`{:error, %Tesla.Env{}}` from `build_installation_client`) fall into the generic branch. Which shapes GitHub actually returns was not traced (`github_sync_component.ex:446-451`, `:560-569`).
- `test "authorized users get an error when initiating github sync if the usage limiter returns an error"` (`project_live_test.exs:6922-7055`) asserts only that the button is disabled; no test drives the sync-time limiter flash.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a failed connect undo what it already wrote to GitHub (6.1), or should the GitHub writes move out of the transaction with an explicit cleanup step?
- Should unrelated projects be allowed to share a repo branch (6.2)? Today only a sandbox family is guarded.
- Should disconnect tell the admin when GitHub cleanup was skipped or failed?
- Should reconnect be audited like connect and remove?
- Is putting the user's email in GitHub commit messages intended? (owner: product)
- In the rebuild, does the limit banner disable every control on the tab or only connect and sync?

## Proposed flows

- `flow-github-connect`: an admin clicks "Connect your GitHub Account" here (or on the profile), authorizes in a new GitHub tab, the callback controller saves the token and closes the tab, and a PubSub event makes this tab reload with "GitHub account linked successfully" and the connect form, or show "Oops! GitHub account failed to link. Please try again". Surfaces: project-settings-github-sync (`github_components.ex:16-31`), external:github-oauth-authorize, controller:oauth-github-callback (`oauth_controller.ex:7-29`), pubsub:version_control_events:<user_id> (`events.ex:14-32`), back into project-settings-github-sync (`settings.ex:688-708`) or profile-github. Tested by `project_live_test.exs:4774-4846`.
- `flow-github-app-install`: from the "Install or manage GitHub app installations" or "Create/update GitHub installations or modify permissions." link, the admin installs the GitHub App in a new tab; GitHub redirects to `/setup_vcs`, which closes the tab; the admin refreshes installations here (S07). Surfaces: project-settings-github-sync (`github_sync_component.html.heex:40-47`, `:95-101`), external:github-app-install, controller:setup-vcs (`router.ex:194`, `version_control_controller.ex:4-16`).
- `flow-github-sync-actions`: a connect (export), reconnect or "Initiate Sync to Branch" dispatches `openfn-pull.yml`, which calls Lightning's provisioning API with the repo secret and commits the project spec to the branch; commits to the branch run the deploy workflow, which pushes the spec back into the project. Surfaces: project-settings-github-sync, external:github-actions (`version_control.ex:192-215`, `priv/github/pull.yml`, `priv/github/deploy.yml`), api:provision (token lookup `version_control.ex:162-164`), workflow-editor GitHubSyncModal (`GitHubSyncModal.tsx`) as a second entry.

## Proposed shared

- `shared-github-connect-link`: `GithubComponents.connect_to_github_link` (Connect / Reconnect label, expired-token tooltip, OAuth URL built from app config) rendered by this tab and by the profile GitHub card. Surfaces: project-settings-github-sync (`settings.html.heex:830-834`), profile-github (`live/profile_live/github_component.ex`).

## Lead resolution (batch 2)

- `flow-github-connect`, `flow-github-app-install` and `flow-github-sync-actions` created as proposed.
- `shared-github-connect-link` folded into `flow-github-connect`, which both this tab and profile-github start.
