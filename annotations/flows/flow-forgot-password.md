---
id: flow-forgot-password
type: flow
title: Forgot password
status: not-started
owner:

trigger:
  entry: auth-login                       # "Forgot your password?" (user_session_html/new.html.heex:92-96)
  exit: projects-dashboard                # /projects, the signed-in landing (user_auth.ex:514)
  surfaces:
    - auth-login                          # "Forgot your password?" link to /users/reset_password
    - auth-reset-password                 # request: GET/POST /users/reset_password (router.ex:183-184; user_reset_password_controller.ex:8-26)
    - email:password-reset                # "Finish resetting your password" (user_notifier.ex:251-265)
    - auth-reset-password                 # set password: GET/PUT /users/reset_password/:token (router.ex:185-186; user_reset_password_controller.ex:28-46)
    - pubsub:user_socket:<user_id>        # disconnect broadcast after a reset (accounts.ex:1328; user_auth.ex:163-166); the revocation is flow-account-revocation-teardown
    - pubsub:users_live:<user_id>
    - auth-login                          # "Password reset successfully." and the new password (user_reset_password_controller.ex:38-41)
    - auth-two-factor                     # MFA accounts only (user_session_controller.ex:40-46)
    - projects-dashboard
  reachable_when:
    - the browser has no valid session or remember-me cookie; every hop up to and including log in sits behind redirect_if_user_is_authenticated (`router.ex:175-186`; `user_auth.ex:271-279`)
    - the email reaches the person only when a mail provider is configured (variant `mail-provider`)

inherits:
  - shared-authenticated-session          # the :browser pipeline on every hop, its S03 two-factor gate, and its S11 first-setup redirect

url_params:
  - name: token (path segment of /users/reset_password/:token)
    set_by: email:password-reset
    effect: url-safe base64 of 32 random bytes; its SHA-256 hash selects an unexpired `reset_password` token whose `sent_to` equals the account's current email (user_token.ex:142-153, :168-191)

config_variants:
  default: { MAIL_PROVIDER: unset, auth provider: none }          # read under this one unless a scenario is tagged; mail stays in the Local adapter (config/config.exs:83)
  mail-provider: { MAIL_PROVIDER: local | mailgun | smtp | ... }  # bootstrap.ex:398-425; the only variant in which a real person receives the email
  mfa-enabled-account: { user.mfa_enabled: true }                 # per account, not per instance; adds the auth-two-factor hop

inventory:
  routes:
    - get /users/reset_password  UserResetPasswordController :new             # owned by auth-reset-password
    - post /users/reset_password  UserResetPasswordController :create         # owned by auth-reset-password
    - get /users/reset_password/:token  UserResetPasswordController :edit     # owned by auth-reset-password
    - put /users/reset_password/:token  UserResetPasswordController :update   # owned by auth-reset-password
  events: []
  js_hooks: []
  policies:
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279)
    - LightningWeb.UserResetPasswordController.get_user_by_reset_password_token/2 plug (user_reset_password_controller.ex:6, :48-58)
    - Lightning.Accounts.login_blocked?/1 (accounts.ex:329-345)
  workers: []
  api_endpoints: []
  emails:
    - email:password-reset
  config:
    - :lightning, Lightning.Mailer adapter      # config/config.exs:83; bootstrap.ex:398-425
  not_reachable_here:
    - Lightning.Projects.generate_user_tokens/1 (projects.ex:2102-2119); the invitation mints the same token, owned by flow-invite-new-collaborator

related:
  - lib/lightning_web/controllers/user_reset_password_controller.ex
  - lib/lightning_web/controllers/user_session_controller.ex
  - lib/lightning_web/controllers/user_totp_controller.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning/accounts.ex                  # deliver_user_reset_password_instructions/2 :1268-1282, get_user_by_reset_password_token/1 :1296-1304, reset_user_password/2 :1318-1334
  - lib/lightning/accounts/user_token.ex
  - lib/lightning/accounts/user_notifier.ex
  - test/lightning_web/controllers/user_reset_password_controller_test.exs
  - test/lightning/accounts_test.exs           # :1857-1962
