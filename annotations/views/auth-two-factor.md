---
id: auth-two-factor
type: view
title: Two-factor authentication
status: not-started
owner:

trigger:
  old_route: /users/two-factor
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the browser holds a session token for an active account; otherwise the visitor is sent to /users/log_in (`router.ex:189-193`; `user_auth.ex:288-299`; `accounts.ex:994-1006`)
    - the session carries the `user_totp_pending` flag, set only by the password login (`user_session_controller.ex:40-46`) or the external-provider callback (`oidc_controller.ex:250-256`) for an account with `mfa_enabled`; otherwise both GET and POST redirect to /projects (`user_totp_controller.ex:7`, `:33-41`)
    - first-setup-open only: a superuser exists; otherwise the :browser pipeline sends the request to /first_setup (`router.ex:29`; `plugs/first_setup.ex:11-33`)

inherits:
  - shared-authenticated-session     # router-plug scenarios only, this is a controller page: login redirect (its S01), disabled account (its S02), first-setup redirect (its S11). Its S03 is the gate that sends a pending session here; its S04 lockout explicitly lets this path through (S12). InitAssigns, sidebar and banner behaviour do not apply

url_params:
  - name: authentication_type
    set_by: auth-two-factor (its own "Use your backup code" / "Use your authenticator app" link)
    effect: "backup_code" shows the backup code variant; anything else, or absent, shows the authenticator variant (`user_totp_controller.ex:13`, `:43-51`)
  - name: user[remember_me]
    set_by: auth-login (password login, only when "Keep me logged in for 60 days" was ticked) and controller:oidc-callback (always "true")
    effect: copied into a hidden field and, on a valid code, writes the 60-day remember-me cookie (`user_totp_controller.ex:12`; `new.html.heex:40`; `user_auth.ex:63-79`)

config_variants:
  default: { allow_signup: false, allow_first_setup: false, require_email_verification: false, auth provider: none }   # read under this one unless a scenario is tagged
  sso-provider: { auth provider configured at /settings/authentication }        # arrival from controller:oidc-callback with remember-me forced on (oidc_controller.ex:250-256)
  require-email-verification: { lightning.require_email_verification: true }    # bootstrap.ex:387-389; this path is on the lockout allow list (confirmation_lockout.ex:31-32)
  first-setup-open: { lightning.allow_first_setup: true, no superuser }          # bootstrap.ex:234; inherited from shared-authenticated-session S11, read in code only
  # allow_signup: BlockRoutes never matches /users/two-factor (router.ex:31-42); no effect here
  # Email delivery (MAIL_PROVIDER): the page sends no email; no effect here

inventory:
  routes:
    - get /users/two-factor  UserTOTPController :new         # router.ex:192
    - post /users/two-factor  UserTOTPController :create     # router.ex:193
  events:
    - UserTOTPController#new
    - UserTOTPController#create
  js_hooks: []
  policies:
    - LightningWeb.UserAuth.require_authenticated_user/2 (user_auth.ex:288-311)
    - UserTOTPController.redirect_if_totp_is_not_pending/2 (user_totp_controller.ex:7, :33-41)
    - LightningWeb.UserAuth.totp_pending?/1, totp_validated/1 (user_auth.ex:482-488)
    - LightningWeb.ConfirmationLockout.allowed_path?/1 (confirmation_lockout.ex:31-38)
    - Lightning.Accounts.valid_user_totp?/2 (accounts.ex:462-467)
    - Lightning.Accounts.valid_user_backup_code?/2 (accounts.ex:472-502)
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :require_email_verification     # confirmation_lockout.ex; lets this path through
    - :lightning, :allow_first_setup              # plugs/first_setup.ex:12
  not_reachable_here:
    - UserAuth.mark_totp_pending/1 (user_auth.ex:478-480); called by auth-login and controller:oidc-callback, not by this view
    - Accounts.upsert_user_totp/2, delete_user_totp/1, regenerate_user_backup_codes/1 (accounts.ex:413-457, :507-520); enrolment and backup code management live in profile-mfa and profile-backup-codes
    - UserTOTP.changeset/2 (user_totp.ex:26-43); used by enrolment only
    - LightningWeb.Plugs.BlockRoutes (router.ex:31-42); never matches this path

