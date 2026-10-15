---
id: project-settings-setup
type: view
title: Project settings › Setup
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#project (also /projects/:project_id/settings/delete)
  new_route:
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (see shared-project-scope; settings.ex:51)
    - "#project" is the default tab of the settings page; the delete modal opens at /settings/delete

inherits:
  - shared-project-scope            # login, MFA, membership, live revocation (settings.ex:51)
  - shared-usage-limits-banner      # :check_limits on_mount (settings.ex:52)
  - shared-authenticated-session
  - shared-project-header
  - shared-project-settings-tab-chrome
  - shared-project-deletion-modal
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: project_id
    set_by: every project link
    effect: selects the project (shared-project-scope)
  - name: "#project (URL hash)"
    set_by: settings tab strip, and DownloadsController redirecting back after a failed export (downloads_controller.ex:35-38 lands on /settings, whose default tab is this one)
    effect: shows this panel (settings.html.heex:66)
  - name: /settings/delete (live_action :delete)
    set_by: the "Delete project" / "Delete sandbox" button (settings.html.heex:281-292)
    effect: opens the project deletion modal, or the sandbox confirm modal for a sandbox; non-owners are sent back to /settings (settings.ex:262-281)

config_variants:
  default: { Lightning.Extensions.Routing metadata: { concurrency_input: LightningWeb.ProjectLive.ConcurrencyInputComponent }, purge_deleted_after_days: 7 }   # read under this variant (config/config.exs:52-57, bootstrap.ex:273-278)
  no-concurrency-slot: { Lightning.Extensions.Routing metadata without :concurrency_input }   # settings.ex:245, settings.html.heex:201-202
  usage-caps-slot: { Lightning.Extensions.Routing metadata: { usage_caps_input: <downstream LiveComponent> } }   # settings.ex:246, settings.html.heex:245-250
  purge-immediate: { purge_deleted_after_days: 0 }   # project_deletion_modal.ex:103-106, projects.ex:1655-1659, bootstrap.ex:307
  project-hook: { Lightning.Extensions.project_hook: <adapter with its own handle_project_validation/handle_delete_project> }   # projects.ex:592-593, services/project_hook.ex:26-27

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index (config-injected, live_session :services; config/config.exs:52-57, router.ex:339-355)
    - live /projects/:project_id/settings/delete  ProjectLive.Settings :delete (live_session :default; router.ex:291-292)
  events:
    - ProjectLive.Settings#validate          # shared with the data storage tab's form; this view covers #project-settings-form and #project-concurrency-form
    - ProjectLive.Settings#save
    - ProjectLive.Settings#close-delete-modal
    - ProjectLive.Settings#confirm-delete-validate
    - ProjectLive.Settings#confirm-delete
    - LightningWeb.Components.ProjectDeletionModal#validate
    - LightningWeb.Components.ProjectDeletionModal#delete
    - LightningWeb.Components.ProjectDeletionModal#close_modal
  js_hooks:
    - integer-toggle JS.toggle_attribute + JS.dispatch("input") on the concurrency switch (new_inputs.ex:838-846)
    - modal JS.push("close-delete-modal") on sandbox confirm modal close, click-away and Escape (sandbox_live/components.ex:150-158, :165, :229)
  policies:
    - Lightning.Policies.ProjectUsers (:edit_project, :delete_project, :access_project for the export controller)
    - Lightning.Policies.Sandboxes (:delete_sandbox)
  workers:
    - Lightning.Projects (Oban, type purge_deleted)   # deferred effect of scheduling deletion (projects.ex:193-219)
  api_endpoints: []
  emails:
    - email:project-deletion-scheduled   # UserNotifier.notify_project_deletion/2, user_notifier.ex:430-450
  config:
    - :lightning, Lightning.Extensions.Routing, routes metadata :concurrency_input
    - :lightning, Lightning.Extensions.Routing, routes metadata :usage_caps_input
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
    - Lightning.Extensions.project_hook (handle_project_validation, handle_delete_project)
  not_reachable_here:
    - ProjectDeletionModal delete_project_async branch, "Project deletion started. This may take a while to complete." (project_deletion_modal.ex:66-74, :95-98); reachable only from the superuser projects list
    - SandboxLive.Components.confirm_delete_modal child-sandbox count copy (sandbox_live/components.ex:176-181); this view never passes `descendants`
    - Settings.usage_caps_input_slot/1 (settings.ex:89-98) under the default variant

