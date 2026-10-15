---
id: shared-project-scope
type: shared
title: Project scope gate (login, MFA, membership, live revocation)
status: not-started
owner:

trigger:
  old_route: any live route under /projects/:project_id that mounts {LightningWeb.Hooks, :project_scope}
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the LiveView declares `on_mount {LightningWeb.Hooks, :project_scope}`

inherits: []

url_params:
  - name: project_id
    set_by: every project link
    effect: selects the project; unknown, deleted or inaccessible ids redirect to /projects with a Not Found screen

config_variants:
  default: {}
  experimental-features: { user.preferences.experimental_features: true }

inventory:
  routes: []
  events: []
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers.permitted?(:access_project)
    - Lightning.Policies.ProjectUsers.blocked_by_mfa?/1
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here: []

related:
  - lib/lightning_web/init_assigns.ex
  - lib/lightning_web/hooks.ex
flows: []
---

## 1. Purpose

Every project page has to answer the same question before it renders anything: is this person
allowed in, right now? This gate keeps project data away from people who are not on the project,
sends MFA-required members to enrol instead of leaking a 404, and makes sure that a revoked or
changed membership takes effect on pages people already have open.

## 2. What it does

- **Let the right people in**
  - Signed-out visitors are sent to log in; members of the project get in
  - Members who haven't met the project's MFA requirement are sent to set up MFA
  - Non-members, and visitors to deleted or unknown projects, are sent to the projects list with a Not Found screen
- **Keep open pages in step**
  - Open pages re-check access when the viewer's own membership or support access changes
  - Open pages leave the project when it is scheduled for deletion
  - An open workflow page leaves when that workflow is deleted

**Straightforwardness: 3 of 5.** The gate itself is what you'd expect; the surprises are in who counts as "on the project" and in how open pages react when something changes elsewhere.

### Most surprising behaviours

- **(3)** Superusers who aren't members get "Not Found", even though they can manage the same project from the admin pages. (6.1)
- **(3)** Support users get in without being members whenever the project has support access turned on, and are thrown out the moment it's turned off. (S06, S09)
- **(3)** Any change to your own membership reloads your open page, even being given more access, and if the page hasn't fully settled it may drop you on the workflow list instead. (6.2)
- **(3)** When a sandbox is archived, people editing in it land on the matching workflow in the parent project, but only if they have experimental features on; everyone else just sees "Project deleted." (S11, 6.2)
- **(4)** Even the owner gets "Not Found" once a project is scheduled for deletion, so it looks gone days before it actually is. (S04)

## 3. Who can do what

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Mount a project-scoped page | yes | yes | yes | yes | no | yes, when project support access is on |

Source: `lib/lightning/policies/project_users.ex:136` and `:193` (standing is a role or support access).

**Preconditions beyond role**
- Session token must resolve and the user must not be locked out pending email confirmation (`lib/lightning_web/init_assigns.ex:17-33`).
- Project must exist and not be scheduled for deletion (`lib/lightning/projects/scope.ex:112-117`).
- If the project requires MFA, the user must be enrolled (`project_users.ex:134`, `:186-188`).

## 4. What it touches

**Reads**: `users`, `user_tokens`, `projects`, `project_users`

**Writes**: none

**Immediate side effects**
- Subscribes the socket to the project's event topic (`hooks.ex:276`)

