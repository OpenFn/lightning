---
id: profile-backup-codes
type: view
title: User profile › Two-factor backup codes
status: not-started
owner:

trigger:
  old_route: /profile/auth/backup_codes (and /profile/auth/backup_codes/print, opened in a new tab)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the visitor passes shared-authenticated-session; both routes sit in the `:browser, :require_authenticated_user` scope (`router.ex:189-190`, `:252-265`)
    - the session holds a `sudo_token` (from the session or the `sudo_token` query param) that belongs to this user and is under five minutes old, checked by the `:reauth_sudo_mode` and `:require_sudo_user` plugs on every HTTP request and by `on_mount :ensure_sudo` on every LiveView mount (`router.ex:252-262`; `user_auth.ex:211-231`, `:397-410`, `:443-475`); otherwise flow-reauth-backup-codes runs first
    - MFA is not required to reach either route; the profile only shows the entry point to MFA users (profile-mfa S06), and this page shows an "MFA Disabled" notice otherwise (`index.html.heex:14-52`)
    - the print page is refused to an unconfirmed account past its deadline, like every signed-in route outside the allow list (`confirmation_lockout.ex:14-33`; `confirmation_lockout_test.exs:24-37`; shared-authenticated-session S04)

inherits:
  - shared-authenticated-session    # both routes: login redirect S01, disabled account S02, two-factor pending S03, lockout S04 to S06. The LiveView mounts InitAssigns through the unnamed `:sudo_auth` live_session (router.ex:258-262); the print page is a controller, so only the router-plug scenarios apply to it
  - shared-project-header           # LiveView only, no-project parts as profile-account cites them: global picker S11, S12; confirmation banner S13, S14; role menu S17; account menu S18 (layout_components.ex:259-296, menu.ex:89-110). The print page renders in the bare app layout (layouts/app.html.heex:1-5)
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: sudo_token
    set_by: auth-confirm-access (flow-reauth-backup-codes) and profile-mfa on first enrolment (its S03, `mfa_component.ex:89-97`)
    effect: Base64 of a `sudo_session` token; the plug copies it into the session and the page opens if it is this user's and under five minutes old (`user_auth.ex:211-231`; `accounts.ex:1030-1035`; `user_token.ex:35`)

config_variants:
  default: {}                       # everything below was read under this one; the page reads no config of its own
  # require-email-verification is inherited from shared-authenticated-session (S04 to S06) and adds nothing specific here

inventory:
  routes:
    - live /profile/auth/backup_codes  BackupCodesLive.Index :index          # router.ex:258-263, live_session :sudo_auth
    - get /profile/auth/backup_codes/print  BackupCodesController :print     # router.ex:264
  events:
    - BackupCodesLive.Index#regenerate-backup-codes                          # index.ex:27-35
    - BackupCodesController#print                                            # backup_codes_controller.ex:5-12
  js_hooks:
    - Copy (`#copy-codes-button`, data-to path only)                         # index.html.heex:134-145; assets/js/hooks/index.ts:738-814
    - Flash (`#codes-copied-alert`)                                          # index.html.heex:151-187; assets/js/hooks/index.ts:532-549
    - Tooltip (used-code tooltip via Common.tooltip)                         # index.html.heex:98-102; common.ex:348-357; assets/js/hooks/index.ts:567
    - inline onclick window.open for "Print Codes"                           # index.html.heex:111-131
  policies:
    - LightningWeb.UserAuth.reauth_sudo_mode/2                               # user_auth.ex:211-224
    - LightningWeb.UserAuth.require_sudo_user/2                              # user_auth.ex:397-410
    - LightningWeb.UserAuth.on_mount(:ensure_sudo)                           # user_auth.ex:443-475
    - Lightning.Accounts.sudo_session_token_valid?/2                         # accounts.ex:1030-1035
    - LightningWeb.Hooks.on_mount(:assign_projects)                          # index.ex:9; hooks.ex:194-202; not a gate, see 6.3
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Copy hook `data-content` path and the "Copied!" tooltip path (assets/js/hooks/index.ts:749-750, :808-814); this page sets only `data-to` and has no Tooltip ancestor
    - Accounts.valid_user_backup_code?/2 (accounts.ex:472-502); codes are spent at sign-in (user_totp_controller.ex:55-58), owned by flow-login-return-to S02
    - ReAuthenticateLive.New (/auth/confirm_access); owned by auth-confirm-access and flow-reauth-backup-codes
    - ProfileLive.MfaComponent first-enrolment sudo token and the creation of the first ten codes (mfa_component.ex:89-97; accounts.ex:423-431); owned by profile-mfa S03

