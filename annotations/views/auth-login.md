---
id: auth-login
type: view
title: Log in
status: not-started
owner:

trigger:
  old_route: /users/log_in
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the visitor has no valid session and no valid remember-me cookie; otherwise both GET and POST redirect to /projects (`router.ex:176`, `:181-182`; `user_auth.ex:271-279`)
    - first-setup-open only: a superuser exists; otherwise every request is redirected to /first_setup (`router.ex:29`; `plugs/first_setup.ex:11-33`)

inherits:
  - shared-authenticated-session     # the :browser pipeline it shares (fetch_current_user writes live_socket_id, router.ex:28; user_auth.ex:175-192) and the first-setup redirect (its S11). Its S01 to S06 gates do not run here: this scope has no :require_authenticated_user
  - shared-flash-messages   # added by lead (final pass)

url_params: []                        # nothing is read from the query string; the return path lives in the session (flow-login-return-to)

config_variants:
  default: { allow_signup: false, allow_first_setup: false, require_email_verification: false, auth provider: none, MAIL_PROVIDER: unset }   # read under this one unless a scenario is tagged
  signup-allowed: { lightning.allow_signup: true }                       # ALLOW_SIGNUP, bootstrap.ex:379-381; shows "Register"
  sso-provider: { auth provider configured at /settings/authentication } # AuthProviders.get_handlers/0 non-empty (user_session_controller.ex:75-86)
  first-setup-open: { lightning.allow_first_setup: true, no superuser }   # bootstrap.ex:234; read in code only
  require-email-verification: { lightning.require_email_verification: true }   # bootstrap.ex:387-389; read in code only
  # Email delivery (MAIL_PROVIDER, bootstrap.ex:398-425) does not change this page; see 6.2.

inventory:
  routes:
    - get /users/log_in  UserSessionController :new          # router.ex:181
    - post /users/log_in  UserSessionController :create      # router.ex:182
  events:
    - UserSessionController#new
    - UserSessionController#create
  js_hooks: []                         # the password reveal eye uses an inline phx-click JS command (new_inputs.ex:685-695); see 6.5
  policies:
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279)
    - Lightning.Accounts.login_blocked?/1, login_blocked_reason/1 (accounts.ex:329-345)
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :allow_signup                 # new.html.heex:84
    - :lightning, :allow_first_setup            # plugs/first_setup.ex:12
    - :lightning, :require_email_verification   # affects the landing after login, not this page
    - Lightning.AuthProviders handlers (Cachex store, auth_providers/store.ex:14-19; warmer auth_providers/cache_warmer.ex:16-30)
  not_reachable_here:
    - UserSessionController.exchange_token/2 (user_session_controller.ex:55-67); route /users/token_exchange/:token, owned by flow-account-revocation-teardown as controller:token-exchange. Its "Invalid token" flash is rendered on this page (user_session_controller_test.exs:112-128)
    - UserSessionController.delete/2 (user_session_controller.ex:69-73); route /users/log_out, owned by flow-account-revocation-teardown as controller:user-log-out. Its "Logged out successfully." flash is rendered on this page (S16)
    - OidcController.show/2 and new/2 (oidc_controller.ex:17-73, :227-263); the SSO hop, proposed as flow-sso-login
    - LightningWeb.Plugs.BlockRoutes (router.ex:31-42); never matches /users/log_in

related:
  - lib/lightning_web/controllers/user_session_controller.ex
  - lib/lightning_web/controllers/user_session_html/new.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/controllers/oidc_controller.ex
  - lib/lightning/accounts.ex                        # get_user_by_email_and_password/2 :359-363, login_blocked?/1 :329-345, generate_user_session_token/1 :985-989
  - lib/lightning/accounts/user.ex                   # valid_password?/2 :388-405
  - lib/lightning/accounts/user_token.ex             # session validity :34
  - test/lightning_web/controllers/user_session_controller_test.exs
  - test/lightning_web/controllers/user_auth_test.exs
  - test/lightning/accounts_test.exs                 # :317-339
  - assets/test/e2e/pages/login.page.ts              # page object used by the E2E suites
  - auth-two-factor                                  # where an MFA account goes next
  - auth-reset-password                              # "Forgot your password?"
  - auth-register                                    # "Register", signup-allowed only
  - first-setup
