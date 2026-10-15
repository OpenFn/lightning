---
id: auth-confirm-account
type: view
title: Account confirmation (resend form and confirm page)
status: not-started
owner:

trigger:
  old_route: /users/confirm, /users/confirm/:token, /users/send-confirmation-email
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - "/users/confirm (GET/POST): any visitor, signed in or out; the scope pipes only through :browser (router.ex:66-74)"
    - "/users/confirm/:token and /users/send-confirmation-email: a signed-in session that passes :require_authenticated_user (router.ex:189-190, :229-236; user_auth.ex:288-311)"
    - "an account locked out pending confirmation still reaches all three, through the lockout allow-list (confirmation_lockout.ex:18-33)"
    - "nothing in the app links to /users/confirm; it is reached by typing the URL (see 6.2)"
    - "the token page is reached from the link in email:confirmation (user_notifier.ex:90-102, :107-119, :121-133)"
    - "instance has a superuser, or first setup is off; otherwise the :browser pipeline's FirstSetup plug sends every request here to /first_setup (first_setup.ex:11-33; shared-authenticated-session S11)"

inherits:
  - shared-authenticated-session     # plug half only, on the token and resend routes: S01 (login redirect), S02 (disabled account), S03 (TOTP pending), S05 and the lockout allow-list (confirmation_lockout.ex:18-33); S11 (first setup) applies to all three routes. This is a controller view, so InitAssigns and its chrome (S06 to S10) do not apply
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: token (path segment of /users/confirm/:token)
    set_by: email:confirmation (user_notifier.ex:96, :112, :127)
    effect: identifies the confirm token; must belong to the signed-in user (user_confirmation_controller.ex:106-117)

