---
id: flow-credential-scheduled-deletion
type: flow
title: Schedule a credential for deletion, then cancel or purge
owner:

trigger:
  entry: credentials-index # project credential settings render the same component and modal, so they can start it too (see 8)
  exit: credentials-index
  surfaces:
    - credentials-index
    - email:credential-deletion-scheduled
    - capability:credentials-purge-deleted
    - credentials-index
    - project-settings-credentials # second entry
  reachable_when:
    - credentials-index:
        the signed-in user owns the credential
        (`credential_index_component.html.heex:72`,
        `policies/credentials.ex:76-147`)

inherits:
  - shared-credential-index-component # S05 owns the cancel click and its flash; S06 owns refusal of events sent outside the page

url_params: []

config_variants:
  default: { purge_deleted_after_days: 7 } # read under this variant (bootstrap.ex:273-278)

inventory:
  routes: [] # /credentials is owned by credentials-index
  events:
    - CredentialDeletionModal#delete # scheduling branch only; "Delete now" belongs to credentials-index S17, S18
    - CredentialIndexComponent#cancel_credential_deletion # owned by shared-credential-index-component S05
  js_hooks: []
  policies:
    - Lightning.Policies.Credentials (:delete_credential), via
      Credentials.authorize_credential/3 (credentials.ex:1154-1155;
      policies/credentials.ex:76-147)
  workers:
    - Lightning.Credentials (Oban, queue :background, max_attempts 1, args type
      purge_deleted; cron 02:30) # credentials.ex:6-8, :42-71; bootstrap.ex:310-311
  api_endpoints: []
  emails:
    - email:credential-deletion-scheduled # UserNotifier.send_credential_deletion_notification_email/2, user_notifier.ex:226-246
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

A credential owner retires a secret they no longer want used. Scheduling cuts it
off from every project and job at once, withdraws OpenFn's OAuth access at the
provider where the client supports revocation, and tells the owner by email how
to undo it; a daily purge later scrubs the secret and removes the record.
Without this a retired secret would keep running jobs or sit in the database
indefinitely, and a mistaken deletion would have no window in which to recover
it.

## 2. What it does

1. The owner deletes a credential from their credentials list (or a project's
   credential settings) and confirms.
   - It is unshared from every project at once, and every job using it loses it
   - For an OAuth credential, OpenFn's access is withdrawn at the provider; if
     the provider refuses, the deletion still goes ahead
2. The owner gets an email saying the credential is disconnected, its secrets
   will be scrubbed after the grace period (7 days by default), and how to
   cancel.
3. During the grace period the owner can pick "Cancel deletion" from the
   credential's menu in the list.
4. After the grace period, a nightly cleanup scrubs the secrets of every
   credential past its date.
   - Credentials never used in a run are then deleted outright
   - Credentials used in a run are kept, empty, so run history still points at
     them

**Straightforwardness: 3 of 5.** The happy path is simple, but "cancel" restores
far less than the word suggests, and a scheduled credential can quietly be put
back into use before the cleanup destroys it.

### Most surprising behaviours

- **(2)** For a credential that was used in runs, "Cancel deletion" is still
  offered after the cleanup has emptied it, so the owner gets back a credential
  with no secrets and jobs fail. (6.1)
- **(3)** Cancelling only clears the date: the credential stays unshared from
  every project and off every job, and an OAuth credential stays revoked at the
  provider until the owner reauthorizes it. (6.1, 6.2)

## 3. Who can do what

Ownership, not project role (`policies/credentials.ex:76-147`,
`credentials.ex:1154-1155`).

| Action                                      | Credential owner | Anyone else | System (purge job)               |
| ------------------------------------------- | ---------------- | ----------- | -------------------------------- |
| Schedule deletion                           | yes              | no          | n/a                              |
| Receive the scheduled-deletion email        | yes              | no          | n/a                              |
| Cancel a scheduled deletion                 | yes              | no          | n/a                              |
| Scrub secrets of a credential past its date | n/a              | n/a         | yes                              |
| Delete a credential past its date           | n/a              | n/a         | yes, only if no run step used it |

