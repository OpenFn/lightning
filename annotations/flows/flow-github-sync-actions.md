---
id: flow-github-sync-actions
type: flow
title: Sync a project to and from GitHub
status: not-started
owner:

trigger:
  entry: project-settings-github-sync       # "Initiate Sync to Branch", or a connect/reconnect; also workflow-editor-versions-and-promote ("Save & Sync")
  exit: workflows-index                     # the project's workflows, after a commit to the branch deploys back
  surfaces:
    - project-settings-github-sync          # initiate-sync, connect, reconnect (github_sync_component.ex:39-92, :193-315)
    - workflow-editor-versions-and-promote  # Save & Sync split button and GitHubSyncModal (Header.tsx:144-191, :635-643; GitHubSyncModal.tsx:33-212)
    - controller:workflow-channel-save-and-sync   # WorkflowChannel "save_and_sync" (workflow_channel.ex:516-547, :886-942)
    - external:github-workflow-dispatch     # POST repos/:repo/actions/workflows/openfn-pull.yml/dispatches on the default branch (version_control.ex:192-215; github_client.ex:21-28)
    - external:github-actions-pull          # priv/github/pull.yml, openfn/cli-pull-action@v1
    - controller:api-provision-show         # GET /api/provision/:id and GET /api/provision/yaml (router.ex:114-115; provisioning_controller.ex:131-205)
    - external:github-branch-commit         # the pull action commits the project spec to the connected branch; or someone pushes/merges to it
    - external:github-actions-deploy        # priv/github/deploy.yml, openfn/cli-deploy-action@v1, on push to the branch
    - controller:api-provision-create       # POST /api/provision (router.ex:115; provisioning_controller.ex:62-100)
    - pubsub:project_events:<project_id>#WorkflowDeleted   # provisioner.ex:132-134; receiving end owned by flow-delete-open-workflow
    - workflows-index
    - sandboxes-index   # added by lead
  reachable_when:
    - the project has a GitHub connection (version_control.ex:158-160); without one the editor shows a plain Save button (Header.tsx:90-128) and the settings tab shows the connect form
    - the GitHub app is configured on the instance (version_control.ex:562-568); otherwise the settings tab shows only the "not configured" notice (project-settings-github-sync S16)
    - for a settings-tab sync, the connection verified healthy, since "Initiate Sync to Branch" is disabled otherwise (github_sync_component.html.heex:250-255)
    - for an editor sync, the workflow is saveable (useWorkflow.tsx:886-930) and not live outside a sandbox, where the save button is not rendered (Header.tsx:880-899)
    - the deploy direction needs nobody in Lightning: any push to the connected branch that GitHub runs deploy.yml for (deploy.yml:1-4)

inherits:
  - shared-authenticated-session            # both Lightning-side entry surfaces
  - shared-project-scope                    # entry surfaces only; the API hops are scoped through Projects.Scope separately (policies/provisioning.ex:59-69)

url_params:
  - name: "#vcs (URL fragment)"
    set_by: workflow-editor-versions-and-promote ("Modify connection" link, GitHubSyncModal.tsx:135-145)
    effect: opens project-settings-github-sync; owned by that view
  - name: snapshots (query, on GET /api/provision)
    set_by: external:github-actions-pull (pull.yml:19-21, :38)
    effect: limits the returned spec to those workflow snapshots (provisioning_controller.ex:142-143, :199)

config_variants:
  default: { github_app: { app_id, app_name, client_id, client_secret, cert all set }, usage_limiter: Lightning.Extensions.UsageLimiter }   # config/test.exs:168; read under this one
  github-sync-limited: { usage_limiter: <refuses %Action{type: :github_sync}> }   # version_control_usage_limiter.ex:11-21; provisioner.ex:1091-1095; workflow_channel.ex:2425-2427
  sync-v2: { project_repo_connection.sync_version: true }   # config file is openfn.yaml instead of openfn-<id>-config.json (project_repo_connection.ex:225-235; version_control.ex:672-685); not followed past the config file
  import-direction: { project_repo_connection.sync_direction: deploy }   # connect commit not marked [skip actions] (version_control.ex:602-605)

