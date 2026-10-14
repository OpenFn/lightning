---
id: sandboxes-index
type: view
title: Sandboxes
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/sandboxes (also /new and /:id/edit)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer on :project_id (shared-project-scope; index.ex:27)
    - "/new: viewer may :provision_sandbox on :project_id and the usage limiter allows a new sandbox, otherwise redirected back with a flash (index.ex:69-100)"
    - "/:id/edit: the id is in the viewer's workspace tree and the viewer can manage it (index.ex:46-67)"

inherits:
  - shared-authenticated-session
  - shared-project-scope            # on_mount :project_scope (index.ex:27); access_root and project_label come from it (hooks.ex:104-119); S10 and S11 are the receiving end when a sandbox is deleted or merged here
  - shared-usage-limits-banner      # on_mount :check_limits and the :banner slot (index.ex:28, :556-562)
  - shared-project-header           # breadcrumbs, project picker, side menu with :sandboxes active (index.ex:36, :563-577)
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: project_id
    set_by: side menu, project picker, every redirect on this page
    effect: the project whose workspace is listed; "Create Sandbox" creates under it; marked "active" in the list
  - name: id (on /:id/edit)
    set_by: the edit action on a sandbox card, which puts the sandbox's parent in :project_id (components.ex:835-837)
    effect: opens the edit modal for that sandbox if it is in the viewer's tree and manageable

config_variants:
  default: { max_sandbox_nesting_depth: 5, purge_deleted_after_days: 7, Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # bootstrap.ex:273-278, :372-373; read under this one
  nesting-capped: { max_sandbox_nesting_depth: 1 }   # MAX_SANDBOX_NESTING_DEPTH; index_test.exs:166-187 stubs it
  usage-limited: { Lightning.Extensions.usage_limiter: <adapter returning {:error, _, %{text: _}} for :new_sandbox or provisioning> }   # hosted plans
  purge-immediate: { purge_deleted_after_days: 0 }   # bootstrap.ex:306-316 registers no purge cron
  github-sync: { target project has a project_repo_connection }   # data state, index_test.exs:4750-4885

inventory:
  routes:
    - live /projects/:project_id/sandboxes  SandboxLive.Index :index          # router.ex:317
    - live /projects/:project_id/sandboxes/new  SandboxLive.Index :new        # router.ex:318
    - live /projects/:project_id/sandboxes/:id/edit  SandboxLive.Index :edit  # router.ex:319
  events:
    - SandboxLive.Index#open-delete-modal                 # index.ex:107-127
    - SandboxLive.Index#confirm-delete-validate           # index.ex:130-145
    - SandboxLive.Index#confirm-delete                    # index.ex:148-177
    - SandboxLive.Index#close-delete-modal                # index.ex:180-182
    - SandboxLive.Index#cancel-sandbox-deletion           # index.ex:185-208 (the "Restore" button)
    - SandboxLive.Index#open-merge-modal                  # index.ex:211-290
    - SandboxLive.Index#close-merge-modal                 # index.ex:293-295
    - SandboxLive.Index#toggle-workflow                   # index.ex:298-316
    - SandboxLive.Index#toggle-all-workflows              # index.ex:319-331
    - SandboxLive.Index#toggle-credential                 # index.ex:334-345
    - SandboxLive.Index#toggle-all-credentials            # index.ex:348-359
    - SandboxLive.Index#select-merge-target               # index.ex:362-438
    - SandboxLive.Index#toggle-collection-to-add          # index.ex:441-456
    - SandboxLive.Index#toggle-all-collections-to-add     # index.ex:459-473
    - SandboxLive.Index#confirm-merge                     # index.ex:476-550
    - SandboxLive.FormComponent#close_modal               # form_component.ex:33-35
    - SandboxLive.FormComponent#validate                  # form_component.ex:38-55
    - SandboxLive.FormComponent#save                      # new :58-114, edit :117-150
  js_hooks:
    - CheckboxIndeterminate (assets/js/hooks/index.ts:862; components.ex:352, :429, :474)
    - Tooltip (assets/js/hooks/index.ts:567; components.ex:672, :892)
    - ModalHook (assets/js/hooks/index.ts:522; via the shared <.modal>)
  policies:
    - Lightning.Policies.Sandboxes (:provision_sandbox, :merge_sandbox, :update_sandbox, :delete_sandbox, :cancel_scheduled_deletion; manage_permissions/3) (policies/sandboxes.ex:90-181)
    - Lightning.Projects.Scope.role_in?/3 and fetch/2 (scope.ex:139-147)
    - Lightning.Policies.Credentials :create_keychain_credential (inside merge, sandboxes.ex:619-626)
  workers:
    - Lightning.Projects purge_deleted (Oban cron 45 2 * * *; projects.ex:194-221; bootstrap.ex:311)   # deferred; owned by proposed flow-sandbox-scheduled-deletion
  api_endpoints: []
  emails: []
  config:
    - max_sandbox_nesting_depth (MAX_SANDBOX_NESTING_DEPTH; config.ex:229-230, bootstrap.ex:372-373)
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS; config.ex:80-81, bootstrap.ex:273-278)
    - Lightning.Extensions.usage_limiter (:new_sandbox action; project_limiter.ex:19-24)
    - Lightning.Extensions.project_hook (handle_create_project, projects.ex:564)
  not_reachable_here:
    - Lightning.Projects.Sandboxes.delete_sandbox/2 hard delete (sandboxes.ex:814-827); only the purge worker path deletes immediately
    - Sandboxes.provision/3 :dataclip_ids and :starting_dataclip options (sandboxes.ex:152-160, :170-268); this form never sends them
    - Sandboxes.merge/4 :record_release option (sandboxes.ex:371-385); this page never passes it
    - Sandboxes.update_sandbox/3 :env (documented at sandboxes.ex:723, dropped by Map.take at :752); the form only sends name and colour
    - Projects.update_sandbox/3 and delete_sandbox/2 string-id clauses (sandboxes.ex:759-764, :822-827)

related:
  - project-settings-setup                       # the sandbox's own settings page also deletes a sandbox (its S18 onward)
  - flow-schedule-project-deletion               # root-project deletion; its 6.1 compares the sandbox cascade here
  - flow-delete-open-workflow                    # receiving end when a merge deletes a target workflow (provisioner.ex:134)
  - workflow-editor-versions-and-promote         # promote from the editor is another way into Sandboxes.merge/4
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/projects/merge_projects.ex
  - lib/lightning/policies/sandboxes.ex
