---
id: flow-login-return-to
type: flow
title: Return to the requested page after login
status: not-started
owner:

trigger:
  entry: run-show                    # or workflow-health, projects-dashboard, or any GET route behind :require_authenticated_user (router.ex:189-190, :349)
  exit: run-show                     # the page that was asked for; projects-dashboard when nothing was stored (user_auth.ex:69, :514)
  surfaces:
    - run-show
    - workflow-health
    - auth-login
    - external:oidc-provider         # only under sso-provider
    - controller:oidc-callback       # only under sso-provider (oidc_controller.ex:242-261)
    - auth-two-factor                # only for accounts with MFA enabled
    - projects-dashboard             # fallback exit
  reachable_when:
    - the visitor has no valid session or remember-me cookie (user_auth.ex:175-206, :290)
    - the request is a browser GET; JSON requests get a 401 and other methods store nothing (user_auth.ex:291-293, :490-494)
    - typical sources are a link in email:failure-alert, email:project-digest or email:project-addition, a bookmark, or a link a colleague pasted (run-show S19, workflow-health S25, flow-collaborator-added-email S02)

inherits:
  - shared-authenticated-session     # the gate that starts this flow (its S01) and the two-factor gate (its S03)
  - shared-project-scope             # the gate the returned visitor passes again on landing (its S01 to S05)

url_params: []                       # the return path is held in the session, never in a URL parameter (user_auth.ex:490-492; user_session_controller.ex:8-13)

config_variants:
  default: {}                                                         # read under this one
  sso-provider: { auth provider configured at /settings/authentication } # AuthProviders.get_handlers/0 non-empty (user_session_controller.ex:75-85; router.ex:282-283)
  require-email-verification: { lightning.require_email_verification: true }   # owned by shared-authenticated-session; affects 6.2 only
  init-project-for-new-user: { lightning.init_project_for_new_user: true }     # bootstrap.ex:384; affects 6.2 only

inventory:
  routes:
    - get /users/log_in  UserSessionController :new                  # router.ex:181
    - post /users/log_in  UserSessionController :create              # router.ex:182
    - get /users/two-factor  UserTOTPController :new                 # router.ex:192
    - post /users/two-factor  UserTOTPController :create             # router.ex:193
    - get /authenticate/:provider  OidcController :show              # router.ex:76, sso-provider
    - get /authenticate/:provider/callback  OidcController :new      # router.ex:77, sso-provider
  events: []
  js_hooks: []
  policies:
    - LightningWeb.UserAuth.require_authenticated_user/2 (user_auth.ex:288-311)
    - Lightning.Accounts.login_blocked?/1 (accounts.ex:329-332)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - Lightning.AuthProviders handlers (sso-provider)
  not_reachable_here:
    - UserSessionController.exchange_token/2 also calls redirect_with_return_to (user_session_controller.ex:55-66); reached from first setup and the profile form (first_setup_live/superuser.ex:59, profile_live/form_component.ex:75), not from this flow
    - UserAuth.require_sudo_user/2 stores the same session key for the re-authenticate flow (user_auth.ex:397-410, :496-512; re_authenticate_live/new.ex:9); a separate journey
    - UserRegistrationController.create/2 (registration ends the flow differently; 6.2)

related:
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/controllers/user_session_controller.ex
  - lib/lightning_web/controllers/user_totp_controller.ex
  - lib/lightning_web/controllers/oidc_controller.ex
  - flow-collaborator-added-email     # its S02 runs this flow from email:project-addition
  - flow-export-project-yaml          # its S05 asserts the redirect; this flow owns the return
  - flow-failure-alert-email          # run-show S19 and workflow-health S25 start this flow from its links
  - flow-digest-email                 # its health link can start this flow
flows: []
---

## 1. Purpose

People reach Lightning through links: a failure alert pointing at a run, a digest pointing at a
workflow's health, an access email pointing at a project, a URL a colleague pasted. If they aren't
signed in on that browser, this flow lets them log in, through two-factor if their account needs it,
and puts them back on the exact page the link named. Without it every link from an inbox on a fresh
device would end on the projects list, and the person would have to find the run or workflow again.

## 2. What it does

Signed-out visitor opens a deep link; the gate remembers the path and query and sends them to log in; they enter their password (or use the external provider) and, if enrolled, a code or backup code; they land on the page they asked for, or on the projects list if nothing was remembered.

## 3. Who can do what

Sources: `user_auth.ex:288-311`, `:490-494`, `:63-70`; `user_session_controller.ex:31-53`;
`user_totp_controller.ex:17-41`; `oidc_controller.ex:242-261`. Landing is then decided by the
destination's own gates (shared-authenticated-session, shared-project-scope).

| Action | Signed-out visitor | Account with MFA | Disabled / scheduled for deletion | Non-member of the linked project |
|--------|--------------------|------------------|-----------------------------------|----------------------------------|
| Have the requested path remembered | yes (GET only) | yes (GET only) | yes (GET only) | yes (GET only) |
| Return to it after password login | yes | after a valid code | no, login refused (`user_session_controller.ex:32-38`; `user_session_controller_test.exs:184-214`) | lands, then refused by shared-project-scope S03 |
| Return to it after external-provider login | yes (sso-provider) | after a valid code | no (`oidc_controller.ex:242-248`) | as above |

