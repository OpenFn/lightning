---
id: flow-change-email-confirm
type: flow
title: Change account email with confirmation
status: not-started
owner:

trigger:
  entry: profile-account              # or auth-confirmation-required (the locked-out page's "Change email address" form); both call request_email_update/2
  exit: profile-account               # where the new address is shown; the controller itself redirects to /projects (user_confirmation_controller.ex:36-39), see 6.2
  surfaces:
    - profile-account                       # "Change email" card, FormComponent#change_email (form_component.ex:25-54)
    - auth-confirmation-required            # correction form, UserConfirmationRequiredLive#change_email (user_confirmation_required_live.ex:79-116)
    - email:update-email-warning            # "Your OpenFn email was changed", to the current address (user_notifier.ex:289-301)
    - email:update-email-instructions       # "Please confirm your new email", to the new address (user_notifier.ex:270-284)
    - controller:confirm-email              # GET /profile/confirm_email/:token (router.ex:232-234; user_confirmation_controller.ex:34-49)
    - projects-dashboard                    # where the controller lands, with the flash
    - admin-users   # added by lead: cross-reference, admins change email without confirmation
    - admin-user-edit   # added by lead: cross-reference, admins change email without confirmation
    - auth-confirm-account   # added by lead (link lint)
  reachable_when:
    - the user is signed in; the confirm link sits behind :require_authenticated_user (router.ex:189-190, :232-234; user_auth.ex:288-299)
    - the link is opened within 7 days of the request (user_token.ex:33, :207-217)
    - the signed-in account's current email is still the one the request was made from, because the token context is `change:<that email>` (accounts.ex:702-708, :740-742)

inherits:
  - shared-authenticated-session      # login redirect for a signed-out click, and the lockout whose allow-list lets the link through (confirmation_lockout.ex:18-23)
  - shared-project-header             # the account confirmation banner on projects-dashboard, which a confirmed change removes (its S13)

url_params: []                        # the token is a path segment, /profile/confirm_email/:token (user_notifier.ex:277)

config_variants:
  default: {}                                                                  # entry from profile-account only; S01, S03 to S07, S10 read under this one
  require-email-verification: { lightning.require_email_verification: true }   # auth-confirmation-required exists only for unconfirmed accounts past 48 hours (accounts.ex:1360-1368); S02, S08, S09

inventory:
  routes:
    - get /profile/confirm_email/:token  UserConfirmationController :confirm_email   # router.ex:232-234
  events:
    - UserConfirmationRequiredLive#change_email      # user_confirmation_required_live.ex:79-116; entry hop; the view annotation auth-confirmation-required should also claim it
    - UserConfirmationRequiredLive#validate_email    # user_confirmation_required_live.ex:70-77; same
    # ProfileLive.FormComponent#change_email and #validate_email are inventoried by profile-account
  js_hooks: []
  policies: []                        # no policy module; the token context binds the link to the requesting account (accounts.ex:702-708)
  workers: []                         # both emails go out inline through Mailer.deliver, not Oban (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:update-email-warning      # UserNotifier.deliver_update_email_warning/2
    - email:update-email-instructions # UserNotifier.deliver_update_email_instructions/2
  config:
    - :lightning, :require_email_verification     # gates the auth-confirmation-required entry (accounts.ex:1366)
    - :hammer backend, bucket `email_change`      # correction throttle (accounts.ex:758-781, :795-801)
    - Lightning.Config.instance_admin_email, email_sender_name   # sender and the "contact" address in the warning (user_notifier.ex:26, :53, :296)
  not_reachable_here:
    - Accounts.apply_user_email/3 (accounts.ex:689-694) and Accounts.change_user_email/2 (accounts.ex:650-652); no callers (6.3)
    - Accounts.update_user/3 email change from the admin form (accounts.ex:177-221); a direct change with no confirmation, owned by flow-account-revocation-teardown and admin-users
    - UserConfirmationController :edit / :update (/users/confirm/:token) belong to flow-resend-account-confirmation

related:
  - lib/lightning_web/live/profile_live/form_component.ex
  - lib/lightning_web/live/user_confirmation_required_live.ex
  - lib/lightning_web/live/user_confirmation_required_live.html.heex
  - lib/lightning/accounts.ex
  - lib/lightning/accounts/user_token.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/accounts/user.ex
  - lib/lightning_web/controllers/user_confirmation_controller.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/confirmation_lockout.ex
  - admin-users                       # changes a user's email directly, without this flow (accounts.ex:177-221)
