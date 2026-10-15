---
id: admin-user-edit
type: view
title: Admin settings › New user and edit user
status: not-started
owner:

trigger:
  old_route: /settings/users/new, /settings/users/:id
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session (`router.ex:189-190`; both routes are in the `:settings` live_session, `router.ex:268-270`)
    - the viewer is a superuser (`user_live/edit.ex:8`; shared-admin-space)
    - "/settings/users/:id needs an existing user id: `Accounts.get_user!/1` raises otherwise (`user_live/edit.ex:24-29`; `accounts.ex:372`), see 6.2"
    - entered from "New User" and the row "Edit" action on admin-users (its S08)

inherits:
  - shared-admin-space               # gate (S02, S03), settings layout and side menu with "Users" current (S01; edit.ex:15-16), demotion handoff (S06)
  - shared-authenticated-session     # login redirect (S01), revoked and disabled sessions (S02), TOTP and lockout gates (S03 to S06), sidebar (S07); S08 to S10 not rendered on the settings layout; S11 is where 6.1 row 1 lands
  - shared-flash-messages            # admin toasts that stay until clicked (S07); the flash carried across the navigate to /settings/users (S05)
  - shared-project-header            # no-project parts only, through LayoutComponents.header (edit.html.heex:2-6): confirmation banner (S13, S14), keyboard picker (S04, S06, S08, S10 to S12), account menu (S18)

url_params:
  - name: id (path segment of /settings/users/:id)
    set_by: admin-users (row "Edit", user_live/components.ex:145-147)
    effect: loads that user into the form with `Accounts.get_user!/1` (edit.ex:24-29); unknown or malformed ids raise (6.2)

config_variants:
  default: {}                                                                  # read under this one unless a scenario is tagged
  first-setup-open: { lightning.allow_first_setup: true }                      # bootstrap.ex:234, set when SERVICE_ACCOUNT_PUBLIC_KEY is unset; what makes 6.1 row 1 reachable (plugs/first_setup.ex:11-33)
  first-setup-closed: { lightning.allow_first_setup: false }                   # SERVICE_ACCOUNT_PUBLIC_KEY set; 6.1 row 1 then leaves no superuser and no way back in the UI
  require-email-verification: { lightning.require_email_verification: true }   # an admin-created account that never confirms is locked out after 48 hours (accounts.ex:1360-1368); S02
  custom-account-hook: { lightning.account_hook: "a deployment's AccountHooking module" }   # replaces the insert behind "Save" on /new (config/config.exs:45; services/account_hook.ex:23-28); not read

inventory:
  routes:
    - live /settings/users/new  UserLive.Edit :new       # router.ex:269
    - live /settings/users/:id  UserLive.Edit :edit      # router.ex:270
  events:
    - UserLive.FormComponent#validate                    # form_component.ex:26-38
    - UserLive.FormComponent#support_heads_up            # form_component.ex:40-44
    - UserLive.FormComponent#save                        # form_component.ex:46-48, :57-104; also the entry listed by flow-account-revocation-teardown
  js_hooks: []                                           # the toggle and checkbox are plain inputs (new_inputs.ex:865-905, :1118-1145); Tooltip hook only if the toggle had a tooltip, it has none
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21), through LightningWeb.Hooks :ensure_admin (hooks.ex:31-53); owned by shared-admin-space
  workers: []                                            # a date typed into "Scheduled Deletion" makes the account eligible for oban:accounts-purge-deleted, owned by flow-account-revocation-teardown
  api_endpoints: []
  emails:
    - email:confirmation (admin-created variant, "Confirm your OpenFn account", user_notifier.ex:107-119)   # S02; end to end in proposed flow-admin-created-account-confirm
  config:
    - :lightning, :allow_first_setup                     # 6.1 row 1 (plugs/first_setup.ex:12)
    - :lightning, :account_hook                          # config/config.exs:45
  not_reachable_here:
    - User.changeset/2 and details_changeset/2 cast `confirmed` (user.ex:94, :298, :148-153) and `contact_preference` (user.ex:92); the form has no such input, only the API sends them (6.3)
    - Accounts.deliver_user_confirmation_instructions/1 (accounts.ex:1161-1175), the rate-limited variant; this view calls the /2 variant
    - UserLive.Index and its table and deletion modal; owned by admin-users
    - Lightning.Accounts superuser_changed telemetry consumers; none in lib/ (6.5)