**Preconditions beyond role**
- The return path is taken only from the server's own view of the blocked GET (`current_path(conn)`, path plus query string), never from a parameter the visitor supplies (`user_auth.ex:490-492`).
- It survives the session renewal at login (`user_auth.ex:96-103`) and is deleted once used (`user_auth.ex:68`).
- A page whose session lapses while open (websocket-only mount) redirects without storing a path; that gap is recorded in shared-authenticated-session 6.1 and is not repeated here.

## 4. What it touches

**Reads**
- Hop 1 (blocked GET): `user_tokens`, `users` when a session or remember-me cookie is present (`user_auth.ex:175-206`; `accounts.ex:994-997`)
- Hop 2 (log in): `users` by email and password (`user_session_controller.ex:18`); under sso-provider, the provider's token and userinfo (`oidc_controller.ex:46-63`)
- Hop 3 (two-factor): `user_totps` or `user_backup_codes` (`accounts.ex:463-483`)
- Hop 4 (landing): whatever the destination view reads

**Writes**
- Hop 1: session key `user_return_to` (`user_auth.ex:491`)
- Hop 2: `user_tokens` insert, a "session" token (`user_auth.ex:28-31`; `accounts.ex:985-989`); session renewed and cleared except `user_return_to` (`user_auth.ex:96-103`); session key `user_totp_pending` for MFA accounts (`user_auth.ex:478-480`)
- Hop 3: `user_totps.last_totp_at` on a valid code (`user_totp.ex:45-56`), or `user_backup_codes.used_at` on a valid backup code (`accounts.ex:485-502`); `user_totp_pending` deleted (`user_auth.ex:486-488`)
- Hop 4 (redirect): `user_return_to` deleted; remember-me cookie written when "Keep me logged in for 60 days" was ticked, or always on the external-provider path (`user_auth.ex:63-79`; `oidc_controller.ex:260`)

**Immediate side effects**
- none beyond the writes above; no audit event, email or broadcast at any hop

**Deferred side effects**
- none

**External, non-transactional effects**
- sso-provider: a redirect to and back from the external identity provider (`oidc_controller.ex:17-28`)

