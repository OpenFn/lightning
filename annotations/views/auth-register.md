---
id: auth-register
type: view
title: Register
status: not-started
owner:

trigger:
  old_route: /users/register
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - signup-allowed only: `allow_signup` is true; otherwise GET and POST (and every path beneath /users/register) get a plain-text 404 before any controller runs (`router.ex:31-36`; `plugs/block_routes.ex:12-33`, `:62-64`)
    - the visitor has no valid session and no valid remember-me cookie; otherwise both GET and POST redirect to /projects (`router.ex:175-179`; `user_auth.ex:271-279`, `:514`)
    - first-setup-open only: a superuser exists; otherwise every request is redirected to /first_setup (`router.ex:29`; `plugs/first_setup.ex:11-33`)
    - linked from auth-login, auth-confirm-account and auth-reset-password, each only when `allow_signup` is true (`user_session_html/new.html.heex:84`; `user_confirmation_html/new.html.heex:51`, `edit.html.heex:44`; `user_reset_password_html/new.html.heex:52`, `edit.html.heex:66`)

inherits:
  - shared-authenticated-session     # the :browser pipeline (fetch_current_user, router.ex:28; user_auth.ex:175-206), its S11 first-setup gate (S12 here) and its S06 confirmation warning (S13 here). Its S01 to S05 gates do not run on this scope: it has :redirect_if_user_is_authenticated, not :require_authenticated_user
  - shared-flash-messages   # added by lead (final pass)

url_params: []                        # nothing is read from the query string; a pending return path lives in the session (flow-login-return-to)

config_variants:
  default: { allow_signup: false, init_project_for_new_user: false, require_email_verification: false, allow_first_setup: false, MAIL_PROVIDER: unset }   # bootstrap.ex:379-389; the page is blocked (S11)
  signup-allowed: { lightning.allow_signup: true }                                   # ALLOW_SIGNUP, bootstrap.ex:379-381; most scenarios are read under this one, as is the controller test (user_registration_controller_test.exs:10-15)
  init-project-for-new-user: { signup-allowed, lightning.init_project_for_new_user: true }   # INIT_PROJECT_FOR_NEW_USER, bootstrap.ex:383-385; user_registration_controller.ex:29
  require-email-verification: { signup-allowed, lightning.require_email_verification: true } # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389; changes the next page, not this one
  first-setup-open: { lightning.allow_first_setup: true, no superuser }                     # plugs/first_setup.ex:11-33; read in code only
  mail-provider-set: { signup-allowed, MAIL_PROVIDER: local | mailgun | smtp }              # bootstrap.ex:398-430; unset falls back to Swoosh.Adapters.Local (config.exs:83), so the confirmation email is never delivered off the box
  # Configured auth providers (SSO/OIDC) do not change this page: no "via external provider" control and no call to AuthProviders (user_registration_controller.ex:1-51; new.html.heex:1-119).

inventory:
  routes:
    - get /users/register  UserRegistrationController :new       # router.ex:178
    - post /users/register  UserRegistrationController :create   # router.ex:179
  events:
    - UserRegistrationController#new
    - UserRegistrationController#create
  js_hooks: []                         # the password reveal eye is an inline phx-click JS command (new_inputs.ex:685-695); see 6.5
  policies:
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279)
    - LightningWeb.Plugs.BlockRoutes with {"/users/register", :allow_signup, ...} (router.ex:31-36; plugs/block_routes.ex:12-64)
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)
  workers: []
  api_endpoints: []
  emails:
    - email:confirmation                # "Confirm your OpenFn account" welcome variant (user_notifier.ex:90-102), sent by Accounts.register_user/1 (accounts.ex:579-589)
  config:
    - :lightning, :allow_signup                  # router.ex:34
    - :lightning, :init_project_for_new_user     # user_registration_controller.ex:29
    - :lightning, :require_email_verification    # affects the landing after sign-up (layout_components.ex:261-277; accounts.ex:1362-1368)
    - :lightning, :allow_first_setup             # plugs/first_setup.ex:12
    - :lightning, Lightning.Mailer adapter       # MAIL_PROVIDER, bootstrap.ex:398-430
    - :lightning, :default_retention_period      # starter project's history retention (setup_utils.ex:196-197; config.exs:219)
    - Lightning.Extensions account_hook adapter  # Services.AccountHook.handle_register_user/1 (services/account_hook.ex:12-15)
  not_reachable_here:
    - LightningWeb.API.RegistrationController.create/2 (api/registration_controller.ex:4-13); POST /api/users/register, :api pipeline, not gated by allow_signup; 501 unless an extension provides it. See 6.5
    - Lightning.Accounts.deliver_user_confirmation_instructions/2 (accounts.ex:1177-1190) and its email variant (user_notifier.ex:107-119); the admin-creates-user path, not self-signup
    - SetupUtils.create_starter_project/3 with_workflow: true branch (setup_utils.ex:203-333); this view always passes false (user_registration_controller.ex:33-36)
    - Lightning.Accounts.deliver_user_confirmation_instructions/1 :already_confirmed and :rate_limited arms (accounts.ex:1163-1167); a brand-new account is unconfirmed and has no sends in its bucket

