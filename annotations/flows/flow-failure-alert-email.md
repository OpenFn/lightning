---
id: flow-failure-alert-email
type: flow
title: Failure alert email, from preference to history
status: not-started
owner:

trigger:
  entry: project-settings-collaborators
  exit: history-work-orders
  surfaces:
    - project-settings-collaborators
    - controller:run-channel-complete           # LightningWeb.RunChannel "run:complete" (run_channel.ex:122-138)
    - oban:Janitor                              # lost runs, cron every 5 minutes (janitor.ex:36-48, config/bootstrap.ex:291)
    - capability:failure-alerter                # Lightning.FailureAlerter (pipeline/failure_alerter.ex)
    - email:failure-alert                       # Lightning.FailureEmail + failure_alert.html.heex
    - history-work-orders
    - run-show                                  # alternate exit: "view run" link, added by lead
    - workflow-health                           # alternate exit: health link, added by lead
  reachable_when:
    - the member has a project_users row with failure_alert true (accounts.ex:1349-1355)
    - a run of one of the project's workflows reaches a final state other than success (failure_alerter.ex:12-17)

inherits:
  - shared-project-scope            # the email link lands on a project-scoped page: login, MFA, membership

url_params:
  - name: filters[workorder_id]
    set_by: email:failure-alert (failure_alerter.ex:75-79)
    effect: History lists only that work order, shows a "Work order: <short id>" chip and expands it with every run (owned by history-work-orders S10)

config_variants:
  default: { Lightning.FailureAlerter: { time_scale: 300000, rate_limit: 3 }, usage_limiter: always :ok, hammer: Mnesia backend }
  # config/config.exs:24-27, :193-195, :41-43. The test build uses time_scale 60000 and an ETS backend (config/test.exs:125-132).
  failure-alerts-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(%{type: :alert_failure}) returns {:error, _, _}> }
  email-verification-required: { REQUIRE_EMAIL_VERIFICATION: true }   # config/bootstrap.ex:387-389
  # Read under default, plus the test build's MockUsageLimiter and MockConfig stubs (failure_alert_test.exs:15-29, :240-268, :443-466).

inventory:
  routes:
    - live /projects/:project_id/history  RunLive.Index :index   # exit, router.ex:294
  events:
    - ProjectLive.Settings#set_failure_alert       # entry, owned by project-settings-collaborators (settings.ex:612-645)
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_failure_alerts self-only, project_users.ex:51, :96-110)
    - Lightning.Policies.ProjectUsers (:access_project, via MailRecipients.may_receive?, project_users.ex:134-136, mail_recipients.ex:27-32)
  workers:
    - Lightning.Janitor (Oban, queue background, cron */5; janitor.ex:13-17, config/bootstrap.ex:291)
  api_endpoints: []
  emails:
    - email:failure-alert             # subject "\"<workflow>\" (<project>) failed" (failure_email.ex:9-19)
  config:
    - :lightning, Lightning.FailureAlerter, time_scale and rate_limit (config/config.exs:193-195)
    - :hammer backend (config/config.exs:24-27)
    - :lightning, Lightning.Extensions, :usage_limiter (limit_action :alert_failure, project_limiter.ex:9-15)
    - :lightning, :require_email_verification (config/bootstrap.ex:387-389, accounts.ex:1360-1368)
    - Lightning.Config.email_sender_name, instance_admin_email (failure_email.ex:25-28)
  not_reachable_here:
    - The run link (/projects/:id/runs/:run_id) and health link (/projects/:id/w/:workflow_id/health) in the same email exit to run-show and workflow-health; not covered here (see section 6.5)

related:
  - lib/lightning/pipeline/failure_alerter.ex
  - lib/lightning/pipeline/failure_email.ex
  - lib/lightning_web/templates/failure_notifier/failure_alert.html.heex
  - lib/lightning/projects/mail_recipients.ex
  - lib/lightning/projects/project_limiter.ex
  - lib/lightning_web/channels/run_channel.ex
  - lib/lightning/janitor.ex
  - lib/lightning_web/live/run_live/index.ex
flows: []
---

## 1. Purpose

