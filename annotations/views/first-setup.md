---
id: first-setup
type: view
title: First setup
status: not-started
owner:

trigger:
  old_route: /first_setup
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - first-setup-open only: `allow_first_setup` is true, which bootstrap sets whenever `SERVICE_ACCOUNT_PUBLIC_KEY` is unset (`lib/lightning/config/bootstrap.ex:230-234`). Otherwise an HTTP request gets a plain-text 404 from BlockRoutes (`router.ex:31-42`; `plugs/block_routes.ex:12-33`) and a live navigation is redirected to /projects by mount (`first_setup_live/superuser.ex:15-21`)
    - no user has role superuser (`accounts.ex:1341-1344`). Otherwise an HTTP request is redirected to /projects by the FirstSetup plug (`plugs/first_setup.ex:19-21`) and a live navigation is push-navigated to /projects (`superuser.ex:69-73`)
    - no session needed: the route is piped through `:browser` only, with no `:require_authenticated_user` and no `on_mount` (`router.ex:66-69`)
    - forced: while first-setup-open and no superuser exists, the FirstSetup plug in the `:browser` pipeline redirects every other browser request to /first_setup (`router.ex:29`; `plugs/first_setup.ex:11-33`, `:27-32`); that gate is shared-authenticated-session S11

inherits:
  - shared-authenticated-session     # the :browser pipeline only (fetch_current_user, router.ex:28) and its S11 first-setup redirect, which is how visitors arrive here. Its S01 to S06 gates and InitAssigns do not run: no :require_authenticated_user and no on_mount on this route (router.ex:66-69)
  - shared-flash-messages   # added by lead (final pass)

url_params: []                        # mount and handle_params ignore params (superuser.ex:14, :25-27, :69)

config_variants:
  first-setup-open: { lightning.allow_first_setup: true }     # default when SERVICE_ACCOUNT_PUBLIC_KEY is unset (bootstrap.ex:230-234); the test suite runs under it (first_setup_live_test.exs:6-111). Read under this one unless a scenario is tagged
  first-setup-closed: { lightning.allow_first_setup: false }  # SERVICE_ACCOUNT_PUBLIC_KEY set (bootstrap.ex:230-234); stubbed in first_setup_live_test.exs:114-122
  require-email-verification: { first-setup-open, lightning.require_email_verification: true }   # affects the account created here after 48 hours (accounts.ex:1362-1368); read in code only

inventory:
  routes:
    - live /first_setup  FirstSetupLive.Superuser :show      # router.ex:69, outside any explicit live_session
  events:
    - FirstSetupLive.Superuser#validate                       # superuser.ex:29-42
    - FirstSetupLive.Superuser#save                           # superuser.ex:44-67
  js_hooks: []                                                # the layout's ToggleSidebarViaCtrlM and SidebarHoverDelay belong to shared-authenticated-session
  policies:
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)
    - LightningWeb.Plugs.BlockRoutes with {"/first_setup", :allow_first_setup, ...} (router.ex:37-41; plugs/block_routes.ex:12-33)
    - FirstSetupLive.Superuser.mount/3 flag check (superuser.ex:17-21)
    - FirstSetupLive.Superuser.apply_action/3 superuser check (superuser.ex:69-73)
  workers: []
  api_endpoints: []
  emails: []                                                  # register_superuser sends nothing (accounts.ex:543-547)
  config:
    - :lightning, :allow_first_setup                          # bootstrap.ex:234; plugs/first_setup.ex:12; router.ex:39; superuser.ex:17
    - SERVICE_ACCOUNT_PUBLIC_KEY                              # bootstrap.ex:230-233, sets the flag above
    - :lightning, :require_email_verification                 # accounts.ex:1362-1368, see 6.1
    - Lightning.Extensions account_hook adapter               # Services.AccountHook.handle_register_superuser/1 (services/account_hook.ex:19-21)
  not_reachable_here:
    - UserSessionController.exchange_token/2 (user_session_controller.ex:55-67), the controller this view hands off to; owned by the proposed flow-first-superuser-sign-in
    - the live layout's side menu items, Admin menu and global project picker, hidden by `is_first_setup` (layouts/live.html.heex:42-108, :109-113)
    - the header's email-verification banner (layout_components.ex:261-277); no current_user is assigned here

