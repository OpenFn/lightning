---
id: flow-first-superuser-sign-in
type: flow
title: Create the first superuser and sign in
status: not-started
owner:

trigger:
  entry: first-setup
  exit: projects-dashboard
  surfaces:
    - first-setup                         # "Save" on /first_setup creates the superuser and redirects (superuser.ex:44-62)
    - controller:token-exchange           # GET /users/token_exchange/:token, UserSessionController.exchange_token/2 (router.ex:180; user_session_controller.ex:55-67); shared with flow-account-revocation-teardown
    - projects-dashboard                  # /projects, where the new superuser lands with "Superuser account created." (user_auth.ex:514)
    - admin-user-edit   # added by lead (link lint)
  reachable_when:
    - first-setup-open: `allow_first_setup` is true, which bootstrap sets whenever `SERVICE_ACCOUNT_PUBLIC_KEY` is unset (`bootstrap.ex:230-234`); otherwise first-setup refuses the page (its S09, S10)
    - no user has role superuser when /first_setup is loaded (`superuser.ex:69-73`; `accounts.ex:1341-1344`); save does not re-check (first-setup 6.1)
    - the browser holds no valid session, or the handoff is skipped (6.1 row 2): the exchange route is behind `:redirect_if_user_is_authenticated` (`router.ex:175-180`; `user_auth.ex:271-279`)

inherits:
  - shared-authenticated-session    # the :browser pipeline on every hop (router.ex:21-43): fetch_current_user, and the FirstSetup redirect (its S11) that sends the operator to the entry and stops once this flow has created the superuser; on /projects its S01 to S06 gates and InitAssigns run for the new session

url_params:
  - name: token (path segment of /users/token_exchange/:token)
    set_by: first-setup
    effect: url-safe base64 of a 32-byte random `auth` user token, valid 30 seconds and exchanged once for a new session (superuser.ex:60; user_token.ex:36, :67-72, :96-102; user_session_controller.ex:55-67)

config_variants:
  first-setup-open: { lightning.allow_first_setup: true }   # read under this one; the only variant in which the flow can start (bootstrap.ex:230-234; first_setup_live_test.exs:6-53)

inventory:
  routes:
    - live /first_setup  FirstSetupLive.Superuser :show                       # router.ex:69; owned by first-setup
    - get /users/token_exchange/:token  UserSessionController :exchange_token  # router.ex:180; also listed by flow-account-revocation-teardown
  events:
    - FirstSetupLive.Superuser#save                                           # entry; superuser.ex:44-67, owned by first-setup S01
  js_hooks: []
  policies:
    - LightningWeb.Plugs.FirstSetup (plugs/first_setup.ex:11-33)              # runs on every hop; lets the exchange and /projects through once the superuser exists
    - LightningWeb.UserAuth.redirect_if_user_is_authenticated/2 (user_auth.ex:271-279)
  workers: []
  api_endpoints: []
  emails: []                                                                  # nothing is sent on any hop (accounts.ex:543-547; extensions/account_hook.ex:20-26; user_session_controller.ex:55-67)
  config:
    - :lightning, :allow_first_setup                                          # plugs/first_setup.ex:12; superuser.ex:17
  not_reachable_here:
    - UserAuth.maybe_write_remember_me_cookie/2 remember-me branch (user_auth.ex:72-75); the exchange passes no params, so no remember-me cookie is written (user_session_controller.ex:65)
    - FirstSetupLive.Superuser#validate (superuser.ex:29-42); owned by first-setup

related:
  - lib/lightning_web/live/first_setup_live/superuser.ex          # save :44-67, apply_action :69-81
  - lib/lightning_web/controllers/user_session_controller.ex     # exchange_token/2 :55-67
  - lib/lightning_web/controllers/user_auth.ex                   # new_session/2 :54-58, redirect_with_return_to/2 :63-70, renew_session/1 :96-103, signed_in_path/1 :514
  - lib/lightning/accounts.ex                                    # register_superuser/1 :543-547, generate_user_session_token/1 :985-989, generate_auth_token/1 :1051-1055, exchange_auth_token/1 :1062-1071, get_user_by_auth_token/1 :1076-1079, delete_auth_token/1 :1084-1087, has_one_superuser?/0 :1341-1344
  - lib/lightning/accounts/user_token.ex                         # @auth_validity_in_seconds :36, build_token/2 :67-72, verify_token_query "auth" :96-102
  - lib/lightning_web/plugs/first_setup.ex
  - lib/lightning_web/components/layouts/live.html.heex          # flash :92-93, "Admin Menu" for superusers :45-49
  - test/lightning_web/live/first_setup_live_test.exs            # :31-52, end to end
  - test/lightning_web/controllers/user_session_controller_test.exs   # :86-137
  - test/lightning/accounts_test.exs                             # :1551-1568
  - flow-account-revocation-teardown   # the other flow through controller:token-exchange; owns its single-use (S03), mangled-token crash (6.1), signed-in skip (6.2) and 30-second limit (6.4)
