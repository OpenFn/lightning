---
id: flow-reauth-backup-codes
type: flow
title: Re-authenticate to view recovery codes
status: not-started
owner:

trigger:
  entry: profile-mfa                         # the "View" link under "Recovery codes" (mfa_component.html.heex:268-272)
  exit: profile-backup-codes                 # /profile/auth/backup_codes, or its print page in a new tab
  surfaces:
    - profile-mfa
    - controller:reauth-sudo-mode            # UserAuth.reauth_sudo_mode/2 (user_auth.ex:211-231)
    - controller:require-sudo-user           # UserAuth.require_sudo_user/2 (user_auth.ex:397-410, :496-512)
    - auth-confirm-access                    # ReAuthenticateLive.New (re_authenticate_live/new.ex)
    - profile-backup-codes                   # BackupCodesLive.Index behind on_mount :ensure_sudo (user_auth.ex:443-475)
    - controller:backup-codes-print          # BackupCodesController.print/2, opened in a new tab (backup_codes_controller.ex:5-12)
  reachable_when:
    - the user is signed in and passes shared-authenticated-session; every hop sits in the `:browser, :require_authenticated_user` scope (router.ex:189-190, :242-265)
    - the "View" link renders only when the user has MFA enabled (mfa_component.html.heex:256-273, as profile-mfa S06); the routes themselves do not check MFA (router.ex:252-265)
    - the session holds no `sudo_token` that is valid for this user and younger than five minutes (user_auth.ex:211-224; user_token.ex:35, :119-127)

inherits:
  - shared-authenticated-session    # every hop: login redirect S01, disabled account S02, two-factor pending S03, lockout S04 to S06

url_params:
  - name: sudo_token
    set_by: auth-confirm-access (also profile-mfa on first enrolment, its S03)
    effect: Base64 of a `sudo_session` token; `reauth_sudo_mode` copies it into the session and, if it belongs to the current user and is under five minutes old, opens the backup codes routes (user_auth.ex:211-231; re_authenticate_live/new.ex:39-42, :71-78)

config_variants:
  default: {}                       # read under this one; the five-minute window is a compile-time constant (user_token.ex:35)

inventory:
  routes:
    - live /auth/confirm_access  ReAuthenticateLive.New :new                         # router.ex:242-244, live_session :auth
    - live /profile/auth/backup_codes  BackupCodesLive.Index :index                  # router.ex:252-263, live_session :sudo_auth; owned by profile-backup-codes
    - get /profile/auth/backup_codes/print  BackupCodesController :print             # router.ex:264; owned by profile-backup-codes
  events:
    - ReAuthenticateLive.New#toggle-option                                           # new.ex:29-32
    - ReAuthenticateLive.New#reauthenticate-user                                     # new.ex:34-46
  js_hooks: []                                                                       # "Print Codes" is an inline onclick window.open (backup_codes_live/index.html.heex:113)
  policies:
    - LightningWeb.UserAuth.reauth_sudo_mode/2                                       # user_auth.ex:211-224
    - LightningWeb.UserAuth.require_sudo_user/2                                      # user_auth.ex:397-410
    - LightningWeb.UserAuth.on_mount(:ensure_sudo)                                   # user_auth.ex:443-475
    - Lightning.Accounts.sudo_session_token_valid?/2                                 # accounts.ex:1030-1035
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - BackupCodesLive.Index#regenerate-backup-codes and the "Copy Codes" Copy hook (backup_codes_live/index.ex:27-35; index.html.heex:134-150); owned by profile-backup-codes
    - ProfileLive.MfaComponent first-enrolment sudo token (mfa_component.ex:89-97); skips this flow, owned by profile-mfa S03 and flow-require-project-mfa
    - WebhookAuthMethodFormComponent's own `sudo_mode?` assign (webhook_auth_method_form_component.ex:32, :52); an in-component re-auth unrelated to these plugs, owned by shared-webhook-auth-method-form
    - Accounts.valid_user_backup_code?/2 (accounts.ex:470-483); recovery codes are not accepted on /auth/confirm_access