related:
  - lib/lightning_web/live/first_setup_live/superuser.ex
  - lib/lightning_web/live/first_setup_live/superuser.html.heex
  - lib/lightning_web/plugs/first_setup.ex
  - lib/lightning_web/plugs/block_routes.ex
  - lib/lightning_web/router.ex                     # :21-43 pipeline, :69 route, :180 token exchange
  - lib/lightning/config/bootstrap.ex               # :230-234
  - lib/lightning/accounts.ex                       # register_superuser/1 :543-547, change_superuser_registration/1 :559-561, generate_auth_token/1 :1051-1055, exchange_auth_token/1 :1062-1071, has_one_superuser?/0 :1341-1344
  - lib/lightning/extensions/account_hook.ex        # handle_register_superuser/1 :20-26
  - lib/lightning/accounts/user.ex                  # validate_names :102-110, superuser_registration_changeset/2 :230-239, validate_email :241-256, validate_password :258-281
  - lib/lightning/utils/validators.ex               # validate_email_format/2 :20-28, validate_name/3 :81-90
  - lib/lightning/accounts/user_token.ex            # @auth_validity_in_seconds 30 :36, verify_token_query "auth" :96-102
  - lib/lightning_web/components/layouts/live.html.heex   # is_first_setup :42, :109
  - test/lightning_web/live/first_setup_live_test.exs
  - test/lightning_web/plugs/first_setup_test.exs
  - test/lightning/config/bootstrap_test.exs        # :1445, :1463
  - projects-dashboard                              # landing after setup, and where a refused visit is sent
  - auth-login                                      # its S19 asserts the forced redirect from that page
  - auth-register                                   # its S12 asserts the same
  - auth-confirmation-required                      # its 6.1 row on a first-setup superuser who was never sent a confirmation link
flows:
  - flow-first-superuser-sign-in
---

## 1. Purpose

Whoever installs Lightning uses this page once, on a fresh instance, to create the first superuser
account. Without it, a new install has no administrator and nobody can create projects or users
without going to the database. Because whoever completes the form first holds every permission on an
instance that will carry health data, the page must also shut for good once that account exists, and
stay shut on instances that are administered by a service account instead.

## 2. What it does

- **Create the first superuser** (anyone reaching the page on a fresh install)
  - Visitors give both names, a valid unused email and a password of at least 12 characters, and are signed in as the new superuser
  - The form flags a password confirmation that doesn't match while typing, and refuses names with control characters
  - Save stays disabled until the form is valid
- **When the page is open**
  - A fresh install sends every browser page here until a superuser exists
  - Once a superuser exists, the page sends visitors to their projects
  - Instances administered by a service account refuse the page and never force it

**Straightforwardness: 3 of 5.** A one-off form, but who gets to fill it in, and how firmly it shuts afterwards, has gaps you need explained.

### Most surprising behaviours

- **(2)** On a fresh install anyone who reaches the address first becomes the superuser; there is no setup code or other check. (6.5)
- **(2)** The "already set up" check only happens when the page loads, so a tab left open, or two people saving at once, can create a second superuser. (6.1)
- **(2)** Where email confirmation is required, the superuser made here is never confirmed or emailed, so the only administrator gets locked out 48 hours later. (6.1)
- **(3)** If the browser is already signed in as someone else, it stays that person and the new superuser isn't signed in. (6.2)
- **(3)** A short password shows "minimum 12 characters" and "minimum 8 characters" at the same time, and first setup can only be switched off by setting up a service account. (6.1, 6.2)

## 3. Who can do what

