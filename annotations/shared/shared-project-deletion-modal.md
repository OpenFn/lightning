---
id: shared-project-deletion-modal
type: shared
title: Project deletion modal
status: not-started
owner:

trigger:
  old_route: any LiveView that renders LightningWeb.Components.ProjectDeletionModal (today /projects/:project_id/settings/delete and /settings/projects/:id/delete)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host decides who sees it; the modal does no authorization of its own (project_deletion_modal.ex:9-74)
    - project-settings-setup renders it for an owner on a non-sandbox project (settings.html.heex:304-311, settings.ex:262-267)
    - admin-projects renders it for a superuser on any project (index.ex:7, index.html.heex:16-24)

inherits: []

url_params: []                               # the modal reads none; hosts own their /delete routes

config_variants:
  default: { purge_deleted_after_days: 7 }   # read under this variant (bootstrap.ex:272-278)
  purge-immediate: { purge_deleted_after_days: 0 }   # copy says "today"; bootstrap.ex:307 registers no purge cron

inventory:
  routes: []                                 # host routes are owned by project-settings-setup and admin-projects
  events:
    - LightningWeb.Components.ProjectDeletionModal#validate
    - LightningWeb.Components.ProjectDeletionModal#delete
    - LightningWeb.Components.ProjectDeletionModal#close_modal
  js_hooks:
    - ModalHook (LightningWeb.Components.Modal, modal.ex:37)
    - client-side hide_modal on Escape and click-away (modal.ex:45-48, :63-70)
  policies: []                               # none in the component; see section 3
  workers:
    - Lightning.Projects (Oban, type purge_deleted, per-project job inserted by the delete-now branch; projects.ex:929-934)
  api_endpoints: []
  emails:
    - email:project-deletion-scheduled       # sent by the schedule branch; owned by flow-schedule-project-deletion
  config:
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
  not_reachable_here:
    - delete-now branch from project-settings-setup (project_deletion_modal.ex:69-70); a scheduled project fails the scope gate before settings mounts (shared-project-scope S04)

related:
  - project-settings-setup                   # schedule branch only
  - admin-projects                           # both branches
  - lib/lightning_web/live/components/project_deletion_modal.ex
  - lib/lightning_web/live/components/modal.ex
  - lib/lightning/projects.ex
  - lib/lightning/projects/project.ex
  - lib/lightning/config.ex
  - lib/lightning/config/bootstrap.ex
  - test/lightning_web/live/project_live_test.exs
  - test/lightning/projects/project_test.exs
flows:
  - flow-schedule-project-deletion
---

## 1. Purpose

The last step before a whole project is wound down, used by owners from project settings and by
superusers from the admin projects list. It makes the person type the project's name and tells them
what will happen and when, so a project full of health data is not shut down or purged by a
misclick or on the wrong row.

## 2. What it does

- Shows the project name to type and when the project will be deleted
- Refuses to act until the typed name matches
- Schedules an unscheduled project for deletion and returns to the host's "after delete" page
- Starts an immediate purge of an already scheduled project and returns to the host's "after delete" page
- Cancel or the close button returns to the host's "cancel" page with nothing changed

## 3. Who can do what

The component checks no policy (`project_deletion_modal.ex:9-74`). Who reaches it is entirely the
host's decision, so this matrix is the union of the inheriting views' gates.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support |
|--------|--------|--------|-------|-------|--------------------|---------|
| See the modal (project settings) | no | no | no | yes, non-sandbox | no | no |
| See the modal (admin projects list) | no | no | no | no | yes | no |
| Schedule deletion | no | no | no | yes (settings) | yes (admin) | no |
| Purge now (project already scheduled) | no | no | no | no | yes (admin) | no |

Sources: `settings.ex:119-121`, `:262-267`, `settings.html.heex:304` (`:delete_project` is owner
only, `policies/project_users.ex:138`); `index.ex:7`, `hooks.ex:40-53` (`:access_admin_space`).

**Preconditions beyond role**
- The typed name must equal the submitted `name` field (`project.ex:276-280`, `project_deletion_modal.ex:33-38`); see 6.1 for what that compares.
- The branch is picked from `project.scheduled_deletion` as loaded by the host, not re-read on submit (`project_deletion_modal.ex:68-74`).
- Any host that renders the modal must gate it itself; the modal would delete for anyone it is rendered to.

## 4. What it touches

**Reads**: the `project` assign passed by the host; `purge_deleted_after_days` config (`project_deletion_modal.ex:76-79`)

**Writes**
- Schedule branch: via `Projects.schedule_project_deletion/1`, project triggers disabled and `projects.scheduled_deletion` set (`projects.ex:1639-1690`); detail owned by flow-schedule-project-deletion
- Delete-now branch: inserts an Oban job `{project_id, type: purge_deleted}`, max 3 attempts (`projects.ex:929-934`)