related:
  - admin-users                       # list this form returns to; "Cancel" and "Save" both land there
  - admin-audit                       # where the `user` `created` and `updated` events written here are read
  - first-setup                       # 6.1 row 1 sends the instance back to it
  - auth-confirm-account              # where the admin-created confirmation link lands
  - lib/lightning_web/live/user_live/edit.ex
  - lib/lightning_web/live/user_live/edit.html.heex
  - lib/lightning_web/live/user_live/form_component.ex
  - lib/lightning_web/live/user_live/form_component.html.heex
  - lib/lightning/accounts.ex         # create_user/2 :146-165, update_user/3 :177-201, revoke_contexts :204-221, maybe_audit_update :223-230, superuser_changes :233-240, superuser_changed :242-260, get_user!/1 :372, change_user/2 :903-905, build_email_token :1135-1142, deliver_user_confirmation_instructions/2 :1177-1190, has_one_superuser?/0 :1341-1344
  - lib/lightning/accounts/user.ex    # RolesEnum :16-19, changeset/2 :85-100, details_changeset/2 :287-305, maybe_clear_scheduled_deletion :442-447
  - lib/lightning/accounts/audit.ex
  - lib/lightning/extensions/account_hook.ex
  - test/lightning_web/live/user_live_test.exs        # :43-75, :77-107, :109-135, :137-174, :176-217, :219-299, :740-749
  - test/lightning/accounts_test.exs                  # :1351-1380, :1382-1434, :1792-1816
  - test/lightning_web/live/confirmation_lockout_live_test.exs   # :24-31, :43-68 (/settings/users/new only)
flows:
  - flow-account-revocation-teardown        # disabling, and changing password, email, role or support access, start it here (S08); its S01 row 2 and 3, S04, S05, S08
  - flow-change-email-confirm               # cross-reference only: an admin email change skips that confirmation (S09)
  - flow-first-superuser-sign-in            # answers its 6.5: the last superuser can be demoted or disabled here (6.1 rows 1 and 2)
  - flow-admin-created-account-confirm
---

## 1. Purpose

Superusers use this form to create accounts and to change any existing one: names, email, password,
role, support access, disabled state and scheduled deletion. It is how an instance without self
sign-up gets its users, how a departed staff member is cut off, how someone locked out of their
inbox gets a new address, and how another administrator is appointed. Every save here changes
what that person can reach across every project, so a mistake either locks out someone who needs
access or leaves access with someone who should have lost it.

## 2. What it does

- **Create accounts**
  - Superusers create a user or another superuser, with name, email, password, role and support access
  - The new person is sent a confirmation email naming the superuser who created them
- **Change accounts**
  - Superusers change any account's names, email, password, role and support access; a blank password keeps the current one
  - Superusers change an email without the owner confirming it
  - Superusers disable an account so it can't sign in
- **Guard rails**
  - The form checks names, email and password as they are typed and won't save an invalid account
  - Granting support access warns how far it reaches, and scheduled deletion is offered only for non-superuser accounts
  - Superusers leave the form without saving
- **Consequences of a save**
  - Changes that reduce or move access sign the person out everywhere; name changes don't
  - Every create and change is recorded in the audit trail under the superuser who made it

**Straightforwardness: 2 of 5.** It looks like an ordinary user form, but a few saves have instance-wide consequences that nothing on the form warns about.

### Most surprising behaviours

- **(2)** Nothing stops the last superuser being demoted. On instances where first setup is allowed, every visitor, signed in or not, is then sent to the setup page and can make themselves administrator of an instance full of data. (6.1)
- **(2)** The last superuser can also be disabled, which leaves nobody able to reach any admin page and no way back in the app. Superusers can demote, disable or change their own account here too, and are signed out mid-save. (6.1)
- **(2)** "Scheduled Deletion" is a free text box. A date typed here revokes every token and blocks sign-in like a deletion, but sends no deletion email, doesn't disable the account, and a badly formatted value shows no error until you save. (6.2)
- **(3)** Promoting someone to superuser signs them out everywhere, and silently cancels any scheduled deletion they had. (6.2)
- **(3)** An admin email change keeps the account marked as confirmed at an address nobody verified, tells neither address, and a superuser-set password is never sent to the owner. (S09, 6.2)

