---
id: flow-resend-account-confirmation
type: flow
title: Resend the account confirmation email
status: not-started
owner:

trigger:
  entry: shared-project-header       # or workflow-editor-canvas (its EmailVerificationBanner); both link to the same GET
  exit: shared-project-header        # the page the resend was clicked on (user_confirmation_controller.ex:72, :79-86); the confirm step itself lands on projects-dashboard (:93-94)
  surfaces:
    - shared-project-header                  # "Resend confirmation email" in the LiveView banner (layout_components.ex:259-277)
    - workflow-editor-canvas                 # same link in the React banner (EmailVerificationBanner.tsx:40-46; Header.tsx:647)
    - controller:send-confirmation-email     # GET /users/send-confirmation-email (router.ex:236; user_confirmation_controller.ex:51-87)
    - email:confirmation                     # "Confirm your OpenFn account" reminder (user_notifier.ex:121-133)
    - auth-confirm-account                   # GET/POST /users/confirm/:token (router.ex:229-230; user_confirmation_controller.ex:89-104)
    - projects-dashboard                     # where a confirmation lands, without the banner
  reachable_when:
    - the instance requires email verification, so the banner renders (layout_components.ex:261-265; workflow_channel.ex:1409-1415; EmailVerificationBanner.tsx:21)
    - the user is signed in and `confirmed_at` is nil (layout_components.ex:263-265; workflow_channel.ex:1395; user_confirmation_controller.ex:51-53)
    - the account is inside its 48-hour grace period; past it every banner page redirects to /users/confirm-required (shared-authenticated-session S04)

inherits:
  - shared-authenticated-session     # the lockout this flow heads off (its S04 to S06) and the paths a locked-out account may still reach (confirmation_lockout.ex:18-39)
  - shared-project-header            # owns the banner's visibility (its S13) and the handoff into this flow (its S14)

url_params: []                       # the token is a path segment, /users/confirm/:token (user_notifier.ex:127)

config_variants:
  default: {}                                                                  # banner never renders; this flow has no entry
  require-email-verification: { lightning.require_email_verification: true }   # REQUIRE_EMAIL_VERIFICATION, bootstrap.ex:387-389; every scenario is read under this one

inventory:
  routes:
    - get /users/send-confirmation-email  UserConfirmationController :send_email   # router.ex:236
    - get /users/confirm/:token  UserConfirmationController :edit                  # router.ex:229
    - post /users/confirm/:token  UserConfirmationController :update               # router.ex:230
  events: []                          # the banner link is a plain anchor, not a LiveView event (common.ex:266-270; EmailVerificationBanner.tsx:40-46)
  js_hooks: []
  policies: []                        # gated by :require_authenticated_user and the controller's confirmed_at match, not a policy module (router.ex:189-190)
  workers: []                         # the email is sent inline in the request, not through Oban (user_notifier.ex:49-60)
  api_endpoints: []
  emails:
    - email:confirmation              # UserNotifier.remind_account_confirmation/2 (user_notifier.ex:121-133)
  config:
    - :lightning, :require_email_verification
    - :hammer backend (config/config.exs:25-28; application.ex:18-19)
    - Lightning.Config.instance_admin_email, email_sender_name (sender, user_notifier.ex:26, :53)
  not_reachable_here:
    - UserConfirmationController :new and :create (GET/POST /users/confirm, router.ex:72-73) belong to auth-confirm-account's signed-out resend form, not this flow
    - UserConfirmationController :confirm_email (/profile/confirm_email/:token) is the email-change link
    - UserConfirmationRequiredLive "resend-confirmation-email" (user_confirmation_required_live.ex:43-68) is the locked-out page's own resend; it shares this flow's rate-limit bucket (see S03) but is owned by auth-confirmation-required
    - deliver_confirmation_instructions/2 and /3 (welcome and admin-created emails, user_notifier.ex:89-118) send the same link from registration, not from the banner

related:
  - lib/lightning_web/components/layout_components.ex
  - lib/lightning_web/live/components/common.ex
  - assets/js/collaborative-editor/components/EmailVerificationBanner.tsx
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning_web/controllers/user_confirmation_controller.ex
  - lib/lightning_web/controllers/user_confirmation_html/edit.html.heex
  - lib/lightning_web/confirmation_lockout.ex
  - lib/lightning/accounts.ex
  - lib/lightning/accounts/user_token.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning_web/controllers/user_auth.ex
flows:
  - flow-login-return-to             # S04 hands off to it when the link is opened signed out
---

## 1. Purpose

