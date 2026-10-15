---
id: flow-digest-email
type: flow
title: Project digest email, from preference to history
status: not-started
owner:

trigger:
  entry: project-settings-collaborators
  exit: history-work-orders
  surfaces:
    - project-settings-collaborators
    - oban:DigestEmailWorker(daily_project_digest | weekly_project_digest | monthly_project_digest)
    - capability:mail-recipients
    - email:project-digest
    - history-work-orders
    - workflow-health   # added by lead (link lint)
  reachable_when:
    - the member has a project_users row on the project (support users without a row have no digest; digest_email_worker.ex:45-52)
    - the member set their own digest to Daily, Weekly or Monthly (project-settings-collaborators S23)
    - the project is not scheduled for deletion and has at least one workflow that is not deleted (digest_email_worker.ex:48, :66-68; workflows.ex:832)

inherits:
  - shared-project-scope            # the history link lands on a project-scoped page: login, MFA, membership

url_params:
  - name: filters[workflow_id]
    set_by: email:project-digest (user_notifier.ex:331-341)
    effect: workflow chip reads "Workflow is <name>" and only that workflow's work orders are listed (index.html.heex:62-73, invocation.ex:713-717)
  - name: filters[date_after], filters[date_before]
    set_by: email:project-digest (user_notifier.ex:331-341, search_params.ex:177-187)
    effect: last activity chip shows the digest's window; work orders whose last activity falls inside it are listed (index.html.heex:206-226, invocation.ex:741-755)
  - name: filters[log]=true
    set_by: email:project-digest (search_params.ex:167-175)
    effect: search scoped to run logs, matching what a bare visit sets; no search term is sent, so nothing is filtered by it

config_variants:
  default: {}                       # cron in UTC: daily 10:00, weekly Monday 10:00, monthly 1st 10:00 (config/bootstrap.ex:294-299); background queue concurrency 1 (bootstrap.ex:339)
  mfa-required: { project.requires_mfa: true }
  # Read under default. The test build runs Oban inline (config/test.exs:155); the worker tests call perform/1 directly.

inventory:
  routes:
    - live /projects/:project_id/history  RunLive.Index :index   # exit, router.ex:294
  events:
    - ProjectLive.Settings#set_digest                             # entry, owned by project-settings-collaborators (settings.ex:612-645)
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_digest_alerts)          # project_users.ex:51, :101-109, :155-156
    - Lightning.Policies.ProjectUsers (:access_project, via MailRecipients.may_receive?/2)   # mail_recipients.ex:28-32
  workers:
    - Lightning.DigestEmailWorker (Oban cron, queue background, max_attempts 1; digest_email_worker.ex:4-6, :23-42)
  api_endpoints: []
  emails:
    - email:project-digest            # "<Daily|Weekly|Monthly> digest for project <name>" (user_notifier.ex:392-428)
  config:
    - Oban.Plugins.Cron crontab entries for DigestEmailWorker (config/bootstrap.ex:294-299, :325)
    - Oban queue :background (config/bootstrap.ex:339)
    - Lightning.Config.instance_admin_email, email_sender_name (user_notifier.ex:26, :53)
    - require_email_verification flag (accounts.ex:1360-1368, read by mail_recipients.ex:30)
  not_reachable_here:
    - the health link in the same email opens workflow-health, not this flow's exit (user_notifier.ex:373-378); asserted as a link only (S06)

related:
  - lib/lightning_web/live/components/data_tables.ex
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning/projects.ex
  - lib/lightning/digest_email_worker.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/projects/mail_recipients.ex
  - lib/lightning/workorders/search_params.ex
  - lib/lightning/invocation.ex
  - lib/lightning_web/live/run_live/index.ex
  - test/lightning/digest_email_worker_test.exs
  - test/lightning/digest_email_worker_delivery_failure_test.exs
  - test/lightning/accounts/user_notifier_test.exs
flows: []
---

## 1. Purpose

Project members who don't watch the app every day still need to know whether their workflows are
working. This flow lets each member choose a daily, weekly or monthly summary of successful and
failed work orders per workflow, and gives them a link that opens History on exactly that workflow
and window. Without it, a failing integration goes unnoticed until someone downstream complains.

## 2. What it does

1. A project member sets their own digest to daily, weekly or monthly (or never) on the collaborators tab; nobody can set it for someone else.
2. At 10:00 UTC on the matching day, each member who chose that frequency is emailed a summary of the period.
   - Per workflow: how many work orders succeeded and how many failed, counting every kind of failure and leaving out work still in progress
   - Projects being deleted send nothing, and members who couldn't open the project right now (disabled, unconfirmed, or missing required multi-factor) get nothing
