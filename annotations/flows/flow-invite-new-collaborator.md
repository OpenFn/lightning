---
id: flow-invite-new-collaborator
type: flow
title: Invite someone without an account to a project
status: not-started
owner:

trigger:
  entry: project-settings-collaborators
  exit: workflows-index               # the reset itself lands on auth-login, then /projects (projects-dashboard); see 6.2
  surfaces:
    - project-settings-collaborators  # invite form submit (invite_collaborator_component.ex:45-75)
    - pubsub:project:<project_id>     # ProjectUserAdded (projects.ex:2020-2024, :757-762)
    - email:project-invitation        # "Join <project> on OpenFn as a collaborator" (user_notifier.ex:452-464)
    - auth-reset-password             # GET/PUT /users/reset_password/:token (router.ex:185-186)
    - email:password-reset            # recovery branch only, when the invitation link has lapsed (accounts.ex:1268-1282)
    - auth-login                     # where a successful reset lands (user_reset_password_controller.ex:38-41)
    - projects-dashboard              # /projects, the signed-in landing (user_auth.ex:514)
    - workflows-index                 # /projects/:id/w, reached from the dashboard row (dashboard_live/components.ex:114)

inherits:
  - shared-project-scope              # the invitee's entry into the project, incl. the MFA-required redirect (its S05)

url_params:
  - name: token (path segment of /users/reset_password/:token)
    set_by: email:project-invitation, email:password-reset
    effect: identifies the invitee; valid for one day and only while the user's email is unchanged (user_token.ex:31, :168-180)

config_variants:
  default: { require_email_verification: false, account_hook: Lightning.Extensions.AccountHook }   # bootstrap.ex:388-389, config/config.exs:45
  email-verification-required: { require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION
  # Read under default. The email-verification-required variant was read in code only (accounts.ex:1358-1368, layout_components.ex:259-275).

inventory:
  routes:
    - get /users/reset_password/:token  UserResetPasswordController :edit     # router.ex:185
    - put /users/reset_password/:token  UserResetPasswordController :update   # router.ex:186
  events:
    - ProjectLive.InviteCollaboratorComponent#add_collaborators   # the hop owned by project-settings-collaborators; listed for the handoff
  js_hooks: []
  policies:
    - Lightning.Policies.ProjectUsers (:add_project_user)          # invite_collaborator_component.ex:48-54
  workers: []
  api_endpoints: []
  emails:
    - email:project-invitation
    - email:password-reset            # recovery branch
  config:
    - :lightning, :require_email_verification
    - :lightning, Lightning.Extensions, :account_hook
  not_reachable_here: []

related:
  - lib/lightning/projects.ex                                    # invite_collaborators/3 and helpers, :2010-2125
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning_web/controllers/user_reset_password_controller.ex
  - lib/lightning/accounts.ex                                    # reset_user_password/2, get_user_by_reset_password_token/1
  - lib/lightning/accounts/user_token.ex
  - test/lightning/projects/membership_events_test.exs           # :314-353
  - test/lightning_web/live/project_live_test.exs                # :3811-3876
  - test/lightning_web/controllers/user_reset_password_controller_test.exs
flows: []
---

## 1. Purpose

Project admins use this to bring a colleague who has never used OpenFn straight into a project: one
form creates the account, grants the role and emails the person a link to choose their own password.
Without it, an admin would need a superuser to create the account first, or would have to set and
share a password themselves, and a new team member could not start work on the project's data.

## 2. What it does

1. A project admin or owner invites someone who has no OpenFn account, choosing a viewer, editor or admin role.
2. The account is created and added to the project straight away, and the person is emailed "Join <project> on OpenFn as a collaborator" with a link.
3. They open the link while signed out and choose their own password.
   - The password has to meet the usual rules, and the link stays usable until it works
   - The link works once and lapses after a day; after that they can use "Forgot your password?" instead
4. They log in, land on their projects list and open the project with the role they were given.

**Straightforwardness: 3 of 5.** One form does a lot at once, and the invitee's experience is borrowed from password reset, which shows in the wording and the gaps.

### Most surprising behaviours

- **(2)** When email confirmation is required, setting a password from the invite doesn't count as confirming the email, so the new person sees a warning banner and is locked out 48 hours after the invite. (6.1)
- **(3)** The link dies after one day and the email doesn't say so. There's no way for the admin to resend it; the invitee has to know to use "Forgot your password?". (S03, 6.1, 6.5)
- **(3)** The person is a full member from the moment the invite is sent, and the email tells them to ignore it if they didn't ask to join, which leaves that account and membership in place. (6.1, 6.2)
- **(3)** Someone who has never had a password is shown "Reset password" throughout. (6.1)
- **(3)** If the email fails to send the right way, the admin's page just reloads with no message and nothing is saved. (6.1)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:29-37` (add), `invite_collaborator_component.ex:48-54`
(re-checked at submit), `user_reset_password_controller.ex:6`, `:48-58` (token holder), `router.ex:174-186`
(signed-out only).

| Action                                   | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) | Holder of the link (signed out) |
|------------------------------------------|--------|--------|-------|-------|--------------------|------------------|---------------------------------|
| Send an invitation                       | no     | no     | yes   | yes   | no                 | no               | n/a                             |
| Open the set-password page from the link | n/a    | n/a    | n/a   | n/a   | n/a                | n/a              | yes, within one day             |
| Set the invitee's password               | n/a    | n/a    | n/a   | n/a   | n/a                | n/a              | yes, once                       |
| Enter the project afterwards             | invitee gets the role the admin chose: viewer, editor or admin (`invited_collaborators.ex:16`) | | | | | | |

