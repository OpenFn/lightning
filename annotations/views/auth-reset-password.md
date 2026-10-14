---
id: auth-reset-password
type: view
title: Reset password
status: not-started
owner:

trigger:
  old_route: /users/reset_password and /users/reset_password/:token
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the visitor has no valid session and no valid remember-me cookie; otherwise every request (GET, POST and PUT) redirects to /projects (`router.ex:175-176`, `:183-186`; `user_auth.ex:271-279`, `:514`)
    - first-setup-open only: a superuser exists; otherwise every request is redirected to /first_setup (`router.ex:29`; `plugs/first_setup.ex:11-33`)
    - /users/reset_password/:token only: the token matches an unexpired `reset_password` row whose `sent_to` equals the account's current email (`user_reset_password_controller.ex:6`, `:48-58`; `user_token.ex:168-191`)

inherits:
  - shared-authenticated-session     # the :browser pipeline only (fetch_current_user writes live_socket_id, router.ex:28; user_auth.ex:175-192) and its S11 first-setup gate. Its S01 to S06 gates do not run here: this scope has no :require_authenticated_user
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: token (path segment of /users/reset_password/:token)
    set_by: email:password-reset, email:project-invitation
    effect: url-safe base64 of 32 random bytes; its SHA-256 hash identifies the `reset_password` user token and so the account (user_token.ex:142-153, :168-188)

config_variants:
  default: { allow_signup: false, allow_first_setup: false, require_email_verification: false, auth provider: none, MAIL_PROVIDER: unset }   # read under this one unless a scenario is tagged
  signup-allowed: { lightning.allow_signup: true }                          # ALLOW_SIGNUP, bootstrap.ex:379-381; shows "Register" on both pages (new.html.heex:51-56, edit.html.heex:65-70)
  first-setup-open: { lightning.allow_first_setup: true, no superuser }      # bootstrap.ex:234; read in code only
  mail-provider: { MAIL_PROVIDER: local | mailgun | smtp | ... }           # bootstrap.ex:398-425; with it unset the base config's Swoosh.Adapters.Local (config/config.exs:83) keeps mail in memory, see 6.2
  require-email-verification: { lightning.require_email_verification: true } # bootstrap.ex:387-389; does not change this page, and a reset does not confirm the address (6.2)
  # sso-provider (auth provider at /settings/authentication) does not change this page: no code path here reads AuthProviders. See 6.5.

inventory:
  routes:
    - get /users/reset_password  UserResetPasswordController :new             # router.ex:183
    - post /users/reset_password  UserResetPasswordController :create         # router.ex:184
    - get /users/reset_password/:token  UserResetPasswordController :edit     # router.ex:185
    - put /users/reset_password/:token  UserResetPasswordController :update   # router.ex:186
  events:
    - UserResetPasswordController#new
    - UserResetPasswordController#create
    - UserResetPasswordController#edit
    - UserResetPasswordController#update
  js_hooks: []                         # the password reveal eye on the edit page is an inline phx-click JS command (new_inputs.ex:685-695); see 6.5
  policies:
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279)
    - LightningWeb.UserResetPasswordController.get_user_by_reset_password_token/2 plug (user_reset_password_controller.ex:6, :48-58)
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)
  workers: []
  api_endpoints: []
  emails:
    - email:password-reset             # "Finish resetting your password" (user_notifier.ex:251-265)
  config:
    - :lightning, :allow_signup                 # new.html.heex:51-56; edit.html.heex:65-70
    - :lightning, :allow_first_setup            # plugs/first_setup.ex:12
    - :lightning, Lightning.Mailer adapter      # config/config.exs:83; bootstrap.ex:398-425
    - Lightning.Config.reset_password_token_validity_in_days/0  # config.ex:161-163, used only in the email copy (user_notifier.ex:261)
  not_reachable_here:
    - LightningWeb.Plugs.BlockRoutes (router.ex:31-42); its rules for /users/register and /first_setup never match these paths
    - Lightning.Projects.generate_user_tokens/1 (projects.ex:2102-2119); mints the same `reset_password` token for invitees; owned by flow-invite-new-collaborator