**Deferred side effects**
- Reacts to `ProjectUserAdded`, `ProjectUserRemoved`, `ProjectUserRoleChanged`, `SupportAccessUpdated`, `ProjectDeletionScheduled`, `WorkflowDeleted` (`hooks.ex:248-376`)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Project scope gate
  In order to keep project data limited to the people on the project
  As any user
  I want project pages to admit me only while I have access

  @S01 @pending
  Scenario: Signed-out visitor is sent to log in
    # Value: project data is never rendered to an anonymous browser.
    Given I am not logged in
    When I visit "/projects/<project_id>/w"
    Then I am on "/users/log_in"
    # lib/lightning_web/init_assigns.ex:22-23, lib/lightning_web/hooks.ex:64-72

  @S02 @pending
  Scenario: Member opens a project page
    # Value: people on a project can get to their work.
    Given I am an editor on project "Malawi HIV"
    When I visit the project's workflows page
    Then I see the page for project "Malawi HIV"
    # hooks.ex:102-118

  @S03 @pending
  Scenario: Non-member is told the project was not found
    # Value: outsiders can't see a project's data, or confirm it exists.
    Given I am a registered user not on project "Malawi HIV"
    When I visit the project's workflows page
    Then I am on "/projects"
    And I see "Not Found"
    # hooks.ex:122-124, lib/lightning_web/live/live_helpers.ex:81-86

  @S04 @pending
  Scenario: A project scheduled for deletion is not found
    # Value: a project being wound down can't be worked on.
    Given project "Malawi HIV" is scheduled for deletion
    And I am its owner
    When I visit the project's workflows page
    Then I am on "/projects"
    And I see "Not Found"
    # hooks.ex:127-130, scope.ex:114

  @S05 @pending
  Scenario: Member without MFA on an MFA-required project is sent to enrol
    # Value: sensitive projects are only reachable from MFA-protected accounts, and the member learns why.
    Given project "Malawi HIV" requires MFA
    And I am an editor who has not enrolled in MFA
    When I visit the project's workflows page
    Then I am on "/mfa_required"
    # hooks.ex:100-101, project_users.ex:186-188

  @S06 @pending
  Scenario: Support user reaches a project with support access on
    # Value: support staff can help a customer without being added as a collaborator.
    Given I am a support user with no role on project "Malawi HIV"
    And project "Malawi HIV" has support access enabled
    When I visit the project's workflows page
    Then I see the page for project "Malawi HIV"
    # project_users.ex:167-169, :193-194

  @S07 @pending
  Scenario: Removing a member ends their open session on the project
    # Value: revoking access takes effect immediately, not when the person next reloads.
    Given I have project "Malawi HIV" open as an editor
    When an admin removes me from the project in another session
    Then my page eventually leaves the project
    And I see "Not Found"
    # hooks.ex:361-368 re-mounts via remount_path (hooks.ex:417-421), which re-runs this gate
    # test/lightning_web/live/project_live/membership_revocation_test.exs

  @S08 @pending
  Scenario: A role change takes effect on an open page
    # Value: a demoted user loses edit rights straight away.
    Given I have project "Malawi HIV" open as an admin
    When an owner changes my role to viewer in another session
    Then my page eventually reloads with viewer permissions, keeping its query string
    # hooks.ex:361-368, :417-418

  @S09 @pending
  Scenario: Turning off support access ends a support session
    # Value: a customer can withdraw support access and know it has taken effect.
    Given I am a support user with project "Malawi HIV" open through support access only
    When an owner disables support access
    Then my page eventually leaves the project
    # hooks.ex:349-359, test/lightning_web/live/project_live/support_access_teardown_test.exs

  @S10 @pending
  Scenario: Open pages leave a project scheduled for deletion
    # Value: nobody keeps editing a project that is being deleted.
    Given I have project "Malawi HIV" open
    When an owner schedules the project for deletion
    Then I am eventually on "/projects"
    And I see "Project deleted."
    # hooks.ex:294-318

  @S11 @pending @variant:experimental-features
  Scenario: Archiving a sandbox moves its open editor to the parent workflow
    # Value: someone editing in a sandbox that gets merged and archived lands on the live workflow instead of a dead end.
    Given I have experimental features enabled
    And I have workflow "Intake" open in sandbox "dev" of project "Malawi HIV"
    And project "Malawi HIV" has a workflow named "Intake"
    When sandbox "dev" is scheduled for deletion
    Then I am eventually on the editor for "Intake" in "Malawi HIV" with "archived=1"
    # hooks.ex:296-317, :378-411

  @S12 @pending
  Scenario: Deleting the open workflow returns the viewer to the workflow list
    # Value: nobody edits a workflow that no longer exists.
    Given I have workflow "Intake" open
    When another user deletes "Intake"
    Then I am eventually on the project's workflows page
    And I see "Workflow deleted."
    # hooks.ex:325-335
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Superuser with no membership row is refused by this gate, though the admin projects page lets them manage the project | `project_users.ex:193-194` | "Not Found" on a project they can edit from `/settings/projects` | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Every membership event for the viewer re-mounts, including additions, so a user added to a second role sees a reload | `hooks.ex:248-262` comment | preserve |
| When `current_uri` is not yet set the re-mount falls back to the workflow list instead of the current page | `hooks.ex:417-421` | decide |
| Sandbox archive redirect only applies when the viewer has experimental features on; otherwise they get the generic "Project deleted." | `hooks.ex:295-299` | decide |
| Hook is a no-op when the route has no `project_id`, which `DashboardLive` relies on | `hooks.ex:134-136` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Loads every project the user belongs to on every project-scoped mount (for the picker) | `hooks.ex:83` | no | preserve |

### 6.5 Things seen but not understood

none

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should superusers bypass this gate in the rebuild (see 6.1)?