People responsible for a workflow need to know when it fails, without watching History all day.
This flow lets each member opt in to failure alerts on the collaboration tab; when a run fails,
every opted-in member who may still see the project gets an email naming the workflow and project,
and its link opens History on that failed work order, already expanded. Without it, a failed
delivery of health data is noticed only when someone downstream complains.

## 2. What it does

Member enables their own failure alert on the collaboration tab; a run ends in a non-success state (worker report or janitor marking it lost); the alerter emails each opted-in, eligible member, at most 3 per workflow per 5 minutes; the email's link opens History filtered to and expanding the failed work order, after login if needed.

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:51`, `:96-110` (preference is self-only),
`:134-136`, `:193-194` (access); recipients from `accounts.ex:1349-1355`; eligibility from
`mail_recipients.ex:27-32`. Landing is governed by shared-project-scope.

| Action                                   | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|------------------------------------------|--------|--------|-------|-------|--------------------|-----------------------------|
| Turn own failure alert on or off         | yes    | yes    | yes   | yes   | n/a                | n/a                         |
| Receive the alert when opted in          | yes    | yes    | yes   | yes   | no                 | no (query joins `project_users`) |
| Open the link and land on the work order | yes    | yes    | yes   | yes   | no                 | yes                         |

**Preconditions beyond role**
- The project's plan must allow `:alert_failure`, checked once per failed run before any recipient is considered (`failure_alerter.ex:20`, `project_limiter.ex:11-15`).
- The recipient's account must not be disabled or scheduled for deletion (`accounts.ex:329-332`), nor locked out pending email confirmation under `email-verification-required` (`accounts.ex:1360-1368`).
- The recipient must hold `:access_project` on the project at send time: MFA enrolled if the project requires it, project not scheduled for deletion (`mail_recipients.ex:28-31`, `project_users.ex:134`; `scope.ex:149`).
- At most `rate_limit` emails per recipient per workflow per `time_scale` window (`failure_alerter.ex:87-94`).

## 4. What it touches

**Reads**
- Hop 1 (preference): `project_users` (owned by project-settings-collaborators S22)
- Hop 2 (run ends): `runs`, `work_orders`, `workflows` (`run_channel.ex:128-130`, `janitor.ex:46-47`)
- Hop 3 (alerter): `projects` (`failure_alerter.ex:21`), `users` joined to `project_users` where `failure_alert` (`accounts.ex:1349-1355`), the recipient's project standing (`mail_recipients.ex:31`)
- Hop 4 (landing): `work_orders`, `runs` for the filtered list (history-work-orders)

**Writes**
- Hop 1: `project_users.failure_alert` (`projects.ex:814-825`)
- Hop 2: `runs.state` (run completion, or `lost` by the janitor, `janitor.ex:44`)
- Hop 3: none in the database; increments the Hammer bucket `"<workflow_id>::<user_id>"`, and decrements it when delivery fails (`failure_alerter.ex:88-94`, `:117-124`)

**Immediate side effects**
- Hop 1: success flash "Project user updated successfuly" (`settings.ex:726-735`)
- Hop 2 and 3, in the same process as the run completion: for each eligible recipient, `email:failure-alert` sent synchronously through `Mailer.deliver/1` (`run_channel.ex:131-132`, `failure_alerter.ex:97-110`, `failure_email.ex:21-49`)
- Refused recipients: an info log "Withheld failure alert from user <id> in project <id>" (`failure_alerter.ex:49-52`)
- Mailer telemetry logs "Email sent" or "Failed to send email" (`mailer.ex:16-27`)

**Deferred side effects**
- Lost runs are alerted by the janitor's cron run, up to 5 minutes later plus the run timeout (`config/bootstrap.ex:291`, `janitor.ex:36-48`)

**External, non-transactional effects**
- The email. From the janitor it is sent inside `Repo.transaction` (`janitor.ex:41-48`), so a rollback after sending leaves an alert for a loss that was not recorded.

**Depends on config**
- Rate limit and window (`config/config.exs:193-195`); the email states them (`failure_alert.html.heex:11-17`)
- Usage limiter adapter for `:alert_failure` (variant `failure-alerts-limited`)
- `REQUIRE_EMAIL_VERIFICATION` (variant `email-verification-required`)
- Sender name and address (`failure_email.ex:25-28`); link host from the endpoint URL (`failure_alerter.ex:69-85`)

**Product limits**
- Three alerts per workflow per recipient per five minutes; later failures in the window send nothing (`config/config.exs:193-195`, `failure_alerter.ex:130-131`)

## 5. Scenarios

```gherkin
Feature: Failure alert email
  In order to find out quickly when a workflow fails and get to the failure
  As a project member who has opted in
  I want an email for each failed run that takes me to the failed work order

  @S01 @pending
  Scenario: An opted-in member is emailed about a failed run and opens the work order from it
    # Value: the person responsible learns of a failure without watching History, and gets straight to the failed work order.
    Given I am an editor named "Amara" on project "Malawi HIV" with failure alerts disabled
    When I set my failure alert to "Enabled" on the collaboration tab
    And a run of workflow "Daily sync" succeeds
    Then I receive no failure alert
    When a run of workflow "Daily sync" fails in work order "W"
    Then I receive an email with subject "\"Daily sync\" (Malawi HIV) failed"
    And it says "A \"Daily sync\" run just failed in \"Malawi HIV\"."
    When I open the work order link in the email
    Then I am on the history page of "Malawi HIV"
    And I see only work order "W", expanded, with a chip "Work order: <short id of W>"
    # settings.ex:612-645; projects.ex:814-825; run_channel.ex:122-138; failure_alerter.ex:12-38, :75-79, :97-110
    # failure_email.ex:9-19; failure_alert.html.heex:2-9; index.ex:133, :930-942; index.html.heex:288-296
    # failure_alert_test.exs:296-336 (run:complete with reason "crash" sends the subject), :139-155 (body, work order id)

  @S02 @pending
  Scenario: Members who have not opted in, or opted out, get no alert
    # Value: members only receive failure mail they asked for, and can stop it themselves.
    Given "Bob" was just added to project "Malawi HIV" and has not changed his failure alert
    And I am a member with failure alerts enabled
    When I set my failure alert to "Disabled" on the collaboration tab
    And a run of a workflow in "Malawi HIV" fails
    Then neither Bob nor I receive a failure alert
    # project_user.ex:37 (default false); project_live_test.exs:597-605; accounts.ex:1349-1355
    # failure_alert_test.exs:225-238

  @S03 @pending
  Scenario: Repeated failures of one workflow are capped, other workflows still alert
    # Value: a workflow failing in a loop does not bury the inbox, and a failure elsewhere still gets through.
    Given I have failure alerts enabled on project "Malawi HIV"
    When runs of workflow "Daily sync" fail 4 times within 5 minutes
    Then I receive emails with subjects "\"Daily sync\" (Malawi HIV) failed", "... failed 2 times in the last 5 minutes" and "... failed 3 times in the last 5 minutes"
    And the second and third say "We will only send 3 failure alerts for this workflow (\"Daily sync\") at most every 5 minutes"
    And I receive no fourth email
    When a run of workflow "Weekly report" fails in the same window
    Then I receive "\"Weekly report\" (Malawi HIV) failed"
    # failure_alerter.ex:87-96, :130-131; failure_email.ex:14-18; failure_alert.html.heex:11-17; config/config.exs:193-195
    # failure_alert_test.exs:121-171, :189-223 (asserted under the test window of 1 minute)

  @S04 @pending @variant:failure-alerts-limited
  Scenario: No alerts are sent when the plan doesn't include them
    # Value: the plan limit holds at send time, not only in what the settings tab shows.
    Given failure alerts are not available for project "Malawi HIV"
    And my project_users row has failure_alert true
    When a run of a workflow in "Malawi HIV" fails
    Then I receive no failure alert
    And the collaboration tab shows my failure alert as "Unavailable" (project-settings-collaborators S25)
    # failure_alerter.ex:20; project_limiter.ex:11-15; failure_alert_test.exs:240-268

  @S05 @pending
  Scenario Outline: Opted-in members who may not see the project are not emailed
    # Value: a failure alert never sends project details to someone who could not open the project in the app.
    Given I have failure alerts enabled on project "Malawi HIV"
    And <condition>
    When a run of a workflow in "Malawi HIV" fails
    Then I receive no failure alert
    And other opted-in members still receive theirs

    Examples:
      | condition                                                        |
      | my account is disabled                                           |
      | my account is scheduled for deletion                             |
      | the project requires MFA and I have not enrolled                 |
      | the project is scheduled for deletion                            |
    # failure_alerter.ex:45-56; mail_recipients.ex:28-31; accounts.ex:329-332; project_users.ex:134-136
    # failure_alert_test.exs:359-400, :402-439, :493-506; enrolled-member counterpart :340-357

  @S06 @pending @variant:email-verification-required
  Scenario: An account barred pending email confirmation is not emailed
    # Value: alerts don't go to an address nobody has shown they own.
    Given email verification is required on the instance
    And I signed up more than 48 hours ago and never confirmed my email
    And I have failure alerts enabled on project "Malawi HIV"
    When a run of a workflow in "Malawi HIV" fails
    Then I receive no failure alert
    # mail_recipients.ex:10-13, :30; accounts.ex:1360-1368; failure_alert_test.exs:443-466

  @S07 @pending
  Scenario: The alert links to logs rather than carrying them
    # Value: sensitive values a job logs (patient ids, payloads) are not copied into people's inboxes.
    Given I have failure alerts enabled on project "Malawi HIV"
    And a failed run logged "patient_id=12345"
    When I receive its failure alert
    Then the email does not contain "patient_id=12345"
    And it links to that run's page
    # failure_alert.html.heex:4-9; failure_alerter.ex:69-73; failure_alert_test.exs:173-187

  @S08 @pending
  Scenario: A run that stops reporting is alerted once the janitor marks it lost
    # Value: a run whose worker died is not a silent failure.
    Given I have failure alerts enabled on project "Malawi HIV"
    And a run of workflow "Daily sync" was claimed longer ago than its timeout and never completed
    When the janitor runs
    Then the run is marked lost
    And I receive "\"Daily sync\" (Malawi HIV) failed"
    # janitor.ex:36-48; config/bootstrap.ex:291; janitor_test.exs:10-107

  @S09 @pending
  Scenario: A signed-out recipient is returned to the work order after logging in
    # Value: the alert still works when opened on a device where the person isn't logged in.
    Given I received a failure alert for work order "W" in "Malawi HIV"
    And I am not logged in
    When I open the work order link in the email
    Then I am asked to log in
    When I log in
    Then I am on the history page with only work order "W", expanded
    # router.ex:294; user_auth.ex:490-491 (current_path keeps the query string), :63-69