inventory:
  routes:
    - get /api/provision/yaml  API.ProvisioningController :show_yaml   # router.ex:114
    - get /api/provision/:id  API.ProvisioningController :show         # router.ex:115
    - post /api/provision  API.ProvisioningController :create          # router.ex:115
  events:
    - WorkflowChannel#save_and_sync                                    # workflow_channel.ex:516-547
    - ProjectLive.GithubSyncComponent#initiate-sync                    # owned by project-settings-github-sync; handoff here
  js_hooks:
    - GitHubSyncModal (Headless UI dialog; Ctrl/Cmd+Enter submit, GitHubSyncModal.tsx:73-78)
    - Header Save & Sync menu item and Ctrl/Cmd+Shift+S shortcut (Header.tsx:144-191, :635-643)
  policies:
    - Lightning.Policies.ProjectUsers :initiate_github_sync (settings tab; project_users.ex:39-49)
    - Lightning.Policies.ProjectUsers :edit_workflow (editor Save & Sync; workflow_channel.ex:1915-1956)
    - Lightning.Policies.Provisioning :describe_project, :provision_project for a %ProjectRepoConnection{} actor (policies/provisioning.ex:59-69)
  workers: []
  api_endpoints:
    - GET /api/provision/:id
    - GET /api/provision/yaml
    - POST /api/provision
  emails: []
  config:
    - :lightning, :github_app (installation client for the dispatch; github_client.ex:162-177)
    - Lightning.Config.repo_connection_token_signer (the secret the Actions authenticate with; project_repo_connection.ex:215-223)
    - :lightning, Lightning.Extensions, :usage_limiter (action :github_sync)
  not_reachable_here:
    - Provisioner.import_document :reconcile_collaboration and :release options (provisioner.ex:62-71, :514-539); the provisioning controller passes neither
    - Provisioner.maybe_add_project_credentials for a repo connection actor (provisioner.ex:942-944); only a %User{} adds credentials

related:
  - project-settings-github-sync
  - flow-delete-open-workflow               # receiving end of WorkflowDeleted after a deploy removes a workflow
  - lib/lightning/version_control/version_control.ex
  - lib/lightning/version_control/project_repo_connection.ex
  - lib/lightning/projects/provisioner.ex
  - lib/lightning/policies/provisioning.ex
  - lib/lightning/projects/scope.ex
  - lib/lightning_web/controllers/user_auth.ex
  - priv/github/pull.yml
  - priv/github/deploy.yml
  - test/lightning_web/controllers/api/provisioning_controller_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - assets/test/collaborative-editor/components/GitHubSyncModal.test.tsx
  - assets/test/collaborative-editor/components/Header.keyboard.test.tsx
flows:
  - flow-delete-open-workflow
---

## 1. Purpose

Teams that keep a project in GitHub need the branch to hold what Lightning is running, and need
changes reviewed and merged in GitHub to reach Lightning without anyone copying them across. Editors
push the project out from the settings tab or straight from the workflow editor; GitHub Actions do
the commit and the deploy back, authenticated with a per-connection secret. If this breaks, the repo
silently drifts from production, or a push from GitHub overwrites the wrong project, revives one
being shut down, or reaches a project it was never connected to.

## 2. What it does

1. An editor (or above) on a connected project starts a sync, either with "Initiate Sync to Branch" on the Sync to GitHub settings tab, or with "Save & Sync" in the workflow editor.
   - In the editor they first see the repository and branch, write a commit message (never blank), and the workflow is saved
   - Viewers, projects with no connection, projects over their plan's sync limit, and projects with clashing workflow names are stopped with a message
2. OpenFn asks GitHub to run a pull Action, and tells the editor it's done.
3. The pull Action fetches the project's saved, current workflows from OpenFn using a secret stored in the repository, and commits them to the branch.
4. Any commit to the branch runs a deploy Action, which writes the branch's contents back into the project.
   - Changes show in the audit trail as made by "GitHub", and a deleted workflow closes for anyone who has it open
   - A deploy is refused for another project, a project scheduled for deletion, or a project over its sync limit
   - On connect, export mode marks the first commits to skip the deploy; import mode deploys the branch over the project straight away