## 3. Who can do what

Sources: `policies/users.ex:19-21`; `hooks.ex:31-53`; `user_live/edit.ex:8`;
`user_live/form_component.ex:26-104`; `user.ex:287-305`, `:442-447`. Roles are `:user` and
`:superuser` (`user.ex:16-19`); `support_user` is a flag the gate ignores.

| Action | Signed out | Signed-in non-superuser | Superuser |
|--------|-----------|-------------------------|-----------|
| Open /settings/users/new or /settings/users/:id | no (login) | no (shared-admin-space S02) | yes |
| Create a user or a superuser | no | no | yes |
| Change names, email, password, role, support access of any account | no | no | yes, including their own and other superusers |
| Disable any account | no | no | yes, including their own and the last superuser (6.1) |
| Demote a superuser | no | no | yes, including themselves and the last superuser (6.1) |
| Set "Scheduled Deletion" | no | no | yes, only while the role field reads "User" |
| Confirm an account's email | no | no | no (no control; 6.3) |

**Preconditions beyond role**
- The superuser check runs once, at mount (`edit.ex:8`); `validate`, `support_heads_up` and `save` check nothing themselves (`form_component.ex:26-48`). A superuser demoted while the form is open loses it through the revocation broadcast (shared-admin-space S06), not here.
- No guard counts remaining superusers or compares the target with the actor (`accounts.ex:177-201`; `user.ex:287-305`).
- Saving as a superuser clears any scheduled deletion (`user.ex:442-447`).

## 4. What it touches

**Reads**: one `users` row by id on /:id (`edit.ex:24-29`; `accounts.ex:372`); `users` by email on every validate and save that changes the email, for uniqueness (`user.ex:241-256`); the actor's own row via the session (inherited).

**Writes**
- Create: `users` insert through the account hook (`accounts.ex:146-161`; `extensions/account_hook.ex:28-33`) and, with the actor, an `audit_events` row `user` `created` in the same transaction (`accounts.ex:163-165`; `accounts/audit.ex:15-19`); then, outside that transaction, a `user_tokens` row in context `confirm` (`accounts.ex:1135-1142`, `:1177-1190`)
- Edit: one transaction updating `users`, inserting an `audit_events` row `user` `updated` when anything recorded changed, and deleting `user_tokens` in context `session`, or in every context when a scheduled deletion is set (`accounts.ex:181-201`, `:204-230`, `:604-612`; `accounts/audit.ex:28-46`)

**Immediate side effects** (in the same request)
- Create: email "Confirm your OpenFn account" to the new address, sent inline through the mailer, naming the creator's first name and email (`form_component.ex:79-92`; `user_notifier.ex:49-60`, `:107-119`); flash "User created successfully", or error flash "User created, but the confirmation email could not be sent" with a logged error; `push_navigate` to `/settings/users` (`form_component.ex:84-99`)
- Edit: flash "User updated successfully" and `push_navigate` to `/settings/users` (`form_component.ex:65-68`)
- Edit that disables, or changes password, email, role or support access, or sets a scheduled deletion: `disconnect` broadcast on `user_socket:<id>` and `users_live:<id>` after commit (`accounts.ex:191-192`; `user_auth.ex:163-166`); the rest is flow-account-revocation-teardown
- Telemetry `[:lightning, :accounts, :superuser_changed]` on creating a superuser, granting superuser, or changing a superuser's password; not on demotion or disabling (`accounts.ex:153-160`, `:194-195`, `:233-260`)

