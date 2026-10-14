---
id: flow-schedule-project-deletion
type: flow
title: Schedule a project for deletion
status: not-started
owner:

trigger:
  entry: project-settings-setup            # owner; admin-projects (superuser) also starts it
  exit: projects-dashboard                 # admin-projects returns to /settings/projects instead
  surfaces:
    - project-settings-setup
    - admin-projects
    - email:project-deletion-scheduled
    - pubsub:project_events:<project_id>#ProjectDeletionScheduled
    - projects-dashboard
    - oban:purge_deleted
  reachable_when:
    - project-settings-setup: viewer is an owner and the project is not a sandbox (settings.html.heex:304, settings.ex:262-267)
    - admin-projects: viewer is a superuser (index.ex:7, hooks.ex:40-53, policies/users.ex:19-21)

inherits:
  - shared-project-scope            # receiving end of the broadcast (S10, S11) and the Not Found gate on a scheduled project (S04)

url_params:
  - name: /projects/:project_id/settings/delete
    set_by: "Delete project" in the setup danger zone
    effect: opens the deletion modal (see project-settings-setup)
  - name: /settings/projects/:id/delete
    set_by: "Delete" or "Delete now" on a row of the superuser projects list (index.ex:153-180)
    effect: opens the same modal; schedules an unscheduled project, starts the purge for a scheduled one (project_deletion_modal.ex:68-74)

config_variants:
  default: { purge_deleted_after_days: 7 }   # read under this variant (bootstrap.ex:273-278)
  purge-immediate: { purge_deleted_after_days: 0 }   # bootstrap.ex:307 registers no purge cron
  project-hook: { Lightning.Extensions.project_hook: <adapter with its own handle_delete_project> }   # projects.ex:915

inventory:
  routes:
    - live /projects/:project_id/settings/delete  ProjectLive.Settings :delete   # owned by project-settings-setup
    - live /settings/projects  ProjectLive.Index :index   # owned by admin-projects
    - live /settings/projects/:id/delete  ProjectLive.Index :delete   # owned by admin-projects
  events:
    - LightningWeb.Components.ProjectDeletionModal#validate
    - LightningWeb.Components.ProjectDeletionModal#delete
    - LightningWeb.Components.ProjectDeletionModal#close_modal
    - ProjectLive.Index#cancel_deletion
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:delete_project)
    - Lightning.Policies.Users (:access_admin_space)
    - Lightning.Projects.Scope (still_operable/1, the refusal during the grace period)
  workers:
    - Lightning.Projects (Oban, queue :background, args type purge_deleted; sweep and per-project)
  api_endpoints: []
  emails:
    - email:project-deletion-scheduled   # UserNotifier.notify_project_deletion/2, user_notifier.ex:430-450
  config:
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
    - Lightning.Extensions.project_hook (handle_delete_project)
  not_reachable_here:
    - Lightning.Projects.Events.ProjectDeleted (events.ex:88-93); broadcast by the purge, no subscriber in lib/ (see 6.3)

related:
  - lib/lightning_web/live/components/project_deletion_modal.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/live/project_live/index.ex
  - lib/lightning_web/live/project_live/index.html.heex
  - lib/lightning/projects.ex
  - lib/lightning/projects/events.ex
  - lib/lightning/projects/scope.ex
  - lib/lightning/extensions/project_hook.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/helpers.ex
  - lib/lightning/config/bootstrap.ex
  - lib/lightning_web/hooks.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning_web/channels/ai_assistant_channel.ex
  - lib/lightning_web/controllers/webhooks_controller.ex
  - test/lightning/projects_test.exs
  - test/lightning/accounts/user_notifier_test.exs
  - test/lightning_web/live/project_live_test.exs
  - test/lightning_web/live/project_live/deletion_teardown_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - test/lightning_web/channels/run_channel_test.exs
  - test/lightning_web/channels/ai_assistant_channel_test.exs
flows: []
---

## 1. Purpose

Owners (and superusers, for any project) use this to wind a project down. One confirmation
stops the project taking in and processing data, tells every member, ends everyone's open
sessions on it, and then removes its data once a grace period has passed. Without it a retired
project would keep running and holding health data, and a mistaken deletion would leave no window
in which to undo it.

## 2. What it does