flows:
  - flow-login-return-to              # S04 hands off to it when the link is opened signed out
  - flow-resend-account-confirmation  # the other way out of auth-confirmation-required; a confirmed change voids its outstanding links (user_token.ex:179)
---

## 1. Purpose

A user's email address is where password resets, failure alerts and project invitations arrive, so
it has to be changed by the user and only to an inbox they can prove they read. This flow lets any
signed-in user move their account to a new address, warns the old inbox in case the request is not
theirs, and gives a locked-out user who mistyped their address at sign-up a way back in. Without it,
an address change would need an administrator, or anyone with a borrowed session could silently
point the account at an inbox they control.

## 2. What it does

1. A signed-in user asks for a new address on their profile, entering their current password.
   - A user locked out for not confirming their account can do the same from the blocked page to fix a mistyped address, at most 3 times in 15 minutes
   - The new address must be valid, different from the current one and not used by another account
2. Two emails go out: a warning to the current address, and a confirmation link to the new one. Nothing changes yet.
3. The user opens the link while signed in as that account, within 7 days.
   - If they're signed out they're asked to log in first, then sent on to the link
   - A link opened in someone else's session, expired, or already used is refused
4. The email changes, the account counts as confirmed, any other pending change links stop working, and the user lands on the projects list with "Email changed successfully."

**Straightforwardness: 3 of 5.** The two-email shape is familiar, but the warning email jumps the gun, failures all look like an expired link, and a self-service change is treated much more lightly than an admin one.

### Most surprising behaviours

- **(2)** The old inbox is told "Your OpenFn email was changed" the moment the change is requested, even though nothing has changed and may never, and it hears nothing when the change actually goes through. (S10, 6.1, 6.2)
- **(3)** If someone else takes the new address before the link is opened, the user just sees "Email change link is invalid or it has expired", with no hint that the address is the problem. (S07, 6.1)
- **(3)** A completed change keeps every session and API token and leaves no audit record, while a superuser changing the same email signs the user out everywhere and is audited. (6.2)
- **(3)** Tabs already open keep showing the old address, and other tabs of a recently registered user keep the "please confirm" banner, until they're reloaded. (6.1)
- **(3)** In a rare case a leftover change link opened in a different account's session may change that other account's email; nothing checks which account the link was made for. (6.1)

## 3. Who can do what

No policy module. The request hop checks the current password (`accounts.ex:827-858`); the confirm hop sits behind `:require_authenticated_user` (`router.ex:189-190`, `:232-234`) and only finds a token whose context is `change:<signed-in user's email>` (`accounts.ex:702-708`; `user_token.ex:207-217`).

| Action | Signed out | Requesting account, confirmed or in grace period | Requesting account, locked out | Signed in as another account |
|--------|------------|--------------------------------------------------|--------------------------------|------------------------------|
| Request a change from profile-account | no (login) | yes | no (redirected to /users/confirm-required) | n/a |
| Request a change from auth-confirmation-required | no | no (redirected to /projects, `user_confirmation_required_live.ex:24-39`) | yes | n/a |
| Open the link and complete the change | no (login first) | yes | yes (`confirmation_lockout.ex:18-23`) | refused |

**Preconditions beyond role**
- The current password must be entered and match (`accounts.ex:849-858`); an account with no password hash can never request a change (`user.ex:394-405`).
- The new address must be well-formed, different from the current one and not used by another account, at request time and again at confirm time (`accounts.ex:827-847`; `user.ex:241-256`, `:325-333`, `:115`).
- From auth-confirmation-required, at most 3 requests per account per 15 minutes, bucket `email_change`, separate from the resend bucket (`accounts.ex:758-781`, `:795-801`). From profile-account, unmetered (`accounts.ex:788-791`).
- The link is valid for 7 days (`user_token.ex:33`, `:216`).

## 4. What it touches

**Reads**
- Hop 1 (request): `users` for the password hash and the address uniqueness check (`accounts.ex:849-858`; `user.ex:241-250`); Hammer bucket `email_change::<user_id>` on the correction entry only (`accounts.ex:762-767`)
- Hop 3 (confirm): `user_tokens` by hashed token, context `change:<current email>`, age (`user_token.ex:207-217`); `users` uniqueness check on the new address (`user.ex:241-250`)

**Writes**
- Hop 1: `user_tokens` insert, context `change:<current email>`, `sent_to` the new address (`accounts.ex:740-744`; `user_token.ex:142-154`)
- Hop 3: `users.email` set to `sent_to` and `users.confirmed_at` set to now, then every `change:<old email>` token for the user deleted, in one transaction (`accounts.ex:707-728`; `user.ex:325-333`, `:367-370`)

