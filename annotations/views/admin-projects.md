---
id: admin-projects
type: view
title: Admin settings › Projects
status: not-started
owner:

trigger:
  old_route: /settings/projects, /settings/projects/new, /settings/projects/:id, /settings/projects/:id/delete
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session; the four routes sit in the `:settings` live_session, which mounts `InitAssigns` (`lib/lightning_web/router.ex:268`, `:273-276`)
    - the viewer is a superuser (`project_live/index.ex:7`; gate owned by shared-admin-space S02, S03)
    - "/settings/projects/:id needs an existing project id (`index.ex:61`, `projects.ex:519-522`, raises otherwise, 6.2)"
    - "/settings/projects/:id/delete is reached from the row's \"Delete\" or \"Delete now\" link (`index.ex:165-177`); an unknown id crashes (6.1)"
    - entered from the "Projects" item in the admin side menu (shared-admin-space S01) or the "Admin Menu" link in the project side menu (shared-project-header S17)

inherits:
  - shared-admin-space                # gate (S02, S03), settings layout and side menu (S01); this view's active item is :projects except on /delete (shared-admin-space 6.1)
  - shared-authenticated-session      # login redirect, revoked sessions, TOTP and lockout gates, sidebar (S01 to S07, S11); S08 to S10 not on the settings layout
  - shared-flash-messages             # bottom toasts on the settings layout (S07 uses this view's "Project deletion canceled")
  - shared-project-header             # no-project parts only, as admin-users: LayoutComponents.header confirmation banner (S13, S14) rendered at index.html.heex:3, global picker (S04, S06, S08, S10 to S12), account menu (S18)
  - shared-project-deletion-modal     # the /delete route; save_return_to and cancel_return_to both /settings/projects (index.html.heex:17-23); S01 to S05, both branches

url_params:
  - name: id (path segment of /settings/projects/:id)
    set_by: admin-projects (row "Edit" link, index.html.heex:120-124)
    effect: loads that project with its members into the project form (`index.ex:56-67`)
  - name: id (path segment of /settings/projects/:id/delete)
    set_by: admin-projects (row "Delete" / "Delete now" links, index.ex:165-177)
    effect: loads that project into the deletion modal over the list (`index.ex:82-93`)

config_variants:
  default: { lightning.project_hook: Lightning.Extensions.ProjectHook }   # read under this one (config/config.exs:47); Oban inline in test (config/test.exs:155), background queue otherwise
  require-email-verification: { lightning.require_email_verification: true }   # inherited only; shared-project-header S13, S14

inventory:
  routes:
    - live /settings/projects  ProjectLive.Index :index              # router.ex:273
    - live /settings/projects/new  ProjectLive.Index :new            # router.ex:274
    - live /settings/projects/:id  ProjectLive.Index :edit           # router.ex:275
    - live /settings/projects/:id/delete  ProjectLive.Index :delete  # router.ex:276
  events:
    - ProjectLive.Index#cancel_deletion          # index.ex:95-107
    - ProjectLive.Index#sort                     # index.ex:109-125
    - ProjectLive.Index#filter                   # index.ex:127-140
    - ProjectLive.Index#clear_filter             # index.ex:142-151
    - ProjectLive.FormComponent#validate         # form_component.ex:92-104
    - ProjectLive.FormComponent#sort             # form_component.ex:106-119
    - ProjectLive.FormComponent#filter           # form_component.ex:121-126
    - ProjectLive.FormComponent#clear_filter     # form_component.ex:128-133
    - ProjectLive.FormComponent#save             # form_component.ex:135-195
    - Components.ProjectDeletionModal#validate   # owned by shared-project-deletion-modal
    - Components.ProjectDeletionModal#delete     # owned by shared-project-deletion-modal
    - Components.ProjectDeletionModal#close_modal  # owned by shared-project-deletion-modal
  js_hooks:
    - ModalHook                                  # via the deletion modal; owned by shared-project-deletion-modal
    - Common.simple_dropdown show_dropdown / hide_dropdown JS commands (common.ex:677-709), row "Actions" menu (index.html.heex:111-127)
    - TableHelpers.filter_input phx-keyup with phx-debounce 300 (table_helpers.ex:33-43), list and form
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), through LightningWeb.Hooks :ensure_admin (hooks.ex:31-53); no project-level policy is checked anywhere in this view
  workers:
    - Lightning.Accounts.UserNotifier (Oban, type project_addition; projects.ex:836-847), on create and on edit for new members
    - Lightning.Projects (Oban, type purge_deleted), via the modal's delete-now branch; owned by shared-project-deletion-modal
  api_endpoints: []
  emails:
    - email:project-addition                     # owned by flow-collaborator-added-email
    - email:project-deletion-scheduled           # via the modal's schedule branch; owned by flow-schedule-project-deletion
  config:
    - :lightning, :project_hook (config/config.exs:47; services/project_hook.ex:12-30)
  not_reachable_here:
    - ProjectLive.ConcurrencyInputComponent and the other project_live components; not rendered by ProjectLive.Index
    - ProjectDeletionModal nothing unreachable here; both branches render (shared-project-deletion-modal 6.3 lists the settings-host branch)
    - Projects.update_project/3 audit path (`projects.ex:589-626`); this view saves through update_project_with_users/4 instead (6.1)
    - Projects.delete_project_user!/2 owner and sandbox parent-admin guards (`projects.ex:864-880`); the admin form removes through cast_assoc instead (6.2)

