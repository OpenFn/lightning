---
id: shared-user-deletion-modal
type: shared
title: User deletion modal
status: not-started
owner:

trigger:
  old_route: any LiveView that renders LightningWeb.Components.UserDeletionModal (today /profile/:id/delete and /settings/users/:id/delete)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the host decides who sees it; the modal checks no policy of its own (user_deletion_modal.ex:1-211)
    - profile-delete-account renders it for the signed-in user's own account, with logout true and return_to /profile (profile_live/components.ex:41-48; edit.ex:61-85; policies/users.ex:23-30)
    - admin-users renders it for a superuser on any user, with is_current_user false, logout false and return_to /settings/users (user_live/components.ex:17-27; user_live/index.ex:7, :28-32; hooks.ex:40-53; router.ex:271)
    - the profile host takes the module from the /profile route's delete_modal metadata, so a deployment can substitute it there (edit.ex:73-76; config/config.exs:50-59); admin-users hard-codes it (user_live/index.html.heex:21)

inherits: []

url_params: []                               # the modal reads none; hosts own their /delete routes

config_variants:
  default: { lightning.purge_deleted_after_days: 7 }   # read under this one (bootstrap.ex:273-277); the modal itself reads no config

inventory:
  routes: []                                 # host routes are owned by profile-delete-account and admin-users
  events:
    - LightningWeb.Components.UserDeletionModal#validate      # user_deletion_modal.ex:24-35
    - LightningWeb.Components.UserDeletionModal#delete        # user_deletion_modal.ex:38-82
    - LightningWeb.Components.UserDeletionModal#close_modal   # user_deletion_modal.ex:84-87
  js_hooks:
    - ModalHook (LightningWeb.Components.Modal, modal.ex:37)
    - client-side hide_modal on Escape and click-away (modal.ex:16-17, :44-47, :60-67)
  policies: []                               # none in the component; see section 3
  workers: []                                # delete now calls Accounts.purge_user/1 inline; the nightly purge belongs to flow-account-revocation-teardown
  api_endpoints: []
  emails:
    - email:account-deletion-scheduled       # schedule branch only (accounts.ex:972; user_notifier.ex:205-224); owned by flow-account-revocation-teardown
  config: []
  not_reachable_here:
    - delete now render and purge branches from profile-delete-account (user_deletion_modal.ex:55-80, :96-137); a scheduled account has no session (accounts.ex:964-968); see profile-delete-account 6.3
    - logout false clause from profile-delete-account, and logout true clause from admin-users (user_deletion_modal.ex:89-93)
    - is_current_user false copy from profile-delete-account, and true copy from admin-users (user_deletion_modal.ex:17, :120, :171, :174-176)

related:
  - profile-delete-account                   # schedule branch only
  - admin-users                              # both branches
  - lib/lightning_web/live/components/user_deletion_modal.ex
  - lib/lightning_web/live/components/modal.ex
  - lib/lightning/accounts.ex                # has_activity_in_projects?/1 (:31-40), purge_user/1 (:43-79), delete_user/1 (:872-888), schedule_user_deletion/2 (:948-977)
  - lib/lightning/accounts/user.ex           # scheduled_deletion_changeset/2 (:338-343, :418-440)
  - test/lightning_web/live/user_live_test.exs        # :301-347, :369-394, :431-508, :538-574
  - test/lightning_web/live/profile_live_test.exs     # :198-280
  - test/lightning/accounts/user_test.exs             # :528-570
  - test/lightning/accounts_test.exs                  # :217-241, :825-965
flows:
  - flow-account-revocation-teardown
---

## 1. Purpose

The last step before a user account is closed, used by people deleting their own account from
their profile and by superusers from the admin users list. It makes the person type the account's
email address before scheduling deletion, refuses superuser accounts, and lets a superuser purge an
already scheduled account at once, so an account and its credentials don't disappear by a misclick,
on the wrong row, or while its records still anchor a project's history.

## 2. What it does