related:
  - lib/lightning_web/controllers/user_registration_controller.ex
  - lib/lightning_web/controllers/user_registration_html/new.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/plugs/block_routes.ex
  - lib/lightning_web/plugs/first_setup.ex
  - lib/lightning/accounts.ex                       # register_user/1 :579-589, change_user_registration/1 :600-602, deliver_user_confirmation_instructions/1 :1161-1175, build_email_token/1 :1135-1142
  - lib/lightning/accounts/user.ex                  # user_registration_changeset/2 :184-206, validate_email/1 :252-256, validate_password/2 :258-281
  - lib/lightning/extensions/account_hook.ex        # handle_register_user/1 :9-16
  - lib/lightning/utils/validators.ex               # validate_email_format/2 :20-28, validate_name/3 :81-90
  - lib/lightning/accounts/user_notifier.ex         # deliver/3 :49-60, deliver_confirmation_instructions/2 :90-102
  - lib/lightning/setup_utils.ex                    # create_starter_project/3 :191-201
  - lib/lightning/projects.ex                       # create_project/2 :562-575
  - test/lightning_web/controllers/user_registration_controller_test.exs
  - test/lightning_web/plugs/block_routes_test.exs
  - test/lightning/accounts_test.exs                # register_user/1 :562-665
  - test/lightning_web/controllers/user_auth_test.exs  # log_in_user/2 :162-190
  - auth-login                                      # "Log in" link; its S13 owns the "Register" link there
  - auth-reset-password                             # "Forgot your password?"
  - auth-confirm-account                            # where the confirmation email's link lands
  - projects-dashboard                              # default landing
  - workflow-editor-new                             # landing under init-project-for-new-user
  - first-setup
flows:
  - flow-register-first-workflow
  - flow-resend-account-confirmation
  - flow-login-return-to                # referenced; a pending return path is honoured only when the new user has no project (6.2)
---

## 1. Purpose

On instances that allow self-signup, this is how someone with no account gets one: they give their
name, email and a password, accept the host's terms, and are signed straight in. On instances that
create accounts centrally, the same route must stay shut so strangers can't join a server that holds
health data. If it is wrong, either new users on an open instance can't get started, or anyone can
create an account (or one with elevated rights) on an instance that never meant to allow it.

## 2. What it does

- **Create an account** (visitors, where self-signup is on)
  - Visitors give both names, a valid email and a password of at least 12 characters, and must accept the terms of service
  - An email that already has an account can't be registered again, and self-signup can never create a superuser
  - A failed submission keeps what the visitor typed
- **After sign-up**
  - New users are signed straight in and sent a confirmation email
  - Where configured, new users get a starter project and land on its new-workflow page
  - Where verification is required, unconfirmed new users are let in and warned to confirm
- **Who reaches the page**
  - Instances without self-signup refuse the page; a fresh install sends visitors to first setup
  - Signed-in visitors are sent to their projects instead
  - Visitors who already have an account reach log in or password reset

**Straightforwardness: 3 of 5.** A normal sign-up form, but several instance settings change what happens afterwards, and a few of those paths fail in ways you wouldn't expect.

### Most surprising behaviours