related:
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/live/re_authenticate_live/new.ex
  - lib/lightning_web/live/backup_codes_live/index.ex
  - lib/lightning_web/controllers/backup_codes_controller.ex
  - flow-login-return-to              # shares the `user_return_to` session key (6.1 row 3)
  - flow-account-revocation-teardown  # a password change deletes every sudo_session token
flows: []
---

## 1. Purpose

Recovery codes let someone sign in without their authenticator, so anyone who sees them can get
past a user's second factor. This flow makes an MFA user prove who they are again, with their
password or a fresh authenticator code, before the codes or their printable copy are shown, and
then lets them through for a few minutes without asking again. Without it, anyone sitting at an
unattended signed-in browser could copy or print the codes and keep a way into the account.

## 2. What it does

1. A user with two-factor turned on clicks "View" under "Recovery codes" on their profile, or opens the printable codes page directly.
2. If they haven't confirmed who they are in the last five minutes, they're sent to "Confirm access" and enter their password, or a code from their authenticator app. A wrong password or code keeps them there.
3. They land on their recovery codes, or on the print page if that's what they asked for; "Print Codes" opens a printable copy in a new tab.
4. For five minutes from confirming they go straight through without being asked again; after that, or for anyone else signed in with the same link, they're asked again. A password change ends the window early.

**Straightforwardness: 3 of 5.** "Confirm it's you before seeing secrets" is a familiar pattern, but the five-minute window is enforced loosely and the page can break or mislead in a few ordinary situations.

### Most surprising behaviours

- **(2)** The printed sheet shows codes that have already been used exactly like unused ones, so someone relying on paper may try a code that no longer works. (6.1)
- **(3)** The five minutes only applies when a page loads. A codes page left open keeps working afterwards, including generating new codes, for whoever sits down at it. (6.2)
- **(3)** After confirming, the codes page is remembered as a destination, so the next sign-in on that browser, possibly by someone else, lands on "Confirm access" instead of the projects list. (6.1)
- **(3)** Opening "Confirm access" directly, or having the codes page reconnect after the window expired, can show an error page instead. Even when it works, the page doesn't say why you were sent there. (6.1)
- **(3)** The approval travels in the page address, so the same user can reuse it from another browser for five minutes. Failed attempts aren't limited or recorded, and recovery codes themselves aren't accepted as proof. (6.2)

## 3. Who can do what

Sources: `user_auth.ex:211-231`, `:397-410`, `:443-475`; `accounts.ex:1030-1035`; `re_authenticate_live/new.ex:34-59`.
No policy module: every hop acts on the session's own user, and a sudo token only counts for the user it was minted for.

| Action | User with MFA (own account) | User without MFA (own account) | Superuser / support | Another signed-in user holding the URL |
|--------|-----------------------------|--------------------------------|---------------------|----------------------------------------|
| See the "View" entry point | yes | no (profile-mfa S01) | as their own MFA state | n/a |
| Re-authenticate with password | yes | yes, by typing the URL (6.2) | yes, own account | yes, own account only |
| Re-authenticate with authenticator code | yes | no, option hidden (`new.html.heex:99`) | if enrolled | if enrolled |
| Re-authenticate with a recovery code | no | no | no | no |
| View or print codes inside the window | yes | yes (6.2) | own codes only | no, the token is not theirs |

**Preconditions beyond role**
- Self only: no hop takes a user id; codes are listed for `current_user` (`backup_codes_live/index.ex:37-44`; `backup_codes_controller.ex:5-6`).
- Sudo window: a `sudo_session` token for this user inserted under five minutes ago (`user_token.ex:35`, `:119-127`; `accounts.ex:1030-1035`). Fixed from the moment of re-authentication, not extended by use.
- The window is checked by the plug on every HTTP request and by `:ensure_sudo` on every LiveView mount, not on events (`router.ex:252-262`; `user_auth.ex:443-458`; 6.2).