flows:
  - flow-invite-new-collaborator               # invitees set their first password on the same token path; its S03 recovers a lapsed invitation through this flow
  - flow-account-revocation-teardown           # a completed reset revokes every session and token the same way
  - flow-login-return-to                       # the log in hop's return path; see 6.2
---

## 1. Purpose

Anyone with an account who can't remember their password uses this to prove they still own the
account's email address and get back to their projects without asking a superuser. Done badly it
either strands locked-out users, or turns an inbox, a leaked link or a guessed email into a way to
take over an account or learn who has one.

## 2. What it does

A signed-out user clicks "Forgot your password?" on log in, requests instructions on /users/reset_password, opens the link in "Finish resetting your password", sets a new password (ending every other session and token), logs in with it, passes two-factor if enrolled, and lands on /projects.

## 3. Who can do what

Sources: `router.ex:175-193`; `user_auth.ex:271-279`, `:288-303`; `user_reset_password_controller.ex:6`, `:48-58`;
`user_session_controller.ex:31-52`; `user_totp_controller.ex:7`, `:33-41`. No policy module; access is
route scope, the token plug and the login gate.

| Action                                   | Signed-out visitor | Holder of a valid link (signed out) | Signed-in user |
|------------------------------------------|--------------------|-------------------------------------|----------------|
| Request instructions for any email       | yes                | yes                                 | no, sent to /projects |
| Set a new password                       | no                 | yes, once                           | no, sent to /projects |
| Log in with the new password             | yes, if the account is active | yes, if the account is active | no, sent to /projects |
| Pass the second factor                   | MFA accounts only, after the password step | same                  | n/a            |

**Preconditions beyond role**
- The link is valid for one day and only while the account's email equals the address it was sent to (`user_token.ex:31`, `:174-179`).
- Account state is checked only at log in: a disabled or scheduled-for-deletion account can request and complete a reset, then is refused (`accounts.ex:318-320`, `:329-345`; `user_session_controller.ex:31-38`).
- The reset does not touch the second factor; an MFA account still needs its authenticator or a backup code (`user.ex:357-362`; `user_session_controller.ex:40-46`).
- No rate limit on any hop (6.5).

## 4. What it touches

**Reads**: `users`, `user_tokens`, `user_totps` and `user_backup_codes` (two-factor hop only)

**Writes**
- Request hop: `user_tokens` insert, context `reset_password`, hashed, `sent_to` = the account's email; only for a registered email (`accounts.ex:1273-1276`; `user_token.ex:142-153`).
- Set password hop: `users.hashed_password` update and delete of every `user_tokens` row for the user, in one transaction (`accounts.ex:1318-1325`; `user_token.ex:236-238`).
- Log in hop: `user_tokens` insert, context `session` (`user_auth.ex:28-31`).
- Two-factor hop: `user_totps.last_totp_at`, or the used backup code's `used_at` (auth-two-factor; `accounts.ex:472-483`).

**Immediate side effects** (in the same request)
- Request hop: email `email:password-reset` sent synchronously, result discarded (`accounts.ex:1278-1281`; `user_notifier.ex:49-60`); flash "If your email is in our system, you will receive instructions to reset your password shortly." and redirect to /projects, which a signed-out browser bounces to /users/log_in after storing /projects as the return path (`user_reset_password_controller.ex:20-25`; `router.ex:349`; `user_auth.ex:296-298`, `:490-492`).
- Set password hop: `disconnect` broadcast on `user_socket:<id>` and `users_live:<id>` after commit (`accounts.ex:1328`; `user_auth.ex:163-166`); flash "Password reset successfully." and redirect to /users/log_in without a session (`user_reset_password_controller.ex:34-41`).
- Log in hop: session renewed; MFA accounts get `user_totp_pending` and go to /users/two-factor, others go to the stored return path or /projects (`user_session_controller.ex:40-51`; `user_auth.ex:54-70`, `:96-103`).
- Two-factor hop: pending flag cleared, redirect to the return path or /projects (`user_totp_controller.ex:20-23`; `user_auth.ex:486-488`).
- No audit event on any hop.

**Deferred side effects** (later, elsewhere)
- Every other browser and device of the account is signed out as its transports drop or it next reloads (flow-account-revocation-teardown).

**External, non-transactional effects**
- The reset email leaves through the mail adapter after the token insert; a failed send does not roll back the token or change the response (`accounts.ex:1276-1281`).

