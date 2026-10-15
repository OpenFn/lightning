---
id: profile-account
type: view
title: User profile › Account details (name, email, password)
status: not-started
owner:

trigger:
  old_route: /profile
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the user is signed in and admitted by shared-authenticated-session (`router.ex:349`, `:services` live_session `router.ex:351-355`)
    - the route is injected from config, not declared in the router (`config/config.exs:58-59`, `router.ex:340-356`); a deployment that drops it from `Lightning.Extensions.Routing` has no profile page
    - no role or project is required; every action applies to the signed-in user only (`edit.ex:55-59`, `components.ex:49-56`)

inherits:
  - shared-authenticated-session    # login redirect, lockout, sidebar, book-a-demo banner in the :banner slot (edit.html.heex:2-8), GDPR banner; S01 to S10
  - shared-project-header           # no-project header only: global picker S11, S12; role menu S17; account menu S18; confirmation banner S13, S14 (layout_components.ex:259-296)
  - shared-local-datetime           # "Created" date (components.ex:17); S01, S04, S05
  - shared-flash-messages   # added by lead (final pass)

url_params: []

config_variants:
  default: {}                                                                  # everything below was read under this one unless tagged
  gdpr-preferences: { lightning.gdpr_preferences: %{component: <module>, id: <dom id>} }   # config/config.exs:281-291, off by default; config.ex:292-294
  require-email-verification: { lightning.require_email_verification: true }   # header banner only, owned by shared-project-header S13, S14

inventory:
  routes:
    - live /profile  ProfileLive.Edit :edit          # config-injected, config/config.exs:58-59; router.ex:351-355
  events:
    - ProfileLive.FormComponent#validate_basic_info   # form_component.ex:120-127
    - ProfileLive.FormComponent#update_basic_info     # form_component.ex:86-97
    - ProfileLive.FormComponent#validate_email        # form_component.ex:110-117
    - ProfileLive.FormComponent#change_email          # form_component.ex:25-54
    - ProfileLive.FormComponent#validate_password     # form_component.ex:100-107
    - ProfileLive.FormComponent#save_password         # form_component.ex:57-83
  js_hooks: []                                        # LocalTimeConverter, Copy, Tooltip come through shared-local-datetime
  policies: []                                        # no policy check on :edit; Policies.Users :delete_account is only on :delete (edit.ex:61-70)
  workers: []
  api_endpoints: []
  emails:
    - email:update-email-warning                      # "Your OpenFn email was changed", user_notifier.ex:289-301; via flow-change-email-confirm
    - email:update-email-instructions                 # "Please confirm your new email", user_notifier.ex:270-284; via flow-change-email-confirm
  config:
    - :lightning, :gdpr_preferences                   # components.ex:37, :72-78
    - :lightning, Lightning.Extensions.Routing (routes, delete_modal metadata)   # config/config.exs:50-61
  not_reachable_here:
    - ProfileLive.Edit handle_info OauthTokenAdded / OauthTokenFailed and the VersionControl.subscribe in mount (edit.ex:15-17, :33-53); owned by flow-github-connect and profile-github
    - ProfileLive.Edit apply_action :delete, Policies.Users :delete_account, UserDeletionModal (edit.ex:61-86, components.ex:41-48); owned by profile-delete-account
    - ProfileLive.MfaComponent card (components.ex:57-61); owned by profile-mfa
    - ProfileLive.GithubComponent card (components.ex:62-66); owned by profile-github
    - ProfileLive.ExperimentalFeaturesComponent card (components.ex:67-71); owned by profile-experimental-features
    - shared-usage-limits-banner; this LiveView never mounts `:check_limits`, so `:banner` only carries the book-a-demo banner (edit.ex:11, init_assigns.ex:46-54)
    - shared-project-header breadcrumbs, project picker button and project menu items; this page renders the `:title` branch (edit.html.heex:9-13, layout_components.ex:283-296) and `Menu.profile_items` (menu.ex:91-110)
    - Accounts.request_email_correction/2, the rate-limited path into the same email change from auth-confirmation-required (accounts.ex:784-801)

related:
  - profile-mfa
  - profile-github
  - profile-experimental-features
  - profile-delete-account
  - profile-tokens                    # API tokens are revoked by a password change here (6.2)
  - auth-confirmation-required        # shares request_email_update/2 through request_email_correction/2
