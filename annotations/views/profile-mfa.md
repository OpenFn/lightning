---
id: profile-mfa
type: view
title: User profile › Multi-factor authentication
status: not-started
owner:

trigger:
  old_route: /profile (MFA card)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host page `/profile` renders, as catalogued in profile-account (config-injected route, `config/config.exs:58-59`; `:services` live_session `router.ex:351-355`)
    - the card is always rendered on `:edit` and `:delete`; no config, role or project gates it (`components.ex:57-61`)
    - every action applies to the signed-in user's own account only; the component is given `current_user` and takes no user id from the URL (`components.ex:57-61`, `mfa_component.ex:10-21`)

inherits:
  - shared-authenticated-session    # via the host page: login redirect S01, disabled account S02, two-factor pending S03 (a TOTP-pending session never reaches this card), lockout S04 to S06
  - shared-project-header           # via the host page, no-project parts only, as profile-account lists them; this card adds no chrome
  - shared-flash-messages   # added by lead (final pass)

url_params: []

config_variants:
  default: {}                       # everything below was read under this one
  # :lightning, :totp_client (mfa_component.ex:27) is a test seam that fixes the TOTP secret (test/support/totp_adapter.ex); not a deployment variant, see 6.3

inventory:
  routes: []                                            # /profile is owned by profile-account
  events:
    - ProfileLive.MfaComponent#show-mfa-options         # mfa_component.ex:24-47
    - ProfileLive.MfaComponent#hide-mfa-options         # mfa_component.ex:49-51
    - ProfileLive.MfaComponent#save_totp                # mfa_component.ex:53-66
    - ProfileLive.MfaComponent#disable_mfa              # mfa_component.ex:68-87
  js_hooks: []                                          # show_modal / hide_modal and focus_wrap are LiveView JS commands, not hooks (mfa_component.html.heex:60-71, :145, :194-204)
  policies: []                                          # no policy check; self-only by construction
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :totp_client                          # mfa_component.ex:27; test seam only
  not_reachable_here:
    - BackupCodesLive.Index and BackupCodesController :print (router.ex:252-265); owned by profile-backup-codes
    - ReAuthenticateLive.New (/auth/confirm_access); reached from the "View" recovery codes button, owned by its own view and the proposed flow-reauth-backup-codes
    - Accounts.valid_user_totp?/2 and valid_user_backup_code?/2 (accounts.ex:462-483); used at sign-in and re-authentication, not by this card
    - Accounts.regenerate_user_backup_codes/1 called directly (accounts.ex:509-519); reached here only inside upsert_user_totp/2 on first enrolment

related:
  - profile-account                 # host page
  - profile-backup-codes            # first enrolment lands there; "View" leads there
  - auth-two-factor                 # where an enrolled user's next sign-in asks for a code
  - mfa-required                    # its "Visit your account" link points here
  - project-settings-security       # where a project's MFA requirement is turned on
flows:
  - flow-require-project-mfa        # this card is the enrolment hop (its S03, S04)
  - flow-login-return-to            # its S02, S03: the two-factor step this card switches on for the next sign-in
  - flow-reauth-backup-codes
---

## 1. Purpose

Any signed-in user comes here to protect their account with an authenticator app, so a leaked
password alone no longer opens projects holding health and survey data. It is also where a member
turned away by a project that requires MFA goes to restore their own access, where someone who
replaced their phone moves their codes to the new device, and where they can turn the protection
off. Without it a user would need an administrator to enrol, and projects could not require MFA
without locking people out for good.

## 2. What it does

- Any signed-in user sees whether their account has MFA turned on
- Any signed-in user without MFA starts setup and sees a QR code and a manual secret key
- Any signed-in user confirms setup with a code from their app, which turns MFA on
- Any signed-in user abandons setup without changing anything
- Any signed-in user with MFA moves it to another device
- Any signed-in user with MFA turns it off after confirming
- Any signed-in user with MFA reaches their recovery codes

## 3. Who can do what