- Shows what will be deleted and asks for the account's email address
- Refuses to schedule until the typed email matches the account's
- Refuses to schedule a superuser account
- Schedules a matching account for deletion and signs the user out (own account) or returns to the users list (admin)
- Warns when the account has created runs
- Purges an already scheduled account immediately (admin users list only)
- Refuses to purge an account whose runs, project files or keychain credentials remain
- Cancel or the close button returns to the host's page with nothing changed

## 3. Who can do what

The component checks no policy. Who reaches it is the host's decision, so this matrix is the union
of the inheriting views' gates. Sources: `policies/users.ex:19-30`, `edit.ex:61-85`, `hooks.ex:40-53`,
`user_live/components.ex:172-204`, `user.ex:338-343`, `:418-440`.

| Action | Signed-in user, own account (profile) | Superuser, own account (profile) | Superuser, another user (admin list) | Anyone, another user's account (profile) |
|--------|---------------------------------------|----------------------------------|--------------------------------------|------------------------------------------|
| See the modal | yes | yes | yes | no |
| Schedule deletion | yes | no | yes, if the target is not a superuser | no |
| Delete now (target already scheduled) | no | no | yes, if the target is not a superuser and has no runs | no |
| Cancel or close | yes | yes | yes | n/a |

**Preconditions beyond role**
- The typed email must equal the target's stored email exactly (`user.ex:430-440`); this applies to scheduling only (6.1).
- Superuser targets are refused at save, not at the door (`user.ex:418-428`); the admin list hides the links for them (`user_live/components.ex:172-187`).
- The branch is chosen from `user.scheduled_deletion` as the host loaded it (`user_deletion_modal.ex:15`), not re-read on submit (6.1).
- Any host that renders the modal must gate it itself; the modal would act for anyone it is rendered to.

## 4. What it touches

**Reads**: the `user` assign passed by the host; `runs` count where `created_by_id` is the user, on every `update/2` (`user_deletion_modal.ex:11-16`; `accounts.ex:31-40`)

**Writes**
- Schedule branch: `users.scheduled_deletion` (now + `purge_deleted_after_days`), `users.disabled = true` and delete of every `user_tokens` row, in one transaction (`accounts.ex:948-968`); handed to flow-account-revocation-teardown hop 1
- Delete-now branch: in one transaction, delete the user's `project_users`, delete each of their credentials (with a credential `deleted` audit row each), then delete the `users` row, rolled back if runs, project files or keychain credentials reference it (`accounts.ex:43-79`, `:872-888`; `credentials.ex:836-849`). Jobs using those credentials lose their project credential (`accounts_test.exs:847-875`)

**Immediate side effects** (in the same request)
- Schedule branch: `disconnect` broadcasts and the "Your account has been scheduled for deletion" email (`accounts.ex:971-972`); owned by flow-account-revocation-teardown
- Flash and `push_navigate`: "User scheduled for deletion" to `/users/log_out` or `return_to` (`user_deletion_modal.ex:45-49`, `:89-93`); "User deleted" or "Cannot delete user with associated activity" to `/settings/users` (`:64-79`)
- No user-level audit event on either branch (`accounts.ex:43-79`, `:948-977`)

**Deferred side effects** (later, elsewhere)
- Schedule branch: the nightly purge; owned by flow-account-revocation-teardown

**External, non-transactional effects**
- The scheduling email; owned by the flow

**Depends on config**
- none in the component; `purge_deleted_after_days` sets the date the schedule branch writes (`accounts.ex:949-953`), not shown in the modal

**Product limits**
- none

## 5. Scenarios

Verified against `default`. Hosts inherit these instead of restating them; profile-delete-account
S01, S03, S05, S06 and S07 cover the same ground as S01, S02, S03, S05 and S08 here and could point
to them.