**Where a save shows up elsewhere**
- The target's open pages, editors and sessions on every device: flow-account-revocation-teardown (S08 here)
- admin-users: the row's name, email, role, enabled, support and scheduled date, after navigation
- admin-audit: the `user` `created` and `updated` events with before and after values and `password_changed` metadata (`accounts/audit.ex:13`, `:28-46`)
- Every project the user is on: collaborator lists, alert and digest recipients read the new name and email from `users`
- Support access: projects that allow support access appear for the user (shared-project-header "Support users see projects that allow support access")
- Superuser grant or demotion: the admin space opens or closes for them (shared-admin-space S02, S06); demoting the last superuser reopens first setup (6.1 row 1)
- The new account's inbox: proposed flow-admin-created-account-confirm

**Deferred side effects** (later, elsewhere)
- Under `require-email-verification`, an admin-created account that does not confirm is sent to /users/confirm-required after 48 hours (`accounts.ex:1360-1368`; shared-authenticated-session S04)
- A date typed into "Scheduled Deletion" makes the account eligible for the nightly purge once it passes (flow-account-revocation-teardown, deferred)

**External, non-transactional effects**
- The confirmation email on create is sent after the user is committed; a delivery failure leaves the account in place and shows the error flash (`form_component.ex:76-92`)
- The disconnect broadcast after an edit commits (`accounts.ex:191-192`)

**Depends on config**
- `:allow_first_setup` decides what happens after the last superuser is demoted (6.1 row 1)
- `:require_email_verification` decides whether an unconfirmed admin-created account is later locked out
- `:account_hook` replaces the insert on create (`services/account_hook.ex:23-28`)

**Product limits**
- Passwords 12 to 72 characters with no NUL (`user.ex:258-267`); names up to 255 characters (`user.ex:102-110`); email up to 160 characters and lowercased (`utils/validators.ex:20-28`)

## 5. Scenarios

Verified by reading code and tests under `default` unless tagged. Nothing was run.

