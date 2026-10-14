---
id: auth-confirm-access
type: view
title: Confirm access (re-authenticate)
status: not-started
owner:

trigger:
  old_route: /auth/confirm_access
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the browser holds a session for an active, non-TOTP-pending account; the route sits in the `[:browser, :require_authenticated_user]` scope (`router.ex:189-190`, `:242-244`) and the `:auth` live_session mounts `LightningWeb.InitAssigns` (`router.ex:242`; `init_assigns.ex:17-35`)
    - the session holds `user_return_to`; `mount/3` matches only that session shape (`re_authenticate_live/new.ex:9`; 6.1 row 1). In practice it is set by `UserAuth.require_sudo_user/2` when a sudo-gated GET is refused (`user_auth.ex:397-410`, `:490-512`), or by any earlier signed-out GET (`user_auth.ex:490-492`)
    - the only links into this page are the two sudo gates' redirects (`user_auth.ex:407`, `:455`); no UI links to it

inherits:
  - shared-authenticated-session     # applies: S01 (login redirect), S02 (disabled account), S03 (TOTP pending), S04 and S05 (lockout, via InitAssigns `locked_out?` at init_assigns.ex:26-30), S11 (first setup, :browser pipeline). Does not apply: S06 (deadline warning lives in LayoutComponents.header, layout_components.ex:259-275, not rendered here), S07 (no sidebar in the :app layout, layouts/app.html.heex:1-5), S08 and S09 (no `:banner` slot rendered), S10 (GDPR banner is in layouts/live.html.heex:102-104, not the :app layout)

url_params: []                       # inbound state arrives in the session (`user_return_to`), not the URL; the page writes `sudo_token` onto the outbound URL (new.ex:40, :71-78)

config_variants:
  default: {}                        # read under this one; no app config changes this page. MFA is per-user state, not config (new.html.heex:99)

inventory:
  routes:
    - live /auth/confirm_access  ReAuthenticateLive.New :new       # router.ex:242-244, live_session :auth
  events:
    - ReAuthenticateLive.New#toggle-option                         # new.ex:29-32
    - ReAuthenticateLive.New#reauthenticate-user                   # new.ex:34-46
  js_hooks: []
  policies:
    - Lightning.Accounts.User.valid_password?/2                    # user.ex:394-405
    - Lightning.Accounts.valid_user_totp?/2                        # accounts.ex:463-467; UserTOTP.validate_totp/3 user_totp.ex:45-65
    - Lightning.Accounts.generate_sudo_session_token/1             # accounts.ex:1021-1025
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - UserAuth.reauth_sudo_mode/2, require_sudo_user/2, on_mount(:ensure_sudo) (user_auth.ex:211-231, :397-410, :443-475); the gates that send users here and consume the token; owned by flow-reauth-backup-codes
    - Accounts.sudo_session_token_valid?/2 (accounts.ex:1030-1035); consumer of the token this page mints; owned by flow-reauth-backup-codes
    - Accounts.valid_user_backup_code?/2 (accounts.ex:472-483); recovery codes are not accepted here (6.2)
    - InitAssigns#toggle_sidebar hook (init_assigns.ex:56); attached on mount but no control renders it in the :app layout

related:
  - lib/lightning_web/live/re_authenticate_live/new.ex
  - lib/lightning_web/live/re_authenticate_live/new.html.heex
  - lib/lightning_web/components/layout_components.ex     # user_avatar/1 :21-46
  - lib/lightning_web/components/layouts/app.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning/accounts.ex
  - lib/lightning/accounts/user_totp.ex
  - test/lightning_web/live/reauthenticate_live_test.exs
  - test/lightning_web/controllers/user_auth_test.exs       # :779-795, :870-895 (redirects into this page)
  - profile-backup-codes
  - profile-mfa
flows:
  - flow-reauth-backup-codes          # the only journey through this page; owns the end-to-end scenarios
  - flow-login-return-to              # shares the `user_return_to` session key (6.1 row 2)
---

## 1. Purpose

Signed-in users land here when they ask for something sensitive (today, only their MFA recovery
codes) and haven't proved who they are in the last few minutes. They confirm with their password
or, if enrolled, an authenticator code, and are sent back to what they asked for. Without it, anyone
at an unattended signed-in browser could read codes that bypass the account's second factor.

## 2. What it does

