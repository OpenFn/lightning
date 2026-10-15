---
id: flow-sandbox-scheduled-deletion
type: flow
title: Delete a sandbox
status: not-started
owner:

trigger:
  entry: sandboxes-index                   # project-settings-setup also starts it (its S18), with a hard delete
  exit: sandboxes-index                    # of the deleted sandbox's parent when the viewer was inside the subtree; the settings path ends on workflows-index of the root
  surfaces:
    - sandboxes-index
    - project-settings-setup
    - pubsub:project_events:<subtree ids>#ProjectDeletionScheduled
    - controller:webhooks
    - workflows-index
    - oban:purge_deleted
    - workflow-editor-canvas   # added by lead (link lint)
  reachable_when:
    - sandboxes-index: the row is a sandbox (not the workspace root), not already scheduled, and the viewer is owner or admin on it or on the root (index.ex:107-127, :718-735; policies/sandboxes.ex:155-166)
    - project-settings-setup: the project is a sandbox and the viewer is its owner (settings.ex:262-276, settings.html.heex:296-303)

inherits:
  - shared-project-scope            # S10, S11 are the receiving end of the broadcast; S04 refuses a scheduled sandbox on any later visit

url_params:
  - name: /projects/:project_id/settings/delete
    set_by: "Delete sandbox" in the sandbox's setup danger zone (settings.html.heex:280-291)
    effect: opens the sandbox confirm modal (owned by project-settings-setup)

config_variants:
  default: { purge_deleted_after_days: 7 }   # read under this variant (bootstrap.ex:273-278)
  purge-immediate: { purge_deleted_after_days: 0 }   # scheduled date is now, and bootstrap.ex:306-316 registers no purge cron
  experimental-features: { user.experimental_features: true }   # changes where an open page goes (hooks.ex:295-300)

inventory:
  routes:
    - live /projects/:project_id/sandboxes  SandboxLive.Index :index   # owned by sandboxes-index
    - live /projects/:project_id/settings/delete  ProjectLive.Settings :delete   # owned by project-settings-setup
  events:
    - SandboxLive.Index#open-delete-modal
    - SandboxLive.Index#confirm-delete
    - SandboxLive.Index#cancel-sandbox-deletion
    - ProjectLive.Settings#confirm-delete
  js_hooks: []
  policies:
    - Lightning.Policies.Sandboxes (:delete_sandbox, :cancel_scheduled_deletion)
    - Lightning.Policies.ProjectUsers (:delete_project, the settings UI gate)
    - Lightning.Projects.Scope (still_operable/1)
  workers:
    - Lightning.Projects (Oban, queue :background, args type purge_deleted; nightly sweep and per-project job)
  api_endpoints:
    - POST /i/:webhook (refuses a disabled trigger)
  emails: []
  config:
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
    - Lightning.Extensions.project_hook (handle_delete_project)
  not_reachable_here:
    - WorkflowChannel#archive_sandbox (workflow_channel.ex:501-513); a third entry into Sandboxes.schedule_sandbox_deletion/2 from the editor, see 6.5
    - Events.project_deleted/1 (events.ex:88-93); fired by the hard delete and the purge, no subscriber in lib/

related:
  - flow-schedule-project-deletion   # root-project path; shares Projects.delete_project/1, the purge worker and the Scope gate
  - flow-sandbox-merge               # a merge ends by calling the same schedule_sandbox_deletion (index.ex:1196)
  - lib/lightning/projects/sandboxes.ex
  - lib/lightning/policies/sandboxes.ex
  - lib/lightning/projects/scope.ex
  - lib/lightning/projects/events.ex
  - lib/lightning/projects.ex
  - lib/lightning/extensions/project_hook.ex
  - lib/lightning/config/bootstrap.ex
  - lib/lightning_web/live/sandbox_live/index.ex
  - lib/lightning_web/live/sandbox_live/components.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/hooks.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/controllers/webhooks_controller.ex
  - test/lightning/sandboxes_test.exs
  - test/lightning/projects_test.exs
  - test/lightning_web/live/sandbox_live/index_test.exs
  - test/lightning_web/live/project_live/sandbox_settings_test.exs
  - test/lightning_web/live/project_live/deletion_teardown_test.exs
