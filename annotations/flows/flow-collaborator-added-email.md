---
id: flow-collaborator-added-email
type: flow
title: Existing user added to a project gets an access email
status: not-started
owner:

trigger:
  entry: project-settings-collaborators
  exit: workflows-index
  surfaces:
    - project-settings-collaborators
    - oban:UserNotifier(project_addition)
    - email:project-addition
    - workflows-index
    - admin-projects   # added by lead: superuser project form also queues this email
    - projects-dashboard   # added by lead (link lint)
  reachable_when:
    - the actor can add collaborators on the entry view (project-settings-collaborators S02)
    - at least one submitted email belongs to a registered user who is not yet on the project

inherits:
  - shared-project-scope            # the email link lands on a project-scoped page: login, MFA, membership

url_params: []                      # the link carries no params; it is /projects/:project_id/w (user_notifier.ex:147)

config_variants:
  default: {}                       # Oban queue background, concurrency 1 (config/bootstrap.ex:336-339)
  # Read under default. The test build runs Oban inline (config/test.exs:155), so the email is sent
  # inside the add request there; in production it is delivered later by the background queue.

inventory:
  routes:
    - live /projects/:project_id/w  WorkflowLive.Index :index   # exit, router.ex:288, :301
  events:
    - ProjectLive.NewCollaboratorComponent#add_collaborators     # entry, owned by project-settings-collaborators
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:add_project_user)          # project_users.ex:29-37
  workers:
    - Lightning.Accounts.UserNotifier (Oban, type project_addition; user_notifier.ex:8-10, :28-46)
  api_endpoints: []
  emails:
    - email:project-addition          # "You now have access to \"<project>\"" (user_notifier.ex:135-151)
  config:
    - Lightning.Config.instance_admin_email (sender address, user_notifier.ex:26, :53)
    - Lightning.Config.email_sender_name (sender name, user_notifier.ex:53)
    - Oban queue :background (config/bootstrap.ex:339)
  not_reachable_here:
    - Projects.create_project/2 and the superuser project form also schedule this email (projects.ex:562-567, :648; form_component.ex:166-170, :184); those entries are outside this flow's scope (see section 6.5)

related:
  - lib/lightning_web/live/project_live/new_collaborator_component.ex
  - lib/lightning/projects.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/mailer.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/route_helpers.ex
flows: []
---

## 1. Purpose

When a project admin adds someone who already has an OpenFn account, that person is in the
project at once but would otherwise have no way of knowing. This flow tells them, by email, which
project they can now reach and with what role, and gives them a link that opens the project's
workflows. Without it, the admin has to tell each new collaborator out of band, and the new
collaborator has to find the project themselves.

## 2. What it does