**Preconditions beyond role**
- The invited email must not already belong to an account (view S11; `invited_collaborators.ex:38-81`).
- The link works only while signed out; a signed-in browser is redirected to `/projects` (`router.ex:174-176`, `user_auth.ex:271-279`).
- The link is valid for one day and only while the account's email equals the address it was sent to (`user_token.ex:31`, `:174-178`).
- Entering the project goes through shared-project-scope, so an MFA-required project sends the invitee to enrol first (shared-project-scope S05).
- Variant `email-verification-required`: the invitee is locked out 48 hours after the invite unless they confirm their email (`accounts.ex:1358-1368`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `users`, `user_tokens`

**Writes**
- Invite hop: `users` insert with a random 16-character password (`projects.ex:2048-2067`); `project_users` insert (`projects.ex:2034-2046`, `:686-694`); `user_tokens` insert, context `reset_password`, one per invitee (`projects.ex:2102-2119`); `audit_events` (below). All in one transaction (`projects.ex:2010-2025`).
- Reset hop: `users.hashed_password` update; every `user_tokens` row for the user deleted (`accounts.ex:1318-1334`).
- Log in hop: `user_tokens` insert, context `session` (`user_auth.ex:28-31`).

**Immediate side effects** (in the same request)
- Invite hop: audit `collaborator_added` on the project, actor the inviter (`projects.ex:693`; `membership_events_test.exs:315-332`).
- Invite hop: email `email:project-invitation` delivered synchronously, inside the transaction (`projects.ex:2014-2016`, `:2079-2099`).
- Invite hop: `ProjectUserAdded` broadcast on the project topic after commit (`projects.ex:2020-2024`, `:757-762`); consumed by shared-project-scope.
- Invite hop: flash "Invite sent successfully" ("Invites ..." for several) and navigation back to the collaboration tab (`invite_collaborator_component.ex:67-75`).
- Reset hop: the user's live sockets are disconnected (`accounts.ex:1328`); flash "Password reset successfully." and redirect to `/users/log_in` (`user_reset_password_controller.ex:38-41`).

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- The invitation email leaves through `Mailer.deliver` before the transaction commits (`projects.ex:2014-2016`, `user_notifier.ex:49-60`); a later rollback cannot recall it.

**Depends on config**
- `:account_hook` adapter performs the user registration (`projects.ex:2059-2063`, `services/account_hook.ex:13-15`, `config/config.exs:45`).
- `:require_email_verification` (variant `email-verification-required`).
- The link's host comes from the endpoint URL config (`user_notifier.ex:458`).

**Product limits**
- The invitation link expires after one day (`user_token.ex:31`).

## 5. Scenarios

```gherkin
Feature: Invite someone without an account to a project
  In order to bring a new colleague into a project without a superuser
  As a project admin, and as the person invited
  I want one invitation to create the account and let them choose their own password

  @S01 @pending
  Scenario: An invitee sets a password from the email and opens the project
    # Value: someone new to OpenFn can start work on the project from a single email, without anyone else knowing their password.
    Given I am an admin on project "Malawi HIV" with first name "Ama"
    And "new.person@example.org" has no OpenFn account
    When I invite "new.person@example.org" as "Non Exists" with role "Editor"
    Then "new.person@example.org" receives an email "Join Malawi HIV on OpenFn as a collaborator"
    And it says "Ama has invited you to join project \"Malawi HIV\" and granted you \"editor\" access"
    And it contains no password
    When the invitee opens the link in that email in a signed-out browser
    Then they see "Reset password" with fields "New password" and "Confirm new password"
    When they enter "a long new password" in both and click "Reset password"
    Then they are on "/users/log_in" and see "Password reset successfully."
    When they log in with "new.person@example.org" and "a long new password"
    Then they are on "/projects" and see "Malawi HIV"
    When they open "Malawi HIV"
    Then they see the project's workflows page with editor permissions
    # projects.ex:2010-2025, :2048-2067, :2079-2119; user_notifier.ex:452-464
    # user_reset_password_controller.ex:28-46; edit.html.heex:29-52; accounts.ex:1318-1334
    # user_session_controller.ex:15-53; user_auth.ex:61-70, :514; dashboard_live/index.ex:44-48; dashboard_live/components.ex:114
    # project_live_test.exs:3811-3876 (invite and email only); user_reset_password_controller_test.exs:86-105 (reset only)

  @S02 @pending
  Scenario: The invitation link works only once
    # Value: a forwarded or leaked invitation can't be used to take over the account after the invitee has set it up.
    Given an invitee has set their password from the invitation link
    When anyone opens the same link
    Then they are sent away with "Reset password link is invalid or it has expired."
    # accounts.ex:1321-1324; user_reset_password_controller.ex:48-58; user_reset_password_controller_test.exs:67-74

  @S03 @pending
  Scenario: A lapsed invitation can be recovered with "Forgot your password?"
    # Value: an unused invitation stops being a way into the account after a day, yet the invitee can still get in without asking the admin.
    Given "new.person@example.org" was invited more than one day ago and never used the link
    When they open the link in the invitation email
    Then they see "Reset password link is invalid or it has expired."
    When they click "Forgot your password?" on the log in page and submit "new.person@example.org"
    Then they see "If your email is in our system, you will receive instructions to reset your password shortly."
    And they receive an email "Finish resetting your password"
    And its link lets them set a password and log in as in S01
    # user_token.ex:31, :168-180; user_reset_password_controller.ex:12-26, :48-58
    # user_session_html/new.html.heex:93-95; accounts.ex:1268-1282; user_notifier.ex:251-252
    # user_reset_password_controller_test.exs:20-35

  @S04 @pending
  Scenario: The invitee's password must meet the account rules
    # Value: an account created on someone's behalf still ends up with a password the instance accepts for everyone else.
    Given the invitee has opened a valid invitation link
    When they enter "too short" and "does not match" and click "Reset password"
    Then they stay on "Reset password" and see "Your passwords do not match."
    And the link still works
    # user.ex:258-261, :357-361; priv/gettext/en/LC_MESSAGES/errors.po:43-44
    # user_reset_password_controller.ex:43-44; user_reset_password_controller_test.exs:107-120
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Invited users are created unconfirmed and setting a password does not confirm them, though following the emailed link proves they own the address. No confirmation email is sent at invite time | `projects.ex:2048-2067`; `user.ex:357-361`; `accounts.ex:1358-1368`; `layout_components.ex:259-275` | variant `email-verification-required`: a red "Please confirm your account before ..." banner on first login, and a lockout 48 hours after the invite | decide |
| The invitation email doesn't say the link expires, and it expires after one day | `user_notifier.ex:452-464`; `user_token.ex:31` | an invitee who opens it the next day gets "Reset password link is invalid or it has expired." with no idea why | fix |
| The invitee's set-password page, button and confirmation flash all say "Reset password" | `edit.html.heex:5`, `:51`; `user_reset_password_controller.ex:40` | someone who has never had a password is told they are resetting one | fix |
| The email says "If you did not request to join this project, please ignore this email", but the invitee never requested anything; ignoring it leaves an account and membership in place | `user_notifier.ex:460` | misleading advice | decide |
| The invitation is delivered inside the transaction and a raise from the mailer path rolls everything back but crashes the inviter's LiveView (the test raises from `email_sender_name`); a returned mailer error is ignored and reports success (the view's 6.1 row owns that half) | `projects.ex:2014-2016`, `:2081-2096`; `user_notifier.ex:49-60`; `membership_events_test.exs:334-353` | inviter sees the page reload with no message | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The journey does not land in the project: a successful reset goes to log in, then `/projects`, and the invitee must pick the project | `user_reset_password_controller.ex:41`; `user_auth.ex:514` | decide |
| Setting the password deliberately does not sign the invitee in ("to avoid a leaked token giving the user access") | `user_reset_password_controller.ex:34-35`; `user_reset_password_controller_test.exs:96` | preserve |
| Opening the link in a browser where someone else is signed in redirects to that person's `/projects`, with no hint the link was for someone else | `router.ex:174-176`; `user_auth.ex:271-279` | decide |
| The invitation reuses the password-reset token context and route rather than an invitation of its own | `projects.ex:2106`; `user_notifier.ex:458` | preserve |
| The email shows the role as its raw lowercase value ("editor") | `user_notifier.ex:456`; `invited_collaborators.ex:16` | decide |
| The invitation mail goes through `deliver/3`, not the project-mail recipient check, though it names the project; the invitee is a member by then | `user_notifier.ex:62-71`, `:453` | preserve |
| The invitee is a full member from the moment the invite commits; there is no pending state before they set a password | `projects.ex:2014-2016` | decide |
| The reset page shows a "Register" link when signup is allowed | `edit.html.heex:65-70` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, reason}` from `generate_user_tokens` | `projects.ex:2097-2098`, `:2108-2114` | token insert only fails on a database error |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Invitation link valid for one day | `user_token.ex:31` | yes | preserve (S03) |
| Invitation emails are sent one by one, synchronously, while the transaction holds its locks | `projects.ex:2081-2096` | inviter waits longer for large invite lists | decide |

### 6.5 Things seen but not understood

- There is no way for an admin to resend an invitation: the invite form refuses an email that already has an account (view S11), and adding the person through the add form sends "You now have access to" instead (view S02). The only recovery is the invitee's own "Forgot your password?" (S03). Unclear whether that is intended.
- The random password is 16 characters of URL-unsafe base64 and is never shown or stored anywhere but hashed (`projects.ex:2065-2068`); it exists only to satisfy `validate_password`. Unclear whether the rebuild should create invitees with no password at all.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should following the invitation link confirm the account (see 6.1, variant `email-verification-required`)?
- Should the journey end in the project rather than on log in and `/projects`?
- Should admins be able to resend or revoke a pending invitation, which implies a pending state the old app does not have?
- Should the invitation email be sent after commit, and should a delivery failure be reported to the inviter?

## Proposed flows

none

## Proposed shared

none

Views this flow passes through that have no annotation yet: `auth-reset-password`, `auth-login`,
`projects-dashboard`, and capability `email:password-reset`; `email:project-invitation` is owned by this flow.