**Depends on config**
- `sso-provider`: shows "via external provider" on the login page (`user_session_html/new.html.heex:56-72`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Return to the requested page after login
  In order to land where a link pointed
  As someone opening a Lightning link while signed out
  I want to log in and be taken straight to that page

  @S01 @pending
  Scenario: A run link opened while signed out returns to the run and step after login
    # Value: a link from an alert or a colleague reaches the exact run and step it named, not the project list.
    Given I am not logged in
    And I am an editor on project "Malawi HIV" with run "R" whose step "S" failed
    When I open "/projects/<project_id>/runs/<R id>?step=<S id>"
    Then I am on "/users/log_in"
    When I log in with my email and password
    Then I am on "/projects/<project_id>/runs/<R id>?step=<S id>"
    And the flow ends on run-show with step "S" selected
    # user_auth.ex:290-299, :490-491, :96-103, :63-70; user_session_controller.ex:47-50
    # user_auth_test.exs:501-516 (path and query stored); user_session_controller_test.exs:250-262 (redirect to stored path)

  @S02 @pending
  Scenario Outline: An MFA account returns to the requested page after its second factor
    # Value: protecting an account with two-factor doesn't cost the person the page they were going to.
    Given I am not logged in
    And my account has MFA enabled
    When I open the health page of workflow "Daily sync"
    And I log in with my email and password
    Then I am on "/users/two-factor"
    When I enter a valid <factor>
    Then I am on the health page of workflow "Daily sync"
    # user_session_controller.ex:40-46; user_totp_controller.ex:17-24; user_auth.ex:97-102
    # user_totp_controller_test.exs:108-122, :168-183

    Examples:
      | factor              |
      | authentication code |
      | backup code         |

  @S03 @pending
  Scenario: A wrong password or code doesn't lose the destination
    # Value: a typo on the way in still ends on the page the link named.
    Given I am not logged in
    And my account has MFA enabled
    When I open a run link
    And I log in with a wrong password
    Then I see "Invalid email or password"
    When I log in with the right password
    And I enter a wrong authentication code
    Then I see "Invalid two-factor authentication code"
    When I enter a valid authentication code
    Then I am on the run page I opened
    # user_session_controller.ex:22-25 and user_totp_controller.ex:25-29 re-render without touching the session
    # no test covers the retry path

  @S04 @pending
  Scenario: Logging in with nothing requested lands on the projects list
    # Value: someone who opens the login page directly arrives at a known starting point.
    Given I am not logged in
    When I open "/users/log_in" directly
    And I log in
    Then I am on "/projects"
    And the flow ends on projects-dashboard
    # user_auth.ex:69, :514; user_auth_test.exs:193-197; user_session_controller_test.exs:151-164

  @S05 @pending
  Scenario: A remembered destination is used once
    # Value: an old link doesn't keep hijacking later logins on the same browser.
    Given I opened a run link while signed out and logged in, landing on the run
    When I log out and log in again from "/users/log_in"
    Then I am on "/projects"
    # user_auth.ex:68; user_auth_test.exs:199-207 (refutes user_return_to after redirect)

  @S06 @pending @variant:sso-provider
  Scenario: Logging in through the external provider returns to the requested page
    # Value: organisations using single sign-on get the same deep links as password users.
    Given an external authentication provider is configured
    And I am not logged in
    When I open the health page of workflow "Daily sync"
    And I click "via external provider" and sign in at the provider
    Then I am on the health page of workflow "Daily sync"
    # user_session_controller.ex:75-85; oidc_controller.ex:17-28, :250-261; user_auth.ex:97-102
    # oidc_controller_test.exs:95-103 asserts only "/projects" with no stored path; no test reads a stored path on this route

  @S07 @pending
  Scenario: Returning to a project page re-checks access
    # Value: a forwarded link never gives a project's data to someone who logs in but isn't on the project.
    Given "chen@example.org" is a registered user not on project "Malawi HIV"
    And Chen is not logged in
    When Chen opens a run link in project "Malawi HIV" and logs in
    Then Chen is on "/projects"
    And Chen sees "Not Found"
    # user_auth.ex:63-70 hands off to shared-project-scope S03 (hooks.ex:122-124); this flow asserts only the handoff
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A session waiting on its second factor that opens a different deep link is sent to two-factor without updating the stored path | `user_auth.ex:302-303`, `:313-322` | after verifying, they land on the first link they opened, not the one they just clicked | fix |
| Logout renews the session but keeps any pending `user_return_to` (set by a signed-out GET or by the sudo gate and never used) | `user_auth.ex:96-103`, `:128-131`, `:406` | the next login on that browser, possibly by someone else, lands on a page the previous user asked for (still subject to that page's gates) | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The redirect to login carries no flash, so the login page doesn't say why the visitor is there or that they will be returned | `user_auth.ex:296-299` | decide |
| The URL fragment never reaches the server, so a link to a run's "#output" or "#input" tab returns to the run on the Log tab | `user_auth.ex:491`; `tabbed.ex:125-136` | decide |
| Only GET requests store a path; a signed-out POST or PUT goes to login and then to `/projects` | `user_auth.ex:494`; `user_auth_test.exs:518-524` | preserve |
| JSON requests are answered 401 with nothing stored, so the health page's API calls never set the return path | `user_auth.ex:291-293` | preserve |
| One session key: opening two deep links in two tabs before logging in returns to whichever was opened last | `user_auth.ex:491` | decide |
| A visitor who registers instead of logging in is sent to their first project's new-workflow page when they have a project (always under init-project-for-new-user), and to the stored path only when they have none | `user_registration_controller.ex:13-24`, `:40-50`; `bootstrap.ex:384` | decide |
| Under require-email-verification, a locked-out account consumes the stored path at login and is then sent to `/users/confirm-required`; after confirming it does not go back | `user_auth.ex:68`, `:305-306` | decide |
| Visiting `/users/two-factor` with no second factor pending redirects to `/projects` | `user_totp_controller.ex:33-41` | preserve |
| A signed-in visitor opening `/users/log_in` goes to `/projects` and any pending path is left in the session | `user_auth.ex:271-279`; `user_session_controller_test.exs:70-75` | preserve |
| The second-factor page carries the "Keep me logged in for 60 days" choice in a hidden field and in the switch-method link, so it survives two-factor; the external-provider path always sets it | `user_session_controller.ex:41-46`; `user_totp_html/new.html.heex:40`, `:78-80`; `oidc_controller.ex:255`, `:260`; `user_totp_controller_test.exs:89-100` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| The stored path, query string included, lives in the signed cookie session, which is capped at 4 KB by Plug; a very long filtered URL could overflow it | `endpoint.ex:12-16`; `user_auth.ex:491` | only for extreme URLs; not tested | preserve |

### 6.5 Things seen but not understood

- The LiveView project-scope hook also redirects a missing user to `/users/log_in` without storing a path (`hooks.ex:64-72`). For a first visit the HTTP plug always runs first, so this branch seems reachable only on a websocket-only mount, the case already recorded in shared-authenticated-session 6.1. Not confirmed by a test.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a pending return path be dropped at logout (6.1), and should the latest deep link win while a second factor is pending (6.1)?
- Should the login page say "Log in to continue" when a path is pending (6.2)?
- Should a registering visitor be returned to the link they opened (6.2)?
- flow-collaborator-added-email S02 lands on workflows-index, which is not in `surfaces`; should every signed-in view that is an email destination be listed, or is "any signed-in page" enough for flow lint?

## Proposed flows

none. Referenced: flow-collaborator-added-email (S02 runs this flow), flow-export-project-yaml (S05 asserts the redirect only), flow-failure-alert-email and flow-digest-email (their links start this flow via run-show S19 and workflow-health S25).

## Proposed shared

none. Referenced: shared-authenticated-session (S01 and S03 are this flow's starting gates), shared-project-scope (S03 is the landing gate in S07).