flows: []
---

## 1. Purpose

Sandbox owners and admins (and admins of the workspace root) use this to retire an experiment.
From the sandboxes list, one confirmation stops the sandbox and every sandbox under it from
running, ends everyone's open sessions in that subtree, and leaves a grace period in which it can
be restored before the nightly purge removes its data. Without it, abandoned sandboxes keep
firing triggers against real systems, and a mistaken delete would take colleagues' child
sandboxes with no way back.

## 2. What it does

1. An admin or owner of a sandbox (or of the workspace it sits in) types its name to confirm deletion on the sandboxes list.
2. The sandbox and every sandbox under it get the same deletion date, a week out by default, and all their triggers switch off straight away; the parent and sibling sandboxes keep running.
3. Everyone with a page, editor, run log or AI assistant open anywhere in that group of sandboxes is moved out; the person who deleted it stays on the list, or lands on the parent's sandboxes if they were inside it.
4. Until the date passes, an admin can restore it from the list; after that the nightly clean-up removes the sandboxes and all their data.
5. Deleting from the sandbox's own settings is different: the owner's confirmation removes the sandbox and its children at once, and they land on the workspace's workflows.

**Straightforwardness: 2 of 5.** The list path is clear on its own, but the settings path quietly does something else under the same wording, and restore doesn't fully undo what deletion did.

### Most surprising behaviours

- **(2)** Deleting from the sandbox's settings wipes it and all its children immediately, even though the dialog promises a grace period and a restore. It also never warns that child sandboxes go too, and colleagues with them open aren't told. (6.1)
- **(2)** Restoring a child sandbox while its parent is still scheduled looks like it worked, but the child is deleted anyway when the parent is purged. (6.1)
- **(3)** Restoring a sandbox doesn't switch its triggers back on, so it comes back silent until someone notices and turns each one on again. (S06, 6.2)
- **(3)** Nobody gets an email when a sandbox is deleted, unlike a whole project, so members of a child sandbox only find out when they're bounced out of it or see it on the list. (6.2)
- **(3)** On a server set to purge immediately, the sandbox is marked as deleted but no clean-up ever runs, so it sits under "Scheduled for deletion" for good. (6.1)

## 3. Who can do what

Source: `policies/sandboxes.ex:90-92` (never a root), `:109-119` (`:delete_sandbox` through `Scope`:
owner or admin on the sandbox with MFA met, or owner or admin on the root), `:125-130`
(`:cancel_scheduled_deletion`, roles read directly), `:155-166` (list buttons), `settings.ex:119-121`,
`:262-267` (settings gate uses owner-only `:delete_project`), `hooks.ex:294-318` (teardown reaches
every socket on the topic).

| Action | Viewer | Editor | Admin | Owner | Root owner or admin (no row) | Superuser (no row) | Support |
|--------|--------|--------|-------|-------|------------------------------|--------------------|---------|
| Schedule from the sandboxes list | no | no | yes | yes | server yes; the list only shows sandboxes they have a row on | no | no |
| Hard-delete from sandbox settings (UI) | no | no | no | yes | no | no | no |
| Hard-delete from sandbox settings (server, `confirm-delete`) | no | no | yes | yes | yes | no | no |
| Restore during the grace period | no | no | yes | yes | yes | no | no |
| Have an open page torn down | yes | yes | yes | yes | yes | yes | yes |