Admin adds an existing user on the collaboration tab; a background job emails that user "You now have access to <project>" with their role; the link opens the project's workflows page, after login if needed.

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:29-37` (`:add_project_user` is an admin action),
re-checked at submit in `new_collaborator_component.ex:41-47`. Landing is governed by
shared-project-scope.

| Action                                   | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|------------------------------------------|--------|--------|-------|-------|--------------------|------------------|
| Start the flow by adding an existing user | no     | no     | yes   | yes   | no                 | no               |
| Receive the email                        | the added person, whatever role they were given (`projects.ex:836-847`) | | | | | |
| Open the link and land on the project    | yes    | yes    | yes   | yes   | n/a                | n/a              |

**Preconditions beyond role**
- Only people who were not members before the save are emailed (`projects.ex:837-841`).
- Only the "add existing users" path sends this email. The invite path for people without accounts does not (`projects.ex:2033-2045` builds the membership without scheduling; project-settings-collaborators S10 asserts no "You now have access to" email).
- Landing on the project needs the recipient to pass the scope gate when they click: logged in (or log in first), membership still present, MFA enrolled if the project requires it (shared-project-scope S01, S02, S05).

## 4. What it touches

**Reads**
- Hop 1 (add): `projects`, `project_users`, `users` (`projects.ex:672-685`, `:635`)
- Hop 2 (job): `project_users` by id, then `users` and `projects` (`user_notifier.ex:34-37`); the recipient's current role (`user_notifier.ex:139`, `projects.ex:1568-1571`)
- Hop 3 (landing): as shared-project-scope and workflows-index

**Writes**
- Hop 1: `project_users` insert, `audit_events` `collaborator_added` (owned by project-settings-collaborators S02); `oban_jobs` insert, one per new member (`projects.ex:836-847`)
- Hop 2: none in the database beyond Oban's own job state
- Hop 3: `user_return_to` in the session when the recipient is signed out (`user_auth.ex:296-299`, `:490-491`)

**Immediate side effects** (in the add request)
- PubSub `ProjectUserAdded` on the project topic (`projects.ex:644`), consumed by shared-project-scope
- Oban job `UserNotifier` `%{type: "project_addition", project_user_id: id}` per new member, inserted after the membership transaction commits (`projects.ex:635-649`, `:842-846`)

**Deferred side effects** (in the Oban job)
- Email `email:project-addition` to the added user, addressed as "First Last <email>" (`user_notifier.ex:28-46`, `:138-151`, `mailer.ex:5-10`)
- Subject `You now have access to "<project name>"`; body names the role and project and links to `/projects/<project_id>/w` (`user_notifier.ex:141-150`)
- Mailer telemetry logs "Email sent" or "Failed to send email" (`mailer.ex:16-23`)

**External, non-transactional effects**
- The email itself. It is sent by the job after the membership has committed, so it is never sent for a membership that was rolled back.

**Depends on config**
- Sender name and address (`user_notifier.ex:26`, `:53`; `config.ex:578-584`)
- Link host comes from the endpoint URL config via `url/1` (`user_notifier.ex:147`)
- Delivery timing depends on the `background` queue (concurrency 1, `config/bootstrap.ex:339`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Access email for an existing user added to a project
  In order to know I can now work on a project, and get to it
  As a registered user an admin has just added
  I want an email that names the project and my role and links me to it

  @S01 @pending
  Scenario: An added user is told about their access and can open the project from the email
    # Value: a new collaborator learns they have access, and with what role, without the admin having to tell them separately.
    Given I am an admin on project "Malawi HIV"
    And "amara@example.org" is a registered user named "Amara" who is not on the project
    When I add "amara@example.org" as an editor on the collaboration tab
    Then eventually "amara@example.org" receives an email with subject "You now have access to \"Malawi HIV\""
    And the email says "You've been granted \"editor\" access to the \"Malawi HIV\" project on OpenFn."
    When Amara, logged in, opens the link in the email
    Then she is on the workflows page of project "Malawi HIV"
    # new_collaborator_component.ex:38-51, :134-151; projects.ex:827-847, :623-649
    # user_notifier.ex:28-46, :138-151; route_helpers.ex:7-11; router.ex:288, :301
    # user_notifier_test.exs:41-62 (subject, body, link equal to project_dashboard_url)

  @S02 @pending
  Scenario: A signed-out recipient is returned to the project after logging in
    # Value: the link still works from an inbox on a device where the person isn't logged in.
    Given "amara@example.org" has been added to project "Malawi HIV" and received the access email
    And she is not logged in
    When she opens the link in the email
    Then she is asked to log in
    When she logs in
    Then she is on the workflows page of project "Malawi HIV"
    # router.ex:189-190, :301; user_auth.ex:288-299, :490-491, :63-69

  @S03 @pending
  Scenario: Only the people just added are emailed
    # Value: existing members are not emailed every time someone else joins the project.
    Given I am an owner on project "Malawi HIV"
    And "bob@example.org" is already an editor on the project
    And "amara@example.org" and "chen@example.org" are registered users not on the project
    When I add "amara@example.org" and "chen@example.org" in one submission
    Then eventually each of them receives one "You now have access to \"Malawi HIV\"" email
    And "bob@example.org" receives no such email
    And I, the owner, receive no such email
    # projects.ex:672-685 (whole member list resubmitted), :836-847 (existing user ids rejected)
```