## 4. What it touches

**Reads**
- Hop 1, GET `/profile/auth/backup_codes` (or `/print`): `user_tokens` (session), and `user_tokens` with context `sudo_session` when the query or session carries a sudo token (`user_auth.ex:211-224`; `accounts.ex:1030-1035`)
- Hop 2, `/auth/confirm_access`: session `user_return_to` (`new.ex:9`); `users`, `user_preferences` via InitAssigns (`init_assigns.ex:17-45`); on submit, `users.hashed_password` (`user.ex:394-405`) or `user_totps` (`accounts.ex:462-467`)
- Hop 3, landing: `user_tokens` again, `user_backup_codes` (`accounts.ex:526-530`), the user's projects for the header combobox (`backup_codes_live/index.ex:9`; `hooks.ex:194-202`)
- Hop 4, print: `user_backup_codes` (`backup_codes_controller.ex:6`)

**Writes**
- Hop 1, refused: session `user_return_to` = requested path and query, minus any `sudo_token` (GET only); flash error (`user_auth.ex:397-410`, `:490-512`)
- Hop 2, success: `user_tokens` insert, context `sudo_session` (`new.ex:39`; `accounts.ex:1021-1025`); with a code, `user_totps.last_totp_at` (`user_totp.ex:45-56`)
- Hop 3: session `sudo_token` copied from the query (`user_auth.ex:226-231`)
- Logout: the session's `sudo_session` row deleted (`user_auth.ex:117-118`; `accounts.ex:1040-1044`)

**Immediate side effects**
- Hop 2 to hop 3 is a `push_navigate` across live_sessions (`:auth` to `:sudo_auth`), so the browser does a full page load and the plugs see the token (`new.ex:42`; `router.ex:242-244`, `:258-263`)
- No audit event, email, PubSub broadcast or Oban job at any hop (`new.ex:34-46`; `user_auth.ex:211-231`, `:397-410`)

**Deferred side effects**
- A password change deletes every `sudo_session` token and ends the window (`accounts.ex:919-930`); owned by flow-account-revocation-teardown
- `user_return_to` is left in the session after re-authenticating (6.1 row 3)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- The sudo window lasts five minutes from re-authentication (`user_token.ex:35`)

## 5. Scenarios