**Preconditions beyond role**

- The purge only touches credentials whose `scheduled_deletion` has passed
  (`credentials.ex:44-47`).
- A credential referenced by any `steps.credential_id` is scrubbed but never
  deleted (`credentials.ex:55-58`, `:1088-1093`); the FK has
  `on_delete: :nothing`
  (`priv/repo/migrations/20230419234837_add_credential_id_to_runs.exs:6`).
- The purge cron exists only when `purge_deleted_after_days > 0`
  (`bootstrap.ex:306-317`).

## 4. What it touches

**Reads**: `credentials`, `credential_bodies`, `project_credentials`, `jobs`,
`oauth_clients`, `users`, `steps`

**Writes**

- Hop 1, schedule (one transaction, `credentials.ex:889-920`):
  `credentials.scheduled_deletion = now + purge_deleted_after_days`
  (`:922-925`); `jobs.project_credential_id = null` for every job using it; all
  its `project_credentials` deleted (`:1036-1052`); one `token_revoked` audit
  row per environment for OAuth credentials whose client has a revocation
  endpoint (`:961-1034`, `audit.ex:104-113`)
- Hop 3, cancel: `credentials.scheduled_deletion = null` plus an `updated` audit
  row, through the ordinary update path (`credentials.ex:936-941`, `:262-290`,
  `:703-733`)
- Hop 4, purge: every body of each due credential set to `{}`
  (`credentials.ex:74-83`); credentials with no step activity deleted with a
  `deleted` audit row, bodies cascading (`:60-68`, `:842-849`,
  `priv/repo/migrations/20250926003931_create_credential_bodies.exs:8`)

**Immediate side effects** (in the same request)

- Hop 1: flash "Credential scheduled for deletion" and navigate back to the list
  (`credential_deletion_modal.ex:44`); the row's menu now shows "Cancel
  deletion" and "Delete now" (`credential_index_component.ex:459-490`)
- Hop 2: email "Your "<name>" credential will be deleted" to the owner, sent
  from inside the transaction (`credentials.ex:908-911`, `:1054-1059`,
  `user_notifier.ex:226-246`)
- Hop 3: flash "Credential deletion canceled" (shared-credential-index-component
  S05)

**Deferred side effects** (later, elsewhere)

- Daily at 02:30 the purge job runs (`bootstrap.ex:310-311`,
  `credentials.ex:42-71`)

**External, non-transactional effects**

- Token revocation HTTP calls to the OAuth client's revocation endpoint, refresh
  token then access token, per environment, inside the transaction
  (`credentials.ex:904-907`, `oauth_http_client.ex:31-60`); a later rollback
  leaves tokens revoked
- The email leaves from inside the transaction; a later rollback leaves the
  owner told about a deletion that did not happen (`credentials.ex:908-911`)

**Depends on config**

- `purge_deleted_after_days`: the scheduled date, the grace period in the email
  (`user_notifier.ex:154-162`), and whether the purge runs at all

**Product limits**

- A scheduled credential keeps its secrets for `purge_deleted_after_days`
  (default 7), stated in the email

## 5. Scenarios

Verified against `default` unless tagged. Single-surface steps owned elsewhere
are not restated: the schedule click and its in-page result (credentials-index
S16), "Delete now" (credentials-index S17, S18), the refusal of a changed id
(credentials-index S19), the cancel click (shared-credential-index-component
S05) and events sent outside the page (shared-credential-index-component S06).