related:
  - lib/lightning_web/controllers/user_totp_controller.ex
  - lib/lightning_web/controllers/user_totp_html.ex
  - lib/lightning_web/controllers/user_totp_html/new.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/confirmation_lockout.ex
  - lib/lightning/accounts.ex                       # valid_user_totp?/2 :462-467, valid_user_backup_code?/2 :472-502
  - lib/lightning/accounts/user_totp.ex             # validate_totp/3 :45-65 (replay guard via last_totp_at)
  - lib/lightning/accounts/user_backup_code.ex      # code format :29-35
  - test/lightning_web/controllers/user_totp_controller_test.exs
  - test/lightning_web/controllers/user_auth_test.exs              # :541-565
  - test/lightning/accounts_test.exs                               # :492-541
  - test/lightning/accounts/user_totp_test.exs                     # :100-238
  - test/lightning_web/confirmation_lockout_test.exs               # :7-21, :48-69
  - auth-login                                      # where the visitor comes from (its S05, S08)
  - profile-mfa                                     # where the authenticator is enrolled
  - profile-backup-codes                            # where backup codes are viewed and regenerated
flows:
  - flow-login-return-to                 # this view is its two-factor hop (S10)
  - flow-sso-login
  - flow-spend-backup-code
  - flow-forgot-password
---

## 1. Purpose

People who have turned on two-factor authentication land here after their password (or their
external provider) has been accepted. They enter the six-digit code from their authenticator app,
or one of their one-time backup codes if the device is lost, and only then is the session allowed
into Lightning. Without this step a leaked or guessed password would be enough to read and change
an account's projects, credentials and health data.

## 2. What it does

- **Finish signing in** (users with a pending second factor)
  - Users enter a code from their authenticator app, or switch to a backup code and back
  - Users who sign in through an external provider finish here too
  - Users then go on to the page they asked for, and "Keep me logged in for 60 days" takes effect only now
- **Refuse what shouldn't work**
  - A wrong code is refused and the session stays pending
  - A used backup code can't be used again, and an accepted authenticator code can't be replayed
  - The page gives a pending session no live connection to the app
- **Who reaches the page**
  - Signed-out visitors are sent to log in instead
  - Unconfirmed accounts past their deadline can still finish the second factor

**Straightforwardness: 3 of 5.** Entering a code is simple, but the page goes wrong in confusing ways after a mistake, and gives a stuck person nowhere to go.

### Most surprising behaviours

- **(2)** After one wrong code the page gets muddled: headings and help disappear, and the switch link says "Use your authenticator app" but leads to the backup code form, so there's no way back. (6.1)
- **(2)** Nothing limits wrong codes, so someone who has the password can keep guessing six-digit codes, and nothing records the attempts. (6.5)
- **(3)** There's no log out or cancel, and nothing tells someone who has lost both their phone and their backup codes what to do; they can only close the browser. (6.2, 6.5)
- **(3)** On a phone the backup code box opens a number pad although backup codes include letters, and a code typed in lowercase or with spaces is refused. (6.1, 6.2)
- **(4)** If two-factor is turned off in another browser while this one is waiting, authenticator codes seem to always fail here and only a backup code gets the person in. (6.5)

## 3. Who can do what

Sources: `router.ex:189-193`; `user_auth.ex:288-323`, `:378-392`, `:482-488`;
`user_totp_controller.ex:7`, `:17-41`; `confirmation_lockout.ex:31-38`; `accounts.ex:994-1006`.
Project roles, superuser and support access have no bearing on this page.

| Action | Signed out | Disabled / scheduled for deletion | Second factor pending | Pending and locked out (require-email-verification) | Fully signed in |
|--------|------------|-----------------------------------|-----------------------|-----------------------------------------------------|-----------------|
| See the page | no, sent to log in | no, sent to log in | yes | yes | no, sent to /projects |
| Submit an authenticator code | no | no | yes | yes | no, sent to /projects |
| Submit a backup code | no | no | yes | yes | no, sent to /projects |
| Receive a live socket token on this page | n/a | n/a | no | no | n/a |