Pulled from the code, not a policy module: the component calls no policy (`mfa_component.ex:1-128`).
It is rendered with the session's `current_user` and acts only on that user's `user_totps` row
(`components.ex:57-61`; `mfa_component.ex:16`, `:34`, `:69`).

| Action | Signed-in user without MFA (own account) | Signed-in user with MFA (own account) | Superuser / support (own account) | Anyone, on another user's account |
|--------|------------------------------------------|---------------------------------------|-----------------------------------|-----------------------------------|
| See the card and its state | yes | yes | yes | no |
| Start setup (QR code and secret) | yes | yes, as "Setup another device instead" | yes | no |
| Confirm setup with a code | yes | yes | yes | no |
| Cancel setup | yes | yes | yes | no |
| Turn MFA off | n/a | yes | yes | no |
| Open recovery codes | n/a | yes, after re-authenticating | yes | no |

**Preconditions beyond role**
- Self only: there is no user id in the route or the events (`components.ex:57-61`).
- Confirming setup needs a six-digit code that is valid for the newly generated secret (`user_totp.ex:26-43`, `:58-65`).
- Starting setup, moving to another device and turning MFA off need no password, code or sudo window; turning it off needs only the confirmation modal (`mfa_component.ex:24-47`, `:68-76`; see 6.2).
- Opening recovery codes from the "View" button needs a valid sudo session, which the backup codes route enforces by redirecting to `/auth/confirm_access` (`mfa_component.html.heex:268-272`; `router.ex:252-265`; `user_auth.ex:397-409`).
- A session still waiting on its second factor never reaches this card (shared-authenticated-session S03).

## 4. What it touches

**Reads**: `user_totps` by user id on every component update (`mfa_component.ex:16`, `accounts.ex:406-408`); `users.mfa_enabled` from the session's user (`mfa_component.ex:15`, `:90`, `:118`)

**Writes**:
- Confirm setup, in one transaction (`accounts.ex:415-437`):
  - `user_totps` insert, or update of the existing row with the new secret and `last_totp_at` (`mfa_component.ex:33-36`; `user_totp.ex:26-33`)
  - `users.mfa_enabled = true`
  - `user_backup_codes`: ten new codes, only if the user has none (`accounts.ex:423-431`, `:509-519`)
- First enrolment only: `user_tokens` insert, context `sudo_session` (`mfa_component.ex:93`, `accounts.ex:1021-1025`)
- Turn off, in one transaction: `users.mfa_enabled = false`, `user_totps` delete; `user_backup_codes` are left in place (`accounts.ex:444-457`)

**Immediate side effects** (in the same request)
- Flash "MFA Setup" and a live navigation: to `/profile/auth/backup_codes?sudo_token=<base64>` on first enrolment, to `/profile` when moving to another device (`mfa_component.ex:56-61`, `:89-97`); the first hands off to profile-backup-codes
- Flash "MFA Disabled" and live navigation to `/profile` after turning off (`mfa_component.ex:71-76`)
- No audit event, email or PubSub broadcast for enrolment, device change or turning off (`accounts.ex:415-457` do not touch `Accounts.Audit`, the notifier or PubSub)

**Deferred side effects** (later, elsewhere)
- The next sign-in asks for a two-factor code once MFA is on, and stops asking once it is off (`user_session_controller.ex:40`; `oidc_controller.ex:250`); owned by flow-login-return-to S02, S03
- Projects that require MFA admit the user once `mfa_enabled` is true, and refuse them again once it is false (`scope.ex:221-222`); owned by flow-require-project-mfa
- Digest and failure-alert emails for MFA-required projects follow the same flag (flow-require-project-mfa section 4)

**External, non-transactional effects**
- none; the QR code is rendered server-side as inline SVG (`mfa_component.ex:102-108`), and the secret never leaves the server except in the page

**Depends on config**
- none in a deployment; `:totp_client` is a test seam (`mfa_component.ex:26-28`)

