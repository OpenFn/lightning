---
id: shared-credential-index-component
type: shared
title: Credential index component (credentials, OAuth clients, keychains)
status: not-started
owner:

trigger:
  old_route: rendered by /credentials and /projects/:project_id/settings#credentials
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - host page renders `Components.Credentials.credentials_index_live_component`

inherits: []

url_params: []

config_variants:
  default: {}

inventory:
  routes: []
  events:
    - CredentialIndexComponent#close_active_modal
    - CredentialIndexComponent#show_modal
    - CredentialIndexComponent#edit_oauth_client
    - CredentialIndexComponent#request_oauth_client_deletion
    - CredentialIndexComponent#delete_oauth_client
    - CredentialIndexComponent#edit_credential
    - CredentialIndexComponent#request_credential_deletion
    - CredentialIndexComponent#request_credential_transfer
    - CredentialIndexComponent#edit_keychain_credential
    - CredentialIndexComponent#request_keychain_credential_deletion
    - CredentialIndexComponent#delete_keychain_credential
    - CredentialIndexComponent#cancel_credential_deletion
  js_hooks: []
  policies:
    - Lightning.Policies.Users (:edit_credential, :delete_credential)
    - Lightning.Policies.Credentials (:create/edit/delete_keychain_credential)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - purge_deleted_after_days
  not_reachable_here: []

related:
  - lib/lightning_web/live/credential_live/credential_index_component.ex
  - lib/lightning_web/live/credential_live/credential_index_component.html.heex
  - lib/lightning_web/live/components/credentials.ex
flows: []
---

## 1. Purpose

The same list-and-modals component shows credentials in two places: a user's own credentials
page, and a project's credentials settings. It is the one place people see which secrets exist,
who owns them, and where they're used, and the entry point for creating, editing, transferring
and deleting them. The form modals it opens (credential, OAuth client, keychain, transfer,
delete) are behaviour of their own and are catalogued by the views that host this component.

## 2. What it does

- Anyone who can see the page sees the credentials, OAuth clients and, in a project, keychain credentials
- Owners open edit, delete and transfer for their own credentials and OAuth clients
- Owners cancel a scheduled credential deletion
- Project admins and owners create, edit and delete keychain credentials
- Anyone else who reaches one of these actions gets "You are not authorized to perform this action"

**Straightforwardness: 4 of 5.** A list with owner-only actions; the one thing to get your head around is that ordinary credentials follow who owns them while keychains follow project role.

### Most surprising behaviours

- **(3)** Project admins can't edit, delete or transfer a credential someone else shared into their project; only the person who owns it can, whatever their role. (S02)
- **(4)** Deleting a credential doesn't remove it straight away: it waits a configured number of days before it's purged, and its owner can cancel in the meantime. (S05, 4)
- **(4)** Any refused action closes whatever dialog was open, so the user loses what they were looking at along with seeing the error. (6.2)

## 3. Who can do what

Credentials and OAuth clients (`lib/lightning/policies/users.ex:42-44`): ownership, not project role.

| Action | Credential owner | Anyone else |
|--------|------------------|-------------|
| See the row | yes | yes, when it is shared with the project being viewed |
| Edit, delete, transfer, cancel deletion | yes | no |

Keychain credentials (`lib/lightning/policies/credentials.ex:54-63`, `:87-98`):

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See keychains | yes | yes | yes | yes | no | yes |
| Create, edit, delete keychain | no | no | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Keychain actions also require the project's MFA requirement to be met (`policies/credentials.ex:90-93`).
- Creating a project credential is gated by the host page's `can_create_project_credential` (`credential_index_component.ex:92`).

## 4. What it touches

**Reads**: `credentials`, `project_credentials`, `oauth_clients`, `project_oauth_clients`, `keychain_credentials`, `projects`

**Writes**: `oauth_clients` (delete), `keychain_credentials` (delete), `credentials` (clear `scheduled_deletion`)

**Immediate side effects**
- Audit events from the context functions it calls

**Deferred side effects**
- A credential scheduled for deletion is purged after `purge_deleted_after_days` (`lib/lightning/credentials.ex:46`, `:922-925`)

**External, non-transactional effects**
- none

**Depends on config**
- `purge_deleted_after_days`

**Product limits**
- none

## 5. Scenarios

```gherkin
Feature: Credential index
  In order to keep track of the secrets my workflows use
  As a user or project admin
  I want to see and manage credentials in one list

  @S01 @pending
  Scenario: Owner sees edit actions on their own credential
    # Value: people can maintain their own secrets.
    Given I own credential "DHIS2 prod"
    When I open the credential list
    Then I see edit, delete and transfer actions for "DHIS2 prod"
    # credential_index_component.html.heex:72

  @S02 @pending
  Scenario: Another member's credential has no edit actions
    # Value: shared secrets can be used but only changed by the person responsible for them.
    Given credential "DHIS2 prod" is owned by someone else and shared with project "Malawi HIV"
    When I open the project's credential list
    Then I see "DHIS2 prod"
    And I see no edit, delete or transfer actions for it
    # credential_index_component.html.heex:72, policies/users.ex:42-44

  @S03 @pending
  Scenario: Editor cannot manage keychains
    # Value: keychains can resolve many secrets at run time, so only project admins set them up.
    Given I am an editor on project "Malawi HIV" with keychain "By district"
    When I open the project's credential list
    Then I see "By district"
    And I see no edit or delete actions for it
    # credential_index_component.html.heex:134, policies/credentials.ex:92-93

  @S04 @pending
  Scenario: Admin deletes a keychain
    # Value: admins can retire a keychain that is no longer needed.
    Given I am an admin on project "Malawi HIV" with keychain "By district"
    When I delete keychain "By district" and confirm
    Then I see "Keychain credential deleted"
    And "By district" is no longer listed
    # credential_index_component.ex:319-346

  @S05 @pending
  Scenario: Owner cancels a scheduled credential deletion
    # Value: a credential deleted by mistake can be recovered before it is purged.
    Given I own credential "DHIS2 prod" which is scheduled for deletion
    When I cancel its deletion
    Then I see "Credential deletion canceled"
    # credential_index_component.ex:353-374, lib/lightning/credentials.ex:936-940

  @S06 @pending
  Scenario: A forged action from a non-owner is refused
    # Value: hiding a button is not the only thing protecting someone else's secret.
    Given credential "DHIS2 prod" is owned by someone else
    When I send "edit_credential" for "DHIS2 prod"
    Then I see "You are not authorized to perform this action"
    # credential_index_component.ex:224-238, :420-424
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `project_user` lookup has a TODO to reject a nil member; a non-member host would still load | `credential_index_component.ex:35` | none today, since host pages gate first | decide |
| OAuth client list is not refetched after deletion (TODO) | `credential_index_component.ex:202` | relies on the `push_patch` remount to refresh | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Global OAuth clients show "GLOBAL" in the projects column | `credential_index_component.ex:449-450` | preserve |
| Every refusal patches back to `return_to`, closing any open modal | `credential_index_component.ex:420-424` | preserve |
| A keychain delete refusal from the context is matched though the gate above makes it unreachable | `credential_index_component.ex:203-207` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Keychain events on `/credentials` | `credential_index_component.ex:272-346` | keychains load only when a `project` is assigned (`:68-77`) |

### 6.4 Performance and operational limits

none

### 6.5 Things seen but not understood

none

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

none