flows:
  - flow-account-revocation-teardown
  - flow-change-email-confirm
  - flow-resend-account-confirmation  # entered from the header banner, via shared-project-header S14
---

## 1. Purpose

Every signed-in user comes here to keep their own account accurate and secure: the name their
collaborators see, the address that receives password resets and alerts, and the password that
guards access to project data. If it didn't exist, a user who changed jobs, got married or suspected
their password leaked would need an administrator to fix it, and an attacker with a borrowed session
could quietly redirect the account's email or lock the owner out.

## 2. What it does

- Any signed-in user sees their name, sign-up date and email address, plus a privacy preferences card on instances that configure one
- **Update their details**
  - Any signed-in user changes their first name, last name and contact preference
  - Any signed-in user asks to change their email address, confirmed with their password; it only changes once they open the link sent to the new address
  - Any signed-in user changes their password, confirmed with their current password
- Any signed-in user reaches the account deletion page from here

**Straightforwardness: 3 of 5.** The forms are what you'd expect, but a password change reaches well beyond this page, and the email form gives away more than it should.

### Most surprising behaviours

- **(2)** Changing your password signs you out on every other device and deletes all your API tokens, so working scripts and integrations stop with no warning here. (S08, 6.2)
- **(3)** Asking for an email change sends the old address a message saying "Your OpenFn email was changed", even though nothing changes until the new address confirms, and it may never be confirmed. (6.1)
- **(3)** The email form checks your current password every time you leave the field, with no limit on attempts, and tells you if an address already belongs to another account. Someone at an unattended session can use it to guess the password or probe for accounts. (6.2)
- **(3)** Typing the wrong password on the email form says "Your passwords do not match.", which is confusing because you only typed one. (6.1)
- **(4)** "Contact preference" promises fewer messages if you pick "Critical", but nothing seems to read the setting, so it may do nothing at all. (6.5, 8)

## 3. Who can do what

Pulled from the code, not a policy module: this view calls no policy on `:edit` (`edit.ex:55-59`).
Every form is bound to `current_user` from the session (`components.ex:49-56`, `form_component.ex:12-22`).

| Action | Signed-in user (own account) | Superuser (own account) | Support user (own account) | Anyone, on another user's account |
|--------|------------------------------|-------------------------|----------------------------|-----------------------------------|
| See the page | yes | yes | yes | no |
| Change name and contact preference | yes | yes | yes | no |
| Request an email change | yes | yes | yes | no |
| Change password | yes | yes | yes | no |
| Open the delete account page | yes | yes | yes | no |

**Preconditions beyond role**
- Self only: there is no route parameter on `:edit`; the page always edits the session's user (`edit.ex:55-59`).
- Email change requires the current password (`accounts.ex:827-836`, `:849-857`).
- Password change requires the current password (`accounts.ex:919-923`, `user.ex:410-416`).
- An account without a stored password hash can never pass either check (`user.ex:394-405`).
- Whether deletion is then allowed is decided on the delete page (profile-delete-account), not here.

## 4. What it touches

**Reads**: `users` (via the session, shared-authenticated-session); `users` email lookup for uniqueness on every email validation (`user.ex:241-250`); `projects` / `project_users` for every project the user can reach, on mount (`hooks.ex:194-202`, `edit.ex:11`)

**Writes**:
- `users.first_name`, `users.last_name`, `users.contact_preference` (`accounts.ex:618-620`, `user.ex:314-318`)
- `user_tokens` insert, context `change:<current email>`, `sent_to` the new address (`accounts.ex:740-744`)
- `users.hashed_password`, then `user_tokens` delete of every token the user holds, all contexts, in one transaction (`accounts.ex:919-930`, `user_token.ex:236-238`)
- `user_tokens` insert, context `auth`, after a password change (`form_component.ex:76`, `accounts.ex:1051-1055`)