related:
  - admin-audit                       # collaborator_added / role_changed / removed events written here land there (S10)
  - project-settings-collaborators    # the project-admin way to do S08, with a removal warning this view lacks (6.2)
  - lib/lightning_web/live/project_live/index.ex
  - lib/lightning_web/live/project_live/index.html.heex
  - lib/lightning_web/live/project_live/form_component.ex
  - lib/lightning_web/live/project_live/form_component.html.heex
  - lib/lightning_web/live/helpers/table_helpers.ex
  - lib/lightning/projects.ex          # create_project/2 (:562-577), update_project_with_users/4 (:629-660), membership helpers (:662-776), schedule_project_addition_emails/2 (:836-847), cancel_scheduled_deletion/1 (:1728-1732)
  - lib/lightning/projects/project.ex  # form_with_users_changeset/2 (:165-187), project_with_users_changeset/2 (:282-302), validate_project_owner/1 (:304-325)
  - lib/lightning/projects/project_user.ex
  - lib/lightning/projects/audit.ex    # derive_membership_events/4 (:47-85)
  - lib/lightning/projects/events.ex
  - lib/lightning/extensions/project_hook.ex
  - test/lightning_web/live/project_live_test.exs   # :33-49, :52-746 (superuser describe block)
flows:
  - flow-collaborator-added-email      # S05, S08 handoff; admin-projects is not yet in its surfaces (section 8)
  - flow-schedule-project-deletion     # S13 to S15 handoff (its S10 to S12)
---

## 1. Purpose

Superusers use this page to see every project on the instance, set up new projects for teams, and
fix who owns and can reach a project when nobody on the project can, for example after the only
owner leaves. It is also where a superuser retires, un-retires or purges a project. Without it,
an orphaned project, or one whose membership has gone wrong, has no way back short of a database
change, and an instance admin has no single view of what projects exist and who answers for them.

## 2. What it does

- **See every project**
  - Superusers see every project with its creation date, description, owner and scheduled deletion date, and which have no owner
  - Superusers filter the list by name, description or owner, and sort it by any column
- **Create a project**
  - Superusers create a project with a name and a set of members, one of them the owner, without joining it
- **Change a project**
  - Superusers rename a project and add, re-role or remove its members
  - Superusers are stopped from saving a project without exactly one owner
- **Retire a project**
  - Superusers schedule a project for deletion, cancel a scheduled deletion, or purge a scheduled project now

**Straightforwardness: 3 of 5.** The list and the deletion actions are simple; the member form is where things go quietly wrong, and its effects reach well beyond this page.

### Most surprising behaviours

