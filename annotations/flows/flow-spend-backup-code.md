---
id: flow-spend-backup-code
type: flow
title: Signing in with a recovery code
status: not-started
owner:

trigger:
  entry: auth-two-factor                     # /users/two-factor?authentication_type=backup_code, reached after the password step (user_session_controller.ex:40-46)
  exit: profile-backup-codes                 # /profile/auth/backup_codes, where the spent code should show struck through (index.html.heex:93-102); blocked by 6.1 row 1
  surfaces:
    - auth-two-factor                        # GET /users/two-factor, backup code variant (user_totp_controller.ex:9-15, :43-51; new.html.heex:55-66, :76-89)
    - controller:user-totp                   # POST /users/two-factor, UserTOTPController.create/2 (user_totp_controller.ex:17-31, :53-58)
    - profile-backup-codes                   # reached through flow-reauth-backup-codes (router.ex:252-263)
  reachable_when:
    - the account has `mfa_enabled` and the session carries `user_totp_pending`, set only after the password or the external provider was accepted (user_session_controller.ex:40-46; oidc_controller.ex:250-256; user_totp_controller.ex:7, :33-41)
    - the account holds at least one backup code with no `used_at` (accounts.ex:485-494); codes are created on first enrolment or by "Generate new backup codes" (accounts.ex:423-431, :509-519)
    - the exit hop additionally needs a sudo window, so it runs after flow-reauth-backup-codes (router.ex:252-262; user_auth.ex:211-231, :397-410, :443-475)

inherits:
  - shared-authenticated-session    # every hop: login redirect (its S01), disabled account (its S02); its S03 is the gate that holds a pending session on /users/two-factor until this flow's second hop clears it

url_params:
  - name: authentication_type
    set_by: auth-two-factor ("Use your backup code" link, new.html.heex:76-89)
    effect: "backup_code" renders the backup code variant and posts `user[authentication_type]=backup_code` (user_totp_controller.ex:13, :43-51; new.html.heex:41-45)

config_variants:
  default: {}                        # everything below was read under this one
  # sso-provider: arrival from controller:oidc-callback reaches the same entry hop with remember-me forced on (oidc_controller.ex:250-256); owned by flow-sso-login, adds nothing to spending a code

inventory:
  routes:
    - get /users/two-factor  UserTOTPController :new                       # router.ex:192
    - post /users/two-factor  UserTOTPController :create                   # router.ex:193
    - live /profile/auth/backup_codes  BackupCodesLive.Index :index        # router.ex:263
  events:
    - UserTOTPController#create                                            # user_totp_controller.ex:17-31
  js_hooks:
    - Tooltip (spent-code tooltip via Common.tooltip)                      # index.html.heex:98-102; common.ex:348-357
  policies:
    - UserTOTPController.redirect_if_totp_is_not_pending/2                 # user_totp_controller.ex:7, :33-41
    - Lightning.Accounts.valid_user_backup_code?/2                         # accounts.ex:472-502
    - LightningWeb.UserAuth.totp_validated/1                               # user_auth.ex:486-488
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - Accounts.valid_user_totp?/2 (accounts.ex:462-467); the authenticator branch of the same controller, owned by auth-two-factor S01 and S04
    - Accounts.regenerate_user_backup_codes/1 (accounts.ex:509-519); owned by profile-backup-codes S04
    - BackupCodesController.print/2 (backup_codes_controller.ex:5-12); owned by flow-reauth-backup-codes S07, S08

related:
  - lib/lightning_web/controllers/user_totp_controller.ex
  - lib/lightning_web/controllers/user_totp_html/new.html.heex
  - lib/lightning/accounts.ex                          # valid_user_backup_code?/2 :472-502, list_user_backup_codes/1 :525-530
  - lib/lightning/accounts/user_backup_code.ex
  - lib/lightning_web/live/backup_codes_live/index.html.heex
  - test/lightning_web/controllers/user_totp_controller_test.exs   # :122-183
  - test/lightning/accounts_test.exs                               # :515-543
  - flow-login-return-to              # its S02 backup code row covers only where a valid code redirects to
  - flow-reauth-backup-codes          # the sudo gate in front of the exit hop
flows: []
---

## 1. Purpose

A user with two-factor authentication who has lost or reset their authenticator uses one of their
printed or saved recovery codes to finish signing in. Each code must open the account exactly once,
so a code that has been seen, photographed or left in an old printout is useless after its first
use, and the user must be able to tell afterwards which of their codes are already spent.