flows:
  - flow-login-return-to                 # this view is the login hop (S01, S12)
  - flow-invite-new-collaborator         # a successful password set lands here (S14)
  - flow-account-revocation-teardown     # exit: revoked browsers land here (S15)
  - flow-sso-login
  - flow-forgot-password
  - flow-log-out
  - flow-admin-created-account-confirm
---

## 1. Purpose

Everyone with a Lightning account starts here when their browser has no session: they prove who
they are with an email and password (or through the organisation's identity provider) and get into
their projects. The page is also the gate that keeps disabled, scheduled-for-deletion and
second-factor accounts out. If it is wrong, either people who should get in can't reach their
workflows, or someone holding a guessed or stolen password reaches health data.

## 2. What it does

- **Log in**
  - Registered users log in with email and password, and can choose to stay logged in for 60 days
  - Users on instances with an external provider log in through it instead
  - Users who forgot their password reach the reset page; visitors on instances with self-signup see a link to register
- **Keep the wrong people out**
  - Wrong credentials are refused without saying whether the email exists
  - Disabled and scheduled-for-deletion accounts are refused
  - Accounts with MFA are sent on to their second factor before they get in
- **Send people to the right place**
  - Signed-in visitors are sent to their projects instead
  - A fresh install sends visitors to first setup
  - People arriving from logout, a password reset or a revoked session see why they are here

**Straightforwardness: 3 of 5.** The login itself is simple, but the security gaps around it, and what it does and doesn't tell an attacker, need explaining.

### Most surprising behaviours

- **(2)** There is no limit on failed password attempts and nothing is logged, so someone can keep guessing a password forever and nobody would know. (6.5)
- **(2)** After a failed attempt the page may send the typed password back inside the page, so it could sit in plain text in the browser or a cache. Not yet checked in a browser. (6.1)
- **(3)** The "account is disabled" and "scheduled for deletion" messages only appear once the password is right, so they quietly confirm to anyone holding a password that it works. (S04, 6.2)
- **(3)** "Forgot your password?" shows even when the instance has no way to send email, so the reset message may never arrive. (6.2)
- **(3)** A newly added external provider can take up to half an hour to show its button, so SSO users may see no way in for a while. (6.4)

## 3. Who can do what

Sources: `router.ex:176-182`; `user_auth.ex:271-279`; `user_session_controller.ex:15-53`;
`accounts.ex:329-345`, `:359-363`; `plugs/first_setup.ex:11-33`. There is no policy module; the
gates are account state, not roles.

| Action | Signed-out visitor | Signed-in user | Disabled account | Scheduled for deletion | Account with MFA |
|--------|--------------------|----------------|------------------|------------------------|------------------|
| See the page | yes | no, redirected to /projects | yes | yes | yes |
| Log in with password | yes | no, redirected to /projects | no | no | partly: session pending second factor |
| Tick "Keep me logged in" | yes | n/a | n/a | n/a | yes, cookie written only after the second factor |
| See "via external provider" | sso-provider only | n/a | sso-provider only | sso-provider only | sso-provider only |
| See "Register" | signup-allowed only | n/a | signup-allowed only | signup-allowed only | signup-allowed only |
| See "Forgot your password?" | yes | n/a | yes | yes | yes |

**Preconditions beyond role**
- The account-state check runs only after the password has matched (`user_session_controller.ex:18-20`, `:31-38`).
- Superuser role and project membership play no part here.
- first-setup-open: no one can reach the page until a superuser exists (`plugs/first_setup.ex:27-33`).
- require-email-verification: an unconfirmed account past its deadline can still log in; the gate on the next page sends it to confirm (`user_auth.ex:305-306`). Not checked here.

## 4. What it touches

**Reads**: `users` by email (citext, case-insensitive: `priv/repo/migrations/20220405135153_create_users.exs:12`; `accounts.ex:359-363`); `user_tokens` and `users` for the current session or remember-me cookie (`user_auth.ex:175-206`); auth provider handlers from the Cachex store (`user_session_controller.ex:75-86`; `auth_providers/store.ex:14-19`); `users` superuser count under first-setup-open (`plugs/first_setup.ex:28`)

**Writes**
- `user_tokens` insert, context "session", on every successful password match that is not blocked, MFA included (`user_auth.ex:28-31`; `accounts.ex:985-989`)
- Session renewed and cleared, keeping only `user_return_to`; then `user_token` set (`user_auth.ex:54-58`, `:96-103`)
- Session key `user_totp_pending` for MFA accounts (`user_auth.ex:478-480`)
- Session key `user_return_to` deleted on redirect (`user_auth.ex:68`)
- Signed cookie `_lightning_web_user_remember_me`, max age 60 days, SameSite Lax, when "remember_me" is "true" and the account has no MFA (`user_auth.ex:16-21`, `:72-79`)

**Immediate side effects**
- none: no audit event, email, broadcast or log line on success, failure or refusal

**Deferred side effects**
- none

**External, non-transactional effects**
- none on this page; the external provider is reached only after clicking "via external provider" (flow-sso-login)

**Depends on config**
- `signup-allowed`: "Register" link (`new.html.heex:83-88`)
- `sso-provider`: "or" divider and "via external provider" (`new.html.heex:56-73`)
- `first-setup-open`: redirect to /first_setup (`plugs/first_setup.ex:11-33`)

**Product limits**
- A session token is valid for 60 days and the remember-me cookie lasts 60 days (`user_token.ex:34`; `user_auth.ex:16-19`); the checkbox copy promises this ("Keep me logged in for 60 days", `new.html.heex:50`)

## 5. Scenarios

```gherkin
Feature: Log in
  In order to reach my projects
  As someone with a Lightning account
  I want to prove who I am and be let in, and nobody else to be

  @S01 @pending
  Scenario: Log in with email and password
    # Value: a registered user reaches their projects with the credentials they chose.
    Given "amara@example.org" is a registered user with password "a long password"
    And I am not logged in
    When I open "/users/log_in"
    And I fill in "Email" with "amara@example.org"
    And I fill in "Password" with "a long password"
    And I click "Log in"
    Then I am logged in as "amara@example.org"
    And the flow "flow-login-return-to" continues from here
    # user_session_controller.ex:15-20, :47-50; user_auth.ex:28-31, :54-58, :63-70, :514
    # user_session_controller_test.exs:151-164 (session token set, redirect to /projects, "User Profile" on the next page)

  @S02 @pending
  Scenario Outline: Wrong credentials are refused with one message
    # Value: an attacker trying addresses can't tell from the response which ones have accounts.
    Given "amara@example.org" is a registered user with password "a long password"
    When I log in with "<email>" and "<password>"
    Then I am on the log in page
    And I see "Invalid email or password"
    And I am not logged in

    Examples:
      | email                  | password        |
      | amara@example.org      | wrong password  |
      | nobody@example.org     | a long password |
      | amara@example.org      |                 |
    # user_session_controller.ex:18, :22-25; accounts.ex:359-363
    # user.ex:388-405: an unknown email or empty password still runs Bcrypt.no_user_verify/0, so response time does not separate the cases either
    # user_session_controller_test.exs:264-275 covers the wrong-password row only; accounts_test.exs:318-328 covers the unknown email at the context

  @S03 @pending
  Scenario: Email capitalisation does not matter
    # Value: someone who types their address with different capitals is not locked out.
    Given "amara@example.org" is a registered user with password "a long password"
    When I log in with "Amara@Example.org" and "a long password"
    Then I am logged in as "amara@example.org"
    # priv/repo/migrations/20220405135153_create_users.exs:5-12 (email is citext); accounts.ex:361
    # no test covers it

  @S04 @pending
  Scenario Outline: Blocked accounts can't log in even with the right password
    # Value: disabling an account or scheduling it for deletion stops new logins straight away.
    Given "<email>" is a registered user whose account is <state>
    When I log in with "<email>" and the right password
    Then I am on the log in page
    And I see "<message>"
    And I am not logged in

    Examples:
      | email               | state                       | message                                      |
      | ruth@example.org    | disabled                    | This user account is disabled                |
      | kofi@example.org    | scheduled for deletion      | This user account is scheduled for deletion  |
    # user_session_controller.ex:31-38; user_auth.ex:41-45; accounts.ex:329-345
    # user_session_controller_test.exs:184-214

  @S05 @pending
  Scenario: An account with MFA is sent to its second factor
    # Value: a password alone is never enough to get into an account protected by two-factor.
    Given "amara@example.org" has MFA enabled
    When I log in with "amara@example.org" and the right password
    Then I am on "/users/two-factor"
    And when I visit "/projects" I am sent back to "/users/two-factor"
    # user_session_controller.ex:40-46; user_auth.ex:302-303, :478-480
    # user_session_controller_test.exs:166-182; the second factor itself is auth-two-factor; the gate is shared-authenticated-session S03

  @S06 @pending
  Scenario: Keep me logged in for 60 days
    # Value: people on their own device are not asked to log in every time they open the browser.
    Given "amara@example.org" is a registered user without MFA
    When I log in with "amara@example.org" and the right password
    And I had ticked "Keep me logged in for 60 days"
    Then a signed remember-me cookie valid for 60 days is set
    And after the browser session ends I am still logged in
    # user_auth.ex:16-21, :72-75, :194-206; new.html.heex:47-52
    # user_session_controller_test.exs:216-228 (cookie set, redirect to /projects)

  @S07 @pending
  Scenario: Without "Keep me logged in", closing the browser ends the session
    # Value: on a shared computer, the next person to open the browser is not logged in as me.
    Given "amara@example.org" is a registered user without MFA
    When I log in without ticking "Keep me logged in for 60 days"
    Then no remember-me cookie is set
    # user_auth.ex:77-79; endpoint.ex:12-16 (session cookie has no max_age)
    # no test asserts the absence on this path

  @S08 @pending
  Scenario: "Keep me logged in" waits for the second factor
    # Value: a remember-me cookie is never issued for a session that has only passed the password step.
    Given "amara@example.org" has MFA enabled
    When I log in with the right password and "Keep me logged in for 60 days" ticked
    Then no remember-me cookie is set yet
    And I am on "/users/two-factor" with my choice carried along
    # user_session_controller.ex:41-46; user_session_controller_test.exs:230-248

  @S09 @pending
  Scenario: Logging in starts a fresh session
    # Value: a session id planted in my browser before login can't be used to ride my logged-in session.
    Given my browser holds a session with other values in it
    When I log in successfully
    Then the session id is renewed
    And nothing from the old session remains except the page I was going to
    # user_auth.ex:54-58, :96-103; user_auth_test.exs:163-189

  @S10 @pending
  Scenario: A signed-in visitor is sent to their projects
    # Value: someone already logged in isn't asked for their password again or shown a second login.
    Given I am logged in
    When I open "/users/log_in"
    Then I am on "/projects"
    # router.ex:176, :181-182; user_auth.ex:271-279, :514
    # user_session_controller_test.exs:70-75; user_auth_test.exs:461-475

  @S11 @pending
  Scenario: Forgot your password?
    # Value: a user who has forgotten their password can recover the account without an administrator.
    Given I am not logged in
    When I open "/users/log_in"
    Then I see a "Forgot your password?" link to "/users/reset_password"
    # new.html.heex:92-96; user_session_controller_test.exs:41-68 (copy only); the reset itself is auth-reset-password

  @S12 @pending
  Scenario: A deep link opened while signed out continues after login
    # Value: a link from an alert or a colleague still reaches the page it named.
    Given the flow "flow-login-return-to" brought me here from a page that needs login
    When I log in successfully
    Then the flow "flow-login-return-to" continues to the page I asked for
    # user_auth.ex:63-70, :96-103; user_session_controller_test.exs:250-262 (redirect to the stored "/foo/bar")
    # flow-login-return-to S01 to S07 own the end-to-end journey

  @S13 @pending @variant:signup-allowed
  Scenario Outline: Register link only where self-signup is allowed
    # Value: instances that create accounts centrally don't advertise a signup that would be refused.
    Given self-signup is <setting>
    When I open "/users/log_in"
    Then I <see> a "Register" link to "/users/register"

    Examples:
      | setting  | see        |
      | allowed  | see        |
      | disabled | do not see |
    # new.html.heex:83-88; router.ex:31-36 (the route itself is blocked when disabled)
    # user_session_controller_test.exs:41-68 (stubs every flag true or false, so both rows are covered)

  @S14 @pending
  Scenario: An invited collaborator who has set a password logs in here
    # Value: someone invited to a project gets in with the password they chose, without an admin.
    Given the flow "flow-invite-new-collaborator" has reset my password
    When I arrive on "/users/log_in"
    Then I see "Password reset successfully."
    And I can log in as in S01
    # new.html.heex:23-27 renders the info flash; user_reset_password_controller.ex:38-41 sets it and redirects here
    # flow-invite-new-collaborator owns the journey

  @S15 @pending
  Scenario: A revoked browser lands here and can sign in again
    # Value: after a password change or account disable elsewhere, other devices stop at the login page and only the current credentials work.
    Given the flow "flow-account-revocation-teardown" has revoked my sessions on this browser
    Then this browser is on "/users/log_in"
    When I log in with my old password
    Then I see "Invalid email or password"
    # user_auth.ex:131; user_session_controller.ex:22-25; flow-account-revocation-teardown owns the revocation
    # a disabled account then hits S04

  @S16 @pending
  Scenario: Logging out lands here with a confirmation
    # Value: on a shared computer, the person leaving can see that the logout took effect.
    Given I am logged in
    When I log out
    Then I am on "/users/log_in"
    And I see "Logged out successfully."
    # user_session_controller.ex:69-73; user_auth.ex:114-132; new.html.heex:23-27
    # user_session_controller_test.exs:278-297

  @S17 @pending @variant:sso-provider
  Scenario Outline: External provider button only when one is configured
    # Value: organisations with single sign-on send their staff through it, and other instances show no dead button.
    Given an external authentication provider is <configured>
    When I open "/users/log_in"
    Then I <see> "via external provider"

    Examples:
      | configured     | see        |
      | configured     | see        |
      | not configured | do not see |
    # user_session_controller.ex:8-13, :75-86; new.html.heex:56-73
    # user_session_controller_test.exs:41-53 (not configured), :77-83 (configured)

  @S18 @pending @variant:sso-provider
  Scenario: The external provider button starts single sign-on
    # Value: SSO users never type a Lightning password.
    Given an external authentication provider "acme" is configured
    When I click "via external provider"
    Then I am sent to "/authenticate/acme"
    And the flow "flow-sso-login" has started
    # user_session_controller.ex:80-85 (routes through OidcController.show so it mints state and nonce); new.html.heex:61

  @S19 @pending @variant:first-setup-open
  Scenario: A fresh install sends visitors to first setup
    # Value: nobody is shown a login that no account can pass before the administrator exists.
    Given first setup is allowed
    And there is no superuser
    When I open "/users/log_in"
    Then I am on "/first_setup"
    # router.ex:29; plugs/first_setup.ex:11-33; first_setup_test.exs:5-10 (asserts on "/", not on this route)
    # shared-authenticated-session S11 owns the gate

  @S20 @pending @variant:require-email-verification
  Scenario: An account past its confirmation deadline logs in and is sent to confirm
    # Value: a locked-out user is shown how to get unblocked instead of a login that seems to fail.
    Given my account was created 50 hours ago and my email is unconfirmed
    When I log in with the right password
    Then I am logged in
    And the gate in shared-authenticated-session S04 sends me to "/users/confirm-required"
    # user_session_controller.ex:31-53 does not check confirmation; user_auth.ex:305-306, :327-343
    # no test covers login under this variant
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| After a failed or refused login the form is rebuilt from the posted params (`for={@conn}`), and the password input renders `value={Form.normalize_value(@type, @value)}`. As far as I can tell phoenix_html 4.3 has no password clause in `normalize_value/2`, so the submitted password is written back into the page HTML | `new.html.heex:10-15`, `:40-45`; `new_inputs.ex:431-446`, `:651-672`; `mix.lock:101` | the password field arrives pre-filled (masked) after a failed attempt, and the plain password sits in the response body and any cached copy. Deps were not installed, so this was read, not run | fix (verify first) |
| A POST with no `user[password]` key, or with an email or password that is not a string (`user[email][]=x`), crashes instead of re-rendering; a POST with no `user` at all has no matching clause | `user_session_controller.ex:15-16`; `accounts.ex:359-360` | a 500 (MatchError or FunctionClauseError) or a 400 instead of "Invalid email or password". Not reachable from the rendered form | fix |
| "via external provider" is an `<a>` inside a `<button type="button">`; only the link inside navigates | `new.html.heex:60-72`; `new_inputs.ex:112` | clicking the button's padding outside the text does nothing; nested interactive elements are invalid HTML and announce oddly to screen readers | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Failed and refused logins re-render with status 200, not 401 or 422 | `user_session_controller.ex:22-25`, `:33-38`; `user_session_controller_test.exs:196`, `:212`, `:273` | decide |
| The disabled and scheduled-for-deletion messages are shown only after the password matched, so they confirm to anyone holding the right password that it is right and what state the account is in | `user_session_controller.ex:18-20`, `:31-38` | decide |
| "Remember me" is the checkbox's label (humanised field name); "Keep me logged in for 60 days" is a separate span under it, not part of the label | `new.html.heex:47-52`; `live/components/form.ex:301-310` | decide |
| Email is `required` on the input, password is not; an empty password submits and gets "Invalid email or password" | `new.html.heex:31-46` | preserve |
| Only the first handler in the cache is offered; the page has no provider name, only "via external provider" | `user_session_controller.ex:80-85` | decide |
| "Forgot your password?" is shown even when no mail provider is configured (MAIL_PROVIDER unset), so the reset email may never be delivered | `new.html.heex:92-96`; `bootstrap.ex:398-400` | decide |
| Page title is the root layout fallback, "Lightning · OpenFn Lightning", since no `page_title` is assigned | `root.html.heex:16-18`; `user_session_controller.ex:9-12` | decide |
| The nav bar is a logo only; no link back to a public site or docs | `layout_components.ex:315-333` | preserve |
| An MFA account's "session" token is inserted at the password step, before the second factor; the pending flag, not the token, keeps it out | `user_session_controller.ex:43-46`; `user_auth.ex:302-303`, `:381-384` | preserve |
| Flash on error is a `div role="alert"`, on info a `p role="alert"`; both are rendered by the template rather than the layout | `new.html.heex:18-27` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `error_message: nil` assign | `user_session_controller.ex:10` | the template never reads `@error_message`; `create/2` does not set it |
| The empty `grid-cols-6` block under the form | `new.html.heex:103-105` | renders an empty `col-span-3` div; no content |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every successful login inserts a `user_tokens` row; nothing here removes earlier ones, they expire by age (60 days) | `accounts.ex:985-989`; `user_token.ex:34`, `:111-116` | no | preserve |
| The SSO button reads only the in-memory handler cache, refreshed by a warmer every 30 minutes (the moduledoc says 30 seconds); a provider added on another node may not show until the warmer runs | `auth_providers/store.ex:14-19`; `auth_providers/cache_warmer.ex:2-3`, `:16-17` | yes, a missing button | decide |
| Bcrypt runs on every attempt, known email or not | `user.ex:394-405` | login takes a fraction of a second | preserve |

### 6.5 Things seen but not understood

- No rate limiting, throttling, lockout or delay on failed password attempts, per account or per IP, anywhere on this path. Hammer is in the deps and used for other endpoints (`token_exchange_controller.ex:119`), not here. Unlimited online password guessing is possible; only Bcrypt cost slows it. Stated as a finding, not a behaviour to keep (see section 8).
- No audit event or log line for successful, failed or refused logins (`user_session_controller.ex:15-53`), so a guessing attack leaves no trace in the app.
- The remember-me cookie sets `sign: true, max_age, same_site: "Lax"` but no explicit `secure:` flag (`user_auth.ex:21`). Whether production relies on HTTPS-only cookies elsewhere was not checked.
- The password reveal eye uses a `phx-click` JS command (`new_inputs.ex:685-695`) on a controller-rendered page with no LiveView container. Whether LiveView's JS commands run on a dead view here was not confirmed.
- Unconfirmed accounts under require-email-verification are not checked at login (S20 records the handoff). Whether that is intended, so the user can reach the confirmation page, or an omission, is not documented.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should password login be rate limited or locked out after repeated failures, and should failures be logged or audited (6.5)? (owner: security)
- Does the failed-login re-render really echo the submitted password into the HTML (6.1)? Verify in a browser, then fix. (owner: security)
- Should the disabled and scheduled-for-deletion messages be replaced with the generic message, given they confirm a correct password (6.2)? (owner: security)
- Should "Forgot your password?" be hidden when no mail provider is configured (6.2)? (owner: product)
- Should the external provider button name the provider, and should more than one provider ever be offered (6.2)? (owner: product)

## Proposed flows

- `flow-sso-login`: single sign-on through the configured external provider. "via external provider" links to `/authenticate/:provider` (`user_session_controller.ex:75-86`), which mints state and nonce and redirects to the provider (`oidc_controller.ex:17-29`); the provider calls back to `/authenticate/:provider/callback`, which verifies state, nonce and the id token, looks the user up by verified email, refuses unknown, disabled and scheduled-for-deletion accounts back to this page with a flash, sends MFA accounts to two-factor, and otherwise logs in with remember-me always on (`oidc_controller.ex:46-73`, `:227-263`). Surfaces: auth-login, controller:oidc-show, external:oidc-provider, controller:oidc-callback, auth-two-factor, auth-login (refusals), projects-dashboard or the stored return path. This file asserts only the start (S18).
- Referenced, not proposed: flow-login-return-to (S01, S12), flow-invite-new-collaborator (S14), flow-account-revocation-teardown (S15, exit; also S16 for the logout redirect it lists as controller:user-log-out).

## Proposed shared

none. Referenced: shared-authenticated-session (the :browser pipeline and its S11 first-setup gate in S19; its S03 and S04 gates as handoffs in S05 and S20).

## Lead resolution (batch 8)

- `flow-sso-login` created.
- flow-invite-new-collaborator used the id `auth-log-in`; renamed to `auth-login` everywhere by the lead. The open question this file raised about it is resolved and removed.