Sources: `router.ex:21-43`, `:66-69`; `plugs/first_setup.ex:11-33`; `plugs/block_routes.ex:12-33`;
`superuser.ex:14-22`, `:44-81`. There is no policy module: the page has no role check, only the
instance flag and the "no superuser yet" state.

| Action | Visitor, no superuser yet (first-setup-open) | Visitor, a superuser exists (first-setup-open) | Any visitor (first-setup-closed) |
|--------|-----|-----|-----|
| See the page | yes, signed in or not | no, redirected to /projects | no, plain-text 404 (HTTP) or redirect to /projects (live navigation) |
| Create the superuser | yes | no (but see 6.1, stale tab) | no |
| Be forced here from other pages | yes | no | no |

**Preconditions beyond role**
- No session is required; the first visitor to reach the URL can claim the instance (`router.ex:66-69`).
- "Superuser exists" is checked on page load only, not on save (`superuser.ex:44-62`, `:69-81`; 6.1).
- The flag is not an independent setting: it is true exactly when `SERVICE_ACCOUNT_PUBLIC_KEY` is unset (`bootstrap.ex:230-234`).

## 4. What it touches

**Reads**: `users` count where role is superuser, on every browser request while first-setup-open (`plugs/first_setup.ex:20`, `:28`; `accounts.ex:1341-1344`) and on each page load (`superuser.ex:70`); `users` by email for the "already taken" check (`user.ex:241-250`)

**Writes**: `users` (insert one row with role `superuser`, bcrypt-hashed password, `confirmed_at` unset; `accounts.ex:543-547`; `extensions/account_hook.ex:20-26`; `user.ex:230-239`, `:269-281`); `user_tokens` (insert one `auth` token for the handoff; `accounts.ex:1051-1055`)

**Immediate side effects** (in the same request)
- Flash "Superuser account created." and a redirect to `/users/token_exchange/<base64url auth token>` (`superuser.ex:51-62`)

**Deferred side effects** (later, elsewhere)
- The token exchange controller deletes the auth token, starts a session and redirects to /projects (`user_session_controller.ex:55-67`; `accounts.ex:1062-1071`); owned by the proposed flow-first-superuser-sign-in
- From then on the FirstSetup plug stops redirecting other pages here (`plugs/first_setup.ex:27-29`)

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- none

**Depends on config**
- `allow_first_setup` / `SERVICE_ACCOUNT_PUBLIC_KEY` (`bootstrap.ex:230-234`): variants first-setup-open and first-setup-closed
- `require_email_verification`: the account created here is never confirmed (6.1)
- The account hook extension can replace how the superuser is inserted (`services/account_hook.ex:19-21`)

**Product limits** (limits a user would notice and that we intend to keep)
- Password between 12 and 72 characters (`user.ex:261`)
- Names up to 255 characters, email up to 160 (`user.ex:107`; `utils/validators.ex:26`)

## 5. Scenarios

