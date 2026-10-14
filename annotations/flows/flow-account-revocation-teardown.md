---
id: flow-account-revocation-teardown
type: flow
title: Revoking a user's sessions and tokens
status: not-started
owner:

trigger:
  entry: profile-account                  # also admin-users / admin-user-edit and profile-delete-account; each can start it
  exit: auth-login                        # every other browser and device; the tab that changed its own password exits on projects-dashboard
  surfaces:
    - profile-account                     # "Update password" (form_component.ex:57-78)
    - admin-users                         # "Delete" modal on /settings/users/:id/delete (user_live/components.ex:17-26)
    - admin-user-edit                     # the form where a superuser disables a user or changes password, email, role, support access (user_live/form_component.ex:57-68)
    - profile-delete-account              # /profile/:id/delete, same modal with logout: true (profile_live/components.ex:40-47)
    - email:account-deletion-scheduled    # deletion entries only (user_notifier.ex:205-224)
    - pubsub:users_live:<user_id>         # the /live transport of every open LiveView page (user_auth.ex:151, :165)
    - pubsub:user_socket:<user_id>        # the /socket transport: editor, run and AI channels (user_auth.ex:138, :164; user_socket.ex:11-13, :53-54)
    - workflow-editor-canvas
    - workflow-editor-run-viewer
    - workflow-editor-ai-assistant
    - controller:token-exchange           # /users/token_exchange/:token, password-change tab only (router.ex:180)
    - controller:user-log-out             # /users/log_out, own-deletion tab only (router.ex:71)
    - projects-dashboard                  # where the password-change tab lands (user_auth.ex:514)
    - auth-login
    - profile-tokens   # added by lead
    - auth-reset-password   # added by lead: a reset revokes sessions the same way (see auth-reset-password 6.5)
    - admin-live-dashboard   # added by lead
  reachable_when:
    - the actor is signed in (shared-authenticated-session)
    - admin entries: the actor is a superuser (`hooks.ex:40-51`; `policies/users.ex:19-21`)
    - own deletion: the target is the actor (`policies/users.ex:23-30`) and is not a superuser (`user.ex:418-428`)

inherits:
  - shared-authenticated-session    # the gate that refuses the revoked session on reload and on LiveView reconnect (its S02); writes live_socket_id
  - shared-editor-session           # the editor's own "disconnected" state while the /socket transport is down

url_params:
  - name: token (path segment of /users/token_exchange/:token)
    set_by: profile-account
    effect: url-safe base64 of a 30-second "auth" user token; exchanged once for a new session (user_session_controller.ex:55-67)

config_variants:
  default: { lightning.purge_deleted_after_days: 7 }   # read under this one (bootstrap.ex:273-277)
  no-purge: { lightning.purge_deleted_after_days: 0 }  # no nightly purge job; deletion entries still revoke (bootstrap.ex:306-309)

inventory:
  routes:
    - get /users/token_exchange/:token  UserSessionController :exchange_token   # router.ex:180, behind :redirect_if_user_is_authenticated
    - get /users/log_out  UserSessionController :delete                         # router.ex:71; own-deletion tab only
  events:
    - ProfileLive.FormComponent#save_password       # entry; owned by profile-account S08
    - UserLive.FormComponent#save                   # entry (:edit); owned by admin-user-edit
    - Components.UserDeletionModal#delete           # entry for admin-users and profile-delete-account
  js_hooks: []                                      # the /socket client is SocketProvider.tsx, not a hook
  policies:
    - Lightning.Policies.Users :access_admin_space (policies/users.ex:19-21)
    - Lightning.Policies.Users :delete_account (policies/users.ex:23-30)
  workers:
    - oban:accounts-purge-deleted                   # Lightning.Accounts perform/1, accounts.ex:92-130; cron bootstrap.ex:306-309
  api_endpoints: []                                 # API tokens are affected, not called; Tokens.verify/1 is the receiving gate
  emails:
    - email:account-deletion-scheduled              # user_notifier.ex:205-224
  config:
    - :lightning, :purge_deleted_after_days         # bootstrap.ex:273-277, :306-309
  not_reachable_here:
    - Accounts.reset_user_password/2 (accounts.ex:1318-1333); the same revocation, entered from the password reset email, which is outside this flow's entries (6.5)
    - UserAuth.log_out_user/1 broadcast on the session's own live_socket_id (user_auth.ex:114-132); logout hangs up pages but revokes only its own token (6.2)
    - UserLive.Index#cancel_deletion (user_live/index.ex:34-52); owned by admin-users