- Signed-in users see who they are signed in as before confirming
- Users confirm with their password
- Users with MFA enabled switch to an authenticator code, and back
- A wrong password or code is refused with an error and nothing is unlocked
- A correct password or code sends the user back to the page they asked for, unlocked for five minutes

## 3. Who can do what

Sources: `re_authenticate_live/new.ex:9-59`; `new.html.heex:99-120`; `router.ex:189-190`, `:242-244`.
No policy module: every action is on the session's own user.

| Action | Signed-in user without MFA | Signed-in user with MFA | Superuser / support | Signed out |
|--------|----------------------------|-------------------------|---------------------|------------|
| See the page | yes | yes | yes, as their own account | no (shared-authenticated-session S01) |
| Confirm with password | yes | yes | yes, own password | no |
| See "Use your authenticator app instead" | no | yes | if enrolled | no |
| Confirm with authenticator code | no (option hidden; a crafted event fails, `user_totp.ex:58-60`) | yes | if enrolled | no |
| Confirm with a recovery code | no | no | no | no |

**Preconditions beyond role**
- Self only: the event verifies `socket.assigns.current_user` and mints the token for that user (`new.ex:35-39`).
- Session must hold `user_return_to` or the mount crashes (`new.ex:9`; 6.1 row 1).
- An authenticator code already used in the current time step is refused (`user_totp.ex:45-65`, `since: last_totp_at`).

## 4. What it touches

**Reads**: session `user_return_to` (`new.ex:9`); `users`, `user_tokens`, `users.preferences` via InitAssigns (`init_assigns.ex:17-45`); on submit, `users.hashed_password` (`user.ex:394-399`) or `user_totps` (`accounts.ex:463-467`)

**Writes**
- On success: `user_tokens` insert, context `sudo_session` (`new.ex:39`; `accounts.ex:1021-1025`)
- On success with a code: `user_totps.last_totp_at` (`user_totp.ex:45-56`)
- On failure: nothing persisted; `error_message` assign only (`new.ex:44`)

**Immediate side effects**
- `push_navigate(replace: true)` to `user_return_to` with `sudo_token=<Base64 token>` merged into its query (`new.ex:40-42`, `:71-78`); crossing into the `:sudo_auth` live_session (or the print controller) causes a full page load where the sudo plugs read the token (`router.ex:252-264`); owned by flow-reauth-backup-codes
- No audit event, email, PubSub broadcast or Oban job (`new.ex:34-46`)

**Deferred side effects**
- `user_return_to` is not cleared on success (`new.ex:34-46`); see 6.1 row 2 and flow-login-return-to

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- The unlocked window lasts five minutes from confirmation (`user_token.ex:35`, `:119-127`); enforced downstream, owned by flow-reauth-backup-codes

## 5. Scenarios