On instances that require email verification, a new user has 48 hours to confirm their address
before they are locked out of everything but the confirmation page. The welcome email can be lost,
filtered or expired, so the warning banner on every project page and in the workflow editor lets
them ask for a fresh link without leaving their work. Without it, a user who missed the first email
has no way back in short of an administrator, and the instance has no proof the address belongs to
the person using it.

## 2. What it does

Unconfirmed user clicks "Resend confirmation email" in the header or editor banner; the server emails a new link and returns them to the same page with a flash; the user opens the link, presses "Confirm my account", and lands on projects without the banner.

## 3. Who can do what

No policy module: the routes sit behind `:require_authenticated_user` (`router.ex:189-190`, `user_auth.ex:288-311`) and the controller matches on `confirmed_at: nil` (`user_confirmation_controller.ex:51-53`). The confirm step accepts only a token belonging to the signed-in user (`user_confirmation_controller.ex:106-117`).

| Action | Signed out | Unconfirmed, inside deadline | Unconfirmed, locked out | Confirmed | Signed in as another user |
|--------|------------|------------------------------|-------------------------|-----------|---------------------------|
| See the banner and its resend link | no | yes | no (redirected away from banner pages) | no | n/a |
| Request a new email | no (login) | yes | yes, by direct URL (`confirmation_lockout.ex:28-30`) | no-op redirect | n/a |
| Open the link and confirm | no (login first) | yes | yes (`confirmation_lockout.ex:19-20`) | no-op redirect | refused |

**Preconditions beyond role**
- At most 3 resend emails per account per 15 minutes, shared with the locked-out page's resend button (`accounts.ex:758-782`, `:1197-1206`; bucket `confirmation_resend`).
- The link works for 7 days and only while the account's email is still the address it was sent to (`user_token.ex:32`, `:168-183`).
- Confirming deletes every outstanding confirm token for the account (`accounts.ex:1248-1254`).

## 4. What it touches

**Reads**
- Hop 1 (banner): `users.confirmed_at`, `users.inserted_at` (`layout_components.ex:263-270`; editor via channel join, `workflow_channel.ex:1388-1397`)
- Hop 2 (resend): the session user; the Hammer bucket `confirmation_resend::<user_id>` (`accounts.ex:762-767`)
- Hop 4 (confirm): `users_tokens` joined to `users` by hashed token, context `confirm`, age and `sent_to` (`user_token.ex:168-183`; `accounts.ex:1220-1228`)

**Writes**
- Hop 2: `users_tokens` insert, context `confirm`, `sent_to` the current email (`accounts.ex:1135-1142`); Hammer counter increment (Mnesia)
- Hop 4 (POST): `users.confirmed_at` set to now, and all `confirm` tokens for the user deleted, in one transaction (`accounts.ex:1236-1255`; `user.ex:367-370`)

**Immediate side effects**
- Hop 2: email `email:confirmation` to the user's address, subject "Confirm your OpenFn account", sent in the request (`user_notifier.ex:49-60`, `:121-133`)
- Hop 2: flash "Confirmation email sent successfully", the throttle message (`confirmation_lockout.ex:11-12`) or "We could not send that email just now. Please try again in a moment." with a `Logger.error` (`user_confirmation_controller.ex:55-68`); redirect to the referring path (`:70-86`)
- Hop 4: flash "User confirmed successfully." and redirect to /projects (`user_confirmation_controller.ex:90-94`)

**Deferred side effects**
- none; no PubSub broadcast on confirm, so other open pages keep their banner until they remount (see 6.1)

**External, non-transactional effects**
- The email. The token is inserted before the send and is not removed if the send fails (`accounts.ex:1199-1202`).

**Depends on config**
- `require_email_verification` for the banner (`layout_components.ex:262`; `workflow_channel.ex:1412-1413`); the controller itself does not check it (see 6.2)
- Link host from the endpoint URL config (`user_notifier.ex:127`)
- Sender name and address (`user_notifier.ex:26`, `:53`)

**Product limits**
- 3 resend emails per 15 minutes per account (`accounts.ex:758-759`)
- Links expire after 7 days (`user_token.ex:32`, `:190`)

## 5. Scenarios