**Immediate side effects**
- Hop 1: email `email:update-email-warning` to the current address, then `email:update-email-instructions` to the new address, both sent inline in the request; the second is skipped if the first fails (`accounts.ex:745-751`; `user_notifier.ex:49-60`)
- Hop 1: on profile-account the flash "You will receive an email with instructions shortly." (`form_component.ex:34-39`); on auth-confirmation-required the alert "We have sent confirmation instructions to <new address>." (`user_confirmation_required_live.ex:86-90`; `user_confirmation_required_live.html.heex:44-52`)
- Hop 3: flash "Email changed successfully." or "Email change link is invalid or it has expired.", redirect to `/projects` (`user_confirmation_controller.ex:34-49`)
- No audit event and no PubSub broadcast at either hop (`accounts.ex:702-756`)

**Deferred side effects**
- Outstanding account-confirmation and password-reset links sent to the old address stop working once the email changes, because those lookups require `sent_to == user.email` (`user_token.ex:179`)

**External, non-transactional effects**
- Both emails. The token is inserted before either is sent and is not removed if a send fails (`accounts.ex:743-755`). On the correction entry the rate allowance is spent before any of this (`accounts.ex:795-800`).

**Depends on config**
- `require_email_verification` for the auth-confirmation-required entry (`accounts.ex:1362-1368`)
- Link host from the endpoint URL config (`user_notifier.ex:277`); sender name and admin address (`user_notifier.ex:26`, `:53`, `:296`)

**Product limits**
- Link valid 7 days (`user_token.ex:33`)
- 3 corrections per 15 minutes from auth-confirmation-required (`accounts.ex:758-759`)

## 5. Scenarios