related:
  - lib/lightning/accounts.ex                       # update_user/3 and revoke_contexts (:177-221), update_user_password/3 (:919-940), schedule_user_deletion/2 (:948-977)
  - lib/lightning_web/controllers/user_auth.ex      # disconnect_user_sockets/1 (:163-166), fetch_current_user/2 (:175-192)
  - lib/lightning/tokens.ex                         # API token gate (:98-117, :190-218)
  - test/lightning_web/live/account_revocation_teardown_test.exs
  - test/lightning/accounts_test.exs                # :1382-1434, :1460-1506, :2014-2027
  - flow-login-return-to                            # a revoked user who signs in again on a page with a stored return path
flows: []
---

## 1. Purpose

When an account must lose access (its owner changes a password they think has leaked, a superuser
disables or demotes someone, or the account is being deleted), the change has to reach every browser
and device the account is already signed in on, not just the next login. Without this flow a stolen
session or a departed staff member could keep reading health data in an open tab or editor, or keep
calling the API, until they happened to reload.

## 2. What it does

A user changes their password, a superuser disables, demotes or deletes them, or the user deletes their own account; their session tokens (and, for a password change or deletion, API tokens) are deleted and both transports are told to disconnect; every open page, editor, run viewer and AI chat on every device drops and lands on the login page, while the tab that changed its own password signs back in through `/users/token_exchange/:token` and lands on `/projects`.

## 3. Who can do what

Sources: `lib/lightning/policies/users.ex:19-30`, `lib/lightning_web/hooks.ex:40-51`,
`lib/lightning/accounts/user.ex:338-343`, `:418-440`, `lib/lightning/accounts.ex:177-221`.

| Action (starts the flow) | Signed-in user, own account | Superuser, own account | Superuser, another user |
|--------------------------|-----------------------------|------------------------|-------------------------|
| Change password with current password (profile) | yes | yes | no |
| Set a new password without the current one (admin form) | no | yes | yes |
| Disable an account | no | yes | yes |
| Change email, role or support access (admin form) | no | yes | yes |
| Schedule deletion | yes, if not a superuser | no | yes, if the target is not a superuser |

| What is revoked | Own password change | Admin: disable, password, email, role, support access | Schedule deletion (either entry) |
|-----------------|---------------------|--------------------------------------------------------|----------------------------------|
| Browser sessions (`session`) | yes | yes | yes |
| Sudo and pending auth tokens | yes | no | yes |
| API tokens (`api`) | yes, deleted | no, kept; refused while the account is disabled | yes, deleted |
| Open pages and channels (both transports) | yes | yes | yes |

Sources: `accounts.ex:204-221`, `:604-610`, `:927-935`, `:964-972`; `tokens.ex:98-117`, `:207-217`.

**Preconditions beyond role**
- Own password change needs the current password (profile-account S09; `accounts.ex:919-923`).
- Deletion needs the target's email typed back (`user.ex:430-440`); superusers can't be scheduled (`user.ex:418-428`).
- An admin edit that changes only names, confirmation or scheduled-deletion-free fields revokes nothing (`accounts.ex:218-219`).

## 4. What it touches