```gherkin
Feature: Scheduled credential deletion
  In order to retire a secret without losing it to a single mistaken click
  As a credential owner
  I want a deletion that takes effect at once, tells me how to undo it, and completes on its own

  @S01
  Scenario: Scheduling cuts the credential off and emails the owner how to undo it
    # Value: the owner has a record of the deletion and knows how and until when it can be reversed.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV" and used by a job there
    When I delete "DHIS2 prod" on "/credentials" and confirm
    Then "DHIS2 prod" is scheduled for deletion 7 days from now
    And "DHIS2 prod" is no longer shared with any project and the job has no credential
    And I receive an email "Your \"DHIS2 prod\" credential will be deleted"
    And the email says the credential has been disconnected from all projects, its secrets will be scrubbed after 7 days, and the deletion can be cancelled from the "Credentials" menu
    # credential_deletion_modal.ex:40-44, credentials.ex:889-925, :1036-1059, user_notifier.ex:154-162, :226-246
    # credentials_test.exs:150-201 (date, unshare, job, subject and recipient; body copy not asserted)

  @S02
  Scenario: Scheduling an OAuth credential revokes its tokens at the provider
    # Value: access the owner granted OpenFn is withdrawn at the provider, not only hidden in OpenFn.
    Given I own OAuth credential "Google Sheets" whose client has a revocation endpoint
    And it has environments "main" and "staging" with access and refresh tokens
    When I schedule "Google Sheets" for deletion
    Then the refresh and access tokens of each environment are sent to the revocation endpoint
    And a "token_revoked" audit event with success true is recorded for each environment
    # credentials.ex:904-907, :961-999, oauth_http_client.ex:31-60, audit.ex:104-113; credentials_test.exs:204-237 (two revocation calls, one environment)

  @S03
  Scenario: A provider that refuses revocation does not block the deletion
    # Value: an owner can always retire a credential, even when the provider is down.
    Given I own OAuth credential "Google Sheets" whose revocation endpoint returns an error
    When I schedule "Google Sheets" for deletion
    Then I see "Credential scheduled for deletion"
    And a "token_revoked" audit event with success false and the environment name is recorded
    # credentials.ex:1001-1023, :904-907; no test found

  @S04
  Scenario: The owner cancels from the credential list before the purge
    # Value: a credential deleted by mistake survives the purge once the owner acts on the email.
    Given I own credential "DHIS2 prod" which was scheduled for deletion yesterday
    When I follow the email's instructions and cancel its deletion on "/credentials" (shared-credential-index-component S05)
    Then "DHIS2 prod" is no longer scheduled for deletion
    And an "updated" audit event is recorded
    And after the purge runs on its scheduled date "DHIS2 prod" and its secrets still exist
    # credential_index_component.ex:353-377, credentials.ex:936-941, :703-733, :44-47; credentials_test.exs:307-328 (context only, no LiveView test clicks cancel)

  @S05
  Scenario: The purge deletes an unused credential after its grace period
    # Value: a retired secret is actually removed once the grace period ends.
    Given credential "Old token" was scheduled for deletion and its date has passed
    And no run step has used "Old token"
    When the purge runs
    Then "Old token" and its bodies no longer exist
    And a "deleted" audit event is recorded for "Old token"
    # credentials.ex:42-71, :842-849; credentials_test.exs:1124-1151 (deleted_count 1, record gone; audit not asserted)

  @S06
  Scenario: The purge scrubs but keeps a credential used in runs
    # Value: the secret is gone while run history still points at a real credential record.
    Given credential "DHIS2 prod" was scheduled for deletion and its date has passed
    And a run step used "DHIS2 prod"
    When the purge runs
    Then "DHIS2 prod" still exists
    And every one of its environment bodies is empty
    # credentials.ex:49-58, :74-83, :1088-1093; credentials_test.exs:1085-1098, :1115-1121

  @S07
  Scenario: The purge leaves credentials whose grace period has not ended
    # Value: the grace period promised in the email is honoured.
    Given credential "DHIS2 prod" is scheduled for deletion 3 days from now
    And credential "Active" is not scheduled for deletion
    When the purge runs
    Then both credentials and their secrets are unchanged
    # credentials.ex:44-47; credentials_test.exs:1077-1082, :1100-1113 (unscheduled case only; a future date is not tested)

  @S08
  Scenario: Scheduling a credential that is already scheduled leaves its date and secrets alone
    # Value: a second confirmation, from a stale list or another tab, can't push the deletion date back or repeat the owner's email and the provider revocation.
    Given credential "DHIS2 prod" is already scheduled for deletion
    When its owner confirms "Delete credential" again from a page that still showed it as live
    Then the owner sees "This credential is already scheduled for deletion"
    And the deletion date is unchanged
    And no second email is sent and no tokens are revoked again
    # credential_deletion_modal.ex:46-72; credentials.ex:1088-1092, :1161-1169; policies/credentials.ex:106-114
    # not driven through the page; read from code (credentials_test.exs covers the context refusal)
```

