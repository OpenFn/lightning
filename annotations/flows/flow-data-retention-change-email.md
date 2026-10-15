---
id: flow-data-retention-change-email
type: flow
title: Changing data retention notifies admins
status: not-started
owner:

trigger:
  entry: project-settings-data-storage
  exit: email:data-retention-change
  surfaces:
    - project-settings-data-storage
    - email:data-retention-change            # UserNotifier.send_data_retention_change_email/2 (user_notifier.ex:170-200)
  reachable_when:
    - the actor passes `:edit_data_retention` on the entry view (project_users.ex:33; settings.ex:366-378; project-settings-data-storage S02, S03)
    - the save changes `history_retention_period` or `dataclip_retention_period` (projects.ex:603-605, :782-785)

inherits:
  - shared-project-scope            # recipients are filtered by the same :access_project standing (mail_recipients.ex:27-32); the email link lands on a project-scoped page

url_params:
  - name: "#data-storage (URL fragment)"
    set_by: email:data-retention-change (user_notifier.ex:195)
    effect: opens the data storage tab client-side (owned by project-settings-data-storage)

config_variants:
  default: { Lightning.Mailer: Swoosh.Adapters.Local in dev, Swoosh.Adapters.Test in test, set from env in prod; require_email_verification: false }
  # config/config.exs:83, config/test.exs:107, lib/lightning/config/bootstrap.ex:388-389, :403-414. Read under default.
  email-verification-required: { REQUIRE_EMAIL_VERIFICATION: true }   # bootstrap.ex:388-389; unconfirmed accounts older than 48h are withheld (accounts.ex:1360-1370)

inventory:
  routes: []                        # entry route owned by project-settings-data-storage
  events:
    - ProjectLive.Settings#save_retention_settings   # entry, owned by project-settings-data-storage (settings.ex:366-378)
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:edit_data_retention to start, project_users.ex:33; :access_project per recipient via MailRecipients.may_receive?, project_users.ex:134-136, mail_recipients.ex:27-32)
  workers: []                       # sent inline, not through Oban (projects.ex:787-801)
  api_endpoints: []
  emails:
    - email:data-retention-change   # "The data retention policy for <project> has been modified" (user_notifier.ex:172-200)
  config:
    - Lightning.Config.instance_admin_email and email_sender_name (sender, user_notifier.ex:26, :53; config.ex:144-158)
    - :lightning, Lightning.Mailer adapter (config/config.exs:83; bootstrap.ex:403-414)
    - :require_email_verification (bootstrap.ex:388-389; accounts.ex:1360-1370)
  not_reachable_here:
    - Projects.update_project/3 called with retention fields from anywhere else; the only UI caller passing them is save_retention_settings (settings.ex:351-359 and :386, :418 pass other fields; sandboxes.ex:752-753 takes only name and color)

related:
  - lib/lightning/projects.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/projects/mail_recipients.ex
  - lib/lightning/mailer.ex
  - lib/lightning/projects/audit.ex
flows: []
---

## 1. Purpose

A retention change decides how long a project's run history and its input/output data (often
health records) are kept, or whether I/O data is kept at all. Any single admin can make that
change, so this flow tells every other admin and owner what the new policy is and gives them a
link to reset it if they didn't approve it. Without it, a retention policy agreed with a partner
could be shortened, lengthened or cleared by one person and nobody else would know until data
went missing or was kept too long.

## 2. What it does

1. A project admin or owner saves a new history or input/output data retention period on the data storage tab.
   - A save that changes no period, or that is rejected, sends nothing
2. Straight away, every admin and owner on the project, including the one who made the change, is emailed the new policy with a link back to the tab to reset it.
   - Editors and viewers aren't emailed, nor are admins who couldn't open the project right now (disabled, unconfirmed, or missing required multi-factor)

**Straightforwardness: 3 of 5.** The idea is simple, but the email misses the change that matters most and can describe the policy wrongly.

### Most surprising behaviours