**Product limits**
- Verification code is exactly six digits (`user_totp.ex:31`)
- Ten recovery codes are created on first enrolment (`accounts.ex:510-513`)
- The sudo token handed to the backup codes page lasts five minutes (`user_token.ex:35`)

## 5. Scenarios

```gherkin
Feature: Multi-factor authentication on the user profile
  In order to keep my account safe even if my password leaks
  As any signed-in user
  I want to turn on, move and turn off an authenticator app second factor myself

  @S01 @pending
  Scenario: A user without MFA sees that it is off
    # Value: a user can tell at a glance that their account is protected by a password alone.
    Given I am signed in and have not enrolled in MFA
    When I open "/profile"
    Then I see "Enable multi-factor authentication"
    And the "Enable multi-factor authentication" switch is off
    And I do not see "You have configured an authentication app to get two-factor authentication codes"
    And I do not see "Scan the QR code"
    And I do not see "Recovery codes"
    # mfa_component.ex:15; mfa_component.html.heex:9, :15-31, :39, :123, :256-273
    # profile_live_test.exs:288-296

  @S02 @pending
  Scenario: Starting setup shows a QR code and a key to type in by hand
    # Value: a user can enrol whether or not their authenticator app can scan a code.
    Given I am signed in and have not enrolled in MFA
    And I am on "/profile"
    When I click the "Enable multi-factor authentication" switch
    Then the switch is on
    And I see "Scan the QR code" and a QR code
    When I click "this secret key"
    Then I see "Your two-factor secret" and a secret in base32
    # mfa_component.ex:24-47, :102-108; mfa_component.html.heex:133-149, :188-253
    # profile_live_test.exs:298-303 (QR heading only; the secret modal is untested)

  @S03 @pending
  Scenario: Confirming setup with a code from the app turns MFA on
    # Value: a user turns on a second factor in one sitting, without an administrator, and is shown their recovery codes before they could need them.
    Given I am signed in and have not enrolled in MFA
    And I have started setup on "/profile"
    When I enter a valid code from my authenticator app in "Verify the code from the app"
    And I click "Save"
    Then I see "MFA Setup"
    And my account has MFA enabled
    And I am on the two-factor backup codes page with a sudo token
    And my next sign-in asks for a two-factor code, as in flow "flow-login-return-to" S02
    And the flow "flow-require-project-mfa" continues to its exit if a project had stopped me
    # mfa_component.ex:53-61, :89-97; accounts.ex:415-437, :1021-1025
    # profile_live_test.exs:311-349 (sudo_session token row, redirect path and flash asserted)
    # accounts_test.exs:410-422 (ten backup codes created)
    # landing behaviour is owned by profile-backup-codes

  @S04 @pending
  Scenario: A code that doesn't match the app is refused
    # Value: MFA is only switched on once the user has proved their app produces working codes, so they can't lock themselves out with a bad setup.
    Given I have started setup on "/profile"
    When I enter "123456", which is not a valid code, and click "Save"
    Then I see "invalid code" under "Verify the code from the app"
    And I still see "Scan the QR code"
    And my account does not have MFA enabled
    # user_totp.ex:35-43, :58-65; mfa_component.ex:63-64; accounts.ex:433-436
    # accounts_test.exs:388-408; user_totp_test.exs:73-90

  @S05 @pending
  Scenario: Abandoning setup changes nothing
    # Value: a user who starts setup without their phone to hand can back out without half-enabling MFA.
    Given I am signed in and have not enrolled in MFA
    And I have started setup on "/profile"
    When I click "Cancel"
    Then I do not see "Scan the QR code"
    And the "Enable multi-factor authentication" switch is off
    And my account does not have MFA enabled
    # mfa_component.ex:49-51; mfa_component.html.heex:171-177
    # profile_live_test.exs:305-308 (closes via the switch, not "Cancel"; both send hide-mfa-options)

  @S06 @pending
  Scenario: A user with MFA sees it is on and where their recovery codes are
    # Value: an enrolled user can confirm their account is protected and knows where to get back in if they lose their phone.
    Given I am signed in and have enrolled in MFA
    When I open "/profile"
    Then the "Enable multi-factor authentication" switch is on
    And I see "You have configured an authentication app to get two-factor authentication codes."
    And I see "Setup another device instead"
    And I see "Recovery codes" with a "View" button
    And I do not see "Scan the QR code"
    # mfa_component.ex:15-16; mfa_component.html.heex:39-52, :256-273
    # profile_live_test.exs:365-374

  @S07 @pending
  Scenario: Moving MFA to another device replaces the old one
    # Value: someone who replaces or loses their phone can move their second factor themselves, and the old device's codes stop working.
    Given I am signed in and have enrolled in MFA with my old phone
    And I am on "/profile"
    When I click "Setup another device instead"
    Then I see "Scan the QR code"
    And I do not see "Setup another device instead"
    When I enter a valid code from the new device and click "Save"
    Then I am on "/profile"
    And I see "MFA Setup"
    And codes from my old phone are no longer accepted
    And my recovery codes are unchanged
    # mfa_component.ex:33-36 (same row, new secret), :89-91; accounts.ex:415-431
    # profile_live_test.exs:376-380, :394-418; accounts_test.exs:425-446 (backup codes kept)

  @S08 @pending
  Scenario: Turning MFA off asks first, then removes it
    # Value: a user can drop a second factor they no longer want, and a stray click on the switch can't silently weaken the account.
    Given I am signed in and have enrolled in MFA
    And I am on "/profile"
    When I click the "Enable multi-factor authentication" switch
    Then I see "Disable MFA"
    And I see "Are you sure you want to disable MFA from your account? This will make your account less secure."
    When I click "Disable"
    Then I am on "/profile"
    And I see "MFA Disabled"
    And the switch is off
    And I do not see "You have configured an authentication app to get two-factor authentication codes"
    And my next sign-in no longer asks for a two-factor code
    # mfa_component.ex:68-76, :116-120; mfa_component.html.heex:53-121; accounts.ex:444-457
    # profile_live_test.exs:382-391 (clicks the hidden modal's button directly; the modal opening is a JS command and untested)
    # projects that require MFA refuse me again afterwards: flow-require-project-mfa 6.2 row 5

  @S09 @pending
  Scenario: Backing out of turning MFA off keeps it on
    # Value: a user who opened the confirmation by mistake leaves with their protection intact.
    Given I am signed in and have enrolled in MFA
    And I have opened the "Disable MFA" confirmation
    When I click "Cancel"
    Then I no longer see "Disable MFA"
    And my account still has MFA enabled
    # mfa_component.html.heex:110-116, :66-71 (escape and click-away also close it)

  @S10 @pending
  Scenario: Viewing recovery codes hands off to re-authentication
    # Value: recovery codes, which bypass the second factor, are only shown to someone who has just proved who they are.
    Given I am signed in and have enrolled in MFA
    And I am on "/profile"
    When I click "View" under "Recovery codes"
    Then the flow "flow-reauth-backup-codes" has started
    # mfa_component.html.heex:268-272; router.ex:252-265; user_auth.ex:397-409
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Turning MFA off in one tab and then again in a second tab opened earlier deletes a `user_totps` row that is already gone; `Repo.delete` on a stale struct raises inside the Multi | `mfa_component.ex:16`, `:68-71`; `accounts.ex:444-452` | the LiveView crashes and the page reloads, instead of the handled "Oops! Could not disable 2FA..." flash | fix |
| Enrolling in a second tab opened before enrolling in the first: that tab still has `current_totp: nil`, builds a new `UserTOTP`, and the insert hits the unique index on `user_id`, which the changeset doesn't declare | `mfa_component.ex:16`, `:33-34`; `user_totp.ex:26-33`; `priv/repo/migrations/20230713043851_create_users_totps_table.exs:13` | the LiveView crashes on "Save" with a valid code | fix |
| `upsert_user_totp/2` matches only a failure at the `:totp` step; a failure updating the user or creating backup codes raises a `CaseClauseError` | `accounts.ex:433-436` | a crash instead of a form error, should either step ever fail | fix |
| A user with `mfa_enabled: true` but no `user_totps` row sees the "on" switch and the disable modal, and "Disable" calls `delete_user_totp(nil)`, which crashes; reachable only with inconsistent data (factories create it, no app path does) | `mfa_component.ex:69-71`; `accounts.ex:444-449` | a crash, and no way to turn MFA off from the profile | decide |
| The disable modal's `aria-labelledby` is `disable-mfa-moda-title`, but the heading's id is `disable-mfa-modal-title` | `mfa_component.html.heex:57`, `:87` | a screen reader announces the dialog with no name | fix |
| `<a href>` nested inside a `<button>` for "View"; only the text is a link, and the button is not keyboard-equivalent to the link | `mfa_component.html.heex:268-272` | clicking the padding of the button does nothing; invalid nesting of interactive elements | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Starting setup, moving to another device and turning MFA off need no password, code or sudo window; someone with an unattended signed-in session can enrol their own device or remove the owner's second factor | `mfa_component.ex:24-47`, `:68-76`; flow-require-project-mfa 6.5 | decide |
| Turning MFA off sends no email and records no audit event; neither does enrolling or changing device | `accounts.ex:415-457` | decide |
| Turning MFA off keeps the old recovery codes; re-enrolling later reuses them instead of issuing new ones, and lands on the backup codes page showing the old set | `accounts.ex:423-431`, `:444-457` | decide |
| Every click on "Enable" or "Setup another device instead" generates a new secret; a QR code scanned before closing and reopening setup no longer matches | `mfa_component.ex:27-36` | preserve |
| The switch is driven by the session's `mfa_enabled`, so while setting up another device the switch opens the disable modal rather than closing the form | `mfa_component.ex:116-127` | decide |
| A well-formed wrong code shows the untranslated, lowercase "invalid code"; a malformed one shows both "Invalid OTP code." and "invalid code" under the same field | `user_totp.ex:31`, `:41`; `errors.po:39-40`; `user_totp_test.exs:58-71` | decide |
| The card says "multi-factor authentication" and "MFA", the error flash says "2FA", the setup copy says "two-factor"; the heading "Enable multi-factor authentication" stays the same when MFA is already on | `mfa_component.html.heex:9`, `:41`, `:239`; `mfa_component.ex:60`, `:75`, `:83` | decide |
| The success flash is "MFA Setup" for both a first enrolment and a device change | `mfa_component.ex:60` | decide |
| Issuer and account label in the authenticator are hard-coded "OpenFn" and the user's email, whatever the instance | `mfa_component.ex:25`, `:30-31` | decide |
| The disable warning talks about attackers but not about losing access to projects that require MFA | `mfa_component.html.heex:92-95`; flow-require-project-mfa 6.2 row 5 | decide |
| The sudo token for the backup codes page is passed Base64 in the URL query string | `mfa_component.ex:93-96`; `user_auth.ex:226-231` | decide |
| A completed GitHub connection (`OauthTokenAdded`) push-navigates the host page to `/profile`, discarding a setup in progress on this card | `edit.ex:33-41` | preserve |
| Moving to another device carries over `last_totp_at` from the old device, so the new device's first code must be from a later time step than the last code used on the old one | `mfa_component.ex:33-36`; `user_totp.ex:29`, `:63` | preserve |
| Turning MFA off and the error path both push-navigate to `/profile`, remounting the whole page, rather than updating the card | `mfa_component.ex:76`, `:85` | preserve |
| "Cancel" in setup leaves `qrcode_uri` and `totp_changeset` assigned; only `editing_totp` is cleared | `mfa_component.ex:49-51` | preserve |
| The QR SVG has its XML declaration stripped so it parses as HTML | `mfa_component.ex:110-114`; `profile_live_test.exs:301-302` | preserve |
| The secret modal's close button is hidden below the `sm` breakpoint; on phones it closes only by escape or tapping outside | `mfa_component.html.heex:207` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:lightning, :totp_client` override | `mfa_component.ex:26-28`; `test/support/totp_adapter.ex` | set only by tests (`profile_live_test.exs:315`, `:396`); production always uses NimbleTOTP |
| `{:error, _reason}` branch of `disable_mfa` and its "Oops! Could not disable 2FA..." flash | `mfa_component.ex:78-86` | the Multi changes only a boolean and deletes a row; a stale row raises instead of returning an error (6.1), so no known path returns `{:error, ...}` |
| `#disable-mfa-modal-bg` / `phx-remove` on the disable modal and its container | `mfa_component.html.heex:60`, `:71` | the modal is removed only by a navigation that remounts the page, so the remove transition never plays |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `get_user_totp/1` runs on every `update/2` of the component, i.e. on every host re-render that passes it new assigns | `mfa_component.ex:16` | no | preserve |
| QR code SVG is 264 px wide | `mfa_component.ex:105` | yes | preserve |
| Sudo token for the backup codes page expires after five minutes | `user_token.ex:35` | yes, if the user waits before viewing codes | preserve |