**Preconditions beyond role**
- The typed name must match the sandbox name (`index.ex:156-176`, `settings.ex:283-296`, `:476-482`).
- Scheduling goes through `Scope`, so it is refused on a sandbox already scheduled or whose MFA requirement the actor hasn't met (`scope.ex:112-116`, `:149-152`); restore skips `Scope` on purpose (`policies/sandboxes.ex:121-130`).
- Restore is also refused when the plan's sandbox limit is reached (`sandboxes.ex:923-931`; sandboxes-index S31).
- A superuser deleting a sandbox from admin-projects takes the root path instead (flow-schedule-project-deletion 6.2).

## 4. What it touches

**Reads**: `projects` (subtree via `descendants_query`), `project_users`, `triggers`, `workflows`

**Writes**
- Hop 1, list confirm: `projects.scheduled_deletion = now + purge_deleted_after_days` (to the second) on the sandbox and every descendant, overwriting any earlier date; `triggers.enabled = false` for every enabled trigger in the subtree; one transaction (`sandboxes.ex:942-964`, `:997-1006`)
- Hop 1b, settings confirm: immediate hard delete through `Projects.delete_project/1`: child sandboxes first (recursively), stored files, work orders, channel requests, jobs, triggers, workflows, project users, project credentials, OAuth clients, dataclips, then the row (`settings.ex:484-494`, `sandboxes.ex:814-820`, `project_hook.ex:22-45`, `:69-77`)
- Hop 4, restore: `projects.scheduled_deletion = nil` on every scheduled project in the subtree; triggers stay off (`sandboxes.ex:975-988`)
- Hop 5, purge: same deletes as hop 1b, per project past its date (`projects.ex:194-219`, `:909-926`)

**Immediate side effects** (in the same request)
- Hop 1: PromEx "scheduled for deletion" (`sandboxes.ex:963`); flash "Sandbox <name> scheduled for deletion." and either a list reload or a navigate to `/projects/<parent_id>/sandboxes` when the viewer's project is in the subtree (`index.ex:828-855`)
- Hop 2: after commit, `ProjectDeletionScheduled` on `project_events:<id>` for each id in the subtree (`sandboxes.ex:965-972`, `events.ex:116-121`, `:165`). Received by project-scoped LiveViews (`hooks.ex:294-318`; shared-project-scope S10, S11), the collaborative editor channel (`workflow_channel.ex:1081-1083`), browser run channels (`run_channel.ex:333-353`) and the AI assistant channel (`ai_assistant_channel.ex:491`)
- Hop 1b: flash "Sandbox <name> and all its associated descendants deleted", navigate to `/projects/<root_id>/w` (`settings.ex:488-494`); `Events.project_deleted` on `projects_events:all` and PromEx "sandbox deleted" per sandbox (`projects.ex:923`, `project_hook.ex:36-40`); no `ProjectDeletionScheduled`
- No email at any hop (contrast `projects.ex:1677-1689` on the root path)

**Deferred side effects** (later, elsewhere)
- Hop 3: webhooks to subtree triggers get 403 `trigger_disabled` (`webhooks_controller.ex:40`, `:109-115`); cron triggers stop being picked up (`workflows.ex:1290`)
- Hop 5: nightly at 02:45 the sweep enqueues one purge job for every project past its date, which includes every member of the subtree (`bootstrap.ex:312`, `projects.ex:208-219`)

**External, non-transactional effects**
- Hard delete and purge remove stored export files from object storage before any row and stop if one can't be removed (`project_hook.ex:47-63`); a child that fails halts the parent's delete (`project_hook.ex:69-77`)
- The broadcast runs after commit, so a failed schedule tells nobody (`sandboxes.ex:965-972`)

**Depends on config**
- `purge_deleted_after_days`: the scheduled date, the modal copy and whether a purge cron exists (`sandboxes.ex:997-1006`, `components.ex:240-246`, `bootstrap.ex:306-316`)
- Experimental features on the viewer: where a torn-down page goes (`hooks.ex:295-317`)
- `project_hook` adapter: what hard delete and purge actually remove (`projects.ex:915`)