related:
  - lib/lightning_web/controllers/user_reset_password_controller.ex
  - lib/lightning_web/controllers/user_reset_password_html.ex
  - lib/lightning_web/controllers/user_reset_password_html/new.html.heex
  - lib/lightning_web/controllers/user_reset_password_html/edit.html.heex
  - lib/lightning_web/controllers/user_auth.ex                 # redirect_if_user_is_authenticated/2 :271-279, disconnect_user_sockets/1 :163-166
  - lib/lightning/accounts.ex                                  # get_user_by_email/1 :318-320, change_user_password/2 :899-901, deliver_user_reset_password_instructions/2 :1268-1282, get_user_by_reset_password_token/1 :1296-1304, reset_user_password/2 :1318-1334
  - lib/lightning/accounts/user_token.ex                       # :26-31, :142-153, :168-191, :236-238
  - lib/lightning/accounts/user.ex                             # validate_password/2 :258-267, maybe_hash_password/2 :269-281, password_changeset/3 :357-362
  - lib/lightning/accounts/user_notifier.ex                    # deliver/3 :49-60, deliver_reset_password_instructions/2 :251-265
  - priv/gettext/en/LC_MESSAGES/errors.po                      # :27-34, :43-44
  - test/lightning_web/controllers/user_reset_password_controller_test.exs
  - test/lightning/accounts_test.exs                           # :1857-1962
  - test/lightning/accounts/user_notifier_test.exs             # :573-585
  - auth-login                                                 # links here ("Forgot your password?", user_session_html/new.html.heex:93); a successful reset lands there
  - auth-register                                              # links here (user_registration_html/new.html.heex:105); "Register" link, signup-allowed only
flows:
  - flow-invite-new-collaborator        # invitees set their first password here (S11)
  - flow-account-revocation-teardown    # a successful reset revokes sessions and tokens the same way (S06); not yet one of its entries, see 8
  - flow-forgot-password
---

## 1. Purpose

Anyone with an account who cannot sign in, because they forgot their password or never had one
(an invited collaborator), uses this to prove they own the account's email address and choose a new
password. Without it they would need a superuser to reset it for them; done badly, it becomes a way
to find out who has an account, or to take over an account from a stale or leaked link.

## 2. What it does

- A signed-out visitor asks for reset instructions by email
- The response is the same whether or not the email has an account
- The holder of a valid link sets a new password
- The new password must meet the account password rules
- A successful reset sends the person to log in rather than signing them in
- A successful reset ends the account's other sessions and API tokens
- A link stops working once used, after one day, or once the account's email changes
- A malformed or unknown link is refused
- Invitees use the same page to set their first password

## 3. Who can do what

Sources: `router.ex:175-186`; `user_auth.ex:271-279`; `user_reset_password_controller.ex:6`, `:48-58`;
`user_token.ex:168-191`. There is no policy module; access is the route scope and the token plug.

| Action                                      | Signed-out visitor | Signed-out holder of a valid link | Signed-in user (any role, incl. superuser) |
|---------------------------------------------|--------------------|-----------------------------------|--------------------------------------------|
| See "Forgot your password?" page            | yes                | yes                               | no, redirected to /projects                |
| Request reset instructions for any email    | yes                | yes                               | no, redirected to /projects                |
| See "Reset password" (set password) page    | no, refused        | yes                               | no, redirected to /projects                |
| Set a new password                          | no, refused        | yes, once                         | no, redirected to /projects                |

**Preconditions beyond role**
- The link is valid for one day from when it was sent (`user_token.ex:31`, `:176-178`, `:190-191`).
- The link is valid only while the account's email equals the address it was sent to (`user_token.ex:178`).
- Any successful reset deletes every token for the account, so all outstanding links die together (`accounts.ex:1320-1324`; `user_token.ex:236-238`).
- Account state is not checked: a disabled or scheduled-for-deletion account can request and complete a reset (`accounts.ex:318-320`, `:1296-1304`; `user_notifier_test.exs:573-585`). See 6.2.
- No rate limit, throttle or CAPTCHA on any of the four actions (see 6.5).

