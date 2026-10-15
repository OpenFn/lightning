---
id: flow-admin-created-account-confirm
type: flow
title: A user created by a superuser confirms their account
status: not-started
owner:

trigger:
  entry: admin-user-edit             # "Save" on /settings/users/new (form_component.ex:46-48, :75-104)
  exit: projects-dashboard           # /projects after "Confirm my account" (user_confirmation_controller.ex:89-94); auth-confirmation-required when the account is never confirmed under require-email-verification
  surfaces:
    - admin-user-edit                        # create, then Accounts.deliver_user_confirmation_instructions/2 inline (form_component.ex:75-99; accounts.ex:1177-1190)
    - email:enroller-confirmation            # "Confirm your OpenFn account", enroller variant (user_notifier.ex:107-119); flow-resend-account-confirmation calls the same email family email:confirmation
    - auth-login                             # the new user has no session, so the link sends them to log in first (router.ex:189-190, :229; user_auth.ex:290-299)
    - auth-confirm-account                   # GET/POST /users/confirm/:token (router.ex:229-230; user_confirmation_controller.ex:30-32, :89-117)
    - projects-dashboard                     # where confirming lands; an account a superuser just made is on no project yet
    - auth-confirmation-required             # require-email-verification only: an unconfirmed account 48 hours after creation (accounts.ex:1360-1368; confirmation_lockout.ex:43)
  reachable_when:
    - a superuser saves the new-user form (admin-user-edit reachable_when; shared-admin-space)
    - the email is sent under every config variant; only the lockout at the end depends on require-email-verification (form_component.ex:79-82; accounts.ex:1177-1190, :1362-1368)
    - the new user knows the password the superuser typed; the email does not carry it (user_notifier.ex:107-119; see 6.1)

inherits:
  - shared-authenticated-session     # login redirect (S01) that the link triggers, the lockout (S04, S05) and the deadline banner (S06)
  - shared-admin-space               # the superuser gate on the entry hop
  - shared-flash-messages            # "User created successfully" toast on the entry hop, "User confirmed successfully." on the exit

url_params: []                       # the token is a path segment, /users/confirm/:token (user_notifier.ex:113); the return path is held in the session (user_auth.ex:490-492)

config_variants:
  default: {}                                                                  # S01 and S04 read under this one; the controller never checks the flag
  require-email-verification: { lightning.require_email_verification: true }   # S02 and S03 read under this one (accounts.ex:1362-1368; layout_components.ex:259-277)

inventory:
  routes: []                         # every route is owned by a surface: /settings/users/new (admin-user-edit), /users/log_in (auth-login), /users/confirm/:token (auth-confirm-account), /users/confirm-required (auth-confirmation-required)
  events:
    - UserLive.FormComponent#save    # :new arm only (form_component.ex:75-104); owned by admin-user-edit
  js_hooks: []
  policies: []                       # superuser gate is shared-admin-space; the confirm step matches the token owner, not a policy (user_confirmation_controller.ex:106-117)
  workers: []                        # the email is sent inline from the LiveView process (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:enroller-confirmation    # UserNotifier.deliver_confirmation_instructions/3 (user_notifier.ex:107-119)
  config:
    - :lightning, :require_email_verification
  not_reachable_here:
    - Accounts.deliver_user_confirmation_instructions/2 `{:error, :already_confirmed}` arm (accounts.ex:1181-1182); a user saved by the form has no `confirmed_at` (6.3)
    - Accounts.remind_account_confirmation/1 and the reminder copy (accounts.ex:1197-1206; user_notifier.ex:121-133); reached from the banner or the locked-out page, owned by flow-resend-account-confirmation