flows: []
---

## 1. Purpose

Whoever installs Lightning needs to come out of first setup already signed in as the administrator
they just created, ready to create projects and users. If the handoff failed, a fresh instance would
have an administrator nobody is signed in as, and if first setup stayed open afterwards, anyone else
reaching the instance could keep being sent to a page that hands out superuser accounts.

## 2. What it does

1. On a fresh instance with no superuser (and first setup allowed), whoever visits any page is sent to the first-setup form.
2. They fill in their name, email and password and save; the superuser account is created. No email is sent.
3. The page hands them straight on through a one-time sign-in link that lasts 30 seconds, which starts a fresh session.
   - If the link arrives late, they land on the login page with "Invalid token", but the account exists and they can sign in with the password they chose
4. They land on the projects list as the new superuser, with "Superuser account created." and the admin menu showing; from then on nobody is sent to first setup.

**Straightforwardness: 3 of 5.** The happy path is a one-step setup, but the edges around stale tabs and browsers that are already signed in are easy to miss and matter because they hand out administrator access.

### Most surprising behaviours

- **(2)** A first-setup tab left open from before the first superuser was created can still be saved, and it creates and signs in a second superuser. (6.1)
- **(3)** In a browser already signed in as someone else, the handoff is skipped: the projects list says "Superuser account created." but the browser is still signed in as the old account. (6.1)
- **(3)** If the sign-in link is opened twice within the 30 seconds, both browsers may get a superuser session. Not confirmed to be reachable in practice. (6.1)
- **(3)** Demoting the only superuser may send the instance back into first setup, and disabling them may leave it with no usable administrator. This path wasn't followed. (6.5)
- **(4)** The page the operator first tried to open isn't remembered; they always end on the projects list. (6.2)

## 3. Who can do what

Sources: `router.ex:21-43`, `:66-69`, `:175-180`; `plugs/first_setup.ex:11-33`; `superuser.ex:14-22`,
`:44-81`; `user_auth.ex:271-279`. No policy module is involved; each hop is gated by instance state
and session state, not by role.

| Action | Visitor, no superuser yet, signed out | Visitor, no superuser yet, browser already signed in | Anyone, superuser exists |
|--------|-----|-----|-----|
| Start the flow (save on /first_setup) | yes | yes | no, /first_setup redirects to /projects (first-setup S07, S08; but see first-setup 6.1 on stale tabs) |
| Be signed in by the handoff | yes | no, the exchange redirects to /projects on the existing session (6.1) | n/a |
| Be forced to /first_setup from other pages | yes | yes | no |

**Preconditions beyond role**
- The handoff token is valid for 30 seconds after save and only once (`user_token.ex:36`, `:96-102`; `accounts.ex:1062-1071`).
- The account has no MFA at creation, so the exchange does not route through TOTP (`user_session_controller.ex:55-67`; compare `:40-46` for password login).

## 4. What it touches

**Hop 1: save on first-setup**
- One transaction inserts the `users` row with role `superuser`, `confirmed_at` unset (`accounts.ex:543-547`; `extensions/account_hook.ex:20-26`; `user.ex:230-239`).
- After that transaction commits, a separate insert writes one `user_tokens` row, context `auth` (`superuser.ex:60`; `accounts.ex:1051-1055`; `user_token.ex:67-72`).
- Flash "Superuser account created." and a full redirect to `/users/token_exchange/<base64url token>` (`superuser.ex:52-62`).
- No audit event, email, broadcast or job.