5. Removing the connection in OpenFn cuts the repository's access, even if the secret is still in GitHub.

**Straightforwardness: 2 of 5.** Most of the journey happens in GitHub, out of OpenFn's sight, so what the editor is told and what actually happened can differ, and changes arriving from GitHub don't play well with people editing at the same time.

### Most surprising behaviours

- **(2)** "Save & Sync" saves first and syncs second. If the sync part fails, the editor seems to get a failure message with Retry even though the workflow was saved, and colleagues' screens don't learn it was saved. (6.1)
- **(2)** "Workflow saved and synced to GitHub" appears as soon as GitHub accepts the request. The Action can still fail afterwards and OpenFn never finds out. (6.1)
- **(2)** A deploy from GitHub doesn't update anyone who has that workflow open in the editor; they keep editing the old version, and what their next save does to the deployed change hasn't been traced. (6.2, 6.5)
- **(3)** It's unclear whether the pull Action's own commit triggers the deploy Action; if it does, every sync deploys straight back into the project. (6.5)
- **(3)** In the editor, GitHub's errors show as "An internal error occurred", while the settings tab shows GitHub's real message for the same problem. (6.1)

## 3. Who can do what

Sources: `project_users.ex:39-49`, `:160-172`; `policies/provisioning.ex:38-71`; `scope.ex:122-129`, `:156-160`, `:208-215`; `user_auth.ex:241-266`, `:357-367`; `workflow_channel.ex:527-528`, `:1915-1977`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) | Repo connection token |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|-----------------------|
| See the Save & Sync option in the editor | yes, disabled | yes | yes | yes | n/a | yes | n/a |
| Start a sync from the settings tab | no | yes | yes | yes | n/a | yes | n/a |
| Save & Sync from the editor | no | yes | yes | yes | n/a | yes | n/a |
| Read the project spec (`GET /api/provision`) | n/a | n/a | n/a | n/a | n/a | n/a | own project only |
| Deploy into the project (`POST /api/provision`) | n/a | n/a | n/a | n/a | n/a | n/a | own project only |
| Create a new project through the API | n/a | n/a | n/a | n/a | n/a | n/a | no |

People calling the API with their own token are outside this flow; the matrix covers only the token the Actions carry.

**Preconditions beyond role**
- The Actions authenticate with the connection's `access_token`, stored in the repo as secret `OPENFN_<project_id>_API_KEY` (`version_control.ex:752-755`, `:801-820`); the bearer is resolved by a lookup on `project_repo_connections.access_token`, so deleting the connection row revokes it (`user_auth.ex:263-266`; `version_control.ex:162-164`, `:138-145`).
- A repo connection may act only on the project it belongs to, and never on one scheduled for deletion (`scope.ex:122-129`, `:150-160`).
- A repo connection is exempt from the project's MFA requirement (`scope.ex:202-215`).
- The `:github_sync` usage limit is checked at dispatch (`version_control.ex:178-182`) and at deploy (`provisioner.ex:97-99`, `:1091-1095`), not when the spec is read.
- The editor path also requires the workflow to be editable (not live outside a sandbox, not a pinned version) (`workflow_channel.ex:1915-1937`; `useWorkflow.tsx:886-930`).
- Whether a GitHub user may push to the branch, and whether the Actions run, is decided in GitHub.

## 4. What it touches

**Hop 1a, project-settings-github-sync (entry)**
- Reads: `project_repo_connections`; `workflows` and `workflow_snapshots` for the snapshot list and the export pre-flight (`version_control.ex:166-191`, `:220-231`)
- Writes: none in Lightning
- Flash "GitHub sync initiated" and `push_navigate` to `#vcs` (`github_sync_component.ex:296-306`)

**Hop 1b, workflow-editor-versions-and-promote → controller:workflow-channel-save-and-sync (entry)**
- Writes: the workflow through `Session.save_workflow/2` (workflows, jobs, triggers, edges, a snapshot), before the sync is attempted (`workflow_channel.ex:534-541`)
- Broadcast `workflow_saved` to the other clients in the room, only when both save and dispatch succeed (`workflow_channel.ex:886-906`)
- Toast "Workflow saved and synced to GitHub" with a link to `https://github.com/<repo>/actions` (`useWorkflow.tsx:626-652`)