```gherkin
Feature: Resend the account confirmation email
  In order to keep using OpenFn after the confirmation deadline
  As a user who has not yet confirmed my email
  I want to get a fresh confirmation link from the page I'm on and use it

  @S01 @pending @variant:require-email-verification
  Scenario: A user asks for a new link from the project header and confirms with it
    # Value: a user who lost or never got the welcome email can confirm before they are locked out, without an admin.
    Given my account was created 2 hours ago and my email is unconfirmed
    And I am on the workflows page of project "Malawi HIV"
    When I click "Resend confirmation email" in the banner
    Then I am back on the workflows page of project "Malawi HIV"
    And I see "Confirmation email sent successfully"
    And I receive an email with subject "Confirm your OpenFn account"
    When I open the link in the "Confirm your OpenFn account" email
    Then I see a "Confirm my account" button
    When I click "Confirm my account"
    Then I am on "/projects"
    And I see "User confirmed successfully."
    And I do not see the account confirmation banner
    # layout_components.ex:259-277; common.ex:266-270; router.ex:229-230, :236
    # user_confirmation_controller.ex:51-86, :89-94; accounts.ex:1197-1206, :1236-1255; user_notifier.ex:121-133
    # edit.html.heex:10-31; user_confirmation_controller_test.exs:23-41, :247-268; user_notifier_test.exs:65-89

  @S02 @pending @variant:require-email-verification
  Scenario: Asking from the workflow editor returns me to the same workflow
    # Value: an editor mid-task can request the link without losing their place in the workflow.
    Given my account was created 2 hours ago and my email is unconfirmed
    And I have workflow "Intake" open in the editor
    When I click "Resend confirmation email" in the editor banner
    Then I am back in the editor on workflow "Intake"
    And I see "Confirmation email sent successfully"
    And I receive an email with subject "Confirm your OpenFn account"
    # EmailVerificationBanner.tsx:21-46; Header.tsx:647; workflow_channel.ex:1388-1397, :1409-1415
    # user_confirmation_controller.ex:70-86 (referer path); layouts/live.html.heex:92-93 (flash)

  @S03 @pending @variant:require-email-verification
  Scenario: A fourth request within 15 minutes sends nothing and says why
    # Value: the banner can't be used to flood an inbox, and the user is told to check their mail rather than told it was sent.
    Given my account was created 2 hours ago and my email is unconfirmed
    And I have asked for a confirmation email 3 times in the last 15 minutes
    When I click "Resend confirmation email"
    Then I see "You've asked for this a few times recently. Check your inbox and spam folder; you can request another in a few minutes."
    And no new confirmation email is sent
    # accounts.ex:758-782, :1197-1206; confirmation_lockout.ex:11-12, :48-50; user_confirmation_controller.ex:57-58
    # user_confirmation_controller_test.exs:59-81; accounts_test.exs:76-100
    # the locked-out page's resend button spends the same allowance (user_confirmation_required_live.ex:43-49)

  @S04 @pending @variant:require-email-verification
  Scenario: Opening the link while signed out asks me to log in, then confirms
    # Value: the link still works from an inbox on a device where I'm not logged in.
    Given I have received a "Confirm your OpenFn account" email
    And I am not logged in
    When I open the link in the email
    Then I am asked to log in
    And the flow "flow-login-return-to" has started
    When I log in
    Then I see a "Confirm my account" button
    # router.ex:189-190, :229; user_auth.ex:288-299, :490-492; user_confirmation_controller_test.exs:167-170

  @S05 @pending @variant:require-email-verification
  Scenario: A link for another account does not confirm the signed-in account
    # Value: an account is only confirmed by someone who can read the inbox it was registered with.
    Given "amara@example.org" has received a confirmation link
    And I am logged in as "ben@example.org", unconfirmed
    When I open Amara's link
    Then I am on "/projects"
    And I see "User confirmation link is invalid or it has expired."
    And neither account is confirmed
    # user_confirmation_controller.ex:106-117, :123-136, :96-102
    # user_confirmation_controller_test.exs:190-211, :270-293

  @S06 @pending @variant:require-email-verification
  Scenario: An expired link is refused and I can ask again
    # Value: an old link lying in an inbox stops working, and the user knows to request a new one.
    Given my email is unconfirmed
    And my only confirmation link was sent 8 days ago
    When I open the link
    Then I see "User confirmation link is invalid or it has expired."
    And my account is still unconfirmed
    # user_token.ex:32, :168-190; accounts.ex:1220-1228; user_confirmation_controller.ex:106-117, :128-135
    # user_confirmation_controller_test.exs:213-223 (asserts an invalid token; the 7-day expiry is untested)

  @S07 @pending @variant:require-email-verification
  Scenario: Any link I was sent works, and confirming retires the rest
    # Value: a user with several emails can click whichever arrives first, and the others can't be reused afterwards.
    Given my email is unconfirmed
    And I asked for a confirmation email twice
    When I confirm with the link from the first email
    Then my account is confirmed
    When I open the link from the second email
    Then I am on "/projects" with no error
    # accounts.ex:1135-1142 (no earlier tokens removed), :1248-1254 (all confirm tokens deleted)
    # user_confirmation_controller.ex:119-127; user_confirmation_controller_test.exs:225-236, :247-268

  @S08 @pending @variant:require-email-verification
  Scenario: Confirming after the deadline lets me back in on the same session
    # Value: a user who missed the 48 hours is not stuck once they find the link.
    Given my account was created 50 hours ago and my email is unconfirmed
    And I am logged in and held on "/users/confirm-required" (shared-authenticated-session S04)
    When I open a confirmation link I was sent and click "Confirm my account"
    Then my account is confirmed
    And I can open "/projects" without logging in again
    # confirmation_lockout.ex:18-20; user_auth.ex:305-306, :327-330; accounts.ex:1362-1368
    # confirmation_lockout_recovery_test.exs:46-80, :82-103

  @S09 @pending @variant:require-email-verification
  Scenario: A failed send tells me to try again
    # Value: the user doesn't wait for an email that was never sent.
    Given my email is unconfirmed
    And the mail service rejects the message
    When I click "Resend confirmation email"
    Then I see "We could not send that email just now. Please try again in a moment."
    # user_confirmation_controller.ex:63-68; user_notifier.ex:57-59
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Confirming broadcasts nothing; the editor reads `email_confirmed` once at channel join and LiveView pages read `current_user` at mount | `accounts.ex:1236-1255`; `workflow_channel.ex:1388-1397`; `layout_components.ex:263-265` | the editor or project tab they came from still says "Please confirm your account before ..." until reloaded | fix |
| A failed send still spends one of the 3 allowed requests and leaves a token behind | `accounts.ex:762-767`, `:1198-1202`, `:1135-1142` | after three mail outages, the fourth try says "You've asked for this a few times recently" though no email ever arrived | fix |
| The confirm page shows "Log in" and "Register" links to a user who is already signed in | `edit.html.heex:33-51` | links that make no sense for the signed-in user; "Register" invites a second account | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Resend is a GET that sends mail, and returns to the referer path with its query string dropped (the editor loses its selected job or run); owned as a decide row in shared-project-header 6.2 | `user_confirmation_controller.ex:79-86`; `router.ex:236` | decide |
| With no Referer header the resend lands on /projects | `user_confirmation_controller.ex:84` | decide |
| Confirming lands on /projects, not the page the user came from | `user_confirmation_controller.ex:90-94` | decide |
| Opening the link does not confirm; it renders a "Confirm my account" button that POSTs | `user_confirmation_controller.ex:30-32`, `:89-104`; `edit.html.heex:10-31` | decide |
| A confirmed user hitting the resend URL is silently redirected; an unconfirmed user on an instance with verification off still gets an email, because the controller does not check the flag | `user_confirmation_controller.ex:51-77`; `user_confirmation_controller_test.exs:43-57` | decide |
| A stale link opened by a confirmed user redirects with no message; an unconfirmed user gets the error | `user_confirmation_controller.ex:119-136` | preserve |
| Changing the account's email invalidates every outstanding confirmation link | `user_token.ex:179` | preserve |
| Confirm page wrapper has `id="reset-password"` | `edit.html.heex:9` | decide |
| Email says "If you have not requested an account confirmation email, please ignore this." | `user_notifier.ex:129` | decide |
| The surface ids proposed for the controller and email in workflow-editor-canvas and shared-project-header "Proposed flows" (`controller:user-confirmation-send-email`, `email:remind-account-confirmation`) differ from the ones used here | `workflow-editor-canvas.md:622`; `shared-project-header.md:384` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| none | | |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| 3 resends per 15 minutes per account, bucket `confirmation_resend` | `accounts.ex:758-767` | yes, throttle flash (S03) | preserve |
| Confirmation links valid 7 days | `user_token.ex:32`, `:190` | yes, "invalid or it has expired" (S06) | preserve |
| Rate limiter fails open: if Hammer errors the send is allowed, with a warning log | `accounts.ex:774-780` | no | preserve |
| Hammer uses Mnesia `disc_copies` on the local node | `config/config.exs:25-28`; `application.ex:18-19` | no | decide |

### 6.5 Things seen but not understood

- Whether the Mnesia rate-limit table is shared across nodes in a clustered deployment. If not, the 3-per-15-minutes limit is per node, and a user behind a load balancer could get more emails (`application.ex:18-19`).
- Clicking the link in the editor is a full navigation; whether unsaved edits survive and whether a leave warning shows is owned by shared-editor-session (`useUnloadWarning.ts:26`), not asserted here.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should confirming return the user to the page they started from (or the original resend page) rather than /projects? (6.2)
- Should open tabs drop the banner when the account is confirmed elsewhere? (6.1)
- Align the controller and email surface ids in workflow-editor-canvas and shared-project-header with this file's `controller:send-confirmation-email` and `email:confirmation`. (6.2)

## Proposed flows

none

## Proposed shared

none