## 4. What it touches

**Reads**: `users` (by email, citext so case-insensitive: `accounts.ex:318-320`, `priv/repo/migrations/20220405135153_create_users.exs:12`), `user_tokens` joined to `users` (`user_token.ex:168-188`)

**Writes**
- Request: `user_tokens` insert, context `reset_password`, storing the SHA-256 of the token and `sent_to` = the account's email; only when the email matches an account (`user_reset_password_controller.ex:13-18`; `accounts.ex:1273-1276`; `user_token.ex:142-153`).
- Set password: `users.hashed_password` update and delete of every `user_tokens` row for the user (sessions, API tokens, other reset and confirm tokens) in one transaction (`accounts.ex:1318-1334`; `user_token.ex:236-238`).

**Immediate side effects** (in the same request)
- Request: email `email:password-reset` "Finish resetting your password" delivered synchronously through `Mailer.deliver`; its result is discarded (`accounts.ex:1278-1281`; `user_notifier.ex:49-60`, `:251-265`; `user_reset_password_controller.ex:13-18`).
- Request: flash "If your email is in our system, you will receive instructions to reset your password shortly." and redirect to /projects (`user_reset_password_controller.ex:20-25`).
- Set password: after commit, `disconnect` broadcast on `user_socket:<id>` and `users_live:<id>` (`accounts.ex:1328`; `user_auth.ex:163-166`), the hand-off into flow-account-revocation-teardown.
- Set password: flash "Password reset successfully." and redirect to /users/log_in; the session is not written (`user_reset_password_controller.ex:34-41`; `user_reset_password_controller_test.exs:95-99`).
- Refused link: flash "Reset password link is invalid or it has expired." and redirect to /projects (`user_reset_password_controller.ex:53-57`).
- No audit event on request or reset.

**Deferred side effects** (later, elsewhere)
- none

**External, non-transactional effects**
- The reset email leaves through the configured mail adapter after the token is inserted; the insert is not rolled back if delivery fails (`accounts.ex:1276-1281`).

**Depends on config**
- Mail adapter: whether the email actually reaches anyone (variant `mail-provider`; `config/config.exs:83`, `bootstrap.ex:398-425`).
- `allow_signup` shows "Register" (variant `signup-allowed`).
- `allow_first_setup` with no superuser redirects everything to /first_setup (variant `first-setup-open`).
- Endpoint URL config sets the host in the emailed link (`user_reset_password_controller.ex:16`).

**Product limits**
- Reset links expire after one day (`user_token.ex:31`).
- Passwords are 12 to 72 characters (`user.ex:261`).

## 5. Scenarios