Owner confirms on setup (or superuser on the admin projects list) → triggers disabled, every member emailed, open pages and channels on the project end → owner lands on `/projects` → superuser can cancel or purge now during the grace period → nightly purge deletes the project and its sandboxes.

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:138` (`:delete_project` is owner only),
`settings.ex:119-121`, `:262-267` (setup gate), `index.ex:7` with `hooks.ex:40-53` and
`policies/users.ex:19-21` (admin list needs `:access_admin_space`, superuser only),
`scope.ex:149-152` (nobody may operate a scheduled project).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Schedule from project settings | no | no | no | yes | no | no |
| Schedule from the admin projects list | no | no | no | no | yes | no |
| Cancel a scheduled deletion | no | no | no | no | yes | no |
| Purge a scheduled project now | no | no | no | no | yes | no |
| Receive the scheduled-deletion email | yes | yes | yes | yes | only with a project row | no |
| Open the project during the grace period | no | no | no | no | no | no |

**Preconditions beyond role**
- The typed name must match before anything changes (`project.ex:276-280`, `project_deletion_modal.ex:33-38`).
- From project settings, the project must not be a sandbox (`settings.html.heex:304`); sandboxes use their own delete path (project-settings-setup S18).
- The admin list offers every project, sandboxes included, and its modal always uses this root path (`index.ex:195-201`, `project_deletion_modal.ex:68-74`).
- Purge waits until `scheduled_deletion` has passed and the next 02:45 sweep runs (`projects.ex:208-219`, `bootstrap.ex:312`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `users`, `triggers`, `workflows`

**Writes**
- Hop 1, confirm: every trigger on the project's workflows `enabled = false`; `projects.scheduled_deletion = now + purge_deleted_after_days` truncated to the second; one transaction (`projects.ex:1639-1690`)
- Hop 1b, admin cancel: `projects.scheduled_deletion = nil` (`projects.ex:1728-1732`); triggers are left disabled
- Hop 1c, admin purge now: inserts an Oban job `{project_id, type: purge_deleted}`, max 3 attempts (`projects.ex:929-934`)
- Hop 5, purge: deletes child sandboxes recursively, stored files, work orders, channel requests, jobs, triggers, workflows, project users, project credentials, OAuth clients, dataclips, then the project row (`project_hook.ex:22-45`, `:66-77`)

**Immediate side effects** (in the same request)
- Hop 2: email "Project scheduled for deletion" to every `project_users` user, sent from inside the transaction (`projects.ex:1677-1689`, `user_notifier.ex:430-450`)
- Hop 3: after commit, `ProjectDeletionScheduled` on `project_events:<project_id>` (`projects.ex:1644`, `events.ex:116-121`, `:165`). Received by: every project-scoped LiveView (`hooks.ex:294-318`, see shared-project-scope S10, S11); the collaborative editor channel, which stops (`workflow_channel.ex:1081-1083`); a browser-joined run channel (`run_channel.ex:79`, `:333-345`, `:352-353`); the AI assistant channel (`ai_assistant_channel.ex:491-493`)
- Hop 4: flash "Project scheduled for deletion" and navigate to `/projects` (setup) or `/settings/projects` (admin) (`project_deletion_modal.ex:49-53`, `settings.html.heex:309`, `index.html.heex:21`)

**Deferred side effects** (later, elsewhere)
- Webhooks to the project's triggers get 403 `trigger_disabled` (`webhooks_controller.ex:40`, `:109-115`); cron triggers stop firing (`workflows.ex:1288-1291`)
- Nightly at 02:45 the sweep enqueues one purge job per project past its date (`bootstrap.ex:312`, `projects.ex:208-219`); each job deletes its project and broadcasts `ProjectDeleted` on `projects_events:all` (`projects.ex:194-205`, `:909-926`)

**External, non-transactional effects**
- Emails leave from inside the transaction; a later rollback leaves members told about a deletion that did not happen (`projects.ex:1677-1689`)
- The purge deletes stored export files from object storage before any database row, and stops if any file can't be removed (`project_hook.ex:47-63`)

**Depends on config**
- `purge_deleted_after_days`: the scheduled date, the modal's copy, the email's date, and whether the purge cron exists (`projects.ex:1655-1659`, `project_deletion_modal.ex:76-79`, `user_notifier.ex:434-437`, `bootstrap.ex:307`)
- `project_hook` adapter: what the purge actually deletes (`projects.ex:915`)

**Product limits**
- A scheduled project is kept for `purge_deleted_after_days` (default 7) before purge, stated in the modal and the email

## 5. Scenarios

Verified against `default` unless tagged. Single-surface steps of the modal (mistyped name,
cancel, non-owner bounce) are owned by project-settings-setup S13 to S15 and are not restated.

```gherkin
Feature: Schedule a project for deletion
  In order to retire a project safely
  As a project owner, or a superuser
  I want one confirmation to stop the project, tell its members and purge it after a grace period

  @S01 @pending
  Scenario: Owner schedules a project and lands on the projects list
    # Value: an owner can retire a project themselves, and it stops taking in data at once.
    Given I am the owner of project "project-1" with an enabled webhook trigger and an enabled cron trigger
    When I confirm deletion of "project-1" on its settings
    Then I am on "/projects"
    And I see "Project scheduled for deletion"
    And project "project-1" is scheduled for deletion 7 days from now
    And every trigger in "project-1" is disabled
    And a request to its webhook URL gets 403 with error "trigger_disabled"
    # project_deletion_modal.ex:32-53, settings.html.heex:304-311, projects.ex:1639-1690, webhooks_controller.ex:40, :109-115
    # project_live_test.exs:168-195 (flash); projects_test.exs:1079-1102 (triggers, date)

  @S02 @pending
  Scenario: Every member is emailed when a project is scheduled
    # Value: members who didn't make the decision learn about it in time to object.
    Given project "project-1" has members "user_1" and "user_2"
    When the owner confirms deletion of "project-1"
    Then "user_1" and "user_2" each receive "Project scheduled for deletion"
    And the email names "project-1", says its workflows have been disabled, gives the deletion date and the instance admin address to contact
    # projects.ex:1677-1689, user_notifier.ex:430-450; projects_test.exs:1019-1065, user_notifier_test.exs:14-40

  @S03 @pending
  Scenario: Other members' open project pages leave the project
    # Value: nobody keeps working in a project that is being deleted.
    Given another member has a page of "project-1" open
    When the owner confirms deletion of "project-1"
    Then that member's page follows shared-project-scope S10
    # handoff only: projects.ex:1644, events.ex:116-121, hooks.ex:294-318; deletion_teardown_test.exs:45-70

  @S04 @pending
  Scenario: Open editor, run log and AI assistant sessions end
    # Value: edits and replies stop reaching other participants as soon as the project is wound down, not when someone reloads.
    Given another member has the collaborative editor, a run's log stream and the AI assistant open on "project-1"
    When the owner confirms deletion of "project-1"
    Then each of those channels closes
    And a log line appended to the run afterwards is not pushed to them
    # workflow_channel.ex:1075-1083, run_channel.ex:333-345, :352-353, ai_assistant_channel.ex:488-493
    # workflow_channel_test.exs:2195-2235, run_channel_test.exs:3515-3530, ai_assistant_channel_test.exs:1316-1323

  @S05 @pending
  Scenario: Sessions on other projects are unaffected
    # Value: one project's deletion doesn't interrupt people working elsewhere.
    Given I have a page, an editor channel and a run channel open on "project-2"
    When "project-1" is scheduled for deletion
    Then all of them stay open
    # events.ex:165 (per-project topic); deletion_teardown_test.exs:210-224, workflow_channel_test.exs:2237-2255, run_channel_test.exs:3532-3544

  @S06 @pending
  Scenario: Nothing is broadcast when scheduling fails
    # Value: people are not thrown out of a project that was not actually scheduled.
    Given project "project-1" no longer exists in the database
    When scheduling its deletion is attempted
    Then it fails
    And no ProjectDeletionScheduled is broadcast
    # projects.ex:1642-1651; projects_test.exs:1116-1128

  @S07 @pending
  Scenario: The purge deletes the project after the grace period
    # Value: a retired project's data is actually removed once the grace period ends.
    Given project "project-1" was scheduled for deletion and its date has passed
    And it has a sandbox "sandbox-1"
    When the nightly purge runs
    Then "project-1", its workflows, history, memberships and "sandbox-1" no longer exist
    # bootstrap.ex:312, projects.ex:194-219, :909-926, project_hook.ex:22-45, :66-77; projects_test.exs:2031-2051

  @S08 @pending
  Scenario: The purge leaves a project whose grace period has not ended
    # Value: the grace period promised in the modal and email is honoured.
    Given project "project-1" is scheduled for deletion 10 seconds from now
    When the purge sweep runs
    Then "project-1" still exists
    # projects.ex:208-212; projects_test.exs:2031-2051 (not_to_delete)

  @S09 @pending
  Scenario: A purge that cannot remove stored files keeps the project whole and fails
    # Value: exported raw data is never left in storage with nothing tracking it, and the failure is visible.
    Given project "project-1" is past its deletion date and has a stored export that cannot be deleted
    When its purge job runs
    Then the job fails
    And "project-1" still exists
    # projects.ex:194-205, project_hook.ex:47-63; projects_test.exs:2063-2078

  @S10 @pending
  Scenario: Superuser schedules a project from the admin projects list
    # Value: a project can be retired when no owner is available to do it.
    Given I am a superuser
    When I click "Delete" on "project-1" in "/settings/projects" and confirm with "project-1"
    Then I am on "/settings/projects"
    And I see "Project scheduled for deletion"
    And "project-1" shows "Cancel deletion" and "Delete now"
    And the effects of S01 to S04 apply to "project-1"
    # index.ex:82-93, :153-180, index.html.heex:16-24, project_deletion_modal.ex:68-74; project_live_test.exs:239-276

  @S11 @pending
  Scenario: Superuser cancels a scheduled deletion
    # Value: a mistaken deletion can be undone during the grace period, as the email invites members to ask for.
    Given project "project-1" is scheduled for deletion
    And I am a superuser on "/settings/projects"
    When I click "Cancel deletion" on "project-1"
    Then I see "Project deletion canceled"
    And "project-1" is no longer scheduled for deletion
    And its members can open it again
    # index.ex:96-107, projects.ex:1728-1732, scope.ex:149; project_live_test.exs:308-320 (flash only)

  @S12 @pending
  Scenario: Superuser purges a scheduled project without waiting
    # Value: a superuser can remove a project's data before the grace period ends when that is needed.
    Given project "project-1" is scheduled for deletion
    And I am a superuser on "/settings/projects"
    When I click "Delete now" on "project-1" and confirm with "project-1"
    Then I am on "/settings/projects"
    And I see "Project deletion started. This may take a while to complete."
    And "project-1" is eventually deleted
    # index.ex:165-170, project_deletion_modal.ex:40-47, :68-71, projects.ex:929-934, :194-205; project_live_test.exs:322-355
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Scheduling a root project does not cascade to its sandboxes: their triggers stay enabled, they are not marked, no broadcast reaches them, their members are not emailed, and `Scope` admits them. The purge then hard-deletes them. Sandbox scheduling does cascade | `projects.ex:1661-1689`, `scope.ex:149-152`, `project_hook.ex:66-77`; compare `sandboxes.ex:942-973` | sandbox members keep working and sandbox workflows keep running for the whole grace period, then the sandbox vanishes without notice | fix |
| The `/projects` list does not filter scheduled projects (`projects_overview_query` checks only `parent_id` and workflow `deleted_at`) | `projects.ex:101-175`, `user_projects_section.ex:46` | right after "Project scheduled for deletion", the project is still listed; clicking it shows "Not Found" | fix |
| The email's date is the next 02:04 after now + N days (default cron in the helper), but the purge sweep runs at 02:45 and selects anything past `scheduled_deletion` | `user_notifier.ex:434-437`, `helpers.ex:96-110`, `bootstrap.ex:312`, `projects.ex:208-212` | scheduled between 02:04 and 02:45 UTC, the project is purged at 02:45 on day N while the email says day N+1 | fix |
| Under `purge-immediate` the email still promises deletion at the next 02:04, but no purge cron is registered, so the project is never purged (the scheduling side is project-settings-setup 6.2) | `helpers.ex:104-110`, `bootstrap.ex:307` | an email with a deletion date that never happens; the project stays inaccessible indefinitely | fix |
| `/settings/projects/:id/delete` with an unknown id assigns `project: nil` and the template reads `@project.id` | `index.ex:82-93`, `index.html.heex:19` | a crash page for a stale or mistyped link | fix |
| The "Delete now" test's `refute` selector lacks `#`, so it can never fail | `project_live_test.exs:354` | none (test gap, not product); the project actually stays listed until the job runs | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Cancelling a scheduled deletion does not re-enable the triggers it disabled (sandbox cancel behaves the same) | `projects.ex:1728-1732`, `sandboxes.ex:975-988` | decide |
| A failed send to one member is ignored (`Enum.each` drops `{:error, _}`), so the transaction commits and that member is silently not told | `projects.ex:1679-1689`, `user_notifier.ex:57-59` | decide |
| The notice uses `deliver/3`, not `deliver_project_mail/4`, so it skips the `MailRecipients.may_receive?` check other project mail runs | `user_notifier.ex:49-75`, `:439` | decide |
| Email copy: "All of the workflows in this project have been disabled" (triggers are disabled, workflows are not), "it's associated resources", date shown as `%F at %T` with no time zone | `user_notifier.ex:441-447` | fix |
| The admin list's modal always takes the root path, so a superuser "Delete" on a sandbox schedules it without the descendant cascade `Sandboxes.schedule_sandbox_deletion` applies | `index.ex:195-201`, `project_deletion_modal.ex:68-74`, `sandboxes.ex:942-973` | decide |
| Admin cancel has no confirmation and uses `get_project!`, so a project purged in the meantime raises | `index.ex:96-107`, `projects.ex:1728-1729` | decide |
| "Delete now" and the nightly sweep enqueue purge jobs with no uniqueness; duplicates are harmless because a missing project returns `:ok` | `projects.ex:194-200`, `:214-218`, `:929-934`; `projects_test.exs:2053-2061` | preserve |
| Scheduling emits no audit event, from either entry | `projects.ex:1639-1690`, `projects/audit.ex:20-39` | decide |
| The admin "Scheduled deletion" column formats the date `%d %b  %H:%M` (double space, UTC, no zone) | `index.html.heex:106-107` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `Events.project_deleted/1` broadcast on `projects_events:all` | `events.ex:88-93`, `projects.ex:922` | no module in `lib/` subscribes to that topic (`Projects.subscribe/0` has no caller) |
| `ProjectDeletionModal` "delete now" branch from project settings | `project_deletion_modal.ex:69-70` | a scheduled project fails the scope gate before settings mounts (shared-project-scope S04); reachable only from admin-projects |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Purge runs once a night at 02:45 UTC, so deletion happens up to a day after `scheduled_deletion` | `bootstrap.ex:312`, `projects.ex:208-219` | yes, via the email date | preserve |
| Per-project purge job: queue `:background`, 3 attempts; the sweep job itself has 1 attempt | `projects.ex:6-8`, `:214-215`, `:931` | no | preserve |
| Purge deletes work orders and dataclips in batches of 1000 | `projects.ex:1698-1714` | no | preserve |
| Scheduling updates triggers one Multi step each and sends every email synchronously inside one transaction | `projects.ex:1661-1689` | yes, a slow confirm on a large project | decide |