### 6.5 Things seen but not understood

- The "Disable" button carries `phx-disable-with="Disabling..."` while the modal it sits in is a client-side JS modal; whether the disabled state is ever visible before the navigation is unclear (`mfa_component.html.heex:100-108`). Disposition: preserve.
- The first-enrolment branch keys off the session's `mfa_enabled`, not off whether a `user_totps` row existed, so a user with a stale tab could be sent to backup codes after what is really a device change (`mfa_component.ex:89-97`). Not reproduced; it would also need the second 6.1 row not to crash first. Disposition: decide.
- `last_totp_at` is set by the changeset to the current time on enrolment (`user_totp.ex:29`), and sign-in later checks codes `since:` that time (`user_totp.ex:63`); whether the enrolment code itself can be replayed at the very next sign-in inside the same 30-second step was not traced. Disposition: preserve.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should starting setup, changing device or turning MFA off require a password or re-authentication, as viewing recovery codes does (6.2)? (owner: product)
- Should turning MFA off notify the user by email and record an audit event (6.2)?
- Should turning MFA off revoke recovery codes, so a later re-enrolment issues fresh ones (6.2)?
- Should the disable confirmation warn about projects that require MFA (6.2, shared with flow-require-project-mfa)?

## Proposed flows

- `flow-reauth-backup-codes` (new): from the "View" button under "Recovery codes" on `/profile`, a GET to `/profile/auth/backup_codes` without a sudo session is refused by `require_sudo_user`, which stores the path (without any `sudo_token`) as `user_return_to` and redirects to `/auth/confirm_access` with "You must verify yourself again in order to access this page." (`mfa_component.html.heex:268-272`; `router.ex:252-265`; `user_auth.ex:211-231`, `:397-409`, `:496-510`); after re-authenticating, ReAuthenticateLive navigates back with a fresh `sudo_token` appended (`re_authenticate_live/new.ex:9-14`, `:40-42`, `:74`) and the backup codes page renders (`backup_codes_live_test.exs:20-43`). Surfaces: profile-mfa, controller:require-sudo-user, reauth-confirm-access, profile-backup-codes. This file asserts only the handoff (S10). First enrolment skips this flow by minting its own sudo token (S03).
- Referenced, not proposed: `flow-require-project-mfa` (this card is its enrolment hop, its S03 and S04; S03 here asserts only the handoff); `flow-login-return-to` (its S02 and S03 are the two-factor sign-in that S03 and S08 here switch on and off).

## Proposed shared

- none. Referenced: shared-authenticated-session (S01 to S06, through the host page), shared-project-header (no-project parts, through the host page, as profile-account cites them).

## Lead resolution (batch 7)

- `flow-reauth-backup-codes` created as proposed.