- **(2)** Filtering the member list inside the form seems to drop the hidden people from what gets saved: on edit the page may crash, and on a new project an owner picked before filtering can silently vanish. Read from the code, not run. (6.1)
- **(2)** Handing a project to a new owner in one save may fail with no visible message, so "Save" appears to do nothing. Read from the code, not run. (6.1)
- **(3)** Removing a member also takes their own credentials off the project, with no confirmation or warning, so workflows using those credentials may stop working. Project settings warns about this; this page doesn't. (S09, 6.2)
- **(3)** A superuser can manage any project here but may be refused when they try to open it, because admin access and project access are separate. (6.5)
- **(3)** A project already scheduled for deletion can still be edited, and anyone added gets an access email whose link leads to "Not Found". Disabled accounts can be added and emailed too. (6.1)

## 3. Who can do what

Project roles play no part here: the only gate is the admin space, and a superuser acts on every
project whether or not they are a member (`index.ex:7`, `:195-201`; no project policy is called in
`index.ex` or `form_component.ex`).

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| See the project list (all projects) | no | no | no | yes |
| Create a project | no | no | no | yes |
| Rename a project, change its members | no | no | no | yes |
| Schedule a deletion | no | no | no | yes |
| Cancel a scheduled deletion | no | no | no | yes |
| Purge a scheduled project now | no | no | no | yes |

Sources: `policies/users.ex:19-21`, `hooks.ex:40-53` (via shared-admin-space S02); tests
`project_live_test.exs:33-49`.

**Preconditions beyond role**
- Exactly one member must be owner for a create or an edit to save (`project.ex:304-325`).
- "Cancel deletion" and "Delete now" are offered only on a project already scheduled for deletion; "Delete" only on one that is not (`index.ex:153-180`).
- The delete-now branch of the modal runs only when the project, as loaded by this page, is already scheduled (shared-project-deletion-modal, preconditions).
- Handlers re-check nothing: a socket that passed the mount gate can send every event (`hooks.ex:28-30` comment; shared-admin-space S03).

## 4. What it touches

**Reads**
- `projects` with `project_users` and `users` preloaded, all rows, on every list render, filter and sort (`index.ex:182-201`)
- One project with its members (`projects.ex:519-522`) and every row of `users` (`accounts.ex:290-292`) for the form (`index.ex:56-80`)
- One project with its parent for the deletion modal (`projects.ex:282-287`, `index.ex:88`)

**Writes**
- Create: `projects` insert and `project_users` inserts in one transaction (`projects.ex:562-577`, `project_hook.ex:14-18`); `oban_jobs` insert per member (`projects.ex:836-847`)
- Edit: `projects` update (name), `project_users` insert, update role, delete; `project_credentials` delete for each removed member's own credentials; `audit_events` insert per membership change (`projects.ex:629-660`, `:695-708`, `:738-755`; `audit.ex:47-85`); `oban_jobs` per new member
- Cancel deletion: `projects.scheduled_deletion` set to nil (`projects.ex:1728-1732`)
- Schedule and delete-now: owned by shared-project-deletion-modal and flow-schedule-project-deletion

**Immediate side effects** (in the same request)
- Create: PubSub `ProjectCreated` on `projects_events:all` (`projects.ex:574-576`, `events.ex:81-86`); nothing subscribes (6.3)
- Edit: PubSub `ProjectUserAdded`, `ProjectUserRoleChanged`, `ProjectUserRemoved` on the project topic, one per change (`projects.ex:644`, `:757-773`, `events.ex:95-114`); consumed by every open project page (`hooks.ex:252-254`, shared-project-scope S07, S08), the workflow channel (`workflow_channel.ex:19-21`), the AI assistant channel (`ai_assistant_channel.ex:480-482`, `:520-522`) and the run channel on removal (`run_channel.ex:336`)
- Edit: `SupportAccessUpdated` if a submitted payload flips `allow_support_access` (`projects.ex:645`, `:776-780`); not reachable from the rendered form (6.1)
- Audit: `collaborator_added`, `collaborator_role_changed`, `collaborator_removed` with the superuser as actor (`audit.ex:57-85`); create writes none (6.2)
- Flash "Project created successfully", "Project updated successfully" or "Project deletion canceled" and a patch back to `/settings/projects` (`form_component.ex:171-175`, `:186-189`; `index.ex:103-106`)