related:
  - profile-mfa                     # "View" under "Recovery codes" leads here; first enrolment lands here
  - auth-confirm-access             # where an expired or missing sudo window sends the visitor
  - auth-two-factor                 # where these codes are spent
  - flow-login-return-to            # its S02 signs in with a backup code
flows:
  - flow-reauth-backup-codes        # exit: this page and its print tab
  - flow-require-project-mfa        # first enrolment lands here (its S03)
  - flow-spend-backup-code
---

## 1. Purpose

A user with multi-factor authentication comes here to see, save and replace the one-time recovery
codes that let them sign in if they lose their authenticator device. Without it, someone whose
phone breaks or is stolen has no way back into an account holding health and survey data short of
an administrator, and someone who thinks their codes have leaked has no way to cancel them.

## 2. What it does

- **See the codes**
  - Any signed-in user who has re-authenticated in the last five minutes sees their own recovery codes; anyone else is sent to re-authenticate first
  - Any signed-in user who has just enrolled in MFA lands here and sees their new codes
  - A signed-in user without MFA is told the codes need MFA and pointed to the profile
- **Keep a copy**
  - Any signed-in user copies all their codes to the clipboard
  - Any signed-in user opens a printable copy of their codes in a new tab
- Any signed-in user replaces all their codes with ten new ones

**Straightforwardness: 3 of 5.** A familiar recovery-codes page, but used codes, the one-click replace and what a user without MFA can do all behave in ways you wouldn't guess.

### Most surprising behaviours

- **(2)** Once a user has signed in with one of their codes, this page seems likely to fail to load at all, right when they most need to check what's left. Not yet confirmed by running it. (6.1, 8)
- **(3)** "Generate new backup codes" acts on one click, with no confirmation and no email, and every old code stops working at once. It also works after the five-minute window has run out if the page is still open. (6.2, 6.4)
- **(3)** Copy and print include codes that have already been used, with nothing marking them, so the saved list looks like it has more working codes than it does. (6.1)
- **(4)** The codes can be shown again any time rather than only once, because they are stored in a form that can be read back. (6.2)
- **(4)** A user who has never turned on MFA still sees the codes and can generate them below the "MFA Disabled" notice. (6.2)

## 3. Who can do what

Pulled from the code, not a policy module: no policy is called (`index.ex:1-45`;
`backup_codes_controller.ex:1-13`). Every read and write uses the session's `current_user`, and
neither route takes a user id (`index.ex:28-29`, `:42`; `backup_codes_controller.ex:6`).

| Action | User with MFA (own account) | User without MFA (own account) | Superuser / support | Another signed-in user |
|--------|-----------------------------|--------------------------------|---------------------|------------------------|
| See the page and own codes, inside the sudo window | yes | yes, below an "MFA Disabled" notice | own codes only | no, only their own |
| Copy codes | yes | yes | own codes only | no |
| Open the print page | yes | yes | own codes only | no |
| Generate new backup codes | yes | yes | own codes only | no |
| See the "MFA Disabled" notice | no | yes | if not enrolled | n/a |

**Preconditions beyond role**
- Self only: no user id in either route or in the event (`router.ex:263-264`; `index.ex:27-29`).
- Sudo window: a `sudo_session` token for this user, inserted under five minutes ago, in the session or the query (`user_auth.ex:211-231`, `:443-475`; `user_token.ex:35`). It is checked on page load and mount only; "Generate new backup codes" is not re-checked (`index.ex:27-35`; flow-reauth-backup-codes 6.2).
- MFA state does not gate anything; it only switches the notice on (`index.html.heex:15`).
- A session still waiting on its second factor, a disabled account and a locked-out unconfirmed account never reach either route (shared-authenticated-session S02 to S04).