- **(2)** Switching a project to or from "Never retain" input/output data sends no email at all, even though catching that kind of unapproved change is the whole point. (6.1)
- **(3)** When I/O data isn't kept, the email still lists an I/O retention period, and clearing the history period shows "∞ days" instead of saying data is kept indefinitely. (6.1)
- **(3)** The email doesn't say who made the change or what the old values were, so admins can't easily tell if it's something to undo. (6.2)
- **(3)** If emails fail to send, the admin who saved still sees "Project updated successfully" and nobody learns the others weren't told. (6.1)

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:edit_data_retention` is an admin
action), `:134` (MFA unsatisfied denies everything), `:136` (`:access_project` is any standing).
Recipient selection: `projects.ex:787-801` (role admin or owner), `user_notifier.ex:69-85` and
`mail_recipients.ex:27-32` (per-recipient check).

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| Start the flow by saving a period change | no | no | yes | yes | no | no |
| Receive the email | no | no | yes | yes | no | no |
| Act on the email link (change the policy) | no | no | yes | yes | n/a | n/a |

**Preconditions beyond role**
- The acting admin is a recipient too; nothing excludes them (`projects.ex:787-792`).
- A recipient is withheld when their account is disabled or scheduled for deletion, when it is unconfirmed past 48 hours under `email-verification-required`, or when the project requires MFA and they haven't enrolled (`mail_recipients.ex:28-31`; `accounts.ex:328-332`, `:1360-1370`; `project_users.ex:134`).
- Membership and role are read after the save commits, not when the page loaded (`projects.ex:599-605`, `:788-794`).

## 4. What it touches

**Reads**
- Hop 1 (save, entry view): `projects`; `project_users` and `users` for the policy check (`settings.ex:371`, `:744-749`)
- Hop 2 (recipients, same process): `project_users` joined to `users` where role is admin or owner (`projects.ex:788-794`); per recipient, the scope for `:access_project` (`mail_recipients.ex:31`)

**Writes**
- Hop 1: `projects` retention fields; `audit_events` `history_retention_period_updated` / `dataclip_retention_period_updated` in the same transaction (`projects.ex:589-598`, `:620-625`; `audit.ex:20-39`). Owned by project-settings-data-storage S02, S03.
- Hop 2: none

**Immediate side effects** (in the save request, after commit)
- Email `email:data-retention-change` to each eligible admin and owner, addressed as "First Last <email>" (`projects.ex:603-605`, `:796-801`; `mailer.ex:5-10`)
- Subject "The data retention policy for <project> has been modified"; body lists the history period, whether I/O data is saved, the I/O period, and links to `/projects/<id>/settings#data-storage` (`user_notifier.ex:183-198`)
- Withheld recipients get an info log "Withheld project mail ..." with user and project ids, no address (`user_notifier.ex:77-81`; `user_notifier_test.exs:525-549`)
- Mailer telemetry logs "Email sent" or "Failed to send email" (`mailer.ex:16-23`)

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- The emails. They are sent after the transaction commits, one at a time inside the LiveView process, and their results are discarded (`projects.ex:596-605`, `:796-801`). A delivery failure doesn't affect the save.