**Hop 1: the revoking write (profile-account, admin-user-edit, admin-users, profile-delete-account)**
- Own password: one transaction updates `users.hashed_password` and deletes every `user_tokens` row for the user (`accounts.ex:924-931`; `user_token.ex:236-238`). No audit event.
- Admin edit: one transaction updates `users`, writes a `user` `updated` audit event when an actor is given, and deletes `user_tokens` in context `session` (or all contexts when `scheduled_deletion` is set) (`accounts.ex:181-201`, `:204-221`, `:223-231`). A superuser grant or superuser password change emits a `[:lightning, :accounts, :superuser_changed]` telemetry event (`accounts.ex:192-196`, `:233-260`).
- Schedule deletion: one transaction sets `scheduled_deletion` (now + `purge_deleted_after_days`), `disabled = true`, and deletes every `user_tokens` row (`accounts.ex:948-968`). No audit event on this path.

**Hop 2: disconnect broadcasts (pubsub)**
- After commit, `Endpoint.broadcast` of `disconnect` on `user_socket:<id>` and `users_live:<id>` (`user_auth.ex:163-166`; called from `accounts.ex:192`, `:934`, `:971`). Phoenix closes every transport registered under that id: `/live` transports carry `live_socket_id` from the session, written per user on every browser request (`user_auth.ex:175-192`); `/socket` transports identify as `user_socket:<id>` (`user_socket.ex:53-54`).

**Hop 3: deletion email (deletion entries only)**
- `send_deletion_notification_email/1` delivers "Your account has been scheduled for deletion" inline through the mailer after the broadcast; its result is discarded (`accounts.ex:971-973`; `user_notifier.ex:49-60`, `:205-224`).

**Hop 4: every other open page (pubsub:users_live)**
- The LiveView client reconnects; the rejoin's `on_mount` reads `session["user_token"]`, finds no user, and halts with a redirect to `/users/log_in` (`init_assigns.ex:17-24`). The redirect GET runs `fetch_current_user/2`, which finds nothing (`user_auth.ex:175-182`).

**Hop 5: editor, run viewer and AI chat (pubsub:user_socket)**
- `WorkflowChannel`, `RunChannel` and `AiAssistantChannel` all ride the one `/socket` (`user_socket.ex:11-13`), so all end with it. The client retries with `window.userToken`, minted once per page render from the now-deleted session token (`root.html.heex:20`; `user_auth.ex:378-392`; `SocketProvider.tsx:39-74`), and `connect/3` refuses it (`user_socket.ex:30-50`). The host LiveView's redirect (hop 4) takes the page away.

**Hop 6: the password-change tab (controller:token-exchange)**
- Before returning, the LiveView inserts an `auth` user token and redirects to `/users/token_exchange/<base64 token>` (`form_component.ex:66-78`; `accounts.ex:1051-1055`). The controller verifies the token is under 30 seconds old, deletes it, inserts a new `session` token, renews the session and redirects to `/projects` (`user_session_controller.ex:55-67`; `accounts.ex:1062-1072`; `user_token.ex:96-102`; `user_auth.ex:54-70`).

**Hop 7: the own-deletion tab (controller:user-log-out)**
- `push_navigate` to `/users/log_out` (`user_deletion_modal.ex:45-49`, `:89-90`), which deletes the (already deleted) session token, broadcasts on the session's `live_socket_id`, renews the session, clears the remember-me cookie and redirects to `/users/log_in` (`user_auth.ex:114-132`).

**Deferred side effects**
- API requests with a kept token are refused per request while the account is disabled or scheduled for deletion (`tokens.ex:98-117`, `:207-217`); deleted tokens fail the existence check (`tokens.ex:190-196`).
- Login attempts are refused with "This user account is disabled" or "This user account is scheduled for deletion" (`user_session_controller.ex:31-38`; `user_auth.ex:41-45`).
- `oban:accounts-purge-deleted` purges users whose `scheduled_deletion` has passed and who have no runs, project files or keychain credentials, one job per user, nightly at 02:15 (`accounts.ex:92-130`, `:43-79`; `bootstrap.ex:306-309`). Variant `no-purge` has no cron.