**Hop 2, external:github-workflow-dispatch**
- An installation token is minted for the connection's installation (`github_client.ex:162-177`), the repo's default branch is read, and `openfn-pull.yml` is dispatched on it with `projectId`, `apiSecretName`, `pathToConfig`, `branch`, `commitMessage` and, when the project has workflows, the space-separated current snapshot ids (`version_control.ex:192-215`, `:249-255`)

**Hop 3, external:github-actions-pull → controller:api-provision-show**
- Reads: `projects`, workflows, jobs, triggers, edges, credentials and collections for the spec (`provisioning_controller.ex:131-148`, `:187-205`)
- Writes on `GET /api/provision/:id`: a workflow version row for any workflow without one (`provisioning_controller.ex:141`, `:150-157`)
- The Action commits the spec and state to the connected branch (pull.yml:30-38; external)

**Hop 4, external:github-actions-deploy → controller:api-provision-create**
- Writes, in one transaction: the project's workflows, jobs, triggers, edges, collections and channels; triggers of soft-deleted workflows disabled; orphaned edges removed (`provisioner.ex:97-125`)
- Audit: workflow `inserted_by_provisioner` / `updated_by_provisioner` / `deleted_by_provisioner`, `snapshot_created`, and channel events, with the repo connection as actor, shown as "GitHub" in the audit trail (`provisioner.ex:115-117`, `:330-417`, `:468-499`; `workflows/audit.ex:38-49`; `auditing.ex:47-58`)
- Workflow versions recorded with source `"cli"` (`provisioner.ex:384-402`)
- PubSub `WorkflowUpdated` on `workflow_events:<project_id>` for every workflow, and `WorkflowDeleted` on the project topic for each deleted one (`provisioner.ex:130-134`; `workflows/events.ex:9-29`; `projects/events.ex:123-131`)

**Immediate side effects**
- none beyond the per-hop list

**Deferred side effects**
- Every hop after the dispatch happens later, in GitHub Actions, outside any Lightning request

**External, non-transactional effects**
- The dispatch starts a GitHub Actions run that Lightning neither tracks nor reports on
- The pull Action's commit to the branch cannot be undone from Lightning

