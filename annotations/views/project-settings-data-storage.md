---
id: project-settings-data-storage
type: view
title: Project settings › Data storage
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#data-storage
  new_route: /projects/:project_id/settings/data-storage
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; settings.ex:51)
    - the client-side tab hash is "data-storage" (settings.html.heex:862; TabbedContainer, see shared-project-settings-tab-chrome)
    - controls are interactive only when the viewer passes `:edit_data_retention` at mount (settings.ex:138-144; settings.html.heex:910-913, :966, :1018-1022, :1031, :1042-1045)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # on_mount :project_scope (settings.ex:51); login, MFA gate, membership remount
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab navigation (S02, S04 use this tab), role notice (S06 row "editor | Data Storage"), sandbox Local banner (S08 row "Data Storage")
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: "#data-storage (URL fragment)"
    set_by: >-
      dataclip viewers' wiped-data message (viewers.ex:334, :343; shown to admins only, viewers.ex:330);
      run step rerun tooltip "Go to data storage settings" (run_live/components.ex:563; shared-run-components S13);
      data retention change email (user_notifier.ex:195)
    effect: opens this tab client-side; the server never sees it (settings.ex:233)

config_variants:
  default: { Lightning.Extensions.usage_limiter: Lightning.Extensions.UsageLimiter }   # periods [7, 14, 30, 90, 180, 365], no message (usage_limiter.ex:25-30); read under this one
  retention-limited: { Lightning.Extensions.usage_limiter: <adapter whose get_data_retention_periods returns a subset and get_data_retention_message returns %{text: _} or %{function: _, attrs: _}> }   # hosted plans; read from code and project_live_test.exs:3334-3370
  retention-single-option: { Lightning.Extensions.usage_limiter: <adapter whose get_data_retention_periods returns exactly one period> }   # project_live_test.exs:3372-3397
  sandbox: { project.parent_id: <parent project id> }   # data state, named so the sandbox banner row in shared-project-settings-tab-chrome S08 applies

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # catalogued by project-settings-setup
  events:
    - ProjectLive.Settings#validate                  # settings.ex:299-328; shared with project-settings-setup; this view covers #retention-settings-form
    - ProjectLive.Settings#cancel-retention-change   # settings.ex:330-338
    - ProjectLive.Settings#save_retention_settings   # settings.ex:366-378
  js_hooks: []                                       # tab switching via TabbedContainer is in shared-project-settings-tab-chrome
  policies:
    - Lightning.Policies.ProjectUsers (:edit_data_retention; project_users.ex:29-37, :134, :160-161; flag at settings.ex:138-144; re-checked settings.ex:371, :744-749)
  workers: []                                        # the retention cleanup job reads these settings; see proposed flow flow-retention-cleanup
  api_endpoints: []
  emails:
    - email:data-retention-change                    # UserNotifier.send_data_retention_change_email/2, user_notifier.ex:172-200
  config:
    - :lightning, Lightning.Extensions, :usage_limiter (config/config.exs:43), read through on_mount {LightningWeb.Hooks, :limit_retention_periods} (settings.ex:55; hooks.ex:229-239; project_limiter.ex:42-58)
    - :lightning, Lightning.Extensions, :project_hook (config/config.exs:47), handle_project_validation on every save (projects.ex:593; extensions/project_hook.ex:79-81)
  not_reachable_here:
    - "retain_with_errors" retention policy option (commented out, settings.html.heex:954-955; see 6.3)

related:
  - project-settings-setup                 # owns the host route and mount; shares the `validate` event and `project_changeset`
  - shared-run-components                  # S13 links here from the rerun tooltip
  - history-work-orders                    # shows wiped dataclips produced by zero persistence
  - lib/lightning/projects/sandboxes.ex    # retention fields copied at sandbox creation (sandboxes.ex:104-107)
  - lib/lightning/channels/persistence_policy.ex   # channel request payloads follow retention_policy
