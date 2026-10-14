---
id: profile-delete-account
type: view
title: User profile › Delete account
status: not-started
owner:

trigger:
  old_route: /profile/:id/delete
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the user is signed in and admitted by shared-authenticated-session (`router.ex:189-190`, `:default` live_session `router.ex:288`, route `router.ex:324`)
    - "`:id` is the signed-in user's own id (`edit.ex:61-70`; `policies/users.ex:23-30`); any other existing id is sent back to `/profile`"
    - the account is not already scheduled for deletion (such an account has no session left: `accounts.ex:964-968`)
    - entered from the "Delete my account" card on profile-account (profile-account S11; `components.ex:86-100`)

inherits:
  - shared-authenticated-session    # login redirect, lockout, sidebar, banners; S01 to S10, as profile-account
  - shared-project-header           # no-project header only: S11, S12, S13, S14, S17, S18, as profile-account
  - shared-local-datetime           # the "Created" date on the profile behind the modal (components.ex:17); S01, S04, S05
  - shared-user-deletion-modal
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: id (path segment)
    set_by: profile-account
    effect: must equal the signed-in user's id; it is only used for the policy check, the modal always acts on the session's user (`edit.ex:62-70`, `components.ex:41-48`)

config_variants:
  default: { lightning.purge_deleted_after_days: 7 }                     # read under this one (bootstrap.ex:272-278)
  custom-delete-modal: { Lightning.Extensions.Routing: "/profile route metadata delete_modal: <module>" }   # config/config.exs:58-59; edit.ex:73-76