```gherkin
Feature: First setup
  In order to administer a fresh Lightning install
  As the person who installed it
  I want to create the first superuser account from the browser

  @S01 @pending
  Scenario: Operator creates the first superuser and is handed off to sign in
    # Value: a fresh install gets an administrator without anyone touching the database.
    Given first setup is allowed
    And there is no superuser
    When I open "/first_setup"
    Then I see the heading "Setup"
    When I fill in first name "Test", last name "McTest", email "foo@example.com"
    And I fill in password and password confirmation "1234567890ab"
    And I click "Save"
    Then a user "foo@example.com" exists with role superuser
    And the flow "flow-first-superuser-sign-in" has started for "foo@example.com"
    # superuser.ex:44-62; accounts.ex:543-547, :1051-1055; extensions/account_hook.ex:20-26; user.ex:230-239
    # first_setup_live_test.exs:31-52 (asserts the end of the flow: /projects with the flash)

  @S02 @pending
  Scenario: A mismatched password confirmation is flagged while typing
    # Value: the operator doesn't lock themselves out of the only administrator account with a typo.
    Given first setup is allowed
    And there is no superuser
    When I open "/first_setup"
    And I type password "123" and leave the confirmation empty
    Then I see "does not match confirmation"
    And "Save" is disabled
    # superuser.ex:35-41; superuser.html.heex:59-65; first_setup_live_test.exs:16-20

  @S03 @pending
  Scenario: A password shorter than 12 characters is refused
    # Value: the most privileged account on the instance has a minimum password strength.
    Given first setup is allowed
    And there is no superuser
    When I open "/first_setup"
    And I type password and confirmation "123"
    Then I see "Password minimum length is 12 characters."
    And "Save" is disabled
    # user.ex:258-261; priv/gettext/en/LC_MESSAGES/errors.po:27-30
    # first_setup_live_test.exs:22-29 asserts only the 8-character copy; see 6.1

  @S04 @pending
  Scenario: A superuser without first and last name is refused
    # Value: the administrator is identifiable wherever their name appears, in audit trails and user lists.
    Given first setup is allowed
    And there is no superuser
    When I open "/first_setup"
    And I fill in first name " ", an empty last name, email "nameless@example.com" and a valid password and confirmation
    Then I see "can't be blank"
    And "Save" is disabled
    When I submit the form anyway
    Then I see "can't be blank"
    And no user "nameless@example.com" exists
    And there is still no superuser
    # user.ex:102-110; utils/validators.ex:81-90; superuser.ex:64-65; first_setup_live_test.exs:55-79

  @S05 @pending
  Scenario: A name with a control character is refused
    # Value: names shown to other users, in emails and in exported files can't carry hidden characters.
    Given first setup is allowed
    And there is no superuser
    When I open "/first_setup"
    And I submit first name "Ann" followed by a bell character, last name "Smith", email "bell@example.com" and a valid password
    Then I see "can't contain control characters"
    And no user "bell@example.com" exists
    And there is still no superuser
    # utils/validators.ex:46, :81-86; user.ex:102-106; first_setup_live_test.exs:81-104

  @S06 @pending
  Scenario: An invalid or already registered email is refused
    # Value: the administrator account has an address that reaches them, and can't collide with an existing account.
    Given first setup is allowed
    And there is no superuser
    And a non-superuser account "amara@example.org" exists
    When I open "/first_setup"
    And I fill in email "not-an-email"
    Then I see "must be a valid email address"
    When I fill in email "amara@example.org"
    Then I see "has already been taken"
    And "Save" is disabled
    # utils/validators.ex:20-27; user.ex:241-256; not covered by first_setup_live_test.exs

  @S07 @pending
  Scenario: Visiting the page after a superuser exists sends me to projects
    # Value: once the instance has an administrator, the page can't be used to create another one.
    Given first setup is allowed
    And a superuser exists
    When I visit "/first_setup"
    Then I am redirected to "/projects"
    # plugs/first_setup.ex:19-21; first_setup_live_test.exs:106-111 (flash is empty)

  @S08 @pending
  Scenario: Navigating to the page from inside the app after a superuser exists sends me to projects
    # Value: the page stays shut even when reached without a full page load, where the plugs don't run.
    Given first setup is allowed
    And a superuser exists
    And I am signed in on "/credentials"
    When a live navigation takes me to "/first_setup"
    Then I land on "/projects"
    And no registration form is shown
    # superuser.ex:69-73; router.ex:69 and :288 (same live_session name, see 6.2); not covered by a test

  @S09 @pending @variant:first-setup-closed
  Scenario: Instances administered by a service account refuse the page
    # Value: an instance provisioned by automation can't be claimed by whoever reaches the URL first.
    Given first setup is not allowed
    And there is no superuser
    When I visit "/first_setup"
    Then I get a 404 with "First setup is disabled for this instance."
    # router.ex:37-41; plugs/block_routes.ex:12-19, :26-33; first_setup_live_test.exs:129-133, :144-147

  @S10 @pending @variant:first-setup-closed
  Scenario: Instances administered by a service account refuse live navigation to the page
    # Value: the page stays shut on such instances even when no plug runs.
    Given first setup is not allowed
    And I am signed in on "/credentials"
    When a live navigation takes me to "/first_setup"
    Then I am redirected to "/projects"
    # superuser.ex:15-21; first_setup_live_test.exs:135-142

  @S11 @pending @variant:first-setup-closed
  Scenario: Instances administered by a service account are not forced into first setup
    # Value: such instances are usable without anyone creating a superuser in the browser.
    Given first setup is not allowed
    And there is no superuser
    When I visit "/"
    Then I am not redirected to "/first_setup"
    # plugs/first_setup.ex:11-16; first_setup_live_test.exs:124-127
```