## 4. What it touches

**Reads**
- `user_tokens` (session token, and `sudo_session` token when one is in the query or session) on every request and mount (`user_auth.ex:211-224`, `:461-475`; `accounts.ex:1030-1035`)
- `user_backup_codes` for the current user, on load and on the print page (`index.ex:42`; `backup_codes_controller.ex:6`; `accounts.ex:525-530`)
- `users.mfa_enabled` from the session's user (`index.html.heex:15`)
- The user's projects, twice: once by `:assign_projects`, unused (`index.ex:9`; `hooks.ex:194-202`; 6.3), and once for the global project picker (`layout_components.ex:461-468`)

**Writes**
- Session `sudo_token`, copied from the query param (`user_auth.ex:226-231`)
- "Generate new backup codes": every existing `user_backup_codes` row for the user deleted and ten new rows inserted, in one `Repo.update` (`accounts.ex:509-519`; `user.ex:51-52`, `on_replace: :delete`)

**Immediate side effects** (in the same request)
- Flash "New Backup Codes Generated!" and the new codes rendered in place (`index.ex:31-34`)
- "Copy Codes" writes every listed code, one per paragraph, to the browser clipboard, with an `execCommand` fallback, then shows "Copied!" (`index.html.heex:134-187`; `assets/js/hooks/index.ts:738-806`)
- "Print Codes" opens `/profile/auth/backup_codes/print` in a new tab (`index.html.heex:113`); the print page itself is owned by flow-reauth-backup-codes S07, S08
- No audit event, email, PubSub broadcast or Oban job on viewing, printing or regenerating (`index.ex:27-35`; `accounts.ex:509-530`)

**Deferred side effects** (later, elsewhere)
- After regenerating, the old codes are no longer accepted at sign-in, because they no longer exist (`accounts.ex:472-483`, `:509-519`); the sign-in itself is owned by flow-login-return-to S02
- A code spent at sign-in gets `used_at` and would show struck through here (`accounts.ex:485-502`; `index.html.heex:93-102`); proposed as flow-spend-backup-code, blocked by 6.1 row 1

**External, non-transactional effects**
- none; the clipboard write is in the browser

**Depends on config**
- none

**Product limits**
- Ten codes per regeneration (`accounts.ex:510-513`)
- Each code is nine characters from the base32 alphabet, with "O" replaced by "X" to avoid confusion with zero (`user_backup_code.ex:29-35`)
- Each code works once at sign-in (`accounts.ex:488-489`); enforced on the sign-in page, not here
- The sudo window that opens this page lasts five minutes (`user_token.ex:35`)

## 5. Scenarios

