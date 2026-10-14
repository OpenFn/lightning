---
id: flow-log-out
type: flow
title: Log out
status: not-started
owner:

trigger:
  entry: shared-project-header            # the account menu's "Log out" on every app page; auth-confirmation-required also starts it
  exit: auth-login
  surfaces:
    - shared-project-header               # account menu "Log out" (layout_components.ex:173-181), rendered by live.html.heex:29-31 and settings.html.heex:29
    - auth-confirmation-required          # "Log out" link on the lockout page (user_confirmation_required_live.html.heex:125-129)
    - controller:user-log-out      # GET /users/log_out, UserSessionController.delete/2 (router.ex:66-71; user_session_controller.ex:69-73)
    - pubsub:users_live:<user_id>         # the session's live_socket_id; disconnects that account's /live transports (user_auth.ex:120-126)
    - auth-login                          # /users/log_in with "Logged out successfully."
  reachable_when:
    - none for the route itself: /users/log_out sits in the plain `:browser` scope, outside both `require_authenticated_user` and `redirect_if_user_is_authenticated` (router.ex:66-71), so a locked-out, TOTP-pending or signed-out browser reaches it (confirmation_lockout.ex:16-17)
    - the account menu renders only when `current_user` is assigned (live.html.heex:29-31)

inherits:
  - shared-authenticated-session    # writes live_socket_id on every request (user_auth.ex:175-192) and refuses the deleted token on the next request or LiveView mount (its S02 gate; init_assigns.ex:17-24)

url_params: []

config_variants:
  default: {}                                                                  # read under this one; the account menu entry
  require-email-verification: { lightning.require_email_verification: true }   # the only variant in which auth-confirmation-required can be reached (S02)
  custom-menus: { lightning.user_menu_items: %{component, assigns_keys} }      # replaces the account menu, including "Log out" (layout_components.ex:54-58, :135-140); shared-project-header's variant, not set in this repo

inventory:
  routes:
    - get /users/log_out  UserSessionController :delete      # router.ex:71
  events: []                                                 # both entries are plain links, not handle_event
  js_hooks: []
  policies: []                                               # no policy; the route is unauthenticated (router.ex:66-71)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :user_menu_items                           # layout_components.ex:54-58
  not_reachable_here:
    - UserAuth.disconnect_user_sockets/1 (user_auth.ex:163-166); account-wide revocation, owned by flow-account-revocation-teardown; logout does not call it (user_auth.ex:161)
    - UserSessionController.exchange_token/2 (user_session_controller.ex:55-67); owned by flow-account-revocation-teardown

related:
  - lib/lightning_web/controllers/user_session_controller.ex   # delete/2 :69-73
  - lib/lightning_web/controllers/user_auth.ex                 # log_out_user/1 :105-132, renew_session/1 :96-103, remember-me cookie :16-21
  - lib/lightning/accounts.ex                                  # delete_session_token/1 :1011-1014, delete_sudo_session_token/1 :1040-1044
  - lib/lightning_web/components/layout_components.ex          # user_menu_dropdown/1 :50-185
  - test/lightning_web/controllers/user_session_controller_test.exs   # :278-298
  - test/lightning_web/controllers/user_auth_test.exs                 # :229-327
  - test/lightning_web/confirmation_lockout_recovery_test.exs         # :46-80
  - flow-account-revocation-teardown   # revokes every session and token for an account; logout ends only this browser's session. Its own-deletion tab passes through this controller (its hop 7)
flows: []
---

## 1. Purpose

Anyone signed in to Lightning, including someone locked out pending email confirmation, needs to be
able to leave a browser so the next person at that machine cannot act as them. People use shared and
borrowed computers in clinics and field offices; if logging out left the session, a remember-me
cookie or an open tab usable, the next person could read or change health data under someone else's
account.

## 2. What it does

A signed-in user clicks "Log out" in the account menu (or on the confirm-your-email page); `GET /users/log_out` deletes this browser's session token, hangs up that account's LiveView pages, renews the session, clears the remember-me cookie and lands on `/users/log_in` with "Logged out successfully.", while the account's other browsers stay signed in.

## 3. Who can do what

Sources: `router.ex:66-71` (no auth pipeline), `live.html.heex:29-31`, `settings.html.heex:29`,
`user_confirmation_required_live.html.heex:125-129`, `user_session_controller.ex:69-73`.

| Action | Signed-out visitor | Signed-in user | Locked-out user (unconfirmed past deadline) | Superuser |
|--------|--------------------|----------------|---------------------------------------------|-----------|
| See "Log out" in the account menu | no | yes | no (every app page redirects to the lockout page) | yes |
| See "Log out" on the confirm-your-email page | no | no (redirected to /projects) | yes | no |
| Request /users/log_out | yes, a no-op that still redirects with the message | yes | yes | yes |

**Preconditions beyond role**
- none. There is no policy, CSRF token or confirmation step on this route (`router.ex:71`; 6.1).
- Under `custom-menus` the account menu entry is whatever the configured component renders (`layout_components.ex:135-140`).