flows:
  - flow-data-retention-change-email
  - flow-zero-persistence-runs
  - flow-zero-persistence-channel-requests
---

## 1. Purpose

Project owners and admins use this tab to decide how long a project's run history is kept and
whether the input and output data of runs and channel requests (which often holds health
records and other PII) is stored at all. They need to be able to keep data long enough to debug
and retry failed runs, or to keep nothing, to meet a data protection agreement. Without it,
sensitive payloads would sit on the servers indefinitely, or an admin would have no way to stop
storing them; and everyone else on the project would have no way to see what the policy is.

## 2. What it does

- Every member sees the project's current history retention period, I/O storage policy and I/O retention period
- New projects keep all I/O data and have no history retention period until an admin sets one
- Admins and owners set how long run history is kept
- Admins and owners set how long I/O data is kept, once a history period is set
- I/O data can't be set to outlive the run history it belongs to
- Admins and owners switch the project to never storing I/O data, after a warning
- Admins and owners switch back to retaining all I/O data
- Admins and owners discard unsaved changes with Cancel
- Editors, viewers and support users see the settings with every control disabled
- Editors, viewers, support users and admins demoted while the page is open cannot save
- The retention form changes only retention fields
- An admin is told when a save failed
- Each saved period change is recorded in the audit trail with the acting user
- Each saved period change notifies the project's admins and owners by email
- On a plan that limits retention, admins only see the plan's periods, and the plan's explanation
- On a plan with a single period, the history period can't be changed

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_data_retention` is an admin
action), `:134` (MFA unsatisfied denies everything), `:160-161` (admin actions need an owner or
admin row; support standing never fills them). Flag computed once at mount
(`settings.ex:138-144`) and used to disable every control (`settings.html.heex:910-913`, `:966`,
`:1018-1022`, `:1031`, `:1042-1045`). The save handler re-checks the policy against the current
membership (`settings.ex:371`, `:744-749`).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab and current settings | yes | yes | yes | yes | no (cannot open the project) | yes |
| Change history retention period | no | no | yes | yes | no | no |
| Change I/O storage policy | no | no | yes | yes | no | no |
| Change I/O retention period | no | no | yes | yes | no | no |
| Cancel unsaved changes | no | no | yes | yes | no | no |
| Receive the retention change email | no | no | yes | yes | no | no |

**Preconditions beyond role**
- The I/O retention period select is enabled only when a history period is chosen and the policy is not "Never retain" (`settings.html.heex:1018-1022`).
- The history period select is disabled when the usage limiter offers only one period (`settings.html.heex:910-913`; variant `retention-single-option`).
- A member who hasn't met the project's MFA requirement never reaches this page (shared-project-scope), and every policy check fails for them (`project_users.ex:134`).
- An admin demoted after the page mounted keeps enabled controls but is refused on save (`settings.ex:371`, `membership_revocation_test.exs:300-308`).
- The email goes only to admins and owners who may receive project mail (`projects.ex:787-801`, `user_notifier.ex:69-85`).

## 4. What it touches

**Reads**: `projects` (retention fields via `project_changeset`, `settings.ex:206-207`); `project_users` and `users` for permission (`scope.ex`, via `Permissions.can`, `settings.ex:744-749`); the usage limiter's allowed periods and message at mount (`hooks.ex:229-239`)

**Writes**: `projects.retention_policy`, `projects.history_retention_period`, `projects.dataclip_retention_period` (`settings.ex:348-349`, `:373`, `:771-774`; `projects.ex:589-598`; validated in `project.ex:107-111`, `:231-270`)

**Immediate side effects** (in the same request)
- Audit `project` events `history_retention_period_updated` and `dataclip_retention_period_updated` with before and after values and the acting user, inside the same transaction (`projects.ex:597`, `:620-625`; `audit.ex:20-39`, `:93-97`; `projects_test.exs:3484-3530`; `project_live_test.exs:3545-3563`)
- No audit event for a `retention_policy` change (`audit.ex:21-26`; see 6.1)
- Flash "Project updated successfully" on success (`settings.ex:775-779`)

**Deferred side effects** (later, elsewhere)
- From the next run on, a project set to "Never retain" stores no step input or output: dataclips are written wiped (`usage_limiter.ex:17-21`, `projects.ex:425-435`, `runs/handlers.ex:192-200`, `:440-446`, `:512-522`). Proposed flow `flow-zero-persistence-runs`.
- Channel request and event payload fields are dropped and requests marked wiped (`channels/persistence_policy.ex:20-37`, `channels.ex:605`, `channel_proxy_plug.ex:224`). Same proposed flow.
- Every two hours at minute 17 the `data_retention` Oban job deletes work orders, runs, steps, unreferenced dataclips, channel requests and project files older than the history period, and wipes I/O dataclips older than the I/O period (`bootstrap.ex:301`; `projects.ex:223-245`, `:1734-1788`, `:1806-1889`). Proposed flow `flow-retention-cleanup`.

**External, non-transactional effects**
- Email "The data retention policy for <project> has been modified" to each admin and owner, sent after the transaction commits, only when a period changed (`projects.ex:603-605`, `:782-801`; `user_notifier.ex:172-200`; `projects_test.exs:3338-3429`). Delivery is synchronous and its result is ignored (`projects.ex:796-801`). Proposed flow `flow-data-retention-change-email`.

**Depends on config**
- `Lightning.Extensions.usage_limiter`: which periods are offered and the message beside the history select (`hooks.ex:229-239`; variants `retention-limited`, `retention-single-option`)
- `Lightning.Extensions.project_hook`: may add validation errors to any save (`projects.ex:593`; default is a no-op, `extensions/project_hook.ex:79-81`)

**Product limits**
- Retention periods are 7, 14, 30, 90, 180 or 365 days; leaving history unset keeps history indefinitely (`project.ex:65-67`, `:110-111`)
- On hosted plans, only the plan's periods are offered (variant `retention-limited`, S13)
- Deletion is not immediate: data past its period is removed on the next two-hourly cleanup (`bootstrap.ex:301`)

## 5. Scenarios

```gherkin
Feature: Project data storage
  In order to control how long run history and sensitive I/O data are kept
  As a project admin
  I want to set retention periods and choose whether I/O data is stored at all

  @S01 @pending
  Scenario: A new project keeps everything until an admin decides otherwise
    # Value: no run history or I/O data is deleted before someone has chosen a policy.
    Given project "Malawi HIV" has never had its data storage settings changed
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    Then "Retain all input/output data" is selected
    And the "History Retention Period" select shows "Select Period"
    And the "Input/Output Data Retention Period" select is disabled
    And I do not see "Heads Up!"
    # project.ex:28-33; settings.html.heex:902-916, :956-976, :981-983, :1018-1022
    # project_live_test.exs:3064-3104 (retain_all checked, no heads-up), :3399-3416 (I/O select disabled)

  @S02 @pending
  Scenario: Admin sets the history retention period
    # Value: an admin can make sure run history, which may hold PII, is deleted after an agreed time.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is an owner on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "7 Days" for "History Retention Period"
    And I click "Save"
    Then I see "Project updated successfully"
    And project "Malawi HIV" keeps history for 7 days
    And an audit event "history_retention_period_updated" is recorded with me as the actor
    And the flow "flow-data-retention-change-email" has started for "amara@example.org"
    # settings.html.heex:902-916, :1038-1049; settings.ex:366-374, :770-779; projects.ex:589-605; audit.ex:20-39
    # project_live_test.exs:3545-3563 (audit actor), :3495-3543 (flash); projects_test.exs:3338-3380 (email to admins and owners)

  @S03 @pending
  Scenario: Admin sets the I/O retention period once a history period is chosen
    # Value: an admin can keep I/O data for retries for a shorter time than the run record itself.
    Given I am an admin on project "Malawi HIV" with no history retention period
    When I open the "Data Storage" tab
    Then the "Input/Output Data Retention Period" select is disabled
    When I choose "14 Days" for "History Retention Period"
    Then the "Input/Output Data Retention Period" select is enabled
    When I choose "7 Days" for "Input/Output Data Retention Period"
    And I click "Save"
    Then I see "Project updated successfully"
    And project "Malawi HIV" keeps I/O data for 7 days
    And an audit event "dataclip_retention_period_updated" is recorded with me as the actor
    # settings.html.heex:999-1026; settings.ex:299-323; project.ex:231-270
    # project_live_test.exs:3399-3436, :3495-3543; projects_test.exs:3517-3530

  @S04 @pending
  Scenario: I/O data can't be kept longer than run history
    # Value: sensitive I/O data never outlives the run history it belongs to.
    Given I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "7 Days" for "History Retention Period"
    And I choose "14 Days" for "Input/Output Data Retention Period"
    Then I see "dataclip retention period must be less or equal to the history retention period"
    And the "Save" button is disabled
    # settings.ex:299-323; project.ex:260-266; settings.html.heex:1042-1045
    # project_live_test.exs:3505-3528

  @S05 @pending
  Scenario: Shortening history below the current I/O period is refused
    # Value: an admin can't accidentally leave I/O data configured to outlive the history that references it.
    Given project "Malawi HIV" keeps history for 30 days and I/O data for 30 days
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "7 Days" for "History Retention Period"
    Then I see "dataclip retention period must be less or equal to the history retention period"
    And the "Save" button is disabled
    And project "Malawi HIV" still keeps history for 30 days
    # project.ex:231-238, :260-266; settings.html.heex:1042-1045
    # projects_test.exs:3431-3444 (context only; the UI path is inferred from code)

  @S06 @pending
  Scenario: Admin switches the project to never storing I/O data
    # Value: projects bound by a zero-persistence agreement can stop storing PII payloads, knowing what they give up.
    Given project "Malawi HIV" keeps history for 14 days and I/O data for 7 days
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "Never retain input/output data (zero-persistence)"
    Then I see "Heads Up!"
    And I see "When enabled, you will no longer be able to retry workflow runs, and channel request/response payloads will not be stored."
    And the "Input/Output Data Retention Period" select is disabled and shows no period
    When I click "Save"
    Then I see "Project updated successfully"
    And when I reload the "Data Storage" tab "Never retain input/output data (zero-persistence)" is selected
    And the flow "flow-zero-persistence-runs" has started for project "Malawi HIV"
    # settings.html.heex:956-993, :1018-1022; settings.ex:299-323, :366-374
    # project_live_test.exs:3150-3180 (heads-up copy), :3265-3332 (saved and reloaded), :3438-3493 (I/O select disabled and cleared)

  @S07 @pending
  Scenario: Admin switches back to retaining all I/O data
    # Value: a project that needs to debug or retry runs again can turn storage back on without a superuser.
    Given project "Malawi HIV" never retains I/O data
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "Retain all input/output data"
    Then I do not see "Heads Up!"
    When I click "Save"
    Then I see "Project updated successfully"
    And when I reload the "Data Storage" tab "Retain all input/output data" is selected
    # settings.html.heex:956-983; project_live_test.exs:3265-3332 (second iteration of the loop)

  @S08 @pending
  Scenario: Cancel discards unsaved changes
    # Value: an admin who starts changing a sensitive policy can back out without saving anything.
    Given project "Malawi HIV" retains all I/O data
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    And I choose "Never retain input/output data (zero-persistence)"
    And I click "Cancel"
    Then "Retain all input/output data" is selected
    And project "Malawi HIV" still retains all I/O data
    # settings.html.heex:1029-1037; settings.ex:330-338; project_live_test.exs:3182-3214

  @S09 @pending
  Scenario Outline: Non-admins see the policy but can't change it
    # Value: everyone on the project can check how their data is handled, while only admins decide it.
    Given project "Malawi HIV" keeps history for 30 days
    And I am a <role> on project "Malawi HIV"
    When I open the "Data Storage" tab
    Then I see "Input/Output Data Storage Policy"
    And the "History Retention Period" select shows "30 Days" and is disabled
    And both I/O storage radio buttons are disabled
    And the "Input/Output Data Retention Period" select is disabled
    And the "Cancel" and "Save" buttons are disabled
    # role notice: shared-project-settings-tab-chrome S06 row "editor | Data Storage"
    # settings.html.heex:910-913, :966, :1018-1022, :1031, :1042-1045; project_live_test.exs:3217-3229, :3243-3255 (heading and notice only)

    Examples:
      | role    |
      | viewer  |
      | editor  |
      | support user with no membership row |

  @S10 @pending
  Scenario Outline: A save from a non-admin is refused on the server
    # Value: retention decisions stay with admins even if someone bypasses the disabled controls.
    Given I am a <role> on project "Malawi HIV"
    And project "Malawi HIV" has no history retention period
    When I submit the data storage form with history "14", I/O period "7" and policy "Retain all"
    Then I see "You are not authorized to perform this action."
    And project "Malawi HIV" still has no history retention period
    # settings.ex:366-378, :744-764; project_live_test.exs:3217-3263

    Examples:
      | role   |
      | editor |
      | viewer |

  @S11 @pending
  Scenario: An admin demoted while the page is open can't save
    # Value: losing admin rights takes effect immediately, not when the page is reloaded.
    Given I am an admin on project "Malawi HIV" with the "Data Storage" tab open
    And my role is changed to viewer without the page reloading
    When I choose "Never retain input/output data (zero-persistence)" and click "Save"
    Then I see "You are not authorized to perform this action"
    And project "Malawi HIV" still retains all I/O data
    # settings.ex:371, :744-749; membership_revocation_test.exs:262-274, :300-308

  @S12 @pending
  Scenario: The data storage form can't change other project settings
    # Value: the retention form can't be used to rename the project or flip MFA or support access past their own gates.
    Given I am an admin on project "Malawi HIV"
    When I submit the data storage form with history "14" and also a name "renamed" and requires MFA "true"
    Then I see "Project updated successfully"
    And project "Malawi HIV" keeps history for 14 days
    And its name and MFA requirement are unchanged
    # settings.ex:341-349, :373 (Map.take of retention fields only); inferred from code, no test asserts this

  @S13 @pending @variant:retention-limited
  Scenario: A plan that limits retention offers only its periods and says why
    # Value: admins on a plan with limited retention see exactly what they can choose and why the rest are missing.
    Given project "Malawi HIV" is on a plan that allows history periods of 7 and 14 days
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    Then the "History Retention Period" select offers "7 Days" and "14 Days"
    And it does not offer "30 Days", "90 Days", "180 Days" or "365 Days"
    And the "Input/Output Data Retention Period" select offers the same periods
    And the plan's retention message is shown next to the history select
    # hooks.ex:229-239; settings.html.heex:905-909, :917-930, :1013-1017
    # project_live_test.exs:3334-3370 (options only; the message has no test)

  @S14 @pending @variant:retention-single-option
  Scenario: A plan with a single period can't change history retention
    # Value: admins aren't offered a choice their plan doesn't give them.
    Given project "Malawi HIV" is on a plan that allows only a 7 day history period
    And I am an admin on project "Malawi HIV"
    When I open the "Data Storage" tab
    Then the "History Retention Period" select is disabled
    # settings.html.heex:910-913; project_live_test.exs:3372-3397

  @S15 @pending
  Scenario: A failed save is reported
    # Value: an admin is never left believing a retention change took effect when it didn't.
    Given I am an admin on project "Malawi HIV"
    And recording the audit event will fail
    When I choose "7 Days" for "History Retention Period" and click "Save"
    Then I see "Changes couldn't be saved, please try again"
    And project "Malawi HIV" still has no history retention period
    # settings.ex:784-787; projects.ex:595-616; project_live_test.exs:3565-3590 (flash only)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Changing only the I/O storage policy records no audit event and sends no email, although the email exists to catch unapproved retention changes and lists the policy | `audit.ex:21-26`; `projects.ex:782-785`; `user_notifier.ex:178`, `:190` | switching to or from zero persistence leaves no trace and admins aren't told | decide |