### 6.5 Things seen but not understood

- The owner's own settings LiveView is subscribed to the project topic, so after it pushes the navigate with "Project scheduled for deletion" it also receives `ProjectDeletionScheduled` and may redirect with "Project deleted." (`project_deletion_modal.ex:49-53`, `hooks.ex:294-318`). Which flash a real browser shows was not established; the test only follows the first redirect. (decide)
- Whether the support user's run channel is closed (the clause requires `current_user`; worker joins have none) beyond the browser case was not followed (`run_channel.ex:79`, `:333-338`). (preserve)
- Nothing tells the members the project was cancelled or purged; only scheduling sends mail. Not clear whether that is intended. (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should scheduling a root project cascade to its sandboxes as sandbox scheduling does (marking, triggers, broadcast, email)?
- Should cancelling a deletion restore the triggers it disabled?
- Under `purge-immediate`, should scheduled projects ever be purged, and what should the email say?
- Should the email date come from the real purge schedule?

## Proposed flows

none

## Proposed shared

- `shared-channel-project-scope`: the project-event handlers in `WorkflowChannel`, `RunChannel` and `AiAssistantChannel` that end a socket on `ProjectDeletionScheduled`, `ProjectUserRemoved`, `SupportAccessUpdated` and `WorkflowDeleted` (`workflow_channel.ex:1075-1100`, `run_channel.ex:325-360`, `ai_assistant_channel.ex:485-500`). The channel counterpart of shared-project-scope; S04 and S05 here would move there.
- `shared-project-deletion-modal`: already proposed by project-settings-setup; this flow confirms admin-projects uses both branches.

## Summary

- Scenarios: 12 (S01 to S12), all `@pending`.
- Section 6: 6.1 has 6, 6.2 has 9, 6.3 has 2, 6.4 has 4, 6.5 has 3.
- Flows: none proposed; references project-settings-setup S13 to S15 and shared-project-scope S04, S10, S11.
- Shared: references shared-project-scope; proposes shared-channel-project-scope; endorses shared-project-deletion-modal.
- Unsure: the owner's own flash race (6.5); the 6.1 email-date mismatch and the dashboard listing are read from code, not run; admin-projects and projects-dashboard have no annotation files yet, so their `flows:` lists cannot be checked.
