---
id: auth-confirmation-required
type: view
title: Confirm your email (lockout page)
status: not-started
owner:

trigger:
  old_route: /users/confirm-required
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the request passes `[:browser, :require_authenticated_user]` (router.ex:189-190), where the path is on the lockout allow-list (confirmation_lockout.ex:25-27, :35-39; user_auth.ex:305-306, :327-330)
    - the session token resolves to an account that is not disabled or scheduled for deletion (accounts.ex:994-1006; user_confirmation_required_live.ex:18-22)
    - the account is locked out, that is `require_email_verification` is on, `confirmed_at` is nil and the account is at least 48 hours old (accounts.ex:1360-1368; user_confirmation_required_live.ex:24); every other account is redirected to /projects (:37-39)
    - in practice, users arrive here by redirect from any other signed-in page (shared-authenticated-session S04)

inherits:
  - shared-authenticated-session      # HTTP plug parts only: S01 (signed out), S02 (disabled), S03 (TOTP pending), S04 and S05 (lockout redirect and allow-list), S11 (first setup, :browser pipeline). Not S06 to S10: the :confirmation_required live_session has no on_mount, so InitAssigns, its chrome and its banners never run here (router.ex:246-250)
  - shared-flash-messages

url_params: []

config_variants:
  default: {}                                                                  # verification off; nobody is ever locked out, so every visitor is redirected to /projects (S13)
  require-email-verification: { lightning.require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389; S01 to S12 and S14 are read under this one, as are all tests in user_confirmation_required_live_test.exs:13-20

inventory:
  routes:
    - live /users/confirm-required  UserConfirmationRequiredLive :show   # router.ex:248-250
  events:
    - UserConfirmationRequiredLive#resend-confirmation-email   # user_confirmation_required_live.ex:42-68
    - UserConfirmationRequiredLive#validate_email              # user_confirmation_required_live.ex:70-77; also listed by flow-change-email-confirm
    - UserConfirmationRequiredLive#change_email                # user_confirmation_required_live.ex:79-121; also listed by flow-change-email-confirm
  js_hooks:
    - Flash                           # on Common.flash (common.ex:517-536); assets/js/hooks/index.ts:532-549; see Proposed shared
  policies: []                        # no policy module; the gate is the plug plus the mount's locked_out? check
  workers: []                         # all mail is sent inline in the LiveView event (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:confirmation              # reminder variant, Accounts.remind_account_confirmation/1 (accounts.ex:1197-1206; user_notifier.ex:121-133); owned by flow-resend-account-confirmation
    - email:update-email-warning      # via request_email_correction/2 (accounts.ex:795-801, :745-746); owned by flow-change-email-confirm
    - email:update-email-instructions # same (accounts.ex:747-751)
  config:
    - :lightning, :require_email_verification     # accounts.ex:1366
    - :hammer backend, buckets `confirmation_resend` and `email_change` (accounts.ex:758-782)
  not_reachable_here:
    - InitAssigns on_mount and its toggle_sidebar hook, book-a-demo and GDPR banners (shared-authenticated-session S06 to S10); no on_mount in this live_session (router.ex:246-250)
    - the user socket: no `user_token` is assigned for a locked-out account, so `window.userToken` is empty (user_auth.ex:378-392; layouts/root.html.heex:20)
    - Common.flash's dynamic_component branch (common.ex:541-543); nothing here puts a component flash

related:
  - lib/lightning_web/live/user_confirmation_required_live.ex
  - lib/lightning_web/live/user_confirmation_required_live.html.heex
  - lib/lightning_web/confirmation_lockout.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning/accounts.ex
  - lib/lightning/accounts/user.ex
  - lib/lightning/utils/validators.ex
  - lib/lightning_web/components/layouts/app.html.heex
  - test/lightning_web/live/user_confirmation_required_live_test.exs
  - test/lightning_web/live/confirmation_lockout_live_test.exs
  - test/lightning_web/confirmation_lockout_recovery_test.exs
  - test/lightning_web/confirmation_lockout_test.exs
  - profile-account                   # the same email-change request, unmetered, for accounts that are not locked out
flows:
  - flow-change-email-confirm         # starts here: the "Change email address" form (its S02, S08, S09)
  - flow-resend-account-confirmation  # the resend button feeds its confirm step (its S08); shares its `confirmation_resend` allowance (its S03)
  - flow-login-return-to              # a signed-out visit is sent to log in first (shared-authenticated-session S01)
  - flow-log-out
  - flow-admin-created-account-confirm
---

## 1. Purpose

On instances that require verified email addresses, an account that has not confirmed within 48
hours is confined to this one page. It is for that user: it tells them why everything else is
closed, and gives them the only ways out that do not need an administrator: ask for a fresh
confirmation link, or correct an address they mistyped at sign-up. Without it a locked-out user
would hit a redirect loop or a dead end, and a typo in their address would lock them out for good.

## 2. What it does

- **Explain the block** (locked-out users)
  - Locked-out users see why they are blocked and the address the link went to
  - Locked-out users see no project data, app chrome or live connection to the app
- **Ways out** (locked-out users)
  - Ask for a new confirmation link, up to three times in 15 minutes, and are told when one could not be sent
  - Correct their email address, with their password, up to three times in 15 minutes
  - Log out
- Anyone who is not locked out is sent to their projects

**Straightforwardness: 3 of 5.** Two buttons and a form, but the messages they leave behind and the address they act on don't always match what the user just did.

### Most surprising behaviours

- **(2)** After asking to correct a mistyped address, the page still shows the old one, and "Resend confirmation email" keeps sending to the wrong address until the new link is opened. (6.2)
- **(2)** The page tells everyone a link was sent "when you signed up". The first administrator, and anyone an administrator created, never got one, so they're sent looking for an email that doesn't exist. (6.1)
- **(3)** Once the resend limit is hit, "We have sent a new confirmation link" stays on screen beside "You've asked for this a few times recently", though nothing was sent. (6.1)
- **(3)** The password is checked every time you leave the email field, with no limit, so someone at an unattended blocked session can guess the password and check which addresses have accounts. (6.1)
- **(3)** A wrong password shows "Your passwords do not match", though the user typed only one password. (6.1)

## 3. Who can do what

No policy module. The HTTP request goes through `require_authenticated_user` (`router.ex:189-190`; `user_auth.ex:288-311`) and the mount re-resolves the session and checks `Accounts.locked_out?/1` (`user_confirmation_required_live.ex:17-40`).

| Action | Signed out | TOTP pending | Disabled or scheduled for deletion | Unconfirmed, inside 48 hours | Confirmed | Verification off | Locked out |
|--------|------------|--------------|------------------------------------|------------------------------|-----------|------------------|------------|
| See the page | no (login) | no (two-factor) | no (login) | no (/projects) | no (/projects) | no (/projects) | yes |
| Resend confirmation email | n/a | n/a | n/a | n/a | n/a | n/a | yes |
| Request an email correction | n/a | n/a | n/a | n/a | n/a | n/a | yes |
| Log out | n/a | n/a | n/a | n/a | n/a | n/a | yes |

Superuser, support access and project roles have no bearing; a locked-out superuser sees the same page (`confirmation_lockout_recovery_test.exs:119-146`).

**Preconditions beyond role**
- An email correction needs the account's current password (`accounts.ex:827-836`, `:849-858`).
- The new address must be well formed, at most 160 characters, different from the current one and not used by another account (`validators.ex:20-28`; `user.ex:241-256`; `accounts.ex:839-847`).
- At most 3 resends and, separately, 3 corrections per account per 15 minutes (`accounts.ex:758-782`, `:795-801`, `:1197-1206`).

## 4. What it touches

**Reads**: `user_tokens` and `users` for the session lookup on every mount (`accounts.ex:994-1006`); `users.confirmed_at`, `users.inserted_at` (`accounts.ex:1362-1368`); `users` for the password hash and address uniqueness on every validate and submit (`accounts.ex:827-858`; `user.ex:241-250`); Hammer buckets `confirmation_resend::<user_id>` and `email_change::<user_id>` (`accounts.ex:762-767`)

**Writes**: `user_tokens` insert, context `confirm`, on each allowed resend (`accounts.ex:1135-1142`, `:1199-1202`); `user_tokens` insert, context `change:<current email>`, on each allowed correction (`accounts.ex:740-744`); Hammer counter increments (Mnesia)

**Immediate side effects**
- Resend: email `email:confirmation` (reminder variant) to the current address; alert "We have sent a new confirmation link to <email>." (`user_confirmation_required_live.ex:50-56`; `.html.heex:28-32`), or the throttle warning (`:46-48`; `.html.heex:34-42`; `confirmation_lockout.ex:11-12`), or the failure alert and a `Logger.error` (`:58-66`; `.html.heex:54-63`)
- Correction: `email:update-email-warning` to the current address, then `email:update-email-instructions` to the new one; alert "We have sent confirmation instructions to <new address>." (`user_confirmation_required_live.ex:85-90`; `.html.heex:44-52`); on failure a `Logger.error` and an error under the email field (`:105-119`)
- On arrival by redirect, the lockout flash from the plug is shown here (`user_auth.ex:345-351`; `.html.heex:1-2`)

**Deferred side effects**
- none here; the confirm steps belong to flow-resend-account-confirmation and flow-change-email-confirm
- The session's `live_socket_id` (written at login, `user_auth.ex:181-192`) is honoured by this page's LiveView socket, so a revocation disconnects it; that belongs to flow-account-revocation-teardown

**External, non-transactional effects**
- Every email above. Tokens are inserted before the send and the rate allowance is spent before either, so a failed send still costs one of the three (flow-resend-account-confirmation 6.1; flow-change-email-confirm 6.2).

**Depends on config**
- `require_email_verification` (`accounts.ex:1366`)
- Hammer backend (`config/config.exs:25-28`)

**Product limits**
- 48-hour grace period before an unconfirmed account lands here (`accounts.ex:1367`)
- 3 resends per 15 minutes per account (S04)
- 3 corrections per 15 minutes per account (S10)

## 5. Scenarios

```gherkin
Feature: Confirm your email (lockout page)
  In order to get back into OpenFn after missing the confirmation deadline
  As a user whose account is blocked pending email confirmation
  I want to see why, get a new link, or fix my address

  @S01 @pending @variant:require-email-verification
  Scenario: A locked-out user sees why and every way out
    # Value: a blocked user understands what is wrong and can recover without contacting an administrator.
    Given my account "amara@example.org" was created 50 hours ago and is unconfirmed
    When I visit "/users/confirm-required"
    Then I see the heading "Confirm your email address"
    And I see "Your account is blocked pending email confirmation"
    And I see "amara@example.org"
    And I see a "Resend confirmation email" button
    And I see a "Change email address" form with "New email address" and "Enter password to confirm"
    And I see a "Log out" link
    # user_confirmation_required_live.ex:24-36; .html.heex:11-26, :65-72, :75-123, :125-129
    # user_confirmation_required_live_test.exs:35-49; reachability is shared-authenticated-session S05

  @S02 @pending @variant:require-email-verification
  Scenario: The page shows no project data, chrome or socket credential
    # Value: a locked-out account learns nothing about the projects it belongs to and holds nothing that opens a channel.
    Given my account was created 50 hours ago and is unconfirmed
    And I am an owner of project "Malawi HIV"
    When I visit "/users/confirm-required"
    Then I do not see "Malawi HIV"
    And I do not see the project picker, side menu or user menu
    And the page carries no socket token
    # user_confirmation_required_live.ex:36 (layout app.html.heex:1-5); router.ex:246-250 (no InitAssigns)
    # user_auth.ex:378-392; layouts/root.html.heex:20
    # user_confirmation_required_live_test.exs:51-63; user_auth_test.exs:633-656 (no user_token for this path)

  @S03 @pending @variant:require-email-verification
  Scenario: Asking for a new confirmation link
    # Value: a user whose first link expired or never arrived can get another one from the only page they can reach.
    Given my account "amara@example.org" was created 50 hours ago and is unconfirmed
    And I am on "/users/confirm-required"
    When I click "Resend confirmation email"
    Then I see "We have sent a new confirmation link to amara@example.org."
    And "amara@example.org" receives an email with subject "Confirm your OpenFn account"
    And the "Resend confirmation email" button is still enabled
    And the flow "flow-resend-account-confirmation" continues from that email (its S08)
    # user_confirmation_required_live.ex:42-56; .html.heex:28-32; accounts.ex:1197-1206; user_notifier.ex:121-133
    # user_confirmation_required_live_test.exs:65-87

  @S04 @pending @variant:require-email-verification
  Scenario: A fourth resend within 15 minutes sends nothing and says why
    # Value: a blocked account can't be used to flood its inbox, and the user is told to check their mail instead of being told it was sent.
    Given my account was created 50 hours ago and is unconfirmed
    And I have clicked "Resend confirmation email" 3 times in the last 15 minutes
    When I click "Resend confirmation email"
    Then I see "You've asked for this a few times recently. Check your inbox and spam folder; you can request another in a few minutes."
    And no confirmation email is sent
    # user_confirmation_required_live.ex:46-48; .html.heex:34-42; confirmation_lockout.ex:11-12, :48-50
    # accounts.ex:758-782, :1197-1206; user_confirmation_required_live_test.exs:89-110

  @S05 @pending @variant:require-email-verification
  Scenario: Resends from the bookmarked resend link count against the same allowance
    # Value: the three-per-15-minutes cap can't be doubled by switching to the other route.
    Given my account was created 50 hours ago and is unconfirmed
    And I have opened "/users/send-confirmation-email" 3 times in the last 15 minutes
    When I click "Resend confirmation email" on "/users/confirm-required"
    Then I see "you can request another in a few minutes"
    And I do not see "We have sent a new confirmation link"
    And no confirmation email is sent
    # accounts.ex:1197-1206 (both routes call remind_account_confirmation/1); confirmation_lockout.ex:28-30
    # user_confirmation_required_live_test.exs:112-138

  @S06 @pending @variant:require-email-verification
  Scenario: A failed send tells me to try again
    # Value: the user doesn't wait for an email that was never sent, and knows who to ask if it keeps failing.
    Given my account was created 50 hours ago and is unconfirmed
    And the mail service rejects the message
    When I click "Resend confirmation email"
    Then I see "We could not send that email just now. Try again in a moment; if it keeps failing, contact your instance administrator."
    And I do not see "We have sent a new confirmation link"
    # user_confirmation_required_live.ex:58-66; .html.heex:54-63; user_notifier.ex:57-59; no test

  @S07 @pending @variant:require-email-verification
  Scenario: Correcting a mistyped address sends the link to the new address
    # Value: a user who mistyped their address at sign-up is not locked out for good.
    Given my account "amara@exmaple.org" was created 50 hours ago and is unconfirmed
    And I am on "/users/confirm-required"
    When I set "New email address" to "amara@example.org"
    And I set "Enter password to confirm" to my password
    And I click "Update email"
    Then I see "We have sent confirmation instructions to amara@example.org."
    And "Enter password to confirm" is empty
    And the flow "flow-change-email-confirm" has started for "amara@example.org" (its S02)
    # user_confirmation_required_live.ex:79-90; .html.heex:44-52, :75-123; accounts.ex:740-756, :795-801
    # user_confirmation_required_live_test.exs:160-185 (both emails, in order; password not in the html), :187-216

  @S08 @pending @variant:require-email-verification
  Scenario: A correction with the wrong password is refused
    # Value: someone at an unattended, locked-out session can't point the account at an inbox they control.
    Given my account was created 50 hours ago and is unconfirmed
    When I submit "Change email address" with "typo-fixed@example.com" and a wrong password
    Then "Enter password to confirm" shows an error
    And I do not see "We have sent confirmation instructions"
    And no email is sent
    # user_confirmation_required_live.ex:84, :92-96; accounts.ex:849-858
    # user_confirmation_required_live_test.exs:144-158; the error copy is in 6.1

  @S09 @pending @variant:require-email-verification
  Scenario Outline: An address that can't be used is refused before anything is sent
    # Value: the correction can only go to a new, well-formed address no other account owns, so no confirmation mail reaches another account's owner.
    Given my account "amara@exmaple.org" was created 50 hours ago and is unconfirmed
    And "taken@example.org" belongs to another account
    When I set "New email address" to "<address>" and leave the field
    Then "New email address" shows "<error>"
    And the "Update email" button is disabled
    And no email is sent

    Examples:
      | address            | error                         |
      | amara@exmaple.org  | Please change your email      |
      | taken@example.org  | This value should be unique.  |
      | not-an-address     | Email address not valid.      |
    # user_confirmation_required_live.ex:70-77; .html.heex:100-106, :118; accounts.ex:827-847
    # user.ex:241-256; validators.ex:20-28; errors.po:4-5, :37-38, :70-71; no test on this page

  @S10 @pending @variant:require-email-verification
  Scenario: A fourth correction within 15 minutes sends nothing and keeps what I typed
    # Value: a blocked account can't be used to send mail to arbitrary addresses at volume, and the user doesn't lose their input.
    Given my account was created 50 hours ago and is unconfirmed
    And I have submitted 3 address corrections in the last 15 minutes
    When I submit a correction to "typo-fixed-4@example.com" with my password
    Then I see "You've asked us to change this address a few times recently."
    And "New email address" still contains "typo-fixed-4@example.com"
    And I do not see "We have sent confirmation instructions"
    And no "Please confirm your new email" email is sent
    # user_confirmation_required_live.ex:98-103; .html.heex:88-98; accounts.ex:758-782, :795-801
    # user_confirmation_required_live_test.exs:218-249; also asserted by flow-change-email-confirm S08 (see 8)

  @S11 @pending @variant:require-email-verification
  Scenario: Spending the resend allowance does not block a correction
    # Value: a user who resent to a mistyped address until throttled can still fix the address.
    Given my account was created 50 hours ago and is unconfirmed
    And I have clicked "Resend confirmation email" 4 times
    When I submit a correction to "typo-fixed@example.com" with my password
    Then I see "We have sent confirmation instructions to typo-fixed@example.com."
    And I do not see "You've asked us to change this address a few times recently."
    # accounts.ex:761 (separate buckets), :795-801, :1197-1206; user_confirmation_required_live_test.exs:251-280

  @S12 @pending @variant:require-email-verification
  Scenario Outline: An account that is not locked out is sent to its projects
    # Value: a user who can use OpenFn is never told their account is blocked.
    Given my account was created <age> and <state>
    When I visit "/users/confirm-required"
    Then I am on "/projects"

    Examples:
      | age          | state                 |
      | 50 hours ago | is confirmed          |
      | 2 hours ago  | is unconfirmed        |
    # user_confirmation_required_live.ex:24, :37-39; accounts.ex:1360-1368
    # user_confirmation_required_live_test.exs:283-298

  @S13 @pending @variant:default
  Scenario: Nobody is held here when verification is not required
    # Value: instances that don't require verified addresses never block anyone, however old their unconfirmed account.
    Given email verification is not required
    And my account was created 50 hours ago and is unconfirmed
    When I visit "/users/confirm-required"
    Then I am on "/projects"
    # accounts.ex:1366; user_confirmation_required_live.ex:24, :37-39
    # the plug half is user_auth_test.exs:660-689; no test mounts this page with the flag off

  @S14 @pending @variant:require-email-verification
  Scenario: A locked-out user can log out
    # Value: someone signed in to the wrong account, or on a shared computer, can leave without confirming.
    Given my account was created 50 hours ago and is unconfirmed
    And I am on "/users/confirm-required"
    When I click "Log out"
    Then the flow "flow-log-out" has started
    # .html.heex:125-129; router.ex:71 (outside the authenticated scope, so the lockout never applies)
    # confirmation_lockout.ex:16-17; confirmation_lockout_recovery_test.exs:107-117
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A throttled or failed resend does not clear `email_sent`, and a throttled resend does not clear `send_failed`, so earlier alerts stay up next to the new one | `user_confirmation_required_live.ex:46-48`, `:58-66`; `.html.heex:28-63` | after three sends, "We have sent a new confirmation link to <email>." beside "You've asked for this a few times recently", though nothing was sent | fix |
| A wrong password shows "Your passwords do not match.", the copy for a mismatched new-password pair, because both use the msgid "does not match password" (same row in profile-account 6.1) | `accounts.ex:853-855`; `errors.po:43-44` | under "Enter password to confirm": "Your passwords do not match." though only one password was typed | fix |
| The block copy says a link was sent "when you signed up". A superuser created through first setup was never sent one, and an account created by a superuser did not sign up | `.html.heex:17-22`; `extensions/account_hook.ex:20-26` | a first-setup operator locked out after 48 hours is told to open an email that does not exist | fix |
| `validate_email` checks the current password on every blur with no limit, while only submit is rate-limited, so a held locked-out session can guess the account password without bound (the same gap is a decide row in profile-account 6.2) | `user_confirmation_required_live.ex:70-77`; `accounts.ex:827-836`, `:849-858`; `.html.heex:107-114` | nothing; an attacker sees the error appear or clear | fix |
| The same blur check says whether any address has an account ("This value should be unique."), unmetered; the same disclosure exists at sign-up (auth-register 6.5) | `user.ex:241-250`; `accounts.ex:833` | an enumeration oracle for anyone holding a locked-out session | decide |
| Neither event re-checks `locked_out?` or `confirmed_at`, and `remind_account_confirmation/1` has no confirmed guard (the controller route has one). A page left open after confirming in another tab still sends a link | `user_confirmation_required_live.ex:42-46`, `:79-86`; `accounts.ex:1197-1206`; `user_confirmation_controller.ex:51-53` | "We have sent a new confirmation link" for an already confirmed account; the link then does nothing | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Own live_session with no on_mount, because InitAssigns would redirect a locked-out user back here in a loop; the mount does its own session lookup and the inverse lockout check. Test pins that every exempt LiveView is hook-free | `router.ex:246-250`; `user_confirmation_required_live.ex:17-40`; `confirmation_lockout_test.exs:72-94` | preserve |
| Being in its own live_session means arriving from any other LiveView is a full page load | `router.ex:248` | preserve |
| A mount with no valid session (revoked, disabled, expired) redirects to /projects, which then redirects to /users/log_in, with no flash; only reachable on a websocket remount, since the HTTP plug refuses first | `user_confirmation_required_live.ex:18-22`, `:37-39`; `user_auth.ex:290-300` | decide |
| TOTP-pending sessions are refused only by the HTTP plug; the mount does not check | `user_auth.ex:302-303`; `user_confirmation_required_live.ex:17-24` | preserve |
| The plug's lockout flash ("Your account is blocked pending email confirmation. Confirm your email address, or update it below...") repeats the page's own body copy, so both show on arrival | `confirmation_lockout.ex:8-9`; `user_auth.ex:345-351`; `.html.heex:1-2`, `:17-26` | decide |
| Flashes auto-hide after 5 seconds, including an "Email change link is invalid or it has expired." carried in from a failed link (flow-change-email-confirm S09) | `common.ex:530-535`; `assets/js/hooks/index.ts:532-549` | decide |
| The typed address is used raw for the token's `sent_to` and the success alert, while validation downcases it | `user_confirmation_required_live.ex:86-89`; `validators.ex:27` | decide |
| After a correction is requested, the page still names the old address and "Resend confirmation email" still sends to it, since the email only changes when the link is opened | `.html.heex:20`, `:30`; `user_confirmation_required_live.ex:44-46` | decide |
| The resend button is deliberately never disabled; the rate limit is the only bound (test comment) | `.html.heex:65-72`; `user_confirmation_required_live_test.exs:79-81` | preserve |
| "Update email" is disabled until the changeset is valid; both fields validate on blur | `.html.heex:105`, `:112`, `:118` | preserve |
| "Log out" is a GET link | `.html.heex:126`; `router.ex:71` | decide |
| Page title "Confirm your email" differs from the heading "Confirm your email address" | `user_confirmation_required_live.ex:28`; `.html.heex:12` | preserve |
| A failed correction send shows "could not be updated, please try again" under the field, where the profile shows a flash (owned by flow-change-email-confirm 6.2) | `user_confirmation_required_live.ex:105-119` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| 3 resends per 15 minutes per account, bucket `confirmation_resend`, shared with `/users/send-confirmation-email` | `accounts.ex:758-767`, `:1197-1206` | yes, S04, S05 | preserve |
| 3 corrections per 15 minutes per account, bucket `email_change`; the profile path is unmetered | `accounts.ex:758-767`, `:788-801` | yes, S10 | preserve |
| Rate limiter fails open with a warning log if Hammer errors | `accounts.ex:774-780` | no | preserve |
| Emails are sent synchronously in the event. The correction button shows "Sending confirmation email..." while it waits; the resend button has no `phx-disable-with`, so a slow mailer allows repeat clicks, each spending allowance | `.html.heex:65-72`, `:119`; `user_notifier.ex:49-60` | yes | decide |
| 48-hour grace period before lockout | `accounts.ex:1367` | yes | preserve |

### 6.5 Things seen but not understood

- Whether the password input echoes the typed password back as its `value` after a refused submit (S08, S10). The input passes `Form.normalize_value("password", @value)` (`new_inputs.ex:651-669`); `deps/` is not present, so phoenix_html's handling could not be read. The test only asserts the password is gone after a successful request (`user_confirmation_required_live_test.exs:174-175`). Disposition: decide.
- `confirmation_lockout.ex:3-4` says the module is expected to be absorbed into a general account-state check and deleted; the shape of this page may change with it. Disposition: preserve.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the email-correction blur check stop verifying the password, or be metered like submit? (6.1) (owner: security)
- Should "This value should be unique." on this page be replaced with a non-disclosing response, in line with whatever is decided for sign-up? (6.1) (owner: security)
- What should a first-setup superuser who was never sent a link be told here? (6.1) (owner: product)
- Should the lockout flash be suppressed on this page, given the body says the same thing? (6.2) (owner: product)
- S10 here and flow-change-email-confirm S08 assert the same in-page throttle; which one keeps it? (owner: cataloguing)
- Should a revoked or expired session on this page go straight to login with a message? (6.2) (owner: product)

## Proposed flows

- `flow-log-out`: clicking "Log out" issues GET /users/log_out, which deletes the session token, broadcasts `disconnect` on the session's `live_socket_id`, renews the session, clears the remember-me cookie and lands on /users/log_in with "Logged out successfully." (`router.ex:71`; `user_auth.ex:114-132`; `confirmation_lockout_recovery_test.exs:107-117`). Surfaces: auth-confirmation-required, the user menu on every app page (shared-authenticated-session), controller:user-log-out, auth-login. flow-account-revocation-teardown already lists controller:user-log-out but only for the own-deletion tab, so it does not own the ordinary journey. This file asserts only the handoff (S14).

Referenced: flow-change-email-confirm (S07), flow-resend-account-confirmation (S03), flow-login-return-to (via shared-authenticated-session S01).

## Proposed shared

- `shared-flash-messages`: `Common.flash` for `:info` and `:error`, rendered by this page and most others, with the `Flash` hook that auto-hides after 5 seconds, restarts the timer on hover, and clears on click via `lv:clear-flash` (`common.ex:517-598`; `assets/js/hooks/index.ts:532-549`). Surfaces: every view that renders `Common.flash`, directly or through the live and settings layouts. This file lists the hook in `js_hooks` and records only the auto-hide quirk in 6.2.

## Lead resolution (batch 9)

- `flow-log-out` and `shared-flash-messages` created. S10 duplicates flow-change-email-confirm S08; listed for the final cleanup.
