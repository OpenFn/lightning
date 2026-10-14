---
id: flow-credential-scheduled-deletion
type: flow
title: Schedule a credential for deletion, then cancel or purge
status: not-started
owner:

trigger:
  entry: credentials-index                   # project credential settings render the same component and modal, so they can start it too (see 8)
  exit: credentials-index
  surfaces:
    - credentials-index
    - email:credential-deletion-scheduled
    - capability:credentials-purge-deleted
    - credentials-index
    - project-settings-credentials            # second entry, added by lead
  reachable_when:
    - credentials-index: the signed-in user owns the credential (`credential_index_component.html.heex:72`, `policies/users.ex:42-44`)

inherits:
  - shared-credential-index-component       # S05 owns the cancel click and its flash; S06 owns forged-action refusal

url_params: []

config_variants:
  default: { purge_deleted_after_days: 7 }               # read under this variant (bootstrap.ex:273-278)
  purge-immediate: { purge_deleted_after_days: 0 }       # dated now, but no purge cron is registered (credentials.ex:922-925, bootstrap.ex:306-317)

inventory:
  routes: []                                # /credentials is owned by credentials-index
  events:
    - CredentialDeletionModal#delete        # scheduling branch only; "Delete now" belongs to credentials-index S17, S18
    - CredentialIndexComponent#cancel_credential_deletion   # owned by shared-credential-index-component S05
  js_hooks: []
  policies:
    - Lightning.Policies.Users (:delete_credential), via Credentials.authorize_credential_owner/2 (credentials.ex:948-959)
  workers:
    - Lightning.Credentials (Oban, queue :background, max_attempts 1, args type purge_deleted; cron 02:30)   # credentials.ex:6-8, :42-71; bootstrap.ex:310-311
  api_endpoints: []
  emails:
    - email:credential-deletion-scheduled   # UserNotifier.send_credential_deletion_notification_email/2, user_notifier.ex:226-246
  config:
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
  not_reachable_here: []

related:
  - lib/lightning_web/live/components/credential_deletion_modal.ex
  - lib/lightning_web/live/credential_live/credential_index_component.ex
  - lib/lightning_web/live/credential_live/credential_index_component.html.heex
  - lib/lightning/credentials.ex
  - lib/lightning/credentials/audit.ex
  - lib/lightning/auth_providers/oauth_http_client.ex
  - lib/lightning/accounts/user_notifier.ex
  - lib/lightning/config/bootstrap.ex
  - test/lightning/credentials_test.exs
  - test/lightning_web/live/credential_live_test.exs
flows: []
---

## 1. Purpose

A credential owner retires a secret they no longer want used. Scheduling cuts it off from every
project and job at once, withdraws OpenFn's OAuth access at the provider, and tells the owner by
email how to undo it; a daily purge later scrubs the secret and removes the record. Without this a
retired secret would keep running jobs or sit in the database indefinitely, and a mistaken
deletion would have no window in which to recover it.

## 2. What it does

Owner confirms "Delete credential" on credentials-index → credential unshared from all projects, jobs lose it, OAuth tokens revoked, owner emailed → owner may "Cancel deletion" from the list during the grace period → after `purge_deleted_after_days` the 02:30 purge scrubs every scheduled credential's secrets and deletes those never used in a run.

## 3. Who can do what

Ownership, not project role (`policies/users.ex:42-44`, `credentials.ex:948-959`).

| Action | Credential owner | Anyone else | System (purge job) |
|--------|------------------|-------------|--------------------|
| Schedule deletion | yes | no | n/a |
| Receive the scheduled-deletion email | yes | no | n/a |
| Cancel a scheduled deletion | yes | no | n/a |
| Scrub secrets of a credential past its date | n/a | n/a | yes |
| Delete a credential past its date | n/a | n/a | yes, only if no run step used it |