## 4. What it touches

**Hop 1: the entry link (shared-project-header, auth-confirmation-required)**
- No server write. The account menu link uses `navigate` (`layout_components.ex:174-180`); the lockout page link uses `href` (`user_confirmation_required_live.html.heex:126`).

**Hop 2: controller:user-log-out**
- Puts the info flash "Logged out successfully." (`user_session_controller.ex:69-73`).
- Deletes the `user_tokens` row for this session's token in context `session` (`user_auth.ex:115-116`; `accounts.ex:1011-1014`; `user_token.ex:229-231`). Other `session` rows for the account are kept (`user_auth_test.exs:296-318`).
- Attempts to delete the `sudo_session` row named by the session's `sudo_token` (`user_auth.ex:117-118`; `accounts.ex:1040-1044`); in practice it deletes nothing (6.1).
- Broadcasts `disconnect` on the session's `live_socket_id`, read from the session rather than derived from the user, so a session still carrying the retired token-keyed id is reached too (`user_auth.ex:120-126`; `user_auth_test.exs:249-263`, `:265-294`).
- Renews the session id and clears the session, keeping only `user_return_to` (`user_auth.ex:96-103`, `:128-129`).
- Expires the `_lightning_web_user_remember_me` cookie (max age 0) (`user_auth.ex:20`, `:130`; `user_auth_test.exs:230-245`).
- Redirects to `/users/log_in` (`user_auth.ex:131`).
- No audit event, email, Oban job or telemetry.

**Hop 3: pubsub:users_live:<user_id>**
- Since `live_socket_id` is per user (`user_auth.ex:140-151`, `:186-192`), every `/live` transport the account has open on every browser closes and the client reconnects. Pages in a browser whose session was just cleared fail the mount gate and redirect to `/users/log_in` (`endpoint.ex:18-20`; `init_assigns.ex:17-24`); pages on other browsers remount on their own surviving token.
- The `/socket` transport (editor, run and AI channels) is not broadcast to (`user_auth_test.exs:296-318`); in this browser its reconnect is refused once the token is gone (`accounts.ex:994-998`), and the LiveView redirect takes the page away.

**Hop 4: auth-login**
- Renders the flash (auth-login S16). `fetch_current_user/2` finds no token and no cookie, so the login form renders rather than redirecting to /projects (`user_auth.ex:175-206`, `:271-279`).

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- `user_menu_items` replaces the account menu entry (`layout_components.ex:54-58`, `:135-140`).
- `require_email_verification` decides whether the lockout entry exists (`accounts.ex:1360-1368`).

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Log out
  In order to leave a computer without leaving my account open on it
  As a signed-in user
  I want logging out to end my session in this browser

  @S01 @pending
  Scenario: Logging out from the account menu ends this browser's session
    # Value: the next person at a shared computer can't open pages as the person who just left.
    Given I am signed in as "amara@example.org"
    And I am on "/projects"
    When I open the account menu and click "Log out"
    Then I am on "/users/log_in"
    And I see "Logged out successfully."
    When I visit "/projects"
    Then I am on "/users/log_in"
    # layout_components.ex:173-181; user_session_controller.ex:69-73; user_auth.ex:114-131; accounts.ex:1011-1014
    # user_session_controller_test.exs:279-288; user_auth_test.exs:230-245

  @S02 @pending @variant:require-email-verification
  Scenario: A locked-out user can log out from the confirm-your-email page
    # Value: someone signed in to the wrong account, or on a shared computer, can leave without first confirming an address they may not control.
    Given my account was created 50 hours ago and is unconfirmed
    And I am on "/users/confirm-required"
    When I click "Log out"
    Then I am on "/users/log_in"
    And I see "Logged out successfully."
    And my session no longer opens "/users/confirm-required"
    # user_confirmation_required_live.html.heex:125-129; router.ex:66-71; confirmation_lockout.ex:16-17
    # confirmation_lockout_recovery_test.exs:46-80 (token stops resolving); user_confirmation_required_live_test.exs:48 (link present)

  @S03 @pending
  Scenario: Logging out forgets "Keep me logged in"
    # Value: a browser that was told to remember me doesn't sign the next person back in as me after I log out.
    Given I signed in with "Keep me logged in for 60 days" checked
    When I log out
    And the browser session cookie is discarded
    And I visit "/projects"
    Then I am on "/users/log_in"
    # user_auth.ex:16-21, :130, :195-206; user_auth_test.exs:230-245 (cookie max_age 0, token deleted)

  @S04 @pending
  Scenario: Other open tabs in the same browser are signed out too
    # Value: a second tab left open on a shared computer doesn't keep showing or changing project data after I log out.
    Given I am signed in and have "/projects" open in two tabs of the same browser
    When I log out in the first tab
    Then the second tab eventually is on "/users/log_in"
    # user_auth.ex:120-126; endpoint.ex:18-20; init_assigns.ex:17-24
    # user_auth_test.exs:296-318 asserts the broadcast only; the transport reconnect is read from code (6.5)

  @S05 @pending
  Scenario: Logging out on one browser leaves my other browsers signed in
    # Value: logging out of a borrowed computer doesn't throw me out of work open on my own laptop; ending every session is flow-account-revocation-teardown.
    Given "amara@example.org" is signed in on browsers A and B
    And browser B has "/projects" open
    When Amara logs out on browser A
    Then browser B is still on "/projects"
    And reloading "/projects" on browser B shows the projects page
    # user_auth.ex:105-113, :115-116; accounts.ex:1011-1014
    # user_auth_test.exs:296-318 (other device's token still resolves)