inventory:
  routes:
    - live /profile/:id/delete  ProfileLive.Edit :delete      # router.ex:324, :default live_session
  events:
    - Components.UserDeletionModal#validate       # user_deletion_modal.ex:24-35; behaviour owned by shared-user-deletion-modal (proposed)
    - Components.UserDeletionModal#delete         # user_deletion_modal.ex:38-82; scheduling branch only, see 6.3
    - Components.UserDeletionModal#close_modal    # user_deletion_modal.ex:84-87
  js_hooks:
    - ModalHook                                   # assets/js/hooks/index.ts:522-530, via modal.ex:37
  policies:
    - Lightning.Policies.Users :delete_account (policies/users.ex:23-30)
  workers: []                                     # the purge job is reached through flow-account-revocation-teardown
  api_endpoints: []
  emails:
    - email:account-deletion-scheduled            # user_notifier.ex:205-224; via flow-account-revocation-teardown
  config:
    - :lightning, Lightning.Extensions.Routing (the /profile route's delete_modal metadata)   # config/config.exs:58-59; edit.ex:73-76
    - :lightning, :purge_deleted_after_days       # accounts.ex:949-953; via flow-account-revocation-teardown
  not_reachable_here:
    - UserDeletionModal "delete now" render and purge branches (user_deletion_modal.ex:55-80, :96-137); owned by admin-users (6.3)
    - UserDeletionModal logout false clause (user_deletion_modal.ex:92-93); owned by admin-users
    - UserDeletionModal is_current_user false copy (user_deletion_modal.ex:17, :120, :171, :174-176); owned by admin-users
    - ProfileLive.Edit :edit, FormComponent, MfaComponent, GithubComponent, ExperimentalFeaturesComponent and the GDPR card render behind the modal; owned by profile-account, profile-mfa, profile-github, profile-experimental-features
    - ProfileLive.Edit handle_info OauthTokenAdded / OauthTokenFailed (edit.ex:33-53); owned by flow-github-connect

related:
  - profile-account                 # host page and entry point (S11)
  - admin-users                     # the other user of user_deletion_modal.ex (user_live/components.ex:17-26)
  - lib/lightning/accounts.ex       # schedule_user_deletion/2 (:948-977), has_activity_in_projects?/1 (:31-40)
  - test/lightning_web/live/profile_live_test.exs   # :198-280
flows:
  - flow-account-revocation-teardown
---

## 1. Purpose

Any signed-in user who no longer wants an OpenFn account comes here to close it themselves. The
page asks them to type their own email address before it disables the account and schedules it,
and its credentials, for removal. Without it, leaving would need an administrator; and without the
checks here, a mistyped click or an edited URL could disable an account its owner still needs, or
someone else's.

## 2. What it does

- Any signed-in user opens a deletion confirmation for their own account, over the profile page
- Any non-superuser schedules their own account for deletion by typing their email address
- Users who have created runs are warned their account may not be fully removable
- Superusers can open the confirmation but cannot delete their own account
- Nobody can open the confirmation for another user's account
- Any user backs out with "Cancel" and returns to the profile

## 3. Who can do what

Sources: `policies/users.ex:23-30` (`:delete_account`), `edit.ex:61-85`, `user.ex:338-343`, `:418-440`.

| Action | Signed-in user, own id | Superuser, own id | Support user, own id | Anyone, another user's id |
|--------|------------------------|-------------------|----------------------|---------------------------|
| See the confirmation | yes | yes | yes | no |
| Schedule own deletion | yes | no | yes | no |
| Cancel | yes | yes | yes | n/a |

**Preconditions beyond role**
- Self only: the URL id must match the session's user (`policies/users.ex:23-30`).
- The typed email must equal the account's stored email exactly (`user.ex:430-440`).
- Superusers are refused at save, not at the door (`user.ex:418-428`).
- An account already scheduled for deletion has no session and cannot reach the page (`accounts.ex:964-968`).

## 4. What it touches

**Reads**: `users` by URL id (`edit.ex:62`; `accounts.ex:372`); `runs` count where `created_by_id` is the user, on every modal update (`user_deletion_modal.ex:16`; `accounts.ex:31-40`); everything profile-account reads for the page behind the modal

**Writes** (handed to flow-account-revocation-teardown, hop 1)
- `users.scheduled_deletion` (now + `purge_deleted_after_days`) and `users.disabled = true`, plus delete of every `user_tokens` row, in one transaction (`accounts.ex:948-968`)

**Immediate side effects**
- `disconnect` broadcast on `user_socket:<id>` and `users_live:<id>` (`accounts.ex:971`); flow-account-revocation-teardown hop 2
- Email "Your account has been scheduled for deletion" (`accounts.ex:972`; `user_notifier.ex:205-224`); flow hop 3
- Flash "User scheduled for deletion" and `push_navigate` to `/users/log_out` (`user_deletion_modal.ex:45-49`, `:89-90`); flow hop 7
- No audit event (`accounts.ex:948-977`)

**Deferred side effects**
- Nightly purge of the user, credentials and project memberships once the date passes, if the user has no runs, project files or keychain credentials (`accounts.ex:43-79`, `:104-130`); owned by flow-account-revocation-teardown

**External, non-transactional effects**
- The deletion email; owned by the flow

**Depends on config**
- The modal module comes from the `/profile` route's `delete_modal` metadata (`edit.ex:73-76`; `config/config.exs:58-59`); variant `custom-delete-modal` lets a deployment substitute its own
- `purge_deleted_after_days` sets the deletion date (`accounts.ex:949-953`)

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Deleting my own account from the profile
  In order to leave OpenFn without asking an administrator
  As any signed-in user
  I want to confirm and schedule the deletion of my own account

  @S01 @pending
  Scenario: The delete page asks me to confirm over my profile
    # Value: a user sees that their credentials go with the account before anything happens, and can check none are used in production.
    Given I am signed in as "amara@example.org"
    When I open "/profile/<my user id>/delete"
    Then I see my profile page
    And I see a dialog "Delete user"
    And I see "Your account and credential data will be deleted. Please make sure none of these credentials are used in production workflows."
    And I see a "User email" field and the buttons "Delete account" and "Cancel"
    # edit.ex:61-81; components.ex:41-48; user_deletion_modal.ex:139-205
    # profile_live_test.exs:198-216

  @S02 @pending
  Scenario: A user schedules their own account for deletion
    # Value: a user can close their own account, and it stops working everywhere at once.
    Given I am signed in as "amara@example.org", who is not a superuser
    And I am on "/profile/<my user id>/delete"
    When I set "User email" to "amara@example.org"
    And I click "Delete account"
    Then my account is disabled and scheduled for deletion
    And this browser is sent to "/users/log_out"
    And the flow "flow-account-revocation-teardown" has started for my account
    # user_deletion_modal.ex:38-49, :89-90; accounts.ex:948-977
    # profile_live_test.exs:225-236 (asserts the redirect and the email; the email belongs to the flow, S07 there)

  @S03 @pending
  Scenario: The wrong email address does not delete the account
    # Value: a slip of the mouse or a half-read dialog can't disable an account its owner still needs.
    Given I am on "/profile/<my user id>/delete"
    When I set "User email" to "invalid@email.com"
    Then I see "This email doesn't match your current email"
    When I click "Delete account"
    Then I still see the dialog with that error
    And my account is not disabled
    And no email is sent
    # user.ex:338-343, :430-440; user_deletion_modal.ex:24-35, :51-52
    # profile_live_test.exs:218-223 (live validation only; the refused submit is read from code)

  @S04 @pending
  Scenario: I can't open the deletion of someone else's account
    # Value: no one can disable another person's account by editing the URL.
    Given I am signed in
    And "bob@example.org" is another registered user
    When I open "/profile/<bob's user id>/delete"
    Then I am on "/profile"
    And I see "You can't perform this action"
    And I do not see the "Delete user" dialog
    # edit.ex:61-70, :82-84; policies/users.ex:23-30
    # profile_live_test.exs:239-249

  @S05 @pending
  Scenario: A superuser can't delete their own account here
    # Value: an instance can't lose its administrators through the self-service page.
    Given I am signed in as a superuser
    And I am on "/profile/<my user id>/delete"
    When I set "User email" to my email address
    Then I see "You can't delete a superuser account."
    When I click "Delete account"
    Then my account is not disabled
    # user.ex:338-343, :418-428; user_deletion_modal.ex:51-52; no test covers this

  @S06 @pending
  Scenario: A user who has created runs is warned the account may stay
    # Value: someone whose work is part of a project's audit history isn't told their account is gone when it can't be removed yet.
    Given I have started a run in a project
    When I open "/profile/<my user id>/delete"
    Then I see "*Note that you still have activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted."
    Given I have never started a run
    When I open "/profile/<my user id>/delete"
    Then I do not see that note
    # user_deletion_modal.ex:16, :173-177; accounts.ex:31-40, :104-111; no LiveView test covers the note

  @S07 @pending
  Scenario: Cancelling leaves the account alone
    # Value: a user can back out of deletion safely at the last moment.
    Given I am on "/profile/<my user id>/delete"
    When I click "Cancel"
    Then I am on "/profile"
    And I do not see the "Delete user" dialog
    And my account is not disabled
    # user_deletion_modal.ex:84-87, :197-204, :106-115 (the close button does the same); components.ex:47
    # profile_live_test.exs:251-280
```

Reaching this page from "Delete my account" is profile-account S11. Every other browser dropping,
the deletion email and sign-in refusal are flow-account-revocation-teardown S01, S06 and S07. They are
not restated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The URL user is loaded with `get_user!` before the policy runs, so an id that doesn't exist raises `Ecto.NoResultsError` and one that isn't a UUID raises `Ecto.Query.CastError`, instead of "You can't perform this action" | `edit.ex:62`; `accounts.ex:372` | an error page (404 or 400 through phoenix_ecto) for a mistyped URL; the difference also tells a probing user which ids exist | fix |
| Escape and click-away close the dialog with client-side JS only; the URL stays on `/profile/:id/delete` and the server still has the modal mounted, so a reload or reconnect reopens it | `modal.ex:16-17`, `:44-47`, `:60-67`, `:151-170`; `user_deletion_modal.ex:99`, `:142` (no `on_close`) | the dialog disappears but the address bar still says delete; refreshing brings it back | fix |
| If a deployment's routing config drops the `/profile` route or its `delete_modal` metadata, `route_info` returns `:error` (then `Map.get` raises `BadMapError`) or `nil` (then `live_component` has no module); the attr default in `action_cards` never applies because the template always passes the key | `edit.ex:73-76`; `edit.html.heex:21`; `components.ex:30-31` | a crash on "Delete my account" under variant `custom-delete-modal` with incomplete metadata | fix |
| The scheduling write broadcasts `disconnect` to this page's own transport before `push_navigate` to `/users/log_out` returns; same as flow-account-revocation-teardown 6.1 row 2 | `accounts.ex:971`; `user_deletion_modal.ex:45-49`, `:89-90` | probably "/users/log_in" without "User scheduled for deletion"; the end page is the same | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The dialog is titled "Delete user" and the field labelled "User email" when a user is deleting their own account; the copy is shared with the admin list | `user_deletion_modal.ex:146`, `:182` | decide |
| "Your account and credential data will be deleted" reads as immediate, but the account is only disabled now; the date is not shown in the dialog (only in the email), and the purge skips anyone with runs, project files or keychain credentials | `user_deletion_modal.ex:171`; `accounts.ex:948-968`, `:104-127`; `user_notifier.ex:205-224` | decide |
| The activity note checks only runs created by the user, while the purge is also blocked by project files and keychain credentials the user created; the note says "active projects" but counts runs in any project | `accounts.ex:31-40` vs `:104-127`; `user_deletion_modal.ex:173-177` | decide |
| The typed email is compared to the stored email exactly; stored emails are lowercase, so typing the address with capitals is refused as "doesn't match" | `user.ex:430-433`; `utils/validators.ex:27` | decide |
| The URL `:id` only feeds the policy; the modal is always given the session's `current_user`, and the loaded `@user` assign is not read by the template | `edit.ex:62`, `:80`; `components.ex:44-45`; `edit.html.heex:16-25` | preserve |
| A refused id uses `push_patch` to `/profile`, which sits in another live_session (`:services`), so it lands as a redirect during mount rather than a patch | `edit.ex:83-84`; `router.ex:288`, `:324`, `:351-355`; `profile_live_test.exs:245-247` | preserve |
| `/profile/:id/delete` is in `:default` and `/profile` in `:services`, so opening the dialog and "Cancel" are full page loads; same as profile-account 6.2 | `router.ex:324`, `:351-355`; `components.ex:92`, `:47`; `user_deletion_modal.ex:86` | decide |
| The profile reads the modal module from `/profile`'s route metadata, while the admin users list hard-codes `UserDeletionModal`, so a deployment's substitute applies to self-deletion only | `edit.ex:73-76`; `user_live/index.html.heex:21` | decide |
| A hidden `user[id]` field is submitted and ignored | `user_deletion_modal.ex:185`, `:38-44` | preserve |
| The initial changeset already fails the email check, but its errors are hidden until the first change sets an action | `user_deletion_modal.ex:18`, `:32` | preserve |
| "Delete account" shows "Deleting..." while the submit is in flight | `user_deletion_modal.ex:192` | preserve |
| The whole profile page, including its forms and the GitHub subscription, mounts and stays live behind the dialog | `edit.ex:14-20`; `components.ex:49-79` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| "Delete now" render and the `purge_user` / "Cannot delete user that has activities in other projects" branches, which would send a non-superuser to `/settings/users` | `user_deletion_modal.ex:15`, `:55-80`, `:96-137` | `delete_now?` needs `scheduled_deletion` set, and scheduling deletes every session token (`accounts.ex:964-968`; also `:205-206` for the admin form); owned by admin-users |
| `logout_after_deletion` with `logout: false` | `user_deletion_modal.ex:92-93` | the profile always passes `logout={true}` (`components.ex:46`) |
| "This user" / "This user's" / "this user still has" copy | `user_deletion_modal.ex:17`, `:120`, `:171`, `:174-176` | the profile never passes `is_current_user`, which defaults to true |
| `:user` and `:page_title` assigns on `:delete` beyond the policy check | `edit.ex:79-80` | the template reads `@current_user`, and the page title is the same "User Profile" as `:edit` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `has_activity_in_projects?` counts all the user's runs on every modal `update/2`, i.e. on every parent re-render | `user_deletion_modal.ex:11-16`; `accounts.ex:31-40` | no | preserve |
| Email validated on every change, no debounce | `user_deletion_modal.ex:164` | no | preserve |

### 6.5 Things seen but not understood

- A user with runs is never picked up by the purge (`accounts.ex:104-111`), and the note says this lasts "until those projects are deleted". Whether data retention or project deletion ever removes those runs, so the account is eventually purged, was not traced. Disposition: decide.
- Whether the "User scheduled for deletion" flash survives `push_navigate` to `/users/log_out`, which puts its own "Logged out successfully." (`user_session_controller.ex:69-73`); flow-account-revocation-teardown 6.5 asks the same. Disposition: decide.
- No test covers the superuser refusal (S05), the activity note on the profile (S06), or a refused submit (S03). Disposition: preserve (write the tests).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the dialog say when the account will actually be deleted, and that runs may keep it (6.2)?
- Should self-deletion use the same deployment-substitutable modal as the admin list, or neither (6.2)?
- Should the email check ignore case (6.2)?
- Does the self-disconnect lose the logout navigation in a real browser (6.1)?

## Proposed flows

- none. Referenced: `flow-account-revocation-teardown` (this page is one of its entries, `profile-delete-account` in its surfaces; S02 asserts only the handoff to `/users/log_out` and the flow).

## Proposed shared

- `shared-user-deletion-modal` (new): the "Delete user" confirmation LiveComponent used by profile-delete-account and admin-users (`user_deletion_modal.ex`; entries `profile_live/components.ex:41-48` with `logout: true`, `is_current_user` defaulted, `return_to: /profile`, and `user_live/components.ex:17-26` with `is_current_user: false`, `logout: false`, `return_to: /settings/users`). Behaviour: typed-email confirmation validated on change and on submit with "This email doesn't match your current email" (`:24-35`, `user.ex:430-440`); superusers refused with "You can't delete a superuser account." (`user.ex:418-428`); scheduling via `Accounts.schedule_user_deletion/2` then flash "User scheduled for deletion" and navigate to `/users/log_out` or `return_to` (`:38-53`, `:89-93`); activity note when the user has created runs (`:16`, `:173-177`); "delete now" when `scheduled_deletion` is already set, which skips the email check, purges via `Accounts.purge_user/1` with "User deleted" or "Cannot delete user with associated activity", or shows "cannot be deleted until their auditable activities have also been purged" with only "Cancel" when runs exist (`:55-80`, `:96-137`; `user_live_test.exs:431-506`, `:538-574`); Cancel and the close button navigate to `return_to` (`:84-87`), while Escape and click-away only hide it client-side (`modal.ex:16-17`, `:44-47`, `:60-67`). Surfaces: profile-delete-account, admin-users.

## Lead resolution (batch 7)

- `shared-user-deletion-modal` created from this file's Proposed shared entry; admin-users will inherit it too.