**Immediate side effects** (in the same request)
- Two emails sent inline through the mailer, not Oban, on an email change request: warning to the current address, then instructions to the new one (`accounts.ex:745-751`, `user_notifier.ex:49-60`); handed to flow-change-email-confirm
- `disconnect` broadcast on `user_socket:<id>` and `users_live:<id>` after a password change (`accounts.ex:934`, `user_auth.ex:163-166`); handed to flow-account-revocation-teardown
- Browser redirect to `/users/token_exchange/:token` after a password change (`form_component.ex:71-78`), which signs this browser back in and lands on `/projects` (`user_session_controller.ex:55-67`)
- No audit event is recorded for any of these changes (`accounts.ex:618-620`, `:740-756`, `:919-940` do not touch `Accounts.Audit`)

**Deferred side effects** (later, elsewhere)
- The email address only changes when the confirmation link is opened (`user_confirmation_controller.ex:34-49`, `accounts.ex:702-728`); owned by flow-change-email-confirm

**External, non-transactional effects**
- Email delivery via the configured mailer adapter: the change token is inserted before either email is sent, and a failure after the warning leaves the token and a sent warning with no instructions (`accounts.ex:740-756`)

**Depends on config**
- `:gdpr_preferences` renders a deployment-supplied component (`components.ex:37`, `:72-78`; `config/config.exs:281-291`)
- `Lightning.Extensions.Routing` must include `/profile` (`config/config.exs:58-59`)

**Product limits**
- Password 12 to 72 characters (`user.ex:258-266`)
- First and last name at most 255 characters, required (`user.ex:102-110`)
- Email at most 160 characters (`utils/validators.ex:20-28`)

## 5. Scenarios