**Depends on config**
- Sender name and address (`user_notifier.ex:26`, `:53`)
- Mailer adapter (`config/config.exs:83`; `bootstrap.ex:403-414`)
- Link host from the endpoint URL via `url/1` (`user_notifier.ex:195`)
- `require_email_verification` widens who is withheld (variant `email-verification-required`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Data retention change notice
  In order to catch a retention change I didn't agree to
  As a project admin or owner
  I want an email whenever someone changes how long the project's data is kept

  @S01 @pending
  Scenario: Every admin and owner is emailed the new policy with a link to reset it
    # Value: admins learn of a retention change they didn't make, with the new values, and can undo it.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is an owner and "chen@example.org" is an admin on project "Malawi HIV"
    When I choose "14 Days" for "History Retention Period" and "7 Days" for "Input/Output Data Retention Period" on the "Data Storage" tab
    And I click "Save"
    Then "amara@example.org", "chen@example.org" and I each receive an email with subject "The data retention policy for Malawi HIV has been modified"
    And the email lists "14 days history retention", "input/output (I/O) data is saved for reprocessing" and "7 days I/O data retention"
    And the email links to "/projects/<project id>/settings#data-storage"
    # settings.ex:366-378; projects.ex:589-605, :782-801; user_notifier.ex:172-200
    # projects_test.exs:3338-3380 (admin and owner each get exact subject, recipient and body)

  @S02 @pending
  Scenario: Editors and viewers are not emailed
    # Value: the notice goes only to people who can act on it by changing the policy back.
    Given "bob@example.org" is an editor and "dee@example.org" is a viewer on project "Malawi HIV"
    When an admin saves a new history retention period for project "Malawi HIV"
    Then neither "bob@example.org" nor "dee@example.org" receives a data retention email
    # projects.ex:788-792 (role in [:admin, :owner])
    # projects_test.exs:3382-3399 asserts this, but see 6.5: the refutation can't fail

  @S03 @pending
  Scenario Outline: An admin who couldn't open the project is not sent its policy
    # Value: project details are not mailed to an account that couldn't see them in the app.
    Given "amara@example.org" is an admin on project "Malawi HIV"
    And <condition>
    And "chen@example.org" is an owner on project "Malawi HIV" in good standing
    When an admin saves a new history retention period for project "Malawi HIV"
    Then "chen@example.org" receives the data retention email
    And "amara@example.org" receives no data retention email
    # user_notifier.ex:69-85, :180; mail_recipients.ex:27-32; accounts.ex:328-332, :1360-1370; project_users.ex:134
    # projects_test.exs:4978-5022; user_notifier_test.exs:525-549 (withheld returns {:ok, :suppressed}, logged, nothing sent)

    Examples:
      | condition                                                              |
      | her account is disabled                                                |
      | her account is scheduled for deletion                                  |
      | the project requires MFA and she has not enrolled                      |

    @variant:email-verification-required
    Examples:
      | condition                                                              |
      | her account was created over 48 hours ago and is still unconfirmed     |

  @S04 @pending
  Scenario: An enrolled admin on an MFA-required project is still emailed
    # Value: the MFA filter withholds only from people the gate would stop, so the admins who should know still do.
    Given project "Malawi HIV" requires MFA
    And "amara@example.org" is an admin on it with MFA enabled
    When an admin saves a new history retention period for project "Malawi HIV"
    Then "amara@example.org" receives the data retention email
    # mail_recipients.ex:31; project_users.ex:134-136; projects_test.exs:4960-4976

  @S05 @pending
  Scenario: A save that changes no period sends no email
    # Value: the email stays a signal that the policy actually changed, not noise from every save.
    Given project "Malawi HIV" keeps history for 14 days and I/O data for 7 days
    And I am an admin on project "Malawi HIV"
    When I click "Save" on the "Data Storage" tab without changing anything
    Then I see "Project updated successfully"
    And no admin or owner receives a data retention email
    # projects.ex:603, :782-785 (only when a period is in changeset.changes); settings.ex:775-779
    # projects_test.exs:3401-3412 asserts this, but see 6.5: the refutation can't fail

  @S06 @pending
  Scenario: A rejected save sends no email
    # Value: admins are never told about a retention change that didn't happen.
    Given I am an admin on project "Malawi HIV"
    When I submit the data storage form with history "7" and I/O period "14"
    Then the save is refused with "dataclip retention period must be less or equal to the history retention period"
    And no admin or owner receives a data retention email
    # projects.ex:595-612 (email only in the {:ok, _} branch); project.ex:260-266
    # projects_test.exs:3414-3428 (invalid period) asserts this, but see 6.5
```

The link in the email lands on the data storage tab under shared-project-scope (login redirect,
MFA gate, membership check); what the recipient can do there is owned by
project-settings-data-storage (S02 to S09). Neither is repeated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Changing only the I/O storage policy (to or from "Never retain") sends no email, though the email reports the policy and exists to catch unapproved changes (same row in project-settings-data-storage 6.1) | `projects.ex:782-785`; `user_notifier.ex:178`, `:190` | switching a project to or from zero persistence goes unannounced | decide |
| Under "Never retain" the email still reports an I/O period: it falls back to the history period when `dataclip_retention_period` is nil | `user_notifier.ex:175-176`, `:190-191`; `project.ex:244-247` | "is not saved for reprocessing" next to "14 days I/O data retention" | fix |
| Clearing history to "Select Period" emails "∞ days history retention" and "∞ days I/O data retention" (`"∞" <= 1` is false, so "days") | `user_notifier.ex:173-176`, `:189-191`; `utils.ex:16-17` | an odd glyph and plural instead of "kept indefinitely" | fix |
| Delivery results are discarded; a mailer error is only logged and the admin who saved is told "Project updated successfully" | `projects.ex:796-801`; `mailer.ex:16-19`; `settings.ex:775-779` | nobody learns that the other admins were not told | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The acting admin is emailed about their own change | `projects.ex:787-792` | decide |
| The email doesn't say who made the change or what the previous values were, although the audit event records both | `user_notifier.ex:184-198`; `audit.ex:20-39` | decide |
| Emails are sent synchronously in the LiveView process, one per recipient, so SMTP latency delays the save's flash; other project mail goes through Oban | `projects.ex:796-801`; compare `user_notifier.ex:8-10` | decide |
| Plain text only, no HTML part | `user_notifier.ex:49-55` | preserve |
| Sent by `update_project/3` itself, so any future caller that changes a period (including with `user` nil, which skips the audit) also triggers it | `projects.ex:589-605`, `:620` | preserve |
| Body copy "This policy can be changed by owners and administrators. If you haven't approved this change, please reset the policy" | `user_notifier.ex:193` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `retain_with_errors` reads as "is saved" in the email | `user_notifier.ex:178` | the option is commented out of the form (project-settings-data-storage 6.3); only a crafted save reaches it |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| One permission check (scope build) and one SMTP call per admin and owner, in sequence, inside the save request | `projects.ex:796-801`; `mail_recipients.ex:28-32` | yes, on projects with many admins the save is slow | decide |
| No retry on delivery failure | `user_notifier.ex:49-60` | yes, a transient failure means no email | decide |

### 6.5 Things seen but not understood

- The refutations for editors and viewers, for a no-op save and for a rejected save all match `to: [{"", ^email}]`, but recipients are formatted as "First Last" (`mailer.ex:5-10`), so these `refute_receive` calls can never fail (`projects_test.exs:3392-3397`, `:3407-3412`, `:3423-3428`). S02, S05 and S06 are inferred from code, not proven by those tests.
- No LiveView test asserts the email is sent from the data storage tab; the email assertions are all at the context level (`projects_test.exs:3338-3429`, `:4959-5023`).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a policy-only change (zero persistence on or off) send this email (6.1)?
- Should the email name the actor and the previous values, and should the actor receive it (6.2)?
- Should delivery move to a background job with retries, and should the saving admin ever learn that a notice failed (6.1, 6.4)?

## Proposed flows

- none. Referenced: project-settings-data-storage S02 (entry handoff).

## Proposed shared

- none. Referenced: shared-project-scope (recipient standing and landing gate).