related:
  - lib/lightning_web/live/user_live/form_component.ex
  - lib/lightning/accounts.ex                # create_user/2 :146-165, build_email_token :1135-1142, deliver_user_confirmation_instructions/2 :1177-1190, confirm_user :1236-1255, reset_user_password :1318-1334, locked_out? :1360-1368
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/accounts/user_token.ex
  - lib/lightning_web/controllers/user_confirmation_controller.ex
  - lib/lightning_web/controllers/user_session_controller.ex
  - lib/lightning_web/controllers/user_auth.ex
  - lib/lightning_web/controllers/user_reset_password_controller.ex
  - lib/lightning_web/confirmation_lockout.ex
  - test/lightning/accounts/user_notifier_test.exs   # :116-154 (full enroller body)
  - test/lightning/accounts_test.exs                 # :1792-1816 (token context and sent_to), :1946-1955 (reset deletes all tokens)
  - test/lightning_web/live/user_live_test.exs       # :43-75 (create; no email assertion)
flows:
  - flow-resend-account-confirmation  # owns the confirm step (its S01 from "Confirm my account"), signed-out link (S04), wrong-user (S05), expired (S06), confirming after the deadline (S08)
  - flow-login-return-to              # the login hop between the link and the confirm page
  - flow-forgot-password              # the route a new user takes when the superuser has not told them the password (6.1)
  - flow-account-revocation-teardown  # cross-reference: a superuser editing the new account's email or password before it is confirmed (6.1)
---

## 1. Purpose

On instances without self sign-up, superusers bring people on by creating their accounts. The
enroller email tells the person an account exists, who made it, and gives them a link to prove the
address is theirs. Without it the person never learns about the account, and on instances that
require verified emails they are locked out 48 hours after the superuser pressed "Save".

## 2. What it does

1. A superuser creates the account on the new-user form, typing the person's password, and the person is emailed "Confirm your OpenFn account" naming who created it. If the email fails to send, the superuser is told.
2. The new user opens the link and, having no session yet, is asked to log in first with the password the superuser gave them (plus the second step if the account uses two-factor), then is brought back to the confirm page.
3. They press "Confirm my account" and land on the projects list, which is empty until someone adds them to a project.
   - The link lasts 7 days and only works when signed in as that account; the superuser opening it in their own browser is refused
4. On instances that require verified emails, an unconfirmed user sees a banner with a deadline 48 hours after the account was created and can ask for a new link; after that deadline they are held on a blocked page until they confirm.

**Straightforwardness: 2 of 5.** The happy path is short, but it relies on the superuser passing on a password out of band, and several ordinary fixes quietly break the link.

### Most surprising behaviours

- **(2)** The email says to "complete your registration", but there is no registration step and no password in it. The person lands on a login form asking for a password they were never told, unless the superuser told them separately. (6.1)
- **(2)** A new user who uses "Forgot your password?" to set their own password loses their confirmation link. Afterwards it says it's invalid or expired, and on default instances the only way to get another is a signed-out form you have to know the address of, which sends the generic welcome email instead. (6.1)
- **(2)** If the superuser corrects a mistyped address, nothing is sent to the new address and the original link stops working. The real person never hears about the account and, where verification is required, is later locked out. (6.1)
- **(3)** The 48-hour clock starts when the superuser presses Save, not when the person first logs in, so an account made on a Friday can already be locked on Monday. The email mentions neither the 48 hours nor the 7-day link expiry. (S03, 6.2)
- **(3)** Superusers can't see whether someone has confirmed and have no way to resend the email, and confirming leaves no audit record. (6.2)

## 3. Who can do what

No policy module beyond the entry gate (shared-admin-space, `policies/users.ex:19-21`). The link
routes sit behind `:require_authenticated_user` (`router.ex:189-190`, `:229-230`) and accept only a
token belonging to the signed-in account (`user_confirmation_controller.ex:106-117`).

| Action | Superuser | The new user, signed out | The new user, signed in | Any other signed-in user |
|--------|-----------|--------------------------|-------------------------|--------------------------|
| Create the account and send the email | yes | no | no | no |
| Open the link and see "Confirm my account" | no (refused, flow-resend-account-confirmation S05) | no (log in first) | yes | no (refused) |
| Confirm | no | no | yes | no |
| See whether the account was confirmed | no (no control or column; 6.2) | n/a | no | no |
| Ask for a new link | no | yes, by typing /users/confirm (auth-confirm-account) | yes, banner or locked-out page, require-email-verification only | n/a |