- **(2)** With starter projects on, someone named José or O'Brien gets an error page after their account has already been made; they aren't signed in, and retrying says the email is taken. (6.1)
- **(2)** When email confirmation isn't required, anyone can sign up with someone else's address and use the account indefinitely; the real owner can't register and has to reset the password to take it back. (6.5)
- **(3)** "Has already been taken" tells anyone whether an address has an account, even though the login page is careful not to. (S07, 6.5)
- **(3)** Nothing limits sign-ups, so one person can create accounts in bulk and make the server send email to any addresses they choose. (6.5)
- **(3)** Double-clicking "Register" may show an error page instead of a normal message, and the confirmation email is sent even when confirmation isn't required, with failed sends never shown. (6.1, 6.2)

## 3. Who can do what

Sources: `router.ex:21-43`, `:175-179`; `plugs/block_routes.ex:12-33`; `plugs/first_setup.ex:11-33`;
`user_auth.ex:271-279`; `user_registration_controller.ex:7-50`; `user.ex:184-206`. There is no policy
module; the gates are config and session state, not roles.

| Action | Signed-out visitor | Signed-in user | Any visitor, signup off | Any visitor, no superuser yet (first-setup-open) |
|--------|--------------------|----------------|-------------------------|--------------------------------------------------|
| See the page | signup-allowed only | no, redirected to /projects | no, plain-text 404 | no, redirected to /first_setup |
| Submit the form | signup-allowed only | no, redirected to /projects | no, plain-text 404 | no, redirected to /first_setup |
| Choose own role | no | n/a | n/a | n/a |
| Get a starter project as owner | init-project-for-new-user only | n/a | n/a | n/a |
| Follow "Log in" / "Forgot your password?" | signup-allowed only | n/a | n/a | n/a |

**Preconditions beyond role**
- The new account is always role `user`; `role` is not cast (`user.ex:184-195`, `:157-165`; schema default `user.ex:32`).
- A signed-in visitor with signup off gets the 404, not the redirect: BlockRoutes runs in `:browser` before `redirect_if_user_is_authenticated` (`router.ex:31-36`, `:176`; see shared-authenticated-session 6.2).
- First setup is checked before the signup block (`router.ex:29` precedes `:31`).
- require-email-verification: the new account is unconfirmed but not locked out for 48 hours (`accounts.ex:1362-1368`).

## 4. What it touches

**Reads**: `users` by email for the existence check (citext, unique: `priv/repo/migrations/20220405135153_create_users.exs:12`, `:19`; `user.ex:241-250`); `user_tokens` and `users` for the current session or remember-me cookie (`user_auth.ex:175-206`); `users` superuser count under first-setup-open (`plugs/first_setup.ex:28`); `project_users` and `projects` for the new user's projects (`user_registration_controller.ex:41`)

**Writes**
- `users` insert: first and last name (NFC, trimmed), email (lowercased), bcrypt hash, `contact_preference` (default `critical`), role `user`, `confirmed_at` nil (`extensions/account_hook.ex:9-16`; `user.ex:184-206`, `:269-281`; `validators.ex:20-28`, `:81-90`, `:346-351`; `accounts_test.exs:620-638`)
- `user_tokens` insert, context "confirm", for the email link (`accounts.ex:1135-1142`)
- `user_tokens` insert, context "session" (`user_auth.ex:28-31`)
- Session renewed and cleared, keeping only `user_return_to`; then `user_token` set (`user_auth.ex:54-58`, `:96-103`); `user_return_to` deleted on the default redirect (`user_auth.ex:63-70`)
- init-project-for-new-user: `projects` insert named `<first name>-demo`, env `main`, and `project_users` insert with role `owner` (`user_registration_controller.ex:28-37`; `setup_utils.ex:191-201`; `projects/project.ex:94-103`)

**Immediate side effects** (in the same request)
- PubSub `users:all` `%UserRegistered{}` (`accounts.ex:585`; `accounts/events.ex:6`, `:13-18`); no subscriber in `lib/`
- Email `email:confirmation` (welcome variant) to the new address, sent synchronously; the result is discarded (`accounts.ex:583-588`, `:1161-1175`; `user_notifier.ex:49-60`, `:90-102`)
- Hammer bucket `confirmation_request::<user id>` incremented (`accounts.ex:758-779`)
- init-project-for-new-user: PubSub `projects_events:all` `%ProjectCreated{}` (`projects.ex:572-574`; `projects/events.ex:81-86`, `:163`); no project-addition email (`setup_utils.ex:200`; `projects.ex:565-567`)
- Flash "User created successfully." (`user_registration_controller.ex:19`)
- No audit event