**External, non-transactional effects**
- The deletion email (hop 3); the account is already disabled if it fails.

**Depends on config**
- `purge_deleted_after_days` sets the deletion date and whether the purge job runs (`accounts.ex:949-953`; `bootstrap.ex:273-277`, `:306-309`).

**Product limits**
- The sign-back-in link is valid for 30 seconds (`user_token.ex:36`).

## 5. Scenarios

```gherkin
Feature: Revoking a user's sessions and tokens
  In order to cut off access the moment an account should lose it
  As a user protecting my account, or a superuser managing accounts
  I want every open page, editor and token for that account to stop working at once

  @S01 @pending
  Scenario Outline: Revoking an account ends its pages on every other browser
    # Value: a leaked session or a departed user can't keep reading or changing project data in a tab that was already open.
    Given "amara@example.org" is signed in on two browsers, A and B
    And browser B has "/projects" open
    When <actor> <revokes> from browser A
    Then browser B eventually is on "/users/log_in"
    And reloading "/projects" in browser B lands on "/users/log_in"
    # accounts.ex:192, :934, :971; user_auth.ex:163-166, :175-192; init_assigns.ex:17-24
    # account_revocation_teardown_test.exs:46-66 (topic broadcast), :69-90 (reload refused); accounts_test.exs:1384-1434, :1497-1506, :2014-2027

    Examples:
      | actor                                    | revokes                                              |
      | Amara                                    | changes her password on "/profile"                   |
      | a superuser                              | ticks "Disabled?" on her account and saves           |
      | a superuser                              | changes her role from superuser to user and saves    |
      | Amara                                    | deletes her account on "/profile/<her id>/delete"    |
      | a superuser                              | deletes her account from "/settings/users"           |

  @S02 @pending
  Scenario: The tab that changed its own password stays signed in
    # Value: a user who has just proved who they are with the new password isn't made to sign in again in the tab they used.
    Given I am signed in and on "/profile"
    When I change my password with my correct current password
    Then I am on "/projects"
    And I see "Password changed successfully."
    And the flow passed through "/users/token_exchange/<token>"
    # form_component.ex:66-78; user_session_controller.ex:55-67; profile_live_test.exs:141-153
    # see 6.1 row 1: in a real browser the self-disconnect may win the race

  @S03 @pending
  Scenario: The sign-back-in link works only once
    # Value: the link left in browser history after a password change can't be replayed to open a new session.
    Given I have just changed my password and been sent through "/users/token_exchange/<token>"
    And I have signed out
    When I open "/users/token_exchange/<token>" again
    Then I am on "/users/log_in"
    And I see "Invalid token"
    # accounts.ex:1062-1072 (deleted on exchange); user_token.ex:36, :96-102 (30 s); user_session_controller_test.exs:113-128

  @S04 @pending
  Scenario: An open workflow editor stops with the account
    # Value: a revoked user can't keep editing a workflow, following a run or chatting with the AI assistant through an editor they already had open.
    Given Bob has the workflow editor open on project "Malawi HIV" with the AI assistant panel showing
    When a superuser disables Bob's account
    Then Bob's editor channels are closed
    And Bob's editor cannot reconnect to "/socket"
    And Bob's page eventually is on "/users/log_in"
    # user_socket.ex:11-13, :30-54; user_auth.ex:164; user_socket_test.exs:55-66, :79-86
    # the editor's interim "You are disconnected. Reconnecting..." state is shared-editor-session's

  @S05 @pending
  Scenario: A disabled account can't sign in or use its API tokens until it is re-enabled
    # Value: disabling is a complete, reversible stop: the person loses every way in, and gets their integrations back without reissuing tokens if re-enabled.
    Given "bob@example.org" has an API token
    When a superuser disables Bob's account
    Then signing in as Bob shows "This user account is disabled"
    And a request to "/api/projects" with Bob's API token is refused with 401
    When a superuser re-enables Bob's account
    Then the same API token is accepted
    # accounts.ex:204-221 (session only); tokens.ex:98-117, :207-217; api_auth.ex:12-46; user_session_controller.ex:31-38
    # accounts_test.exs:1384-1404 asserts the token row is kept; acceptance after re-enable is read from code

  @S06 @pending
  Scenario Outline: A password change or deletion also ends API tokens
    # Value: an account that is leaving, or whose owner thinks it is compromised, can't keep being used by scripts holding its tokens.
    Given "amara@example.org" has an API token
    When <event>
    Then a request with that API token is refused with 401
    And the token no longer appears on "/profile/tokens"
    # accounts.ex:927-930, :964-967; tokens.ex:190-196; accounts_test.exs:1488-1495, :2014-2027

    Examples:
      | event                                                 |
      | Amara changes her password on "/profile"              |
      | Amara's account is scheduled for deletion             |

  @S07 @pending
  Scenario: Deleting an account tells its owner by email
    # Value: the owner learns their account was disabled and when it will be removed, and who to contact if that was a mistake.
    Given "amara@example.org" is not a superuser
    When her account is scheduled for deletion from "/profile/<her id>/delete" or "/settings/users"
    Then an email "Your account has been scheduled for deletion" is sent to "amara@example.org"
    And signing in as Amara shows "This user account is scheduled for deletion"
    # accounts.ex:971-973; user_notifier.ex:205-224; profile_live_test.exs:224-236; user_live_test.exs:329-342

  @S08 @pending
  Scenario: Routine admin edits don't sign anyone out
    # Value: correcting a name doesn't throw the person out of work they have open.
    Given Bob has "/projects" open
    When a superuser changes Bob's first name and saves
    Then Bob's page stays open
    And Bob is still signed in after a reload
    # accounts.ex:218-219; accounts_test.exs:1424-1434
```