**Depends on config**
- Mail adapter: whether the email reaches anyone (variant `mail-provider`).
- Endpoint URL config sets the host in the emailed link (`user_reset_password_controller.ex:16`).

**Product limits**
- The link expires after one day, and the email says so (`user_token.ex:31`; `user_notifier.ex:261`).
- Passwords are 12 to 72 characters (`user.ex:261`).

## 5. Scenarios

```gherkin
Feature: Forgot password
  In order to get back into my account when I've forgotten my password
  As someone who owns the account's email address
  I want to reset it from an emailed link and log in with the new one

  @S01 @pending @variant:mail-provider
  Scenario: Reset from the log in page through to the projects list
    # Value: a locked-out user gets back to their work without a superuser.
    Given "amara@example.org" is an active user without MFA
    And I am signed out on "/users/log_in"
    When I click "Forgot your password?"
    And I enter "amara@example.org" in "Email" and click "Send instructions to reset password"
    Then I am on "/users/log_in"
    And I see "If your email is in our system, you will receive instructions to reset your password shortly."
    And "amara@example.org" receives an email "Finish resetting your password"
    When I open the link in that email
    Then I see "Reset password"
    When I enter "a long new password" in "New password" and "Confirm new password" and click "Reset password"
    Then I am on "/users/log_in" and see "Password reset successfully."
    And I am not signed in
    And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    When I log in with "amara@example.org" and "a long new password"
    Then I am on "/projects"
    # user_session_html/new.html.heex:92-96; user_reset_password_controller.ex:12-46; accounts.ex:1268-1334
    # user_notifier.ex:251-265; user_session_controller.ex:15-51; user_auth.ex:63-70, :514
    # user_reset_password_controller_test.exs:20-35 (request), :86-105 (reset, no session); no test walks the whole journey

  @S02 @pending
  Scenario: The old password stops working once the reset completes
    # Value: whoever knew or guessed the old password is cut off as soon as the owner resets it.
    Given "amara@example.org" has reset her password from an emailed link
    When anyone logs in with "amara@example.org" and her old password
    Then they see "Invalid email or password"
    And they are not signed in
    # user.ex:357-362; accounts.ex:1318-1325, :359-363; user_session_controller.ex:22-25

  @S03 @pending @variant:mfa-enabled-account
  Scenario: A reset does not bypass two-factor
    # Value: someone with access to the owner's inbox still can't get into an account protected by a second factor.
    Given "amara@example.org" has MFA enabled
    And she has set a new password from an emailed reset link
    When she logs in with "amara@example.org" and the new password
    Then she is on "/users/two-factor"
    When she enters a valid authenticator code
    Then she is on "/projects"
    # user.ex:357-362 (only password is cast); user_session_controller.ex:40-46; user_totp_controller.ex:17-23
    # user_session_controller_test.exs:166-182; user_totp_controller_test.exs:107-119

  @S04 @pending
  Scenario: Using one reset link kills every other link already sent
    # Value: older reset emails left in an inbox stop being a way into the account once the owner has reset.
    Given "amara@example.org" requested reset instructions twice and received two emails
    When she sets a new password from the second email's link
    And anyone opens the first email's link
    Then they see "Reset password link is invalid or it has expired."
    # accounts.ex:1321-1324; user_token.ex:236-238; user_reset_password_controller.ex:48-58
    # accounts_test.exs:1946-1953 (all tokens deleted); the refusal copy is auth-reset-password S07

  @S05 @pending
  Scenario: A disabled account can reset but still can't log in
    # Value: an emailed reset link is never a way around a superuser disabling or scheduling an account for deletion.
    Given "ruth@example.org" is disabled
    When she requests reset instructions and sets a new password from the emailed link
    And she logs in with "ruth@example.org" and the new password
    Then she sees "This user account is disabled"
    And she is not signed in
    # accounts.ex:318-320 (no state filter), :329-345; user_session_controller.ex:31-38
    # user_notifier_test.exs:573-585 (email reaches a disabled account); the login refusal is auth-login S04
```