**Deferred side effects** (later, elsewhere)
- Email `email:project-addition` to each member on create and each new member on edit, through the Oban `background` queue (`projects.ex:567`, `:648`, `:836-847`); handoff to flow-collaborator-added-email
- Schedule: emails to members, trigger disabling and the nightly purge; delete-now: the purge job (flow-schedule-project-deletion S01 to S07, S12)

**External, non-transactional effects**
- none in this view; emails leave from the Oban job after commit

**Depends on config**
- `:project_hook` decides how a project is inserted on create (`config/config.exs:47`, `services/project_hook.ex:14-15`); read under the default `Lightning.Extensions.ProjectHook`
- `purge_deleted_after_days` through the modal (shared-project-deletion-modal)

**Product limits**
- none set by this view; see 6.4 for the unpaginated list and form

## 5. Scenarios

Verified against `default` by reading code and test assertions; not run. The non-superuser refusal
is shared-admin-space S02 and S03 (tests `project_live_test.exs:33-49`) and is not restated.

```gherkin
Feature: Admin projects
  In order to keep every project on the instance owned, reachable by the right people, and retired on purpose
  As a superuser
  I want to list, create, edit and delete any project

  @S01 @pending
  Scenario: Superuser sees every project on the instance
    # Value: instance admins can see what projects exist and who answers for each, including ones they are not a member of.
    Given I am a superuser who is not a member of project "malawi-hiv"
    And project "malawi-hiv" was created on 3 March, has description "HIV programme" and owner "Amara Banda"
    When I open "/settings/projects"
    Then I see a row for "malawi-hiv" with "03 Mar", "HIV programme" and "Amara Banda"
    And the row has an "Actions" menu with "Edit" and "Delete"
    # index.ex:44-54, :182-211; index.html.heex:41-130; project_live_test.exs:71-77 (asserts the name only)

  @S02 @pending
  Scenario: A project without an owner is called out
    # Value: an orphaned project is visible to the one role that can give it an owner again.
    Given project "legacy-sync" has members but none with role owner
    When I open "/settings/projects"
    Then the owner column for "legacy-sync" says "No owner"
    # index.ex:203-211; index.html.heex:97-104

  @S03 @pending
  Scenario: Superuser filters the list by name, description or owner
    # Value: on an instance with many projects, an admin finds the one a user is asking about by whatever they remember of it.
    Given projects "alpha-project" (description "First project", owner "John Owner") and "beta-project" (description "Second project")
    When I type "alpha" in "Filter projects..."
    Then I see "alpha-project" and not "beta-project"
    When I type "First" in "Filter projects..."
    Then I see "alpha-project" and not "beta-project"
    When I type "John" in "Filter projects..."
    Then I see "alpha-project" and not "beta-project"
    When I clear the filter
    Then I see both projects
    # index.ex:26-32, :127-151; table_helpers.ex:26-58, :130-141; project_live_test.exs:488-536, :538-558

  @S04 @pending
  Scenario: Superuser sorts the list by a column
    # Value: an admin can line projects up by age, owner or upcoming deletion to review them.
    Given projects "alpha-project", "beta-project" and "charlie-project"
    When I click the "Name" header
    Then the projects are listed "charlie-project", "beta-project", "alpha-project"
    When I click the "Name" header again
    Then the projects are listed "alpha-project", "beta-project", "charlie-project"
    When I click the "Created at" header
    Then the oldest project is listed first
    # index.ex:14-24, :109-125; table_helpers.ex:110-118, :152-164, :220-228; project_live_test.exs:419-486
    # first click on the already active "name" key reverses it, since the list starts sorted by name ascending (index.ex:49-51)

  @S05 @pending
  Scenario: Superuser creates a project for a team without joining it
    # Value: a team can be given a project, with its owner already in place, without the superuser appearing on it.
    Given users "1st user" and "another person" exist
    When I click "New Project"
    And I enter "some name" as the name
    And I set "1st user" to owner and "another person" to editor
    And I click "Save"
    Then I am on "/settings/projects"
    And I see "Project created successfully"
    And project "some-name" has exactly those two members and not me
    And the flow "flow-collaborator-added-email" has started for "1st user" and for "another person"
    # form_component.ex:135-163, :183-195; projects.ex:562-577, :836-847; project_hook.ex:14-18
    # project_live_test.exs:97-166 (asserts flash and both "You now have access to" emails; membership asserted by :357-396 for edit)

  @S06 @pending
  Scenario: A project cannot be saved without exactly one owner
    # Value: no project leaves this form with nobody, or two people, answering for it.
    Given I am on "/settings/projects/new"
    Then I do not see "Every project must have exactly one owner. Please specify one below."
    And "Save" is disabled
    When I change the form without choosing an owner
    Then I see "Every project must have exactly one owner. Please specify one below."
    When I set two users to owner
    Then I see "A project can have only one owner."
    When I submit with no owner
    Then no project is created
    # project.ex:304-325; form_component.html.heex:33-47, :191-193; form_component.ex:76-80, :92-104
    # project_live_test.exs:79-95, :97-125

  @S07 @pending
  Scenario: The saved name is shown before saving, and a name with no usable characters is refused
    # Value: the admin knows the exact identifier members, URLs and exports will use, and can't create a project with an empty one.
    Given I am on "/settings/projects/new"
    When I type "Malawi HIV 2025" as the name
    Then I see "Note that this project will be named: malawi-hiv-2025."
    When I type "!!!" as the name and save
    Then I see "can't be blank"
    # project.ex:189-194; helpers.ex:221-240; form_component.ex:161; form_component.html.heex:11-22; pills.ex:98-105
    # project_live_test.exs:398-417 (edit route, blank error only)

  @S08 @pending
  Scenario: Superuser changes a project's members
    # Value: access can be fixed by the instance admin when no one on the project is able to, for example when the owner has left.
    Given project "malawi-hiv" has owner "Alice Smith", editor "Bob Jones" and viewer "Charlie Brown"
    And "Dana Ray" is a registered user not on the project
    When I open "Edit" for "malawi-hiv"
    And I set "Bob Jones" to admin, "Charlie Brown" to "No access" and "Dana Ray" to viewer
    And I click "Save"
    Then I am on "/settings/projects"
    And I see "Project updated successfully"
    And "malawi-hiv" has owner "Alice Smith", admin "Bob Jones" and viewer "Dana Ray"
    And the flow "flow-collaborator-added-email" has started for "Dana Ray" only
    And "Charlie Brown"'s and "Bob Jones"'s open pages on the project are handed to shared-project-scope S07 and S08
    # form_component.ex:135-181; projects.ex:629-660, :695-736, :757-773, :836-847; hooks.ex:252-254
    # project_live_test.exs:357-396, :560-606, :608-645, :647-680 (membership rows asserted; emails and broadcasts not)

  @S09 @pending
  Scenario: Removing a member withdraws their credentials from the project
    # Value: someone taken off a project stops having their own secrets used by that project's workflows.
    Given "Charlie Brown" is a viewer on "malawi-hiv" and owns credential "DHIS2 play" shared with it
    When I set "Charlie Brown" to "No access" on the admin project form and save
    Then "DHIS2 play" is no longer shared with "malawi-hiv"
    And "DHIS2 play" still belongs to "Charlie Brown"
    # projects.ex:695-700, :738-755

  @S10 @pending
  Scenario: Membership changes made here are audited against the superuser
    # Value: a project's owners and auditors can see that an instance admin, and which one, changed who has access.
    Given I am superuser "root@example.org"
    When I change "Bob Jones" from editor to admin on "malawi-hiv" and save
    Then an audit event "collaborator_role_changed" is recorded for "malawi-hiv" with actor "root@example.org", before role "editor" and after role "admin"
    # projects.ex:699-708; audit.ex:47-85; listing of the event belongs to admin-audit

  @S11 @pending
  Scenario: Cancel leaves the project form without saving
    # Value: an admin can back out of a membership edit without side effects on the project.
    Given I am on "Edit" for "malawi-hiv"
    When I set "Bob Jones" to "No access" and click "Cancel"
    Then I am on "/settings/projects"
    And "Bob Jones" is still a member of "malawi-hiv"
    # form_component.html.heex:183-188

  @S12 @pending
  Scenario: Only a project already scheduled for deletion can be purged now
    # Value: a live project's data can't be purged in a single step; it must first go through the grace period and its notice.
    Given project "alpha-project" is not scheduled for deletion
    And project "beta-project" is scheduled for deletion on 21 October
    When I open the "Actions" menu on each row
    Then "alpha-project" offers "Delete" and neither "Cancel deletion" nor "Delete now"
    And "beta-project" offers "Cancel deletion" and "Delete now" and not "Delete"
    And the scheduled deletion column for "beta-project" shows "21 Oct"
    # index.ex:153-180; index.html.heex:105-108, :125; project_live_test.exs:239-255, :308-320, :322-337

  @S13 @pending
  Scenario: Delete starts the schedule-deletion flow
    # Value: an instance admin can retire a project nobody on it is able to retire.
    Given project "alpha-project" is not scheduled for deletion
    When I click "Delete" on "alpha-project"
    Then I am on "/settings/projects/<alpha-project id>/delete" with the deletion modal over the list
    And the flow "flow-schedule-project-deletion" has started (its S10)
    # index.ex:82-93, :172-177; index.html.heex:16-24; project_live_test.exs:239-276

  @S14 @pending
  Scenario: Cancel deletion hands off to the schedule-deletion flow
    # Value: a mistaken deletion can be undone during the grace period.
    Given project "beta-project" is scheduled for deletion
    When I click "Cancel deletion" on "beta-project"
    Then I see "Project deletion canceled"
    And the row for "beta-project" offers "Delete" again
    And the rest is flow "flow-schedule-project-deletion" S11
    # index.ex:95-107 (push_patch re-runs apply_action :index, :44-54); projects.ex:1728-1732; project_live_test.exs:308-320 (flash only)

  @S15 @pending
  Scenario: Delete now hands off to the schedule-deletion flow
    # Value: a superuser can remove a project's data before the grace period ends when that is required.
    Given project "beta-project" is scheduled for deletion
    When I click "Delete now" on "beta-project"
    Then I am on "/settings/projects/<beta-project id>/delete"
    And the flow "flow-schedule-project-deletion" has started (its S12, through shared-project-deletion-modal S04)
    # index.ex:165-170; project_live_test.exs:322-355
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The member table's "No access", "Owner", "Admin", "Editor" and "Viewer" headers are sortable, but `user_sort_map` has no such keys, so `sort_items` falls back to the key string and sorts by a constant | `form_component.html.heex:79-127`; `form_component.ex:48-54`; `table_helpers.ex:155`, `:209-211` | the header shows an active sort arrow and the rows do not move | fix |
| Filtering the member table removes the hidden rows from the form, so the next change or save submits only visible rows. On edit, an existing member missing from the params meets `cast_assoc` with the default `on_replace: :raise`; on new, roles set on filtered-out users are dropped. Read from code, not run | `form_component.html.heex:49-53` (filter input inside the form), `:132`; `form_component.ex:93-97`, `:135-163`, `:205-228`; `project.ex:44`, `:184`, `:299` | edit: the page crashes after filtering then clicking a role or "Save"; new: an owner picked before filtering silently vanishes and the save fails with "exactly one owner" | fix |
| Moving ownership in one save can hit the non-deferrable `project_owner_unique_index`, depending on whether the new owner's row is updated before the old owner's (`users_sort` is `Map.keys` order). The resulting error sits on a nested `project_user` changeset, which the form never renders. Read from code, not run | `priv/repo/migrations/20240502053312_add_unique_index_on_project_users.exs:5-8`; `project_user.ex:59-62`; `form_component.ex:152-156`, `:177-179`; `form_component.html.heex:33-47` | "Save" appears to do nothing when handing a project to a new owner | fix |
| The changesets behind this form cast `id`, `parent_id`, `allow_support_access`, `requires_mfa`, `retention_policy`, `history_retention_period`, `dataclip_retention_period`, `concurrency`, `color`, `env` and `description`, none of which the form renders. A crafted save can set them; the edit path (`update_project_with_users`) writes no `*_updated` audit event and sends no data-retention email, unlike `update_project` | `project.ex:165-187`, `:282-302`; `projects.ex:589-626` vs `:629-660`; `audit.ex:20-39` | nothing in the normal UI; a superuser socket can change MFA, support access, retention or a project's parent with no audit trail | fix |
| `/settings/projects/:id/delete` with an unknown id assigns `project: nil` and the template reads `@project.id` (already flow-schedule-project-deletion 6.1) | `index.ex:88`; `index.html.heex:19` | a crash page for a stale or mistyped link | fix |
| A project scheduled for deletion can still be edited here; a member added to it gets "You now have access to ..." while shared-project-scope S04 refuses them | `index.ex:56-67` (no scheduled check); `projects.ex:648`; shared-project-scope S04 | an access email whose link shows "Not Found" | decide |
| Adding a disabled account or one scheduled for deletion is allowed: the form lists every user row, and the access email is sent to them | `index.ex:62`, `:75`; `accounts.ex:290-292`; `projects.ex:836-847` | an access email to someone who can't log in | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Creating a project writes no audit event for the project or its initial members, while editing members does | `projects.ex:562-577`, `project_hook.ex:14-18`; compare `projects.ex:695-708` | decide |
| Description is listed, filtered and sorted on, but the form has no description field | `index.html.heex:94-96`; `form_component.html.heex:1-197` | decide |
| Removing a member here has no confirmation and no warning that their credentials leave the project, unlike project-settings-collaborators | `form_component.html.heex:153-160`; project-settings-collaborators S15 | decide |
| Removal goes through `cast_assoc` delete, not `Projects.delete_project_user!/2`, so its refusal to remove a parent-project admin from a sandbox does not apply here (the owner case is covered by S06) | `form_component.ex:143-149`; `project_user.ex:66-72`; `projects.ex:864-880` | decide |
| Sandboxes are listed with root projects, under their bare name, with no parent shown; "Delete" on a sandbox takes the root path (flow-schedule-project-deletion 6.2) | `index.ex:195-201`; `index.html.heex:92` | decide |
| Root project names are not unique (the unique index covers children only), so two root projects can share a name | `project.ex:122`; `priv/repo/migrations/20250824190735_add_sandbox_fields_to_projects.exs:14-17` | decide |
| The name input's value is the derived slug (`value={f[:name].value}`), so after a re-render the field shows "malawi-hiv" rather than what was typed | `form_component.html.heex:12-17` | decide |
| Cancel deletion has no confirmation, writes no audit event and does not re-enable the triggers scheduling disabled (flow-schedule-project-deletion 6.2) | `index.ex:95-107`; `projects.ex:1728-1732` | decide |
| The list does not subscribe to anything; changes by another superuser or by owners show only after a reload or a patch | `index.ex:34-42` | decide |
| Dates are `%d %b  %H:%M` (double space, no year, UTC with no zone) for both created and scheduled deletion | `index.html.heex:93`, `:105-108` | decide |
| Nulls in the scheduled deletion column sort last ascending (sentinel 9999-12-31); empty owner or description sort first | `index.ex:16-22` | preserve |
| Member rows start ordered by first name in `update/2`, then are re-sorted by full name by the table; non-members are greyed | `form_component.ex:62-74`, `:205-228`; `form_component.html.heex:133-136` | preserve |
| An unknown id on `/settings/projects/:id` raises `Ecto.NoResultsError`, rendered as a 404 | `index.ex:61`; `projects.ex:519-522` | preserve |
| Labels are not sentence case: "New Project", "Edit Project", "Created At", "Scheduled Deletion", "NAME", "EMAIL", "NO ACCESS", "OWNER" and so on | `index.ex:59`, `:72`; `index.html.heex:9`, `:58`, `:82`; `form_component.html.heex:69-127` | fix |
| FormComponent's moduledoc describes a Job adaptor form | `form_component.ex:2-12` | fix |
| "Save" is disabled while the changeset is invalid, so a fresh "New project" form starts with it disabled; `phx-disable-with="Saving"` | `form_component.html.heex:191` | preserve |
| The admin menu and global picker on /edit and /delete (active item, picker marking the edited project) are recorded on shared-admin-space 6.1 and 6.2 | `index.ex:60-61`, `:86-88` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `Events.project_created/1` broadcast | `projects.ex:574-576`; `events.ex:81-86` | nothing subscribes to `projects_events:all` (flow-schedule-project-deletion 6.3) |
| `get_user_name(nil)` and `get_user_email(nil)` clauses | `form_component.ex:24`, `:29` | every form row is built from `@users`, so the lookup always finds a user |
| `sort_key`, `sort_direction` and `filter` assigns on `:new` and `:edit` | `index.ex:63-65`, `:76-78` | the list is not rendered on those actions; the form keeps its own (`form_component.ex:86-88`) |
| Catch-all `raise` for a failed audit or credential step | `projects.ex:654-658` | only on a database failure |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| No pagination: every list render, filter keystroke and sort re-reads all projects with all members and users, then filters and sorts in memory | `index.ex:117`, `:128-133`, `:143-144`, `:182-201` | yes, a slow list on large instances | decide |
| The edit and new form lists every user on the instance with five radios each, and every change re-casts the whole member set | `index.ex:62`, `:75`; `form_component.ex:62-80`, `:93-97` | yes, a very long form on large instances | decide |
| Filter inputs debounce 300 ms | `table_helpers.ex:40` | yes | preserve |
| Access emails go through the Oban `background` queue, concurrency 1 (flow-collaborator-added-email) | `projects.ex:836-847` | yes, emails arrive later than the save | preserve |

### 6.5 Things seen but not understood

- A superuser who is not a member can manage a project here but is refused by shared-project-scope on the project's own pages (its 6.x row on `project_users.ex:193-194`). Whether that split is intended was not established. (decide)
- Whether `put_flash` in the form component followed by `push_patch` always shows as a settings-layout toast was read from the test's rendered HTML only (`project_live_test.exs:160`, `:387`). (preserve)
- flow-collaborator-added-email lists the admin form as out of its scope (`not_reachable_here`), so its handoff from S05 and S08 has no owning end-to-end scenario yet. (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should admin-projects be added to flow-collaborator-added-email's `surfaces`, with a scenario for the create path that emails every initial member including the owner? (owner: product)
- Should the admin form stop casting fields it does not render, and should edits through it write the same audit events as project settings? (owner: security)
- Should removing a member here confirm and warn about credentials, as project settings does? (owner: product)
- Should a project scheduled for deletion be editable here, and should disabled accounts be offered as members? (owner: product)
- Should a superuser who can manage a project here be able to open it, or is admin access deliberately separate from project access? (owner: security)
- Should the list paginate and filter in the database? (owner: product)

## Proposed flows

none; references flow-collaborator-added-email (S05, S08) and flow-schedule-project-deletion (S13 to S15, its S10 to S12). Membership broadcasts hand off to shared-project-scope S07 and S08.

## Proposed shared

- `shared-admin-table-filter-sort`: the TableHelpers filter input (300 ms debounce, clear button), sortable headers that toggle direction on a second click, and in-memory `filter_and_sort`, with the `simple_dropdown` row actions menu. Surfaces: admin-users, admin-projects (list and member form).

## Lead resolution (batch 10)

- `shared-admin-table-filter-sort` declined: sorting and filtering stay in each view, as for the sortable header and filter chip in batch 1. admin-projects added to flow-collaborator-added-email surfaces.