## 2. What it does

1. A user with two-factor turned on enters their password and lands on the two-factor page.
2. They switch to "Use your backup code", type one of their unused recovery codes and are signed in.
   - A mistyped code is refused and nothing is used up
3. That code is marked as spent and refused at every later sign-in, while the other codes keep working.
4. On their backup codes page in their profile, the spent code should then show struck through with the date it was used.

**Straightforwardness: 3 of 5.** The journey itself is simple, but what happens after a code is spent has real gaps that are easy to miss.

### Most surprising behaviours

- **(2)** Once any code has been spent, the backup codes page may fail to load at all. That page is the only place to generate new codes, so the user could be stuck with a shrinking set they can't see or replace. (6.1)
- **(3)** The same code typed in from two places at the same moment may be accepted twice, so a leaked code could open two sessions. (6.1)
- **(3)** Using a recovery code sends no email and leaves no record, and nobody tells the user how many codes they have left or prompts them to make more. (6.2)
- **(3)** Copying or printing the codes lists spent ones exactly like unused ones, so a saved list can look usable when it isn't. (6.1)
- **(3)** On a phone the code box opens a number pad and hints at six characters, but codes are nine letters and digits; after a wrong code the form also loses its "backup code" wording. (6.1)

## 3. Who can do what

Sources: `router.ex:189-193`, `:252-263`; `user_totp_controller.ex:7`, `:17-41`; `accounts.ex:472-502`; `user_auth.ex:288-311`, `:486-488`.
No policy module: every hop acts on the session's own user, and the code is checked only against that user's rows (`accounts.ex:474`, `:527`).

| Action | Signed out | Second factor pending (own account) | Fully signed in | Another user's pending session |
|--------|------------|-------------------------------------|-----------------|--------------------------------|
| Reach the backup code form | no, sent to log in | yes | no, sent to /projects | yes, own form only |
| Spend one of the account's codes | no | yes, once per code | no, sent to /projects | no, codes are matched per user |
| See which codes are spent | no | no, not until signed in | yes, inside a sudo window (flow-reauth-backup-codes), but 6.1 row 1 | no |

**Preconditions beyond role**
- The pending flag lives in the signed session cookie; the visitor cannot set it (`user_session_controller.ex:40-46`; `user_totp_controller.ex:33-41`).
- A code counts only if it matches exactly and its `used_at` is empty (`accounts.ex:487-488`).
- The exit hop needs a `sudo_session` token under five minutes old (`user_auth.ex:211-231`, `:443-475`; `user_token.ex:35`).

## 4. What it touches

**Reads**
- Hop 1, GET `/users/two-factor?authentication_type=backup_code`: `user_tokens`, `users` for the session (`user_auth.ex:288-299`); session `user_totp_pending` (`user_totp_controller.ex:33-41`)
- Hop 2, POST `/users/two-factor`: every `user_backup_codes` row for the user, decrypted (`accounts.ex:474`, `:525-530`; `user_backup_code.ex:13-15`); the user's `backup_codes` association again for the update (`accounts.ex:498`); session `user_return_to` (`user_auth.ex:64`)
- Hop 3, `/profile/auth/backup_codes`: `user_tokens` (session and `sudo_session`), every `user_backup_codes` row with `used_at` (`index.ex:37-44`; `index.html.heex:88-106`)

**Writes**
- Hop 2, valid code: the matched row's `used_at` set to `DateTime.utc_now()`, written by `put_assoc` of the whole list onto the user changeset and `Repo.update` (`accounts.ex:485-502`; `user.ex:51-52`)
- Hop 2, valid code: session `user_totp_pending` and `user_return_to` deleted; `_lightning_web_user_remember_me` cookie written when `user[remember_me]` is "true" (`user_auth.ex:486-488`, `:63-79`)
- Hop 2, wrong or spent code: nothing; the `with` stops before the update and the page re-renders (`accounts.ex:476-482`; `user_totp_controller.ex:25-29`)
- Hop 3: none (view only)

**Immediate side effects**
- Hop 2: redirect to the stored return path or `/projects` (`user_auth.ex:63-70`, `:514`); the return path journey is owned by flow-login-return-to S02
- No audit event, email, PubSub broadcast, Oban job or log line at any hop (`user_totp_controller.ex:17-31`; `accounts.ex:472-502`; `index.ex:27-44`)