The landing step inherits shared-project-scope: a recipient without MFA on an MFA-required
project is sent to `/mfa_required` (shared-project-scope S05), and one removed before clicking is
told the project was not found (shared-project-scope S03). Neither is repeated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `perform/1` returns `:ok` whatever `deliver/3` returns, so a mailer failure is recorded as a completed job; with `max_attempts: 1` it would not be retried anyway | `user_notifier.ex:8-10`, `:39-44`, `:57-59` | the added user never gets the email; only a "Failed to send email" log line (`mailer.ex:16-17`) records it | decide |
| If the membership is removed before the job runs, `get_project_user!` raises `Ecto.NoResultsError` and the job errors and is discarded | `user_notifier.ex:34-37`, `projects.ex:452-455` | nothing (no email, which is the right outcome), but an Oban error is raised for a normal sequence | fix |
| The role in the email is read when the job runs, not when the person was added; a role change in between shows the new role | `user_notifier.ex:139`, `projects.ex:1568-1571` | an email that names a role other than the one the admin chose (if changed quickly) | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| In `update_project_with_users` the jobs are inserted after the transaction commits and the `Oban.insert_all` result is ignored; in `create_project` they are inserted inside the transaction | `projects.ex:635-649`, `:562-567`, `:836-847` | decide |
| The email is plain text only, no HTML part | `user_notifier.ex:49-55` | decide |
| The email does not go through the `MailRecipients.may_receive?` check used for project mail; it uses plain `deliver/3`, so it is sent even to a user who could not currently open the project (MFA not enrolled, login blocked) | `user_notifier.ex:62-85`, `:138-151`; `mail_recipients.ex:28-32` | decide |
| Sender is the instance admin address with the configured sender name | `user_notifier.ex:26`, `:53` | preserve |
| The test build sends the email inline during the add request, so LiveView tests assert it without draining a queue | `config/test.exs:155` | preserve |
| The email link is the project workflows index, not the collaboration tab or a welcome page | `user_notifier.ex:147` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Single attempt, on the shared `background` queue with concurrency 1 | `user_notifier.ex:8-10`, `config/bootstrap.ex:339` | yes, a transient mail failure means no email; a busy queue delays it | decide |
| One job per added user, inserted in one `Oban.insert_all` | `projects.ex:840-846` | no | preserve |

### 6.5 Things seen but not understood

- Other entries reach the same job: creating a project emails every initial member including the creator, unless `schedule_email?` is false (`projects.ex:562-567`; the dashboard modal passes false, `project_creation_modal.ex:55`; sandboxes pass it through, `projects.ex:2264`), and the superuser project edit form emails newly added members (`form_component.ex:166-170`; `project_live_test.exs:155-166`). These are outside this flow's scope; unclear whether they should be separate flows or extra entries here.
- `Projects.add_project_users/4` has a `notify_users` flag used `false` by kickstart (`kickstart.ex:623`); unclear whether any user-facing path relies on suppressing this email.
- No test asserts the job is enqueued from the collaboration tab, or that the email is sent from that path; the settings-tab tests check only the flash (`project_live_test.exs:4013-4064`). The email assertions are in the notifier unit test and the superuser create-project test.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a failed delivery be retried, and should the admin ever learn that the email didn't go out?
- Should this email go through the same `MailRecipients` check as other project mail, or is it account mail?
- Should the role in the email be the role granted at add time?

## Proposed flows

- none. Referenced: project-settings-collaborators S02 (entry handoff) and S10 (invite path sends no access email).

## Proposed shared

- none. Referenced: shared-project-scope (landing gate).