**Preconditions beyond role**
- The link works for 7 days and only while the account's email is still the address it was sent to (`user_token.ex:32`, `:168-183`).
- The 48-hour grace period counts from the `users` insert by the superuser, not from the email or the first login (`accounts.ex:1362-1368`).
- A disabled or scheduled-for-deletion account can't log in, so can't reach the confirm page (`user_session_controller.ex:31-38`; `accounts.ex:329-345`).
- A password reset deletes the outstanding confirm token (`accounts.ex:1321-1324`; `user_token.ex:236-238`; 6.1).

## 4. What it touches

**Hop 1: admin-user-edit (create)**
- Writes: `users` insert and `audit_events` `user` `created`, one transaction (`accounts.ex:146-165`); then `user_tokens` insert, context `confirm`, `sent_to` the new email, outside it (`accounts.ex:1135-1142`, `:1186-1188`)
- Immediate: email `email:enroller-confirmation` sent inline; flash "User created successfully" or "User created, but the confirmation email could not be sent" with a `Logger.error`; `push_navigate` to /settings/users (`form_component.ex:79-99`)
- Immediate: telemetry `superuser_changed` when the new account is a superuser (`accounts.ex:153-160`)

**Hop 2: email:enroller-confirmation**
- To the new user (name and address), subject "Confirm your OpenFn account", body "Hi <first name>, <creator first name> has just created an OpenFn account for you. You can complete your registration by visiting the URL below:", the `/users/confirm/:token` link, and "If you think this account was created by mistake, you can contact <creator first name> (<creator email>) or ignore this email." (`user_notifier.ex:107-119`; `user_notifier_test.exs:116-154`)
- No password, no deadline, no expiry in the body

**Hop 3: auth-login (link opened signed out)**
- Writes: session `user_return_to` = /users/confirm/<token> (`user_auth.ex:296-298`, `:490-492`); on login a `user_tokens` row, context `session`, with the return path kept across the session renew (`user_auth.ex:28-31`, `:96-103`)
- Immediate: redirect back to the confirm page, or to /users/two-factor first for an MFA account (`user_session_controller.ex:40-51`; `user_auth.ex:63-70`); owned by flow-login-return-to

**Hop 4: auth-confirm-account**
- Reads: `user_tokens` joined to `users` by hashed token, context `confirm`, age and `sent_to` (`user_token.ex:168-183`)
- Writes (POST): `users.confirmed_at` and delete of every `confirm` token for the account, one transaction (`accounts.ex:1236-1255`; `user.ex:367-370`); no audit event (6.2)
- Immediate: flash "User confirmed successfully." and redirect to /projects (`user_confirmation_controller.ex:89-94`)

**Hop 5: projects-dashboard**
- Reads the user's projects; a freshly created account has none unless a superuser or project admin added it since (projects-dashboard S04)

**Deferred side effects**
- require-email-verification: 48 hours after the insert, every authenticated HTML request but the allow-list redirects to /users/confirm-required (`user_auth.ex:305-306`, `:327-351`; `confirmation_lockout.ex:18-33`)
- No PubSub broadcast on confirm; the superuser's admin pages learn nothing (`accounts.ex:1236-1255`)

**External, non-transactional effects**
- The email leaves after the user and token are committed; a failed send leaves an account with a token nobody received (`form_component.ex:76-92`; `accounts.ex:1135-1142`)

**Depends on config**
- `require_email_verification` for the banner, the lockout and the auth-confirmation-required exit (`accounts.ex:1362-1368`; `layout_components.ex:259-277`)
- Endpoint URL config for the link host (`user_notifier.ex:113`); sender name and address (`user_notifier.ex:26`, `:53`)

**Product limits**
- Link valid 7 days (`user_token.ex:32`, `:190`); grace period 48 hours from creation (`accounts.ex:1366-1367`)

## 5. Scenarios

