---
id: admin-audit
type: view
title: Admin settings › Audit
status: not-started
owner:

trigger:
  old_route: /settings/audit
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - the session is admitted by shared-authenticated-session; the route sits in the `:settings` live_session, which mounts `InitAssigns` (`lib/lightning_web/router.ex:268`, `:278`)
    - the viewer is a superuser (`audit_live/index.ex:7`; gate owned by shared-admin-space S02, S03)
    - entered from the "Audit" item in the admin side menu (shared-admin-space S01)

inherits:
  - shared-admin-space                # gate (S02, S03), settings layout and side menu with "Audit" current (S01; `index.ex:16`, `:23`), demotion handoff (S06)
  - shared-authenticated-session      # login redirect, revoked sessions, TOTP and lockout gates, sidebar (S01 to S07, S11); S08 to S10 not on the settings layout
  - shared-flash-messages             # bottom toasts on the settings layout (S07); this view sets no flash of its own
  - shared-project-header             # no-project parts only: LayoutComponents.header at index.html.heex:3 (confirmation banner S13, S14), global picker (S04, S06, S08, S10 to S12), account menu (S18)
  - shared-local-datetime             # Occurred column, `Common.datetime` default format and tooltip (index.html.heex:21; common.ex:399-498); S01 to S05

url_params:
  - name: page
    set_by: admin-audit (pagination bar links, `pagination.ex:159-213` via `index.ex:17-22`)
    effect: which page of events is shown; Scrivener default 1 (`index.ex:34`, `auditing.ex:25`)
  - name: page_size
    set_by: nobody in the app; only a hand-edited URL
    effect: rows per page, default 10, capped at 100 (`repo.ex:6`); dropped again by the next pagination click (6.2)

config_variants:
  default: {}                         # read under this one; the page reads no config of its own
  require-email-verification: { lightning.require_email_verification: true }   # inherited only; shared-project-header S13, S14 and shared-authenticated-session S04 to S06

inventory:
  routes:
    - live /settings/audit  AuditLive.Index :index   # router.ex:278
  events: []                                         # no handle_event; the only interaction is pagination patches into handle_params (index.ex:26-35)
  js_hooks:
    - LocalTimeConverter    # via Common.datetime (common.ex:455); owned by shared-local-datetime
    - Copy                  # via Common.datetime (common.ex:466); owned by shared-local-datetime
    - Tooltip               # via Common.wrapper_tooltip (common.ex:448); owned by shared-local-datetime
  policies:
    - Lightning.Policies.Users :access_admin_space via LightningWeb.Hooks :ensure_admin (index.ex:7); owned by shared-admin-space
  workers: []
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - LightningWeb.Pagination.pagination_bar async_page and help_text branches (pagination.ex:108-118); Table.table passes neither (table.ex:111-119)
    - Table.table pagination_actions and footer slots (table.ex:86-87, :105-107, :116-118); this view fills neither
    - Table.th sortable branch (table.ex:177-230); no column here is sortable (index.html.heex:11-14)

related:
  # writers whose events this page lists (not exhaustive; see section 4)
  - admin-user-edit                   # user created / updated, incl. password_changed metadata the page does not show (6.1)
  - admin-users
  - admin-projects                    # project collaborator_added / role_changed / removed (admin-projects S10)
  - project-settings-collaborators
  - project-settings-security         # requires_mfa_updated, allow_support_access_updated
  - project-settings-data-storage     # history / dataclip retention period updated
  - project-settings-credentials
  - credentials-index
  - project-settings-webhook-security
  - project-settings-github-sync      # repo_connection_created / removed
  - project-settings-history-exports  # history_export requested
  - channels-index
  - dataclip-show                     # dataclip label_created / label_deleted
  - workflow-editor-canvas            # workflow snapshot_created, enabled, disabled
  - workflows-index                   # workflow enabled / disabled, marked_for_deletion
flows: []
---

## 1. Purpose

Superusers use the audit page to answer "who changed what, and when" across the whole instance:
credential and OAuth client changes, project membership and security settings, workflow state,
user accounts and service-account token use. Without it, an instance operator investigating a
leaked secret, an unexpected permission change or a disabled workflow would have to query the
database directly, and changes made by automation (GitHub sync, triggers, service accounts) would
be indistinguishable from changes made by people.

## 2. What it does