**Immediate side effects** (in the same request)
- Schedule branch: email to every member and `ProjectDeletionScheduled` broadcast (handoff to flow-schedule-project-deletion; `projects.ex:1644`, `:1677-1689`)
- Flash and `push_navigate` to the host's `save_return_to` (`project_deletion_modal.ex:40-53`)

**Deferred side effects** (later, elsewhere)
- Delete-now: the purge job deletes the project (`projects.ex:194-205`); schedule: the nightly sweep does (flow-schedule-project-deletion S07)

**External, non-transactional effects**
- none in the component; the schedule branch's emails leave from inside the transaction (owned by the flow)

**Depends on config**
- `purge_deleted_after_days`: the grace-period sentence (`project_deletion_modal.ex:76-79`, `:117-121`) and the scheduled date (`projects.ex:1655-1659`)

**Product limits**
- The modal states the grace period: "N day(s) from today", or "today" when N is 0 (`project_deletion_modal.ex:78`)

## 5. Scenarios

Verified against `default`. Hosts inherit these instead of restating them; project-settings-setup
S13 and S14 cover the same ground as S02 and S05 here and could point to them.

```gherkin
Feature: Project deletion modal
  In order to shut down the right project, on purpose
  As a project owner or a superuser
  I want to confirm deletion by typing the project's name

  @S01 @pending
  Scenario: The modal names the project and the grace period
    # Value: the person deleting sees exactly which project goes, and when its data is removed, before committing.
    Given the modal is open for project "project-1"
    Then I see "Enter the project name to confirm deletion: project-1"
    And I see "The whole project will be deleted along with all workflows and work order history, 7 day(s) from today."
    # project_deletion_modal.ex:76-79, :113-121; project_live_test.exs:180-182 (prompt only)

  @S02 @pending
  Scenario: A mistyped name is refused
    # Value: a project can't be shut down by a slip of the keyboard or on the wrong row.
    Given the modal is open for project "project-1"
    When I type "project-2" into "Project name" and leave the field
    Then I see "doesn't match the project name"
    And "Delete project" is disabled
    When I submit the form
    Then the project is not scheduled for deletion and no purge job is enqueued
    # project_deletion_modal.ex:18-29, :32-38, :58-59, :127, :140, project.ex:276-280
    # project_test.exs:146-167 (changeset only); project_live_test.exs:259-263 asserts only that the prompt still renders

  @S03 @pending
  Scenario: Confirming an unscheduled project schedules it and returns to the host
    # Value: a correct confirmation retires the project in one step, with the grace period the copy promised.
    Given the modal is open for unscheduled project "project-1" with "after delete" page "/projects"
    When I type "project-1" into "Project name" and click "Delete project"
    Then I am on "/projects"
    And I see "Project scheduled for deletion"
    And the flow "flow-schedule-project-deletion" has started for "project-1"
    # project_deletion_modal.ex:38-39, :49-53, :68-74, projects.ex:1639-1652; project_live_test.exs:168-195, :239-276

  @S04 @pending
  Scenario: Confirming an already scheduled project starts the purge now
    # Value: purging before the grace period ends sits behind the same type-the-name check as scheduling.
    Given project "project-1" is scheduled for deletion
    And the modal is open for it with "after delete" page "/settings/projects"
    When I type "project-1" into "Project name" and click "Delete project"
    Then I am on "/settings/projects"
    And I see "Project deletion started. This may take a while to complete."
    And a purge job for "project-1" is enqueued
    # handoff to flow-schedule-project-deletion S12
    # project_deletion_modal.ex:39-47, :68-71, projects.ex:929-934; project_live_test.exs:322-355

  @S05 @pending
  Scenario Outline: Backing out returns to the host and changes nothing
    # Value: abandoning a deletion is one click and leaves the project untouched.
    Given the modal is open for project "project-1" with "cancel" page "<cancel_page>"
    When I click <control>
    Then I am on "<cancel_page>"
    And the project is not scheduled for deletion
    # project_deletion_modal.ex:64-66, :92-101, :144-151, settings.html.heex:310, index.html.heex:22; project_live_test.exs:278-306 (Cancel, admin host)
    Examples:
      | control  | cancel_page                       |
      | "Cancel" | /projects/<project_id>/settings   |
      | "Close"  | /settings/projects                |
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The confirmation compares `name_confirmation` with the submitted hidden `name` field, not the stored name (Ecto `validate_confirmation` reads params; the unit test passes `"name"` explicitly). A crafted payload with matching `name` and `name_confirmation` passes for any project | `project_deletion_modal.ex:131-132`, `:33-38`, `project.ex:276-280`; `project_test.exs:151-154` | nothing in the normal UI; the safety check is only as strong as the browser's hidden field | fix |
| Delete-now copy still promises the grace period: an already scheduled project gets "will be deleted ... 7 day(s) from today", then the confirm purges it immediately | `project_deletion_modal.ex:117-121`, `:68-71` | a superuser is told the data stays for a week, then it is gone within minutes | fix |
| The branch is chosen from the host's possibly stale `project`: if another superuser cancels the deletion after the modal opened, "Delete now" still enqueues a purge, and the purge job does not re-check `scheduled_deletion` | `project_deletion_modal.ex:68-74`, `index.ex:82-93`, `projects.ex:194-205` | a project whose deletion was just cancelled is hard-deleted | fix |
| On a scheduling failure the modal assigns the Multi's failed changeset (possibly a `Trigger` changeset) as the form; errors land on fields the form does not render | `project_deletion_modal.ex:55-56`, `projects.ex:1649-1650` | clicking "Delete project" appears to do nothing, with no message | fix |
| Under `purge-immediate` the copy says the project is deleted "today", but no purge cron is registered, so it never is (email side is flow-schedule-project-deletion 6.1) | `project_deletion_modal.ex:78`, `bootstrap.ex:307` | a promise of same-day deletion that never happens | fix |
| Escape and click-away hide the modal client-side (the component leaves `close_on_keydown` and `close_on_click_away` at their `true` defaults) without pushing `close_modal`, so the URL stays on the `/delete` route | `project_deletion_modal.ex:85`, `modal.ex:16-17`, `:45-48`, `:63-70` | the modal disappears but the address bar still says `/delete`; a reload reopens it | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Delete project" is enabled before anything is typed (an empty deletion changeset is valid); submitting empty is still refused | `project_deletion_modal.ex:13`, `:140`, `project.ex:276-280` | decide |
| Name validates on blur only (`phx-debounce="blur"`), so the button state lags typing | `project_deletion_modal.ex:127` | decide |
| `update/2` rebuilds an empty changeset every time the host re-renders, clearing any validation error | `project_deletion_modal.ex:10-15` | decide |
| A hidden `id` field is rendered and submitted but never cast | `project_deletion_modal.ex:131`, `project.ex:278` | decide |
| Copy says deletion will "disable all jobs"; scheduling disables triggers, jobs are untouched | `project_deletion_modal.ex:118-119`, `projects.ex:1661-1672` | fix |
| "N day(s) from today" is approximate: the nightly sweep at 02:45 purges on the first run after the date, so up to a day later | `project_deletion_modal.ex:78`, `bootstrap.ex:312`, `projects.ex:208-212` | decide |
| `human_readable_grace_period` has no nil guard (`nil > 0` is true in term order); bootstrap defaults to 7, so unreachable under `default` | `project_deletion_modal.ex:76-79`, `config.ex:80-82` | fix |
| Same title, button label and form id (`scheduled_deletion_form`, shared with the user deletion modal) in both branches; nothing on screen says which action will run | `project_deletion_modal.ex:88-90`, `:110`, `:142`, `user_deletion_modal.ex:167` | decide |
| `phx-disable-with="Deleting..."` on the confirm button | `project_deletion_modal.ex:139` | preserve |
| The delete-now branch `{:ok, _} = Oban.insert(...)` raises on an insert failure rather than returning an error | `projects.ex:929-934` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Delete-now branch when hosted by project settings | `project_deletion_modal.ex:69-70` | scheduled projects fail the scope gate before settings mounts (shared-project-scope S04) |
| `nil` grace period wording | `project_deletion_modal.ex:76-79` | bootstrap always sets an integer (`bootstrap.ex:272-278`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Purge job: max 3 attempts, `:background` queue | `projects.ex:6-8`, `:929-934` | yes, "This may take a while to complete." | preserve |

### 6.5 Things seen but not understood

- Whether the owner's settings page, which also receives `ProjectDeletionScheduled`, overrides this modal's "Project scheduled for deletion" flash (flow-schedule-project-deletion 6.5). (decide)
- The setup cataloguer's note about a grace period that sandbox deletion doesn't honour refers to `SandboxLive.Components.confirm_delete_modal`, not this component; it stays with project-settings-setup. This modal, opened on a sandbox from admin-projects, does honour the grace period but skips the sandbox cascade (flow-schedule-project-deletion 6.2). (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should delete-now have its own copy and button label, and re-check that the project is still scheduled before purging?
- Should the name check compare against the stored name rather than a submitted field?
- Should Escape and click-away close the modal through `close_modal` like Cancel does?

## Proposed flows

none (references flow-schedule-project-deletion for S03 and S04)

## Proposed shared

none

## Summary

- Scenarios: 5 (S01 to S05), all `@pending`.
- Section 6: 6.1 has 6, 6.2 has 10, 6.3 has 2, 6.4 has 1, 6.5 has 2.
- Flows: references flow-schedule-project-deletion (S03, S04 hand off to it); none proposed.
- Shared: references shared-project-scope S04; none proposed.
- Unsure: Escape and click-away behaviour on reload is read from code, not run; project-settings-setup S13, S14 and its modal 6.x rows overlap this file; admin-projects has no annotation yet.