**Depends on config**
- `:lightning, :github_app` for the installation token (`github_client.ex:162-164`)
- Usage limiter `:github_sync` (github-sync-limited)
- `sync_version` decides the config file the Actions read (sync-v2)
- `sync_direction` decides whether the connect commit triggers a deploy (import-direction)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Sync a project to and from GitHub
  In order to keep a GitHub branch and a Lightning project in step
  As a project editor
  I want to push the project to GitHub and have commits to the branch deploy back

  @S01 @pending
  Scenario: An editor syncs the project to its branch from the settings tab
    # Value: the branch holds what Lightning is running, with a commit that says who asked for it.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main" and verified
    And I am an editor on the project
    When I click "Initiate Sync to Branch" on the "Sync to GitHub" tab
    Then I see "GitHub sync initiated"
    And "openfn-pull.yml" is dispatched on the repository's default branch with branch "main"
    And the commit message is "user <my email> initiated a sync from Lightning"
    When the pull Action requests the project with the repository secret
    Then it receives the spec of project "Malawi HIV"
    # github_sync_component.ex:81-83, :296-306; version_control.ex:178-215; pull.yml:1-38
    # provisioning_controller.ex:131-148, :187-205; provisioning_controller_test.exs:808-838

  @S02 @pending
  Scenario: An editor saves and syncs a workflow from the editor with their own message
    # Value: a change is versioned in GitHub at the moment it is made, with a message that explains it.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main"
    And I am an editor with unsaved changes to workflow "Intake"
    When I choose "Save & Sync" from the save button menu
    Then I see "Save and sync changes to GitHub" with "Repository: amara/hiv-sync" and "Branch: main"
    And "Commit message" is prefilled with "<my email> initiated a sync from Lightning"
    When I replace the message with "Add HIV intake mapping" and click "Save & Sync"
    Then workflow "Intake" is saved
    And other people with "Intake" open see it as saved
    And "openfn-pull.yml" is dispatched with commit message "Add HIV intake mapping"
    And I see "Workflow saved and synced to GitHub" with a link to the repository's GitHub actions
    # Header.tsx:144-191; GitHubSyncModal.tsx:49-71, :114-147, :178-192; useWorkflow.tsx:602-714
    # createWorkflowStore.ts:1728-1771; workflow_channel.ex:527-547, :886-906
    # GitHubSyncModal.test.tsx:253-273, :491-541, :593-637

  @S03 @pending
  Scenario: A sync publishes only saved, current workflows
    # Value: drafts nobody saved, and workflows already deleted, never land in the repository as if they were live.
    Given project "Malawi HIV" has workflows "Intake" and "Referral", and a deleted workflow "Old"
    And "Referral" has unsaved changes in someone's editor
    When an editor starts a sync from the settings tab
    Then the dispatch lists the current snapshots of "Intake" and "Referral" only
    And the spec the pull Action receives has the saved version of "Referral"
    # version_control.ex:220-231, :249-255; pull.yml:19-21, :38; provisioning_controller.ex:142-143
    # provisioning_controller_test.exs:840-922

  @S04 @pending
  Scenario: A commit to the branch deploys into the project and is attributed to GitHub
    # Value: changes reviewed and merged in GitHub reach Lightning without manual copying, and the audit trail shows where they came from.
    Given project "Malawi HIV" is connected to "amara/hiv-sync" branch "main"
    When a commit that renames workflow "Intake" to "HIV intake" is pushed to "main"
    And the deploy Action posts the spec with the repository secret
    Then the project's workflow list shows "HIV intake"
    And the audit trail shows the change by "GitHub"
    And a new version of the workflow is recorded
    # deploy.yml:1-19; provisioning_controller.ex:62-80; provisioner.ex:97-137, :330-417, :384-402, :468-499
    # auditing.ex:47-58; provisioning_controller_test.exs:1286-1304

  @S05 @pending
  Scenario: Configuring an export connection never deploys the branch over the project
    # Value: connecting a project to a branch that already holds files does not overwrite the project with them.
    Given I connect project "Malawi HIV" with "OpenFn --> GitHub: Export to GitHub (default, non-destructive)"
    Then the commits that add the OpenFn workflow files are marked "[skip actions]"
    And the project's workflows are unchanged until a later commit to the branch
    # version_control.ex:602-605, :650, :823-842; deploy.yml:1-4

  @S06 @pending @variant:import-direction
  Scenario: Connecting in import mode deploys the branch into the project
    # Value: a team whose project already lives in a repo gets it into Lightning without exporting over it first.
    Given I connect project "Malawi HIV" with "GitHub --> OpenFn: Import from GitHub (overwrite this project)" and config path "./config.json"
    Then the "Configure OpenFn" commit to the branch is not marked "[skip actions]"
    And no pull Action is dispatched
    And the deploy Action posts the branch's spec into project "Malawi HIV"
    # version_control.ex:602-605, :836-840; deploy.yml:1-19; project-settings-github-sync S02

  @S07 @pending
  Scenario: A repository secret only reaches its own project
    # Value: a leaked or misconfigured secret in one repository can't read or overwrite another project, or create a new one.
    Given repository "amara/tb-sync" holds the secret of project "Malawi TB"
    When it requests or posts the spec of project "Malawi HIV"
    Then it is refused with "Forbidden"
    And project "Malawi HIV" is unchanged
    When it posts a spec with no project id
    Then it is refused and no project is created
    # policies/provisioning.ex:38-40, :59-69; scope.ex:122-129, :156-160; provisioning_controller.ex:207-213
    # provisioning_controller_test.exs:924-944, :1022-1040

  @S08 @pending
  Scenario: Removing the connection cuts GitHub's access to the project
    # Value: an admin can stop a repository writing to a project even when the secret could not be deleted from GitHub.
    Given project "Malawi HIV" was connected and its secret is still in "amara/hiv-sync"
    When an admin removes the integration
    And the deploy Action later posts a spec with that secret
    Then it is refused as unauthorized
    # user_auth.ex:241-266, :357-367; version_control.ex:138-155, :162-164

  @S09 @pending
  Scenario: A deploy can't revive a project scheduled for deletion
    # Value: a push to the branch doesn't quietly turn back on triggers that shutting the project down disabled.
    Given project "Malawi HIV" is scheduled for deletion and its triggers are disabled
    When the deploy Action posts a spec that enables a trigger
    Then it is refused
    And the trigger stays disabled
    And the pull Action is refused the project's spec
    # scope.ex:150-153; policies/provisioning.ex:59-69; provisioning_controller_test.exs:1536-1660

  @S10 @pending @variant:github-sync-limited
  Scenario: A plan limit on GitHub sync stops a deploy and says why
    # Value: a project over its plan isn't changed from GitHub, and the Action log carries the reason.
    Given the usage limiter refuses GitHub sync for project "Malawi HIV" with "Upgrade to use Github Sync"
    When the deploy Action posts a spec with the repository secret
    Then it receives 403 with error "Upgrade to use Github Sync"
    And the project is unchanged
    # provisioner.ex:97-99, :1091-1095; provisioning_controller.ex:87-97; provisioning_controller_test.exs:1042-1070

  @S11 @pending @variant:github-sync-limited
  Scenario: A plan limit on GitHub sync disables Save & Sync in the editor
    # Value: an editor learns sync is unavailable before writing a commit message, and a stale page still can't dispatch.
    Given the usage limiter refuses GitHub sync for project "Malawi HIV" with "GitHub Sync is not enabled for your plan."
    And I am an editor with workflow "Intake" open
    Then "Save & Sync" is disabled with that message as its tooltip
    And Ctrl+Shift+S does not open the sync dialog
    When a "save_and_sync" request reaches the server anyway
    Then I see "GitHub Sync is not enabled for your plan."
    And nothing is dispatched to GitHub
    # Header.tsx:166-191, :299-303, :635-643; workflow_channel.ex:2425-2427, :2439-2442, :1688-1694
    # workflow_channel_test.exs:4260-4294

  @S12 @pending
  Scenario: Viewers can't save and sync from the editor
    # Value: read-only members can't change a workflow or push the project out.
    Given project "Malawi HIV" is connected
    And I am a viewer with workflow "Intake" open
    Then "Save & Sync" is disabled with "You do not have permission to edit this workflow"
    When a "save_and_sync" request reaches the server anyway
    Then it is refused with "You don't have permission to edit this workflow"
    And nothing is saved or dispatched
    # useWorkflow.tsx:906-909; Header.tsx:144-191; workflow_channel.ex:527-546, :1950-1977
    # workflow_channel_test.exs:4201-4234; Header.keyboard.test.tsx (no edit permission)

  @S13 @pending
  Scenario: Without a connection the editor offers only Save
    # Value: nobody writes a commit message for a sync that has nowhere to go.
    Given project "Malawi HIV" has no GitHub connection
    When I open workflow "Intake" as an editor
    Then I see "Save" with no sync options menu
    And Ctrl+Shift+S does nothing
    When a "save_and_sync" request reaches the server anyway
    Then I see "No GitHub connection configured for this project"
    # Header.tsx:90-128, :635-643; workflow_channel.ex:536-537, :909-921; workflow_channel_test.exs:4176-4199

  @S14 @pending
  Scenario: The commit message can't be blank
    # Value: every commit Lightning asks GitHub to make says something about the change.
    Given I have the "Save and sync changes to GitHub" dialog open
    When I clear "Commit message" or leave only spaces
    Then "Save & Sync" is disabled
    And Ctrl+Enter does nothing
    # GitHubSyncModal.tsx:56-59, :73-78, :181; workflow_channel.ex:516-525
    # GitHubSyncModal.test.tsx:442-489, :785-811; workflow_channel_test.exs:4130-4139

  @S15 @pending
  Scenario: Colliding names stop an editor sync before anything reaches GitHub
    # Value: a sync never silently drops one of two workflows whose names map to the same key, and the editor knows which to rename.
    Given project "Malawi HIV" is connected
    And it has workflows "My Flow" and "My-Flow"
    When I save and sync workflow "Intake"
    Then I see an error naming "My Flow" and "My-Flow"
    And nothing is dispatched to GitHub
    # version_control.ex:183-191; workflow_channel.ex:924-936; workflow_channel_test.exs:4296-4325
    # settings-tab equivalent: project-settings-github-sync S29

  @S16 @pending
  Scenario: A deploy that removes a workflow closes it for anyone who has it open
    # Value: nobody keeps editing a workflow that GitHub has just removed from the project.
    Given amara has workflow "Old" open in the editor
    When a commit that deletes "Old" is deployed into the project
    Then the flow "flow-delete-open-workflow" receives "WorkflowDeleted" for "Old"
    And amara lands on the workflow list with "Workflow deleted."
    # provisioner.ex:132-134, :908-925; projects/events.ex:123-131; hooks.ex:320-341; workflow_channel.ex:1085-1090

  @S17 @pending
  Scenario: The sync dialog links to the connection settings
    # Value: someone who notices they are about to sync to the wrong branch can fix it from where they noticed.
    Given I have the "Save and sync changes to GitHub" dialog open
    When I click "Modify connection"
    Then I am on the project's "Sync to GitHub" settings tab
    # GitHubSyncModal.tsx:135-145; GitHubSyncModal.test.tsx:416-439; project-settings-github-sync url_params
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Save & Sync saves first and only then dispatches; when the dispatch fails (limit, collision, GitHub error, connection removed) the save has already committed, but the reply is an error, `workflow_saved` is not broadcast, and the client does not update its base workflow or lock version. Read, not run | `workflow_channel.ex:534-546`, `:886-942`; `useWorkflow.tsx:609-619`, `:656-690` | "Failed to save and sync workflow" (or a limit/collision message) with Retry, although the workflow was saved; collaborators' latest-version marker and the change indicator stay stale | fix |
| The success toast says "Workflow saved and synced to GitHub" and "Changes pushed to <repo>" when GitHub has only accepted a dispatch; the Action can still fail (for example at a limit or a refused deploy) | `useWorkflow.tsx:626-652`; `version_control.ex:199-215` | a success message for a commit that may never happen | fix |
| GitHub errors on the editor path (`{:error, %Tesla.Env{}}` from a non-204 dispatch, `%GithubError{}` from the installation client) fall to the catch-all; the settings tab shows GitHub's own message for the same failure | `workflow_channel.ex:1706-1714`; `github_client.ex:212-220`; compare `github_sync_component.ex:216-246` | "An internal error occurred" instead of, for example, "GitHub Error: Resource not accessible by integration" | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A deploy does not reconcile open collaborative editors; an editor open on a deployed workflow keeps its pre-deploy Y.Doc. The provisioner documents this as deliberate | `provisioning_controller.ex:71-75`; `provisioner.ex:62-71`, `:146-150` | decide |
| The editor path authorizes `:edit_workflow`, the settings tab `:initiate_github_sync`; both resolve to editor and above today | `workflow_channel.ex:528`, `:1950-1956`; `github_sync_component.ex:82`; `project_users.ex:39-49` | decide |
| Three default commit messages: editor "<email> initiated a sync from Lightning", settings tab "user <email> initiated a sync from Lightning", first sync on connect the bare email | `GitHubSyncModal.tsx:52`; `github_sync_component.ex:298`; `version_control.ex:837` | decide |
| `WorkflowUpdated` is broadcast on `workflow_events:<project_id>` for every deployed workflow, but nothing in `lib/` subscribes to that topic | `provisioner.ex:130`; `workflows/events.ex:9-29` | decide |
| `WorkflowUpdated` and `WorkflowDeleted` are broadcast inside the import transaction, before commit | `provisioner.ex:97-137` | decide |
| The repo connection token carries no expiry; it lasts as long as the connection row | `project_repo_connection.ex:46-65`; `user_auth.ex:263-266` | decide |
| The usage limit is checked at dispatch and deploy but not on `GET /api/provision`, so a run dispatched by hand in GitHub still reads the spec while the limit applies | `provisioning_controller.ex:131-148`, `:187-205`; `provisioner.ex:1091-1095` | decide |
| A deploy from a repo connection never attaches project credentials named in the spec | `provisioner.ex:942-944` | decide |
| Every connected project in one repository shares the `openfn-deployment` concurrency group, so deploys of different projects queue behind each other | `deploy.yml:6-8` | decide |
| `pull.yml` runs from the repository's default branch, not the connected branch | `version_control.ex:192-201`, `:623-660` | preserve |
| `GET /api/provision/:id` records workflow versions for workflows without one, so the pull is a read that writes | `provisioning_controller.ex:141`, `:150-157` | preserve |
| The `show_yaml` docs name `/api/provision/:id.yaml`; the route is `/api/provision/yaml?id=` | `provisioning_controller.ex:12`, `:182`; `router.ex:114` | preserve |
| The sync pre-flight always exports the v1 format, whatever `sync_version` says | `version_control.ex:183-191`, `:236-246` | decide |
| "Save & Sync" uses an ampersand and title case; "Saving..." while in flight | `Header.tsx:188`; `GitHubSyncModal.tsx:191` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_in("save_and_sync")` clause for a payload with no `commit_message` | `workflow_channel.ex:516-525` | the store always sends `commit_message` (`createWorkflowStore.ts:1745-1752`), and the dialog won't submit a blank one; reachable only by a hand-built channel message |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The editor waits up to 75 s for the combined save, export pre-flight and dispatch | `createWorkflowStore.ts:157`, `:1757-1762` | yes, "Saving..." for that long before a timeout error | preserve |
| Each sync runs a full export as a pre-flight and throws it away (owned by project-settings-github-sync 6.4) | `version_control.ex:166-191` | no | preserve |
| Snapshot ids for every workflow in the project go into one workflow_dispatch input | `version_control.ex:249-255`; `pull.yml:19-21` | not known; GitHub input size limits not checked | decide |

### 6.5 Things seen but not understood

- What `openfn/cli-pull-action@v1` and `openfn/cli-deploy-action@v1` actually call is outside this repository. The endpoints above are inferred from the provisioning controller and from its tests that use a repo connection token (`provisioning_controller_test.exs:808-944`, `:1286-1304`).
- Whether the pull Action's own commit to the branch triggers `deploy.yml` depends on how that Action pushes (GitHub does not start workflows for pushes made with `GITHUB_TOKEN`). If it does, every sync deploys straight back into the project.
- `useWorkflow.tsx:621-624` says Save & Sync is unavailable while a workflow is still new, but `Header.tsx:889-899` renders the split button with the label "Create" whenever a connection exists. Which holds was not traced.
- What a later save from an editor that was open during a deploy does to the deployed change (overwrite, or a lock-version conflict) was not traced.
- Under sync-v2 the Actions read `openfn.yaml`; how the CLI Actions treat the v2 format was not followed.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should Save & Sync save and dispatch as one unit, or report "saved, but the sync failed" when only the dispatch fails (6.1)?
- Should Lightning learn the outcome of the Actions run (for example by polling the run, or from the deploy's POST) instead of reporting success at dispatch?
- Should a deploy from GitHub reconcile open editors (6.2)? (owner: product)
- Should repo connection tokens expire or rotate, and should the read endpoint respect the GitHub sync limit?

## Proposed flows

none

## Proposed shared

none

## Summary

- 17 scenarios (S01 to S17), all `@pending`.
- Section 6: 6.1 three, 6.2 fourteen, 6.3 one, 6.4 three, 6.5 five.
- Flows referenced: flow-delete-open-workflow (receiving end of a deployed workflow deletion); none proposed.
- Shared referenced: shared-authenticated-session, shared-project-scope; none proposed.
- Unsure: the CLI Actions' exact calls and whether the pull commit triggers a deploy are outside the repo; the controller ids `controller:workflow-channel-save-and-sync`, `controller:api-provision-show` and `controller:api-provision-create` are new names.