- Superusers see every audit event on the instance, newest first, with when it happened, the event name, who or what did it, and what it was done to
- Superusers see each event's recorded changes as field-by-field old and new values
- Superusers see which credential environments a credential event recorded, without the secret values
- Superusers can tell automated actors (GitHub, a trigger, a service account) from people, and still see who acted after that account or actor was deleted
- Superusers page through the full history ten events at a time

**Straightforwardness: 4 of 5.** A read-only list you understand at a glance; the surprises are about what it leaves out or shows by accident, not how it works.

### Most surprising behaviours

- **(2)** OAuth client IDs and secrets in the trail are only lightly encoded, not encrypted, so anyone reading the page can recover them, unlike webhook secrets on the same page. (6.1)
- **(3)** A password change shows up as a user "updated" event with "No changes", so it's effectively invisible. Token refreshes and failures, service account scopes and export filters also read as "No changes". (6.1, 4)
- **(3)** There is no filter or search, the subject is just a type and a short id with no name or link, and every event pill is green, so a failed token refresh or a removal looks like any other event. (6.1, 6.2)
- **(4)** Nothing is ever deleted, and every workflow save adds an event, so on a busy instance the trail grows without limit and is mostly workflow snapshots. (6.4)

## 3. Who can do what

| Action | Signed out | Regular user | Support user | Superuser |
|--------|-----------|--------------|--------------|-----------|
| See the audit page | no | no | no | yes |
| Page through events | no | no | no | yes |
| Filter, search, export or delete events | n/a | n/a | n/a | n/a (no such control) |

Sources: `audit_live/index.ex:7`; `policies/users.ex:19-21` (via shared-admin-space); `index.html.heex:1-56` (no controls besides pagination). Test: `test/lightning_web/live/audit_live_test.exs:12-22` (regular user is redirected to `/projects` with "Sorry, you don't have access to that.").

**Preconditions beyond role**
- All session gates of shared-authenticated-session apply first; a locked-out superuser cannot read the page and a confirmed one can (`test/lightning_web/live/confirmation_lockout_live_test.exs:24-31`, `:60-75`).
- Support access to projects gives no access here; the policy checks role only (shared-admin-space section 3).

## 4. What it touches

**Reads**: `audit_events` (all rows, every project and user, `auditing.ex:14-29`), left-joined to `users`, `triggers` and `project_repo_connections` on `actor_id` by `actor_type` (`auditing.ex:15-22`); a count of `audit_events` for the pagination total (Scrivener, `repo.ex:6`). Displayed data includes actor names and emails (`auditing.ex:77-81`) and, in user events, the before and after email, name, role, `disabled` and `support_user` of the subject user (`accounts/audit.ex:13`).

**Writes**: none

**Immediate side effects**
- none

**Deferred side effects**
- none

**External, non-transactional effects**
- none

**Depends on config**
- none (page size comes from `Lightning.Repo`, `repo.ex:6`)

**Product limits**
- 10 events per page by default; `page_size` in the URL is honoured up to 100 (`repo.ex:6`)

**Event types the page can show**

Every row in `audit_events` is listed whatever its event name; the page has no allow-list. The writers found, by subject (`item_type`):

| Subject | Events | Writer |
|---------|--------|--------|
| credential | created, updated, added_to_project, removed_from_project, deleted, transfered, token_refreshed, token_refresh_failed, token_revoked | `credentials/audit.ex:5-18` |
| oauth_client | created, updated, added_to_project, removed_from_project, deleted | `credentials/oauth_client_audit.ex:5-14` |
| project | allow_support_access_updated, collaborator_added, collaborator_removed, collaborator_role_changed, dataclip_retention_period_updated, history_retention_period_updated, requires_mfa_updated | `projects/audit.ex:5-16` |
| project | repo_connection_created, repo_connection_removed | `version_control/audit.ex:5-11`, `:20-56` |
| channel | created, updated, deleted, auth_method_added, auth_method_removed, auth_method_changed | `channels/audit.ex:9-19` |
| webhook_auth_method | created, updated, added_to_trigger, removed_from_trigger, deleted | `workflows/webhook_auth_method_audit.ex:5-14` |
| workflow | snapshot_created, enabled, disabled, deleted_by_provisioner, inserted_by_provisioner, updated_by_provisioner, marked_for_deletion | `workflows/audit.ex:5-16` |
| user | created, updated | `accounts/audit.ex:5-8` |
| service_account | token_issued | `service_account/audit.ex:5-15` |
| dataclip | label_created, label_deleted | `invocation/dataclip_audit.ex:5-8` |
| history_export | requested | `workorders/export_audit.ex:5-8`; written at `invocation.ex:1315-1321` |