Wrong-password refusal on the profile is profile-account S09; the reload gate is
shared-authenticated-session S02; the editor's disconnected state is shared-editor-session. They are
not restated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| On a password change the LiveView broadcasts `disconnect` to its own `/live` transport before returning the redirect to `/users/token_exchange/:token`; the transport may close first, the redirect is lost, and the reconnect finds the session deleted. Same as profile-account 6.1 row 2 | `accounts.ex:934`; `user_auth.ex:163-166`; `form_component.ex:62-78` | possibly "/users/log_in" with no message instead of "/projects" with "Password changed successfully."; LiveViewTest has no transport (`account_revocation_teardown_test.exs:12-14`) | decide (verify in a browser, then fix) |
| The same ordering on own deletion: the broadcast precedes `push_navigate` to `/users/log_out` | `accounts.ex:971`; `user_deletion_modal.ex:45-49`, `:89-90` | probably "/users/log_in" without "User scheduled for deletion" or "Logged out successfully."; the end page is the same | decide |
| A superuser who changes their own email, role or password in the admin form, or disables themselves, disconnects their own tab before `push_navigate` returns | `accounts.ex:192`; `user_live/form_component.ex:57-68` | the login page instead of "User updated successfully" | decide |
| `/users/token_exchange/:token` calls `Base.url_decode64!`, so a token that isn't valid base64 raises instead of showing "Invalid token" | `user_session_controller.ex:56` | a server error page for a mangled link | fix |
| The deletion modal on "/settings/users" says "This email doesn't match your current email" when a superuser types another user's email wrongly | `user.ex:430-440`; `user_live_test.exs:323-327` | copy that addresses the superuser as if it were their own account | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| API tokens are deleted on the user's own password change but kept when a superuser sets a new password, disables, or changes email, role or support access; the profile gives no warning that scripts will stop | `accounts.ex:927-930` vs `:204-221`; `accounts.ex:171-174` (doc); `accounts_test.exs:1384-1404` | decide |
| Other browsers land on "/users/log_in" with no message saying why they were signed out | `init_assigns.ex:22-24` | decide |
| Admin revocations delete only `session` tokens; `sudo_session` and `auth` rows survive (useless without a session, and `auth` expires in 30 s) | `accounts.ex:209-216`; `user_token.ex:35-36` | preserve |
| Confirming an email change through the emailed link doesn't revoke sessions, while a superuser changing the email does | `accounts.ex:702-728` vs `:212-216` | decide |
| Setting "Scheduled Deletion" directly in the admin form revokes every token and blocks login like a deletion, but sends no deletion email and skips the email confirmation | `user_live/form_component.html.heex:77-82`; `accounts.ex:205-206`; `user.ex:287-305` | decide |
| "Cancel deletion" re-enables the account but its tokens are already gone, so the user signs in again and must reissue API tokens; it writes no audit event | `accounts.ex:667-674`; `user_live/index.ex:34-52` | decide |
| The deletion email's delivery result is ignored | `accounts.ex:972` | decide |
| The `/socket` client keeps retrying with the page's stale token until the LiveView redirect replaces the page | `SocketProvider.tsx:39-74`; `root.html.heex:20` | preserve |
| Logging out hangs up the account's LiveView pages on every device but revokes only its own session, so the others reconnect and stay signed in | `user_auth.ex:110-132` | preserve |
| `live_socket_id` is keyed per user, not per session token as `phx.gen.auth` generates, so one broadcast reaches every browser | `user_auth.ex:140-151`; `account_revocation_teardown_test.exs:46-66` | preserve |
| `/users/token_exchange/:token` is behind `:redirect_if_user_is_authenticated`, so a browser that still has a valid session goes to "/projects" without consuming the token | `router.ex:176-180`; `user_auth.ex:271-279`; `user_session_controller_test.exs:130-137` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Sign-back-in `auth` token valid for 30 seconds | `user_token.ex:36`, `:96-102` | yes, if the redirect is slow | preserve |
| `/socket` tokens decrypt for two weeks, but only while the wrapped session exists | `user_socket.ex:39-45` | no | preserve |
| Purge job nightly at 02:15, only when `purge_deleted_after_days` > 0; default 7 days | `bootstrap.ex:273-277`, `:306-309` | yes, deletion date in the email | preserve |