```gherkin
Feature: Two-factor backup codes
  In order to get back into my account if I lose my authenticator
  As a signed-in user with MFA
  I want to see, save and replace my recovery codes

  @S01 @pending
  Scenario: A user who has just re-authenticated sees their recovery codes
    # Value: a user can retrieve the codes they need to sign in without their device, and store them somewhere safe.
    Given I am signed in and have enrolled in MFA
    And I have five recovery codes
    And I re-authenticated less than five minutes ago
    When I open "/profile/auth/backup_codes"
    Then I see "Two-factor backup codes"
    And I see "Recovery codes can be used to access your account in the event you lose access to your device"
    And I see "Keep your backup codes as safe as your password."
    And I see each of my five recovery codes
    And I do not see "MFA Disabled"
    # index.ex:37-44; index.html.heex:2-6, :10-13, :54-62, :88-108; user_auth.ex:211-231, :443-475
    # backup_codes_live_test.exs:39-49 (asserts "Recovery codes" and each code)

  @S02 @pending
  Scenario: Opening the page without a valid sudo window hands off to re-authentication
    # Value: codes that bypass the second factor are never shown to someone who has not just proved who they are.
    Given I am signed in and have enrolled in MFA
    And the session holds no sudo token that is mine and under five minutes old
    When I open "/profile/auth/backup_codes"
    Then the flow "flow-reauth-backup-codes" has started
    And I do not see any of my recovery codes
    # router.ex:252-262; user_auth.ex:397-410, :443-458
    # backup_codes_live_test.exs:24-37 (redirect to /auth/confirm_access; the session there still holds the setup user's token, so this is the "someone else's token" case)

  @S03 @pending
  Scenario: First enrolment lands here with the new codes
    # Value: a user who has just turned on MFA is shown their recovery codes before they could ever need them, without being asked to re-authenticate straight after proving their device works.
    Given I have just confirmed MFA setup on "/profile" for the first time
    Then I am on "/profile/auth/backup_codes" with a sudo token in the address
    And I see ten recovery codes
    # handoff from flow-require-project-mfa S03 and profile-mfa S03 (mfa_component.ex:89-97; accounts.ex:423-431, :1021-1025)
    # user_auth.ex:226-231 copies the token into the session; profile_live_test.exs:311-349 asserts the redirect, not this page

  @S04 @pending
  Scenario: Generating new codes replaces every old one
    # Value: a user who suspects their codes were seen can cancel all of them at once and get a fresh set.
    Given I am signed in and have enrolled in MFA
    And I have five recovery codes
    And I am on "/profile/auth/backup_codes" inside my sudo window
    Then I see "When you generate new backup codes, you must copy or print the new codes. Your old codes won't work anymore."
    When I click "Generate new backup codes"
    Then I see "New Backup Codes Generated!"
    And I see ten recovery codes
    And I do not see any of my five old codes
    And none of my five old codes remain on my account
    # index.ex:27-35; index.html.heex:190-206; accounts.ex:509-519; user.ex:51-52
    # backup_codes_live_test.exs:70-91 (old codes gone from the page, stored codes shown; flash not asserted)
    # accounts_test.exs:461-471 (ten new codes, old rows gone)

  @S05 @pending
  Scenario: Copying puts every code on the clipboard
    # Value: a user can paste their codes straight into a password manager, as the page recommends, without retyping them.
    Given I am on "/profile/auth/backup_codes" inside my sudo window
    And I have ten recovery codes
    When I click "Copy Codes"
    Then my clipboard holds each of my ten codes, separated by blank lines
    And I see "Copied!"
    # index.html.heex:134-150, :151-187; assets/js/hooks/index.ts:738-806
    # untested

  @S06 @pending
  Scenario: Printing hands off to a printable copy in a new tab
    # Value: a user can keep a paper copy of their codes away from the device they might lose.
    Given I am on "/profile/auth/backup_codes" inside my sudo window
    When I click "Print Codes"
    Then a new tab opens on "/profile/auth/backup_codes/print"
    And the flow "flow-reauth-backup-codes" S07 owns what that tab shows
    # index.html.heex:111-131; router.ex:264; backup_codes_controller.ex:5-12
    # untested

  @S07 @pending
  Scenario: A user without MFA is told the codes need it and where to turn it on
    # Value: a user who reaches their codes without MFA learns they do nothing yet, instead of trusting them as a way back in.
    Given I am signed in and have not enrolled in MFA
    And I re-authenticated less than five minutes ago
    When I open "/profile/auth/backup_codes"
    Then I see "MFA Disabled"
    And I see "In order to use backup codes, you need to have MFA enabled in your account."
    When I click "Back to profile"
    Then I am on "/profile"
    # index.html.heex:14-52; profile-mfa owns enrolment from there
    # untested
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A spent code renders its tooltip with `NaiveDateTime.truncate(backup_code.used_at, :second)`, but `used_at` is a `:utc_datetime_usec` field, so it loads as a `DateTime`; `NaiveDateTime.truncate/2` pattern-matches a `NaiveDateTime`, so this should raise `FunctionClauseError`. Not executed (no Elixir runtime in this container), and no test inserts a spent code (`factories.ex:385-389`) | `index.html.heex:93-102`; `user_backup_code.ex:17` | after signing in once with a backup code, the page fails to render instead of showing that code struck through | fix |
| Every spent code's tooltip gets the same DOM id, `backup-code-last-used-tooltip`, and each carries the Tooltip hook | `index.html.heex:98-99` | with two or more spent codes (once row 1 is fixed), duplicate-id errors and tooltips that may not attach | fix |
| "Copy Codes" copies spent codes along with unused ones, with nothing marking which is which; the print page has the same gap (flow-reauth-backup-codes 6.1 row 5) | `index.html.heex:149` | a pasted list in which spent codes look usable | fix |
| The "Copied!" alert's Flash hook starts its five-second auto-hide when the page mounts, not when the alert is shown; by the time a user copies, the timer has already fired on the hidden element | `index.html.heex:151-166`; `assets/js/hooks/index.ts:532-541` | "Copied!" stays on screen until clicked or hovered | fix |
| `{:ok, user} = Accounts.regenerate_user_backup_codes(current_user)` has no error branch | `index.ex:29` | a crash and remount instead of an error, should the update ever fail | fix |
| Copy that fails in both the Clipboard API and `execCommand` paths only logs to the console | `assets/js/hooks/index.ts:794-796` | clicking "Copy Codes" appears to do nothing | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Generate new backup codes" acts on one click with no confirmation, and invalidates every old code immediately | `index.html.heex:198-204`; `index.ex:27-35` | decide |
| Regenerating sends no email and records no audit event; neither does viewing or printing | `index.ex:27-35`; `accounts.ex:509-519` | decide |
| A user without MFA still sees the full codes block and can regenerate codes below the "MFA Disabled" notice; regenerating creates ten codes for an account that has never enrolled | `index.html.heex:14-52`, `:54-206`; `accounts.ex:509-519` | decide |
| A user with no codes at all sees an empty grid, and "Copy Codes" does nothing (empty text is skipped) | `index.html.heex:88-108`; `assets/js/hooks/index.ts:763` | decide |
| Codes are stored reversibly encrypted (`Lightning.Encrypted.Binary`), not hashed, which is what lets this page show them again at any time | `user_backup_code.ex:13-15` | decide |
| Codes are listed without an order; after regenerating, the page shows the new list in generation order, but a reload or the print page may show another | `accounts.ex:525-530`; `index.ex:34` | preserve |
| Copy drifts: "Recovery codes" in the intro and warning, "Backup Codes" as the card heading, "Two-factor backup codes" as the page title; title case in "Backup Codes", "MFA Disabled", "Print Codes", "Copy Codes"; "!" in the flash | `index.ex:33`, `:39`; `index.html.heex:11`, `:37`, `:57`, `:82`, `:130`, `:144` | decide |
| The intro says MFA can be enabled "by visiting your profile page" while the button below says "Back to profile", even when the user did not come from there | `index.html.heex:41-42`, `:48-50` | decide |
| The used-code tooltip shows the raw UTC timestamp, not the viewer's local time | `index.html.heex:100` | decide |
| "Print Codes" is a plain `<button>` with an inline `onclick` `window.open`, without `noopener`; the print page does not open the browser's print dialog | `index.html.heex:111-113`; flow-reauth-backup-codes 6.2 | decide |
| The "Copy Codes" button sits next to a hidden `<input>` whose value is the codes joined by blank lines; the Copy hook reads it at click time | `index.html.heex:146-150` | preserve |
| `:sudo_auth` is its own live_session, so arriving from `/profile` (`:services`) or `/auth/confirm_access` (`:auth`) is a full page load | `router.ex:242-244`, `:258-263`, `:351-355` | preserve |
| The sidebar marks "User Profile" as active (`active_menu_item: :profile`) | `index.ex:13`; `menu.ex:97-100` | preserve |
| The print page's logo is a link to `#` | `print.html.heex:3` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `on_mount {LightningWeb.Hooks, :assign_projects}` and the `@projects` assign it sets | `index.ex:9`; `hooks.ex:194-202` | neither this template nor the live layout reads `@projects`; the global picker runs its own query (`layout_components.ex:461-468`). The project-picker test passes through the picker, not this assign (`backup_codes_live_test.exs:51-68`) |
| `JS.remove_class("fade-in-scale", ...)` on the "Copied!" alert | `index.html.heex:156` | nothing adds `fade-in-scale`; `JS.show` at `:137` adds no class |
| Copy hook "Copied!" tooltip (`showCopiedTooltip`) | `assets/js/hooks/index.ts:808-814` | the button has no Tooltip ancestor, so the event is never dispatched |
| `apply_action/3` has only an `:index` clause | `index.ex:37-44` | the router defines only `:index` (`router.ex:263`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| A redundant projects query on every mount (6.3) | `hooks.ex:194-202` | no | preserve |
| "Copied!" auto-hide is five seconds, reset on hover | `assets/js/hooks/index.ts:539-544` | yes (but see 6.1 row 4) | preserve |
| Sudo window is five minutes, fixed from re-authentication; the open page keeps working past it | `user_token.ex:35`; flow-reauth-backup-codes 6.2 | yes | preserve |

### 6.5 Things seen but not understood

- The unique index on `[:user_id, :code]` covers an encrypted column; if the cipher uses a random IV, identical codes encrypt differently and the index can never fire (`priv/repo/migrations/20230721075131_create_user_backup_codes_table.exs:13`; `user_backup_code.ex:13`, `:26`). Collisions are vanishingly unlikely at 45 bits, so this may not matter. Not traced into the vault config. Disposition: preserve.
- The migration declares `used_at` as `naive_datetime_usec` while the schema reads it as `utc_datetime_usec` (`20230721075131_create_user_backup_codes_table.exs:9`; `user_backup_code.ex:17`); this is what makes 6.1 row 1 likely, and whether the template was written against an earlier schema type was not traced. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Does the page render once a code has been spent (6.1 row 1)? Needs a run against the old app with a spent code before S-tagging it. (owner: engineering)
- Should "Generate new backup codes" ask for confirmation and re-check the sudo window (6.2; flow-reauth-backup-codes 6.2)? (owner: security)
- Should regenerating, viewing or printing codes send an email or record an audit event (6.2)? (owner: security)
- Should codes be stored hashed and shown only once, as many products do, instead of viewable at any time (6.2)? (owner: security)
- Should the page refuse, rather than warn, a user without MFA, and should it be possible to generate codes before enrolling (6.2; flow-reauth-backup-codes section 8)? (owner: product)
- Should copy and print mark or leave out spent codes (6.1)? (owner: product)

## Proposed flows

- `flow-spend-backup-code` (new): on `/users/two-factor`, choosing a backup code and entering a valid unused one signs the user in and sets its `used_at` (`user_totp_controller.ex:55-58`; `accounts.ex:472-502`); entering the same code again is refused (`accounts.ex:488-489`); on `/profile/auth/backup_codes` that code then shows struck through with a "Code used on ..." tooltip (`index.html.heex:93-102`), currently blocked by 6.1 row 1. Overlaps flow-login-return-to S02, which covers only the redirect after a valid backup code, not single use or the display here. Surfaces: auth-two-factor, controller:user-totp, profile-backup-codes. This file asserts nothing about it yet.
- Referenced, not proposed: `flow-reauth-backup-codes` (this page and its print tab are the exit; S02 and S06 here assert only the handoff); `flow-require-project-mfa` (first enrolment lands here, its S03; S03 here asserts only the landing).

## Proposed shared

- none. Referenced: shared-authenticated-session (both routes; router-plug scenarios only for the print page), shared-project-header (no-project parts, LiveView only). The `:reauth_sudo_mode` / `:require_sudo_user` / `:ensure_sudo` trio guards only these two routes, so it stays in flow-reauth-backup-codes; a `shared-sudo-mode` annotation would be worth it only if a second route adopts it.

## Lead resolution (batch 8)

- `flow-spend-backup-code` created as proposed.