```gherkin
Feature: Reset password
  In order to get back into my account when I can't sign in
  As a person who owns the account's email address
  I want to request a reset link and use it to choose a new password

  @S01 @pending
  Scenario: Requesting reset instructions for a registered email
    # Value: someone locked out of their account can get back in without a superuser.
    Given I am signed out
    And "amara@example.org" is a registered user
    When I visit "/users/reset_password"
    Then I see "Forgot your password?"
    When I enter "amara@example.org" in "Email" and click "Send instructions to reset password"
    Then I am eventually on "/users/log_in"
    And I see "If your email is in our system, you will receive instructions to reset your password shortly."
    And the flow "flow-forgot-password" has started for "amara@example.org"
    # user_reset_password_controller.ex:8-26; new.html.heex:5, :29-39; accounts.ex:1268-1282
    # user_reset_password_controller_test.exs:13-17, :20-35 (redirect to /projects, flash, token row)
    # the /projects to /users/log_in bounce is user_auth.ex:287-299, see 6.2

  @S02 @pending
  Scenario: An unregistered email gets the same response and no email
    # Value: the page can't be used to find out who has an account on the instance.
    Given I am signed out
    And "nobody@example.org" is not a registered user
    When I request reset instructions for "nobody@example.org"
    Then I see "If your email is in our system, you will receive instructions to reset your password shortly."
    And I am redirected exactly as for a registered email
    And no reset token is created
    And no email is sent
    # user_reset_password_controller.ex:12-26; user_reset_password_controller_test.exs:37-49
    # the response timing differs; see 6.1

  @S03 @pending
  Scenario: Requesting a reset does not change the current password
    # Value: someone who types my email into this form can't lock me out of my account.
    Given "amara@example.org" can log in with "her current password"
    When anyone requests reset instructions for "amara@example.org"
    Then "amara@example.org" can still log in with "her current password"
    # user_reset_password_controller.ex:12-18 (no write to users); accounts.ex:1268-1282

  @S04 @pending
  Scenario: A valid link opens the set-password form
    # Value: the person who received the email can choose a new password from it.
    Given I am signed out
    And I hold a reset link for "amara@example.org" sent less than a day ago
    When I open the link
    Then I see "Reset password" with fields "New password" and "Confirm new password"
    And the link still works afterwards
    # user_reset_password_controller.ex:28-32, :48-52; edit.html.heex:5, :29-52
    # user_reset_password_controller_test.exs:62-65; accounts_test.exs:1891-1894 (lookup does not consume)

  @S05 @pending
  Scenario: Setting a new password sends me to log in without signing me in
    # Value: a leaked link can change the password but never hands its holder a signed-in session.
    Given I have opened a valid reset link for "amara@example.org"
    When I enter "a long new password" in "New password" and "Confirm new password" and click "Reset password"
    Then I am on "/users/log_in"
    And I see "Password reset successfully."
    And I am not signed in
    And "amara@example.org" can log in with "a long new password"
    # user_reset_password_controller.ex:34-41; accounts.ex:1318-1334
    # user_reset_password_controller_test.exs:86-105

  @S06 @pending
  Scenario: A reset ends every other session and API token for the account
    # Value: someone who resets because they think their account is compromised cuts off whoever else is in it.
    Given "amara@example.org" is signed in on another browser and has an API token
    When a new password is set for "amara@example.org" from a valid reset link
    Then every user token for "amara@example.org" is deleted, including the API token
    And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    # accounts.ex:1318-1334; user_token.ex:236-238; user_auth.ex:163-166
    # accounts_test.exs:1946-1953 (tokens deleted), :1955-1961 (transports disconnected)

  @S07 @pending
  Scenario: A reset link works only once
    # Value: a link left in an inbox or browser history can't be replayed after the owner has used it.
    Given I have set a new password using a reset link
    When anyone opens the same link
    Then they are sent away with "Reset password link is invalid or it has expired."
    # accounts.ex:1320-1324; user_reset_password_controller.ex:48-58
    # user_reset_password_controller_test.exs:67-73 (refusal); accounts_test.exs:1946-1953 (token deleted)

  @S08 @pending
  Scenario: A reset link expires after one day
    # Value: an old reset email found later in a mailbox can't be used to take over the account.
    Given a reset link for "amara@example.org" was sent more than one day ago
    When I open the link
    Then I am sent away with "Reset password link is invalid or it has expired."
    And submitting a new password to that link is refused the same way
    # user_token.ex:31, :168-191; user_reset_password_controller.ex:6, :48-58
    # accounts_test.exs:1900-1906

  @S09 @pending
  Scenario: A reset link stops working once the account's email changes
    # Value: a link sent to an address the owner has moved away from can't be used to take the account back.
    Given a reset link was sent to "amara@old.example.org"
    And the account's email has since changed to "amara@new.example.org"
    When I open the link
    Then I am sent away with "Reset password link is invalid or it has expired."
    # user_token.ex:176-178 (token.sent_to == user.email); user_reset_password_controller.ex:48-58

  @S10 @pending
  Scenario Outline: A malformed or unknown link is refused
    # Value: guessing or tampering with links gets no form and no password change.
    Given I am signed out
    When I <method> "/users/reset_password/<token>"
    Then I am sent away with "Reset password link is invalid or it has expired."
    And no password is changed
    # user_reset_password_controller.ex:6, :48-58; accounts.ex:1296-1304; user_token.ex:168-188
    # user_reset_password_controller_test.exs:67-73, :122-128; accounts_test.exs:1896-1898

    Examples:
      | method | token                                        |
      | open   | oops                                         |
      | submit | oops                                         |
      | open   | a well-formed token that was never issued    |

  @S11 @pending
  Scenario: An invitee's link opens the set-password form
    # Value: someone invited to a project without an account can choose their own password.
    Given the flow "flow-invite-new-collaborator" has emailed "new.person@example.org" an invitation link
    When they open the link in a signed-out browser
    Then they see "Reset password" with fields "New password" and "Confirm new password"
    # projects.ex:2102-2119 (same reset_password context); user_reset_password_controller.ex:28-32
    # the rest of the journey is flow-invite-new-collaborator S01

  @S12 @pending
  Scenario: The new password must meet the account password rules
    # Value: a reset can't leave an account with a password the instance would refuse anywhere else.
    Given I have opened a valid reset link
    When I enter "too short" in "New password" and "does not match" in "Confirm new password" and click "Reset password"
    Then I stay on "Reset password"
    And I see "Your passwords do not match."
    And the password is not changed
    And the link still works
    # user.ex:258-267, :357-362; errors.po:27-30, :43-44; user_reset_password_controller.ex:43-44
    # user_reset_password_controller_test.exs:107-120; accounts_test.exs:1914-1934

  @S13 @pending
  Scenario: The reset link can't be rebuilt from the database
    # Value: someone who can read the database (a backup, a support query) can't use it to reset another person's password.
    Given reset instructions were sent to "amara@example.org"
    Then the stored reset token is a SHA-256 hash, not the token in the emailed link
    # user_token.ex:26-27, :142-153, :170-171; accounts_test.exs:1862-1876

  @S14 @pending @variant:first-setup-open
  Scenario: An instance with no superuser sends this page to first setup
    # Value: covered by shared-authenticated-session S11; listed so this view's routes are tagged.
    Given no superuser exists
    When I visit "/users/reset_password"
    Then I am redirected to "/first_setup"
    # plugs/first_setup.ex:11-33; router.ex:29; shared-authenticated-session S11
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The response to "Send instructions" is slower for registered emails: they insert a token and send the email synchronously (an SMTP or HTTP round trip) before redirecting; unknown emails return at once. This undoes S02's identical message as a timing oracle | `user_reset_password_controller.ex:13-18`; `accounts.ex:1273-1281`; `user_notifier.ex:49-60` | nothing visible; a script can tell registered emails apart by response time | fix (verify first) |
| A mailer error is discarded and the user is told instructions are on their way; an adapter that raises gives a 500 only for registered emails, another enumeration signal | `accounts.ex:1278-1281`; `user_reset_password_controller.ex:13-25` | "you will receive instructions" when nothing was sent, or a server error page for real accounts only | fix |
| After a failed set-password attempt the form is rebuilt from the changeset, whose params carry the submitted password; as with auth-login 6.1 row 1 the password input writes `value={Form.normalize_value(@type, @value)}`, so the submitted password is likely echoed into the HTML | `user_reset_password_controller.ex:43-44`; `edit.html.heex:30-47`; `new_inputs.ex:431-446`, `:651-672` | pre-filled password fields and the plain password in the response body. Read, not run | fix (verify first) |
| The "New password" and "Confirm new password" labels use `for={:password}` and `for={:password_confirmation}`, but the inputs' ids are `user_password` and `user_password_confirmation` | `edit.html.heex:29`, `:39-41`; `new_inputs.ex:1170-1180` | clicking a label does not focus its field; screen readers announce the fields unlabelled | fix |
| A POST with no `user` param or with a non-string email (`user[email][]=x`), or a PUT with a valid token but no `user` param, has no matching clause | `user_reset_password_controller.ex:12`, `:36`; `accounts.ex:318` | a 400 or 500 instead of the form. Not reachable from the rendered forms | fix |
| The "at most" error has a typo in its msgid (`%{count}s`), so a too-long password shows the untranslated "should be at most 72 character(s)" while a short one shows "Password minimum length is 12 characters." | `errors.po:27-34`; `accounts_test.exs:1927-1934` | inconsistent error copy for the two length limits | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| After requesting instructions, and after a refused link, the redirect is to /projects, which a signed-out browser bounces to /users/log_in, storing /projects as the return path; the flash survives both redirects | `user_reset_password_controller.ex:25`, `:56`; `user_auth.ex:287-299` | decide |
| A signed-in browser can't reach any of these routes, even to set a password from a link meant for a different account; it goes to /projects with no message | `router.ex:175-176`; `user_auth.ex:271-279` | decide |
| Every request adds another valid token; all outstanding links stay valid until one is used or they age out | `accounts.ex:1273-1276`; `user_token.ex:168-191` | decide |
| Disabled and scheduled-for-deletion accounts get the email and can set a password; the account stays disabled and login is still refused. A test asserts the email reaches a disabled account | `accounts.ex:318-320`, `:1296-1304`; `user_notifier_test.exs:573-585`; `user_notifier.ex:62-68` | preserve |
| A reset does not touch the second factor, so an MFA account still needs its authenticator or a backup code to sign in | `accounts.ex:1318-1334` | preserve |
| A reset does not confirm the email address, though following the link proves ownership (variant `require-email-verification`; owned by flow-invite-new-collaborator 6.1 row 1) | `user.ex:357-362`; `accounts.ex:1318-1334` | decide |
| `password_confirmation` is enforced only when the param is present; a PUT without it succeeds. The form marks it `required` | `user.ex:360`; `edit.html.heex:42-47`; `accounts_test.exs:1936-1944` | decide |
| The expiry is set in two places: the email copy reads `Config.reset_password_token_validity_in_days/0`, enforcement reads `@reset_password_validity_in_days` in `UserToken`; both are 1 | `config.ex:161-163`; `user_notifier.ex:261`; `user_token.ex:31` | decide |
| The token is matched by an equality lookup on its hash in SQL, not a constant-time compare in Elixir; the hash makes timing on the comparison useless | `user_token.ex:168-188` | preserve |
| Opening the link (GET) does not consume it, so link scanners and previews don't burn it | `user_reset_password_controller.ex:28-32`; `accounts_test.exs:1891-1894` | preserve |
| With no mail provider configured the base config's Local adapter keeps the email in memory; the user is still told instructions are on their way (also auth-login 6.2) | `config/config.exs:83`; `bootstrap.ex:398-400` | decide |
| "Register" link on both pages when signup is allowed | `new.html.heex:51-56`; `edit.html.heex:65-70` | decide |
| Flash on error is a `div role="alert"`, on info a `p role="alert"`, rendered by the template, not the layout | `new.html.heex:18-27`; `edit.html.heex:17-26` | preserve |
| Page title is the root layout fallback since no `page_title` is assigned | `user_reset_password_controller.ex:8-10`, `:28-32` | decide |
| The email greets by first name and says the link is "only valid for 1 day"; the invitation email says nothing about expiry (flow-invite-new-collaborator 6.1) | `user_notifier.ex:251-265` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Flash blocks on both templates | `new.html.heex:18-27`; `edit.html.heex:17-26` | no code path redirects to /users/reset_password or /users/reset_password/:token with a flash; both actions here redirect away |
| The 8-byte minimum in `maybe_hash_password/2` | `user.ex:275` | runs only on a valid changeset, which already passed the 12-character minimum (`user.ex:261`) |
| The empty `grid-cols-6` block under each form | `new.html.heex:64-66`; `edit.html.heex:78-80` | renders an empty `col-span-3` div |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Reset link valid for one day | `user_token.ex:31` | yes, in the email | preserve (S08) |
| Password length 12 to 72 characters | `user.ex:261` | yes, error copy | preserve (S12) |
| Bcrypt hashing on a successful set-password submit | `user.ex:276` | no | preserve |
| Reset tokens are never removed except by a successful reset of the same account; expired rows accumulate | `user_token.ex:168-191`; `accounts.ex:1320-1324` | no | decide |

### 6.5 Things seen but not understood

- No rate limiting, throttling, CAPTCHA or per-address cap on "Send instructions", on opening links, or on set-password submits. Anyone can make the instance send unlimited reset emails to any registered address (mail bombing, and mail reputation for the instance's sender), and grow `user_tokens` without bound. The token is 256 bits, so guessing links is not practical. Hammer is used elsewhere (`token_exchange_controller.ex`), not here. A finding, not a behaviour to keep. Disposition: decide.
- No audit event or log line records that a reset was requested or completed (`user_reset_password_controller.ex:12-46`; `accounts.ex:1318-1334`), though completing one revokes every session and API token. Disposition: decide.
- flow-account-revocation-teardown lists `Accounts.reset_user_password/2` in `not_reachable_here` and defers it to this view (its 6.5). The reset revokes all contexts like the user's own password change, but is entered from an email link rather than a signed-in page. Whether it should become an entry of that flow, or stay a handoff from here, is for the flow owner. Disposition: decide.
- On instances with an SSO provider, a person who normally signs in through it can still use this page to set a local password and then sign in with email and password, bypassing the provider. Nothing here reads AuthProviders. Whether password login should coexist with SSO was not checked further. Disposition: decide.
- The password reveal eye is a `phx-click` JS command on a controller-rendered page (`new_inputs.ex:685-695`); whether it works without a LiveView container was not confirmed (same as auth-login 6.5). Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should reset requests be rate limited per address and per client, and should the request respond in constant time so registered emails can't be told apart (6.1, 6.5)? (owner: security)
- Should a requested or completed reset be audited (6.5)? (owner: security)
- Should a reset from the email link be an entry of flow-account-revocation-teardown, given it revokes the same way (6.5)? (owner: catalogue lead)
- Should a new request invalidate earlier reset links (6.2)? (owner: security)
- Should disabled and scheduled-for-deletion accounts be able to reset (6.2)? (owner: product)
- Should accounts on SSO instances be able to set a local password here (6.5)? (owner: security)
- Should requests and refused links land on /users/log_in directly instead of bouncing through /projects (6.2)? (owner: product)
- Should "Send instructions" be offered at all when no mail provider is configured (6.2)? (owner: product)

## Proposed flows

- `flow-forgot-password`: self-service password reset through email. A signed-out user requests instructions on `/users/reset_password` (this view, S01), receives "Finish resetting your password" with a one-day link (`user_notifier.ex:251-265`), opens it to `/users/reset_password/:token` (this view, S04), sets a new password, lands on `/users/log_in` with "Password reset successfully." and signs in with the new password (MFA accounts still go to two-factor). Also covers requesting twice and using the older link, and a lapsed invitation recovered this way (flow-invite-new-collaborator S03 overlaps). Surfaces: auth-reset-password, email:password-reset, auth-reset-password, auth-login, auth-two-factor (MFA accounts), projects-dashboard. This file asserts only the start (S01) and the hop it owns (S04, S05).
- Referenced, not proposed: flow-invite-new-collaborator (S11, the invitee's set-password hop), flow-account-revocation-teardown (S06, the revocation a reset triggers).

## Proposed shared

none. Referenced: shared-authenticated-session (the :browser pipeline and its S11 first-setup gate, S14).

## Lead resolution (batch 8)

- `flow-forgot-password` created. auth-reset-password added to flow-account-revocation-teardown surfaces; whether a reset should be a full entry stays an open question there.
- flow-invite-new-collaborator used the id `auth-log-in`; renamed to `auth-login` everywhere by the lead. The open question this file raised about it is resolved and removed.