3. Each workflow's link opens History filtered to that workflow and the digest's dates, after logging in first if needed.
   - A workflow with failures also links to its failures grouped by error

**Straightforwardness: 3 of 5.** The idea is simple, but the numbers in the email and the list behind the link don't always line up, and a missed digest is easy not to notice.

### Most surprising behaviours

- **(2)** The history link filters by last activity, not by when the work happened, and doesn't filter by status. So the list can show more or fewer work orders than the email counted, especially once something is retried. (6.1, 6.2)
- **(2)** One error while building digests can stop the whole run, so members of unrelated projects silently miss that period's digest, and a failed send is never retried. (6.1, 6.4)
- **(3)** The email says "today" or "this month", but it really covers the last 24 hours, or the previous calendar month, up to 10:00 UTC. A monthly digest on 1 November calls October "this month". (6.1)
- **(3)** A project with workflows but no activity still sends a digest full of zeros, and a work order finishing at exactly 10:00 UTC can be counted in two digests. (6.2)
- **(3)** On a big instance digests are built one after another, so they may arrive well after 10:00 UTC. (6.4)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:51`, `:101-109`, `:155-156` (`:edit_digest_alerts`
is self-only and needs MFA satisfied); `lib/lightning/projects/mail_recipients.ex:28-32` (who may be
sent the email); landing is governed by shared-project-scope.

| Action                                  | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|-----------------------------------------|--------|--------|-------|-------|--------------------|------------------|
| Set own digest frequency                | yes    | yes    | yes   | yes   | n/a                | n/a              |
| Set another member's digest             | no     | no     | no    | no    | no                 | no               |
| Receive the digest                      | yes    | yes    | yes   | yes   | no                 | no               |
| Open the history link and see the list  | yes    | yes    | yes   | yes   | n/a                | n/a              |

**Preconditions beyond role**
- The recipient must pass `MailRecipients.may_receive?/2` when the job runs: account not disabled or scheduled for deletion, not locked out for an unconfirmed address, and `:access_project` true, which includes the project's MFA requirement (`mail_recipients.ex:28-32`, `accounts.ex:329-332`, `:1360-1368`).
- Only rows whose `digest` equals the run's frequency are read; the default is `never` (`project_user.ex:26-31`, `:39`; `digest_email_worker.ex:49`).
- Projects scheduled for deletion are excluded (`digest_email_worker.ex:48`).
- Landing needs the recipient to pass the scope gate when they click (shared-project-scope S01, S03, S05).

## 4. What it touches

**Reads**
- Hop 1 (preference): `project_users` scoped to the project (`settings.ex:627-631`)
- Hop 2 (job): `project_users` joined to `projects`, with `users` (`digest_email_worker.ex:45-52`); `workflows` not deleted (`workflows.ex:826-834`); `projects` again per workflow (`digest_email_worker.ex:160`); `work_orders` counted twice per workflow (`digest_email_worker.ex:162-180`, `invocation.ex:634-639`); `project_users` and `users` for the recipient check (`mail_recipients.ex:28-32`)
- Hop 3 (landing): `work_orders`, `workflows` as history-work-orders

**Writes**
- Hop 1: `project_users.digest` update, only when the value changed (`projects.ex:814-825`); no audit event
- Hop 2: none beyond Oban's own job state
- Hop 3: `user_return_to` in the session when the recipient is signed out (`user_auth.ex:296-298`, `:490-491`)

**Immediate side effects** (in the preference request)
- Flash "Project user updated successfuly" and a refreshed member list (`settings.ex:726-736`)

**Deferred side effects** (in the cron job)
- Three cron entries enqueue the worker (`config/bootstrap.ex:294-299`)
- Email `email:project-digest` per eligible member per project: subject `<Frequency> digest for project <name>`, a header naming the window in UTC, and per workflow the success count, the failure count, a history link, and a health link when failures are above zero (`user_notifier.ex:344-378`, `:392-428`)
- A withheld email logs at info "Withheld project mail ... they may not be sent this project's contents" (`user_notifier.ex:68-84`)
- Mailer telemetry logs "Email sent" or "Failed to send email" (`mailer.ex:16-23`)

**External, non-transactional effects**
- The emails. They are sent one by one inside a single job; there is nothing to roll back.

**Depends on config**
- Cron schedule and its UTC timezone (`config/bootstrap.ex:294-299`)
- `require_email_verification` decides whether an unconfirmed address older than 48 hours is withheld (`accounts.ex:1362-1368`)
- Sender name and address (`user_notifier.ex:26`, `:53`); link host from the endpoint URL (`user_notifier.ex:340`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Project digest email
  In order to know how my workflows are doing without watching the app
  As a member of a project
  I want a periodic summary by email that links to the matching history

  @S01 @pending
  Scenario: A weekly digest reaches the member and its link opens the matching history
    # Value: a member learns how each workflow did over the week, and lands on exactly the work orders behind the numbers.
    Given I am a viewer on project "Malawi HIV" with workflow "Intake"
    And I set my digest to "Weekly" on the collaboration tab
    And "Intake" had 3 successful and 1 failed work order in the last 7 days
    When the weekly digest runs on Monday at 10:00 UTC
    Then I receive an email with subject "Weekly digest for project Malawi HIV"
    And it says "3 workorders were successful this week" and "1 workorders were not" under "Intake:"
    When I, logged in, open the "See these runs in history" link for "Intake"
    Then I am on the history page of "Malawi HIV"
    And the workflow chip reads "Workflow is Intake"
    And the last activity chip shows the digest's window
    And I see the 4 work orders
    # data_tables.ex:520-559; settings.ex:612-645; projects.ex:814-825; bootstrap.ex:296-297
    # digest_email_worker.ex:30-35, :44-88, :159-185; user_notifier.ex:331-378, :392-428
    # index.ex:182-186; index.html.heex:62-73, :206-226; invocation.ex:713-717, :741-755
    # user_notifier_test.exs:178-206 (link path and params), :293-376 (weekly body)

  @S02 @pending
  Scenario: Failures are counted across every failure state, and in-progress work is not
    # Value: the failure number a member reads is every work order that needs attention, and only those.
    Given workflow "Intake" has work orders that are failed, crashed, killed, exception, lost and rejected, one success, and one pending and one running
    When my daily digest is built
    Then "Intake" shows 1 successful and 6 not successful
    # digest_email_worker.ex:162-198; workorder.ex:48-58
    # digest_email_worker_test.exs:108-198

  @S03 @pending
  Scenario: Only members who chose a frequency get that frequency's digest
    # Value: people only receive the project email they asked for, at the cadence they asked for.
    Given on project "Malawi HIV" Amara's digest is "Daily", Bob's is "Weekly" and Chen's is "Never"
    When the daily digest runs
    Then Amara receives "Daily digest for project Malawi HIV"
    And Bob and Chen receive no digest
    # project_user.ex:26-31, :39; digest_email_worker.ex:45-52; bootstrap.ex:294-299
    # digest_email_worker_test.exs:31-86

  @S04 @pending @variant:mfa-required
  Scenario: The digest is withheld from someone who could not open the project
    # Value: a project's health data never reaches an inbox whose owner could not see it in the app.
    Given project "Malawi HIV" requires MFA
    And Amara (enrolled in MFA) and Bob (not enrolled) both chose "Daily"
    And Chen chose "Daily" but his account is disabled
    When the daily digest runs
    Then Amara receives the digest
    And Bob and Chen receive no digest
    # user_notifier.ex:67-85, :427; mail_recipients.ex:28-32; accounts.ex:329-332
    # digest_email_worker_test.exs:211-305

  @S05 @pending
  Scenario: A project being deleted sends no digests
    # Value: a project that is being wound down stops mailing its members.
    Given project "Malawi HIV" is scheduled for deletion
    And Amara chose "Daily"
    When the daily digest runs
    Then Amara receives no digest for "Malawi HIV"
    # digest_email_worker.ex:48; digest_email_worker_test.exs:9-28

  @S06 @pending
  Scenario: A workflow with failures also links to its failures grouped by error
    # Value: a member who sees failures can go straight to triage by cause.
    Given "Intake" had 2 failed work orders and "Sync" had none in the period
    When my digest arrives
    Then under "Intake" I see "See this workflow's failures grouped by error" linking to the workflow health page
    And under "Sync" I see only the history link
    # user_notifier.ex:365-382; router.ex:304
    # user_notifier_test.exs:208-291 (daily body)

  @S07 @pending
  Scenario: A signed-out recipient returns to the filtered history after logging in
    # Value: the link still lands on the right work orders when opened from a device that isn't logged in.
    Given I received a digest for "Malawi HIV"
    And I am not logged in
    When I open the "See these runs in history" link for "Intake"
    Then I am asked to log in
    When I log in
    Then I am on the history page with the workflow chip "Workflow is Intake" and the digest's window
    # user_auth.ex:288-298, :490-491 (current_path keeps the query string)
```