```gherkin
Feature: Admin user form
  In order to give people the right access to this instance and take it away when they should lose it
  As a superuser
  I want to create accounts and change any account's details, role and access

  @S01 @pending
  Scenario: A superuser creates a user account
    # Value: an instance without self sign-up can still bring people on, without database access.
    Given I am a superuser
    When I visit "/settings/users/new"
    And I fill in "First Name" with "Amara", "Last Name" with "Okafor", "Email" with "amara@example.org" and "Password" with "a long enough password"
    And I choose role "User"
    And I click "Save"
    Then I am on "/settings/users"
    And I see "User created successfully"
    And I see "amara@example.org" in the list with role "user"
    And an audit event "user" "created" is recorded for "amara@example.org" with me as the actor
    # form_component.ex:46-48, :75-99; accounts.ex:146-165; extensions/account_hook.ex:28-33; user.ex:85-100
    # user_live_test.exs:43-75 (flash, list, stored names and role); :137-174 (audit actor and event)

  @S02 @pending
  Scenario: A new account is sent a confirmation email that names its creator
    # Value: the person learns an account exists for them, who made it, and how to confirm the address before any verification deadline.
    Given I am a superuser named "Bob" with email "bob@example.org"
    When I create an account for "amara@example.org"
    Then an email "Confirm your OpenFn account" is sent to "amara@example.org"
    And it says "Bob has just created an OpenFn account for you"
    And it names "bob@example.org" as the person to contact
    And the flow "flow-admin-created-account-confirm" has started for "amara@example.org"
    # form_component.ex:79-82; accounts.ex:1135-1142, :1177-1190; user_notifier.ex:107-119
    # accounts_test.exs:1792-1816 asserts the token and recipient; no LiveView test asserts this email
    # Under require-email-verification the account is locked out after 48 hours if unconfirmed (accounts.ex:1360-1368)

  @S03 @pending
  Scenario: The superuser is told when the confirmation email could not be sent
    # Value: the administrator knows the new user has not been told about the account and has no confirmation link, and can follow up.
    Given I am a superuser
    And the mailer refuses deliveries
    When I create an account for "amara@example.org"
    Then I am on "/settings/users"
    And I see the error "User created, but the confirmation email could not be sent"
    And "amara@example.org" is in the list
    # form_component.ex:78-92; user_notifier.ex:49-60; untested

  @S04 @pending
  Scenario: A superuser creates another superuser
    # Value: an instance can have more than one administrator, so it isn't stranded when one is away or leaves.
    Given I am a superuser
    When I create an account for "root@example.org" with role "Superuser"
    Then I see "User created successfully"
    And "root@example.org" is stored with role superuser
    # form_component.ex:50-55 (options "Superuser", "User"); user.ex:93; accounts.ex:153-160
    # user_live_test.exs:77-107

  @S05 @pending
  Scenario: The form refuses an account that can't be used
    # Value: an administrator can't create or leave an account nobody can sign in to, or one whose email collides with another person's.
    Given I am a superuser
    And "taken@example.org" already has an account
    When I visit "/settings/users/new"
    Then the "Save" button is disabled
    When I clear "First Name"
    Then I see "can't be blank"
    When I fill in "Email" with "taken@example.org"
    Then I see "has already been taken"
    When I fill in "Password" with "short"
    Then I see that the password should be at least 12 characters
    And the "Save" button is disabled
    # form_component.ex:12-23, :26-38; form_component.html.heex:104; user.ex:102-131, :241-267
    # user_live_test.exs:57-59, :120-122 assert "can't be blank" only; the other messages are read from code

  @S06 @pending
  Scenario: A superuser changes an account's details, role and access
    # Value: an administrator can correct a name, reset a forgotten password, appoint an administrator or cut off an account without database access.
    Given I am a superuser
    And "amara@example.org" is a user
    When I visit "/settings/users/<amara id>"
    And I change "First Name" to "Ama", "Email" to "ama@example.org" and "Password" to "some updated password"
    And I choose role "Superuser"
    And I tick the disabled checkbox
    And I click "Save"
    Then I am on "/settings/users"
    And I see "User updated successfully"
    And the account has email "ama@example.org", role superuser, is disabled, and signs in only with "some updated password"
    # form_component.ex:57-73; accounts.ex:177-201; user.ex:287-305
    # user_live_test.exs:109-135 (all fields, password checked with valid_password?)

  @S07 @pending
  Scenario: Leaving the password blank keeps the current one
    # Value: correcting someone's name doesn't silently reset their password or sign them out.
    Given I am a superuser
    And "amara@example.org" signs in with "her own password"
    When I visit "/settings/users/<amara id>"
    And I change "Last Name" to "Okafor-Bello" and leave "Password" empty
    And I click "Save"
    Then "amara@example.org" still signs in with "her own password"
    And the flow "flow-account-revocation-teardown" reports her sessions untouched
    # form_component.html.heex:35 (no value rendered); user.ex:118-127 (password validated only when changed), :136-146; accounts.ex:218-219
    # flow-account-revocation-teardown S08; the blank password case itself is untested

  @S08 @pending
  Scenario Outline: Changes that reduce or move access hand off to the revocation flow
    # Value: when an administrator cuts off or changes how someone gets in, the change reaches the browsers and editors they already have open.
    Given I am a superuser
    And "amara@example.org" is a superuser with support access, signed in elsewhere
    When I visit "/settings/users/<amara id>"
    And I <change>
    And I click "Save"
    Then I see "User updated successfully"
    And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    # accounts.ex:181-201, :204-221 (session tokens deleted, disconnect broadcast); form_component.ex:57-68
    # accounts_test.exs:1382-1405 (each row revokes sessions, keeps API tokens); end to end is the flow's S01, S04, S05

    Examples:
      | change                                        |
      | tick the disabled checkbox                    |
      | set "Password" to "a brand new password"      |
      | change "Email" to "amara@new.example.org"     |
      | choose role "User"                            |
      | turn off "Support User"                       |

  @S09 @pending
  Scenario: A superuser changes someone's email without their confirmation
    # Value: an account whose owner has lost their old inbox can be moved to a new address by an administrator, who is accountable for it in the audit trail.
    Given I am a superuser
    And "amara@example.org" is a confirmed user
    When I visit "/settings/users/<amara id>"
    And I change "Email" to "amara@new.example.org" and click "Save"
    Then the account's email is "amara@new.example.org" at once
    And no email is sent to either address
    And an audit event "user" "updated" records the email before and after
    And the flow "flow-change-email-confirm" has not started
    # user.ex:287-305 (email cast directly, confirmed_at untouched); accounts.ex:177-230; accounts/audit.ex:28-46
    # contrast flow-change-email-confirm entry (accounts.ex:740-756); see 6.2 rows on confirmation status and leftover change tokens

  @S10 @pending
  Scenario: Granting support access warns how far it reaches
    # Value: an administrator understands that support access opens every project that allows it before granting it.
    Given I am a superuser
    And "amara@example.org" is a user without support access
    When I visit "/settings/users/<amara id>"
    Then I do not see "Heads Up!"
    When I turn on "Support User"
    Then I see "This user will be able to access ALL projects that have support access enabled"
    When I click "Save"
    Then "amara@example.org" has support access
    # form_component.ex:21, :40-44; form_component.html.heex:53-71; user.ex:295
    # user_live_test.exs:176-217; what support access opens is shared-project-header (support users) and project policies

  @S11 @pending
  Scenario: Scheduled deletion is only offered for non-superuser accounts
    # Value: an instance administrator can't be queued for automatic deletion from this form.
    Given I am a superuser
    And "amara@example.org" is a user
    When I visit "/settings/users/<amara id>"
    Then I see "Scheduled Deletion"
    When I choose role "Superuser"
    Then I do not see "Scheduled Deletion"
    When I visit "/settings/users/<my id>"
    Then I do not see "Scheduled Deletion"
    When I choose role "User"
    Then I see "Scheduled Deletion"
    # form_component.html.heex:75-83; form_component.ex:26-38 (role re-read on change)
    # user_live_test.exs:219-236, :238-259, :261-277, :279-299
    # saving as a superuser also clears any stored date (user.ex:442-447); untested

  @S12 @pending
  Scenario: Cancel leaves the account unchanged
    # Value: a superuser who opened the wrong account can back out without touching it.
    Given I am a superuser
    And "amara@example.org" is a user
    When I visit "/settings/users/<amara id>"
    And I change "First Name" to "Someone else"
    And I click "Cancel"
    Then I am on "/settings/users"
    And the account's first name is unchanged
    # form_component.html.heex:109-114; untested
```