## 6. Unclear value

### 6.1 Possible bugs

| What                                                                                                                                                          | Where                                                                                 | What a user sees                                                                        | Disposition |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ----------- |
| A credential used in runs is scrubbed but stays scheduled, and "Cancel deletion" is still offered; cancelling restores a credential whose bodies are all `{}` | `credentials.ex:49-58`, `:74-83`, `:936-941`; `credential_index_component.ex:459-490` | "Credential deletion canceled", then jobs given it fail for missing secrets             | decide      |
| Cancelling an OAuth credential's deletion does not undo the token revocation done at scheduling                                                               | `credentials.ex:904-907`, `:936-941`                                                  | the credential looks restored but runs fail authentication until the owner reauthorizes | decide      |

### 6.2 Quirks and implementation details

| What                                                                                                                                                                           | Where                                                | Disposition                            |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- | -------------------------------------- | -------------------------------------------- | -------- |
| The purge's `deleted` audit is attributed to the credential owner as actor, though the code comment says the purge has no actor                                                | `credentials.ex:60-65`, `:842-847`; `audit.ex:30-35` | decide                                 |
| The email gives no date, ends "accessed by clicking opening the user menu", and says the record is kept until "audit trail activity" expires when it is run steps that keep it | `user_notifier.ex:226-246`; `credentials.ex:55-58`   | fix                                    |
| A failed email send is ignored; the transaction commits and the owner is not told                                                                                              | `credentials.ex:908-911`, `user_notifier.ex:49-60`   | decide                                 |
| The list shows no scheduled date or badge; only the menu items change                                                                                                          | `credential_index_component.ex:459-490`              | decide                                 |
| Credentials kept for run activity are re-selected and re-scrubbed by every nightly purge                                                                                       | `credentials.ex:44-58`                               | preserve                               |
| A nil `purge_deleted_after_days` dates the deletion now (`                                                                                                                     |                                                      | 0`), though bootstrap defaults it to 7 | `credentials.ex:922-925`, `bootstrap.ex:277` | preserve |
| Cancelling does not restore project access or job assignments (credentials-index 6.2, not restated)                                                                            | `credentials.ex:1036-1052`                           | preserve                               |

### 6.3 Unreachable or dead code

none

### 6.4 Performance and operational limits

| What                                                                                                  | Where                                                  | User-visible?                                 | Disposition |
| ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------------------- | ----------- |
| Purge job: queue `:background`, `max_attempts: 1`, so a crash waits for the next night                | `credentials.ex:6-8`                                   | no                                            | preserve    |
| Revocation HTTP calls (up to two per environment) run synchronously inside the scheduling transaction | `credentials.ex:904-907`, `oauth_http_client.ex:31-42` | yes, a slow confirm when the provider is slow | decide      |

### 6.5 Things seen but not understood

- The user-account purge's handling of the departing user's credentials was not
  followed; it belongs to a user-deletion flow. (decide)
- No LiveView test clicks "Cancel deletion"; `credential_live_test.exs:175` only
  refutes its presence before scheduling. (preserve)

## 7. Not migrating

| Item | Reason | Decided by | Date |
| ---- | ------ | ---------- | ---- |

## 8. Open questions

- Should the project credential settings view, which renders the same component
  and modal, be a second entry in `surfaces`?
- After the purge scrubs a credential kept for run activity, should "Cancel
  deletion" still be offered (6.1)?
- Should cancelling an OAuth credential's deletion warn that it must be
  reauthorized (6.1)?

## Proposed flows

none

## Proposed shared

none