Verified by reading code and tests. Nothing was run.

```gherkin
Feature: A user created by a superuser confirms their account
  In order to start using an account someone else made for me
  As a person a superuser has enrolled
  I want to prove the address is mine from the email I was sent and get into OpenFn

  @S01 @pending
  Scenario: The new user confirms from the enroller email on a device where they are not signed in
    # Value: a person an administrator brought on can claim the account from their own inbox, with no self sign-up and no database access.
    Given I am a superuser named "Bob"
    And I create an account for "amara@example.org" with password "a long enough password" (admin-user-edit S01, S02)
    And Bob tells Amara her password
    When Amara opens the link in the "Confirm your OpenFn account" email in a browser with no session
    Then she is asked to log in
    When she logs in as "amara@example.org" with "a long enough password"
    Then she sees a "Confirm my account" button
    When she clicks "Confirm my account"
    Then she is on "/projects"
    And she sees "User confirmed successfully."
    And she sees "No projects found." (projects-dashboard S04)
    And "amara@example.org" is confirmed
    # form_component.ex:75-99; accounts.ex:1177-1190; user_notifier.ex:107-119
    # router.ex:189-190, :229-230; user_auth.ex:290-299, :490-492, :63-70, :96-103; user_session_controller.ex:47-51
    # user_confirmation_controller.ex:30-32, :89-94, :106-117; accounts.ex:1236-1255
    # the confirm step itself is flow-resend-account-confirmation S01 and S04; no test drives the enroller link end to end

  @S02 @pending @variant:require-email-verification
  Scenario: A new user who lost the enroller email can get a new link before the deadline
    # Value: the person can recover from a lost or filtered first email themselves, without going back to the superuser.
    Given a superuser created my account "amara@example.org" 2 hours ago and I have not confirmed
    When I log in
    Then I am on "/projects"
    And I see "Please confirm your account before" with a deadline 48 hours after my account was created
    And the flow "flow-resend-account-confirmation" can start from the banner (its S01)
    # accounts.ex:1362-1368; layout_components.ex:259-277; shared-authenticated-session S06; shared-project-header S14

  @S03 @pending @variant:require-email-verification
  Scenario: An account that is never confirmed is held at the confirmation page 48 hours after it was created
    # Value: an account a superuser created for a mistyped or wrong address can't be used to reach data until someone proves they read that inbox.
    Given a superuser created my account "amara@example.org" 50 hours ago
    And I have never signed in or confirmed
    When I log in with the password the superuser gave me
    Then I am on "/users/confirm-required"
    And I see "Your account is blocked pending email confirmation"
    And the page offers the ways out in auth-confirmation-required S01
    When I open the link from the enroller email and click "Confirm my account"
    Then I can open "/projects"
    # accounts.ex:1360-1368; user_auth.ex:63-70, :305-306, :327-351; confirmation_lockout.ex:18-20, :43
    # confirmation_lockout_recovery_test.exs:46-80 (recovery on an ordinary unconfirmed account); flow-resend-account-confirmation S08
    # the clock starts at the superuser's insert, not the first login (6.2)

  @S04 @pending
  Scenario: The superuser's own browser can't confirm the new account
    # Value: an account is confirmed only by someone signed in as that account, so a superuser clicking the link to test it doesn't vouch for an address they don't own.
    Given I am a superuser and I created "amara@example.org"
    When I open the link from Amara's enroller email in my own signed-in browser
    Then I am on "/projects"
    And I see "User confirmation link is invalid or it has expired."
    And "amara@example.org" is still unconfirmed
    And the link still works for Amara afterwards
    # user_confirmation_controller.ex:106-117, :123-136 (no token is deleted on refusal); accounts.ex:1236-1255
    # general case is flow-resend-account-confirmation S05; user_confirmation_controller_test.exs:190-211
```