```

The login page's own rendering of the flash is auth-login S16; the gate that refuses the deleted
token on reload is shared-authenticated-session S02; the account menu's contents are
shared-project-header S18. They are not restated beyond the steps above.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Logout deletes nothing in `sudo_session`: the session stores the base64 `sudo_token` from the query string, but `delete_sudo_session_token/1` matches it against the raw token bytes, so the re-auth grant survives logout until it expires (5 minutes) | `user_auth.ex:117-118`, `:226-231`; `accounts.ex:1040-1044`; `re_authenticate_live/new.ex:39-40`; `profile_live/mfa_component.ex:93-94`; `user_token.ex:35`; no test covers logout with a sudo token | nothing visible; a sudo token left in browser history or a shared link stays valid for the account for up to 5 minutes after logout (it still needs a signed-in session for that user, `accounts.ex:1030-1035`) | fix |
| Logout is a plain GET with no CSRF token or confirmation, so any cross-site top-level link (cookies are SameSite Lax by default, `endpoint.ex:12-16`) signs the user out | `router.ex:71`; `user_session_controller.ex:69-73`; `user_confirmation_required_live.html.heex:126` | being signed out unexpectedly after following a link, losing unsaved LiveView form state | decide (owner: security) |
| `renew_session/1` carries `user_return_to` across logout, so a path stored before logging out (for example by the re-auth redirect) sends the next person who signs in on that browser to the previous user's page | `user_auth.ex:96-103`, `:128-129`, `:396-407`, `:496-512` | after signing in, landing on another account's page, typically an access error instead of "/projects" | decide (owner: security) |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Logging out briefly disconnects and remounts the account's LiveView pages on every other browser, though they stay signed in; same row as flow-account-revocation-teardown 6.2 | `user_auth.ex:105-113`, `:120-126`; `user_auth_test.exs:296-318` | preserve |
| The account menu uses `navigate` (live navigation) to a controller route, so the client falls back to a full page load; the lockout page uses `href` | `layout_components.ex:174-180`; `user_confirmation_required_live.html.heex:126` | preserve |
| The action is `delete/2` and the test block says "DELETE /users/log_out", but the route is GET | `router.ex:71`; `user_session_controller_test.exs:278` | decide |
| A signed-out visitor to /users/log_out still sees "Logged out successfully." | `user_session_controller_test.exs:290-297`; `user_auth_test.exs:322-327` | preserve |
| The flash is put before the session is cleared and still arrives, because Phoenix writes the flash to the session when the response is sent | `user_session_controller.ex:69-73`; `user_auth.ex:128-129`; `user_session_controller_test.exs:285-287` | preserve |
| The broadcast topic is read from the session, not derived from the user, so sessions still holding the retired token-keyed id are reached | `user_auth.ex:120-126`; `user_auth_test.exs:249-263` | preserve |
| No audit event is written for logout | `user_auth.ex:114-132` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| The built-in account menu "Log out" link under `custom-menus` | `layout_components.ex:135-181` | a configured `user_menu_items` component replaces the whole block; not set in this repo |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| none | | | |

### 6.5 Things seen but not understood

- How an other tab in the same browser ends on the login page (S04) is read from code, not tested: after `clear_session` its LiveView reconnect either fails the CSRF check on the session read through `connect_info` and reloads, or remounts and halts at `init_assigns.ex:22-24`. Either path ends on "/users/log_in"; no test drives a real transport. Disposition: preserve.
- auth-login S16 already asserts the "Logged out successfully." landing; it duplicates S01's last steps and should reduce to an "ends here" handoff. Disposition: decide.
- flow-account-revocation-teardown names this controller `controller:user-log-out` (its surfaces, hop 7) and auth-login cites it as owned by that flow; this file uses `controller:user-log-out`. The two ids need reconciling. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should logout be a POST or DELETE with a CSRF token, as the action name and test describe suggest (6.1, 6.2)? (owner: security)
- Should `user_return_to` be cleared on logout so it can't carry over to the next account (6.1)? (owner: security)
- Should logging out be audited (6.2)? (owner: product)
- Should logout offer "Log out everywhere", which today only a password change gives (flow-account-revocation-teardown)? (owner: product)

## Proposed flows

- none. Referenced: flow-account-revocation-teardown (revoking every session; its own-deletion tab ends through this controller).

## Proposed shared

- none. Referenced: shared-authenticated-session (inherits), shared-project-header (entry, S18).