related:
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/live/project_live/concurrency_input_component.ex
  - lib/lightning_web/live/components/project_deletion_modal.ex
  - lib/lightning_web/live/sandbox_live/components.ex
  - lib/lightning_web/components/sandbox_settings_banner.ex
  - lib/lightning_web/components/layout_components.ex
  - lib/lightning_web/components/new_inputs.ex
  - lib/lightning_web/components/pills.ex
  - lib/lightning_web/controllers/downloads_controller.ex
  - lib/lightning/projects.ex
  - lib/lightning/projects/project.ex
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/extensions/project_hook.ex
  - lib/lightning/policies/project_users.ex
  - lib/lightning/policies/sandboxes.ex
  - test/lightning_web/live/project_live_test.exs
  - test/lightning_web/live/project_live/sandbox_settings_test.exs
flows:
  - flow-export-project-yaml
  - flow-schedule-project-deletion
  - flow-sandbox-scheduled-deletion
---

## 1. Purpose

This is the first tab of project settings. Admins use it to keep a project's name and description
meaningful, and to switch off parallel run execution when a project's workflows must never run at
the same time. Every member uses it to export the project as code. Owners use it to wind a project
down, or to delete a sandbox they no longer need. Without it, a project's name and description
would go stale, overlapping runs couldn't be prevented project-wide, and shutting a project down
would need a superuser.

## 2. What it does

- **See the project**
  - Members see the project's (or sandbox's) name, environment and description, and for a sandbox a link to its parent
  - Nobody changes the project environment here
- **Change the project** (admins and owners)
  - Rename the project and edit its description
  - Switch parallel run execution off or back on for the whole project
- **Export the project**
  - Members export the project as YAML
- **Delete it** (owners)
  - Owners schedule a project for deletion after typing its name
  - Sandbox owners delete a sandbox after typing its name

**Straightforwardness: 3 of 5.** The edit and export parts are simple, but deletion does more than it says, and the sandbox delete dialog tells people the wrong thing.

### Most surprising behaviours