Setting the preference, and refusing to set someone else's, are owned by project-settings-collaborators
S23 and S24. A recipient removed or unenrolled between the email and the click is handled by
shared-project-scope S03 and S05. Neither is repeated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The per-workflow line says "successful today" for a daily digest and "this month" for a monthly one, but the window is the 24 hours, or the calendar month, ending at 10:00 UTC on the send day | `user_notifier.ex:352`, `:357`; `digest_email_worker.ex:142-153` | a monthly digest sent on 1 November describing October as "this month" | fix |
| The history link filters on last activity, so a work order retried after the digest moves out of the window; the code comment says the link "still shows the runs these counts came from however long the mail sits unread" | `user_notifier.ex:365-368`; `invocation.ex:741-755` | history listing fewer work orders than the email counted | decide |
| A refused send is grouped as `failed` and the job still returns `{:ok, ...}` with `max_attempts: 1`, so nobody is retried | `digest_email_worker.ex:4-6`, `:90-97`, `:138-140` | that member gets no digest for the period; only a log line records it | decide |
| One exception (for example `Projects.get_project!` per workflow) aborts the single job, so every later project in that run gets no digest | `digest_email_worker.ex:60-88`, `:160` | members of unrelated projects silently miss a digest | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The history link carries no status filter, so the list includes pending, running and cancelled work orders that neither count includes | `user_notifier.ex:331-341`; `digest_email_worker.ex:162-180` | decide |
| Cancelled work orders are in neither count, and the failure line names the failure states followed by "etc." | `workorder.ex:48`; `user_notifier.ex:353`, `:358` | decide |
| A digest is sent with zero counts when the project has workflows but no activity; only a project with no workflows is skipped | `digest_email_worker.ex:68-86`; `digest_email_worker_test.exs:373-390` | decide |
| Because the link always carries `filters`, History's 30-day default window does not apply on landing (history-work-orders 6.2) | `index.ex:133`, `:182`; `search_params.ex:167-175` | preserve |
| The link adds `filters[log]=true` so the search-field toggles render consistently | `search_params.ex:163-175`; `user_notifier_test.exs:197-200` | preserve |
| Dates in the email header are formatted in UTC with the zone shown; the history chip shows them from the URL as UTC | `user_notifier.ex:420`; `helpers.ex:132-137` | decide |
| Window bounds are inclusive at both ends, so a work order whose last activity is exactly 10:00 UTC can appear in two consecutive digests | `invocation.ex:743-755`; `digest_email_worker.ex:24-27` | decide |
| Changing the digest writes no audit event | `projects.ex:814-825` | decide |
| Success flash copy reads "successfuly" | `settings.ex:735` | fix |
| The email is plain text only | `user_notifier.ex:49-55` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| One job per frequency handles every project and member sequentially on the `background` queue (concurrency 1), with two count queries and a project lookup per workflow | `digest_email_worker.ex:44-88`, `:159-185`; `bootstrap.ex:339` | yes on large instances: digests arrive later than 10:00 UTC | preserve |
| Single attempt per run | `digest_email_worker.ex:4-6` | yes, a crashed run means no digest that period | decide |