**Preconditions beyond role**
- The purge only touches credentials whose `scheduled_deletion` has passed (`credentials.ex:44-47`).
- A credential referenced by any `steps.credential_id` is scrubbed but never deleted (`credentials.ex:55-58`, `:1088-1093`); the FK has `on_delete: :nothing` (`priv/repo/migrations/20230419234837_add_credential_id_to_runs.exs:6`).
- The purge cron exists only when `purge_deleted_after_days > 0` (`bootstrap.ex:306-317`).

## 4. What it touches

**Reads**: `credentials`, `credential_bodies`, `project_credentials`, `jobs`, `oauth_clients`, `users`, `steps`

**Writes**
- Hop 1, schedule (one transaction, `credentials.ex:889-920`): `credentials.scheduled_deletion = now + purge_deleted_after_days` (`:922-925`); `jobs.project_credential_id = null` for every job using it; all its `project_credentials` deleted (`:1036-1052`); one `token_revoked` audit row per environment for OAuth credentials whose client has a revocation endpoint (`:961-1034`, `audit.ex:104-113`)
- Hop 3, cancel: `credentials.scheduled_deletion = null` plus an `updated` audit row, through the ordinary update path (`credentials.ex:936-941`, `:262-290`, `:703-733`)
- Hop 4, purge: every body of each due credential set to `{}` (`credentials.ex:74-83`); credentials with no step activity deleted with a `deleted` audit row, bodies cascading (`:60-68`, `:842-849`, `priv/repo/migrations/20250926003931_create_credential_bodies.exs:8`)

**Immediate side effects** (in the same request)
- Hop 1: flash "Credential scheduled for deletion" and navigate back to the list (`credential_deletion_modal.ex:47-51`); the row's menu now shows "Cancel deletion" and "Delete now" (`credential_index_component.ex:459-490`)
- Hop 2: email "Your "<name>" credential will be deleted" to the owner, sent from inside the transaction (`credentials.ex:908-911`, `:1054-1059`, `user_notifier.ex:226-246`)
- Hop 3: flash "Credential deletion canceled" (shared-credential-index-component S05)

**Deferred side effects** (later, elsewhere)
- Daily at 02:30 the purge job runs (`bootstrap.ex:310-311`, `credentials.ex:42-71`)

**External, non-transactional effects**
- Token revocation HTTP calls to the OAuth client's revocation endpoint, refresh token then access token, per environment, inside the transaction (`credentials.ex:904-907`, `oauth_http_client.ex:31-60`); a later rollback leaves tokens revoked
- The email leaves from inside the transaction; a later rollback leaves the owner told about a deletion that did not happen (`credentials.ex:908-911`)

**Depends on config**
- `purge_deleted_after_days`: the scheduled date, the grace period in the email (`user_notifier.ex:154-162`), and whether the purge runs at all

**Product limits**
- A scheduled credential keeps its secrets for `purge_deleted_after_days` (default 7), stated in the email

## 5. Scenarios

Verified against `default` unless tagged. Single-surface steps owned elsewhere are not restated:
the schedule click and its in-page result (credentials-index S16), "Delete now" (credentials-index
S17, S18), the tampered-id refusal (credentials-index S19), the cancel click (shared-credential-index-component S05)
and forged actions (shared-credential-index-component S06).