```gherkin
Feature: User deletion modal
  In order to close the right account, on purpose
  As a user deleting my own account, or a superuser
  I want to confirm deletion by typing the account's email address

  @S01 @pending
  Scenario Outline: The modal says what is deleted and asks for the email
    # Value: the person deleting sees that credentials go with the account, and can check none are in production use, before committing.
    Given the modal is open on "<host>" for user "amara@example.org"
    Then I see a dialog "Delete user"
    And I see "<owner> account and credential data will be deleted. Please make sure none of these credentials are used in production workflows."
    And I see a "User email" field and the buttons "Delete account" and "Cancel"
    # user_deletion_modal.ex:17, :139-205; profile_live_test.exs:198-216 (profile host); no admin-host test asserts the copy
    Examples:
      | host                          | owner        |
      | /profile/<own id>/delete      | Your         |
      | /settings/users/<id>/delete   | This user's  |

  @S02 @pending
  Scenario: A mismatched email does not schedule the account
    # Value: a slip of the mouse or the wrong row can't disable an account its owner still needs.
    Given the modal is open for unscheduled user "amara@example.org"
    When I set "User email" to "invalid@email.com"
    Then I see "This email doesn't match your current email"
    When I click "Delete account"
    Then I still see the dialog with that error
    And "amara@example.org" is not disabled or scheduled for deletion
    # user_deletion_modal.ex:24-35, :41-44, :51-52; user.ex:338-343, :430-440
    # user_live_test.exs:322-327, profile_live_test.exs:218-223 (live validation only); user_test.exs:528-539 (changeset)

  @S03 @pending
  Scenario: A superuser account can't be scheduled for deletion
    # Value: an instance can't lose its administrators through either deletion modal.
    Given the modal is open for superuser "root@example.org"
    When I set "User email" to "root@example.org"
    Then I see "You can't delete a superuser account."
    When I click "Delete account"
    Then "root@example.org" is not disabled or scheduled for deletion
    # user.ex:338-343, :418-428; user_deletion_modal.ex:51-52; user_test.exs:557-570 (changeset only); no LiveView test

  @S04 @pending
  Scenario Outline: A matching email schedules the account and hands off
    # Value: a confirmed deletion takes effect in one step, and the person lands somewhere that makes sense for who they are.
    Given the modal is open on "<host>" for unscheduled non-superuser "amara@example.org"
    When I set "User email" to "amara@example.org"
    And I click "Delete account"
    Then "amara@example.org" is disabled and scheduled for deletion
    And I am sent to "<next>"
    And the flow "flow-account-revocation-teardown" has started for "amara@example.org"
    # user_deletion_modal.ex:38-49, :89-93; accounts.ex:948-977
    # user_live_test.exs:329-346 (admin host: list, date shown, email); profile_live_test.exs:225-236 (profile host: redirect, email)
    Examples:
      | host                          | next             |
      | /profile/<own id>/delete      | /users/log_out   |
      | /settings/users/<id>/delete   | /settings/users  |

  @S05 @pending
  Scenario: An account that has created runs is warned it may stay
    # Value: nobody is told an account is gone when its audit history keeps it from being removed.
    Given user "amara@example.org" has started a run
    And "amara@example.org" is not scheduled for deletion
    When the modal opens for "amara@example.org"
    Then I see "activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted."
    Given user "bob@example.org" has never started a run
    When the modal opens for "bob@example.org"
    Then I do not see that note
    # user_deletion_modal.ex:16, :173-177; accounts.ex:31-40; accounts_test.exs:217-241 (function only); no LiveView test

  @S06 @pending
  Scenario: A superuser purges an already scheduled account
    # Value: a superuser can remove an account and its credentials at once instead of waiting out the grace period.
    Given I am a superuser on "/settings/users"
    And non-superuser "amara@example.org" is scheduled for deletion and has no runs, project files or keychain credentials
    When I click "Delete now" for "amara@example.org"
    And I click "Delete account"
    Then I am on "/settings/users"
    And I see "User deleted"
    And "amara@example.org", their project memberships and their credentials no longer exist
    # user_deletion_modal.ex:15, :64-70; accounts.ex:43-79; user_live_test.exs:431-458; accounts_test.exs:825-910

  @S07 @pending
  Scenario: An account with runs can't be purged now
    # Value: a person whose runs are part of a project's audit trail is not hard-deleted out from under it.
    Given I am a superuser on "/settings/users"
    And "amara@example.org" is scheduled for deletion and has started a run
    When I click "Delete now" for "amara@example.org"
    Then I see "This user cannot be deleted until their auditable activities have also been purged."
    And I see only a "Cancel" button
    # user_deletion_modal.ex:96-137; user_live_test.exs:538-574

  @S08 @pending
  Scenario: A purge blocked by remaining activity changes nothing
    # Value: a failed purge leaves the account, its memberships and credentials intact and says so, instead of claiming success.
    Given I am a superuser with the delete now modal open for scheduled user "amara@example.org"
    And "amara@example.org" has a run, a project file or a keychain credential the modal did not count
    When I click "Delete account"
    Then I am on "/settings/users"
    And I see "Cannot delete user with associated activity"
    And I do not see "User deleted"
    And "amara@example.org" still exists with their memberships and credentials
    # user_deletion_modal.ex:65, :72-79; accounts.ex:50-79, :872-888
    # user_live_test.exs:460-508 (run created after the modal opened); accounts_test.exs:913-965

  @S09 @pending
  Scenario Outline: Backing out returns to the host and changes nothing
    # Value: abandoning a deletion is one click and leaves the account untouched.
    Given the modal is open on "<host>" for user "amara@example.org"
    When I click <control>
    Then I am on "<return_to>"
    And "amara@example.org" is not disabled or scheduled for deletion
    # user_deletion_modal.ex:84-87, :106-115, :125-132, :149-158, :197-204
    # user_live_test.exs:369-394 (admin, Cancel); profile_live_test.exs:251-280 (profile, Cancel)
    Examples:
      | host                          | control  | return_to        |
      | /profile/<own id>/delete      | "Cancel" | /profile         |
      | /settings/users/<id>/delete   | "Close"  | /settings/users  |
```