The forced redirect from every other page while first-setup-open is shared-authenticated-session S11;
auth-login S19, auth-register S12 and auth-reset-password S14 assert it on their own routes.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Save does not re-check that no superuser exists, or that the flag is on; only page load does. A tab opened before setup finished (by the operator or anyone else who reached the URL) can still create a second superuser afterwards, and two people saving at once both succeed | `superuser.ex:44-62` vs `:69-81`; `accounts.ex:543-547`; `extensions/account_hook.ex:20-26` | a second superuser account appears; the instance's administrator is not who the operator thinks | fix |
| A short password shows two contradictory messages: the LiveView adds an 8-character minimum on top of the changeset's 12, and both render through the same gettext string | `superuser.ex:38`; `user.ex:261`; `errors.po:27-30`; `new_inputs.ex:432-440`; the test asserts the 8 copy (`first_setup_live_test.exs:22-29`) | "Password minimum length is 12 characters." and "Password minimum length is 8 characters." together | fix |
| Password confirmation is validated only in `validate`; `save` calls `register_superuser` with no confirmation check. A submit that arrives before the change round trip, or a crafted event, creates the account with an unconfirmed password | `superuser.ex:35-41` vs `:50`; `user.ex:230-239` | the administrator account's password is not the one the operator meant to type | fix |
| The "Superuser account already exists." flash is put with kind `:warn`, which the live layout never renders (only `:info` and `:error`) | `superuser.ex:72`; `layouts/live.html.heex:92-93` | a silent jump to /projects with no explanation | fix |
| The superuser is inserted with `confirmed_at` unset and no confirmation email. Under require-email-verification it is locked out 48 hours later, possibly on an instance with no mail configured. Same root as auth-confirmation-required 6.1 | `extensions/account_hook.ex:20-26`; `accounts.ex:543-547`, `:1362-1368` | the only administrator is shut out of the instance | fix |
| Two concurrent saves with the same email: the "already taken" check is a query, and the insert has no `unique_constraint`, so the loser raises instead of returning a changeset | `user.ex:241-250`; `extensions/account_hook.ex:24` | the LiveView crashes and reconnects | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The route sits outside any explicit `live_session`, so Phoenix places it in an implicit `:default` session, the same name as Lightning's `live_session :default`. Live navigation from those pages reaches mount with no plug and no `on_mount`, which is why mount re-checks the flag | `router.ex:69`, `:288`; `superuser.ex:15-16` | decide |
| No `on_mount`: no `current_user`, sidebar preference or banners are assigned; the layout survives only because `is_first_setup` hides the side menu items, Admin menu and project picker that read `@current_user` | `superuser.ex:18`; `layouts/live.html.heex:29`, `:42-108`, `:109-113` | preserve |
| HTTP visits after setup are redirected by the plug to "/projects"; live navigations are push-navigated by the view to `dashboard_index_path`, the same path but a different code path and a full load across live_sessions | `plugs/first_setup.ex:19-21`; `superuser.ex:73`; `config/config.exs:53` | preserve |
| The token exchange route is behind `redirect_if_user_is_authenticated`. A browser already signed in as another (non-superuser) account keeps that session; the new superuser's auth token is never used and expires | `router.ex:175-180`; `user_auth.ex:271-279` | decide |
| The flag is not its own setting: it is the absence of `SERVICE_ACCOUNT_PUBLIC_KEY`, so an operator can't turn first setup off without configuring a service account | `bootstrap.ex:230-234`; `bootstrap_test.exs:1445`, `:1463` | decide |
| `role` is cast from the submitted params and then overwritten with `:superuser` | `user.ex:231-238` | preserve |
| Errors show only for fields the user has touched; "Save" starts disabled because the empty changeset is invalid | `new_inputs.ex:432-433`; `superuser.html.heex:59-65`; `superuser.ex:79` | preserve |
| "Save" shows "Saving" while the submit is in flight | `superuser.html.heex:62` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `assign(:registration, %Accounts.User{})` | `superuser.ex:75-78` | the template never reads `@registration` (`superuser.html.heex:1-70`) |
| "Superuser account already exists." flash | `superuser.ex:72` | `:warn` is never rendered (6.1) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| While first-setup-open, every browser request counts superusers, for the life of the instance, because the flag stays on after setup. Same row as shared-authenticated-session 6.4 | `plugs/first_setup.ex:12`, `:20`, `:28`; `accounts.ex:1341-1344` | no | preserve |
| The handoff auth token is valid for 30 seconds | `user_token.ex:36`, `:96-102` | yes, a stalled redirect lands on log in with "Invalid token" (flow-first-superuser-sign-in) | preserve |
| Password is bcrypt-hashed on save; the 72-byte cap bounds the cost | `user.ex:261`, `:269-276` | no | preserve |