The superuser's side of the entry hop (form, flashes, audit, email body) is admin-user-edit S01 to
S03. The confirm step, expired links and reused links are flow-resend-account-confirmation S01,
S06 and S07. The login hop is flow-login-return-to.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The email says "You can complete your registration by visiting the URL below", but there is no registration step: the link needs a session, and the password was typed by the superuser and is not in the email | `user_notifier.ex:107-119`; `router.ex:189-190`, `:229`; `form_component.html.heex:32-37` | a login form asking for a password they were never told | fix |
| A new user who takes "Forgot your password?" to set their own password loses their confirmation link, because a reset deletes every token of every context | `accounts.ex:1318-1334`; `user_token.ex:236-238`; `accounts_test.exs:1946-1953` | after resetting, the enroller link says "User confirmation link is invalid or it has expired."; under `default` nothing in the app offers a new one except the signed-out form at /users/confirm, which sends the welcome copy | fix |
| A superuser who corrects a mistyped address on admin-user-edit sends nothing to the new address, and the original link stops working because `sent_to` no longer matches | `user.ex:287-305`; `accounts.ex:177-201`; `user_token.ex:179` | the person at the corrected address never hears about the account; under require-email-verification they are later locked out | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The 48-hour grace period starts at the superuser's insert, so an account created on a Friday for someone who reads mail on Monday is already locked out when they first log in | `accounts.ex:1362-1368` | decide |
| The link is valid 7 days but the account locks after 48 hours; the email states neither | `user_token.ex:32`; `accounts.ex:1366-1367`; `user_notifier.ex:107-119` | decide |
| Confirming writes no audit event, though `confirmed_at` is one of the audited fields on update | `accounts.ex:1236-1255`; `accounts/audit.ex:13` | decide |
| Superusers can't see whether an account they created has confirmed, and have no resend control; nothing under `user_live/` reads `confirmed_at` | `lib/lightning_web/live/user_live/` (no match for `confirmed`); admin-user-edit 6.5 | decide |
| Every later email the new user can ask for is the reminder or the welcome copy, neither naming the creator; owned as a decide row in auth-confirm-account 6.2 | `user_notifier.ex:90-102`, `:121-133` | decide |
| Under `default` confirming changes nothing the user can see: only the banner and the lockout read `confirmed_at`, both behind require-email-verification | `layout_components.ex:261-265`; `workflow_channel.ex:1394`; `accounts.ex:1362-1368` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `{:error, :already_confirmed}` arm of `deliver_user_confirmation_instructions/2` | `accounts.ex:1181-1182` | its only caller passes a user the form just inserted; the form sends no `confirmed` param (`user.ex:94`, `:148-153`); a custom account hook was not read |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Link valid 7 days | `user_token.ex:32`, `:190` | yes, "invalid or it has expired" | preserve |
| The enroller send is not rate limited; each create sends one | `accounts.ex:1177-1190` vs `:1161-1175` | no | preserve |

### 6.5 Things seen but not understood

- On instances with an SSO provider, whether admin-created accounts are expected to log in through it, which would make the superuser-typed password and the login hop in S01 moot, was not read. Disposition: decide.
- Under `custom-account-hook` (admin-user-edit config_variants), whether the deployment's module sets `confirmed_at` or sends its own email was not read. Disposition: decide.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should an admin-created account set its own password from the enroller link instead of logging in with one the superuser typed (6.1 row 1)? (owner: product)
- Should a password reset keep an outstanding confirm token, or count as proof of the address and confirm the account (6.1 row 2)? (owner: security)
- Should correcting an unconfirmed account's email from admin-user-edit send a new enroller email (6.1 row 3)? (owner: product)
- Should the grace period for an admin-created account start at creation, and should the email state it (6.2)? (owner: product)
- Should confirmation be audited and visible to superusers, with a resend control (6.2)? (owner: product)

## Proposed flows

none. Referenced: flow-resend-account-confirmation (confirm step, S01, S04 to S08), flow-login-return-to (login hop), flow-forgot-password (6.1 row 2), flow-account-revocation-teardown (admin edits before confirmation).

## Proposed shared

none. Inherits shared-authenticated-session, shared-admin-space, shared-flash-messages.