flows:
  - flow-sandbox-merge
  - flow-sandbox-scheduled-deletion
  - flow-github-sync-actions           # referenced; sandboxes-index needs adding to its surfaces as a third entry (merge dispatches openfn-pull.yml)
  - flow-edit-in-sandbox
---

## 1. Purpose

People who build workflows use sandboxes to try changes on a copy of a project without touching
the live one, then merge the changes back. This page is where they see every sandbox in their
workspace they belong to, create new ones, rename, delete and restore them, and merge one into
another project. Getting it wrong either breaks production (a merge silently deletes or overwrites
workflows, credentials or collections) or loses work (a sandbox deleted without warning, or one
nobody can restore).

## 2. What it does

- Members see the workspace root and every sandbox they belong to, with the current one marked
- Editors and above create a sandbox under the current project
- Sandbox admins and owners (and workspace root admins and owners) rename and recolour a sandbox
- The same people delete a sandbox, which schedules it and its children for deletion
- The same people restore a sandbox during its grace period
- The same people merge a sandbox into a project where they are an editor or above, choosing which workflows, credentials and collections go across
- Nobody can act on the workspace root itself, or on a sandbox they can't see

## 3. Who can do what

Columns are the viewer's role on the sandbox in the row (for "Create", on the current project).
Sources: `policies/sandboxes.ex:90-181`, `index.ex:677-697`, `:717-738`, `:907-928`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the page | yes | yes | yes | yes | no (project scope gate) | yes, when support access is on |
| See a sandbox in the list | yes | yes | yes | yes | no | yes, when that sandbox allows support access |
| Create a sandbox under the current project | no | yes | yes | yes | no | no |
| Rename or recolour | no | no | yes | yes | no | no |
| Delete (schedule) | no | no | yes | yes | no | no |
| Restore | no | no | yes | yes | no | no |
| Merge, source side | no | no | yes | yes | no | no |
| Merge, target side (role on target) | no | yes | yes | yes | no | no |
| Edit, delete or merge the workspace root | no | no | no | no | no | no |

**Preconditions beyond role**
- Root cascade: an admin or owner on the absolute workspace root may rename, delete, restore and merge any sandbox in it, but only sandboxes they also have a row on are listed (`policies/sandboxes.ex:109-119`, `:157-166`; `projects.ex:1438-1441`).
- A project with no parent is refused for every action except provisioning and merge target (`policies/sandboxes.ex:90-92`, `:160-166`).
- Rename and delete go through `Scope`, so they also require the sandbox's MFA requirement to be met and the sandbox not to be scheduled for deletion (`policies/sandboxes.ex:109-119`; `scope.ex:139-152`). Restore reads roles directly and ignores both (`policies/sandboxes.ex:121-130`).
- Create is refused at the nesting cap (`index.ex:685-687`; `sandboxes.ex:268-271`, `:1015-1017`) and when the usage limiter refuses `:new_sandbox` (`index.ex:37-40`; `form_component.ex:75`).
- Restore is refused when the usage limiter refuses `:new_sandbox` (`sandboxes.ex:923-931`).
- Merge targets offered: projects in the viewer's tree, not the source, not its descendants, not scheduled for deletion, where the viewer's own row is editor or above (`index.ex:907-943`). Confirm re-checks `:merge_sandbox` on the target through `Scope` (MFA included) (`index.ex:514-520`; `policies/sandboxes.ex:98-100`).
- The tree starts at the viewer's access root: the topmost ancestor they belong to, not the absolute root (`hooks.ex:104-105`; `projects.ex:1456-1464`).

## 4. What it touches

**Reads**: `projects` (tree walks by recursive CTE), `project_users`, `workflows`, `workflow_versions`, `project_credentials`, `credentials`, `collections`, `keychain_credentials`, `project_repo_connections`

**Writes**
- Create: `projects`, `project_users`, `project_credentials`, `keychain_credentials`, `workflows`, `jobs`, `triggers` (disabled), `edges`, `workflow_versions`, `collections` (names, empty) (`sandboxes.ex:1009-1051`, `:1265-1267`)
- Rename or recolour: `projects.name`, `projects.color` (`sandboxes.ex:743-757`; `projects.ex:589-617`)
- Delete: `projects.scheduled_deletion` on the whole subtree; `triggers.enabled = false` on the whole subtree (`sandboxes.ex:942-973`)
- Restore: clears `projects.scheduled_deletion` on the subtree; triggers stay disabled (`sandboxes.ex:976-988`)
- Merge: `project_credentials` and `keychain_credentials` on the target, the target's workflows, jobs, triggers, edges and snapshots through the provisioner, `collections` (create only), `workflow_versions` sync points on the source, then the delete writes for the source (`sandboxes.ex:300-363`, `:1463-1475`; `index.ex:1195-1205`)

**Immediate side effects** (in the same request)
- `Events.project_created` after create (`projects.ex:572-574`)
- Project audit events derived from the rename changeset (`projects.ex:597`, `:620-625`)
- `Events.project_deletion_scheduled` for every project in a deleted subtree, after commit (`sandboxes.ex:965-972`); open pages on those projects leave (shared-project-scope S10, S11)
- Provisioner audit and snapshot events, `workflow_updated` and `workflow_deleted` broadcasts on the merge target (`provisioner.ex:130-134`, `:411`, `:493`)
- `WorkflowReconciler.request_reconciliation` for merged workflows, so open editors on the target pick up the merge (`sandboxes.ex:349-355`)
- PromEx telemetry: created, merged, scheduled for deletion, deletion cancelled (`sandboxes.ex:1045`, `:963`, `:986`; `index.ex:1170`)
- Error logs on merge failure and on unexpected create failures (`sandboxes.ex:683-716`; `form_component.ex:95-97`)

**Deferred side effects** (later, elsewhere)
- The nightly purge hard-deletes sandboxes whose `scheduled_deletion` has passed (`projects.ex:194-221`; `bootstrap.ex:311`)

**External, non-transactional effects**
- With GitHub sync on the merge target: two `openfn-pull.yml` dispatches, "pre-merge commit" before the merge and "Merged sandbox <name>" after it (`index.ex:1128-1160`; `version_control.ex:178-215`). The first one fires even if the merge then fails.