| Saving "Never retain" keeps the old I/O retention period in the database: the I/O select is disabled so the browser doesn't submit it, `validate` only clears it client-side, and the schema clears it only when a period changed. Inferred from code, not run | `settings.html.heex:1018-1022`; `settings.ex:305-308`, `:373`; `project.ex:231-238` | after reload the disabled I/O select shows the old period again; switching back to "Retain all" silently restores it | fix |
| A crafted save with `retention_policy=retain_with_errors` is accepted (the enum still has it), after which `Projects.save_dataclips?/1` has no clause for it and raises | `project.ex:28-30`; `settings.ex:348-349`, `:373`; `projects.ex:425-435`; callers `usage_limiter.ex:19`, `persistence_policy.ex:21` | an admin can put the project in a state where every run's options lookup and every channel request crashes | fix |
| The server validates periods against the fixed list, not the plan's list, so a crafted save can pick a period the plan doesn't offer; choosing the "Select Period" prompt also clears history to unlimited on a limited plan | `project.ex:65-67`, `:110-111`; `hooks.ex:229-239`; `settings.html.heex:904` | admins on limited plans can exceed or remove the plan's retention cap | decide |
| Validation error says "dataclip retention period" under a control labelled "Input/Output Data Retention Period" | `project.ex:265`; `settings.html.heex:1001` | an unfamiliar internal term in the error | fix |
| On a single-period plan, a project with no history period can never set one: the history select is disabled at "Select Period", which also keeps the I/O select disabled | `settings.html.heex:910-913`, `:1018-1022` | admin can't apply the plan's only period. Inferred from code, not run | decide |
| The change email reports an I/O retention period even under "Never retain" (falls back to the history period) and prints "∞ days" when history is unset | `user_notifier.ex:173-191` | contradictory summary: "is not saved" next to "14 days I/O data retention" | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| One `project_changeset` backs the Setup, concurrency and retention forms; a retention `validate` rebuilds it from the saved project plus retention params, dropping unsaved Setup edits, and Cancel here resets the Setup form too | `settings.ex:299-323`, `:330-338`; `settings.html.heex:108`, `:193`, `:877` | decide |
| After a successful save the changeset isn't rebuilt from the saved project (row in project-settings-setup 6.1) | `settings.ex:775-779` | fix |
| Element id `heads-up-description` duplicated with the Setup tab's concurrency warning (row in project-settings-setup 6.2) | `settings.html.heex:216`, `:983` | fix |
| Labels are title case: "History Retention Period", "Input/Output Data Storage Policy", "Input/Output Data Retention Period", "Heads Up!", "Select Period", "7 Days" | `settings.html.heex:886`, `:940`, `:985`, `:1001`, `:904`, `:907` | decide |
| Warning says "When enabled" for a radio choice that is selected, not enabled | `settings.html.heex:990` | decide |
| The I/O section heading greys out when history is unset or policy is "Never retain" | `settings.html.heex:999` | preserve |
| Cancel is enabled even with nothing to discard, and asks no confirmation | `settings.html.heex:1029-1037` | preserve |
| Save shows "Saving" while the request is in flight | `settings.html.heex:1046` | preserve |
| Retention changes take effect without confirmation, although "Never retain" stops retries | `settings.html.heex:1038-1049` | decide |
| CSS class typo `ocus:ring-indigo-600` on the I/O select | `settings.html.heex:1024` | fix |
| "Learn more" links open docs.openfn.org retention and I/O storage pages in a new tab | `settings.html.heex:890-896`, `:944-950` | preserve |
| The limiter message is rendered as either a function component or plain text; any other shape renders an empty span | `settings.html.heex:917-930` | preserve |
| Each sandbox gets the parent's retention settings at creation, then they diverge (banner says changes don't sync on merge) | `sandboxes.ex:104-107` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| "Only retain input/output data when a run fails" (`retain_with_errors`) option | `settings.html.heex:954-955`; `project.ex:28-30`; commented assertions `project_live_test.exs:3084-3090`, `:3109-3116`, `:3123-3148`, `:3277-3279` | commented out pending issue #1694; only reachable by crafted payload (see 6.1) |
| `validate` clause without a `project` key | `settings.ex:325-328` | the retention form always submits the radio, so this tab never hits it (covered by project-settings-setup) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Retention cleanup runs every two hours at minute 17, not on save | `bootstrap.ex:301` | yes, data past its period lingers up to two hours | preserve |
| Cleanup deletes in chunks of `activity_cleanup_chunk_size`, fetches wipe candidates in slices 100 times that, with ten times the default DB timeout | `projects.ex:1736-1784`; `config.ex:85-87` | no | preserve |
| Cleanup jobs retry at most 3 times per project | `projects.ex:239` | no | preserve |
| Retention periods are a fixed menu of six values | `project.ex:65-67` | yes | preserve |