```gherkin
Feature: Change account email with confirmation
  In order to keep receiving resets and alerts after my address changes
  As any signed-in user
  I want to move my account to a new email address that I prove I own

  @S01 @pending
  Scenario: A user changes their email from the profile and confirms it from the new inbox
    # Value: the account only moves to an inbox its owner can read, and they can do it without an administrator.
    Given I am signed in as "amara@example.org"
    And I have asked to change my email to "amara@new.example.org" on "/profile" (profile-account S04)
    Then "amara@example.org" receives an email with subject "Your OpenFn email was changed"
    And "amara@new.example.org" receives an email with subject "Please confirm your new email"
    And my email is still "amara@example.org"
    When I open the link in the "Please confirm your new email" email
    Then I am on "/projects"
    And I see "Email changed successfully."
    When I open "/profile"
    Then I see "Email: amara@new.example.org"
    # form_component.ex:25-39; accounts.ex:740-756, :702-728; user_notifier.ex:270-301
    # router.ex:232-234; user_confirmation_controller.ex:34-39; components.ex:20
    # accounts_test.exs:1243-1279, :1291-1310; user_confirmation_controller_test.exs:324-353

  @S02 @pending @variant:require-email-verification
  Scenario: A locked-out user corrects a mistyped address and the link lets them back in
    # Value: someone who mistyped their address at sign-up is not locked out for good once the confirmation deadline passes.
    Given my account was created 50 hours ago with the unconfirmed email "amara@exmaple.org"
    And I am signed in and held on "/users/confirm-required"
    When I set "New email address" to "amara@example.org"
    And I set "Enter password to confirm" to my password and click "Update email"
    Then I see "We have sent confirmation instructions to amara@example.org."
    And "amara@example.org" receives an email with subject "Please confirm your new email"
    When I open the link in that email
    Then I am on "/projects"
    And my email is "amara@example.org" and my account is confirmed
    And I am no longer redirected to "/users/confirm-required"
    # user_confirmation_required_live.ex:79-90; .html.heex:44-52, :75-123; accounts.ex:795-801
    # confirmation_lockout.ex:18-23; user_auth.ex:305-306, :327-330; user.ex:367-370
    # user_confirmation_required_live_test.exs:160-185, :187-216

  @S03 @pending
  Scenario: A link for another account does not change the signed-in account
    # Value: an email change link only ever moves the account that asked for it, even if it is opened in someone else's session.
    Given "amara@example.org" has asked to change her email to "amara@new.example.org"
    And I am signed in as "ben@example.org"
    When I open Amara's "Please confirm your new email" link
    Then I am on "/projects"
    And I see "Email change link is invalid or it has expired."
    And my email is still "ben@example.org"
    And Amara's email is still "amara@example.org"
    # accounts.ex:702-708 (context built from the signed-in user's email); user_token.ex:207-217
    # user_confirmation_controller.ex:41-48; no test covers a second account

  @S04 @pending
  Scenario: Opening the link while signed out asks me to log in first
    # Value: the link can't change an account for whoever happens to open the email; the account owner has to sign in.
    Given I have asked to change my email to "amara@new.example.org"
    And I am not logged in
    When I open the link in the "Please confirm your new email" email
    Then I am asked to log in
    And my email is still "amara@example.org"
    And the flow "flow-login-return-to" has started for "/profile/confirm_email/<token>"
    # router.ex:189-190; user_auth.ex:288-299, :490-492
    # user_confirmation_controller_test.exs:373-380 (asserts only the redirect to login)

  @S05 @pending
  Scenario: An expired link is refused
    # Value: a change link left in an inbox can't be used to take the account weeks later.
    Given I asked to change my email to "amara@new.example.org" 8 days ago
    When I open the link in that email
    Then I see "Email change link is invalid or it has expired."
    And my email is still "amara@example.org"
    # user_token.ex:33, :216; accounts.ex:704-714; user_confirmation_controller.ex:41-48
    # accounts_test.exs:1319-1326

  @S06 @pending
  Scenario: A link works once, and confirming retires every other pending change
    # Value: an old or duplicate link can't later move the account to an address the user has since abandoned.
    Given I asked to change my email to "amara@new.example.org"
    And I then asked to change it to "amara@other.example.org"
    When I open the link sent to "amara@new.example.org"
    Then my email is "amara@new.example.org"
    When I open the same link again
    Then I see "Email change link is invalid or it has expired."
    When I open the link sent to "amara@other.example.org"
    Then I see "Email change link is invalid or it has expired."
    And my email is still "amara@new.example.org"
    # accounts.ex:740-742 (no earlier change tokens removed), :717-728 (all change:<old> tokens deleted)
    # accounts_test.exs:1308-1312; user_confirmation_controller_test.exs:347-353 (reuse only)

  @S07 @pending
  Scenario: An address taken by someone else before confirming is not applied
    # Value: two accounts never share an address, so resets and alerts for one can't reach the other.
    Given I asked to change my email to "shared@example.org"
    And another user has since registered "shared@example.org"
    When I open the link in my "Please confirm your new email" email
    Then my email is still "amara@example.org"
    And the other user's email is still "shared@example.org"
    # user.ex:241-256, :325-333, :115; accounts.ex:707-714; the flash copy is in 6.1

  @S08 @pending @variant:require-email-verification
  Scenario: A locked-out account can send at most three corrections in 15 minutes
    # Value: a blocked account can't be used to send mail to arbitrary addresses at volume.
    Given my account is locked out pending email confirmation
    And I have submitted 3 address corrections in the last 15 minutes
    When I submit a fourth correction to "amara4@example.org"
    Then I see "You've asked us to change this address a few times recently."
    And "amara4@example.org" is still in "New email address"
    And no "Please confirm your new email" email is sent
    # accounts.ex:758-781, :795-801; user_confirmation_required_live.ex:100-105; .html.heex:88-98
    # user_confirmation_required_live_test.exs:218-249; accounts_test.exs:103-157

  @S09 @pending @variant:require-email-verification
  Scenario: A locked-out user opening an expired link is told why on the page they land on
    # Value: a locked-out user knows the link failed and that they need a new one, instead of seeing only the generic block message.
    Given my account is locked out pending email confirmation
    When I open an expired "Please confirm your new email" link
    Then I am on "/users/confirm-required"
    And I see "Email change link is invalid or it has expired."
    # user_confirmation_controller.ex:41-48; user_auth.ex:305-306, :345-351
    # user_auth_test.exs:692-723

  @S10 @pending
  Scenario: The old address is warned and told what to do
    # Value: if someone else used the account to request the change, the owner hears about it at the inbox they still control.
    Given I am signed in as "amara@example.org"
    When I ask to change my email to "attacker@example.org"
    Then "amara@example.org" receives an email with subject "Your OpenFn email was changed"
    And it names "amara@example.org" and "attacker@example.org"
    And it says to contact the instance administrator if I did not request it
    # accounts.ex:745-746; user_notifier.ex:289-301; accounts_test.exs:1264-1267
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The warning to the old address is titled "Your OpenFn email was changed" while the change is only requested and may never be confirmed (carried over from profile-account 6.1) | `user_notifier.ex:289-301` | told their email was changed when it wasn't | fix |
| Any failure in the update transaction, including the new address being taken since the request (S07), collapses to `:error` and shows the expired-link copy | `accounts.ex:707-714`; `user_confirmation_controller.ex:41-48` | "Email change link is invalid or it has expired." for a fresh link, with no hint that the address is in use | fix |
| The change-token lookup matches on hash and `change:<email>` context only, not `user_id`. An admin email change revokes only `session` tokens, so `change:<old email>` tokens survive it; if another account later takes that old address, a leftover link opened in that account's session moves its email to the original requester's target | `user_token.ex:207-217`; `accounts.ex:204-221`, `:702-708` | the wrong account's email changed; needs the leftover link, so unlikely, but no check prevents it | fix |
| Nothing is broadcast when the change completes; open tabs keep the old state until they remount | `accounts.ex:702-728`; `components.ex:20`; `layout_components.ex:263-265` | the profile tab still says "Email: <old address>", and a grace-period user's other tabs keep the confirmation banner | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The confirm step is a GET that writes; there is no confirm button, unlike `/users/confirm/:token` | `router.ex:232-234`; `user_confirmation_controller.ex:34-49` | decide |
| A completed self-service change keeps every session and API token; an admin email change revokes sessions and disconnects sockets | `accounts.ex:717-728` vs `:181-221` | decide |
| No audit event for a self-service email change; an admin change through `update_user/3` with an actor is audited | `accounts.ex:702-728` vs `:186`, `:222-228` | decide |
| The old address is warned at request time but gets no notice when the change completes | `accounts.ex:740-756`, `:702-728` | decide |
| The controller lands on `/projects`, not back on the profile where the change started | `user_confirmation_controller.ex:36-39` | decide |
| Completing the change sets `confirmed_at`, so an unconfirmed account is confirmed by it; this is what makes S02 work | `accounts.ex:717-721`; `user.ex:367-370`; `user_confirmation_required_live.ex:4-7` | preserve |
| Several pending requests are all valid until one is used; using one deletes the rest | `accounts.ex:740-742`, `:722-727` | preserve |
| Changing the email voids outstanding confirmation and reset links sent to the old address | `user_token.ex:179` | preserve |
| A send failure after the token insert leaves a token and possibly a sent warning with no instructions; on the correction entry it also spends one of the 3 allowed requests | `accounts.ex:743-755`, `:795-800`; `user_confirmation_required_live.ex:107-115` | decide |
| A send failure shows "Failed to request email update" as a flash on the profile but "could not be updated, please try again" under the field on the locked-out page | `form_component.ex:44-52`; `user_confirmation_required_live.ex:107-115` | decide |
| The link lookup is keyed on the account's current email, so the link stops working if the address changes by another route (admin form) before it is opened | `accounts.ex:703`; `accounts.ex:177-221` | preserve |
| The warning email's sign-off tells the user to contact `instance_admin_email`, which is also the sender address | `user_notifier.ex:26`, `:53`, `:296` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `Accounts.apply_user_email/3` | `accounts.ex:689-694` | no callers in `lib/` or `test/` |
| `Accounts.change_user_email/2` | `accounts.ex:650-652` | no callers in `lib/` or `test/` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Change link valid 7 days | `user_token.ex:33`, `:216` | yes, S05 | preserve |
| 3 corrections per 15 minutes per account from the locked-out page, bucket `email_change` | `accounts.ex:758-781`, `:795-801` | yes, S08 | preserve |
| Requests from `/profile` are unmetered; each sends two emails (also listed in profile-account 6.4) | `accounts.ex:788-791` | yes, inbox | decide |
| Rate limiter fails open with a warning log if Hammer errors | `accounts.ex:774-780` | no | preserve |
| Both emails are sent synchronously in the LiveView event, so a slow mailer holds the "Sending confirmation email..." button | `user_notifier.ex:49-60`; `user_confirmation_required_live.html.heex:119` | yes | preserve |

### 6.5 Things seen but not understood

- `annotations/INVENTORY.md:123` lists auth-confirm-account against this flow. The only link between them is the shared controller module; auth-confirm-account's routes (`/users/confirm/:token`) are not part of this journey. Disposition: decide whether that row should be removed.
- The `user_tokens` row for a change keeps the old address only inside its `context` string (`accounts.ex:742`); whether anything reports on these contexts was not found. Disposition: preserve.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a completed email change revoke other sessions, record an audit event and notify the old address, as an admin change does for the first two? (6.2)
- Should the confirm step land on `/profile` and update open tabs? (6.1, 6.2)
- Should the change-token lookup be scoped to the user id, and should an admin email change delete pending change tokens? (6.1)
- Should `/profile` requests be metered like the correction path? (6.4)

## Proposed flows

none

## Proposed shared

none