- **(2)** Deleting a sandbox here wipes it and all its data at once, but the dialog promises it will be kept for 7 days and can be restored. Anyone relying on that restore window loses their work. (6.1, S18)
- **(2)** Deleting a sandbox also deletes every sandbox made from it, with no warning in the dialog; the only hint is the message afterwards saying its "descendants" were deleted too. (6.1)
- **(3)** Scheduling a project for deletion takes effect straight away in practice: every trigger is switched off, every member gets an email, and anyone else with the project open is moved out of it, even though the data itself isn't purged for another 7 days. (S12, 4)
- **(3)** The name and parallel-execution sections share one form behind the scenes, so touching the parallel-execution switch may throw away an unsaved name change, and its Save button seems to be live before anything has changed. (6.1)
- **(3)** The name you type is turned into a lowercase, hyphenated version, and the preview can show a name (for example with underscores) that is then refused on save. (S02, 6.1)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_project` is an admin action),
`:138` (`:delete_project` is owner only), `:160-161` (admin actions need an owner or admin row; no
support fallback), `:134` (MFA unsatisfied denies everything); `lib/lightning/policies/sandboxes.ex`
moduledoc (`:delete_sandbox`: owner or admin of the sandbox or of its root, never a root project);
`downloads_controller.ex:13-19` (export needs `:access_project`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the panel | yes | yes | yes | yes | no | yes, when support access is on |
| Edit name and description | no | no | yes | yes | no | no |
| Switch parallel execution | no | no | yes | yes | no | no |
| Export project | yes | yes | yes | yes | no | yes, when support access is on |
| See the danger zone and open the delete modal | no | no | no | yes | no | no |
| Schedule a root project for deletion | no | no | no | yes | no | no |
| Delete a sandbox (UI) | no | no | no | yes, on the sandbox | no | no |
| Delete a sandbox (server, `confirm-delete`) | no | no | yes, on the sandbox or its root | yes, on the sandbox or its root | no | no |

**Preconditions beyond role**
- Edit and delete permissions are computed once at mount (`settings.ex:119-123`); `save` re-checks `:edit_project` at click time (`settings.ex:351-352`, `:744-749`).
- The project deletion modal is rendered only when `can_delete_project` and the project is not a sandbox (`settings.html.heex:304`); the sandbox modal only when `can_delete_project` and it is a sandbox (`settings.html.heex:296`).
- `confirm-delete` does not check `can_delete_project` itself; it relies on `Sandboxes.delete_sandbox/2` (`settings.ex:476-485`, `sandboxes.ex:814-820`), which refuses root projects and admits sandbox admins.
- Both deletion modals require the typed name to match before anything is deleted (`project.ex:276-280`, `settings.ex:283-296`).
- `save` only accepts `raw_name name description concurrency color`; privileged fields are dropped (`settings.ex:341-345`, `:355-358`).

## 4. What it touches

**Reads**: `projects` (and parent and root for a sandbox, `settings.ex:108-111`), `project_users`; for the sandbox modal, the sandbox's own name

**Writes**
- Save: `projects.name`, `projects.description`, `projects.concurrency`, `projects.color` via `Project.changeset/2` (`settings.ex:771-774`, `projects.ex:589-597`). No audit event: `Audit.derive_events` only covers support access, retention and MFA (`projects/audit.ex:20-39`).
- Schedule project deletion: every project trigger `enabled = false`, `projects.scheduled_deletion = now + purge_deleted_after_days` (`projects.ex:1639-1690`)
- Delete sandbox: hard delete of the sandbox, its child sandboxes, stored files, work orders, channel requests, jobs, triggers, workflows, project users, project credentials, OAuth clients, dataclips and the project row (`extensions/project_hook.ex:22-45`)

**Immediate side effects** (in the same request)
- Schedule deletion: email "Project scheduled for deletion" to every project user, sent inside the transaction (`projects.ex:1677-1689`, `user_notifier.ex:430-450`); see flow-schedule-project-deletion
- Schedule deletion: PubSub `ProjectDeletionScheduled` on the project topic (`projects.ex:1644`, `projects/events.ex:116-121`); open project pages leave (shared-project-scope)
- Delete sandbox: `Events.project_deleted` (`projects.ex:915`) and a sandbox-deleted PromEx event (`project_hook.ex:37-40`)
- Save: `ProjectHook.handle_project_validation/1` may add validation (`projects.ex:593`)

**Deferred side effects** (later, elsewhere)
- The nightly Oban `purge_deleted` sweep (02:45, `bootstrap.ex:312`) enqueues a purge for every project whose `scheduled_deletion` has passed, and the purge deletes it (`projects.ex:193-219`)
- Concurrency 1 makes the run queue execute at most one run at a time across the project (copy at `settings.html.heex:179-187`; enforcement is outside this view)

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- Deletion emails are delivered from inside the scheduling transaction (`projects.ex:1677-1689`); if the transaction later fails, members may still have been told
- Sandbox delete removes stored export files before the database rows (`project_hook.ex:47-62`)

**Depends on config**
- Route metadata `:concurrency_input` and `:usage_caps_input` (`settings.ex:237-246`)
- `purge_deleted_after_days` (modal copy, scheduled date, whether the purge cron runs)
- `project_hook` extension adapter

**Product limits** (limits a user would notice and that we intend to keep)
- Project description is at most 240 characters, stated under the field (`project.ex:107`, `settings.html.heex:154-156`)
- A scheduled project is kept for `purge_deleted_after_days` (default 7) before it is purged, stated in the modal (`project_deletion_modal.ex:103-106`, `:144-148`)

## 5. Scenarios

Verified against the `default` variant unless tagged.

```gherkin
Feature: Project setup
  In order to keep a project identifiable, control how its runs execute, and retire it cleanly
  As a member of a project
  I want to edit its identity, set its concurrency, export it and delete it

  @S01 @pending
  Scenario: Admin renames the project and edits its description
    # Value: a project's name and description can be kept accurate without a superuser.
    Given I am an admin on project "project-1"
    When I set "Project name" to "somename" and "Project description" to "some description"
    And I click "Save" in the identity section
    Then I see "Project updated successfully"
    And the project is named "somename" with description "some description"
    # settings.html.heex:107-167, settings.ex:351-363, :771-783; project_live_test.exs:1775-1804

  @S02 @pending
  Scenario: The name is turned into a URL-safe slug
    # Value: project names stay usable in URLs, exports and the CLI whatever people type.
    Given I am an admin on project "project-1"
    When I type "DEP-burundi-datafi" into "Project name"
    Then I see "Your project will be named dep-burundi-datafi."
    When I click "Save" in the identity section
    Then the project is named "dep-burundi-datafi"
    # settings.ex:299-323, settings.html.heex:122-128, pills.ex:98-105, helpers.ex:236-238
    # project_live_test.exs:1834-1855 (asserts the saved name; the preview text is not asserted)

  @S03 @pending
  Scenario: A name with no usable characters is refused
    # Value: a project can't be saved without a name.
    Given I am an admin on project "project-1"
    When I submit the identity form with "Project name" set to "!!!"
    Then I see "can't be blank"
    And the project is still named "project-1"
    # settings.ex:776-778, project.ex:155-157, helpers.ex:182-199; project_live_test.exs:1857-1882

  @S04 @pending
  Scenario: A description over 240 characters is flagged before saving
    # Value: people learn the limit while typing instead of losing their text on save.
    Given I am an admin on project "project-1"
    When I type a 250 character description
    Then I see "should be at most 240 character(s)"
    And the identity "Save" button is disabled
    # project.ex:107, settings.html.heex:162; project_live_test.exs:1742-1773

  @S05 @pending
  Scenario: The project environment cannot be changed here
    # Value: the environment that decides which credential values runs use can't be changed by accident.
    Given I am an admin on project "project-1" with environment "staging"
    Then the "Project environment" field is disabled
    When "save" is sent with env "main"
    Then I see "Project updated successfully"
    And the project environment is still "staging"
    # settings.html.heex:133-143, settings.ex:345, :355-358; project_live_test.exs:1806-1832

  @S06 @pending
  Scenario: A crafted save cannot set privileged fields
    # Value: MFA, support access, deletion and parentage can only change through their own gated controls.
    Given I am an admin on project "project-1"
    When "save" is sent with "raw_name" "renamed", "requires_mfa" true, "allow_support_access" true, "scheduled_deletion" set and "parent_id" of another project
    Then the project is named "renamed"
    And it does not require MFA, does not allow support access, is not scheduled for deletion and has no parent
    # settings.ex:341-358; project_live_test.exs:1884-1920

  @S07 @pending
  Scenario Outline: Members below admin see the identity read-only
    # Value: only people trusted with project administration can rename it or change how it runs.
    Given I am a <role> on project "project-1"
    When I open project settings
    Then "Project name", "Project description" and the concurrency switch are disabled
    And the identity "Save" button is disabled
    And I see "Role based permissions: You cannot modify this project's basic settings, but you can export a copy."
    When "save" is sent anyway
    Then I see "You are not authorized to perform this action."
    # settings.html.heex:68-79, :118, :148, :162, :205, layout_components.ex:590-592, :620-626, settings.ex:351-363, :751-765
    # project_live_test.exs:1946-1975 (viewer only; editor is not tested)
    Examples:
      | role   |
      | viewer |
      | editor |

  @S08 @pending
  Scenario: A support user without a membership cannot edit project details
    # Value: support staff can look but not rename or reconfigure a customer's project.
    Given I am a support user and project "project-1" allows support access
    And I am not a member of it
    When I open project settings
    Then "Project name" and "Project description" are disabled
    When "save" is sent anyway
    Then I see "You are not authorized to perform this action."
    # project_users.ex:160-161; project_live_test.exs:1977-2009

  @S09 @pending
  Scenario: Admin disables parallel execution
    # Value: a project whose workflows must not overlap can be limited to one run at a time.
    Given I am an admin on project "project-1" with parallel execution allowed
    When I switch on "Disable parallel execution"
    Then I see the warning "Disabling parallel run execution may significantly reduce the overall throughput of your project."
    When I click "Save" in the concurrency section
    Then I see "Project updated successfully"
    And the project concurrency is 1
    # concurrency_input_component.ex:8-25, new_inputs.ex:806-861, settings.html.heex:191-240
    # project_live_test.exs:1922-1944 (asserts the saved value; the warning is not asserted)

  @S10 @pending
  Scenario: Admin re-enables parallel execution
    # Value: the one-at-a-time limit can be lifted once it is no longer needed.
    Given I am an admin on project "project-1" with concurrency 1
    When I switch off "Disable parallel execution"
    And I click "Save" in the concurrency section
    Then I see "Project updated successfully"
    And the project has no concurrency limit
    # new_inputs.ex:815-822 (toggles between "" and "1"), settings.ex:351-363

  @S11 @pending
  Scenario: Any member can export the project
    # Value: anyone on the project can take a copy of it as code, even without edit rights.
    Given I am a viewer on project "project-1"
    When I open project settings
    Then I see "Export your project as code, to save this version or edit your project locally."
    And "Export project" links to "/download/yaml?id=<project_id>" in a new tab
    And clicking it starts the flow "flow-export-project-yaml"
    # settings.html.heex:252-266; project_live_test.exs:197-211

  @S12 @pending
  Scenario: Owner schedules the project for deletion
    # Value: an owner can retire a project themselves, with a grace period before data is purged.
    Given I am the owner of project "project-1"
    When I open project settings
    Then I see "Deleting your project is irreversible"
    When I click "Delete project"
    Then I am on "/projects/<project_id>/settings/delete"
    And I see "Enter the project name to confirm deletion: project-1"
    And I see that the project will be deleted "7 day(s) from today"
    When I type "project-1" into "Project name" and click "Delete project"
    Then I am on "/projects"
    And I see "Project scheduled for deletion"
    And the project is scheduled for deletion 7 days from now with all its triggers disabled
    And the flow "flow-schedule-project-deletion" has started for "project-1"
    # settings.html.heex:267-294, :304-311, project_deletion_modal.ex:58-88, :95-106, :131-180, projects.ex:1639-1690
    # project_live_test.exs:168-195

  @S13 @pending
  Scenario: A mistyped name does not delete the project
    # Value: a project can't be deleted by a slip of the keyboard.
    Given I am the owner of project "project-1" on its delete modal
    When I type "project-2" into "Project name" and submit
    Then I see "doesn't match the project name"
    And the project is not scheduled for deletion
    # project_deletion_modal.ex:58-65, :85-87, project.ex:276-280; project_test.exs:165 (changeset only)

  @S14 @pending
  Scenario: Cancelling the delete modal returns to settings
    # Value: backing out of deletion is one click and leaves the project untouched.
    Given I am the owner of project "project-1" on its delete modal
    When I click "Cancel"
    Then I am on "/projects/<project_id>/settings"
    And the project is not scheduled for deletion
    # project_deletion_modal.ex:90-93, :171-178, settings.html.heex:310

  @S15 @pending
  Scenario Outline: Only owners can reach project deletion
    # Value: admins and editors can't shut down a project they don't own.
    Given I am a <role> on project "project-1"
    When I open project settings
    Then I do not see "Deleting your project is irreversible"
    When I visit "/projects/<project_id>/settings/delete"
    Then I am on "/projects/<project_id>/settings"
    And I see "You are not authorize to perform this action"
    # settings.ex:119-121, :262-267, settings.html.heex:267; project_live_test.exs:213-237
    Examples:
      | role   |
      | admin  |
      | editor |
      | viewer |

  @S16 @pending
  Scenario: An admin cannot hard-delete a root project through the sandbox event
    # Value: a crafted request can't skip the owner-only, grace-period deletion and wipe a project outright.
    Given I am an admin on root project "root-project" with a workflow
    When "confirm-delete" is sent with name "root-project"
    Then I am sent back to settings with "You don't have permission to delete this sandbox"
    And the project and its workflow still exist and it is not scheduled for deletion
    # settings.ex:476-505, sandboxes.ex:814-820; sandbox_settings_test.exs:60-89

  @S17 @pending
  Scenario: A sandbox's setup tab identifies it within its parent
    # Value: people working in a sandbox can see which project it belongs to and that changes here stay local.
    Given I am the owner of sandbox "sandbox-test" under "parent-project"
    When I open its settings
    Then I see "Sandbox setup" and "Sandbox Identity"
    And I see "Identifies this sandbox within its parent:" with a link to "parent-project" settings
    And I see "Changes you make here only apply to this sandbox and do not sync to the parent project on merge."
    And the danger zone button reads "Delete sandbox"
    # settings.html.heex:68-104, :271-291, sandbox_settings_banner.ex:30-38
    # sandbox_settings_test.exs:45-58, :116-155

  @S18 @pending
  Scenario: Sandbox owner deletes the sandbox
    # Value: a finished experiment can be removed and the owner lands back in the workspace it came from.
    Given I am the owner of sandbox "sandbox-test" under "parent-project"
    When I visit "/projects/<sandbox_id>/settings/delete"
    And I type "sandbox-test" into "Sandbox name" and click "Delete sandbox"
    Then I am on "/projects/<parent_id>/w"
    And I see "Sandbox sandbox-test and all its associated descendants deleted"
    And the sandbox no longer exists
    # settings.ex:269-276, :476-491, settings.html.heex:296-303, project_hook.ex:22-45; sandbox_settings_test.exs:158-172

  @S19 @pending
  Scenario: A mistyped sandbox name does not delete it
    # Value: a sandbox can't be deleted by a slip of the keyboard.
    Given I am the owner of sandbox "sandbox-test" on its delete modal
    When I type "wrong" into "Sandbox name"
    Then I see "does not match the sandbox name"
    And "Delete sandbox" is disabled
    When I submit the form anyway
    Then I see "does not match the sandbox name"
    And the sandbox still exists
    # settings.ex:283-296, :463-474, :520-524, sandbox_live/components.ex:218-225; sandbox_settings_test.exs:174-201

  @S20 @pending
  Scenario: Closing the sandbox delete modal returns to settings
    # Value: backing out of sandbox deletion is one click.
    Given I am the owner of sandbox "sandbox-test" on its delete modal
    When I click the close button
    Then I am on "/projects/<sandbox_id>/settings"
    # settings.ex:457-461, sandbox_live/components.ex:150-170; sandbox_settings_test.exs:203-213

  @S21 @pending
  Scenario Outline: A failed sandbox delete says so and keeps the sandbox
    # Value: people are never left thinking a sandbox is gone when it isn't.
    Given I am the owner of sandbox "sandbox-test" on its delete modal
    And deleting it fails with <reason>
    When I confirm with "sandbox-test"
    Then I am on "/projects/<sandbox_id>/settings"
    And I see "<message>"
    And the sandbox still exists
    # settings.ex:493-516; sandbox_settings_test.exs:215-256 (failures stubbed with Mimic)
    Examples:
      | reason        | message                                            |
      | unauthorized  | You don't have permission to delete this sandbox   |
      | another error | Could not delete sandbox. Please try again later.  |
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Deleting a sandbox from settings hard-deletes it at once (`delete_sandbox` → `Projects.delete_project`), but the modal says it "will be retained for 7 days before being permanently removed. You can restore it from the sandbox list during that window." The danger zone text above it says the opposite ("irreversible") | `settings.ex:480-483`, `sandboxes.ex:814-816`, `project_hook.ex:22-45`, `sandbox_live/components.ex:197-201`, `settings.html.heex:272-275` | a promise of a restore window that doesn't exist; the sandbox and its data are gone immediately | fix |
| Sandbox modal never warns about child sandboxes: settings does not pass `descendants`, so the count is always 0, yet the delete removes them and the flash says "and all its associated descendants deleted" | `settings.html.heex:297-302`, `sandbox_live/components.ex:140`, `:147`, `:176-181`, `project_hook.ex:23`, `settings.ex:487-488` | no warning that child sandboxes will also be deleted, then a flash saying they were | fix |
| The concurrency "Save" button and the "Heads Up!" warning are gated on `Enum.any?(@project_changeset.changes)`, but `raw_name` is virtual and nil in the data, so the changeset always carries a `raw_name` change from mount and every `validate`. Inferred from code, not run | `settings.ex:206-207`, `:304`, `settings.html.heex:212-215`, `:234-237`, `project.ex:38`, `:138-142` | concurrency "Save" enabled for admins before anything is changed; the throughput warning shows on load whenever concurrency is already 1 | fix |
| The two forms on the tab share one changeset. Typing in the identity form enables the concurrency "Save" (which would not save the name), and toggling concurrency rebuilds the changeset from the concurrency params only, dropping identity validation errors and resetting `@name` (the name input's value) to the saved name | `settings.html.heex:107-111`, `:192-198`, `settings.ex:299-323` | unsaved name edits and their errors can vanish after touching the concurrency switch | fix |
| After a successful save, `project_changeset` and `name` are not rebuilt from the saved project | `settings.ex:775-780` | the form keeps showing the pre-save changeset state; Save buttons stay enabled | fix |
| Unauthorised `/settings/delete` flash has a typo | `settings.ex:266` | "You are not authorize to perform this action" | fix |
| The name preview keeps underscores, dots and non-ASCII letters (`url_safe_name`), but the name must match `^[a-z\-\d]+$` | `helpers.ex:221-226`, `project.ex:108`, `settings.html.heex:124-128` | "Your project will be named my_project." next to a "has invalid format" error | fix |
| `human_readable_grace_period` does `grace_period > 0` without a nil guard; `nil > 0` is true in Erlang term order | `project_deletion_modal.ex:103-106`, `config.ex:80-82` | "nil day(s) from today" if the setting is ever unset (bootstrap defaults it to 7, so not under `default`) | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| `/settings` lives in the config-injected `:services` live_session and `/settings/delete` in `:default`, so opening and closing the delete modal are full page loads, and the unauthorised bounce is a `push_patch` across sessions | `router.ex:291-292`, `:339-355`, `settings.ex:267`, `project_deletion_modal.ex:92`, `settings.ex:459` | decide |
| On `/settings/delete` the route metadata is not read, so the concurrency switch is missing behind the modal, and other tabs' lists (`project_users`, `webhook_auth_methods`) are empty | `settings.ex:233-260` (only `:index` assigns them), `:262-281` | decide |
| The project deletion modal's "Delete project" button is enabled before anything is typed (an empty deletion changeset is valid); submitting empty is still refused | `project_deletion_modal.ex:37-41`, `:167` | decide |
| Deletion confirmation compares the typed name with the hidden `name` field the form submits, not the stored name (Ecto `validate_confirmation` reads params) | `project_deletion_modal.ex:158-159`, `project.ex:276-280` | fix |
| Name confirmation validates on blur only | `project_deletion_modal.ex:154` | decide |
| The name input's value is `@name`, the derived slug, so after blur the field shows "my-project" instead of what was typed | `settings.html.heex:114-120`, `settings.ex:322` | decide |
| Element id `heads-up-description` is used by both this tab's concurrency warning and the data storage tab's erase-all warning; both panels are in the DOM | `settings.html.heex:216`, `:983` | fix |
| Under `no-concurrency-slot` the "Concurrency Override" card and its "Save" still render with no control | `settings.html.heex:171-240` | decide |
| `validate` without a `project` key is ignored (reached when a form has no inputs, e.g. the concurrency form under `no-concurrency-slot`) | `settings.ex:325-328` | preserve |
| Under `purge-immediate` the project is scheduled for "today", but the purge cron is only registered when the setting is above 0, so the project stays scheduled and inaccessible indefinitely | `projects.ex:1655-1659`, `bootstrap.ex:307-316` | decide |
| Saving name, description or concurrency writes no audit event | `projects/audit.ex:20-39` | decide |
| Sandbox delete modal closes on click-away and Escape (pushes `close-delete-modal`, a full navigation); the project deletion modal does neither | `sandbox_live/components.ex:150-158`, `project_deletion_modal.ex:112` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `ProjectDeletionModal` branch for an already scheduled project (`delete_project_async`, "Project deletion started…") | `project_deletion_modal.ex:66-74`, `:96-97` | the project scope gate refuses scheduled projects before this view mounts (`scope.ex:112-117`); reachable only from the superuser projects list (`project_live_test.exs:322-356`) |
| `save_project` `{:error, :not_related_to_project}` flash "Changes couldn't be saved, please try again" for this tab | `settings.ex:782-785`, `projects.ex:610-614` | only a failing non-project Multi step reaches it, and this tab's fields create no audit step |
| `usage_caps_input_slot/1` | `settings.ex:89-98`, `settings.html.heex:245-250` | no OSS route metadata sets `:usage_caps_input` (`config/config.exs:52-57`); only under `usage-caps-slot` |
| `confirm_delete_modal` child sandbox copy | `sandbox_live/components.ex:176-181` | `descendants` never passed here (see 6.1) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Scheduling deletion updates triggers one Multi step each and emails every member inside one transaction | `projects.ex:1661-1689` | no, unless a large project makes the request slow | decide |
| Purge sweep runs nightly at 02:45, so actual deletion is up to a day after `scheduled_deletion` | `bootstrap.ex:312`, `projects.ex:208-219` | yes, via the email's deletion date | preserve |
| Sandbox delete runs synchronously in the LiveView process (work orders and dataclips in batches of 1000) | `project_hook.ex:22-45`, `projects.ex:1696-1714` | yes, the modal can hang on a large sandbox | decide |

### 6.5 Things seen but not understood

- The UI shows sandbox deletion only to the sandbox's owner (`can_delete_project`, `:delete_project` is owner only), but the server path accepts sandbox admins and root owners or admins (`sandboxes.ex` policy). A sandbox admin can delete from the sandboxes list but not from here. Which gate is intended? (decide)
- `color` is accepted by `save` (`settings.ex:345`) but there is no colour control on this tab. Probably set elsewhere (sandboxes); not followed. (decide)
- Root project names have no uniqueness constraint visible here; `projects_unique_child_name` covers siblings only (`project.ex:121`, `20250824190735_add_sandbox_fields_to_projects.exs:16`). Not verified whether another index exists. (decide)
- Hard-deleting a sandbox emits `project_deleted` but not `ProjectDeletionScheduled`; whether other open sandbox pages are told is not followed. (decide)
- Concurrency enforcement in the run queue is outside this view and was not followed. (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|
| Missing concurrency switch and empty tab lists behind the delete modal | side effect of `apply_action(:delete)` not assigning index data; the rebuild should render the tab normally under the modal | cataloguer (proposed) | 2026-10-14 |

## 8. Open questions

- Should deleting a sandbox from settings schedule it (as the modal promises) or hard-delete it (as the danger zone says)?
- Who may delete a sandbox from its own settings: owners only, or the policy's owners and admins of the sandbox or root?
- Under `purge-immediate`, should scheduled projects ever be purged?
- Should identity and concurrency changes be audited?

## Proposed flows

- `flow-export-project-yaml`: "Export project" opens `/download/yaml?id=<project_id>` in a new tab; `DownloadsController` checks `:access_project`, returns `project-<id>.yaml`, or on a name collision redirects that new tab back to `/projects/<id>/settings` with the error flash. Surfaces: project-settings-setup, controller:downloads-project-yaml (`downloads_controller.ex:10-45`), project-settings-setup.
- `flow-schedule-project-deletion`: confirming deletion here disables triggers, emails every member "Project scheduled for deletion", broadcasts `ProjectDeletionScheduled` so other members' open pages leave the project, and the nightly purge deletes the project after the grace period. Surfaces: project-settings-setup, email:project-deletion-scheduled (`user_notifier.ex:430-450`), pubsub:project:<project_id> ProjectDeletionScheduled (receiving end in shared-project-scope), projects-index (`/projects`), worker:Lightning.Projects purge_deleted.

## Proposed shared

- `shared-project-deletion-modal`: `LightningWeb.Components.ProjectDeletionModal`, the type-the-name deletion modal with schedule and "delete now" branches. Surfaces: project-settings-setup (schedule branch only), superuser projects list `ProjectLive.Index :delete` (both branches).
- `shared-sandbox-settings-banner`: `sandbox_settings_banner/1` with its local, editable and inherited variants, rendered at the top of every settings tab when the project is a sandbox. Surfaces: every project settings tab (`settings.html.heex:80-84` and its siblings).
- `shared-settings-section-header`: `LayoutComponents.section_header/1` with the "Role based permissions: You cannot modify this project's …" message shown when the viewer lacks the tab's permission. Surfaces: every project settings tab.

## Lead resolution (batch 1)

- Both flows created as proposed.
- `shared-project-deletion-modal` created. `shared-sandbox-settings-banner` and `shared-settings-section-header` merged into `shared-project-settings-tab-chrome`.
- `drop` dispositions changed to `decide`: cuts are for a human to make.