```gherkin
Feature: Account details on the user profile
  In order to keep my account accurate and under my control
  As any signed-in user
  I want to change my name, email address and password myself

  @S01 @pending
  Scenario: The profile shows whose account this is
    # Value: someone on a shared machine can tell which account they are about to change.
    Given I am signed in as "Amara Okafor" with email "amara@example.org"
    When I open "/profile"
    Then I see the heading "Amara Okafor"
    And I see "Email: amara@example.org"
    And I see "Created:" followed by my sign-up date
    And I see the cards "Change basic information", "Change email", "Change password" and "Delete account"
    # components.ex:6-24; form_component.html.heex:12, :67, :111; components.ex:86-100
    # profile_live_test.exs:52-58, :63-64

  @S02 @pending
  Scenario: A user updates their name and contact preference
    # Value: collaborators and admins see the person's current name wherever the account appears, without an admin making the edit.
    Given I am signed in as "Amara Okafor"
    When I set "First name" to "Kylian" and "Last name" to "Mbappe"
    And I set "Contact preference" to "Anytime"
    And I click "Save"
    Then I see "User information updated successfully"
    And I see the heading "Kylian Mbappe"
    And "Contact preference" shows "Anytime"
    # form_component.ex:86-97; accounts.ex:618-620; user.ex:314-318; form_component.ex:129-138
    # profile_live_test.exs:88-109 (name only; contact preference is submitted but never asserted)

  @S03 @pending
  Scenario: A blank or unprintable name is refused
    # Value: an account never ends up with a name others can't read or identify.
    Given I am on "/profile"
    When I clear "First name"
    Then I see "This field can't be blank." under "First name"
    When I set "First name" to "Kylian" followed by a bell character and click "Save"
    Then I see "can't contain control characters"
    And my name is unchanged
    # user.ex:102-110; utils/validators.ex:81-90; errors.po:1-2
    # profile_live_test.exs:66-86

  @S04 @pending
  Scenario: A user asks to change their email with their password
    # Value: the account address only moves to an inbox the user proves they control, so password resets and alerts keep reaching them.
    Given I am signed in as "amara@example.org" with password "correct horse battery"
    When I set "New email address" to "amara@new.example.org"
    And I set "Enter password to confirm" to "correct horse battery"
    And I click "Update email"
    Then I see "You will receive an email with instructions shortly."
    And my email is still "amara@example.org"
    And the flow "flow-change-email-confirm" has started for "amara@new.example.org"
    # form_component.ex:25-38; accounts.ex:740-756
    # no LiveView test exercises this path; see 6.5

  @S05 @pending
  Scenario: An email change with the wrong password is refused
    # Value: someone using an unattended signed-in session can't redirect the account's email and take it over.
    Given I am signed in as "amara@example.org"
    When I set "New email address" to "attacker@example.org"
    And I set "Enter password to confirm" to a wrong password
    And I click "Update email"
    Then "Enter password to confirm" shows an error
    And no email is sent
    # accounts.ex:849-857; form_component.ex:28-31, :41-42
    # profile_live_test.exs:156-168 (asserts the copy listed in 6.1)

  @S06 @pending
  Scenario: An address that can't receive mail is refused before anything is sent
    # Value: a typo never sends a confirmation to a non-address and leaves the user waiting for mail that can't arrive.
    Given I am on "/profile"
    When I set "New email address" to "oops email" and leave the field
    Then I see "Email address not valid."
    And "Update email" is disabled
    # utils/validators.ex:20-28; errors.po:37-38; form_component.html.heex:92-96
    # profile_live_test.exs:184-190

  @S07 @pending
  Scenario: A failed email delivery is reported
    # Value: the user knows the confirmation didn't go out and can try again, instead of waiting for nothing.
    Given the mailer is failing
    When I request an email change with my correct password
    Then I see "Failed to request email update"
    # form_component.ex:44-52; accounts.ex:753-755

  @S08 @pending
  Scenario: A user changes their password
    # Value: a user who suspects their password has leaked can replace it immediately and cut off every other session.
    Given I am signed in with password "correct horse battery"
    When I set "New password" and "Confirm new password" to "a much longer phrase"
    And I set "Current password" to "correct horse battery"
    And I click "Update password"
    Then I am on "/projects"
    And I see "Password changed successfully."
    And I can sign in with "a much longer phrase"
    And the flow "flow-account-revocation-teardown" has started for my account
    # form_component.ex:57-78; accounts.ex:919-940; user_session_controller.ex:55-67
    # profile_live_test.exs:141-153 (cannot observe the socket disconnect; see 6.1)

  @S09 @pending
  Scenario: A password change with the wrong current password is refused
    # Value: someone using an unattended signed-in session can't change the password and lock the owner out.
    Given I am on "/profile"
    When I enter a valid new password twice
    And I set "Current password" to a wrong password
    And I click "Update password"
    Then I see "is not valid" under "Current password"
    And my password is unchanged
    And my other sessions are still signed in
    # user.ex:410-416; accounts.ex:919-930, :936-937; accounts_test.exs:1465-1472

  @S10 @pending
  Scenario: A new password must be long enough and typed the same twice
    # Value: accounts guarding health data keep a minimum password strength, and a typo can't lock the user out of their own account.
    Given I am on "/profile"
    When I set "New password" to "abc"
    Then I see "Password minimum length is 12 characters."
    When I set "New password" to "password1234" and "Confirm new password" to "password4567"
    Then I see "Your passwords do not match."
    And "Update password" is disabled
    # user.ex:258-266, :357-362; errors.po:27-30, :43-44; form_component.html.heex:144-151
    # profile_live_test.exs:112-139

  @S11 @pending
  Scenario: The profile leads to account deletion
    # Value: users can find how to remove their own account without asking an administrator.
    Given I am signed in
    When I click "Delete my account"
    Then I am on "/profile/<my user id>/delete"
    # components.ex:86-100; edit.html.heex:22-24; owned from there by profile-delete-account

  @S12 @pending @variant:gdpr-preferences
  Scenario: The configured GDPR preferences card is shown
    # Value: instances with privacy obligations give each user one place to manage their data preferences.
    Given the instance configures a GDPR preferences component
    When I open "/profile"
    Then I see the configured preferences component
    Given the instance does not configure one
    When I open "/profile"
    Then I do not see it
    # components.ex:37, :72-78; config/config.exs:291; profile_live_test.exs:801-815
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A wrong password on the email form shows "Your passwords do not match.", the copy for a mismatched new-password confirmation, because both errors use the msgid "does not match password" | `accounts.ex:853-855`; `errors.po:43-44`; asserted as-is in `profile_live_test.exs:156-168` | under "Enter password to confirm": "Your passwords do not match.", though only one password was typed | fix |
| After a password change the LiveView broadcasts `disconnect` to its own transport before it returns the redirect; both messages go from the same process to the transport in that order, so the transport may close before the redirect arrives, and the reconnect finds the session token already deleted | `accounts.ex:934`; `user_auth.ex:163-166`; `form_component.ex:62-78` | possibly the login page instead of "/projects" with "Password changed successfully."; not observable in LiveViewTest, which has no transport (`account_revocation_teardown_test.exs:12-14`) | decide (verify in a browser, then fix) |
| The warning sent to the current address is titled "Your OpenFn email was changed" while the change is only requested and may never be confirmed | `user_notifier.ex:289-301` | a recipient told their email was changed when it wasn't; belongs to flow-change-email-confirm once created | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| An address already used by another account shows "This value should be unique." on blur, so any signed-in user can test whether an address has an account | `user.ex:241-256`; `accounts.ex:833`; `errors.po:4-5` | decide |
| The email form checks the current password on every blur, before submit, with no rate limit; an unattended session can be used to guess the password | `accounts.ex:827-836`, `:849-857`; `form_component.ex:110-117`; `form_component.html.heex:75`, `:84` | decide |
| A password change deletes every user token, including API tokens (`api` context), so CLI and integration tokens stop working; the page gives no warning | `accounts.ex:919-930`; `user_token.ex:236-238`; `accounts_test.exs:1486-1495` | decide |
| The email change token is inserted before mail is sent and not removed if mail fails; a warning can go out with no instructions behind it | `accounts.ex:740-756` | decide |
| `/profile` sits in the config-injected `:services` live_session and `/profile/:id/delete` in `:default`, so "Delete my account" and the modal's return are full page loads, not live navigation | `router.ex:351-355`, `:324`; `components.ex:92`, `:47` | decide |
| "Save" is disabled until something valid has changed; "Update email" and "Update password" are disabled only while invalid | `form_component.html.heex:49-52`, `:95`, `:147` | preserve |
| Entering the current address shows "Please change your email" | `accounts.ex:839-847`; `errors.po:70-71`; `profile_live_test.exs:170-177` | preserve |
| A too-long password shows the untranslated "should be at most 72 character(s)", while too-short shows "Password minimum length is 12 characters."; the po entry has a stray `s` in `%{count}s` | `errors.po:32-35`; `accounts_test.exs:1454-1463` | preserve |
| Every "should be at least N character(s)" error is translated to "Password minimum length is N characters.", whatever the field | `errors.po:27-30` | preserve |
| Names are NFC-normalised and trimmed before validation; email is lowercased | `utils/validators.ex:81-90`, `:27` | preserve |
| Field errors appear only after the field has been touched | `components/new_inputs.ex:431-433` | preserve |
| A successful basic-info save push-navigates to `/profile`, remounting the page to pick up the new name from the session | `form_component.ex:91-92` | preserve |
| After a successful email change request the form keeps its values and stays submittable | `form_component.ex:36-39` | preserve |
| Contact preference labels: `critical` shows "Critical", `any` shows "Anytime"; default `critical` | `form_component.ex:129-138`; `user.ex:39-41` | preserve |
| A password change ends on `/projects` via `/users/token_exchange/:token`, not back on the profile | `form_component.ex:71-78`; `user_session_controller.ex:62-65` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `:user` assign on `:edit` | `edit.ex:58` | nothing in `edit.html.heex` or `Components` reads `@user`; they use `@current_user` |
| `title`, `return_to` and `action` passed to FormComponent | `components.ex:49-56`; `form_component.ex:12-22` | `title` and `return_to` are never assigned; `action` is assigned but `form_component.html.heex` never reads it |
| GDPR preferences card | `components.ex:72-78` | `config/config.exs:291` sets `false`; the component is supplied by a deployment, none ships in this repo (only a test mock, `test/support` GDPRHelpers) |
| `assigns[:banner]` usage-limits content | `edit.html.heex:2-8` | no `:check_limits` hook on this LiveView; only the book-a-demo banner can fill it, and that is hard-coded off (shared-authenticated-session 6.3) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `:assign_projects` loads every project the user can reach on each mount, and this page never reads `@projects` | `edit.ex:11`; `hooks.ex:194-202` | no | decide |
| Email change requests from `/profile` are unmetered by design; each submit sends two emails | `accounts.ex:788-791` | yes, inbox | decide |
| Email and password fields on the email form validate on blur only | `form_component.html.heex:75`, `:84` | yes | preserve |
| Password re-login token is valid for 30 seconds | `user_token.ex:36` | no | preserve |
| Email change link is valid for 7 days | `user_token.ex:33` | yes, in the flow | preserve |

### 6.5 Things seen but not understood

- `contact_preference` is stored and offered with a tooltip promising fewer messages for "Critical", but nothing in `lib/` reads it outside this form and the schema (`grep contact_preference lib/`). Presumably a downstream deployment or export consumes it. Disposition: decide.
- Test `"a user can change their email address"` (`profile_live_test.exs:179-194`) submits without a password and asserts only "Sending confirmation email...", which is the button's static `phx-disable-with` attribute (`form_component.html.heex:96`); it proves nothing about the request or the emails. No LiveView test covers a successful email change request. Disposition: preserve (write S04's test).
- Test `"validate password confirmation"` (`profile_live_test.exs:156-168`) actually submits the email form with a wrong current password; its name does not match what it checks. Disposition: preserve.
- Test `"update basic information"` submits `contact_preference` but never asserts it is saved (`profile_live_test.exs:88-109`). Disposition: preserve.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Who reads `contact_preference`? If nothing does, the control promises something the product doesn't do.
- Does the password-change redirect survive the self-disconnect in a real browser (6.1)?
- Is revoking API tokens on a password change intended, and should the page say so (6.2)?
- Is the email-existence disclosure and the unmetered, unthrottled password check on the email form acceptable (6.2)?
- Should a password change land the user back on `/profile` rather than `/projects`?

## Proposed flows

- `flow-account-revocation-teardown` (already proposed by shared-authenticated-session): a password change here deletes every session, sudo, auth and API token in one transaction and broadcasts `disconnect` on `user_socket:<id>` and `users_live:<id>` (`accounts.ex:919-940`, `user_auth.ex:163-166`); every other browser and device drops and is refused on reconnect, API tokens stop working, and this browser alone is signed back in through `/users/token_exchange/:token` and lands on `/projects` with "Password changed successfully." (`form_component.ex:71-78`, `user_session_controller.ex:55-67`). Surfaces: profile-account, pubsub:users_live:<user_id>, pubsub:user_socket:<user_id>, controller:user-token-exchange, projects-dashboard, any inheriting view, profile-tokens. This file asserts only the handoff (S08).
- `flow-change-email-confirm` (new): a request on the profile inserts a `change:<old email>` token and sends "Your OpenFn email was changed" to the old address and "Please confirm your new email" to the new one (`accounts.ex:740-756`, `user_notifier.ex:270-301`); opening `/profile/confirm_email/:token` while signed in as the same user within 7 days changes the email, sets `confirmed_at` and deletes the change tokens, then lands on `/projects` with "Email changed successfully." or "Email change link is invalid or it has expired." (`user_confirmation_controller.ex:34-49`, `accounts.ex:702-728`, `user_token.ex:33`, `:207-219`). The same path starts from auth-confirmation-required via `request_email_correction/2` (`accounts.ex:784-801`), and the confirm link is allowed through the lockout (`confirmation_lockout.ex:18-22`). Tests: `user_confirmation_controller_test.exs:310-380`, `accounts_test.exs:1243-1310`. Surfaces: profile-account, auth-confirmation-required, email:update-email-warning, email:update-email-instructions, controller:confirm-email, projects-dashboard. This file asserts only the handoff (S04).
- Referenced, not proposed: `flow-resend-account-confirmation` (header banner, through shared-project-header S14); `flow-github-connect` (the profile page is one of its exits, owned by profile-github).

## Proposed shared

- `shared-project-header` (already proposed by projects-dashboard): the side menu on non-project pages, `Menu.profile_items` with Projects, User Profile, Credentials and API Tokens, the current one marked; this page sets `active_menu_item: :profile` (`edit.ex:19`, `menu.ex:97-100`, `layout_components.ex:207-231`). Surfaces: projects-dashboard, credentials-index, profile-account, profile-tokens.

## Lead resolution (batch 6)

- `flow-account-revocation-teardown` and `flow-change-email-confirm` created.
- `shared-account-side-menu` was declined in batch 4: shared-project-header owns the side menu and account menu. Replaced in `inherits`.