```gherkin
Feature: Confirm access
  In order to reach a sensitive page safely
  As a signed-in user
  I want to prove it is me with my password or authenticator before I am let through

  @S01 @pending
  Scenario: The page shows who is signed in and asks for the password by default
    # Value: the person at the keyboard can see whose account they are confirming before typing a password.
    Given I am signed in as "Amara Diallo"
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    Then I see "Confirm access"
    And I see "Signed in as:" followed by "Amara Diallo" and the avatar "AD"
    And I see "Password" and a password field
    And I see "Enter your password to confirm access"
    And I see a "Confirm" button
    And I do not see "Authentication Code"
    # new.ex:9-16, :48-51; new.html.heex:10-27, :33-39, :55-62, :76-89; layout_components.ex:21-46
    # reauthenticate_live_test.exs:14-26

  @S02 @pending
  Scenario: Correct password sends me back to the page I asked for
    # Value: a user who proves who they are reaches the sensitive page without starting over.
    Given I am signed in
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    When I enter my password and click "Confirm"
    Then a sudo session is recorded for me
    And I am taken to "/profile/auth/backup_codes" with a "sudo_token" query parameter, replacing "Confirm access" in history
    And the flow "flow-reauth-backup-codes" continues on that page
    # new.ex:34-42, :57-59, :71-78; accounts.ex:1021-1025; user.ex:394-400
    # reauthenticate_live_test.exs:74-104 (token row exists; redirect to return path with Base64 token)

  @S03 @pending
  Scenario: Wrong password is refused and unlocks nothing
    # Value: someone at an unattended signed-in browser cannot get through without the account password.
    Given I am signed in
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    When I enter a wrong password and click "Confirm"
    Then I see "Invalid password! Try again."
    And I am still on "Confirm access"
    And no sudo session is recorded for me
    # new.ex:38-46, :57-63; new.html.heex:40-44
    # reauthenticate_live_test.exs:106-124 computes a match without asserting it, against different copy; effectively untested

  @S04 @pending
  Scenario: Users with MFA can switch to their authenticator code and back
    # Value: a user who signs in through an external provider, or doesn't have their password to hand, still has a way to confirm.
    Given I am signed in with MFA enabled
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    When I click "Use your authenticator app instead"
    Then I see "Authentication Code" and a code field
    And I see "Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code."
    And I see a "Verify" button
    And I see "Use your password instead"
    When I click "Use your password instead"
    Then I see "Password" and "Enter your password to confirm access"
    And I see "Use your authenticator app instead"
    # new.ex:29-32; new.html.heex:33-39, :64-72, :76-89, :99-120
    # reauthenticate_live_test.exs:40-72

  @S05 @pending
  Scenario: Users without MFA are not offered the authenticator option
    # Value: users are only offered a method they can actually complete.
    Given I am signed in without MFA
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    Then I do not see "Use your authenticator app instead"
    # new.html.heex:99
    # reauthenticate_live_test.exs:28-38

  @S06 @pending
  Scenario: Correct authenticator code sends me back to the page I asked for
    # Value: an MFA user can confirm with the device they already trust instead of a password.
    Given I am signed in with MFA enabled
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    And I have switched to "Authentication Code"
    When I enter the current code from my authenticator app and click "Verify"
    Then a sudo session is recorded for me
    And I am taken to "/profile/auth/backup_codes" with a "sudo_token" query parameter
    And the flow "flow-reauth-backup-codes" continues on that page
    # new.ex:34-42, :53-55; accounts.ex:463-467; user_totp.ex:45-65
    # reauthenticate_live_test.exs:126-158

  @S07 @pending
  Scenario: Wrong or reused authenticator code is refused and unlocks nothing
    # Value: a guessed, stale or replayed code cannot stand in for the user's own device.
    Given I am signed in with MFA enabled
    And I was sent to "Confirm access" from "/profile/auth/backup_codes"
    And I have switched to "Authentication Code"
    When I enter "000000", which is not a valid code, and click "Verify"
    Then I see "Invalid OTP code! Try again."
    And no sudo session is recorded for me
    When I enter a code I already used to sign in during the current time step and click "Verify"
    Then I see "Invalid OTP code! Try again."
    # new.ex:38-46, :53-55, :65-67; user_totp.ex:45-65 (since: last_totp_at)
    # reauthenticate_live_test.exs:160-178 computes a match without asserting it; effectively untested
    # replay refusal: user_totp_test.exs covers validate_totp, not this page
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `mount/3` matches only a session holding `user_return_to`. Opening `/auth/confirm_access` directly, or being redirected by `:ensure_sudo` (which stores no return path) when nothing earlier set the key, raises `FunctionClauseError`. Tests always seed the key | `new.ex:9`; `user_auth.ex:443-458`; `reauthenticate_live_test.exs:10-12` | an error page instead of "Confirm access" | fix |
| `user_return_to` is never deleted after a successful confirmation, and survives logout, so the next login on that browser redirects to the stale sensitive path (shared with flow-reauth-backup-codes 6.1 row 3 and flow-login-return-to 6.2) | `new.ex:34-46`; `user_auth.ex:96-103`, `:128` | after the next sign-in, possibly by someone else, "Confirm access" instead of `/projects` | fix |
| The gates set the flash "You must verify yourself again in order to access this page.", but the `:app` layout and this template render no flash | `user_auth.ex:401-404`, `:450-454`; `new.ex:16`; `layouts/app.html.heex:1-5` | no explanation of why they were sent here | fix |
| `toggle-option` uses `String.to_existing_atom` on client input; an unknown value raises `ArgumentError` and any other existing atom shows the code form even to non-MFA users | `new.ex:29-32`; `new.html.heex:34`, `:55` | a crashed LiveView (reconnects); reachable only by crafting the event | fix |
| `reauthenticate-user` with neither `password` nor `code` in `user` params has no matching `valid_user_input?/2` or `error_msg/1` clause and raises | `new.ex:53-67` | a crashed LiveView; reachable only by crafting the event | fix |
| Both tests for the wrong-input errors compute `=~` without `assert` and expect copy ("Invalid password!. Try again") that the page never renders | `reauthenticate_live_test.exs:118-123`, `:172-177`; `new.ex:61-67` | nothing; the refusal path is untested | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| No limit, delay or lockout on failed attempts, and no audit event for success or failure: a hijacked session can guess the password or code here without bound and nobody is told | `new.ex:34-46` | decide |
| The token is returned in the URL query string, so it stays in the address bar and history | `new.ex:40-42`, `:71-78` | decide |
| Recovery codes are not accepted here, unlike the login two-factor page | `new.ex:12`, `:53-59`; compare `user_totp_controller.ex` | decide |
| Password is the default method even for MFA users; the `authentication_options` assign is set and never read | `new.ex:12-13` | preserve |
| Lives in its own `:auth` live_session so navigating back to a `:sudo_auth` page forces a full page load through the sudo plugs | `router.ex:242-244`, `:252-263` | preserve |
| Renders in the bare `:app` layout: no header, sidebar, banners or flash | `new.ex:16`; `layouts/app.html.heex:1-5` | decide |
| The logo is a link to `#`, the form has `action="#"`, and the page has two `h1` elements | `new.html.heex:3-9`, `:10-12`, `:33`, `:45-52` | decide |
| Copy uses title case and "!" ("Authentication Code", "Invalid password! Try again.", "Invalid OTP code! Try again.") and mixes "authentication code" with "OTP code"; the button reads "Confirm" for passwords and "Verify" for codes | `new.ex:61-67`; `new.html.heex:33-39`, `:76-82` | decide |
| "Having problems?" box renders with an empty list for users without MFA | `new.html.heex:94-123`, `:99` | decide |
| `valid_password?` runs `Bcrypt.no_user_verify()` for an empty password so timing does not reveal it; the field is also `required` client-side | `user.ex:402-405`; `new.html.heex:58` | preserve |
| A correct code advances `last_totp_at`, so the same code cannot then be used to sign in elsewhere in that time step | `user_totp.ex:45-56` | preserve |
| `handle_params` only sets the page title "Confirm access" | `new.ex:19-27`, `:48-51` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `append_token(nil, _)` returning `"/"` | `new.ex:69` | `mount/3` requires `user_return_to` and every writer stores a string (`user_auth.ex:490-492`) |
| `authentication_options` assign | `new.ex:12` | never read by the template or handlers |
| InitAssigns sidebar toggle hook | `init_assigns.ex:56` | the `:app` layout renders no sidebar control |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every success inserts a `sudo_session` row; expired rows are never purged here (only on logout or password change) | `accounts.ex:1021-1025`, `:1040-1044` | no | decide |