### 6.5 Things seen but not understood

- The worker's `@moduledoc` is false and its `perform` doc mentions only the daily run "everyday at 10am"; unclear whether 10:00 UTC was chosen for any particular audience.
- No test drives the flow end to end: the preference test stops at the select (`project_live_test.exs:4507-4526`), the worker tests call `perform/1` directly, and no LiveView test opens History with a digest URL.
- Sandbox projects are ordinary `projects` rows here, so a sandbox member with a digest set gets one; unclear whether that is intended.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the copy say "in the last day/week/month" rather than "today/this week/this month"? (6.1)
- Should the history link be pinned to the work orders counted (e.g. by created date or ids) rather than last activity? (6.1)
- Should a failed send be retried, and should a crash in one project stop digests for the rest? (6.1, 6.4)
- Should a project with workflows but no activity in the period still send a digest? (6.2)

## Proposed flows

- none. Referenced: project-settings-collaborators S23 (entry handoff) and S24 (others cannot change it); history-work-orders `url_params` for `filters[workflow_id]`, `filters[date_after]`, `filters[date_before]` (exit). The health link (S06) hands off to workflow-health; flow-workflow-health-drilldown covers what happens there.

## Proposed shared

- none. Referenced: shared-project-scope (landing gate). `capability:mail-recipients` (`MailRecipients.may_receive?/2`) is also used by failure alerts and retention notices; it may deserve its own capability annotation.