### 6.5 Things seen but not understood

- The page has no gate beyond the flag and "no superuser yet": on a default install reachable from the internet, whoever loads `/first_setup` first becomes superuser. Whether that is an accepted install-time risk is not stated anywhere in the code (`router.ex:66-69`; `bootstrap.ex:230-234`).
- `test/lightning_web/plugs/first_setup_test.exs:12-18` ("redirects to /projects when there is a first user") asserts only `request_path == "/"` and status 302, which the "/" route produces anyway; it does not show the plug letting the request through.
- With first-setup-closed and no superuser, the instance has no administrator until the service account creates one through `/api/users` (`router.ex:96-101`). That path was not followed here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Is "first visitor to reach the URL becomes superuser" on a default install acceptable, or should first setup need a one-time token from the install (6.5)? (owner: security)
- Should save re-check that no superuser exists, in the same transaction as the insert (6.1)? (owner: security)
- Should the superuser created here be confirmed on creation, or be sent a confirmation email (6.1)? (owner: product)
- Should first setup have its own on/off setting rather than following `SERVICE_ACCOUNT_PUBLIC_KEY` (6.2)? (owner: product)
- What should happen when the browser is already signed in as another account at the handoff (6.2)? (owner: product)
- Should the page move into its own live_session so live navigation can't reach it without the plugs (6.2)? (owner: security)

## Proposed flows

- `flow-first-superuser-sign-in`: after save, the view inserts a 30-second `auth` token and redirects to `/users/token_exchange/<token>`; the controller deletes the token, starts a session and redirects to /projects, where "Superuser account created." shows (`superuser.ex:51-62`; `accounts.ex:1051-1071`; `user_session_controller.ex:55-67`; `user_auth.ex:54-70`, `:514`; asserted end to end in `first_setup_live_test.exs:31-52`). Edge cases it owns: a stalled redirect past 30 seconds ("Invalid token" on log in) and a browser already signed in (6.2). Surfaces: first-setup, controller:token-exchange, projects-dashboard. This file asserts only the start (S01). It shares controller:token-exchange with flow-account-revocation-teardown; the lead may prefer to fold it in there as a second entry.

## Proposed shared

none. Referenced: shared-authenticated-session (the :browser pipeline and its S11 first-setup redirect, which brings visitors here; its 6.2 row on /first_setup after setup and its 6.4 row on the per-request superuser count).

## Lead resolution (batch 9)

- `flow-first-superuser-sign-in` created as its own flow; it shares the token-exchange controller with flow-account-revocation-teardown but is a different journey.