### 6.5 Things seen but not understood

- Whether users created through an external provider have a usable password. If not, and they have no MFA, they cannot pass this page at all (`user.ex:394-405`; `new.html.heex:99`). Not traced. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should failed confirmations be rate limited and audited (6.2)? (owner: security)
- Should the token stay out of the URL, for example by writing it to the session server-side before redirecting (6.2)? (owner: security)
- Should `user_return_to` be cleared once used here (6.1 row 2)? (owner: security)
- Should a recovery code be accepted on this page (6.2)? (owner: product)
- What should this page do when opened with no return path: render and send the user to their profile, or redirect (6.1 row 1)? (owner: product)
- Should the page explain why the user was sent here, via the gates' flash or its own copy (6.1 row 3)? (owner: product)

## Proposed flows

- none. Referenced: `flow-reauth-backup-codes` (surfaces: profile-mfa, controller:reauth-sudo-mode, controller:require-sudo-user, auth-confirm-access, profile-backup-codes, controller:backup-codes-print; this page asserts only the outbound handoff in S02 and S06), `flow-login-return-to` (shares the `user_return_to` session key; 6.1 row 2).

## Proposed shared

- none. Referenced: `shared-authenticated-session` (S01 to S05 and S11 apply; S06 to S10 do not, see `inherits`). The sudo gate trio guards only the backup codes routes today (`router.ex:252-265`); a `shared-sudo-mode` annotation would be warranted only if a second sudo-gated route appears.

## Lead resolution (batch 9)

- No proposals. `shared-sudo-mode` not created: one sudo-gated route so far.