**Deferred side effects**
- The spent code stays in `user_backup_codes` with `used_at` set until the user regenerates codes, which deletes every row (`accounts.ex:509-519`)
- Turning MFA off and on again keeps the same rows, spent ones included (`accounts.ex:423-431`, `:444-457`; profile-mfa 6.2)

**External, non-transactional effects**
- none

**Depends on config**
- none

**Product limits**
- Ten codes per set, each accepted once (`accounts.ex:510-513`, `:487-488`)
- Codes are nine characters from the base32 alphabet with "O" replaced by "X" (`user_backup_code.ex:29-35`)

## 5. Scenarios

```gherkin
Feature: Signing in with a recovery code
  In order to get into my account when I have lost my authenticator
  As a user with two-factor authentication
  I want each of my recovery codes to sign me in once, and only once

  @S01 @pending
  Scenario: A recovery code finishes sign-in and is marked spent
    # Value: someone who has lost or reset their phone still gets into their account, and the code they used is recorded as gone.
    Given "amara@example.org" has MFA enabled and ten unused recovery codes, one of them "K7Q2M9XPA"
    And I have entered the right password for "amara@example.org"
    And I am on "/users/two-factor"
    When I click "Use your backup code"
    And I enter "K7Q2M9XPA" and click "Verify"
    Then I am on "/projects"
    And visiting "/projects" no longer sends me to "/users/two-factor"
    And "K7Q2M9XPA" has a used time on "amara@example.org"'s account
    And her other nine codes have none
    # new.html.heex:76-89; user_totp_controller.ex:17-24, :53-58; accounts.ex:472-502; user_auth.ex:486-488, :63-70
    # user_totp_controller_test.exs:122-148 (redirect, pending flag cleared; used_at not asserted)
    # accounts_test.exs:531-533 (returns true; used_at not asserted)

  @S02 @pending
  Scenario: The same recovery code is refused at the next sign-in, and the rest still work
    # Value: a code that has been seen, photographed or left in an old printout opens the account only once, while a user working through their list can sign in again with the next one.
    Given I signed in as "amara@example.org" earlier today with recovery code "K7Q2M9XPA"
    And I have logged out
    And I have entered the right password for "amara@example.org" again
    When I choose "Use your backup code" and enter "K7Q2M9XPA"
    Then I see "Invalid two-factor authentication code"
    And visiting "/projects" sends me back to "/users/two-factor"
    When I choose "Use your backup code" and enter another of my unused recovery codes
    Then I am on "/projects"
    # router.ex:71 (log out); accounts.ex:485-494 (is_nil(backup.used_at)); user_totp_controller.ex:25-29
    # accounts_test.exs:535-541 (second use false, every other code still true); no controller test spends a code twice

  @S03 @pending
  Scenario: A mistyped recovery code spends nothing
    # Value: a typo on the way in does not burn one of the ten codes the user has to last them until they regenerate.
    Given "amara@example.org" has MFA enabled and ten unused recovery codes, one of them "K7Q2M9XPA"
    And I have entered the right password for "amara@example.org"
    When I choose "Use your backup code" and enter "K7Q2M9XPB"
    Then I see "Invalid two-factor authentication code"
    And none of my ten codes has a used time
    When I enter "K7Q2M9XPA" and click "Verify"
    Then I am on "/projects"
    # accounts.ex:476-482 (no update unless a code matched); user_totp_controller.ex:25-29
    # user_totp_controller_test.exs:123-148 (wrong code, then the right one succeeds; used_at not asserted)
```