**Depends on config**
- `max_sandbox_nesting_depth` (create button and provisioning), `purge_deleted_after_days` (grace period copy and scheduled date; `components.ex:240-246`; `sandboxes.ex:1001-1006`), usage limiter (`:new_sandbox`, and whatever the provisioner checks during merge), project hook on create

**Product limits**
- Sandboxes nest at most `MAX_SANDBOX_NESTING_DEPTH` levels below the root (default 5)
- The number of active sandboxes is capped by the usage limiter on hosted plans; restore counts against it

## 5. Scenarios

```gherkin
Feature: Sandboxes
  In order to try changes safely and bring them back to the live project
  As someone building workflows
  I want to create, manage and merge sandboxes of my project

  @S01 @pending
  Scenario: Members see their workspace with the current project marked
    # Value: people know which sandboxes exist and which one they are in before they act.
    Given I am an owner on project "Malawi HIV" with sandboxes "sb-1" and "sb-2"
    When I open the sandboxes page of "Malawi HIV"
    Then I see a card for "Malawi HIV" with the badges "main" and "active"
    And I see cards for "sb-1" and "sb-2"
    # index.ex:662-709; components.ex:77-123, :608-648; index_test.exs:77-90, :104-113, :152-164

  @S02 @pending
  Scenario: Environment badges tell a sandbox from the live project
    # Value: nobody mistakes a sandbox for production, or production for a sandbox.
    Given project "Malawi HIV" has env "production"
    And it has sandbox "sb-1" with env "staging" and sandbox "sb-2" with no env
    When I open the sandboxes page of "Malawi HIV"
    Then the "Malawi HIV" card shows "production"
    And the "sb-1" card shows "staging"
    And the "sb-2" card shows no environment badge
    # components.ex:625-636, :718-722, :957-961; index_test.exs:115-150

  @S03 @pending
  Scenario: A sandbox I have no membership on is not listed
    # Value: each sandbox's membership decides who sees it, even inside a project someone owns.
    Given I am an owner on project "Malawi HIV"
    And "Malawi HIV" has sandbox "with-me" where I am an owner and sandbox "without-me" where I have no role
    When I open the sandboxes page of "Malawi HIV"
    Then I see "with-me"
    And I do not see "without-me"
    # index.ex:671-675; projects.ex:1438-1441; index_test.exs:830-888

  @S04 @pending
  Scenario: A sandbox-only member does not see the projects above them
    # Value: inviting someone to a sandbox does not reveal the names of projects they were not invited to.
    Given project "Hidden root" has sandbox "team-space", which has sandbox "leaf"
    And I am an admin on "team-space" and "leaf" only
    When I open the sandboxes page of "team-space"
    Then I see "team-space" and "leaf"
    And I do not see "Hidden root"
    # hooks.ex:104-105; projects.ex:1456-1464; index_test.exs:967-995

  @S05 @pending
  Scenario: An empty workspace invites me to create a sandbox
    # Value: new users learn what to do next instead of facing a blank page.
    Given I am an editor on project "Malawi HIV", which has no sandboxes
    When I open the sandboxes page of "Malawi HIV"
    Then I see "No sandboxes found"
    And I see a "Create your first sandbox" link
    # components.ex:98-116; index_test.exs:77-102

  @S06 @pending
  Scenario: Clicking a sandbox opens it
    # Value: one click takes people into the sandbox they want to work in.
    Given project "Malawi HIV" has sandbox "sb-1" that I belong to
    When I click the "sb-1" card
    Then I am on the workflows page of "sb-1"
    # components.ex:698-704; root card components.ex:612; no test

  @S07 @pending
  Scenario: Editor creates a sandbox and lands in it
    # Value: people get a private copy to experiment in without asking an admin.
    Given I am an editor on project "Malawi HIV"
    When I click "Create Sandbox"
    And I enter the name "Test Sandbox" and pick a colour
    Then I see "Your sandbox will be named test-sandbox."
    When I click "Create sandbox"
    Then I am on the workflows page of sandbox "test-sandbox"
    And I see "Sandbox created"
    And sandbox "test-sandbox" has env "dev" and the colour I picked
    # components.ex:55-69; form_component.ex:58-80, :221-242, :314-321; index_test.exs:296-307, :3393-3420; form_component_test.exs:54-79

  @S08 @pending
  Scenario: A new sandbox brings the team along, with the creator in charge
    # Value: collaborators can keep working in the sandbox straight away, and the person who made it can manage it.
    Given "owner@example.org" is the owner, I am an admin and "ed@example.org" is an editor on project "Malawi HIV"
    When I create sandbox "admin-test-sandbox"
    Then on "admin-test-sandbox" I am an owner, "owner@example.org" is an admin and "ed@example.org" is an editor
    # sandboxes.ex:1065-1084; index_test.exs:3466-3606

  @S09 @pending
  Scenario: A new sandbox keeps the parent's support access setting
    # Value: a support consent decision (or refusal) on a project also holds for its copies.
    Given project "Malawi HIV" allows support access
    When I create sandbox "test-sandbox"
    Then "test-sandbox" allows support access
    # sandboxes.ex:104-107, :1076-1077; index_test.exs:3393-3465

  @S10 @pending
  Scenario: A new sandbox copies workflows with their triggers off
    # Value: experimenting in a sandbox never fires production webhooks or schedules twice.
    Given project "Malawi HIV" has workflow "Intake" with an enabled cron trigger
    When I create sandbox "test-sandbox"
    Then "test-sandbox" has a workflow "Intake"
    And its trigger is disabled
    # sandboxes.ex:1036, :1265-1267; read from code, no LiveView test asserts it

  @S11 @pending
  Scenario: A sandbox name already used under the same parent is refused
    # Value: sibling sandboxes stay distinguishable in lists, URLs and merges.
    Given project "Malawi HIV" has sandbox "test-sandbox"
    When I start creating a sandbox and type "Test Sandbox"
    Then I see "Sandbox name already exists"
    # form_component.ex:288-312; projects.ex:2225-2240; form_component_test.exs:81-107, :162-203

  @S12 @pending
  Scenario: A blank name cannot be submitted
    # Value: every sandbox has a usable name.
    When I start creating a sandbox and clear the name
    Then I see "can't be blank" once
    And the "Create sandbox" button is disabled
    # form_component.ex:249-256; project.ex:155-157; form_component_test.exs:109-128

  @S13 @pending
  Scenario: A viewer cannot create a sandbox
    # Value: only people trusted to change workflows can spin up copies of the project and its credentials.
    Given I am a viewer on project "Malawi HIV"
    When I open the sandboxes page of "Malawi HIV"
    Then the "Create Sandbox" button is disabled with "You are not authorized to create sandboxes in this workspace"
    When I go to "/projects/<Malawi HIV>/sandboxes/new"
    Then I am on the sandboxes page of "Malawi HIV"
    And I see "You are not authorized to create sandboxes in this workspace"
    # index.ex:81-92, :1207-1214; index_test.exs:796-812

  @S14 @pending @variant:usage-limited
  Scenario: The plan's sandbox limit blocks creating one
    # Value: people see why they can't create a sandbox before they fill in the form.
    Given the usage limiter refuses a new sandbox on "Malawi HIV" with "Sandbox limit reached"
    When I open the sandboxes page of "Malawi HIV"
    Then the "Create Sandbox" button is disabled and I see "Sandbox limit reached"
    When I go to "/projects/<Malawi HIV>/sandboxes/new"
    Then I am on the sandboxes page of "Malawi HIV" with the error "Sandbox limit reached"
    # index.ex:94-97, :1219-1220; form_component.ex:75, :108-112; index_test.exs:206-261; form_component_test.exs:130-160

  @S15 @pending @variant:nesting-capped
  Scenario: The create button is off at the nesting limit
    # Value: workspaces stay shallow enough to understand and merge.
    Given the maximum sandbox nesting depth is 1
    And I own sandbox "deep-sb-1" under project "deep-root"
    When I open the sandboxes page of "deep-sb-1"
    Then the "Create Sandbox" button is disabled
    And I see "Maximum sandbox nesting depth reached"
    # index.ex:685-687, :1216-1217; index_test.exs:166-204

  @S16 @pending
  Scenario: Admin renames a sandbox
    # Value: sandboxes can be renamed as their purpose changes, without recreating them.
    Given I am an admin on sandbox "sb-1" of project "Malawi HIV"
    When I click the edit action on "sb-1"
    Then I see "Edit sandbox" with the current colour selected
    When I change the name to "sb-2" and click "Save changes"
    Then I am on the sandboxes page
    And I see "Sandbox updated"
    # components.ex:821-849; form_component.ex:116-136, :277-282; index_test.exs:309-321; form_component_test.exs:316-340, :362-381

  @S17 @pending
  Scenario: Renaming to a sibling's name is refused, keeping the same name is fine
    # Value: a rename can't make two sandboxes indistinguishable.
    Given project "Malawi HIV" has sandboxes "sb-1" and "sb-2"
    When I edit "sb-1" and type "sb-2"
    Then I see "Sandbox name already exists"
    When I type "sb-1"
    Then I see no name error
    # form_component.ex:295-312; form_component_test.exs:384-431

  @S18 @pending
  Scenario: Non-admins see the sandbox actions disabled
    # Value: people can tell what they are not allowed to do instead of clicking and failing.
    Given I am a viewer on project "Malawi HIV" and on its sandbox "test-sandbox"
    When I open the sandboxes page of "Malawi HIV"
    Then the merge, edit and delete actions on "test-sandbox" are disabled
    And their tooltips say "You are not authorized to merge this sandbox", "You are not authorized to edit this sandbox" and "You are not authorized to delete this sandbox"
    # components.ex:791-879; index.ex:717-738; index_test.exs:691-744, :2807-2824, :3089-3113

  @S19 @pending
  Scenario: A non-admin following an edit link is sent back
    # Value: a shared or bookmarked edit link can't be used to change a sandbox.
    Given I am a viewer on project "Malawi HIV" and on its sandbox "test-sandbox"
    When I go to "/projects/<Malawi HIV>/sandboxes/<test-sandbox>/edit"
    Then I am on the sandboxes page of "Malawi HIV"
    And I see "You are not authorized to edit this sandbox"
    # index.ex:57-65; index_test.exs:778-794

  @S20 @pending
  Scenario: The workspace root can't be edited, deleted or merged from here
    # Value: the live project can't be renamed, deleted or merged away through sandbox controls, even by its admins.
    Given I am an admin on project "workspace-root" with an enabled trigger
    When I open the sandboxes page of "workspace-root"
    Then the "workspace-root" card has no edit, delete or merge actions
    And a delete or merge request for "workspace-root" says "You are not authorized to delete this sandbox" or "You are not authorized to merge this sandbox"
    And "workspace-root" is not scheduled for deletion and its trigger is still enabled
    # components.ex:89-96, :608-648; policies/sandboxes.ex:90-92, :160-166; index_test.exs:926-965

  @S21 @pending
  Scenario: Requests for a sandbox I can't see are refused
    # Value: hidden sandboxes can't be deleted, restored or merged by guessing their id.
    Given project "Malawi HIV" has sandbox "hidden-sandbox" where I have no role
    When a delete, restore or merge request for "hidden-sandbox" reaches the page
    Then I see "Sandbox not found"
    And no modal opens
    # index.ex:107-110, :190-192, :212-214, :53-55; index_test.exs:890-924

  @S22 @pending
  Scenario: Admin deletes a sandbox by typing its name
    # Value: a sandbox goes away only when someone deliberately confirms which one.
    Given I am an owner on project "Malawi HIV" and its sandbox "sb-1"
    When I click the delete action on "sb-1"
    Then I see "Delete sandbox" and "To confirm, type the sandbox name below."
    When I type "sb-1" and click "Delete sandbox"
    Then I see "Sandbox sb-1 scheduled for deletion."
    And "sb-1" is listed under "Scheduled for deletion" with a "Restore" button
    # index.ex:107-177, :828-855; components.ex:143-238, :125-132; index_test.exs:413-449, :1062-1099, :1167-1191

  @S23 @pending
  Scenario: A mistyped name keeps the delete button off
    # Value: a slip of the keyboard can't delete the wrong sandbox.
    Given the delete modal is open for "sb-1"
    When I type "wrong"
    Then the "Delete sandbox" button is disabled with "Type the sandbox name to enable"
    # index.ex:811-822; components.ex:217-225; index_test.exs:323-348, :559-587

  @S24 @pending
  Scenario: The delete modal says how many child sandboxes go with it
    # Value: nobody deletes more than they were told, including children they can't see.
    Given sandbox "sb-1" has three active child sandboxes and one already scheduled for deletion
    When I open the delete modal for "sb-1"
    Then I see "Its 3 child sandboxes will also be deleted."
    # index.ex:711-715 (counts every active descendant, visible or not); components.ex:174-182; index_test.exs:350-411

  @S25 @pending
  Scenario: The delete modal states the grace period
    # Value: people know a mistaken delete can still be undone, and for how long.
    Given sandboxes are kept for 7 days after deletion
    When I open the delete modal for "sb-1"
    Then I see "This sandbox will be retained for 7 days before being permanently removed."
    # components.ex:197-201, :240-246; index_test.exs:589-616

  @S26 @pending
  Scenario: Deleting a sandbox stops its work and its children's
    # Value: a sandbox someone has decided to remove stops running jobs immediately, not after the grace period.
    Given sandbox "sb-1" has child sandbox "child" and both have enabled triggers
    When I delete "sb-1"
    Then "sb-1" and "child" are scheduled for deletion with the same date
    And every trigger in "sb-1" and "child" is disabled
    And the flow "flow-sandbox-scheduled-deletion" has started for "sb-1"
    # sandboxes.ex:942-973; read from code, no LiveView test asserts triggers

  @S27 @pending
  Scenario: Deleting the sandbox I'm in sends me to its parent
    # Value: nobody is left on a page for a sandbox that is going away.
    Given I am on the sandboxes page of "grandchild", a child of "child-sandbox" under "parent"
    And the delete modal warns "You are currently viewing this project" when I open it for my current project
    When I delete "child-sandbox"
    Then I am on the sandboxes page of "parent"
    # index.ex:828-855; components.ex:188-191; index_test.exs:263-294, :1027-1060, :1101-1144

  @S28 @pending
  Scenario: A scheduled sandbox shows when it will be removed
    # Value: people know how long they have to change their mind.
    Given sandbox "later" is scheduled for deletion in 5 days
    When I open the sandboxes page
    Then "later" is struck through and can't be opened
    And hovering it shows "Scheduled for deletion on <date> (in 5 days). Cancel the deletion to restore it."
    # components.ex:652-696, :963-977; index_test.exs:1167-1191, :1401-1510

  @S29 @pending
  Scenario: Admin restores a scheduled sandbox
    # Value: a mistaken delete is undone in one click during the grace period.
    Given sandbox "scheduled" is scheduled for deletion and I am its owner
    When I click "Restore" on "scheduled"
    Then I see "Cancelled deletion of sandbox scheduled."
    And "scheduled" is back in the active list with its actions
    # index.ex:185-208, :878-885; sandboxes.ex:923-931, :976-988; index_test.exs:1255-1267

  @S30 @pending
  Scenario: A viewer can't restore a scheduled sandbox
    # Value: only people allowed to delete a sandbox can bring it back.
    Given sandbox "scheduled" is scheduled for deletion and I am a viewer on it
    When I open the sandboxes page
    Then the "Restore" button on "scheduled" is disabled with "You are not authorized to cancel deletion of this sandbox"
    # components.ex:753-789; index_test.exs:1269-1302

  @S31 @pending @variant:usage-limited
  Scenario: The sandbox limit blocks restoring
    # Value: restoring can't be used to get past the plan's sandbox limit.
    Given the usage limiter refuses a new sandbox with "stub-blocked-message"
    And sandbox "scheduled" is scheduled for deletion
    When I open the sandboxes page
    Then the "Restore" button on "scheduled" is disabled and I see "stub-blocked-message"
    # index.ex:726-743; components.ex:763-764; sandboxes.ex:925-928; index_test.exs:1357-1399

  @S32 @pending
  Scenario: Admin merges a sandbox into its parent
    # Value: work done safely in a sandbox reaches the live project in one step.
    Given I am an owner on project "parent" and its sandbox "test-sandbox"
    When I click the merge action on "test-sandbox"
    Then the merge target is "parent"
    When I click "Merge"
    Then I am on the workflows page of "parent"
    And I see "Successfully merged test-sandbox into parent. Sandbox scheduled for deletion."
    And the flow "flow-sandbox-merge" has started for "test-sandbox" into "parent"
    # index.ex:211-290, :476-550, :1162-1205; index_test.exs:1611-1628, :1801-1855, :2891-2932

  @S33 @pending
  Scenario: Merge targets are limited to projects I can change
    # Value: a merge can only land where the person merging is already trusted to edit.
    Given "child1" is a sandbox of "root" with children "grandchild1" and "grandchild2"
    And "root" has sandboxes "child2", "child3", "viewer-only" where I am a viewer, and "retiring" scheduled for deletion
    When I open the merge modal for "child1"
    Then the target options are "root", "child2" and "child3"
    # index.ex:907-943; index_test.exs:1586-1609, :1923-1974, :3173-3261

  @S34 @pending
  Scenario: A target I wasn't offered is refused at merge time
    # Value: a crafted request can't merge into a project the screen withheld.
    Given the merge modal is open for "test-sandbox"
    When a merge request names "retiring", "test-sandbox" itself, or an unknown project
    Then I see "Target project not found"
    When a merge request names "restricted-target" where I am a viewer
    Then I see "You are not authorized to merge into this project"
    And nothing is merged
    # index.ex:500-547; index_test.exs:1998-2019, :3129-3171, :4127-4181

  @S35 @pending
  Scenario: Changed and new workflows are preselected, unchanged ones are not
    # Value: a merge brings across what was worked on and leaves the rest of the live project alone.
    Given "parent" and "test-sandbox" both have "Unchanged" at the same version
    And "test-sandbox" has a changed "Changed" and a new "Beta"
    When I open the merge modal for "test-sandbox"
    Then "Changed" is checked and labelled "Changed"
    And "Beta" is checked and labelled "New"
    And "Unchanged" is not checked
    # index.ex:249-263, :971-1032; components.ex:343-415; index_test.exs:3856-3950, :4275-4312

  @S36 @pending
  Scenario: Workflows changed in the target since the fork are flagged
    # Value: people see which live changes a merge would overwrite before they lose them.
    Given "Test Workflow" was changed in both "parent" and "test-sandbox" since the fork
    When I open the merge modal for "test-sandbox"
    Then "Test Workflow" is labelled "Diverged"
    And I see "Any conflicting changes in the target are lost."
    # index.ex:247, :1101-1105; merge_projects.ex:1067-1092; components.ex:337-340, :391-398; index_test.exs:3263-3297, :3627-3726

  @S37 @pending
  Scenario: Deleting a workflow from the target is opt-in
    # Value: a merge never silently deletes a live workflow.
    Given "Gamma" existed in "parent" before "test-sandbox" was created and is not in "test-sandbox"
    When I open the merge modal for "test-sandbox"
    Then "Gamma" is listed as "Deleted in sandbox" and not checked
    When I merge without checking it
    Then "Gamma" still exists in "parent"
    When instead I check "Gamma" and merge
    Then "Gamma" is deleted from "parent"
    # index.ex:1008-1028, :1042-1064; index_test.exs:3952-3992, :4183-4237

  @S38 @pending
  Scenario: Workflows added to the target after the fork are left out of the merge
    # Value: a merge can't delete work that colleagues added to the live project while the sandbox existed.
    Given "Added Later" was created in "parent" after "test-sandbox" was created
    When I open the merge modal for "test-sandbox"
    Then "Added Later" is not listed
    And a request to select it is ignored and it survives the merge
    # index.ex:1013-1018, :1034-1040, :298-316; index_test.exs:3994-4024, :4239-4273

  @S39 @pending
  Scenario: Selecting workflows, and merging nothing is not possible
    # Value: people control exactly which workflows move, and can't run an empty merge by accident.
    Given the merge modal lists 2 workflows, both checked
    When I click the "Workflows to merge" select-all
    Then I see "0 of 2 selected"
    And the "Merge" button is disabled with "No workflows selected"
    When I click it again
    Then I see "2 of 2 selected"
    # index.ex:298-331; components.ex:343-367, :528-536, :552-560; index_test.exs:4314-4420

  @S40 @pending
  Scenario: Changing the target recomputes the workflow list
    # Value: the preview always matches the project the merge will actually change.
    Given the merge modal for "test-sandbox" is open with target "parent"
    When I choose "sibling" as the target
    Then the "Diverged", "New" and "Deleted in sandbox" labels reflect "sibling"
    And workflows I had unchecked stay unchecked
    # index.ex:362-438; index_test.exs:3727-3834, :4422-4515

  @S41 @pending
  Scenario: Credentials only the sandbox has are offered and preselected
    # Value: merged jobs keep working because their credentials come along, unless someone chooses otherwise.
    Given "test-sandbox" has credential "sandbox-only-cred" that "parent" lacks
    When I open the merge modal for "test-sandbox"
    Then I see "Credentials to add" with "sandbox-only-cred" checked
    When I uncheck it, change the target back to "parent" and merge
    Then "parent" does not have "sandbox-only-cred"
    # index.ex:265, :334-359, :414-427, :1072-1095; sandboxes.ex:518-551; index_test.exs:4581-4719

  @S42 @pending
  Scenario: Collections only the sandbox has are created empty; target collections are never removed
    # Value: jobs that use a new collection find it after the merge, and live collection data is never lost to a merge.
    Given "test-sandbox" has collections "col-a" and "col-b" and "parent" has "parent-only"
    When I open the merge modal for "test-sandbox"
    Then I see "Collections to add" with "2 of 2 selected" and no mention of "parent-only"
    When I uncheck "col-b" and merge
    Then "parent" has "col-a" and "parent-only" and not "col-b"
    # index.ex:441-473, :770-801, :1113-1126; sandboxes.ex:1437-1475; index_test.exs:2333-2448, :2550-2720

  @S43 @pending
  Scenario: The merge modal warns that the sandbox and its children will be deleted
    # Value: nobody merges without knowing the sandbox goes away afterwards.
    Given "child1" has one active child sandbox
    When I open the merge modal for "child1"
    Then I see "This sandbox will be deleted after merging"
    And I see "Its child sandbox will also be deleted."
    # index.ex:227; components.ex:511-525; index_test.exs:1647-1707

  @S44 @pending
  Scenario: A failed merge says so without exposing internals
    # Value: people know the merge didn't happen, and error details that could leak workflow names or schema stay in the logs.
    Given the merge will fail validation
    When I merge "child1" into "root"
    Then I see "Couldn't merge this sandbox. Please try again."
    And the merge modal is closed
    And nothing in "root" has changed
    # index.ex:1181-1193, :1227-1231; sandboxes.ex:357-362, :683-716; index_test.exs:2069-2241, :2722-2748

  @S45 @pending @variant:usage-limited
  Scenario: A plan limit hit during the merge shows the limiter's message
    # Value: people learn the merge was blocked by their plan, not by a fault.
    Given the usage limiter refuses the merge with "Custom import error message"
    When I merge "child1" into "root"
    Then I see "Custom import error message"
    # index.ex:1227; sandboxes.ex:691-692; index_test.exs:2167-2201

  @S46 @pending
  Scenario: A merge that can't schedule the sandbox for deletion still reports success
    # Value: people know the merge landed and that the sandbox is still there to clean up.
    Given the sandbox can't be scheduled for deletion after the merge
    When I merge "child1" into "root"
    Then I am on the workflows page of "root"
    And I see "Successfully merged child1 into root, but could not schedule the sandbox for deletion."
    # index.ex:1195-1205; index_test.exs:2021-2067

  @S47 @pending @variant:github-sync
  Scenario: Merging into a GitHub-synced project commits before and after
    # Value: the repository keeps a restore point from just before the merge and a commit of the result.
    Given "parent" is synced to GitHub branch "main"
    When I merge "test-sandbox" into "parent"
    Then the flow "flow-github-sync-actions" has started for "parent" with commit message "pre-merge commit"
    And it has started again with commit message "Merged sandbox test-sandbox"
    # index.ex:1128-1160; index_test.exs:4750-4885; no dispatch without a connection, index_test.exs:4887-4906
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Edit save has no clause for `{:error, :unauthorized}`; `update_sandbox` returns it when the sandbox's MFA requirement isn't met, the sandbox was scheduled for deletion in another tab, or a role changed on the sandbox (not the current project) | `form_component.ex:131-149`; `sandboxes.ex:743-757`; `policies/sandboxes.ex:109-119` | the page crashes and reloads instead of an error | fix |
| `/new` doesn't check the nesting cap, only the button does; submitting at the cap returns `{:error, :nesting_too_deep}`, which the save `with` doesn't match (nor `{:error, :unauthorized}`) | `index.ex:69-100`; `form_component.ex:75-113`; `sandboxes.ex:1015-1017` | typing the URL at the cap opens the form, and submitting crashes the page | fix |
| Delete modal says "you'll be redirected to <root project>", but the redirect goes to the deleted sandbox's parent | `components.ex:188-191`; `index.ex:848-851` | for a nested sandbox, a different project from the one promised | fix |
| After deleting the current sandbox, and on the edit link, the URL uses the sandbox's parent id; a viewer with no row on the parent lands on Not Found (delete) or gets an edit URL that 404s on reload | `index.ex:849-851`; `components.ex:835-837` | sandbox-only members are thrown out of the workspace after deleting, or can't reload the edit modal | fix |
| A sandbox-only member's access-root sandbox has an enabled merge button but no target options; the copy names "MAIN" and Merge is enabled because workflows are preselected | `index.ex:221-225`, `:949-969`; `components.ex:337-340`, `:979-984` | a merge modal that can only end in "Target project not found" | fix |
| "Deleted in sandbox" compares target workflows with the source sandbox's creation time, not with the sandbox's own history; merging into a sibling or grandparent labels the target's older workflows as deleted in the sandbox | `index.ex:1013-1018`, `:1034-1040`; `components.ex:406-412` | a workflow the sandbox never had offered for deletion with a label saying the sandbox deleted it | decide |
| A failed schedule-deletion flash prints `inspect(reason)`, while merge errors are scrubbed | `index.ex:869-875` | raw Elixir terms in a flash | fix |
| `limit_new_sandbox` is read once at mount (for the current project) and not refreshed after delete or restore; restore's tooltip uses the current project's limit while the context checks the sandbox's | `index.ex:37-40`, `:726-743`; `sandboxes.ex:925` | Create and Restore stay enabled or disabled until reload, and the Restore tooltip can disagree with the result | decide |
| Merge trusts `can_merge` captured when the list was last loaded; a demotion on the source sandbox (not the current project, so no remount) doesn't stop the merge, and only the post-merge deletion fails | `index.ex:494`; `index.ex:1195-1205` | merge succeeds, then "could not schedule the sandbox for deletion" | decide |
| Under `purge-immediate` the modal promises "retained for 0 days before being permanently removed", but no purge cron is registered, so the sandbox sits under "Scheduled for deletion" indefinitely | `components.ex:197-201`, `:240-246`; `sandboxes.ex:1001-1006`; `bootstrap.ex:306-316` | copy that contradicts what happens | decide |
| The "pre-merge commit" dispatch fires before the merge and its result is ignored; if the merge fails, GitHub has a commit for a merge that never happened, and a failed dispatch is silent | `index.ex:1136`, `:1155-1160` | nothing in Lightning; an extra commit in the repo | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The list is flat and sorted by name; nesting is not shown | `projects.ex:1097-1103`; `components.ex:118-120` | decide |
| Create always sets env "dev"; env can't be changed here | `form_component.ex:70-73` | decide |
| "Create Sandbox" button label is title case; the modal button is "Create sandbox" | `components.ex:66`; `form_component.ex:164` | fix |
| Header button patches to `/new`, the empty-state link does a full live navigate to the same URL | `components.ex:64`, `:104-109` | preserve |
| "Sandbox not found" on `/:id/edit` stays on the edit URL with no modal; unauthorized redirects | `index.ex:53-63`; `index_test.exs:814-825` | decide |
| Edit's submit isn't disabled when invalid; only create's is | `form_component.ex:252` | decide |
| `url_safe_name` keeps `_` and `.`, but the name format rejects them, so the preview shows a name that will fail | `helpers.ex:223-228`; `project.ex:108` | fix |
| Names of sandboxes scheduled for deletion still block reuse by siblings during the grace period | `projects.ex:2225-2240` | preserve |
| Deletion tooltip date is the UTC date as `%d %b %Y`, and day counts truncate (23 hours is "today") | `components.ex:963-977` | decide |
| Restore does not re-enable the triggers deletion turned off, and is not transactional or broadcast | `sandboxes.ex:884-886`, `:976-988` | decide |
| Restore ignores MFA and the scheduled state, by design, since `Scope` refuses scheduled projects | `policies/sandboxes.ex:121-130` | preserve |
| Merge requires admin or owner on the source although `:merge_sandbox` itself only checks editor on the target | `policies/sandboxes.ex:20-25`, `:64-70` | preserve |
| An editor merging can't carry a sandbox-only keychain into a target where they can't create one; the job arrives without it, silently | `sandboxes.ex:596-617` | decide |
| A merge target with an MFA requirement the user hasn't met is offered, then refused at confirm | `index.ex:913`, `:515-520` | decide |
| Failed delete closes the modal but leaves `confirm_delete_sandbox` assigned; reopening resets it | `index.ex:857-876` | preserve |
| Delete and merge modals close on click-away and Escape; the create and edit modal does not | `components.ex:154-157`, `:293-296`; `form_component.ex:171-176` | decide |
| Collection unchecks only count for the target they were previewed against; a crafted target falls back to creating all | `index.ex:1113-1126`; `index_test.exs:2550-2601` | preserve |
| Workflows are matched by name between sandbox and target, so a renamed workflow shows as "New" plus "Deleted in sandbox" | `index.ex:982-1028` | decide |
| Child sandboxes of a merged sandbox are deleted with it, including ones the viewer can't see | `index.ex:227`; `sandboxes.ex:942-960`; `index_test.exs:2259-2288` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `handle_sandbox_delete_result({:error, :not_found}, ...)` and `handle_cancel_deletion_result({:error, :not_found}, ...)` | `index.ex:863-867`, `:895-897` | the page passes a `%Project{}`; only the string-id clauses return `:not_found` (`sandboxes.ex:872-878`, `:934-940`); tests reach them only by mocking |
| `confirm_delete_input` assign | `index.ex:119`, `:143`, `:750` | set but never rendered |
| `root_project` argument to `handle_merge_result/6` | `index.ex:538`, `:1167` | unused |
| `merge_modal` `:diverged_workflows` attr | `components.ex:253`; `index.ex:628` | passed but not rendered; divergence comes from `source_workflows` |
| `color_palette` `:label`, `:class`, `:disabled` attrs | `components.ex:565-567` | never set by a caller |
| "Invalid merge request" | `index.ex:488-492` | only a crafted `confirm-merge` with no modal open reaches it (`index_test.exs:2841-2857`) |
| `grace_period_label` nil branch | `components.ex:242` | bootstrap always sets an integer (`bootstrap.ex:273-278`); tests stub nil |
| `credential_display_name` fallback "Untitled credential" | `index.ex:1094-1095` | only for a credential with no name |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `/new` reloads the whole workspace again after mount already did | `index.ex:43`, `:84` | no | preserve |
| Every merge-form change (each checkbox lives in the form) recomputes targets, both divergence directions, the workflow list and credentials | `index.ex:362-438` | no | decide |
| Opening the merge modal runs `diverged_workflows` twice (once per direction) and preloads both projects' workflows several times | `index.ex:247-258`, `:1066-1111` | no | preserve |
| Merge runs synchronously in the LiveView, including two GitHub calls and one full YAML export per dispatch | `index.ex:1128-1160`; `version_control.ex:178-215` | yes, on large projects the modal hangs | decide |
| Workflow, credential and collection lists in the modal scroll at `max-h-48`; nothing is paginated | `components.ex:368`, `:445`, `:491` | yes | preserve |
| Tree walks are bounded at `max_sandbox_nesting_depth + 1` | `projects.ex:49-52` | no | preserve |

### 6.5 Things seen but not understood

- The `Sandboxes` moduledoc and `schedule_sandbox_deletion` doc say a scheduled sandbox is "hidden from the parent's sandbox listing"; this page lists it under "Scheduled for deletion" (`sandboxes.ex:834-835`; `components.ex:125-132`). The doc looks stale.
- `merge_select_all_state/2` returns `:all` when the selected count equals the list length, without checking membership; stale ids in the selection could show "all" when they're not (`components.ex:552-560`). Not seen reachable, since selections are intersected with the list on target change (`index.ex:409-412`).
- S10 and S26 are read from code; the LiveView tests mock `schedule_sandbox_deletion` in most delete paths, and no LiveView test asserts triggers after create or delete.
- The collection panel's select-all checkbox has no `disabled` state, unlike the workflow and credential ones (`components.ex:470-481`); it only renders when the list is non-empty, so it may not matter.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Which project should a viewer land on after deleting the sandbox they're in: the parent (code), the root named in the modal copy, or their access root (6.1)? (owner: product).
- Should the list show the sandbox hierarchy rather than a flat, name-sorted list (6.2)?
- Should "Deleted in sandbox" be based on the sandbox's own version history instead of its creation time, so merges into siblings and grandparents are labelled correctly (6.1)?
- Should restore re-enable the triggers deletion turned off, or tell the user they stay off (6.2)?
- What should `purge_deleted_after_days: 0` mean for sandboxes: delete immediately, or never (6.1)?
- Should the pre-merge GitHub commit be kept, moved after a successful merge, or surfaced to the user when it fails (6.1)?
- Should merge re-check the source permission at confirm rather than trust the loaded list (6.1)?

## Proposed flows

- `flow-sandbox-merge`: an admin confirms a merge here, the target's workflows, credentials, keychains and collections change in one transaction, editors open on target workflows are reconciled (`sandboxes.ex:349-355`) or sent to the list when a workflow is deleted (`provisioner.ex:134`; flow-delete-open-workflow), the source subtree is scheduled for deletion and its open pages leave (shared-project-scope S10, S11), and the merging user lands on the target's workflows page with the result flash (`index.ex:1162-1205`). Surfaces: sandboxes-index, pubsub:project_events:<source subtree ids>#ProjectDeletionScheduled, workflow-editor-canvas (target reconcile), pubsub:project_events:<target>#WorkflowDeleted, workflows-index (target landing), external:github-workflow-dispatch when synced.
- `flow-sandbox-scheduled-deletion`: deleting a sandbox here marks it and its descendants with one deletion date and disables their triggers, open pages on any of them leave (shared-project-scope S10, S11), the sandbox is listed under "Scheduled for deletion" with Restore during the grace period, and the nightly purge hard-deletes it after `purge_deleted_after_days` (`sandboxes.ex:942-973`; `projects.ex:194-221`; `bootstrap.ex:311`). Differs from flow-schedule-project-deletion: no email, cascades to children, restore lives here. Surfaces: sandboxes-index, project-settings-setup (its own sandbox delete path), pubsub:project_events:<subtree ids>#ProjectDeletionScheduled, oban:purge_deleted.
- Existing `flow-github-sync-actions` is referenced, not proposed: S47 starts it from a merge. sandboxes-index should be added to its `surfaces` as a third entry, with commit messages "pre-merge commit" and "Merged sandbox <name>".

## Proposed shared

- `shared-tooltip-hook` (already proposed by history-work-orders; referenced here, not created): the `Tooltip` JS hook (`assets/js/hooks/index.ts:567`), used here for the action-button tooltips and the scheduled-deletion tooltip (`components.ex:672`, `:892`). Surfaces: sandboxes-index, history-work-orders and most project views.
- `shared-derived-name-field`: the "raw name to URL-safe name" field with its live preview badge (`Helpers.derive_name_param/1`, `url_safe_name/1`, `Pills.name_badge/1`; `helpers.ex:221-240`, `pills.ex:85-105`), used by the sandbox form here (`form_component.ex:211-242`), project creation (`dashboard_live/project_creation_modal.ex`, `project_live/form_component.html.heex`), project settings (`project_live/settings.html.heex`) and collection creation (`collection_live/collection_creation_modal.ex`). Its 6.2 row about `_` and `.` belongs there. Surfaces: sandboxes-index, project-settings-setup, projects-dashboard, project-settings-collections.

## Lead resolution (batch 4)

- `flow-sandbox-merge` and `flow-sandbox-scheduled-deletion` created. sandboxes-index added to flow-github-sync-actions surfaces.
- `shared-derived-name-field` declined; `shared-tooltip-hook` was declined in batch 1 and is removed from `inherits`.