**Product limits**
- A sandbox deleted from the list is kept for `purge_deleted_after_days` (default 7) and can be restored in that window, as the modal states (sandboxes-index S25)

## 5. Scenarios

Verified against `default` unless tagged. Single-surface steps (modal copy, mistyped name, child
count, tooltip, restore button, landing on the parent's list) are owned by sandboxes-index S22 to
S31 and project-settings-setup S18 to S21 and are not restated.

```gherkin
Feature: Delete a sandbox
  In order to retire an experiment without leaving it running
  As an owner or admin of a sandbox
  I want one confirmation to stop the sandbox and its children and remove them after a grace period

  @S01 @pending
  Scenario: Deleting a sandbox stops it and every sandbox under it at once
    # Value: an experiment someone has decided to remove stops talking to real systems now, not after the grace period.
    Given sandbox "sb-1" has child sandbox "child" and grandchild "grandchild"
    And each has an enabled webhook trigger and an enabled cron trigger
    When an admin of "sb-1" confirms its deletion on the sandboxes list
    Then "sb-1", "child" and "grandchild" are scheduled for deletion with the same date, 7 days from now
    And every trigger in the three sandboxes is disabled
    And a request to any of their webhook URLs gets 403 with error "trigger_disabled"
    # index.ex:148-177, sandboxes.ex:942-964, :997-1006, webhooks_controller.ex:40, :109-115, workflows.ex:1290
    # sandboxes_test.exs:2813-2826, :2867-2910 (dates, triggers); webhook response read from code

  @S02 @pending
  Scenario: The parent and sibling sandboxes keep running
    # Value: retiring one experiment never stops the live project or a colleague's sandbox.
    Given project "parent" has sandboxes "sb-1" and "sibling", each with an enabled trigger
    When "sb-1" is deleted from the sandboxes list
    Then "parent" and "sibling" are not scheduled for deletion
    And their triggers are still enabled
    # sandboxes.ex:942-958, :990-997 (subtree only); sandboxes_test.exs:2912-2922 (scheduled_deletion only; triggers read from code)

  @S03 @pending
  Scenario: Open pages and sessions anywhere in the subtree leave
    # Value: nobody keeps editing or running work in a sandbox that is being deleted, including children they didn't delete.
    Given another member has a page of "child" open, and the editor, a run log and the AI assistant open on "sb-1"
    When "sb-1" is deleted from the sandboxes list
    Then the page on "child" follows shared-project-scope S10
    And the editor, run log and AI assistant sessions on "sb-1" end as in flow-schedule-project-deletion S04
    # handoff only: sandboxes.ex:965-972, hooks.ex:294-318, workflow_channel.ex:1081-1083
    # sandboxes_test.exs:2846-2865 (one broadcast per project); deletion_teardown_test.exs:225-248 (descendant page to "/projects", "Project deleted.")

  @S04 @pending @variant:experimental-features
  Scenario: An editor in the deleted sandbox moves to the parent, but one in a child does not
    # Value: people land on the live workflow when there is one, and are never sent into a project that is itself being deleted.
    Given I have experimental features enabled
    And I have workflow "Intake" open in "sb-1", whose parent "parent" has a workflow named "Intake"
    And another such user has a workflow open in "child"
    When "sb-1" is deleted from the sandboxes list
    Then my editor follows shared-project-scope S11 to "Intake" in "parent"
    And the other user is eventually on "/projects" with "Project deleted."
    # hooks.ex:295-317, :378-394 (the parent must not be scheduled), :398-409

  @S05 @pending
  Scenario: The nightly purge removes the sandbox and its children after the grace period
    # Value: a retired sandbox's data, including the health data in its runs, is actually removed once the grace period ends.
    Given "sb-1" and its child "child" were deleted from the sandboxes list and their date has passed
    When the nightly purge runs
    Then "sb-1" and "child", with their workflows, history and memberships, no longer exist
    And "parent" still exists
    # bootstrap.ex:312, projects.ex:194-219, :909-926, project_hook.ex:22-45, :69-77
    # projects_test.exs:2031-2051 (sweep, root project only); sandbox subtree purge read from code

  @S06 @pending
  Scenario: A sandbox restored during the grace period survives the purge
    # Value: the restore promised in the delete modal actually keeps the sandbox and its children.
    Given "sb-1" and its child "child" were deleted from the sandboxes list
    When an admin restores "sb-1" during the grace period
    And the date it was scheduled for passes and the nightly purge runs
    Then "sb-1" and "child" still exist
    And their triggers are still disabled
    # sandboxes.ex:975-988, projects.ex:208-212; sandboxes_test.exs:3024-3040 (cancel clears the subtree); restore UI is sandboxes-index S29

  @S07 @pending
  Scenario: Deleting a sandbox from its settings takes its child sandboxes with it
    # Value: no child sandbox is left behind pointing at a parent that no longer exists.
    Given I am the owner of sandbox "sb-1" with child "child", each with a workflow
    When I confirm deletion of "sb-1" on its settings
    Then I am on the workflows page of the workspace root
    And "sb-1", "child" and both workflows no longer exist
    # settings.ex:476-494, sandboxes.ex:814-820, project_hook.ex:22-24, :69-77
    # sandbox_settings_test.exs:158-172 (landing, flash, sandbox gone); sandboxes_test.exs:2436-2453, :2711-2745 (children gone, including ones the actor has no row on)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Settings hard-deletes at once while the modal promises a grace period and restore from the list (project-settings-setup 6.1 row 1, restated here because it splits this flow in two) | `settings.ex:484-494`, `sandboxes.ex:814-820`, `components.ex:197-201` | the sandbox and its data are gone immediately, with no restore | fix |
| Settings never passes `descendants`, so its modal never warns that child sandboxes go too, yet they are deleted (project-settings-setup 6.1 row 2) | `settings.html.heex:297-302`, `components.ex:140`, `:174-182`, `project_hook.ex:69-77` | child sandboxes, possibly other people's, deleted without warning | fix |
| The settings hard delete emits no `ProjectDeletionScheduled`, so other people's open pages, editors and run channels on the sandbox or its children are not told | `projects.ex:909-926`, `project_hook.ex:22-45`; compare `sandboxes.ex:965-972` | colleagues keep a live editor on a sandbox that no longer exists until their next request fails | fix |
| The settings path lands on the root's workflows; the list path lands on the parent's sandboxes; the shared modal copy names the root in both | `settings.ex:494`, `index.ex:848-851`, `components.ex:188-191` | for a nested sandbox, a different landing per entry, and the list's landing contradicts the copy (sandboxes-index 6.1) | fix |
| Restoring a child whose parent is still scheduled clears only the child; the parent's purge then hard-deletes every child regardless of its own date | `sandboxes.ex:975-988`, `project_hook.ex:69-77` (`list_sandboxes` has no scheduled filter, `projects.ex:2161-2168`) | a sandbox shown as restored and active vanishes at the parent's purge | fix |
| Under `purge-immediate` the date is "now" and the modal says "0 days", but no purge cron exists, so the subtree is never purged (sandboxes-index 6.1) | `sandboxes.ex:1001-1006`, `components.ex:240-246`, `bootstrap.ex:306-316` | a sandbox under "Scheduled for deletion" forever | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Scheduling a parent overwrites a child's earlier date, so a child's grace period can grow | `sandboxes.ex:845-851`, `:946-950`; `sandboxes_test.exs:2924-2944` | preserve |
| Restore does not re-enable triggers; restore is not transactional and broadcasts nothing (also sandboxes-index 6.2) | `sandboxes.ex:975-988` | decide |
| Sandbox deletion sends no email, unlike the root path; members of a child sandbox learn only from teardown or the list | `sandboxes.ex:942-973`; compare `projects.ex:1677-1689` | decide |
| No audit event for scheduling, restoring or hard-deleting a sandbox | `sandboxes.ex:942-988`, `project_hook.ex:22-45` | decide |
| The settings UI admits only the owner while the server path admits admins and root admins; the list admits admins (project-settings-setup 6.5) | `settings.ex:119-121`, `policies/sandboxes.ex:109-119` | decide |
| Hard delete and purge are not wrapped in a transaction; a failure after the files step leaves a partly deleted sandbox (purgeable on retry) | `project_hook.ex:22-45` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `purge_deleted_after_days: nil` branches ("the configured grace period", schedule at now) | `components.ex:242`, `sandboxes.ex:1002` | `env!` defaults to 7 (`bootstrap.ex:273-278`); only a test mock returns nil |
| `Events.project_deleted/1` | `events.ex:88-93`, `projects.ex:923` | no subscriber to `projects_events:all` in `lib/` (flow-schedule-project-deletion 6.3) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Purge runs nightly at 02:45 UTC, so removal happens up to a day after the date | `bootstrap.ex:312`, `projects.ex:208-219` | yes, against the tooltip date | preserve |
| The sweep enqueues a job for every subtree member as well as the root of the subtree; the parent job deletes the children, the child jobs then find nothing and return `:ok`, or race the parent and retry (3 attempts) | `projects.ex:194-219`, `project_hook.ex:69-77` | no | decide |
| Settings hard delete runs synchronously in the LiveView (batches of 1000), subtree included | `project_hook.ex:22-45`, `projects.ex:1696-1714` | yes, the modal can hang | decide |

### 6.5 Things seen but not understood

- When the deleter's own page is inside the subtree, the LiveView pushes a navigate to the parent's list and then receives its own `ProjectDeletionScheduled`, which redirects to `/projects` with "Project deleted." (`index.ex:848-851`, `sandboxes.ex:965-972`, `hooks.ex:294-311`). Which wins in a browser is not established; the LiveView tests mock `schedule_sandbox_deletion`, so no broadcast fires (`index_test.exs:1039`, `:1112` Mimic expects). (decide)
- The editor's `archive_sandbox` (`workflow_channel.ex:501-513`, `Header.tsx:262`, `createWorkflowStore.ts:1719`) calls the same `schedule_sandbox_deletion`, so it is a third entry into this flow; the lead's scope names two. (decide)
- Whether the hard-delete path should exist at all once settings follows the list's schedule path. (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should deleting from sandbox settings schedule the subtree like the list does, or should the modal stop promising a grace period?
- Should restoring a child be refused, or cascade upward, while its parent is scheduled?
- Where should a viewer land after deleting a sandbox they are in: parent's sandboxes, root's workflows, or their access root? (owner: product) for the list; this flow needs one answer for both entries.
- Should sandbox members be emailed, as root-project members are?
- Is the editor's "archive sandbox" an entry to this flow or to flow-sandbox-merge?

## Proposed flows

none. References flow-schedule-project-deletion (root path, S04 channel teardown, S09 file failure) and flow-sandbox-merge (shares the schedule call).

## Proposed shared

none. References shared-project-scope (S04, S10, S11). `shared-channel-project-scope` proposed by flow-schedule-project-deletion would own S03's channel half.

## Summary

- Scenarios: 7 (S01 to S07), all `@pending`; S04 tagged `@variant:experimental-features`.
- Section 6: 6.1 has 6, 6.2 has 6, 6.3 has 2, 6.4 has 3, 6.5 has 3.
- Flows: none proposed; references flow-schedule-project-deletion, flow-sandbox-merge; handoffs to shared-project-scope S10, S11.
- Shared: references shared-project-scope; none proposed.
- Unsure: the deleter's own redirect race (6.5); S02 triggers, S05 sandbox purge and webhook 403 are read from code; the editor's archive entry is not in `surfaces`.