**Writers the page cannot fully display.** The page renders `changes.before` and `changes.after` and, from `metadata`, only `credential_bodies` (`index.ex:80-99`). Everything else in `metadata` is never shown:
- user `updated` for a password change: `password_changed: true` with empty changes, shown as "No changes" (`accounts/audit.ex:29-44`; 6.1)
- credential `token_refreshed`, `token_refresh_failed`, `token_revoked`: client id, scopes, status, error, endpoint (`credentials/audit.ex:65-80`, `:80-120`), shown as "No changes"
- service_account `token_issued`: `scopes` and `service_account_id` (`service_account/audit.ex:13-15`); the id does appear as the actor identifier (`auditing.ex:31-39`), the scopes do not
- history_export `requested`: `search_params` (`invocation.ex:1315-1321`), shown as "No changes"
- credential `environments` list (`credentials/audit.ex:48-51`); the per-environment bodies are shown instead

## 5. Scenarios

```gherkin
Feature: Instance audit trail
  In order to find out who changed what across the instance
  As a superuser
  I want to read every audit event with its actor, subject and changes

  @S01 @pending
  Scenario: Audit events are listed newest first with actor and subject
    # Value: an operator investigating an incident can see the most recent changes first and who made each one.
    Given I am a superuser
    And "Amara Diallo" (amara@example.org) created credential "DHIS2 prod" yesterday
    And "Amara Diallo" deleted that credential today
    When I open "/settings/audit"
    Then the table has columns "Occurred", "Event", "Actor" and "Subject"
    And the first row has event "deleted" and the second has event "created"
    And both rows show actor "Amara Diallo" with "amara@example.org" beneath
    And both rows show subject "credential" with the first 8 characters of the credential id
    # auditing.ex:14-29 (order_by desc inserted_at), :77-81; index.html.heex:8-46
    # audit_live_test.exs:28-57 (asserts first name, email, short credential id, "created"; not the order)

  @S02 @pending
  Scenario: An event by a deleted user still identifies the actor
    # Value: the audit trail survives offboarding; changes made by someone who has since left can still be traced to their account id.
    Given "temp@example.org" deleted a credential
    And the account "temp@example.org" has since been deleted
    When I open "/settings/audit" as a superuser
    Then that row shows actor "(User deleted)"
    And beneath it the first 8 characters of the deleted user's id
    # auditing.ex:71-75; index.html.heex:28-35 (falls back to display_short_uuid(actor_id))
    # audit_live_test.exs:34-46, :59-62

  @S03 @pending
  Scenario: Changes are shown field by field with old and new values
    # Value: a reviewer sees exactly what an event changed, not just that something changed.
    Given a project's "history_retention_period" was changed from 30 to 7 days
    When I open "/settings/audit" as a superuser
    Then under the "history_retention_period_updated" row I see "history_retention_period" with "30" struck through, an arrow, and "7"
    # index.ex:60-78, :101-134 (old value line-through, hero-arrow-right, new value)
    # audit_live_test.exs:67-127 (diff/1 with before and after, string and atom keys)

  @S04 @pending
  Scenario: Fields only on one side of a change are still listed, in name order
    # Value: a field that was set for the first time or cleared is not silently missing from the record.
    Given an event whose changes have before "bar" and "foo", and after "bar", "baz" and "foo"
    When the event's changes are shown
    Then fields appear in the order "bar", "baz", "foo"
    And "baz" shows only its new value with no arrow
    And a field present only before shows its old value struck through with an arrow to an empty value
    # index.ex:64-72 (union of keys, sorted, uniq), :109-116 (arrow only when old != nil), :136-137
    # audit_live_test.exs:129-171 (before nil), :173-215 (before empty), :217-303 (after nil or empty), :305-451 (extra keys, arrow count 2), :453-493 (alphabetical)

  @S05 @pending
  Scenario: A created event shows only the new values
    # Value: a creation reads as a creation, not as a change from blank values.
    Given user "amara@example.org" was created by a superuser
    When I open "/settings/audit" as a superuser
    Then under the user "created" row each recorded field shows its value with no arrow and nothing struck through
    # accounts/audit.ex:17-19 (after only); auditing/audit.ex:252-256 (before nil for "created" changesets); index.ex:109-116

  @S06 @pending
  Scenario: Credential environment bodies are shown as encrypted values only
    # Value: a superuser can see which environments a credential change touched without the credential's secrets being shown on screen.
    Given credential "DHIS2" was updated with environments "production" and "staging" and a body containing "s3cret-token"
    When I open "/settings/audit" as a superuser
    Then under that credential's "updated" row I see "body:production" and "body:staging", in that order, each followed by an encoded value
    And I do not see "s3cret-token"
    # credentials/audit.ex:30-57 (Encrypted.Map.dump then Base64); index.ex:80-99 (strip "body:", sort by name), :122-131
    # not covered by audit_live_test.exs (every diff/1 test passes metadata %{})

  @S07 @pending
  Scenario: Webhook auth method secrets are shown encrypted
    # Value: reading the audit trail does not reveal webhook passwords or API keys.
    Given a webhook auth method with password "hunter22" and API key "k-123" was created
    When I open "/settings/audit" as a superuser
    Then the "webhook_auth_method" "created" row lists "password" and "api_key"
    And I do not see "hunter22" or "k-123"
    # workflows/webhook_auth_method_audit.ex:16-26 (Encrypted.Binary.dump then Base64 for username, password, api_key)

  @S08 @pending
  Scenario Outline: Automated actors are labelled as the system that acted
    # Value: changes made by GitHub sync, a trigger or a service account are not mistaken for a person's, and stay attributable after the actor is removed.
    Given an audit event whose actor is <actor>
    When I open "/settings/audit" as a superuser
    Then the actor column shows "<label>"

    Examples:
      | actor                                 | label                              |
      | an existing GitHub repo connection    | GitHub                             |
      | a deleted GitHub repo connection      | (Project Repo Connection Deleted)  |
      | an existing cron trigger              | Cron                               |
      | an existing webhook trigger           | Webhook                            |
      | a deleted trigger                     | (Trigger Deleted)                  |
      | a service account                     | Service account                    |
    # auditing.ex:31-39 (service account label, identifier from metadata["service_account_id"]), :45-69; trigger types trigger.ex:27, :66
    # auditing/audit.ex:308-318 (service account keeps its key id in metadata because no table holds it)

  @S09 @pending
  Scenario: The history is paged ten events at a time
    # Value: the full instance history stays browsable on a busy instance without loading every event at once.
    Given there are 25 audit events
    When I open "/settings/audit" as a superuser
    Then I see 10 events and "Showing 1 to 10 of 25 total results"
    When I click page "3"
    Then the URL has "page=3"
    And I see 5 events and "Showing 21 to 25 of 25 total results"
    # repo.ex:6 (page_size 10, max 100); auditing.ex:25; index.ex:17-22, :26-35; table.ex:109-121; pagination.ex:103-156, :159-213
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A password change is recorded as a user "updated" event with empty before and after and `password_changed: true` in metadata, but the page never reads that metadata | `accounts/audit.ex:29-44`; `index.ex:48-58` | a "updated" row on the user with "No changes", so a password change by an admin or the user is invisible in the trail | fix |
| OAuth client `client_id` and `client_secret` in audit changes are only Base64-encoded, not encrypted (the column itself is a plain string, `oauth_client.ex:23-24`); webhook auth method secrets in the same table are encrypted first | `credentials/oauth_client_audit.ex:16-28`; `oauth_clients.ex:211-219`; rendered by `index.ex:101-134` | the OAuth client secret, before and after, on screen in a form anyone can decode | fix |
| Every event pill is green, including `token_refresh_failed`, `deleted`, `collaborator_removed`, `disabled` and `auth_method_removed` | `index.html.heex:24` | a failure or removal looks the same as a success at a glance | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| No filtering or search of any kind; `list_all(params)` passes the URL params straight to Scrivener, which reads only `page` and `page_size` | `auditing.ex:14-29`; `index.ex:34` | decide |
| Events with no change details (credential deleted, token events, provisioner events, export requested, channel deleted) show "No changes" | `index.ex:37-58`, `:139-145`; `audit_live_test.exs:57`, `:495-519` | preserve |
| Ordering is by `inserted_at` only, stored at second precision; events written in the same transaction (a credential `created` and its `added_to_project`) have no stable relative order | `auditing.ex:23`; `schema.ex:14` (`:utc_datetime`) | decide |
| Subject shows only the item type and an 8-character id, with no name and no link; two subjects share the type "project" (`projects/audit.ex:7`, `version_control/audit.ex:7`) | `index.html.heex:39-46` | decide |
| Subject type is computed with `String.split(".") |> Enum.at(-1)`, which does nothing for the plain strings every writer uses | `index.html.heex:41` | preserve |
| `actor_display` is declared a virtual `:string` but holds a map | `auditing/audit.ex:132`; `auditing.ex:31-43` | preserve |
| A `page_size` in the URL is lost on the next pagination click, because page links call the path function with `page:` only | `pagination.ex:164`, `:177`, `:213`; `index.ex:17-22` | preserve |
| The page does not subscribe to anything; new events appear only after a reload or a pagination patch re-runs the query | `index.ex:11-35` | decide |
| Each event takes two table rows (summary, then a full-width changes row), even for "No changes" | `index.html.heex:19-51`; `index.ex:103`, `:141` | preserve |
| Credential environment bodies are shown as Base64 of the Cloak ciphertext; the values are useless on screen but put every credential body's ciphertext in the page HTML | `credentials/audit.ex:54-57`; `index.ex:122-131` | decide |
| Values are rendered as-is; maps would not render, but every writer found stores scalars (ids, strings, numbers, booleans, timestamps) | `index.ex:136-137`; `projects/audit.ex:87-89`; `channels/audit.ex:160-189` | preserve |
| The `actor_type` column was added with default `"user"`; rows written before it by a non-user actor would read as "(User deleted)" | `priv/repo/migrations/20241022125816_add_actor_type_to_audit_events.exs`; `auditing.ex:71-75` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `pagination_bar` async_page and help_text branches | `pagination.ex:108-118` | `Table.table` never passes them (`table.ex:111-119`) |
| `Table.th` sorting | `table.ex:177-230` | no column on this page sets `sortable` (`index.html.heex:11-14`) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Page size 10, max 100 | `repo.ex:6` | yes, pagination bar | preserve |
| No index on `audit_events.inserted_at` (only the primary key and `item_id`); every page sorts the whole table and Scrivener also counts it, joining three tables | `priv/repo/migrations/20230916052400_change_credentials_audit_to_audit_events.exs:5-6`; `auditing.ex:15-25` | yes on large instances, slow page loads | decide |
| No retention for `audit_events`: nothing deletes rows except the dev reset helper; workflow `snapshot_created` is written on every save | `setup_utils.ex:803`; `workflows.ex:730`; `provisioner.ex:493` | yes, history grows without bound and is dominated by snapshot events | decide |

### 6.5 Things seen but not understood

- `item_id` is not required (`auditing/audit.ex:161`) and the Subject cell calls `display_short_uuid(item_id)`, which would raise on nil (`live_helpers.ex:168-171`, `index.html.heex:44`). No writer found passes a nil item id, so it is unclear whether this can happen.
- Users created without an actor (self-registration) are not audited (`accounts.ex:162-165`); it is not clear whether that gap is intended.
- Whether `false` renders as "false" in the changes list (workflow `enabled` before and after, `workflows.ex:752-757`) was not verified without running the app.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should OAuth client secrets in audit events be encrypted like webhook auth method secrets, or dropped from the record, and should existing Base64 rows be rewritten (6.1)? (owner: security)
- Should credential body ciphertext appear in the page at all, or should the page list only the environment names (6.2)? (owner: security)
- Should the rebuild show audit metadata (password changed, token scopes, refresh errors, export filters) so those events are not "No changes" (6.1, section 4)? (owner: product)
- Does the audit page need filters (by subject, actor, event, project, date) and links to the subject, given it is the only instance-wide trail (6.2)? (owner: product)
- Should audit events have a retention policy, and should `snapshot_created` stay in the trail (6.4)? (owner: product)
- Should event pills be coloured by kind, for example failures and removals (6.1)? (owner: product)

## Proposed flows

none. The page writes nothing, so no change made here shows up elsewhere. Events written on other views arrive here by a later page load, not a broadcast; each writing view or flow owns that assertion (for example admin-projects S10). Demotion while the page is open is inherited from shared-admin-space S06 (flow-account-revocation-teardown).

## Proposed shared

- **shared-pagination-bar**: `Table.table` with `page` and `url`, rendering `LightningWeb.Pagination.pagination_bar` ("Showing X to Y of Z total results", "No results found", first, previous, numbered, ellipsis, next and last links that patch `page=`) over a Scrivener page with default size 10 and max 100 (`table.ex:94-124`, `pagination.ex:35-213`, `repo.ex:6`). Surfaces: admin-audit (`index.html.heex:8`), history-channel-logs (`run_live/channel_logs_component.ex`), history-work-orders (`run_live/index.html.heex`).

## Lead resolution (batch 10)

- `shared-pagination-bar` declined, for the same reason as the sortable header and filter chip.