**Preconditions beyond role**
- The `user_totp_pending` flag lives in the signed session cookie and is set only after the password or the external provider has been accepted (`user_session_controller.ex:40-46`; `oidc_controller.ex:250-256`); the visitor cannot set it.
- An authenticator code is checked against the account's `user_totps` row; a code from the window already used at or before `last_totp_at` is refused (`user_totp.ex:45-65`).
- A backup code must match one of the account's codes exactly and have no `used_at` (`accounts.ex:485-494`).
- The account must still pass `login_blocked?`; disabling it while the second factor is pending drops the session user and sends the visitor to log in (`accounts.ex:994-1006`; `user_auth.ex:290-299`).

## 4. What it touches

**Reads**: `user_tokens`, `users` (session lookup, `accounts.ex:994-1006`); `user_totps` (`accounts.ex:464`); `user_backup_codes` (`accounts.ex:474`, `:525-530`)

**Writes**
- `user_totps.last_totp_at` on a valid authenticator code (`user_totp.ex:45-56`)
- `user_backup_codes.used_at` on a valid backup code, written by replacing the user's backup code association (`accounts.ex:485-502`)
- Session: `user_totp_pending` deleted and `user_return_to` deleted on success (`user_auth.ex:486-488`, `:63-70`)
- Response cookie `_lightning_web_user_remember_me` (signed, 60 days, SameSite Lax) when `remember_me` is "true" (`user_auth.ex:18-21`, `:72-79`)
- Signed-out GET only: session key `user_return_to` = "/users/two-factor" (`user_auth.ex:490-492`; see 6.2)

**Immediate side effects**
- Redirect to the stored return path or /projects (`user_auth.ex:63-70`, `:514`)
- No audit event, email, broadcast or log line on success or failure (`user_totp_controller.ex:17-31`)

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `require_email_verification`: the path is on the lockout allow list (`confirmation_lockout.ex:31-32`)
- `allow_first_setup`: the FirstSetup plug runs ahead of this page (`router.ex:29`)
- sso-provider: arrivals from the provider callback always carry `remember_me=true` (`oidc_controller.ex:255`)

**Product limits**
- 10 backup codes per account, each usable once (`accounts.ex:509-513`, `:485-494`)
- Authenticator codes are 6 digits; anything else is refused (`user_totp.ex:58-64`)
- The remember-me cookie, when chosen, lasts 60 days (`user_auth.ex:18-21`)

## 5. Scenarios