**Hop 2: controller:token-exchange**
- The :browser pipeline runs first: `fetch_current_user` and the FirstSetup plug, which now counts one superuser and lets the request through (`router.ex:28-29`; `plugs/first_setup.ex:27-29`); then `redirect_if_user_is_authenticated` (`router.ex:175`).
- Reads the `auth` token joined to `users` where it is under 30 seconds old (`accounts.ex:1076-1079`; `user_token.ex:96-102`).
- Deletes that `auth` token and inserts a `session` token (`accounts.ex:1065-1066`, `:985-989`, `:1084-1087`).
- Renews the session, clears it except `user_return_to`, writes `user_token`, and redirects to `user_return_to` or `/projects` (`user_auth.ex:54-58`, `:63-70`, `:96-103`, `:514`). No remember-me cookie (`user_session_controller.ex:65`).
- On an unknown or expired token: flash "Invalid token" and redirect to `/users/log_in`; nothing is written or deleted (`user_session_controller.ex:57-60`).

**Hop 3: projects-dashboard**
- `fetch_current_user` finds the new session and writes `live_socket_id` (`user_auth.ex:175-192`); the page renders the flash and, for a superuser, the "Admin Menu" and "Sys Info" side menu entries (`layouts/live.html.heex:45-57`, `:92-93`).
- From here on every browser request still counts superusers, now finding one, so no page is redirected to /first_setup (`plugs/first_setup.ex:12`, `:27-29`; shared-authenticated-session 6.4).

**Deferred side effects**
- An `auth` token that is never exchanged stays in `user_tokens`; nothing in this flow deletes it (`accounts.ex:1051-1055`, `:1062-1071`).

**External, non-transactional effects**
- none

**Depends on config**
- `allow_first_setup` / `SERVICE_ACCOUNT_PUBLIC_KEY` (`bootstrap.ex:230-234`): the flow exists only under first-setup-open.

**Product limits**
- The handoff must complete within 30 seconds of save (`user_token.ex:36`); past that the operator signs in on the log in page (S03).

## 5. Scenarios

```gherkin
Feature: Create the first superuser and sign in
  In order to start administering a fresh Lightning install
  As the person who installed it
  I want to come out of first setup signed in as the administrator I created

  @S01 @pending @variant:first-setup-open
  Scenario: Operator creates the first superuser and lands on projects signed in
    # Value: the operator goes straight from install to administering the instance, without a second sign-in.
    Given first setup is allowed
    And there is no superuser
    And my browser is not signed in
    When I visit "/projects"
    Then I am on "/first_setup"
    When I fill in first name "Test", last name "McTest", email "foo@example.com"
    And I fill in password and password confirmation "1234567890ab"
    And I click "Save"
    Then the flow passed through "/users/token_exchange/<token>"
    And I am on "/projects"
    And I see "Superuser account created."
    And I am signed in as "foo@example.com"
    And I see "Admin Menu" in the side menu
    # superuser.ex:44-62; accounts.ex:543-547, :1051-1071; user_session_controller.ex:55-67;
    # user_auth.ex:54-70, :514; layouts/live.html.heex:45-49, :92-93; first_setup_live_test.exs:31-52

  @S02 @pending @variant:first-setup-open
  Scenario: Once the superuser exists, other visitors are no longer sent to first setup
    # Value: after the administrator is created, the rest of the instance opens up and nobody else is offered a page that creates superusers.
    Given I have just completed first setup as "foo@example.com"
    When another browser that is not signed in visits "/users/log_in"
    Then it is on "/users/log_in"
    And it sees the log in form
    # plugs/first_setup.ex:12, :27-29; accounts.ex:1341-1344
    # first_setup_test.exs:12-18 does not show this (see first-setup 6.5)

  @S03 @pending @variant:first-setup-open
  Scenario: A handoff that arrives after 30 seconds still leaves a usable administrator
    # Value: a stalled redirect doesn't strand the operator; the account they created is kept and they can sign in with the password they chose.
    Given first setup is allowed
    And there is no superuser
    When I save the first setup form as "foo@example.com" with password "1234567890ab"
    And the redirect reaches "/users/token_exchange/<token>" more than 30 seconds later
    Then I am on "/users/log_in"
    And I see "Invalid token"
    And a user "foo@example.com" exists with role superuser
    When I log in as "foo@example.com" with password "1234567890ab"
    Then I am on "/projects"
    # user_token.ex:36, :96-102; user_session_controller.ex:57-60; accounts.ex:543-547 (committed before the token, superuser.ex:50-60)
    # user_session_controller_test.exs:113-128 covers the "Invalid token" landing with a bad token, not an expired one
```

