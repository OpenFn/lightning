---
id: shared-authenticated-session
type: shared
title: Authenticated session gate and app chrome
status: not-started
owner:

trigger:
  old_route: any LiveView in the :default, :settings, :auth or :services live_session (all mount LightningWeb.InitAssigns)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the route sits in a scope piped through `[:browser, :require_authenticated_user]` (`lib/lightning_web/router.ex:189-190`, `:349`)
    - the live_session declares `on_mount: LightningWeb.InitAssigns` (`router.ex:242`, `:268`, `:288`; `:services` via `config/config.exs:51`)

inherits: []

url_params: []

config_variants:
  default: {}                                                    # read under this one unless a scenario is tagged
  require-email-verification: { lightning.require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389
  book-demo-banner: { lightning.book_demo_banner.enabled: true, calendly_url: <url>, openfn_workflow_url: <url> }
  gdpr-banner: { lightning.gdpr_banner: %{component: <module>, id: <dom id>} }
  first-setup-open: { lightning.allow_first_setup: true }        # default when SERVICE_ACCOUNT_PUBLIC_KEY is unset, bootstrap.ex:234

inventory:
  routes: []                                                     # owns no route; see `related`
  events:
    - LightningWeb.InitAssigns#toggle_sidebar                    # attach_hook on :handle_event, init_assigns.ex:56, :84-95
    - LightningWeb.BookDemoBanner#dismiss_banner
    - LightningWeb.BookDemoBanner#validate
    - LightningWeb.BookDemoBanner#schedule-call
  js_hooks:
    - ToggleSidebarViaCtrlM
    - SidebarHoverDelay
  policies: []
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :require_email_verification
    - :lightning, :book_demo_banner
    - :lightning, :gdpr_banner
    - :lightning, :allow_first_setup
    - :lightning, :allow_signup
    - :lightning, Lightning.Extensions.Routing (session_opts)
  not_reachable_here:
    - the `:banner` slot is rendered per view; views without it never show the book-a-demo banner (see 6.2)

related:
  - credentials-index
  - history-work-orders
  - project-settings-collaborators
  - project-settings-setup
  - workflows-index
  # Not yet annotated, same live_sessions (router.ex:242-330, config/config.exs:52-61):
  # :default  ProjectLive.MFARequired, ProjectLive.Settings(:delete), RunLive.Index, RunLive.Show,
  #           ChannelRequestLive.Show, DataclipLive.Show, WorkflowLive.Collaborate, WorkflowLive.Health,
  #           ChannelLive.Index, SandboxLive.Index, ProfileLive.Edit(:delete), TokensLive.Index
  # :settings UserLive.Edit, UserLive.Index(:delete), ProjectLive.Index, AuditLive.Index,
  #           MaintenanceLive.Index, AuthProvidersLive.Index, CollectionLive.Index
  # :auth     ReAuthenticateLive.New
  # :services DashboardLive.Index, ProjectLive.Settings, ProfileLive.Edit, UserLive.Index
  # Also attach InitAssigns outside the four named sessions: :sudo_auth BackupCodesLive.Index
  # (router.ex:258-262) and LiveDashboard /dashboard (router.ex:363-369)
flows: []
---

## 1. Purpose

Every signed-in page first has to establish who is looking at it. This gate keeps app pages away
from anonymous browsers and from sessions that have been revoked, disabled or locked out pending
email confirmation, and it hands every page the same signed-in chrome: the user's sidebar
preference and any instance-wide banners. Without it each page would re-implement session checks,
and one that forgot would expose data to a logged-out or blocked account.

## 2. What it does

- **Turn away sessions that shouldn't see app pages**
  - Signed-out visitors are sent to log in
  - Sessions for disabled, deleted or expired accounts stop opening pages
  - Sessions still waiting on a second factor are sent to finish it
- **Enforce email confirmation** (instances that require it)
  - Unconfirmed accounts past the confirmation deadline are sent to the confirmation page
  - Unconfirmed accounts inside the deadline see when they must confirm by
- **Remember the sidebar**
  - Users collapse or expand the sidebar, and it stays that way
- **Show instance banners**
  - Users on instances with the book-a-demo banner see it until they dismiss it or book a call
  - Users on instances with a GDPR banner see it on app pages
- **Send a fresh install to setup**
  - Instances with no superuser send every page to first setup

**Straightforwardness: 3 of 5.** Each rule makes sense on its own, but which check catches you depends on whether you've just loaded the page or had it open for a while, and the banners don't reach every page.

### Most surprising behaviours

- **(3)** When a session expires on a page that's already open, the user is sent to log in with no explanation, and after logging in lands on their projects list rather than where they were. (6.1)
- **(3)** The GDPR consent banner never appears on the admin pages, and the book-a-demo banner only appears on some pages, so "shown on app pages" isn't quite true. (6.2)
- **(3)** A page left open when the 48-hour confirmation deadline passes keeps working until it reconnects; only a fresh load locks the user out. (6.2)
- **(3)** If booking a demo call fails to reach the team's workflow, the page crashes and reloads, the banner stays put and the user never gets to the booking page. (6.1)

## 3. Who can do what

| Action | Signed out | Disabled / scheduled for deletion | TOTP pending | Locked out (unconfirmed, past deadline) | Any other signed-in user |
|--------|-----------|-----------------------------------|--------------|-----------------------------------------|--------------------------|
| Render a signed-in page | no | no | no | no | yes |
| Toggle the sidebar | n/a | n/a | n/a | n/a | yes |
| Dismiss the book-a-demo banner | n/a | n/a | n/a | n/a | yes |

Sources: `lib/lightning_web/controllers/user_auth.ex:288-311`, `lib/lightning_web/init_assigns.ex:17-35`, `lib/lightning/accounts.ex:994-1006`, `:329-332`, `:1360-1370`.

**Preconditions beyond role**
- Session token must exist (session or signed remember-me cookie) and be under 60 days old (`user_auth.ex:194-206`, `lib/lightning/accounts/user_token.ex:34`, `:111-117`).
- Lockout applies only when `require_email_verification` is on, `confirmed_at` is nil and the account is 48 hours old or more (`accounts.ex:1362-1368`).
- A locked-out account can still reach `/users/confirm-required`, `/users/send-confirmation-email`, `/users/two-factor`, and the `/users/confirm/*` and `/profile/confirm_email/*` links (`lib/lightning_web/confirmation_lockout.ex:18-39`).
- Superuser, project role and MFA have no bearing here; project pages add `shared-project-scope` on top.

## 4. What it touches

**Reads**: `user_tokens` and `users` (session lookup, `accounts.ex:994-997`); `users.preferences` (`sidebar_collapsed`, `demo_banner.dismissed_at`, `accounts.ex:1388-1400`, `init_assigns.ex:38-48`); `users` count of superusers on every browser request while first setup is open (`accounts.ex:1341-1344`, `lib/lightning_web/plugs/first_setup.ex:127-149`)

**Writes**: `users.preferences` key `sidebar_collapsed` (`init_assigns.ex:88-89`, `accounts.ex:1417-1423`); `users.preferences` key `demo_banner.dismissed_at` (`lib/lightning_web/live/book_demo_banner.ex:29-37`); session keys `user_token` (from remember-me cookie), `live_socket_id`, `user_return_to` (`user_auth.ex:184-206`, `:490-492`)

**Immediate side effects**
- Assigns `current_user`, `sidebar_collapsed`, `banner`, `gdpr_banner` on mount (`init_assigns.ex:41-55`), and `current_path` / `current_uri` on every `handle_params` (`init_assigns.ex:63-82`); `shared-project-scope` relies on `current_uri` for its re-mount
- Writes `live_socket_id = "users_live:<user id>"` to the session so account-wide revocations can reach open pages (`user_auth.ex:151`, `:184-192`)
- A socket token is minted only for a fully authenticated, non-TOTP-pending, non-locked-out session (`user_auth.ex:378-392`)

**Deferred side effects**
- none here; the disconnect broadcast that consumes `live_socket_id` belongs to the proposed revocation flow

**External, non-transactional effects**
- "Schedule a call" posts name, email and message to the configured OpenFn workflow URL, then redirects the browser to Calendly with those fields in the query (`book_demo_banner.ex:55-73`)

**Depends on config**
- `require_email_verification` (`bootstrap.ex:387-389`), `book_demo_banner` (`lib/lightning/config.ex:268-284`, hard-coded off in `bootstrap.ex:864-867`), `gdpr_banner` (`config/config.exs:292`, `config.ex:287-288`), `allow_first_setup` (`bootstrap.ex:234`), `allow_signup` (`bootstrap.ex:380-381`), `Lightning.Extensions.Routing` session opts (`config/config.exs:50-61`)

**Product limits**
- 48-hour grace period before an unconfirmed account is locked out (`accounts.ex:1367`)
- Sessions last 60 days (`user_token.ex:34`; remember-me cookie `user_auth.ex:19`)

## 5. Scenarios

```gherkin
Feature: Authenticated session gate and app chrome
  In order to keep app pages limited to signed-in, active accounts
  As anyone using Lightning
  I want every signed-in page to check my session and give me the same chrome

  @S01 @pending
  Scenario: Signed-out visitor to a non-project page is sent to log in
    # Value: account-level data (credentials, tokens, profile) is never rendered to an anonymous browser.
    Given I am not logged in
    When I visit "/credentials"
    Then I am on "/users/log_in"
    And the flow "flow-login-return-to" has started for "/credentials"
    # user_auth.ex:290-300, :490-492; init_assigns.ex:22-24 on a websocket-only mount
    # Project pages: shared-project-scope S01

  @S02 @pending
  Scenario: A disabled account's existing session no longer opens pages
    # Value: disabling an account takes effect on sessions that are already logged in.
    Given I am logged in
    And an administrator disables my account
    When I reload "/projects"
    Then I am on "/users/log_in"
    # accounts.ex:994-1006, :329-332; test/lightning_web/live/account_revocation_teardown_test.exs:70-90

  @S03 @pending
  Scenario: A session waiting on its second factor is sent to finish it
    # Value: a stolen password alone never reaches app pages for an account with MFA.
    Given I have entered my password for an account with MFA enabled
    And I have not entered my authentication code
    When I visit "/projects"
    Then I am on "/users/two-factor"
    # user_auth.ex:302-303, :313-323

  @S04 @pending @variant:require-email-verification
  Scenario: An unconfirmed account past the deadline is sent to confirm
    # Value: instances that require verified emails don't serve data to unverified accounts after the grace period.
    Given my account was created 50 hours ago and my email is unconfirmed
    When I visit "/settings/users"
    Then I am on "/users/confirm-required"
    And I see "Your account is blocked pending email confirmation"
    # user_auth.ex:305-306, :327-351; init_assigns.ex:26-30; confirmation_lockout.ex:8-9, :43
    # test/lightning_web/live/confirmation_lockout_live_test.exs:43-97

  @S05 @pending @variant:require-email-verification
  Scenario: A locked-out account can still reach its confirmation page
    # Value: a locked-out user always has a way back in instead of a redirect loop.
    Given my account was created 50 hours ago and my email is unconfirmed
    When I visit "/users/confirm-required"
    Then I see "blocked pending email confirmation"
    # router.ex:246-250, confirmation_lockout.ex:25-27; confirmation_lockout_live_test.exs:99-112

  @S06 @pending @variant:require-email-verification
  Scenario: An unconfirmed account inside the deadline is warned
    # Value: users learn the confirmation deadline before they are locked out.
    Given my account was created 2 hours ago and my email is unconfirmed
    When I open "/projects"
    Then I see the page
    And I see "Please confirm your account before" followed by the deadline 48 hours after sign-up
    And the "Resend confirmation email" link points to "/users/send-confirmation-email"
    # lib/lightning_web/components/layout_components.ex:259-275; init_assigns_test.exs:76-84

  @S07 @pending
  Scenario: Collapsing the sidebar is remembered
    # Value: someone who wants more room for their work sets it once, not on every page.
    Given I am logged in with the sidebar expanded
    When I click "Toggle sidebar"
    Then the sidebar is collapsed
    When I open another page, or log in again later
    Then the sidebar is still collapsed
    # init_assigns.ex:38-45, :84-95; layout_components.ex:652-657; init_assigns_test.exs:91-137

  @S08 @pending @variant:book-demo-banner
  Scenario: Book-a-demo banner shows until dismissed
    # Value: hosted instances can offer new users a call, without nagging anyone who has said no.
    Given I am logged in and have never dismissed the book-a-demo banner
    When I open "/credentials"
    Then I see "What problem are you trying to solve with OpenFn?"
    When I dismiss the banner
    And I open "/projects"
    Then I do not see the banner
    # init_assigns.ex:46-54; book_demo_banner.ex:29-44; test/lightning_web/live/book_demo_banner_test.exs:19-77

  @S09 @pending @variant:book-demo-banner
  Scenario: Scheduling a call hands off to the booking page
    # Value: a prospect reaches the booking page with their details already filled in, and the team hears about it.
    Given the book-a-demo banner is showing
    When I click "Schedule a call"
    And I submit the form with an empty email
    Then I see "This field can't be blank"
    When I submit it with my email and a message
    Then my name, email and message are posted to the configured workflow URL
    And I am sent to the configured Calendly URL with those fields in the query
    And the banner is dismissed for me
    # book_demo_banner.ex:46-77; book_demo_banner_test.exs:79-141

  @S10 @pending @variant:gdpr-banner
  Scenario: The configured GDPR banner shows on app pages
    # Value: instances that must collect consent can show their consent banner wherever users work.
    Given the instance configures a GDPR banner component
    When I open "/credentials"
    Then I see the configured banner
    # init_assigns.ex:55; layouts/live.html.heex:101-106; test/lightning_web/live/profile_live_test.exs:817-821

  @S11 @pending @variant:first-setup-open
  Scenario: An instance with no superuser sends pages to first setup
    # Value: a fresh install can't be used until someone has created the administrator account.
    Given first setup is allowed
    And there is no superuser
    When I visit "/projects"
    Then I am on "/first_setup"
    # first_setup.ex:127-149; test/lightning_web/plugs/first_setup_test.exs:6-10
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| "Schedule a call" matches `{:ok, %{status: 200}}` on the external post; any other status or a network error crashes the LiveView | `book_demo_banner.ex:71` | the page crashes and reconnects, the banner stays, no redirect to Calendly | fix |
| A websocket-only mount that finds no valid session redirects to log in without storing the current path or a flash | `init_assigns.ex:23-24` vs `user_auth.ex:296-299` | after a session expires on an open page, logging back in lands on `/projects`, not where they were, and nothing says why | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The lockout check in `on_mount` only fires on websocket mounts; the HTTP plug refuses first. A page left open when the 48-hour deadline passes keeps working until it reconnects | `init_assigns.ex:26-30`, `init_assigns_test.exs:49-53` | decide |
| The book-a-demo banner only renders on views that place the `:banner` slot (11 views plus the workflow editor); settings-layout pages and others never show it | `layout_components.ex:237`, `grep "<:banner>"` across `lib/lightning_web/live/`, `workflow_live/collaborate.ex:239-241` | decide |
| The GDPR banner is rendered only by the live layout; the six admin pages on the settings layout never show it | `layouts/live.html.heex:101-106`; absent from `layouts/settings.html.heex` | decide |
| `:banner` is shared with the usage-limits banner; the collision is recorded in shared-usage-limits-banner 6.1 | `init_assigns.ex:46-54` | preserve |
| Ctrl/Cmd+M toggles the sidebar by clicking the toggle button | `assets/js/hooks/KeyHandlers.ts:363-390` | preserve |
| `current_path` is assigned without the query string, `current_uri` with it; the project picker and the scope re-mount depend on the split | `init_assigns.ex:69-82` | preserve |
| `:current_path` hook is skipped silently when `attach_hook` raises, to let unit tests use a bare socket | `init_assigns.ex:60-67` | preserve |
| BlockRoutes runs before `redirect_if_user_is_authenticated`, so a signed-in user visiting `/users/register` with signup off gets a plain-text 404 instead of being sent to `/projects` | `router.ex:31-42`, `:175-178`; `lib/lightning_web/plugs/block_routes.ex:63-75` | decide |
| A signed-in user visiting `/first_setup` after a superuser exists is redirected to `/projects`; with first setup disabled it is a plain-text 404 | `first_setup.ex:135-141`, `router.ex:38-41` | preserve |
| The lockout flash is added on the HTTP path only if no error flash is already set | `user_auth.ex:345-351` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Book-a-demo banner and its three events | `init_assigns.ex:46-54`, `book_demo_banner.ex` | `bootstrap.ex:864-867` hard-codes `enabled: false` with no env var; only reachable when a downstream deployment overrides config |
| GDPR banner render | `layouts/live.html.heex:101-106` | `config/config.exs:292` sets it to `false`; the component module is supplied by the deployment, not this repo |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Every mount runs a separate query for `sidebar_collapsed` though the user's preferences are already loaded | `init_assigns.ex:38-39`, `accounts.ex:1388-1393` | no | preserve |
| While first setup is allowed, every browser request counts superusers | `first_setup.ex:128-149`, `accounts.ex:1341-1344` | no | preserve |
| Hovering a collapsed sidebar expands it after 500 ms (the comment says 1 second) | `assets/js/hooks/index.ts:1060-1075` | yes | preserve |

### 6.5 Things seen but not understood

- The live and settings layouts also render the role-dependent menu (Admin menu and Sys info for superusers; Documentation, Community and Support for everyone else), the user menu and the global project picker (`layouts/live.html.heex:29-113`). That is app chrome every inheriting view gets, but it was not in the scope given for this annotation; no annotation owns it yet.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the menus, user menu and project picker in the layouts (6.5) be added here or get their own shared annotation?
- shared-usage-limits-banner section 2 lists "Users on instances with the book-a-demo banner enabled see it until they dismiss it" without a scenario; S08 here now owns it. Should that line move here?
- Should `:sudo_auth` (BackupCodesLive.Index) and `/dashboard` be listed as inheritors? Both attach InitAssigns but sit outside the four named live_sessions.

## Proposed flows

- `flow-login-return-to`: a signed-out GET to a signed-in page stores `user_return_to` (`user_auth.ex:490-492`) and redirects to `/users/log_in`; after a successful login, `redirect_with_return_to` sends the user back (`user_auth.ex:63-70`). Surfaces: any inheriting view, controller:user-session, the original view. This file asserts only the handoff (S01).
- `flow-account-revocation-teardown`: disabling an account, changing or resetting a password revokes tokens and broadcasts `disconnect` on `users_live:<id>` and `user_socket:<id>` (`accounts.ex:192`, `:934`, `:971`, `:1328`; `user_auth.ex:163-166`); every open page on every device drops and, on reconnect, is refused by this gate. Logout broadcasts on the session's own `live_socket_id` (`user_auth.ex:114-132`). Surfaces: profile / user admin, pubsub:users_live:<user_id>, any inheriting view. This file asserts only that `live_socket_id` is written (section 4) and that a reload is refused (S02). Test: `account_revocation_teardown_test.exs:28-67`.

## Proposed shared

none