```

The landing step inherits shared-project-scope: a recipient removed from the project between the
email and the click is told the project was not found (shared-project-scope S03), and is in any
case no longer emailed, since recipients are re-read per failure.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Every final state except success alerts, including a worker-reported `cancel` or `kill`, and the copy always says "just failed" | `failure_alerter.ex:14-17`; `run.ex:46-54`, `:79-87`; `failure_alert.html.heex:5` | a "failed" alert for a run that was cancelled | decide |
| The "failed N times" count is the number of alerts this recipient's bucket has counted for the workflow in the current window, not the number of failures; a member who opted in mid-burst, or whose earlier sends failed (decremented), sees a lower number | `failure_alerter.ex:88-101`, `:117-124`; `failure_email.ex:14-18` | a subject that understates how often the workflow failed | decide |
| The rate window is a fixed Hammer bucket, not a sliding window, so "in the last 5 minutes" can span two buckets and allow up to 6 emails in a 5-minute stretch | `failure_alerter.ex:90-94`; `failure_email.ex:17` | more alerts than the email says will be sent | decide |
| Janitor alerts are sent inside the transaction that marks runs lost; a later failure in the transaction rolls back the state but not the emails | `janitor.ex:41-48`, `:67-69` | an alert for a run that History still shows as running | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The alerter runs synchronously inside the run channel's `run:complete` handler, one mail call per recipient, before replying to the worker (a TODO says to move it to Oban) | `run_channel.ex:125-132` | decide |
| Delivery failure is swallowed; only the mailer telemetry logs it, and the rate bucket is decremented | `failure_alerter.ex:111-128`, `mailer.ex:16-19` | decide |
| A refused recipient is checked before the rate limiter, so their bucket is never touched | `failure_alerter.ex:40-56`; `failure_alert_test.exs:402-439` | preserve |
| Withheld alerts are logged at info with user and project ids, never the address | `failure_alerter.ex:49-52`; `failure_alert_test.exs:470-489` | preserve |
| The email is addressed to the bare address, without the recipient's name (other mail uses the `User` recipient protocol) | `failure_alerter.ex:97`; `mailer.ex:5-10`; `failure_alert_test.exs:353` | decide |
| HTML-only body, rendered from `failure_alert.html.heex`; greets by first name | `failure_email.ex:39-46`, `failure_alert.html.heex:2` | decide |
| The work order link sets only `filters[workorder_id]`, so History skips its 30-day default and finds the work order at any age (history-work-orders 6.2 lists the default as `decide`) | `failure_alerter.ex:75-79`; `index.ex:133`, `:157-169` | preserve |
| Support users and superusers without a membership row can never receive alerts, even with support access on | `accounts.ex:1349-1355` | decide |
| Alerts default off for every new membership | `project_user.ex:37` | preserve |
| Recipients and eligibility are re-read per failed run, so preference and access changes take effect on the next failure | `failure_alerter.ex:21-25`, `:46` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `alert_on_failure(nil)` clause | `failure_alerter.ex:12` | both callers pass a preloaded `%Run{}` (`run_channel.ex:128-132`, `janitor.ex:46-48`) |
| Commented-out `{:cancel, ...}` returns | `failure_alerter.ex:115`, `:127`, `:132` | comments left from an Oban worker version |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Three alerts per recipient per workflow per five minutes; not configurable by env | `config/config.exs:193-195` | yes, stated in the email | preserve |
| Hammer buckets live in Mnesia with 4-hour expiry and 10-minute cleanup | `config/config.exs:24-27` | no | decide |
| One synchronous mail send per recipient in the worker's completion path; a slow mail provider or many subscribers delays the reply to the worker | `run_channel.ex:125-132` | no, worker-side latency | decide |
| Lost runs are found every five minutes | `config/bootstrap.ex:291` | yes, alert for a lost run arrives later | preserve |

### 6.5 Things seen but not understood

- The same email links to the run page and to the workflow's health page (`failure_alert.html.heex:6-8`, `:19-21`; `failure_alerter.ex:69-73`, `:81-85`). Those exits land on run-show and workflow-health and are not covered by any flow yet.
- Under the Mnesia backend it is unclear whether the rate limit is shared across nodes in a multi-node deployment or counted per node.
- `failure_alert_test.exs:270-294` inspects the Hammer bucket keyed by the workflow id alone, but the alerter keys by `"<workflow_id>::<user_id>"` (`failure_alerter.ex:88`), so that test cannot see the decrement it describes. Several tests also drain a `workflow_failures` Oban queue (`failure_alert_test.exs:134`, `:201`) that the alerter no longer uses (`config/bootstrap.ex:338`).
- If the work order is later removed by data retention, the link opens History with the chip and an empty list; no test covers that landing.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Lead: run-show and workflow-health are now listed as alternate exits (see 6.5). Add a handoff scenario for each before this flow can be marked migrated.

- Should cancelled and killed runs send a "failed" alert, or a differently worded one, or none?
- Should the alerter move off the run channel into a background job, and should failed deliveries be retried?
- Should support users with access on be able to opt in to alerts?
- Should the subject count failures rather than alerts sent?

## Proposed flows

- none. Referenced: project-settings-collaborators S22 (entry), S25 (Unavailable display); history-work-orders S10 (landing). The run-page and health-page links in the same email are noted in 6.5 rather than proposed.

## Proposed shared

- none. Referenced: shared-project-scope (landing gate).