The handoff link working only once is flow-account-revocation-teardown S03 on the same controller and
is not repeated here.

## 6. Unclear value

Owned by flow-account-revocation-teardown and not repeated: the mangled-token crash (its 6.1,
`user_session_controller.ex:56`), the signed-in browser skipping the exchange (its 6.2) and the
30-second validity (its 6.4).

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A stale /first_setup tab can still save after the first superuser exists (first-setup 6.1 row 1), and this flow then signs that second person in as superuser too, landing them on /projects with "Superuser account created." | `superuser.ex:44-62` vs `:69-73`; `plugs/first_setup.ex:27-29`; `user_session_controller.ex:55-67` | an unexpected second administrator who is fully signed in | fix |
| A browser that is already signed in as another account skips the exchange but keeps the flash, so /projects says "Superuser account created." while the operator is still the old account; the new superuser's token is never used | `router.ex:175-180`; `user_auth.ex:271-279`; `superuser.ex:54`; `user_session_controller_test.exs:130-137` | a success message on a page that is not signed in as the account it refers to | decide |
| The exchange reads the token and deletes it in two statements, so two requests with the same token inside 30 seconds both get a session | `accounts.ex:1062-1071`, `:1076-1079`, `:1084-1087` | a second browser holding the URL can open its own superuser session | fix |
| The superuser insert commits before the auth token insert (`Repo.insert!`); if the second fails, the LiveView crashes after the account exists | `accounts.ex:543-547`, `:1051-1055`; `superuser.ex:50-60` | an error and reconnect, then /projects redirects to log in; the operator must sign in by hand | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The page the operator first asked for is not remembered: the FirstSetup plug halts before `require_authenticated_user` can store `user_return_to`, so the flow always ends on /projects | `router.ex:29`; `plugs/first_setup.ex:27-32`; `user_auth.ex:491`, `:63-70` | decide |
| The flash set by the LiveView survives two redirects and the session renewal, and is rendered on /projects | `superuser.ex:54`; `user_auth.ex:96-103`; `first_setup_live_test.exs:45-51` | preserve |
| The new session has no remember-me cookie, so it ends with the browser session; password log in offers "remember me", this path does not | `user_session_controller.ex:65`; `user_auth.ex:72-79` | preserve |
| The raw token is in the URL path, so it reaches request logs and browser history; it is single use and expires in 30 seconds | `superuser.ex:56-61`; `user_token.ex:67-72` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Unexchanged `auth` tokens are never cleaned up by this flow | `accounts.ex:1051-1055`, `:1062-1071` | no | preserve |

### 6.5 Things seen but not understood

- `has_one_superuser?` counts rows with role superuser, including disabled ones (`accounts.ex:1341-1344`). An instance whose only superuser is disabled stays out of first setup with no usable administrator; one whose only superuser is demoted to user (`details_changeset` casts `role`, `user.ex:287-299`) would be sent back into first setup. Neither path through admin-user-edit was followed here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the handoff sign the new superuser in, or refuse, when the browser already holds another account's session; and should the success flash be shown in that case (6.1)? (owner: product)
- Should the exchange consume the token in a single statement so it can't be used twice in a race (6.1)? (owner: security)
- Should the superuser and its handoff token be written in one transaction (6.1)? (owner: security)
- Should the flow return the operator to the page they first asked for, rather than always /projects (6.2)? (owner: product)
- Should demoting or disabling the last superuser be refused, given it reopens first setup or leaves no usable administrator (6.5)? (owner: security)

## Proposed flows

none. Referenced: flow-account-revocation-teardown (shares controller:token-exchange).

## Proposed shared

none. Referenced: shared-authenticated-session (the :browser pipeline and its S11 first-setup redirect).

## Summary

- Scenarios: 3 (S01 to S03), all `@pending`, variant first-setup-open.
- Section 6: 6.1 4; 6.2 4; 6.3 0; 6.4 1; 6.5 1.
- Flows referenced: flow-account-revocation-teardown. None proposed.
- Shared referenced: shared-authenticated-session. None proposed.
- Unsure: whether the read-then-delete race and the non-atomic insert are reachable in practice; projects-dashboard does not list this flow in its `flows`.