Every other browser dropping, the scheduling email and the sign-in refusal after S04 are
flow-account-revocation-teardown S01, S06 and S07. They are not restated here.

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The delete-now branch ignores the typed email: it renders the same "User email" field and "Delete account" button, but submitting with the field empty or wrong purges the account | `user_deletion_modal.ex:38-40`, `:64-65`, `:179-183` | a confirmation field that looks required but isn't; one click hard-deletes the account | fix |
| The branch is chosen from the host's possibly stale `user`: if another superuser cancels the deletion after the modal opened, "Delete account" still purges | `user_deletion_modal.ex:11-15`, `:64-65`; `user_live/index.ex:28-52` | an account whose deletion was just cancelled is hard-deleted | fix |
| Delete now has no superuser check; a superuser with `scheduled_deletion` set, opened by URL, is purged. The app's own paths keep that state from arising (scheduling refuses superusers, promotion clears the date), but the admin tests build it directly | `user_deletion_modal.ex:64-70`; `accounts.ex:43-79`; `user.ex:304`, `:442-445`; `user_live_test.exs:413-429`, `:510-536` | a superuser account can be deleted by typing its delete URL | decide |
| Two superusers purging the same account: the second `Repo.get` returns nil and `delete_user/1` has no nil clause | `accounts.ex:64`, `:872` | a crash instead of a message for the slower superuser | fix |
| Escape and click-away hide the dialog client-side only; the modal sets no `on_close`, so the URL stays on the `/delete` route and a reload reopens it (also profile-delete-account 6.1 row 2) | `user_deletion_modal.ex:99`, `:142`; `modal.ex:16-17`, `:44-47`, `:60-67` | the dialog disappears but the address bar still says delete | decide |