The gate (non-superusers on both routes) is shared-admin-space S02, with `/settings/users/<my id>`
in its examples (`user_live_test.exs:740-749`); demotion of an open admin tab is its S06. The
admin toast is shared-flash-messages S07. The lockout of these routes for an unconfirmed
superuser is shared-authenticated-session S04 (`confirmation_lockout_live_test.exs:24-31`, `:43-68`).

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The last superuser can be demoted, by themselves or another superuser. `has_one_superuser?` then returns false, and under `first-setup-open` the FirstSetup plug sends every browser request, signed in or not, to /first_setup, where any visitor can create a new superuser. Under `first-setup-closed` the instance is left with no superuser and no way back in the UI. Answers flow-first-superuser-sign-in 6.5 | `user.ex:287-299` (role cast, no guard); `accounts.ex:177-201`, `:1341-1344`; `plugs/first_setup.ex:11-33`; `router.ex:29`, `:69`; shared-authenticated-session S11 | everyone, including anonymous visitors, lands on "/first_setup" and can make themselves administrator of an instance full of data | fix |
| The last superuser can be disabled. `has_one_superuser?` counts disabled rows, so first setup stays closed while the only administrator can't sign in ("This user account is disabled"). Answers flow-first-superuser-sign-in 6.5 | `user.ex:296`; `accounts.ex:1341-1344`; `user_auth.ex:41-45` | nobody can reach any admin page; recovery needs the database or the API | fix |
| A superuser can demote or disable themselves, or change their own email, password or support access here; their own tab is disconnected before `push_navigate` returns (flow-account-revocation-teardown 6.1 row 3) | `edit.ex:24-29` (any id, including the actor's); `accounts.ex:191-192`; `form_component.ex:65-68` | the login page instead of "User updated successfully" | decide |
| The "Disabled?" label is passed as the checkbox's inner block, but the checkbox input renders only `label`, so the checkbox has no visible or accessible label | `form_component.html.heex:87-89`; `new_inputs.ex:449-458` | a bare checkbox next to "A disabled user will not be allowed to login."; screen readers announce an unlabeled checkbox | fix |
| The "Save" tooltip says "All fields are required", but on edit the password is optional and "Scheduled Deletion" and support access are never required | `form_component.html.heex:100-108`; `user.ex:118-127` | a tooltip that contradicts the form | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Live validation always uses `User.changeset/2`, which does not cast `support_user`, `disabled` or `scheduled_deletion`; save on edit uses `details_changeset/2`. A malformed "Scheduled Deletion" value shows no error and leaves "Save" enabled until it is submitted | `form_component.ex:12-13`, `:26-30`, `:57-62`; `accounts.ex:903-905`; `user.ex:85-100`, `:287-305` | decide |
| "Scheduled Deletion" is a free text input for a UTC datetime, with no format hint; a date set here revokes every token and blocks login like a deletion, but sends no deletion email and does not disable the account (flow-account-revocation-teardown 6.2) | `form_component.html.heex:76-83`; `accounts.ex:205-206` | decide |
| An admin email change keeps `confirmed_at`, so the account stays confirmed at an address nobody verified; nothing is sent to the old or new address | `user.ex:287-305`; `accounts.ex:177-201` | decide |
| An admin email change does not delete pending `change:<old email>` tokens (flow-change-email-confirm 6.1 row 1) | `accounts.ex:204-221` | decide |
| A superuser-set password is never told to the account owner; they are only signed out, and the superuser knows the password | `form_component.html.heex:32-37`; `accounts.ex:177-201` | decide |
| Granting superuser signs the promoted person out, because any role change revokes sessions | `accounts.ex:211-216` | decide |
| Typing the account's current password into "Password" changes nothing and revokes nothing | `user.ex:136-146` | preserve |
| Saving as a superuser silently clears a stored scheduled deletion, so promoting a scheduled user cancels the deletion without the "Cancel deletion" flash or the re-enable | `user.ex:442-447`; compare admin-users S07 | decide |
| An unknown or malformed id on /settings/users/:id raises in `get_user!` instead of showing "Not Found" | `edit.ex:24-29`; `accounts.ex:372` | decide |
| "Save" and "Cancel" go from the `:settings` live_session to `/settings/users` in `:services`, so each is a full page load | `form_component.ex:68`, `:99`; `form_component.html.heex:109-114`; `router.ex:268-270`, `:340-356` | decide |
| The create confirmation email is sent under every verification setting and is not rate limited, unlike the /1 variant | `accounts.ex:1161-1175` vs `:1177-1190` | preserve |
| The confirmation email gives the new user the creator's first name and email address as a contact | `user_notifier.ex:107-119` | preserve |
| The confirmation token is inserted with `Repo.insert!` after the create transaction, so a failure there raises after the account exists | `accounts.ex:1135-1142`; `form_component.ex:76-82` | decide |
| Labels are title case ("First Name", "Last Name", "Support User", "Scheduled Deletion", "Heads Up!", "New User", "Edit User") | `form_component.html.heex:13`, `:20`, `:56`, `:62`, `:79`; `edit.ex:26`, `:33` | decide |
| The role select shows "Superuser" and "User" sorted alphabetically from the enum | `form_component.ex:50-55` | preserve |
| The support heads-up follows the click on the toggle, not the field value, so it can differ from the toggle after a failed save re-render | `form_component.ex:21`, `:40-44`, `:70-71` | preserve |
| The module doc says it edits "a single job" with `JobLive.BigFormComponent` | `edit.ex:2-5` | decide |
| A save that changes nothing still shows "User updated successfully" and writes no audit event | `accounts/audit.ex:32-33`; `auditing/audit.ex:176-178`; `user_live_test.exs:137-174` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `assign(:current_user, socket.assigns.current_user)` in both `apply_action` clauses | `edit.ex:28`, `:35` | reassigns the value already there |
| `assign(:is_support_user, user.support_user)` after a successful save | `form_component.ex:66`, `:97` | followed immediately by `push_navigate`, so never rendered |
| `confirmed` and `contact_preference` casts | `user.ex:92`, `:94`, `:298`, `:148-153` | no input in the form sends them; reachable from the API (`api/user_controller.ex:6`) |
| shared-authenticated-session S08 to S10 (book-a-demo and GDPR banners) | `layouts/settings.html.heex:1-107`; `edit.html.heex:1-18` | the settings layout renders neither and the page has no `:banner` slot |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every `validate` event with a password present runs bcrypt: `maybe_hash_password` hashes on each change once the password is valid, and on edit `keep_current_password` also verifies it | `form_component.ex:26-30`; `user.ex:118-146`, `:269-281` | possibly, as lag while typing the password | decide |
| The email uniqueness query runs on every `validate` that changes the email | `user.ex:241-256` | no | preserve |
| The confirmation email is sent inline before the redirect | `form_component.ex:79-82`; `user_notifier.ex:57` | yes, "Save" waits for the mailer | decide |

### 6.5 Things seen but not understood

- `[:lightning, :accounts, :superuser_changed]` is emitted for superuser creation, grant and superuser password changes, but nothing in `lib/` or `config/` attaches a handler, and demotion or disabling a superuser emits nothing (`accounts.ex:233-260`). Whether a deployment alerts on it, and whether demotion should be reported too, is unknown. Disposition: decide.
- The form shows no MFA state and offers no way to reset MFA or confirm an account, so a user who lost their device or their confirmation email can't be helped from here. Not clear whether that is deliberate. Disposition: decide.
- Under `custom-account-hook` the insert behind create is a deployment's module; whether it keeps the audit, the uniqueness check and the email was not read. Disposition: decide.
- No LiveView test covers the confirmation email on create (S02), its failure flash (S03), the blank password on edit (S07), Cancel (S12), or clearing a scheduled deletion on promotion. Disposition: preserve (write the tests).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should demoting or disabling the last superuser be refused, and should first setup ever reopen on an instance that already has users (6.1 rows 1 and 2)? (owner: security)
- Should a superuser be able to demote, disable or change the sign-in details of their own account from this form (6.1 row 3)? (owner: security)
- Should an admin email change reset confirmation, notify the old address, and clear pending change tokens (6.2)? (owner: security)
- Should a superuser-set password notify the owner, or be replaced by sending a reset link (6.2)? (owner: security)
- Should "Scheduled Deletion" stay a free text field here, or go through the deletion dialog with its email and disable (6.2)? (owner: product)
- Should promotion to superuser sign the person out, and should it silently cancel a scheduled deletion (6.2)? (owner: product)
- Is the `superuser_changed` telemetry consumed anywhere, and should demotion emit it (6.5)? (owner: engineering)

## Proposed flows

- `flow-admin-created-account-confirm`: a superuser creates an account; the new user receives the enroller variant of "Confirm your OpenFn account", opens the link, confirms, and lands signed in or at login; under `require-email-verification` an unconfirmed account is locked out after 48 hours. Surfaces: admin-user-edit, email:confirmation (enroller variant, `user_notifier.ex:107-119`), auth-confirm-account, projects-dashboard, auth-confirmation-required. flow-resend-account-confirmation lists this send as outside it (its inventory).

Referenced:
- `flow-account-revocation-teardown`: S08 hands off; admin-user-edit is already in its surfaces and `UserLive.FormComponent#save` in its events.
- `flow-change-email-confirm`: S09 cross-reference only; admin-user-edit is not in its surfaces (admin-users is, as a cross-reference), so the lead may add it the same way.
- `flow-first-superuser-sign-in`: its 6.5 is answered by 6.1 rows 1 and 2 here; yes, the last superuser can be demoted or disabled from this form.

## Proposed shared

none. Inherits shared-admin-space, shared-authenticated-session, shared-flash-messages and shared-project-header (no-project parts).

## Lead resolution (batch 10)

- `flow-admin-created-account-confirm` created. admin-user-edit added to flow-change-email-confirm surfaces.
- Answers flow-first-superuser-sign-in 6.5: nothing stops the last superuser being demoted or disabled (6.1 rows 1 and 2).