### 6.5 Things seen but not understood

- The password reset email link (`reset_user_password/2`, `accounts.ex:1318-1333`) revokes and disconnects the same way, but it is not one of this flow's entries; it presumably belongs to a reset flow (auth-reset-password). Disposition: decide.
- Nothing in the suite watches a real transport close: `account_revocation_teardown_test.exs` subscribes to the topic as a stand-in (`:115-131`), and the websocket-only reconnect is not exercised (`:72-78`). S01, S02 and S04 need a browser test. Disposition: preserve.
- `schedule_user_deletion/2`'s doc says the purge cron never runs when the env var is unset, but `bootstrap.ex:277` defaults it to 7. Disposition: decide.
- Whether a flash put before `push_navigate` to a controller route (`/users/log_out`) survives is unclear even without the race. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should revoking API tokens on a user's own password change be kept, and made consistent with admin changes (6.2)? (owner: product)
- Does the password-change tab actually land on "/projects" in a real browser, and does the self-disconnect need to move after the redirect (6.1)?
- Should signed-out browsers be told why they were signed out (6.2)?
- Should confirming an email change sign out other sessions as an admin email change does (6.2)?

## Proposed flows

- none. Referenced: profile-account S08 (entry handoff), shared-authenticated-session S02 (reload refused), shared-editor-session (disconnected state), flow-login-return-to (signing back in). The password reset email entry is left to whoever owns auth-reset-password (6.5).

## Proposed shared

- none. Referenced: shared-authenticated-session, shared-editor-session.