config_variants:
  default: {}                                                                  # S01 to S05 read under this one; the controller never checks require_email_verification
  require-email-verification: { lightning.require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION; S06 read under this one (lockout, accounts.ex:1362-1368)
  signup-allowed: { lightning.allow_signup: true }                             # only shows the "Register" link (new.html.heex:50-55; edit.html.heex:43-48)

inventory:
  routes:
    - get /users/confirm  UserConfirmationController :new                        # router.ex:72
    - post /users/confirm  UserConfirmationController :create                    # router.ex:73
    - get /users/confirm/:token  UserConfirmationController :edit                # router.ex:229; also claimed by flow-resend-account-confirmation
    - post /users/confirm/:token  UserConfirmationController :update             # router.ex:230; also claimed by flow-resend-account-confirmation
    - get /users/send-confirmation-email  UserConfirmationController :send_email # router.ex:236; owned by flow-resend-account-confirmation (controller:send-confirmation-email)
  events:
    - UserConfirmationController#new
    - UserConfirmationController#create
    - UserConfirmationController#edit
    - UserConfirmationController#update
    - UserConfirmationController#send_email              # handoff only (S06); scenarios in flow-resend-account-confirmation
    - UserConfirmationController.verify_confirmation_token (plug, :edit and :update)
  js_hooks: []
  policies: []                         # no policy module; gated by :require_authenticated_user and the token owner match (user_confirmation_controller.ex:106-117)
  workers: []                          # mail is sent inline in the request (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:confirmation               # welcome variant from the signed-out form (accounts.ex:1161-1175; user_notifier.ex:90-102)
  config:
    - :lightning, :allow_signup         # Register link
    - :lightning, :require_email_verification   # lockout only, via shared-authenticated-session
    - :lightning, :allow_first_setup    # FirstSetup plug in :browser
    - :hammer backend (config/config.exs:25-28)
  not_reachable_here:
    - UserConfirmationController#confirm_email (GET /profile/confirm_email/:token, router.ex:232-234; user_confirmation_controller.ex:34-49) lives in this module but is the email-change link, owned by flow-change-email-confirm (controller:confirm-email)
    - Accounts.remind_account_confirmation/1 and the reminder email variant behind send_email (accounts.ex:1197-1206; user_notifier.ex:121-133), owned by flow-resend-account-confirmation
    - Accounts.deliver_user_confirmation_instructions/2 (admin-created account variant, accounts.ex:1177-1190); sends a link that lands here but is not called from here

related:
  - lib/lightning_web/controllers/user_confirmation_controller.ex
  - lib/lightning_web/controllers/user_confirmation_html.ex
  - lib/lightning_web/controllers/user_confirmation_html/new.html.heex
  - lib/lightning_web/controllers/user_confirmation_html/edit.html.heex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/confirmation_lockout.ex
  - lib/lightning_web/plugs/first_setup.ex
  - lib/lightning_web/components/layout_components.ex
  - lib/lightning_web/live/components/form.ex
  - lib/lightning/accounts.ex
  - lib/lightning/accounts/user_token.ex
  - lib/lightning/accounts/user_notifier.ex
  - test/lightning_web/controllers/user_confirmation_controller_test.exs
  - test/lightning_web/confirmation_lockout_recovery_test.exs
  - test/lightning_web/confirmation_lockout_test.exs
flows:
  - flow-resend-account-confirmation  # referenced; owns the email, the confirm step end to end, wrong-user and expired links (its S01, S04 to S08)
  - flow-login-return-to              # referenced; S05 hands off to it
  - flow-change-email-confirm         # referenced; owns confirm_email, which lives in this controller
  - flow-admin-created-account-confirm
---

## 1. Purpose

A new account proves it owns its email address by opening a confirmation link and pressing a
button on this page; on instances that require verification, an account that does not do this
within 48 hours is locked out. The same controller lets anyone ask for a fresh link by typing an
address, without signing in. Without it, a user whose welcome email was lost or expired has no
way to confirm, and the instance has no evidence that an address belongs to the person using it.

## 2. What it does

- Anyone, signed in or out, asks for a new confirmation email by entering an address, and gets the same answer whether the address is unknown, already confirmed, unconfirmed or throttled
- A signed-in user opens their confirmation link and confirms their account
- A signed-out user who opens a confirmation link is sent to log in first
- A signed-in unconfirmed user, including a locked-out one, asks for a new link by visiting the resend URL

**Straightforwardness: 4 of 5.** Confirming is one click; the surprises are small ones about a hidden resend form and pages that don't quite fit the person using them.

### Most surprising behaviours

- **(3)** Nothing in the app links to the signed-out "resend" form; you can only reach it by typing its address. (6.2)
- **(3)** The form says the same words for every address, but it answers more slowly for an unconfirmed account, which gives the game away. If the email fails to send, the person is still told it's coming and nobody is warned. (6.1)
- **(3)** The confirm page is only for signed-in users, yet it has no menu or log out and offers "Log in" and "Register" links. (6.1, 6.2)
- **(4)** Anyone can make the server send up to three emails every 15 minutes to any unconfirmed account, and those sends use up the same allowance as the person's own requests. (6.2)
- **(4)** The resent email is the "Welcome to OpenFn, ignore this if you didn't sign up" version, even for someone an administrator created. (6.2)

## 3. Who can do what

No policy module. Sources: `router.ex:66-74`, `:189-190`, `:229-236`; `user_auth.ex:288-311`; `user_confirmation_controller.ex:16-28`, `:51-77`, `:106-137`; `confirmation_lockout.ex:18-39`.

| Action | Signed out | Signed in, unconfirmed | Locked out (unconfirmed, past 48 h) | Signed in, confirmed | TOTP pending | Signed in as another user (token page) |
|--------|-----------|------------------------|-------------------------------------|----------------------|--------------|----------------------------------------|
| See the resend form | yes | yes | yes | yes | yes | n/a |
| Submit the resend form (email sent only for an unconfirmed account) | yes | yes | yes | yes | yes | n/a |
| See the confirm page | no, login | yes, own token only | yes, own token only | no, silent redirect | no, two-factor | no, error |
| Confirm the account | no, login | yes | yes | n/a | no, two-factor | no, error |
| Request a new link by URL | no, login | yes | yes | no-op redirect | no, two-factor | n/a |

**Preconditions beyond role**
- The token must belong to the signed-in account, be under 7 days old and have been sent to the account's current email (`user_confirmation_controller.ex:106-112`; `user_token.ex:32`, `:168-183`).
- The resend form sends at most 3 emails per account per 15 minutes, on the `confirmation_request` bucket shared with the sign-up welcome email (`accounts.ex:758-782`, `:1161-1175`).
- The resend form sends nothing to an unknown address or a confirmed account (`user_confirmation_controller.ex:17-19`; `accounts.ex:1163-1164`).
- A locked-out account reaches all three routes through the allow-list (`confirmation_lockout.ex:18-33`); `/users/confirm` is outside the authenticated scope anyway.

## 4. What it touches

**Reads**
- Resend form: `users` by email, case-insensitive (`accounts.ex:318-320`; citext column, `priv/repo/migrations/20220405135153_create_users.exs:12`); Hammer bucket `confirmation_request::<user_id>` (`accounts.ex:762-767`, `:1166`)
- Token page: `users_tokens` joined to `users` by hashed token, context `confirm`, age and `sent_to` (`accounts.ex:1220-1228`; `user_token.ex:168-183`); session user (`user_auth.ex:175-182`)

**Writes**
- Resend form: `users_tokens` insert, context `confirm`, `sent_to` the account email (`accounts.ex:1135-1142`, `:1171-1174`); Hammer counter increment
- Confirm (POST): `users.confirmed_at` set and every `confirm` token for the user deleted, in one transaction (`accounts.ex:1236-1255`)
- Session `user_return_to` when a signed-out visitor opens the token link (`user_auth.ex:296-298`, `:490-492`)

**Immediate side effects**
- Resend form: email `email:confirmation`, welcome variant, subject "Confirm your OpenFn account" (`user_notifier.ex:90-102`); flash "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly." and redirect to /projects (`user_confirmation_controller.ex:21-27`)
- Confirm: flash "User confirmed successfully." and redirect to /projects (`user_confirmation_controller.ex:90-94`)
- Refused token: flash "User confirmation link is invalid or it has expired." and redirect to /projects, or a silent redirect when the account is already confirmed (`user_confirmation_controller.ex:123-136`, `:96-102`)

**Deferred side effects**
- none

**External, non-transactional effects**
- The email, sent synchronously; the token is inserted before the send and kept if the send fails (`accounts.ex:1135-1142`, `:1171-1174`; `user_notifier.ex:49-60`)

**Depends on config**
- `allow_signup` for the "Register" link (`new.html.heex:50-55`; `edit.html.heex:43-48`)
- `require_email_verification` only through the lockout (`accounts.ex:1362-1368`); the controller ignores it
- `allow_first_setup` through the FirstSetup plug (`router.ex:29`; `first_setup.ex:11-33`)
- Link host from the endpoint URL; sender name and address (`user_notifier.ex:53`, `:96`)

**Product limits**
- 3 resend-form emails per account per 15 minutes (`accounts.ex:758-759`)
- Confirmation links valid 7 days (`user_token.ex:32`)

## 5. Scenarios

```gherkin
Feature: Account confirmation
  In order to prove I own the email address on my account
  As someone with a new OpenFn account
  I want to get a confirmation link and confirm with it

  @S01 @pending
  Scenario: A signed-out user asks for a new confirmation link by email
    # Value: a user who lost the confirmation email can get another without signing in.
    Given "amara@example.org" has an account whose email is unconfirmed
    And I am not logged in
    When I visit "/users/confirm"
    Then I see "Resend confirmation instructions"
    When I enter "amara@example.org" as "Email" and click "Resend confirmation instructions"
    Then I see "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."
    And "amara@example.org" is sent an email with subject "Confirm your OpenFn account"
    And its link opens the confirm step of flow "flow-resend-account-confirmation"
    # router.ex:72-73; new.html.heex:5, :10-38; user_confirmation_controller.ex:12-28
    # accounts.ex:1161-1175, :1135-1142; user_notifier.ex:90-102
    # user_confirmation_controller_test.exs:14-19, :86-99 (asserts a confirm token, not the email)
    # signed out, /projects redirects on to /users/log_in, which renders the flash (user_auth.ex:290-299; user_session_html/new.html.heex:23-27); see 6.2 and 6.5

  @S02 @pending
  Scenario Outline: The resend form gives the same answer for any address
    # Value: the form cannot be used to find out which addresses have accounts, or which are confirmed.
    Given <account>
    When I submit "<email>" on "/users/confirm"
    Then I see "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."
    And I am redirected to "/projects"
    And <mail>

    Examples:
      | account                                              | email               | mail                                   |
      | no account uses "nobody@example.org"                 | nobody@example.org  | no email is sent                       |
      | "ben@example.org" has a confirmed account            | ben@example.org     | no email is sent                       |
      | "amara@example.org" has an unconfirmed account       | amara@example.org   | a confirmation email is sent to Amara  |
    # user_confirmation_controller.ex:16-28; accounts.ex:1161-1164
    # user_confirmation_controller_test.exs:86-99, :101-118, :151-163
    # response time is not uniform across these rows (6.1)

  @S03 @pending
  Scenario: A fourth request within 15 minutes sends nothing and looks the same
    # Value: the form can't be used to flood someone's inbox, and the throttle does not reveal that the address has an account.
    Given "amara@example.org" has an unconfirmed account
    And the form has been submitted for "amara@example.org" 3 times in the last 15 minutes
    When I submit "amara@example.org" on "/users/confirm"
    Then I see "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."
    And no email is sent
    And the response is identical to an allowed request
    # accounts.ex:758-782, :1166-1167; user_confirmation_controller.ex:17-19
    # user_confirmation_controller_test.exs:120-149 (asserts status, redirect, flash and body are equal, and 3 tokens)

  @S04 @pending
  Scenario: A signed-in user confirms with their link
    # Value: the link in the confirmation email is honoured, so the account owner can prove the address is theirs.
    Given I am logged in as "amara@example.org", unconfirmed
    And flow "flow-resend-account-confirmation" has sent me a confirmation link
    When I open the link
    Then I see "Confirm account" and a "Confirm my account" button
    When I click "Confirm my account"
    Then I am on "/projects"
    And I see "User confirmed successfully."
    And the flow "flow-resend-account-confirmation" has reached its confirm step (its S01)
    # router.ex:229-230; user_confirmation_controller.ex:10, :30-32, :89-94, :106-112
    # edit.html.heex:5, :10-31; accounts.ex:1236-1255
    # user_confirmation_controller_test.exs:172-188, :247-268
    # wrong-user, expired and reused links: flow-resend-account-confirmation S05 to S07

  @S05 @pending
  Scenario: Opening a confirmation link while signed out asks me to log in
    # Value: the link still works when opened on a device where I am not logged in.
    Given I am not logged in
    When I open "/users/confirm/<token>"
    Then I am on "/users/log_in"
    And the flow "flow-login-return-to" has started for "/users/confirm/<token>"
    # router.ex:189-190, :229-230; user_auth.ex:290-299, :490-492
    # user_confirmation_controller_test.exs:167-170, :240-245
    # shared-authenticated-session S01; flow-resend-account-confirmation S04

  @S06 @pending @variant:require-email-verification
  Scenario: A locked-out user can still ask for a new link by URL
    # Value: an account past its confirmation deadline always has a way to get a working link, even from a bookmark.
    Given my account was created 50 hours ago and my email is unconfirmed
    And I am logged in
    When I visit "/users/send-confirmation-email"
    Then I receive an email with subject "Confirm your OpenFn account"
    And I end up on "/users/confirm-required"
    And the flow "flow-resend-account-confirmation" has started
    # router.ex:236; confirmation_lockout.ex:28-30; user_auth.ex:305-306, :327-351
    # user_confirmation_controller.ex:51-73, :79-86
    # confirmation_lockout_recovery_test.exs:46-61 (redirect to /projects, email sent, /projects then redirects to /users/confirm-required)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The resend form leaks whether an address has an unconfirmed account through response time: for such an account the request inserts a token and sends mail over SMTP before replying; for any other address it replies at once | `user_confirmation_controller.ex:17-19`; `accounts.ex:1161-1175`; `user_notifier.ex:49-60` | identical text (S02), but a measurably slower response for unconfirmed accounts | fix |
| The resend form discards the delivery result; a failed send is neither logged nor retried, and the token stays | `user_confirmation_controller.ex:17-19`; `accounts.ex:1171-1174`, `:1135-1142` | "you will receive an email with instructions shortly", and no email arrives; operators have no log line (the banner path logs, `user_confirmation_controller.ex:63-64`) | fix |
| `create` matches only `%{"user" => %{"email" => email}}`, and `get_user_by_email/1` guards on `is_binary`; a POST without that key, or with `user[email][]=x`, raises | `user_confirmation_controller.ex:16`; `accounts.ex:318` | a bare 400 or 500 error page (crafted requests only; the form always sends a string) | fix |
| The confirm page shows "Log in" and "Register" links to a user who must already be signed in to see it; also flow-resend-account-confirmation 6.1 | `edit.html.heex:33-51` | links that make no sense for the signed-in user | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Nothing in the app links to `/users/confirm`; the signed-out resend form is reachable only by typing the URL | `router.ex:72-73`; no `user_confirmation_path(_, :new)` or `"/users/confirm"` reference outside the router and the form's own action | decide |
| The resend form redirects to /projects, so a signed-out visitor bounces on to /users/log_in to read the flash | `user_confirmation_controller.ex:27`; `user_auth.ex:290-299` | decide |
| The resend form sends the welcome copy ("Welcome to OpenFn ... If you didn't create an account with us, please ignore this.") rather than the reminder copy the banner sends; an admin-created account also gets the welcome copy instead of its enroller copy | `accounts.ex:1171-1174`; `user_notifier.ex:90-102` vs `:107-119`, `:121-133` | decide |
| The resend form's allowance is the `confirmation_request` bucket that the sign-up welcome email also spends; owned as a decide row in flow-resend-account-confirmation 6.2 | `accounts.ex:1161-1175` | decide |
| The resend form has no per-requester or per-IP limit; anyone can send up to 3 emails per 15 minutes to every unconfirmed account | `accounts.ex:762-767` (keyed on the target user id only) | decide |
| Email lookup is case-insensitive (citext column) | `accounts.ex:318-320`; `20220405135153_create_users.exs:12` | preserve |
| Opening the link renders a "Confirm my account" button; only the POST confirms; owned as a decide row in flow-resend-account-confirmation 6.2 | `user_confirmation_controller.ex:30-32`, `:89-104` | decide |
| A stale link opened by a confirmed account redirects with no message; owned as a preserve row in flow-resend-account-confirmation 6.2 | `user_confirmation_controller.ex:119-127`; `user_confirmation_controller_test.exs:225-236` | preserve |
| Both templates wrap the form in `id="reset-password"` (copied from the reset password page) | `new.html.heex:9`; `edit.html.heex:9` | decide |
| The pages use the bare logo nav and call the header without `current_user`, so a signed-in user on the confirm page gets no sidebar, no log out, no confirmation banner and the signed-out title size | `edit.html.heex:1-7`; `layout_components.ex:259-266`, `:283-288`, `:315-332` | decide |
| "Register" shows only when self-signup is allowed | `new.html.heex:50-55`; `edit.html.heex:43-48` | preserve |
| The lockout allow-list prefix `["users", "confirm"]` also matches `/users/confirm`, which is outside the authenticated scope and never consults it; the lockout test lists it as exempt | `confirmation_lockout.ex:18-20`; `confirmation_lockout_test.exs:48-69` | preserve |
| `/users/confirm` is not behind `redirect_if_user_is_authenticated`, so a signed-in user can use the signed-out form, for any address | `router.ex:66-74` vs `:176` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| The `:error` and `:info` flash blocks in both templates | `new.html.heex:18-27`; `edit.html.heex:18-27` | every action in this controller redirects to /projects, and no redirect into these pages carries a flash (login return uses `redirect_with_return_to`, `user_auth.ex:63-70`, with no flash) |
| `update/2`'s `:error` branch for a token that the plug just accepted | `user_confirmation_controller.ex:96-102` | reachable only if the token is consumed or expires between the plug's lookup and `confirm_user/1` in the same request (`:10`, `:90`, `:106-112`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| 3 resend-form emails per account per 15 minutes, bucket `confirmation_request` | `accounts.ex:758-767`, `:1166` | no, by design the response is unchanged (S03) | preserve |
| Confirmation links valid 7 days | `user_token.ex:32`, `:190` | yes, "invalid or it has expired" (flow-resend-account-confirmation S06) | preserve |
| The rate limiter fails open with a warning log | `accounts.ex:774-780` | no | preserve |
| Mail is sent synchronously inside the request | `user_notifier.ex:49-60` | yes, a slow mail server slows the form (and see 6.1) | decide |
| Every browser request here counts superusers while first setup is allowed (shared-authenticated-session 6.4) | `first_setup.ex:11-33`; `accounts.ex:1341-1344` | no | preserve |

### 6.5 Things seen but not understood

- Whether the form's flash survives the second redirect (/projects to /users/log_in) for a signed-out visitor. Phoenix keeps flash across 3xx responses, so it should, but no test follows the chain (`user_confirmation_controller_test.exs:92-95` stops at the first redirect).
- `create/2` ignores `deliver_user_confirmation_instructions/1`'s return entirely, which is what keeps S02 and S03 uniform; whether that was the intent or an accident of the original phx.gen.auth code is not recorded.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the signed-out resend form be linked from the login page, folded into the banner path, or kept as a URL-only page? (6.2) (owner: product)
- Should the resend form send the reminder copy rather than the welcome copy? (6.2) (owner: product)
- Should the form's response time be made independent of the address (send mail out of the request), and should it be throttled per requester as well as per target account? (6.1, 6.2) (owner: security)
- Should failed sends from the resend form be logged, given the response must stay uniform? (6.1) (owner: security)
- flow-resend-account-confirmation lists `:new` and `:create` in `not_reachable_here`, but the email the form sends lands on the same confirm step. Should the form be added to the flow's `surfaces` as a third entry? (S01) (owner: cataloguing)

## Proposed flows

none. Referenced: flow-resend-account-confirmation (S01 and S04 hand off to its confirm step; S06 starts it), flow-login-return-to (S05), flow-change-email-confirm (owns `confirm_email`, which lives in this controller).

## Proposed shared

none. Referenced: shared-authenticated-session (plug gate only: S01, S02, S03, S05, S11 and the lockout allow-list; its LiveView chrome does not apply to this controller view).

## Lead resolution (batch 9)

- No proposals. This view's form is now in flow-resend-account-confirmation surfaces.