```gherkin
Feature: Re-authenticate to view recovery codes
  In order to see or print my recovery codes safely
  As a user with MFA enabled
  I want to prove it is me before they are shown, without being asked again straight away

  @S01 @pending
  Scenario: Viewing recovery codes asks for my password first, then shows them
    # Value: codes that bypass the second factor are only shown to someone who has just proved who they are.
    Given I am signed in and have enrolled in MFA
    And I have not re-authenticated in the last five minutes
    And I am on "/profile"
    When I click "View" under "Recovery codes"
    Then I am on "/auth/confirm_access"
    And I see "Confirm access" and "Signed in as:" with my name
    And I see "Password"
    When I enter my password and click "Confirm"
    Then I am on "/profile/auth/backup_codes"
    And I see "Two-factor backup codes" and each of my recovery codes
    # mfa_component.html.heex:268-272; user_auth.ex:211-224, :397-410, :490-512
    # re_authenticate_live/new.ex:9-16, :34-46, :57-59, :71-78; new.html.heex:11, :23-26
    # user_auth.ex:443-458; backup_codes_live/index.ex:37-44
    # backup_codes_live_test.exs:24-37 (redirect to /auth/confirm_access); reauthenticate_live_test.exs:74-104 (password, token appended to return path)
    # backup_codes_live_test.exs:39-49 (codes shown with a sudo token in the session); the end-to-end chain is untested

  @S02 @pending
  Scenario: I can confirm with my authenticator app instead of my password
    # Value: a user who signs in through an external provider, or doesn't have their password to hand, can still reach their codes.
    Given I am signed in and have enrolled in MFA
    And I clicked "View" under "Recovery codes" and am on "/auth/confirm_access"
    When I click "Use your authenticator app instead"
    Then I see "Authentication Code"
    And I see "Use your password instead"
    When I enter a valid code from my authenticator app and click "Verify"
    Then I am on "/profile/auth/backup_codes"
    And I see each of my recovery codes
    # new.ex:29-32, :53-55; new.html.heex:34-38, :99-120; user_totp.ex:45-65
    # reauthenticate_live_test.exs:28-72 (toggle and hidden for non-MFA), :126-158 (valid code, token appended)

  @S03 @pending
  Scenario: A wrong password does not open the codes
    # Value: someone at an unattended signed-in browser cannot read the codes without the account password.
    Given I am signed in and have enrolled in MFA
    And I am on "/auth/confirm_access" after clicking "View"
    When I enter a wrong password and click "Confirm"
    Then I see "Invalid password! Try again."
    And I am still on "/auth/confirm_access"
    And no sudo session has been created for me
    And opening "/profile/auth/backup_codes" sends me back to "/auth/confirm_access"
    # new.ex:38-46, :61-63; new.html.heex:40-44
    # reauthenticate_live_test.exs:106-124 has no assert and expects different copy ("Invalid password!. Try again"); effectively untested

  @S04 @pending
  Scenario: A wrong authenticator code does not open the codes
    # Value: a guessed or stale code cannot stand in for the user's own device.
    Given I am signed in and have enrolled in MFA
    And I am on "/auth/confirm_access" with "Authentication Code" selected
    When I enter "000000", which is not a valid code, and click "Verify"
    Then I see "Invalid OTP code! Try again."
    And no sudo session has been created for me
    # new.ex:53-55, :65-67; user_totp.ex:58-65
    # reauthenticate_live_test.exs:160-178 has no assert and expects different copy; effectively untested

  @S05 @pending
  Scenario: Within five minutes I go straight to my codes
    # Value: a user moving between their profile and their codes is not asked to prove themselves on every click.
    Given I re-authenticated two minutes ago
    And I am on "/profile"
    When I click "View" under "Recovery codes"
    Then I am on "/profile/auth/backup_codes" without passing "/auth/confirm_access"
    And I see each of my recovery codes
    # user_auth.ex:211-224, :397-399; user_token.ex:35, :119-127
    # user_auth_test.exs:725-735 (session token sets sudo mode), :816-829 (no redirect when set)

  @S06 @pending
  Scenario: After five minutes I am asked again
    # Value: an unlocked window doesn't stay open for whoever sits down at the browser later.
    Given I re-authenticated more than five minutes ago
    And I am on "/profile"
    When I click "View" under "Recovery codes"
    Then I am on "/auth/confirm_access"
    # user_token.ex:35, :119-127; accounts.ex:1030-1035; user_auth.ex:397-410
    # accounts_test.exs:2050-2065 (token older than five minutes is refused)

  @S07 @pending
  Scenario: Printing codes opens a printable copy in a new tab
    # Value: a user can keep a paper copy of their codes away from the device they might lose.
    Given I re-authenticated two minutes ago
    And I am on "/profile/auth/backup_codes"
    When I click "Print Codes"
    Then a new tab opens on "/profile/auth/backup_codes/print"
    And it shows "Backup Codes", "Account:" with my email, "You can only use each backup code once" and each of my recovery codes
    # backup_codes_live/index.html.heex:113; router.ex:264; backup_codes_controller.ex:5-12; print.html.heex:10-38
    # untested

  @S08 @pending
  Scenario: The print page is gated like the codes page
    # Value: the printable copy cannot be used to read the codes without re-authenticating.
    Given I am signed in and have enrolled in MFA
    And I have not re-authenticated in the last five minutes
    When I open "/profile/auth/backup_codes/print"
    Then I am on "/auth/confirm_access"
    When I enter my password and click "Confirm"
    Then I am on "/profile/auth/backup_codes/print"
    And I see each of my recovery codes
    # router.ex:252-264 (the controller route sits behind the same pipe_through); user_auth.ex:397-410; new.ex:40-42
    # untested

  @S09 @pending
  Scenario: Another user's sudo link does not show their codes
    # Value: a re-authenticated URL that leaks from the address bar or history cannot expose someone else's codes.
    Given "amara@example.org" re-authenticated a minute ago and her address bar shows "/profile/auth/backup_codes?sudo_token=<her token>"
    And I am signed in as a different user
    When I open that URL
    Then I am on "/auth/confirm_access"
    And I do not see any of "amara@example.org"'s recovery codes
    # user_auth.ex:211-231; accounts.ex:1030-1035
    # accounts_test.exs:2050-2055 (token refused for another user)

  @S10 @pending
  Scenario: Logging out ends the window, even for the link that carried the token
    # Value: signing out of a shared computer leaves no way back to the codes, even from browser history.
    Given I re-authenticated a minute ago and was taken to "/profile/auth/backup_codes?sudo_token=<token>"
    When I log out
    And I log in again
    And I open "/profile/auth/backup_codes?sudo_token=<token>" from my history
    Then I am on "/auth/confirm_access"
    # user_auth.ex:114-118, :226-231; accounts.ex:1040-1044
    # accounts_test.exs:2067-2072 (deletion); logout deleting the sudo token is untested
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `ReAuthenticateLive.New.mount/3` matches only a session holding `user_return_to`. Opening `/auth/confirm_access` directly, or being redirected there by `:ensure_sudo` (which stores no return path) when the codes page remounts after the window expired, with no earlier plug bounce in the session (e.g. first enrolment via profile-mfa S03 then a socket reconnect), raises `FunctionClauseError` | `re_authenticate_live/new.ex:9`; `user_auth.ex:443-458`; `reauthenticate_live_test.exs:10-12` always seeds the key | an error page instead of "Confirm access" | fix |
| The plug and the hook set the flash "You must verify yourself again in order to access this page.", but `/auth/confirm_access` renders in the `:app` layout, which has no flash, and the re-auth page does not render it either | `user_auth.ex:401-404`, `:450-454`; `new.ex:16`; `layouts/app.html.heex:1-5` | no explanation of why they were taken to "Confirm access" | fix |
| `user_return_to` is never deleted after re-authenticating, and `renew_session` carries it across logout and the next login; that login then redirects to the stale backup codes path, which bounces to "Confirm access" | `new.ex:34-46`; `user_auth.ex:63-70`, `:96-103`, `:128`; flow-login-return-to | after the next sign-in on that browser (possibly by someone else), "Confirm access" instead of `/projects` | fix |
| A `sudo_token` query param or session value that is not valid Base64 makes `Base.decode64!` raise | `user_auth.ex:217-221`, `:465` | an error page instead of "Confirm access"; reachable only by editing the URL | fix |
| The print page lists used recovery codes exactly like unused ones; the codes page strikes them through with a "Code used on" tooltip | `print.html.heex:33-38`; `backup_codes_live/index.html.heex:93-106` | a printed sheet in which spent codes look usable | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The window is checked only on HTTP requests and LiveView mounts, so an open codes page keeps working (including "Generate new backup codes") after the five minutes; a socket reconnect after expiry sends it to "Confirm access" | `user_auth.ex:443-458`; `backup_codes_live/index.ex:27-35` | decide |
| The sudo token travels Base64 in the URL query string and stays in the address bar and history; the same user can reuse it from another browser for up to five minutes | `new.ex:40-42`, `:71-78`; `user_auth.ex:226-231` | decide |
| No limit or lockout on failed re-authentication attempts, and no audit event for success or failure | `new.ex:34-46` | decide |
| A user without MFA has no "View" link but can reach the codes by URL, re-authenticate with a password, and sees "MFA Disabled" above a codes block | `router.ex:252-265`; `backup_codes_live/index.html.heex:14-52`, `:54-89` | decide |
| Recovery codes are not accepted on "Confirm access"; only password or authenticator code | `new.ex:12`, `:53-59` | decide |
| Password is the default method even for MFA users | `new.ex:13` | preserve |
| A `sudo_token` in the URL replaces whatever the session held, so opening an old link with an expired token during a valid window sends the user to "Confirm access" | `user_auth.ex:226-231` | preserve |
| `require_sudo_user` strips `sudo_token` from the stored return path; `append_token` would overwrite it anyway | `user_auth.ex:496-512`; `new.ex:71-78` | preserve |
| Re-authenticating with a code advances `last_totp_at`, so that code cannot be reused to sign in elsewhere in the same time step | `user_totp.ex:45-56`, `:63` | preserve |
| `toggle-option` converts client input with `String.to_existing_atom`; any existing atom other than `:password` shows the code form | `new.ex:29-32`; `new.html.heex:34-38`, `:55-73` | preserve |
| "Print Codes" opens a plain page through an inline `onclick` `window.open`; the page does not open the print dialog | `backup_codes_live/index.html.heex:113`; `print.html.heex:1-43` | decide |
| Backup codes are listed without an order, so the codes page and the print page may disagree | `accounts.ex:526-530` | preserve |
| Copy drifts: "Recovery codes" on the profile, "Two-factor backup codes" / "Backup Codes" on the landing and print pages, "Authentication Code" vs "OTP code" on re-auth, title-case headings and "!" in error copy | `mfa_component.html.heex:262`; `backup_codes_live/index.ex:39`; `index.html.heex:57`; `print.html.heex:11`; `new.ex:61-67`; `new.html.heex:37` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `append_token(nil, _)` returning `"/"` | `re_authenticate_live/new.ex:69` | `mount/3` requires `user_return_to` in the session and `maybe_store_return_to` always stores a string (`user_auth.ex:490-492`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Sudo window is five minutes, fixed from re-authentication | `user_token.ex:35`, `:119-127` | yes | preserve |
| Expired `sudo_session` rows are never purged; only logout and a password change delete them | `accounts.ex:1040-1044`, `:919-930` | no | decide |

### 6.5 Things seen but not understood

- Whether accounts created through an external provider have a password. If not, they can re-authenticate only with an authenticator code, which this flow offers only to MFA users (`user.ex:394-405`; `new.html.heex:99`). Not traced. Disposition: decide.
- The two wrong-input tests in `reauthenticate_live_test.exs:118-123`, `:172-177` compute `=~` without asserting, against copy that differs from the real error; whether they were meant to pass is unclear. Disposition: preserve.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the sudo window be re-checked on events, so an open codes page stops regenerating codes after five minutes (6.2)? (owner: security)
- Should the sudo token stay out of the URL, for example by writing it to the session server-side before redirecting (6.2)? (owner: security)
- Should failed re-authentication attempts be limited and audited (6.2)? (owner: security)
- Should the backup codes routes require MFA to be enabled, given the profile hides the entry point otherwise (6.2)? (owner: product)
- Should a recovery code be accepted on "Confirm access" (6.2)? (owner: product)
- Should the print page open the print dialog and mark used codes (6.1, 6.2)? (owner: product)

## Proposed flows

- none. Referenced: `flow-login-return-to` (shares `user_return_to`; 6.1 row 3 is a cross-flow leak), `flow-account-revocation-teardown` (password change ends the window), `flow-require-project-mfa` and profile-mfa S03 (first enrolment mints its own sudo token and skips this flow).

## Proposed shared

- none. Referenced: shared-authenticated-session (every hop). The `:reauth_sudo_mode` / `:require_sudo_user` / `:ensure_sudo` trio guards only the two backup codes routes today (`router.ex:252-265`); if a second sudo-gated route appears it would merit a `shared-sudo-mode` annotation.