### 6.5 Things seen but not understood

- The test stub's `get_data_retention_message/1` returns its argument (a `%Context{}`), which falls to the empty-span branch; no test covers either message shape (`test/support/stub_usage_limiter.ex:48`; `settings.html.heex:917-930`).
- Named dataclips are never wiped or deleted by retention (`projects.ex:1749`, `:1876-1877`); unclear whether admins are meant to know this exemption from this tab.
- Email delivery failures are ignored and the save still reports success (`projects.ex:796-801`); unclear whether that's intended.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should changing only the I/O storage policy be audited and emailed like a period change (6.1)?
- Should the server enforce the plan's allowed periods, including whether "Select Period" (unlimited) is allowed on limited plans (6.1)?
- Is the single-period plan expected to pre-set history retention elsewhere, so the disabled select is never empty (6.1)?
- Should the three settings forms keep sharing one changeset (6.2)?

## Proposed flows

- `flow-data-retention-change-email`: an admin saves a new history or I/O period here; every admin and owner who may receive project mail gets "The data retention policy for <project> has been modified" with the new values and a link back to `#data-storage` to reset it. Surfaces: project-settings-data-storage, email:data-retention-change (`user_notifier.ex:172-200`, `projects.ex:782-801`), project-settings-data-storage.
- `flow-zero-persistence-runs`: an admin selects "Never retain" here; subsequent runs store wiped dataclips and channel requests drop payloads; history, run and channel request pages show the wiped-data message with a link back here for admins. Surfaces: project-settings-data-storage, capability:run-dataclip-persistence (`runs/handlers.ex:192-200`, `:440-446`, `:512-522`; `projects.ex:425-435`), capability:channel-persistence-policy (`persistence_policy.ex:20-37`), history-work-orders / run-show / channel-request-show (shared-run-components S13; `viewers.ex:320-345`), project-settings-data-storage.
- `flow-retention-cleanup`: an admin sets periods here; the two-hourly `data_retention` Oban job deletes history and wipes I/O data past those periods; the history page no longer lists those work orders and wiped steps can't be rerun. Surfaces: project-settings-data-storage, capability:data-retention-cleanup (`bootstrap.ex:301`, `projects.ex:223-245`, `:1734-1889`), history-work-orders.

## Proposed shared

- none

## Lead resolution (batch 2)

- `flow-data-retention-change-email` and `flow-zero-persistence-runs` created as proposed.
- `flow-retention-cleanup` deferred to the capabilities pass as `capability:data-retention-cleanup`; it is a cron with no surface to start it from.