```gherkin
Feature: Two-factor authentication
  In order to keep my account safe even if my password leaks
  As someone with two-factor authentication turned on
  I want to prove I hold my authenticator or a backup code before I get in

  @S01 @pending
  Scenario: A valid authenticator code completes sign-in
    # Value: an MFA account gets in with the code from its own device, and only then.
    Given "amara@example.org" has MFA enabled
    And I have entered the right password for "amara@example.org"
    And I am on "/users/two-factor"
    Then I see "Two-factor authentication"
    And I see "Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code."
    When I enter the current code from my authenticator and click "Verify"
    Then I am on "/projects"
    And visiting "/projects" no longer sends me to "/users/two-factor"
    # user_totp_controller.ex:17-24, :60-65; user_auth.ex:486-488, :63-70; accounts.ex:462-467
    # user_totp_controller_test.exs:21-30 (page copy), :78-88 (redirect to /projects, pending flag cleared)

  @S02 @pending
  Scenario: A valid backup code completes sign-in
    # Value: someone who has lost or reset their phone can still get into their account.
    Given "amara@example.org" has MFA enabled and 10 unused backup codes
    And I have entered the right password for "amara@example.org"
    And I am on "/users/two-factor"
    When I click "Use your backup code"
    Then I see "Backup Code"
    And I see "Use one of your backup codes."
    When I enter one of my unused backup codes and click "Verify"
    Then I am on "/projects"
    # user_totp_controller.ex:43-58; user_totp_html.ex:103-126; new.html.heex:61-66, :76-89; accounts.ex:472-502
    # user_totp_controller_test.exs:32-46 (backup variant copy), :123-148 (wrong then right backup code)

  @S03 @pending
  Scenario: A backup code works only once
    # Value: a backup code someone has seen, photographed or found in an old printout cannot be used a second time.
    Given "amara@example.org" has MFA enabled
    And I signed in earlier today with backup code "K7Q2M9XPA"
    And I have entered the right password again
    When I choose "Use your backup code" and enter "K7Q2M9XPA"
    Then I see "Invalid two-factor authentication code"
    And I am still on the two-factor step
    # accounts.ex:485-494 (is_nil(backup.used_at)); accounts_test.exs:530-541 (second use returns false, the others still work)

  @S04 @pending
  Scenario: An accepted authenticator code cannot be replayed
    # Value: a code read over someone's shoulder or captured in transit can't open a second session in the same window.
    Given "amara@example.org" has MFA enabled
    And I signed in a moment ago with authenticator code "482913"
    And another browser has entered the right password for "amara@example.org"
    When that browser enters "482913" before my authenticator shows a new code
    Then it sees "Invalid two-factor authentication code"
    # user_totp.ex:45-65 (since: last_totp_at); user_totp_test.exs:109-125 (last_totp_at updated), :195-205 (reuse in window refused), :207-217 (allowed after the window)

  @S05 @pending
  Scenario: A wrong code is refused and the session stays on the two-factor step
    # Value: guessing or mistyping a code never lets a password-only session into the app.
    Given "amara@example.org" has MFA enabled
    And I have entered the right password for "amara@example.org"
    When I enter "000000" and click "Verify"
    Then I see "Invalid two-factor authentication code"
    And when I visit "/projects" I am sent back to "/users/two-factor"
    # user_totp_controller.ex:25-29; user_auth.ex:302-303
    # user_totp_controller_test.exs:128-136 (error copy, pending flag kept; asserted for backup codes only)

  @S06 @pending
  Scenario Outline: Keep me logged in is honoured only after the second factor
    # Value: a 60-day cookie is never issued to a browser that has only passed the password step, but people who asked for it still get it.
    Given "amara@example.org" has MFA enabled
    And I entered the right password with "Keep me logged in for 60 days" <ticked>
    When I enter a valid <factor>
    Then a remember-me cookie <is_set>
    # user_session_controller.ex:41-46 (choice carried in the URL); user_totp_controller.ex:12, :23; new.html.heex:40; user_auth.ex:72-79
    # user_totp_controller_test.exs:48-58 (hidden field from URL), :90-105 and :150-165 (cookie set); no test asserts the unticked case here

    Examples:
      | ticked     | factor              | is_set                    |
      | ticked     | authentication code | valid for 60 days is set  |
      | ticked     | backup code         | valid for 60 days is set  |
      | not ticked | authentication code | is not set                |

  @S07 @pending
  Scenario: Switching to a backup code keeps the keep-me-logged-in choice
    # Value: someone who lost their phone still gets the session length they asked for.
    Given "amara@example.org" has MFA enabled
    And I entered the right password with "Keep me logged in for 60 days" ticked
    When I click "Use your backup code"
    And I enter an unused backup code
    Then a remember-me cookie valid for 60 days is set
    # new.html.heex:76-89 (link carries user[remember_me]); user_totp_controller.ex:12
    # no test follows the switch link

  @S08 @pending
  Scenario: A signed-out visitor is sent to log in
    # Value: codes can only be tried by a browser that has already passed the password step.
    Given I am not logged in
    When I visit "/users/two-factor"
    Then I am on "/users/log_in"
    # router.ex:189-193; user_auth.ex:290-299; user_totp_controller_test.exs:60-67

  @S09 @pending
  Scenario: The two-factor page gives a pending session no live socket token
    # Value: a session that has only passed the password step cannot join live channels as the user.
    Given "amara@example.org" has MFA enabled
    And I have entered the right password for "amara@example.org"
    When I am on "/users/two-factor"
    Then the page's user socket token is empty
    # user_auth.ex:302-303 (this path is exempt from the redirect), :378-392; root.html.heex:19-21
    # user_auth_test.exs:541-551

  @S10 @pending
  Scenario: After the second factor the visitor goes on to the page they asked for
    # Value: protecting an account with two-factor doesn't cost the person the page their link named.
    Given I opened a run link while signed out and entered my password
    And my account has MFA enabled
    When I enter a valid authentication code
    Then the flow "flow-login-return-to" continues to the run page I opened
    # user_totp_controller.ex:23; user_auth.ex:63-70
    # user_totp_controller_test.exs:107-119 (code), :167-182 (backup code); end-to-end owned by flow-login-return-to S02

  @S11 @pending
  Scenario: With nothing requested, the second factor lands on the projects list
    # Value: someone who logged in from the login page arrives at a known starting point.
    Given I opened "/users/log_in" directly and entered my password
    And my account has MFA enabled
    When I enter a valid authentication code
    Then I am on "/projects"
    # user_auth.ex:69, :514; user_totp_controller_test.exs:78-88

  @S12 @pending @variant:require-email-verification
  Scenario: An unconfirmed account past its deadline can still finish the second factor
    # Value: a locked-out MFA user can complete sign-in and reach the confirmation page instead of looping.
    Given my account was created 50 hours ago, my email is unconfirmed and MFA is enabled
    And I have entered the right password
    When I visit "/users/two-factor"
    Then I see "Two-factor authentication"
    When I enter a valid authentication code
    Then the gate in shared-authenticated-session S04 sends me to "/users/confirm-required"
    # confirmation_lockout.ex:31-32; user_auth.ex:305-306; confirmation_lockout_test.exs:7-21, :48-69
    # no test runs this page under the variant

  @S13 @pending @variant:sso-provider
  Scenario: An MFA account signing in through the external provider finishes here
    # Value: single sign-on doesn't bypass the account's second factor.
    Given an external authentication provider is configured
    And "amara@example.org" has MFA enabled
    When the flow "flow-sso-login" returns me from the provider
    Then I am on "/users/two-factor" with keep-me-logged-in set
    # oidc_controller.ex:250-256; oidc_controller_test.exs:105-124; this file asserts only the arrival
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| After a wrong code, `create/2` re-renders with `authentication_type` as the posted string, not the atom `new/2` uses. Every comparison against `:totp` / `:backup_code` then fails | `user_totp_controller.ex:25-29` vs `:13`, `:43-51`; `user_totp_html.ex:103-126`; `new.html.heex:55-66`, `:78-87` | the title always reads "Authentication Code" (even in backup code mode), both help sentences disappear, and the switch link always reads "Use your authenticator app" but always goes to the backup code form, so after a failed backup code there is no working way back to the authenticator form | fix |
| A POST with `user[authentication_type]` missing or not "totp"/"backup_code", or with no `user[code]`, matches no `valid_user_code?/2` clause; a POST with no `user` matches no `create/2` clause | `user_totp_controller.ex:17`, `:53-65` | a 500 (FunctionClauseError) or 400 instead of "Invalid two-factor authentication code". Not reachable from the rendered form | fix |
| `new/2` reads `params["user"]["remember_me"]`; a crafted `?user=x` makes `params["user"]` a string and Access raises | `user_totp_controller.ex:12` | a 500 on a hand-edited URL. Read, not run | fix |
| The code input is `inputmode="numeric"` with placeholder "XXXXXX" in both modes, but backup codes are 9 letters and digits | `new.html.heex:29-37`; `user_backup_code.ex:29-35` | on a phone the backup code form opens a number pad with no letters, and the placeholder suggests 6 characters | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A wrong code re-renders with status 200, not 401 or 422 | `user_totp_controller.ex:25-29`; `user_totp_controller_test.exs:134` | decide |
| The form is built `for={@conn}`, so after a wrong code the input is pre-filled with the code just rejected | `new.html.heex:21-31` | decide |
| Backup codes are compared exactly: lowercase or spaced entry is refused; an authenticator code with a space is refused because it is not 6 bytes | `accounts.ex:487-488`; `user_totp.ex:60-61` | decide |
| Visiting with no second factor pending (including a fully signed-in user) redirects to /projects, for GET and POST alike | `user_totp_controller.ex:7`, `:33-41`; `user_totp_controller_test.exs:69-74` | preserve |
| A signed-out GET stores "/users/two-factor" as the return path; after login it bounces once more to /projects (or to this page again for an MFA account, then /projects) | `user_auth.ex:490-492`; `user_totp_controller.ex:33-41` | preserve |
| The page has two `h1` headings ("Two-factor authentication" and "Authentication Code"/"Backup Code"); the second is title case; the logo links to "#" | `new.html.heex:3-12`; `user_totp_html.ex:105-115` | decide |
| Backup code help reads "Kindly note that a backup code can only be used once" with no closing period | `new.html.heex:65` | decide |
| No log out or cancel link; a person without their device or backup codes has no visible way off this page except closing the browser or knowing /users/log_out | `new.html.heex:1-95`; `router.ex:71` | decide |
| `remember_me` is taken from the query string, so anyone can add `user[remember_me]=true`; it only affects the visitor's own browser after a valid code | `user_totp_controller.ex:12`; `user_auth.ex:72-75` | preserve |
| The session is not renewed at the second factor; the session token was minted and the session renewed at the password step, and only the pending flag is removed here | `user_auth.ex:486-488`, `:28-31`, `:96-103` | preserve |
| Backup codes are compared with `Plug.Crypto.secure_compare/2` across all of the account's codes; a timing guard not observable through the page | `accounts.ex:485-494` | preserve |
| `last_totp_at` is shared with the re-authenticate page, so a code accepted here is also refused there within the same window | `user_totp.ex:45-56`; flow-reauth-backup-codes | preserve |
| The `title/1` component declares `authentication_type` as `:string` but is passed atoms | `user_totp_html.ex:103` | decide |
| Page title is the root layout fallback ("Lightning · OpenFn Lightning"); no `page_title` is assigned | `root.html.heex:16-18`; `user_totp_controller.ex:10-14` | decide |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Authenticator codes are valid for NimbleTOTP's default period with no extra drift window configured; a device clock a period off is refused. Deps were not installed, so the default (30 seconds) was not read | `user_totp.ex:63`; `user_totp_test.exs:127-137`, `:183-193` (a code 120 seconds old is refused) | yes, "Invalid two-factor authentication code" on a skewed clock | preserve |
| Each backup code attempt loads all of the account's codes and a success rewrites the association | `accounts.ex:473-502` | no | preserve |

### 6.5 Things seen but not understood

- No rate limiting, attempt counter, lockout or delay on wrong codes, per session, account or IP (`user_totp_controller.ex:17-31`). Someone holding the password can submit authenticator codes without limit; with one valid 6-digit code per window this is an online brute force bounded only by request rate. Stated as a finding, not behaviour to keep (see section 8).
- No audit event or log line for a successful or failed second factor (`user_totp_controller.ex:17-31`), so code guessing leaves no trace in the app.
- `InitAssigns` resolves the user from `session["user_token"]` without checking the pending flag (`init_assigns.ex:17-24`). The HTTP plug always runs first on a LiveView page, so this seems reachable only on a websocket-only mount, the gap shared-authenticated-session already records. Not confirmed.
- If MFA is turned off in another signed-in browser while this session is pending, the `user_totps` row is deleted but backup codes are kept and the pending flag stays (`accounts.ex:444-457`): authenticator codes then always fail and only a backup code finishes sign-in. Not tested.
- Nothing on the page tells a person who has lost both their device and their backup codes what to do; whether account recovery exists outside the app was not found in code.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should wrong two-factor codes be rate limited or lock the session out after a number of attempts, and should successes and failures be logged or audited (6.5)? (owner: security)
- Should the page offer "Log out" or "Use a different account", and point to a recovery route for someone without device or backup codes (6.2, 6.5)? (owner: product)
- Should backup codes be accepted case-insensitively and with spaces stripped, and authenticator codes with spaces stripped (6.2)? (owner: product)
- Should a wrong code clear the input rather than echo it back (6.2)? (owner: security)

## Proposed flows

- `flow-sso-login` (already proposed by auth-login under this id): single sign-on through the configured external provider. For an account with MFA the provider callback logs the user in, marks the second factor pending and redirects here with `user[remember_me]=true` (`oidc_controller.ex:250-256`); this view finishes sign-in. Surfaces: auth-login, controller:oidc-show, external:oidc-provider, controller:oidc-callback, auth-two-factor, projects-dashboard or the stored return path. This file asserts only the arrival (S13).
- Referenced, not proposed: flow-login-return-to (S10 asserts the handoff to its return hop; this view is its `auth-two-factor` surface).

## Proposed shared

none. Referenced: shared-authenticated-session (router-plug scenarios S01, S02 and S11 apply; its S03 sends pending sessions here; its S04 lockout gate is the handoff in S12).

## Lead resolution (batch 8)

- `flow-sso-login` created.