The exit hop, a spent code shown struck through with "Code used on ..." on `/profile/auth/backup_codes`
(`index.html.heex:93-102`), has no scenario: on the code as read, rendering it should crash (6.1 row 1).
Write it once that row is fixed.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The exit hop renders a spent code's tooltip with `NaiveDateTime.truncate(backup_code.used_at, :second)`, but `used_at` is a `:utc_datetime_usec` field and loads as a `DateTime`, which `NaiveDateTime.truncate/2` should not accept (`FunctionClauseError`). Not executed; no test inserts a spent code (`factories.ex:385-389`). Same row as profile-backup-codes 6.1 row 1 | `index.html.heex:93-102`; `user_backup_code.ex:17` | after one recovery code sign-in, `/profile/auth/backup_codes` fails to render. "Generate new backup codes" lives only on that page and re-enrolling keeps the old rows (`accounts.ex:423-431`, `:444-457`), so the user can no longer see which codes are spent or replace them; only the print page, which does not mark spent codes (row 4), still lists them | fix |
| Single use is a read then a write with no lock and no conditional update: the codes are listed, matched in memory with `used_at` empty, then rewritten. Two submissions of the same code that both read before either writes should both be accepted. Read, not run | `accounts.ex:473-502` | a leaked code can open two sessions if submitted from two pending sessions at the same moment | fix |
| The code input is `inputmode="numeric"` with placeholder "XXXXXX" in the backup code variant too, while codes are nine letters and digits. Same as auth-two-factor 6.1 row 4 | `new.html.heex:29-37`; `user_backup_code.ex:29-35` | on a phone the recovery code opens a number pad with no letters, and the placeholder suggests six characters | fix |
| Copy and print list spent codes exactly like unused ones (profile-backup-codes 6.1 row 3; flow-reauth-backup-codes 6.1 row 5) | `index.html.heex:149`; `print.html.heex:33-38` | after this flow, a pasted or printed list in which the spent code looks usable | fix |
| After a wrong recovery code the re-rendered form loses its backup code title and help text and its switch link no longer leads back to the authenticator form; the retry still posts as a backup code. Same as auth-two-factor 6.1 row 1 | `user_totp_controller.ex:25-29`; `new.html.heex:55-66`, `:76-89` | "Authentication Code" above a field that only accepts a recovery code | fix |
| Every spent code's tooltip gets the id `backup-code-last-used-tooltip`; reachable only once row 1 is fixed and two codes are spent (profile-backup-codes 6.1 row 2) | `index.html.heex:98-99` | duplicate DOM ids; tooltips that may not attach | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Spending a recovery code sends no email, records no audit event and writes no log line, so an account owner whose codes were taken gets no sign of it | `user_totp_controller.ex:17-31`; `accounts.ex:472-502` | decide |
| Nothing tells the user how many codes they have left after spending one, or prompts them to regenerate when they run low or out | `user_auth.ex:63-70`; `new.html.heex:61-66` | decide |
| Codes are compared exactly: lowercase or a pasted trailing space is refused (auth-two-factor 6.2) | `accounts.ex:487` | decide |
| The spent code is kept with a timestamp rather than deleted, which is what would let the exit hop show it | `accounts.ex:489`; `index.html.heex:93` | preserve |
| `used_at` is set in UTC and the tooltip would show it raw, not in the viewer's time zone (profile-backup-codes 6.2; shared-local-datetime is the existing pattern) | `accounts.ex:489`; `index.html.heex:100` | decide |
| The write replaces the user's whole `backup_codes` association rather than updating one row; unchanged codes are not rewritten | `accounts.ex:496-502`; `user.ex:51-52` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Each attempt loads and decrypts all of the user's codes | `accounts.ex:474`, `:525-530`; `user_backup_code.ex:13` | no | preserve |
| No limit, delay or lockout on wrong recovery codes (auth-two-factor 6.5 and section 8 own the question for both code types) | `user_totp_controller.ex:17-31` | no | decide |

### 6.5 Things seen but not understood

- If the user regenerates codes in another signed-in browser between the list and the update in hop 2, `put_assoc` writes the old list onto a freshly preloaded association holding the new codes (`accounts.ex:474`, `:496-502`). Whether this deletes the new codes, raises a stale entry error, or fails cleanly was not traced. Disposition: decide.
- The migration declares `used_at` as `naive_datetime_usec` while the schema reads `utc_datetime_usec` (`20230721075131_create_user_backup_codes_table.exs:9`; `user_backup_code.ex:17`); profile-backup-codes 6.5 records the same mismatch, which is what makes 6.1 row 1 likely. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Does `/profile/auth/backup_codes` render once a code is spent (6.1 row 1)? Needs a run against the old app before the exit hop can get a scenario. (owner: engineering)
- Should spending a recovery code be atomic, for example a conditional update on `used_at IS NULL` (6.1 row 2)? (owner: security)
- Should spending a recovery code notify the account owner or record an audit event (6.2)? (owner: security)
- Should the user be told how many codes remain, or prompted to regenerate when few are left (6.2)? (owner: product)

## Proposed flows

- none. Referenced: `flow-login-return-to` (its S02 backup code row covers where a valid code redirects to; S01 here asserts only `/projects`), `flow-reauth-backup-codes` (the sudo gate in front of the exit hop), `flow-sso-login` (reaches the same entry hop).

## Proposed shared

- none. Referenced: shared-authenticated-session (every hop; its S03 is the pending gate this flow clears).