```gherkin
Feature: Scheduled credential deletion
  In order to retire a secret without losing it to a single mistaken click
  As a credential owner
  I want a deletion that takes effect at once, tells me how to undo it, and completes on its own

  @S01 @pending
  Scenario: Scheduling cuts the credential off and emails the owner how to undo it
    # Value: the owner has a record of the deletion and knows how and until when it can be reversed.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV" and used by a job there
    When I delete "DHIS2 prod" on "/credentials" and confirm
    Then "DHIS2 prod" is scheduled for deletion 7 days from now
    And "DHIS2 prod" is no longer shared with any project and the job has no credential
    And I receive an email "Your \"DHIS2 prod\" credential will be deleted"
    And the email says the credential has been disconnected from all projects, its secrets will be scrubbed after 7 days, and the deletion can be cancelled from the "Credentials" menu
    # credential_deletion_modal.ex:40-51, credentials.ex:889-925, :1036-1059, user_notifier.ex:154-162, :226-246
    # credentials_test.exs:150-201 (date, unshare, job, subject and recipient; body copy not asserted)

  @S02 @pending
  Scenario: Scheduling an OAuth credential revokes its tokens at the provider
    # Value: access the owner granted OpenFn is withdrawn at the provider, not only hidden in OpenFn.
    Given I own OAuth credential "Google Sheets" whose client has a revocation endpoint
    And it has environments "main" and "staging" with access and refresh tokens
    When I schedule "Google Sheets" for deletion
    Then the refresh and access tokens of each environment are sent to the revocation endpoint
    And a "token_revoked" audit event with success true is recorded for each environment
    # credentials.ex:904-907, :961-999, oauth_http_client.ex:31-60, audit.ex:104-113; credentials_test.exs:204-237 (two revocation calls, one environment)

  @S03 @pending
  Scenario: A provider that refuses revocation does not block the deletion
    # Value: an owner can always retire a credential, even when the provider is down.
    Given I own OAuth credential "Google Sheets" whose revocation endpoint returns an error
    When I schedule "Google Sheets" for deletion
    Then I see "Credential scheduled for deletion"
    And a "token_revoked" audit event with success false and the environment name is recorded
    # credentials.ex:1001-1023, :904-907; no test found

  @S04 @pending
  Scenario: The owner cancels from the credential list before the purge
    # Value: a credential deleted by mistake survives the purge once the owner acts on the email.
    Given I own credential "DHIS2 prod" which was scheduled for deletion yesterday
    When I follow the email's instructions and cancel its deletion on "/credentials" (shared-credential-index-component S05)
    Then "DHIS2 prod" is no longer scheduled for deletion
    And an "updated" audit event is recorded
    And after the purge runs on its scheduled date "DHIS2 prod" and its secrets still exist
    # credential_index_component.ex:353-377, credentials.ex:936-941, :703-733, :44-47; credentials_test.exs:307-328 (context only, no LiveView test clicks cancel)

  @S05 @pending
  Scenario: The purge deletes an unused credential after its grace period
    # Value: a retired secret is actually removed once the grace period ends.
    Given credential "Old token" was scheduled for deletion and its date has passed
    And no run step has used "Old token"
    When the purge runs
    Then "Old token" and its bodies no longer exist
    And a "deleted" audit event is recorded for "Old token"
    # credentials.ex:42-71, :842-849; credentials_test.exs:1124-1151 (deleted_count 1, record gone; audit not asserted)

  @S06 @pending
  Scenario: The purge scrubs but keeps a credential used in runs
    # Value: the secret is gone while run history still points at a real credential record.
    Given credential "DHIS2 prod" was scheduled for deletion and its date has passed
    And a run step used "DHIS2 prod"
    When the purge runs
    Then "DHIS2 prod" still exists
    And every one of its environment bodies is empty
    # credentials.ex:49-58, :74-83, :1088-1093; credentials_test.exs:1085-1098, :1115-1121

  @S07 @pending
  Scenario: The purge leaves credentials whose grace period has not ended
    # Value: the grace period promised in the email is honoured.
    Given credential "DHIS2 prod" is scheduled for deletion 3 days from now
    And credential "Active" is not scheduled for deletion
    When the purge runs
    Then both credentials and their secrets are unchanged
    # credentials.ex:44-47; credentials_test.exs:1077-1082, :1100-1113 (unscheduled case only; a future date is not tested)
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A credential used in runs is scrubbed but stays scheduled, and "Cancel deletion" is still offered; cancelling restores a credential whose bodies are all `{}` | `credentials.ex:49-58`, `:74-83`, `:936-941`; `credential_index_component.ex:459-490` | "Credential deletion canceled", then jobs given it fail for missing secrets | decide |
| Cancelling an OAuth credential's deletion does not undo the token revocation done at scheduling | `credentials.ex:904-907`, `:936-941` | the credential looks restored but runs fail authentication until the owner reauthorizes | decide |
| Edit (including re-sharing with projects) and Transfer stay available on a scheduled credential, and nothing clears `scheduled_deletion` when it is re-shared | `credential_index_component.html.heex:80-107`; `credentials.ex:44-47` | the owner re-shares it, jobs use it, then the 02:30 purge empties or deletes it without warning | fix |
| Under `purge-immediate` the credential is dated now and the email promises a scrub "after a few minutes", but no purge cron is registered (also credentials-index 6.1; owned here) | `credentials.ex:922-925`; `user_notifier.ex:154-162`; `bootstrap.ex:306-317` | secrets are never scrubbed; the credential stays scheduled until "Delete now" | decide |
| Body scrub ignores each update's result and always reports success, so a credential with run activity whose scrub failed keeps its secrets with no log | `credentials.ex:77-82`, `:50-53` | none; secrets the email said would be scrubbed are kept | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Scheduling writes no audit event of its own, and unsharing writes no `removed_from_project` events; only OAuth revocations are audited | `credentials.ex:889-920`, `:1036-1052` | decide |
| The purge's `deleted` audit is attributed to the credential owner as actor, though the code comment says the purge has no actor | `credentials.ex:60-65`, `:842-847`; `audit.ex:30-35` | decide |
| The email gives no date, ends "accessed by clicking opening the user menu", and says the record is kept until "audit trail activity" expires when it is run steps that keep it | `user_notifier.ex:226-246`; `credentials.ex:55-58` | fix |
| A failed email send is ignored; the transaction commits and the owner is not told | `credentials.ex:908-911`, `user_notifier.ex:49-60` | decide |
| The list shows no scheduled date or badge; only the menu items change | `credential_index_component.ex:459-490` | decide |
| Credentials kept for run activity are re-selected and re-scrubbed by every nightly purge | `credentials.ex:44-58` | preserve |
| A nil `purge_deleted_after_days` dates the deletion now (`|| 0`), though bootstrap defaults it to 7 | `credentials.ex:922-925`, `bootstrap.ex:277` | preserve |
| Cancelling does not restore project access or job assignments (credentials-index 6.2, not restated) | `credentials.ex:1036-1052` | preserve |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Purge runs once a day at 02:30 UTC, so secrets are scrubbed up to a day after the date the email implies | `bootstrap.ex:310-311` | yes, via the email's "after N days" | preserve |
| Purge job: queue `:background`, `max_attempts: 1`, so a crash waits for the next night | `credentials.ex:6-8` | no | preserve |
| Revocation HTTP calls (up to two per environment) run synchronously inside the scheduling transaction | `credentials.ex:904-907`, `oauth_http_client.ex:31-42` | yes, a slow confirm when the provider is slow | decide |

### 6.5 Things seen but not understood

- The user-account purge deletes the departing user's credentials with `{:ok, _} = Credentials.delete_credential(...)` and ignores `scheduled_deletion` and run activity; a credential used in a run would make that match fail (`accounts.ex:50-62`). Not followed further; it belongs to a user-deletion flow. (decide)
- No LiveView test clicks "Cancel deletion"; `credential_live_test.exs:175` only refutes its presence before scheduling. (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the project credential settings view, which renders the same component and modal, be a second entry in `surfaces`?
- After the purge scrubs a credential kept for run activity, should "Cancel deletion" still be offered (6.1)?
- Should cancelling an OAuth credential's deletion warn that it must be reauthorized (6.1)?
- Should editing or re-sharing a scheduled credential be blocked, or clear the schedule (6.1)?
- Under `purge-immediate`, should scheduling delete at once or should the purge still run (6.1)?

## Proposed flows

none

## Proposed shared

none

## Summary

- Scenarios: 7 (S01 to S07), all `@pending`.
- Section 6: 6.1 has 5, 6.2 has 8, 6.3 has 0, 6.4 has 3, 6.5 has 2.
- Flows: none proposed; references credentials-index S16 to S19.
- Shared: inherits shared-credential-index-component (S05 cancel, S06 forged actions).
- Unsure: S03 and the 6.1 rows are read from code, not run; project-settings-credentials can start this flow but has no annotation yet.