The admin host's "doesn't match your current email" copy and the self-disconnect racing the
`/users/log_out` navigation are flow-account-revocation-teardown 6.1 rows 5 and 2.

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Both branches share the title "Delete user", the "User email" label and the "Delete account" button; nothing on screen says whether this schedules or purges now | `user_deletion_modal.ex:103`, `:146`, `:182`, `:195` | decide |
| "account and credential data will be deleted" reads as immediate on the schedule branch, where the account is only disabled and the date is not shown | `user_deletion_modal.ex:171`; `accounts.ex:948-968` | decide |
| The activity note and the delete-now block count only runs, while the purge is also blocked by project files and keychain credentials, which surface only as the S08 failure | `accounts.ex:31-40` vs `:108-128`, `:872-888` | decide |
| The email is compared exactly; stored emails are lowercase, so typing capitals is refused | `user.ex:430-433`; `utils/validators.ex:27` | decide |
| The delete-now branch writes no user-level audit event and sends no email; the credential `deleted` audit rows are attributed to the user being purged | `accounts.ex:43-79`; `credentials/audit.ex:30-36` | decide |
| `purge_user/1` matches `{:ok, _}` on each credential delete, so a failure there raises instead of returning the error S08 handles | `accounts.ex:60-62` | decide |
| `update/2` rebuilds an empty changeset on every host re-render, clearing a shown error; the initial changeset already fails the email check but its errors stay hidden until the first change sets an action | `user_deletion_modal.ex:18`, `:32` | preserve |
| A hidden `user[id]` field is submitted and ignored | `user_deletion_modal.ex:185`, `:38-44` | preserve |
| "Delete account" shows "Deleting..." while the submit is in flight | `user_deletion_modal.ex:192` | preserve |
| The form id `scheduled_deletion_form` is shared with the project deletion modal | `user_deletion_modal.ex:167`; `project_deletion_modal.ex:142` | preserve |
| Only the profile host can be given a substitute module through route metadata; the admin list always uses this one | `edit.ex:73-76`; `user_live/index.html.heex:21` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `delete` clause for a scheduled user with runs: flash "Cannot delete user that has activities in other projects" | `user_deletion_modal.ex:55-62` | that state renders the form-less variant (`:96-137`), so no submit can reach it; `update/2` recomputes both assigns together |
| Delete-now render and purge from profile-delete-account | `user_deletion_modal.ex:55-80`, `:96-137` | a scheduled account has no session (`accounts.ex:964-968`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| `has_activity_in_projects?` counts all the user's runs on every `update/2` | `user_deletion_modal.ex:11-16`; `accounts.ex:31-40` | no | preserve |
| Email validated on every change, no debounce | `user_deletion_modal.ex:164` | no | preserve |

### 6.5 Things seen but not understood

- Whether a superuser deleting from the admin list should be told the target's runs count rather than "activity related to active projects", which the note does not scope to active projects (`accounts.ex:31-40`). Disposition: decide.
- No LiveView test covers the superuser refusal (S03), the activity note (S05), or a refused submit (S02). Disposition: preserve (write the tests).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should delete now require the typed email, and re-check that the account is still scheduled and not a superuser before purging (6.1)? (owner: security)
- Should the two branches have distinct copy and button labels, and should scheduling show the deletion date (6.2)? (owner: product)
- Should the email check ignore case (6.2)? (owner: product)
- Should the activity check count project files and keychain credentials, as the purge does (6.2)? (owner: product)
- Should Escape and click-away close through `close_modal` like Cancel does (6.1)? (owner: product)

## Proposed flows

none. Referenced: flow-account-revocation-teardown (S04 hands off to it; it lists both hosts in its surfaces).

## Proposed shared

none

## Summary

- Scenarios: 9 (S01 to S09), all `@pending`.
- Section 6: 6.1 has 5, 6.2 has 11, 6.3 has 2, 6.4 has 2, 6.5 has 2.
- Flows: references flow-account-revocation-teardown (S04); none proposed.
- Shared: none referenced or proposed.
- Unsure: Escape and click-away behaviour is read from code, not run; profile-delete-account S01, S03, S05, S06, S07 and several of its 6.2 rows overlap this file; admin-users has no annotation yet.