**Deferred side effects** (later, elsewhere)
- require-email-verification: 48 hours after sign-up an unconfirmed account is locked out of most pages (`accounts.ex:1358-1368`; shared-authenticated-session S04)

**External, non-transactional effects**
- Mail delivery through Mailgun or SMTP under mail-provider-set (`bootstrap.ex:398-430`; `user_notifier.ex:57`), after the user row has committed (`accounts.ex:580-588`)

**Depends on config**
- `allow_signup`: whether the page exists at all (S11)
- `init_project_for_new_user`: starter project and the landing page (S02, S03)
- `require_email_verification`: warning banner on the landing page (S13)
- `allow_first_setup`: redirect to /first_setup (S12)
- `MAIL_PROVIDER`: whether the confirmation email leaves the server (S14)

**Product limits**
- Password 12 to 72 characters (`user.ex:258-267`); email at most 160 characters (`validators.ex:26`); names at most 255 codepoints (`user.ex:102-110`)
- require-email-verification: 48 hours to confirm (`accounts.ex:1367`; `layout_components.ex:270`)

## 5. Scenarios

```gherkin
Feature: Register
  In order to start using Lightning on an instance that allows it
  As someone without an account
  I want to create one and be signed straight in

  @S01 @pending @variant:signup-allowed
  Scenario: Register a new account and land signed in
    # Value: a newcomer on an open instance gets an account and into the app without waiting on an administrator.
    Given self-signup is allowed
    And I am not logged in
    And "amara@example.org" has no account
    When I open "/users/register"
    And I fill in "First Name" with "Amara", "Last Name" with "Okafor", "Email" with "amara@example.org" and "Password" with "a long password"
    And I tick "I accept the terms of service"
    And I click "Register"
    Then I am logged in as "amara@example.org"
    And I am on "/projects"
    And I see "User created successfully."
    And I see "No projects found."
    # user_registration_controller.ex:13-21, :40-49; user_auth.ex:28-31, :63-70, :514
    # user_registration_controller_test.exs:41-60 (session token set, redirect to /projects, flash and empty list on the next page)

  @S02 @pending @variant:init-project-for-new-user
  Scenario: With starter projects on, sign-up lands on the new-workflow page
    # Value: a new user is put straight where they can build their first workflow.
    Given new users get a starter project
    When I register as "Emory H McLasterson"
    Then I am on "/projects/<starter project id>/w/new"
    And the flow "flow-register-first-workflow" has started
    # user_registration_controller.ex:16, :28-37, :40-45
    # user_registration_controller_test.exs:62-106 follows with get("/") and does not assert the redirect target

  @S03 @pending @variant:init-project-for-new-user
  Scenario: The starter project is named after me and I own it
    # Value: the new user controls the project they were given and can recognise it.
    Given new users get a starter project
    When I register with first name " Emory H   " and last name " McLasterson "
    Then my name is saved as "Emory H" "McLasterson"
    And I am the owner of a new project "emory-h-demo"
    And the project has no workflows, work orders or steps
    # user_registration_controller.ex:28-37; setup_utils.ex:191-201; validators.ex:346-351 (trim)
    # user_registration_controller_test.exs:62-106 asserts the trimmed names, the project name and zero work orders and steps; the owner role is not asserted

  @S04 @pending @variant:signup-allowed
  Scenario: The terms of service must be accepted
    # Value: everyone who joins an instance has agreed to its host's terms.
    Given self-signup is allowed
    When I submit the form without ticking "I accept the terms of service"
    Then I am on the register page
    And I see "Please accept the terms and conditions to register."
    And no account is created
    # user.ex:199-205; new_inputs.ex:1126-1131 (the hidden input posts "false" when unticked)
    # user_registration_controller_test.exs:135-144; accounts_test.exs:572-584
    # a POST that omits the field entirely is not refused (6.1)

  @S05 @pending @variant:signup-allowed
  Scenario Outline: Invalid details are refused
    # Value: every account has an address mail can reach and a password of minimum strength.
    Given self-signup is allowed
    When I register with <field> "<value>"
    Then I see "<message>"
    And no account is created

    Examples:
      | field    | value          | message                                     |
      | Email    | with spaces    | Email address not valid.                    |
      | Email    |                | can't be blank                              |
      | Password | short pass     | Password minimum length is 12 characters.   |
      | Password |                | can't be blank                              |
    # user.ex:252-267; validators.ex:20-28; priv/gettext/en/LC_MESSAGES/errors.po:27-30, :37-38
    # user_registration_controller_test.exs:108-117 (the email row); accounts_test.exs:563-570, :586-604
    # no test drives the short password through the controller

  @S06 @pending @variant:signup-allowed
  Scenario Outline: Names must be present and printable
    # Value: the name collaborators see and emails greet with is a real, readable name.
    Given self-signup is allowed
    When I register with first name "<first>" and last name "Smith"
    Then I see "<message>"
    And no account is created

    Examples:
      | first     | message                            |
      |           | can't be blank                     |
      | Ann\u0007 | can't contain control characters   |
    # user.ex:102-110; validators.ex:81-90, :358-360
    # user_registration_controller_test.exs:119-133 (control character, refuted user); accounts_test.exs:679-688 covers whitespace-only names for the superuser changeset only

  @S07 @pending @variant:signup-allowed
  Scenario: An address that already has an account can't register again
    # Value: one account per address, so log in, password reset and alerts reach one person.
    Given "amara@example.org" already has an account
    When I register with email "Amara@Example.org"
    Then I see "has already been taken"
    And no second account is created
    # user.ex:241-256; validators.ex:27 (lowercased); accounts_test.exs:606-618 (both cases, and no UserRegistered event)
    # the response tells anyone which addresses have accounts (6.5)

  @S08 @pending @variant:signup-allowed
  Scenario: Self-signup can't choose its own role or password hash
    # Value: a stranger on an open instance can never sign themselves up as a superuser.
    Given self-signup is allowed
    When I post a registration that also carries "role" = "superuser" and a "hashed_password"
    Then the account is created with role "user"
    And its password is the one I typed, hashed by the server
    # user.ex:157-165, :184-195 (neither role nor hashed_password is cast), :32 (default role)
    # accounts_test.exs:620-638 (role :user), :652-664 (supplied hash ignored); no test posts a role

  @S09 @pending @variant:signup-allowed
  Scenario: Signing up starts a fresh session
    # Value: a session id planted in my browser before sign-up can't be used to ride my new account.
    Given my browser holds a session with other values in it
    When I register successfully
    Then the session id is renewed
    And nothing from the old session remains except the page I was going to
    # user_registration_controller.ex:20; user_auth.ex:54-58, :96-103; user_auth_test.exs:162-190

  @S10 @pending @variant:signup-allowed
  Scenario: A signed-in visitor is sent to their projects
    # Value: someone already logged in isn't offered a second account by mistake.
    Given I am logged in
    When I open "/users/register"
    Then I am on "/projects"
    # router.ex:176-179; user_auth.ex:271-279; user_registration_controller_test.exs:29-36

  @S11 @pending
  Scenario Outline: Instances without self-signup refuse the page
    # Value: an instance that creates accounts centrally can't be joined by strangers, whatever URL spelling they try.
    Given self-signup is disabled
    When I <method> "<path>"
    Then the response is a 404 with the text "Self-signup has been disabled for this instance. Please contact the administrator."
    And no account is created

    Examples:
      | method | path               |
      | GET    | /users/register    |
      | GET    | /users/register/   |
      | GET    | ///users/register  |
      | GET    | /users/%72egister  |
      | POST   | /users/register    |
    # router.ex:31-36; plugs/block_routes.ex:12-64
    # block_routes_test.exs:23-40, :69-99 (GET spellings through the :browser pipeline); the POST row is not tested but the plug ignores the method

  @S12 @pending @variant:first-setup-open
  Scenario: A fresh install sends visitors to first setup
    # Value: nobody creates the first account through self-signup before the administrator exists.
    Given first setup is allowed
    And there is no superuser
    When I open "/users/register"
    Then I am on "/first_setup"
    # router.ex:29; plugs/first_setup.ex:11-33; shared-authenticated-session S11 owns the gate
    # first_setup_test asserts on "/", not on this route

  @S13 @pending @variant:require-email-verification
  Scenario: A new account is let in and told to confirm its email
    # Value: a new user can start work straight away and is told how long they have before access stops.
    Given email verification is required
    When I register successfully
    Then I am logged in
    And the warning in shared-authenticated-session S06 shows my 48-hour confirmation deadline
    # accounts.ex:1358-1368; layout_components.ex:261-277; user_auth.ex:305-306
    # user_registration_controller_test.exs:10-15 runs under this variant but asserts no banner

  @S14 @pending @variant:signup-allowed
  Scenario: Signing up sends a confirmation email
    # Value: the user has a way to prove they own the address their account is tied to.
    Given self-signup is allowed
    When I register as "amara@example.org"
    Then an email "Confirm your OpenFn account" is sent to "amara@example.org"
    And the flow "flow-resend-account-confirmation" has started
    # accounts.ex:583-588, :1135-1142, :1161-1175; user_notifier.ex:90-102
    # sent under every variant, including when verification is not required (6.2); under default MAIL_PROVIDER it lands in the local mailbox only
    # no test asserts the email

  @S15 @pending @variant:signup-allowed
  Scenario: Existing users are pointed to log in or reset their password
    # Value: someone who already has an account signs in instead of trying to make a duplicate.
    Given self-signup is allowed
    When I open "/users/register"
    Then I see a "Log in" link to "/users/log_in"
    And I see a "Forgot your password?" link to "/users/reset_password"
    # new.html.heex:94-110; user_registration_controller_test.exs:21-27 (asserts "Log in" text only)

  @S16 @pending @variant:signup-allowed
  Scenario: A failed submission keeps the names and email I typed
    # Value: one mistake doesn't make the visitor retype the whole form.
    Given self-signup is allowed
    When I submit "Amara", "Okafor", "amara@example.org" with a password that is too short
    Then the form shows "Amara", "Okafor" and "amara@example.org" again
    And the password error is shown under "Password"
    # user_registration_controller.ex:23-24 renders the changeset built from the posted params; new_inputs.ex:431-446
    # no test asserts the retained values; the password is retained too (6.1)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The starter project is created with `{:ok, project} =` from a name built as `downcase(first_name) <> "-demo"` with only spaces replaced. A first name with an apostrophe, accent, non-Latin letter or other character outside `[a-z0-9-]` fails the project name format and raises MatchError. By then the user row is committed, the confirmation email sent and the event broadcast | `user_registration_controller.ex:16`, `:28-37`; `setup_utils.ex:191-201`; `projects/project.ex:108`; `accounts.ex:579-589` | init-project-for-new-user: "José" or "O'Brien" gets a 500, is not logged in, and on retry is told the email "has already been taken" | fix |
| `terms_accepted` is checked with `validate_change` only, never `validate_required`, so a POST without the key registers without accepting the terms. The rendered form always posts it (hidden "false"), so only a hand-built request reaches this | `user.ex:199-205`; `new_inputs.ex:1126-1131`; `user_registration_controller_test.exs:41-60` (registers with `valid_user_attributes`, which has no `terms_accepted`, `accounts_fixtures.ex:12-19`) | an account with no recorded acceptance of the terms | fix |
| The insert is `Repo.insert(struct(User, data))` with no `unique_constraint`; uniqueness is only the pre-check query. Two submissions with the same email that pass the check together hit the unique index and raise | `extensions/account_hook.ex:9-16`; `user.ex:241-256`; `priv/repo/migrations/20220405135153_create_users.exs:19` | a 500 (Ecto.ConstraintError) on a double-clicked "Register" instead of "has already been taken" | fix |
| On a validation error the form is re-rendered from the changeset, whose password change is kept (hashing only happens on a valid changeset), and the password input renders `value={Form.normalize_value(@type, @value)}`. Same mechanism as auth-login 6.1; phoenix_html 4.3.0 is locked and deps were not installed, so this was read, not run | `user.ex:269-281`; `user_registration_controller.ex:23-24`; `new_inputs.ex:651-672`; `mix.lock:101` | the password field arrives pre-filled after an error, and the plain password sits in the response HTML | fix (verify first) |
| The max-length password translation has msgid `"should be at most %{count}s character(s)"` (stray `s`), so it never matches and the raw Ecto message shows, while the min-length message is translated | `priv/gettext/en/LC_MESSAGES/errors.po:27-35`; `accounts_test.exs:603` | "Password minimum length is 12 characters." but "should be at most 72 character(s)" for the opposite error | fix |
| A POST without a `user` map matches no `create/2` clause | `user_registration_controller.ex:13` | a 400 (ActionClauseError) instead of the form. Not reachable from the rendered form | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| A signed-in visitor with signup off gets the plain-text 404, not the redirect to /projects; already recorded in shared-authenticated-session 6.2 | `router.ex:31-36`, `:176` | decide |
| A pending return path is honoured only when the new user has no project; under init-project-for-new-user the user always goes to the starter project's /w/new. Already recorded in flow-login-return-to 6.2 | `user_registration_controller.ex:40-49`; `user_auth.ex:63-70` | decide |
| The confirmation email is sent even when `require_email_verification` is false, and with MAIL_PROVIDER unset it goes to Swoosh's local mailbox; the delivery result is discarded, so a failed send is invisible to the user | `accounts.ex:583-588`; `config.exs:83`; `bootstrap.ex:398-400` | decide |
| Sign-up never sets the remember-me cookie; there is no "Keep me logged in" option here | `user_registration_controller.ex:20-21`, `:48`; `user_auth.ex:72-79` | preserve |
| `contact_preference` is cast from the POST, so a hand-built request can choose `any`; the form has no control for it | `user.ex:163-164`, `:189-195`; `accounts_test.exs:640-650` | decide |
| Labels "First Name" and "Last Name" are title case; "Email" and "Password" are not | `new.html.heex:31-62` | decide |
| No hint of the 12-character minimum before the first failed submit | `new.html.heex:55-63`; `user.ex:261` | decide |
| Password length is counted in codepoints (12 to 72), then, if valid, in bytes (8 to 72); a password of up to 72 multibyte characters but over 72 bytes passes the first check and fails the second | `user.ex:261`, `:273-276` | decide |
| Two people with the same first name both get a project named `<name>-demo`; repeated inner spaces become repeated hyphens ("emory--h-demo") | `user_registration_controller.ex:30-31` | decide |
| The terms text always links to openfn.org/terms, whoever hosts the instance | `new.html.heex:77-85` | decide |
| Signup disabled is a bare `text/plain` 404, not a page | `plugs/block_routes.ex:14-19` | decide |
| Validation errors re-render with status 200 | `user_registration_controller.ex:23-24`; `user_registration_controller_test.exs:114`, `:141` | decide |
| Page title is the root layout fallback "Lightning · OpenFn Lightning"; no `page_title` is assigned | `root.html.heex:16-18`; `user_registration_controller.ex:7-11` | decide |
| The terms checkbox has no `required` attribute; terms are enforced only on the server | `new.html.heex:67` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Error and info flash blocks in the template | `new.html.heex:18-27` | nothing redirects to /users/register with a flash, and `create/2` re-renders without one; only a leftover flash from an earlier request would show |
| The empty `grid-cols-6` block under the form | `new.html.heex:114-116` | renders an empty `col-span-3` div |
| `redirect_user/2` `[project | _]` arm without init-project-for-new-user | `user_registration_controller.ex:43-45` | a brand-new user has no `project_users` unless the starter project was created or an account-hook extension adds one |
| `%UserRegistered{}` on `users:all` | `accounts.ex:585`; `accounts/events.ex:13-18` | no subscriber in `lib/`; only `accounts_test.exs:620-631` listens. Presumably for extensions |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The confirmation email is delivered synchronously inside the POST, so a slow SMTP relay or Mailgun call delays the redirect | `accounts.ex:583-588`; `user_notifier.ex:57` | yes, a slow "Register" | decide |
| Bcrypt hashes the password on every valid submission | `user.ex:276` | a fraction of a second | preserve |
| Confirmation mail is rate limited to 3 per account per 15 minutes; a new account's first send is always allowed, and a limiter error allows the send | `accounts.ex:758-779` | no | preserve |

### 6.5 Things seen but not understood

- No rate limiting, CAPTCHA or throttling on POST /users/register, per IP or otherwise (`user_registration_controller.ex:13-26`; `router.ex:175-179`). The confirmation-mail limiter is keyed on the new user's id (`accounts.ex:762-766`), so it never applies across sign-ups. Anyone can create accounts in bulk on an open instance, and each one makes the server send an email to an address of the requester's choosing. Stated as a finding, not a behaviour to keep (section 8).
- The "has already been taken" error tells anyone whether an address has an account (`user.ex:241-250`), unlike login, which uses one message for both cases (auth-login S02). Timing also differs: a taken address skips Bcrypt because the changeset is invalid (`user.ex:273`). S07 records the uniqueness rule; the disclosure is not a behaviour to keep without a decision (section 8).
- Under default verification settings, anyone can register someone else's address and use the account indefinitely without confirming it (`accounts.ex:1362-1368` only locks out when verification is required). The real owner then can't register and must use password reset to take it over.
- POST /api/users/register sits in the `:api` pipeline, outside BlockRoutes, so `allow_signup` does not gate it (`router.ex:104-107`; `api/registration_controller.ex:4-13`). It is a 501 unless an extension provides `:registration_controller`; whether an extension's controller checks `allow_signup` was not checked.
- No audit event or log line for a self-signup (`accounts.ex:579-589`; `user_registration_controller.ex:13-26`).
- Under init-project-for-new-user the flash "User created successfully." is set before redirecting into the LiveView at /w/new; whether the editor renders it was not checked.
- The password reveal eye uses a `phx-click` JS command on a controller-rendered page with no LiveView container (`new_inputs.ex:685-695`); whether it runs here was not confirmed (same as auth-login 6.5).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should registration be rate limited or protected by a CAPTCHA, given each sign-up sends mail to an arbitrary address (6.5)? (owner: security)
- Should "has already been taken" be replaced with a response that does not reveal whether an address has an account, for example always "check your email" (6.5)? (owner: security)
- Should an unconfirmed self-signup be usable indefinitely when verification is not required (6.5)? (owner: security)
- Does POST /api/users/register need to respect `allow_signup` (6.5)? (owner: security)
- Should the starter project name be derived so that any first name works, and should project creation share the registration transaction (6.1)? (owner: product)
- Should the confirmation email be sent when verification is not required, and should a failed send be surfaced (6.2)? (owner: product)
- Should the terms link point at the host's own terms rather than openfn.org (6.2)? (owner: product)
- Should the signup-disabled response be a proper page (6.2)? (owner: product)
- Does a validation error echo the submitted password into the HTML (6.1)? Verify in a browser, then fix. (owner: security)

## Proposed flows

- `flow-register-first-workflow`: under init-project-for-new-user, a new user registers, a starter project `<first name>-demo` is created with them as owner, and they are redirected to that project's new-workflow landing screen (`user_registration_controller.ex:16`, `:28-49`). Proposed first by workflow-editor-new, which asserts the landing. Surfaces: auth-register, controller:user-registration, workflow-editor-new. This file asserts only the start (S02) and the project it creates (S03).
- `flow-resend-account-confirmation`: a self-signup is sent the welcome "Confirm your OpenFn account" email with a `/users/confirm/:token` link; opening it confirms the account and clears the require-email-verification warning (`accounts.ex:583-588`, `:1135-1142`, `:1161-1175`; `user_notifier.ex:90-102`; `router.ex:229-230`). Distinct from flow-resend-account-confirmation, which starts from the banner's reminder email (`user_notifier.ex:121-133`). Surfaces: auth-register, email:confirmation, auth-confirm-account, projects-dashboard. This file asserts only the send (S14). If the lead prefers, it could fold into flow-resend-account-confirmation as a second entry.
- Referenced, not proposed: flow-login-return-to (the return path is honoured on the no-project branch; 6.2).

## Proposed shared

none. Referenced: shared-authenticated-session (the :browser pipeline; its S11 first-setup gate in S12; its S06 confirmation warning in S13; its 6.2 row on BlockRoutes ordering).

## Lead resolution (batch 8)

- `flow-register-first-workflow` created. `flow-register-confirm-account` folded into `flow-resend-account-confirmation`, which now covers the first confirmation email as well as resends.