Handoffs, not repeated here: an unregistered email getting the same response is auth-reset-password
S02; link expiry, email-change invalidation, single use and malformed links are auth-reset-password
S07 to S10; password rules are its S12; the invitee's set-password journey is flow-invite-new-collaborator
S01 and its lapsed-invitation recovery through this flow is its S03; the revocation of other browsers
is flow-account-revocation-teardown.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The request hop answers the same words for every email, but registered emails wait for a token insert and a synchronous mail send before the redirect; unknown emails return at once. A timing oracle for who has an account (same row as auth-reset-password 6.1) | `user_reset_password_controller.ex:12-25`; `accounts.ex:1273-1281`; `user_notifier.ex:49-60` | nothing; a script can enumerate accounts by response time | fix (verify first) |
| A failed send is discarded and the user is told instructions are coming; an adapter that raises gives a 500 only for registered emails (same row as auth-reset-password 6.1) | `accounts.ex:1278-1281`; `user_notifier.ex:57-59` | waits for an email that never arrives, with no way to know; or a server error only for real accounts | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The request hop redirects to /projects, which a signed-out browser bounces to /users/log_in after overwriting any stored return path with "/projects"; a deep link that brought the visitor to log in is lost once they use "Forgot your password?" in the same browser | `user_reset_password_controller.ex:25`; `router.ex:349`; `user_auth.ex:296-298`, `:490-492`, `:96-103`; flow-login-return-to | decide |
| A successful reset lands on log in rather than signing in, so the journey needs the password typed twice more (deliberate: "avoid a leaked token giving the user access") | `user_reset_password_controller.ex:34-41`; `user_reset_password_controller_test.exs:95-96` | preserve |
| Every request adds another valid link; all stay valid until one is used or they age out (S04 covers the use case) | `accounts.ex:1273-1276`; `user_token.ex:168-191` | decide |
| A disabled or scheduled-for-deletion account receives the email and completes the reset before being told at log in that it is blocked | `accounts.ex:318-320`; `user_notifier_test.exs:573-585`; `user_session_controller.ex:31-38` | decide |
| The link can be opened in a different browser from the one that requested it; nothing ties the token to the requesting session | `user_token.ex:142-153`, `:168-188` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Link valid for one day | `user_token.ex:31`; `user_notifier.ex:261` | yes, stated in the email | preserve |
| The mail send blocks the request hop's response | `accounts.ex:1278-1281`; `user_notifier.ex:57` | yes, a slower redirect with a slow provider | decide |

### 6.5 Things seen but not understood

- No rate limit, throttle, CAPTCHA or per-address cap on requesting instructions, opening links or setting a password. Anyone can make the instance send unlimited reset emails to any registered address (mail flooding of the owner, sender reputation of the instance) and grow `user_tokens` without bound. Hammer is used elsewhere (`token_exchange_controller.ex:119`), not here. A finding, not a behaviour to keep. Disposition: decide.
- No audit event or log line records a requested or completed reset, though completing one revokes every session and API token (`user_reset_password_controller.ex:12-46`; `accounts.ex:1318-1334`). Disposition: decide.
- An MFA user who has lost both their password and their authenticator, and has no backup codes, has no self-service way back in; this flow gets them only as far as /users/two-factor. Whether a superuser path exists was not checked. Disposition: decide.
- On instances with an SSO provider, a user who normally signs in through it can set a local password here and then log in with email and password, bypassing the provider; nothing on any hop reads AuthProviders (auth-reset-password 6.5). Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should reset requests be rate limited per address and per client, and answered in constant time so registered emails can't be told apart (6.1, 6.5)? (owner: security)
- Should requested and completed resets be audited (6.5)? (owner: security)
- Should a new request invalidate earlier links, and should a blocked account be sent a reset email at all (6.2)? (owner: security)
- Should "Forgot your password?" keep the deep link the visitor was heading to (6.2)? (owner: product)
- Should accounts on SSO instances be able to set a local password through this flow (6.5)? (owner: security)
- What is the recovery path for an MFA user who has lost their authenticator and backup codes (6.5)? (owner: product)

## Proposed flows

none. Referenced: flow-invite-new-collaborator (same token path; its S03 recovers through this flow), flow-account-revocation-teardown (the revocation a reset starts, S01), flow-login-return-to (the return path this flow overwrites, 6.2).

## Proposed shared

none. Referenced: shared-authenticated-session (pipeline, two-factor gate S03, first-setup S11).
