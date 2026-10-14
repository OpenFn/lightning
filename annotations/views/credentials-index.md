---
id: credentials-index
type: view
title: Credentials (user)
status: not-started
owner:

trigger:
  old_route: /credentials
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - signed in (scope `pipe_through [:browser, :require_authenticated_user]`, router.ex:189-190; `live_session :default` with `InitAssigns`, router.ex:288, init_assigns.ex:17-35)
    - account not locked out pending email confirmation (init_assigns.ex:26-30)
    - no project, role or MFA gate; any signed-in user reaches it (index.ex:1-37 has no further on_mount beyond `:assign_projects`, index.ex:7)

inherits:
  - shared-credential-index-component    # the three tables, row action menus, OAuth client delete, cancel scheduled deletion, keychain handling (not reachable here)
  - shared-authenticated-session
  - shared-flash-messages   # added by lead (final pass)

url_params: []                           # live_action :index only (router.ex:322, index.ex:24-27); no params read

config_variants:
  default: { allow_credential_transfer: false, purge_deleted_after_days: 7, max_credential_sensitive_values: 50, book_demo_banner.enabled: false }   # read under this variant (config/config.exs:198, bootstrap.ex:273-278, config.ex:373-375, config.ex:268-269)
  transfer-in-form: { allow_credential_transfer: true }   # the test build (config/test.exs:158); adds a "Transfer ownership" section to the edit form (credential_form_component.ex:1022-1035)
  purge-immediate: { purge_deleted_after_days: 0 }        # bootstrap.ex:306-317, credentials.ex:922-925, user_notifier.ex:154-162
  superuser: { current_user.role: superuser }             # OAuth client "global" checkbox (credential_index_component.html.heex:175, :188; oauth_client_form_component.ex:513)
  support-user: { current_user.support_user: true }       # project picker also lists support-access projects (projects.ex:1160-1170)

inventory:
  routes:
    - live /credentials  CredentialLive.Index :index (live_session :default; router.ex:288, :322)
  events:
    - CredentialLive.Index handle_info {:forward, mod, opts}          # index.ex:32-36; OAuth callback re-entry, see flow-oauth-credential-authorize
    - CredentialFormComponent#validate
    - CredentialFormComponent#schema_selected
    - CredentialFormComponent#retry_schema
    - CredentialFormComponent#retry_adaptors
    - CredentialFormComponent#change_page
    - CredentialFormComponent#change_tab
    - CredentialFormComponent#add_environment
    - CredentialFormComponent#update_environment_name
    - CredentialFormComponent#delete_environment
    - CredentialFormComponent#add_selected_project
    - CredentialFormComponent#remove_selected_project
    - CredentialFormComponent#save
    - GenericOauthComponent#authorize_click
    - GenericOauthComponent#check_scope
    - OauthClientFormComponent#validate
    - OauthClientFormComponent#remove_mandatory_scope
    - OauthClientFormComponent#remove_optional_scope
    - OauthClientFormComponent#add_selected_project
    - OauthClientFormComponent#remove_selected_project
    - OauthClientFormComponent#save
    - TransferCredentialModal#validate
    - TransferCredentialModal#check-user-access
    - TransferCredentialModal#transfer-credential
    - TransferCredentialModal#revoke-transfer
    - CredentialDeletionModal#delete
  js_hooks:
    - OpenAuthorizeUrl (hooks/index.ts:378-384; generic_oauth_component.ex:469) opens the provider in a window named oauth_authorization
    - ClearInput (hooks/index.ts:514-520; oauth_client_form_component.ex:578)
    - Tooltip on the add environment button (credential_form_component.ex:892-901)
    - ModalHook close_modal (hooks/index.ts:522-530) via the shared credential_modal
    - data-confirm on "Delete environment" (credential_form_component.ex:991) and on removing a project in use (components/credentials.ex:194)
  policies:
    - Lightning.Policies.Users (:edit_credential, :delete_credential), owner only (policies/users.ex:40-44)
    - Lightning.Credentials authorize_credential_owner/2 (credentials.ex:948-959) on create, update, schedule, delete, cancel
    - Lightning.OauthClients authorize_client_owner/2 (oauth_clients.ex:304-315) on create, update, delete
    - Credentials.initiate_credential_transfer/3 and revoke_transfer/2 owner checks (credentials.ex:1577-1581, :1742)
  workers:
    - Lightning.Credentials (Oban, type purge_deleted), deferred effect of scheduling deletion (credentials.ex:42-71; cron bootstrap.ex:310-311)
  api_endpoints: []
  emails:
    - email:credential-deletion-scheduled   # UserNotifier.send_credential_deletion_notification_email/2, user_notifier.ex:226-246
    - email:credential-transfer-confirmation   # UserNotifier.deliver_credential_transfer_confirmation_instructions/4, user_notifier.ex:469-497
  config:
    - :lightning, LightningWeb, allow_credential_transfer
    - purge_deleted_after_days (PURGE_DELETED_AFTER_DAYS)
    - max_credential_sensitive_values
    - credential_transfer_token_validity_in_days (copy in the confirmation email only)
    - adaptor catalogue availability (Lightning.Adaptors.packages/0, resolve_name/1, schema/1)
  not_reachable_here:
    - CredentialFormComponent#show_advanced_picker, #select_credential_type_option, #continue_from_advanced_picker, #cancel_advanced_picker, #back_to_advanced_picker_from_second, #back_to_advanced_picker_from_keychain, #validate_keychain, #save_keychain (credential_form_component.ex:312-485); the "Advanced" button and keychain page render only when `from_collab_editor` is true (:1038, :1181-1204), which this host never sets
    - CredentialFormComponent#api_version and #select_project (credential_form_component.ex:146-148, :487-493); no element emits them
    - OauthClientFormComponent#edit_mandatory_scope, #edit_optional_scope, #select_project (oauth_client_form_component.ex:148-165); see 6.3
    - KeychainCredentialFormComponent (all events); keychains load only with a project (credential_index_component.ex:68-77)
    - Lightning.Credentials.create_keychain_credential/3 and keychain policies

related:
  - lib/lightning_web/live/credential_live/index.ex
  - lib/lightning_web/live/credential_live/index.html.heex
  - lib/lightning_web/live/credential_live/credential_form_component.ex
  - lib/lightning_web/live/credential_live/generic_oauth_component.ex
  - lib/lightning_web/live/credential_live/json_schema_body_component.ex
  - lib/lightning_web/live/credential_live/raw_body_component.ex
  - lib/lightning_web/live/credential_live/oauth_client_form_component.ex
  - lib/lightning_web/live/credential_live/transfer_credential_modal.ex
  - lib/lightning_web/live/credential_live/helpers.ex
  - lib/lightning_web/live/components/credential_deletion_modal.ex
  - lib/lightning_web/live/components/credentials.ex
  - lib/lightning_web/live/components/oauth.ex
  - lib/lightning/credentials.ex
  - lib/lightning/credentials/credential.ex
  - lib/lightning/oauth_clients.ex
  - lib/lightning/credentials/oauth_client.ex
  - test/lightning_web/live/credential_live_test.exs
  - test/lightning_web/live/oauth_clients_live_test.exs
flows:
  - flow-credential-transfer
  - flow-oauth-credential-authorize
  - flow-credential-scheduled-deletion
  - flow-editor-credentials-broadcast
---

## 1. Purpose

Every signed-in user's own credentials page: the place they create, rotate, share, hand over and
retire the secrets and OAuth apps their workflows use, independently of any one project. It is the
main home of the credential form, OAuth client form, transfer and delete modals that the shared
credential list opens (project settings and the workflow editor reuse them). Getting it wrong
either leaves jobs running against stale or missing secrets, or lets a secret reach a project or a
person it was never meant for.

## 2. What it does

- Any signed-in user sees the credentials they own and the OAuth clients they own or that are global
- Owners create a credential from an adaptor schema or raw JSON
- Owners create OAuth credentials against their own or a global OAuth client by signing in to the provider
- Owners keep separate values per environment, up to five
- Owners edit a credential's name, values and environments
- Owners share a credential with projects they belong to, and it follows into those projects' sandboxes
- Owners remove project access, with a warning when workflows use it
- Owners schedule a credential for deletion, and delete a scheduled one for good if no runs used it
- Owners start a transfer of a credential to another user, and revoke a pending one
- Users create and edit OAuth clients and share them with projects
- Superusers make an OAuth client global
- Support users can also share into projects that allow support access

## 3. Who can do what

Ownership, not project role, decides every action here (`policies/users.ex:40-44`, `credentials.ex:948-959`,
`oauth_clients.ex:304-315`). "Owner" means the user whose `user_id` is on the credential or client.

| Action | Owner | Other signed-in user | Superuser (not owner) | Support user (not owner) |
|--------|-------|----------------------|-----------------------|--------------------------|
| See the page | yes | yes | yes | yes |
| See a credential in the list | yes | no | no | no |
| See an OAuth client in the list | yes | only if global | only if global | only if global |
| Create a credential | yes (for self) | yes (for self) | yes (for self) | yes (for self) |
| Edit, schedule deletion, delete now, cancel deletion | yes | no | no | no |
| Start or revoke a transfer | yes | no | no | no |
| Create an OAuth client | yes (for self) | yes (for self) | yes (for self) | yes (for self) |
| Edit or delete an OAuth client | yes | no | no | no |
| Make an OAuth client global | superuser only | no | yes | no |
| Share with a project | projects the owner is a member of | n/a | same as owner | also support-access projects |

**Preconditions beyond role**
- Projects offered for sharing are top-level, not scheduled for deletion, and ones the owner has a `project_users` row on (`projects.ex:1138-1147`), plus support-access roots for support users (`projects.ex:1160-1170`). Sandboxes are never offered; they receive shares by propagation (`credentials.ex:782-822`).
- "Delete now" is only offered once a credential is scheduled for deletion (`credential_index_component.ex:459-490`) and is refused when any run step used the credential (`credential_deletion_modal.ex:60-67`).
- A transfer recipient must exist, must not be the sender, and must be a member of every project the credential is shared with (`credentials.ex:1527-1540`, `:1810-1869`).
- `:global` is only cast when `allow_global` is true, which the host sets from `current_user.role === :superuser` (`oauth_client.ex:116-119`, `credential_index_component.html.heex:175`).

## 4. What it touches

**Reads**: `credentials`, `credential_bodies`, `project_credentials`, `projects`, `project_users`, `oauth_clients`, `project_oauth_clients`, `users` (transfer recipient lookup; all users when `transfer-in-form`), `steps` (activity check, `credentials.ex:1088-1093`), `workflows`/`jobs` (workflows using a credential, `credential_form_component.ex:1451-1455`)

**Writes**:
- `credentials` (insert, update name/external ID/schema/OAuth client, set and clear `scheduled_deletion`, set `transfer_status`, delete)
- `credential_bodies` (insert, update, delete per environment; `credentials.ex:221-240`, `:292-368`)
- `project_credentials` (insert, delete; bulk insert into descendant sandboxes, `credentials.ex:799-822`; delete all on scheduled deletion, `:1036-1052`)
- `jobs.project_credential_id` set to null on scheduled deletion (`credentials.ex:1045-1048`)
- `oauth_clients`, `project_oauth_clients` (insert, update, delete)
- audit trail rows (below)

**Immediate side effects** (in the same request)
- Audit (credential): `created`, `updated`, `added_to_project`, `removed_from_project`, `deleted`, `oauth_token_revoked` (`credentials.ex:703-790`, `:845-847`, `:978-1023`)
- Audit (OAuth client): `created`, `updated`, `added_to_project`, `removed_from_project`, `deleted` (`oauth_clients.ex:195-277`, `:326-328`)
- Email `email:credential-deletion-scheduled` to the owner on scheduling (`credentials.ex:908-911`, `:1054-1059`)
- Email `email:credential-transfer-confirmation` to the owner (not the recipient) on starting a transfer (`credentials.ex:1597-1602`, `user_notifier.ex:482-496`)

**Deferred side effects** (later, elsewhere)
- Daily `purge_deleted` job scrubs bodies of credentials past `scheduled_deletion` and deletes those without run activity (`credentials.ex:42-71`, cron at 02:30 `bootstrap.ex:310-311`, only when `purge_deleted_after_days > 0`)
- Transfer completes only when the owner opens the emailed link (flow-credential-transfer)

**External, non-transactional effects**
- OAuth token revocation HTTP call per environment, made inside the scheduling transaction (`credentials.ex:904-907`, `:961-1023`)
- Deletion email sent inside the scheduling transaction (`credentials.ex:908-911`)
- Transfer confirmation email sent after the status update commits (`credentials.ex:1592-1604`)
- OAuth code exchange, token refresh and userinfo calls from the form (`generic_oauth_component.ex:141-143`, `:198-203`, `:407-429`)

**Depends on config**
- `allow_credential_transfer`, `purge_deleted_after_days`, `max_credential_sensitive_values`, `credential_transfer_token_validity_in_days`, adaptor catalogue availability

**Product limits** (limits a user would notice and that we intend to keep)
- At most 5 environments per credential (`credential_form_component.ex:203-209`, `:897-915`)
- Environment names: lowercase letters, digits, `-` and `_`, up to 32 characters (`credential_form_component.ex:242-247`)
- At most `max_credential_sensitive_values` (default 50) sensitive keys in a body (`credential_body.ex:57-67`, `raw_body_component.ex:82-100`)

## 5. Scenarios

Controls are named in sentence case; the old app's labels are title case (see 6.2), so step
matchers should compare case-insensitively.

```gherkin
Feature: My credentials
  In order to give my workflows the secrets they need, and only where they need them
  As a signed-in user
  I want to create, share, rotate, hand over and retire my own credentials and OAuth clients

  @S01 @pending
  Scenario: The page lists only credentials I own
    # Value: a user's credentials page is an inventory of their own secrets, not of everything they can reach.
    Given I own credential "DHIS2 prod"
    And credential "Shared Postgres" is owned by someone else and shared with a project I belong to
    When I open "/credentials"
    Then I see "DHIS2 prod"
    And I do not see "Shared Postgres"
    # credentials.ex:125-136, credential_index_component.ex:65; credential_live_test.exs:119-154 (support user variant)

  @S02 @pending
  Scenario: Owner creates a raw JSON credential and shares it with two projects
    # Value: a secret is stored once and handed to exactly the projects that need it, without a project admin.
    Given I am a member of projects "Malawi HIV" and "Kenya TB"
    When I choose "Add new" then "Credential"
    And I pick "Raw JSON" and continue
    And I add projects "Malawi HIV" and "Kenya TB"
    And I enter name "Mailchimp" and a valid JSON body
    And I save the credential
    Then I see "Credential created successfully"
    And "Mailchimp" is listed with both projects
    And an audit event "created" and two "added_to_project" events are recorded
    # credential_form_component.ex:525-566, :1291-1318, helpers.ex:160-168, credentials.ex:703-788; credential_live_test.exs:635-715

  @S03 @pending
  Scenario: Adaptor credentials ask for that adaptor's fields
    # Value: jobs receive credentials in the shape their adaptor expects, so runs don't fail on a missing field.
    Given the adaptor catalogue includes "dhis2" with a configuration schema
    When I start a new credential and pick "Dhis2"
    Then I see an input for each field in the dhis2 schema
    And a required field I have touched and left empty shows an error
    And "Save credential" stays disabled until the required fields are valid
    # credential_form_component.ex:660-690, :1072-1075, json_schema_body_component.ex:96-149; credential_live_test.exs:832-896

  @S04 @pending
  Scenario: A raw body must be valid JSON
    # Value: a malformed secret is caught when it is entered rather than when a run fails.
    Given I am creating a raw JSON credential named "Mailchimp"
    When I enter "{not json" as the body
    Then I see "Invalid JSON format"
    And "Save credential" is disabled
    # raw_body_component.ex:112-142, credential_form_component.ex:653-658, :1072-1075; credential_live_test.exs:717-753

  @S05 @pending
  Scenario: Two of my credentials cannot share a name
    # Value: owners can tell their credentials apart when choosing one for a job.
    Given I own credential "DHIS2 prod"
    When I create another credential named "DHIS2 prod"
    Then I see "you have another credential with the same name"
    And no second credential is created
    # credential.ex:77-79, credential_form_component.ex:1315-1316

  @S06 @pending
  Scenario: Owner updates a credential's values
    # Value: a rotated secret is changed in one place and every project using it picks it up.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    When I edit "DHIS2 prod", change its password and save
    Then I see "Credential updated successfully"
    And the stored value for environment "main" is the new password
    And an audit event "updated" is recorded
    # credential_form_component.ex:1255-1289, credentials.ex:256-300, :344-368; credential_live_test.exs:1153-1179

  @S07 @pending
  Scenario: A credential keeps separate values per environment
    # Value: sandbox runs pick up the environment whose name matches theirs, so staging never uses production secrets (copy at credential_form_component.ex:1211).
    Given I am creating a raw JSON credential named "Mailchimp"
    When I add an environment and rename it "staging"
    And I enter different bodies on "main" and "staging"
    And I save the credential
    Then the credential has bodies named "main" and "staging" with the values I entered
    # credential_form_component.ex:195-229, :231-277, :621-626, credentials.ex:221-240; credential_live_test.exs:3839-3911

  @S08 @pending
  Scenario: Two environments cannot share a name
    # Value: one environment's secrets can't silently replace another's.
    Given I am editing a credential with environments "main" and "staging"
    When I rename "staging" to "main"
    Then I see "Environment 'main' already exists"
    And the environments are still "main" and "staging"
    # credential_form_component.ex:249-256

  @S09 @pending
  Scenario: The sixth environment cannot be added
    # Value: keeps a credential's environment list to a size people can review (product limit).
    Given I am editing a credential with 5 environments
    Then the add environment button is disabled
    And its tooltip reads "Maximum of 5 environments reached"
    # credential_form_component.ex:892-915, :203-209

  @S10 @pending
  Scenario: Removing an environment deletes its stored values
    # Value: secrets for a retired environment don't linger after the owner removes it.
    Given I own a credential with environments "main" and "staging"
    When I edit it, delete environment "staging", confirm, and save
    Then the credential has no "staging" body
    # credential_form_component.ex:280-310, :549, :628-631, credentials.ex:302-324

  @S11 @pending
  Scenario: Removing project access warns when workflows use the credential
    # Value: an owner doesn't break a running integration by accident.
    Given I own credential "DHIS2 prod" used by workflow "Daily sync" in project "Malawi HIV"
    When I edit "DHIS2 prod" and remove "Malawi HIV"
    Then I am asked to confirm a warning naming "Daily sync"
    # components/credentials.ex:194, credential_form_component.ex:1451-1455; credential_live_test.exs:1338-1408

  @S12 @pending
  Scenario: Removing project access is recorded
    # Value: project admins can later see when and how a credential left their project.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    When I edit "DHIS2 prod", remove "Malawi HIV" and save
    Then "DHIS2 prod" no longer lists "Malawi HIV"
    And an audit event "removed_from_project" is recorded
    # helpers.ex:32-57, credentials.ex:738-761; credential_live_test.exs:1286-1336

  @S13 @pending
  Scenario: Sharing with a project also shares with its sandboxes
    # Value: sandboxes keep working with the parent's credentials without re-sharing each one.
    Given project "Malawi HIV" has sandbox "Malawi HIV staging"
    When I share my credential "DHIS2 prod" with "Malawi HIV"
    Then "DHIS2 prod" is available in "Malawi HIV staging"
    # credentials.ex:763-822; credential_live_test.exs:3368-3448

  @S14 @pending
  Scenario: I can only share with projects I belong to
    # Value: people can't push their secrets into projects they have no part in.
    Given I am a member of "Malawi HIV" and not of "Kenya TB"
    When I open the project picker on a new credential
    Then "Malawi HIV" is offered
    And "Kenya TB" is not offered
    # hooks.ex:194-201, projects.ex:1138-1147, helpers.ex:94-121

  @S15 @pending @variant:support-user
  Scenario: Support users can also share into projects that allow support access
    # Value: support staff can set up credentials for a project they are helping without being added as members.
    Given I am a support user
    And project "Kenya TB" allows support access and I am not a member
    When I create a credential and add "Kenya TB"
    Then the credential is shared with "Kenya TB"
    # projects.ex:1160-1170; credential_live_test.exs:755-830

  @S16 @pending
  Scenario: Owner schedules a credential for deletion
    # Value: a credential stops being usable at once but can still be recovered during the grace period.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV" and used by a job there
    When I delete "DHIS2 prod" and confirm
    Then I see "Credential scheduled for deletion"
    And "DHIS2 prod" shows "Cancel deletion" and "Delete now"
    And "DHIS2 prod" is no longer shared with any project
    And the job no longer has a credential
    And the flow "flow-credential-scheduled-deletion" has started for "DHIS2 prod"
    # credential_deletion_modal.ex:40-51, credentials.ex:883-920, :1036-1052; credential_live_test.exs:156-230

  @S17 @pending
  Scenario: Owner deletes a scheduled credential for good
    # Value: an owner who is sure can remove a never-used secret immediately rather than waiting for the purge.
    Given I own credential "Old token" scheduled for deletion and never used in a run
    When I choose "Delete now" and confirm
    Then I see "Credential deleted successfully"
    And "Old token" no longer exists
    And an audit event "deleted" is recorded
    # credential_deletion_modal.ex:69-98, credentials.ex:836-849; credential_live_test.exs:339-376

  @S18 @pending
  Scenario: A credential used in runs cannot be deleted now
    # Value: run history in the audit trail keeps pointing at a real credential record.
    Given I own credential "DHIS2 prod" scheduled for deletion and used in a run step
    When I choose "Delete now"
    Then I see "Credential marked for deletion" with only an "Ok, understood" button
    And forcing the delete shows "Cannot delete a credential that has activities in projects"
    And "DHIS2 prod" still exists
    # credential_deletion_modal.ex:60-67, :107-135; credential_live_test.exs:378-413

  @S19 @pending
  Scenario: A delete confirmation cannot be pointed at another credential
    # Value: someone else's secret can't be deleted by editing the request from my own modal.
    Given I own "DHIS2 prod" and "Other" is owned by someone else
    When I open the delete modal for "DHIS2 prod" and submit it with the id of "Other"
    Then I see "You can't perform this action"
    And neither credential is scheduled for deletion
    # credential_deletion_modal.ex:27-37; credential_live_test.exs:232-259

  @S20 @pending
  Scenario: Owner starts a credential transfer
    # Value: a credential can change hands when its owner leaves a team, without recreating the secret.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    And "amara@example.org" is a member of "Malawi HIV"
    When I choose "Transfer" on "DHIS2 prod" and submit "amara@example.org"
    Then I see "Credential transfer initiated. We've sent you a confirmation email."
    And "DHIS2 prod" shows "Revoke transfer"
    And the flow "flow-credential-transfer" has started for "DHIS2 prod"
    # transfer_credential_modal.ex:68-112, credentials.ex:1572-1609; credential_live_test.exs:2524-2548

  @S21 @pending
  Scenario: A transfer to someone outside the credential's projects is refused
    # Value: a credential never ends up owned by someone who can't see the projects that depend on it.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    And "amara@example.org" is not a member of "Malawi HIV"
    When I enter "amara@example.org" in the transfer form
    Then I see "User doesn't have access to these projects: Malawi HIV"
    And "Transfer" is disabled
    # credentials.ex:1810-1847, transfer_credential_modal.ex:31-39, :225-233

  @S22 @pending
  Scenario: Owner revokes a pending transfer
    # Value: an owner can stop a transfer started by mistake before it is confirmed.
    Given I own credential "DHIS2 prod" with a pending transfer
    When I choose "Revoke transfer" and confirm with "Revoke"
    Then I see "Transfer revoked successfully"
    And "DHIS2 prod" shows "Transfer"
    # transfer_credential_modal.ex:41-66, credentials.ex:1740-1758; credential_live_test.exs:2703-2722

  @S23 @pending
  Scenario: User adds an OAuth client
    # Value: users can connect credentials to their own OAuth apps without an instance administrator.
    Given I am a member of "Malawi HIV"
    When I choose "Add new" then "OAuth client"
    And I fill in name, authorization endpoint, token endpoint, client ID and client secret
    And I add mandatory scopes "read, write" and project "Malawi HIV"
    And I add the OAuth client
    Then I see "Oauth client created successfully"
    And the client is listed with project "Malawi HIV"
    And an audit event "created" is recorded for the client
    # oauth_client_form_component.ex:199-212, :246-305, :320-339, oauth_clients.ex:134-151; oauth_clients_live_test.exs:232-284

  @S24 @pending
  Scenario: OAuth client endpoints must be URLs
    # Value: a mistyped endpoint is caught before anyone tries to authorize against it.
    When I enter "oauth2/v2/auth" as the authorization endpoint of a new OAuth client
    Then I see "must be either a http or https URL"
    And "Add OAuth client" is disabled
    # oauth_client.ex:90-95, oauth_client_form_component.ex:114-138, :529; oauth_clients_live_test.exs:244-251

  @S25 @pending
  Scenario: A non-superuser cannot publish a global OAuth client
    # Value: only instance administrators can offer an OAuth app to every project.
    Given I am not a superuser
    When I add an OAuth client and the request carries global "true"
    Then the client is saved as not global
    And I do not see the "Make client global" checkbox
    # oauth_client.ex:116-119, oauth_client_form_component.ex:513; oauth_clients_live_test.exs:286-303

  @S26 @pending @variant:superuser
  Scenario: Superuser makes an OAuth client global
    # Value: an administrator can offer one approved OAuth app to every project in the instance.
    Given I am a superuser
    When I add an OAuth client and tick "Make client global"
    Then the project picker is hidden
    And other users see the client in their list as "GLOBAL" and can pick it for a new credential
    # oauth_client_form_component.ex:513-523, :549-559, oauth_clients.ex:82-88, credential_form_component.ex:1359-1392

  @S27 @pending
  Scenario: Creating an OAuth credential hands off to the provider sign-in
    # Value: people authorize with their own provider account instead of pasting tokens.
    Given OAuth client "Google Sheets app" is mine or global
    When I start a new credential, pick "Google Sheets app" and continue
    And I choose "Sign in with Google Sheets app"
    Then the flow "flow-oauth-credential-authorize" has started for environment "main"
    # credential_form_component.ex:150-174, :947-966, generic_oauth_component.ex:95-121, :302-308

  @S28 @pending
  Scenario: Changing scopes after authorizing requires signing in again
    # Value: the token saved always carries the scopes the form shows.
    Given I have authorized an OAuth credential with scopes "read"
    When I tick an extra optional scope "write"
    Then I am told to reauthorize
    And "Save credential" is disabled until I do
    # generic_oauth_component.ex:310-372, components/oauth.ex:177-178, credential_form_component.ex:1072-1075; credential_live_test.exs:3109-3151

  @S29 @pending
  Scenario: Opening an OAuth credential with an expired token refreshes it
    # Value: the owner sees whether the stored authorization still works before relying on it.
    Given I own an OAuth credential whose access token has expired and whose refresh token is valid
    When I edit it
    Then the token is refreshed and the account details are shown
    # generic_oauth_component.ex:49-93, :391-417; credential_live_test.exs:3195-3242

  @S30 @pending
  Scenario: A revoked refresh token asks the owner to reauthorize
    # Value: the owner learns the credential has stopped working and how to fix it.
    Given I own an OAuth credential whose refresh token the provider rejects with "invalid_grant"
    When I edit it
    Then I see a prompt to reauthorize with the provider
    # generic_oauth_component.ex:220-236, :387-389; credential_live_test.exs:1555-1620

  @S31 @pending
  Scenario: An OAuth credential whose client was deleted shows a warning
    # Value: the owner learns why the credential can no longer be reauthorized.
    Given I own an OAuth credential whose OAuth client has been deleted
    When I edit it
    Then I see "OAuth client not found"
    # credential_form_component.ex:818-820, components/oauth.ex:108-118; credential_live_test.exs:3244-3287

  @S32 @pending
  Scenario: The type picker recovers when the adaptor catalogue is unavailable
    # Value: a temporary catalogue outage doesn't stop people creating credentials once it recovers.
    Given the adaptor catalogue cannot answer
    When I start a new credential
    Then I see "Couldn't load adaptors. Please try again." with a "Retry" button
    And "Raw JSON" is still offered
    # credential_form_component.ex:731-744, :1364-1396, :187-189; credential_live_test.exs:3927-3951
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Saving an OAuth credential whose body fails token validation (for example before signing in, body `%{}`) returns `{:error, %OauthValidation.Error{}}`, which neither `save_credential` clause matches. Read, not run. | `credential_form_component.ex:1262-1288`, `:1299-1317`; `credentials.ex:211`, `:277-282`, `:416-436` | "Save credential" is enabled for OAuth (`body_valid?` is true for `"oauth"`, `:648-651`), and submitting appears to crash the LiveView and lose the modal | fix |
| Under `transfer-in-form` the edit form shows "Transfer ownership" with an owner select listing every user in the instance by name and email; the chosen `user_id` is dropped because `Credential.changeset/2` does not cast it | `credential_form_component.ex:1022-1035`, `:1241-1249`, `:1463-1468`; `components/credentials.ex:327-346`; `credential.ex:38-46` | any credential owner sees all users' emails; "Credential updated successfully" but the owner is unchanged | fix |
| With `purge_deleted_after_days` 0 the deletion is dated now and the email says secrets are scrubbed "after a few minutes", but the purge cron is only registered when the setting is above 0 | `credentials.ex:922-925`; `user_notifier.ex:154-162`, `:239`; `bootstrap.ex:306-317` | secrets are never scrubbed; the credential stays "scheduled" until someone uses "Delete now" | decide |
| A changeset error from `schedule_credential_deletion` is swallowed with `{:noreply, socket}` | `credential_deletion_modal.ex:56-57` | clicking "Delete credential" does nothing, with no message | fix |
| Transfer and revoke failures flash `inspect(reason)` | `transfer_credential_modal.ex:57-64`, `:105-107` | "Could not revoke transfer: :not_found" or an inspected changeset | fix |
| The transfer form tells the owner whether an email has an account ("User does not exist") and, on blur, which of the credential's projects that person is not in | `credentials.ex:1863-1864`, `:1819-1823`; `transfer_credential_modal.ex:31-39` | account enumeration for any signed-in user who owns a credential | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Old copy is title case ("Save Credential", "Add an OAuth Client", "Transfer Credential Ownership", "Revoke Credential Transfer", "Credential Name"); flash "Oauth client created successfully" lowercases the "A" | `credential_form_component.ex:845`, `:1077`; `oauth_client_form_component.ex:316`, `:326`, `:365-369`; `transfer_credential_modal.ex:123-127` | fix |
| Every successful save, delete, transfer or revoke does `push_navigate` back to `/credentials`, remounting the page rather than patching | `helpers.ex:160-168`; `credential_form_component.ex:1320-1326`; `credential_deletion_modal.ex:49-51`; `transfer_credential_modal.ex:52-55` | preserve |
| Project picker lists top-level projects only; sandboxes get access through propagation, and removing the parent does not remove the sandbox copies | `projects.ex:1138-1147`; `credentials.ex:738-761`, `:782-822` | decide |
| Cancelling a scheduled deletion does not restore project access or job assignments removed when it was scheduled (the delete modal copy warns about this; the "Credential deletion canceled" flash does not) | `credentials.ex:1036-1052`, `:936-942`; `credential_deletion_modal.ex:146-149` | preserve |
| `@openfn/language-googlesheets` and `@openfn/language-gmail` are excluded from the credential type list | `credential_form_component.ex:1220-1222` | decide |
| Type list is adaptors with a schema, plus "Raw JSON", plus OAuth clients, sorted case-insensitively by name | `credential_form_component.ex:1214-1226`, `:1385-1394` | preserve |
| Environments sort with "main", "production", "prod", "master", "principal", "primary", "default" first; the first of those is the tab opened on edit | `credential_form_component.ex:1521-1540`, `:1560-1577` | preserve |
| New environments are named "untitled", "untitled-1", ... | `credential_form_component.ex:1542-1558` | preserve |
| Environment names are trimmed and lowercased as typed, with a 300 ms debounce | `credential_form_component.ex:231-233`, `:936` | preserve |
| Schema field errors only show for fields the user has touched | `credential_form_component.ex:637-644`, `:681-690` | preserve |
| An empty raw body renders as "{}" and only reports "can't be blank" once touched | `raw_body_component.ex:126-142` | preserve |
| An empty external ID is stored as null; external ID must be unique per owner and within a project and its sandboxes (app-level check with a noted race) | `credential.ex:80-82`, `:104-109`; `credentials.ex:459-536` | preserve |
| Scopes typed into the OAuth client form split on commas or spaces into sorted, de-duplicated chips | `oauth_client_form_component.ex:246-272` | preserve |
| OAuth client "Client ID" is a password input | `oauth_client_form_component.ex:446-451` | decide |
| Global OAuth clients owned by others appear on every user's `/credentials` with no actions | `oauth_clients.ex:82-88`; shared-credential-index-component 6.2 | preserve |
| "Revoke transfer" and "Transfer" are the same menu item; the label follows `transfer_status`, and a completed transfer reads "Transfer" again | `credential_index_component.html.heex:81-95`; `transfer_credential_modal.ex:12` | preserve |
| The transfer confirmation email goes to the owner, not the recipient, matching the flash | `credentials.ex:1597-1602`; `user_notifier.ex:482` | preserve |
| `/credentials` sits in `live_session :default` alongside project pages but mounts no project scope or limits banner; it shows the book-a-demo banner when enabled | `router.ex:288`, `:322`; `index.html.heex:2-8`; `init_assigns.ex:46-54` | preserve |
| The host hard-codes `can_create_project_credential={true}` | `index.html.heex:33` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `apply_action(:index)` assigns `credential: nil`, which nothing on the page reads | `index.ex:24-27` | the component owns its own `credential` assign |
| `handle_event("api_version")` | `credential_form_component.ex:146-148` | no element emits it |
| `handle_event("select_project")` in both forms | `credential_form_component.ex:487-493`; `oauth_client_form_component.ex:156-165` | the picker only emits `add_selected_project` and `remove_selected_project` (`components/credentials.ex:170`, `:191`) |
| `handle_event("edit_mandatory_scope" / "edit_optional_scope")` and `phx-hook="EditScope"` | `oauth_client_form_component.ex:148-154`, `:228-243`, `:478`, `:489`, `:584` | no `EditScope` hook exists in `assets/js`; the browser reports an unknown hook |
| Second `schema_selected` clause matching only `_target` | `credential_form_component.ex:176-178` | the first clause matches whenever `selected` is present |
| `update_body` assign and `update_body/3` | `credential_form_component.ex:1251-1253`, `:1470-1474`, `:1506` | assigned but never called |
| Advanced picker and keychain pages of the credential form | `credential_form_component.ex:312-485`, `:1038-1059`, `:1087-1204` | `from_collab_editor` is only set by the workflow editor (`workflow_live/collaborate.ex:291`) |
| "Maximum of 5 environments allowed per credential" flash | `credential_form_component.ex:203-209` | the button is disabled at 5 (`:907`) |
| "Cannot delete the last environment" flash | `credential_form_component.ex:281-287` | the delete button renders only with more than one environment (`:984`) |
| Not-authorized branches of both forms' `save` | `credential_form_component.ex:526-541`; `oauth_client_form_component.ex:200-211` | this host always passes `true` (`index.html.heex:33`) |
| `{:error, :unauthorized}` on credential create | `credential_form_component.ex:1307-1313` | `user_id` is seeded with the current user (`credential_index_component.ex:101-104`) |
| Keychain events and modals of the index component | `credential_index_component.ex:272-346` | already listed in shared-credential-index-component 6.3 |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Max 5 environments | `credential_form_component.ex:203`, `:897-915` | yes, disabled button and tooltip | preserve |
| Max sensitive keys per body (default 50, `max_credential_sensitive_values`) | `credential_body.ex:57-67`; `config.ex:373-375` | yes, "contains too many sensitive keys (N). Max allowed is 50" | preserve |
| Environment name max 32 characters | `credential_form_component.ex:242-247` | yes | preserve |
| `list_users/0` loads every user in the instance into the edit form when `transfer-in-form` | `credential_form_component.ex:1241-1249`, `:1463-1468` | no (until the instance is large) | fix |
| Project list is loaded once on mount and not refreshed while the page is open | `hooks.ex:194-201` | yes, a newly joined project is missing until reload | preserve |
| OAuth token and userinfo fetches run as `start_async` tasks with no timeout of their own | `generic_oauth_component.ex:141-143`, `:198-203`, `:414-428` | yes, a hanging provider leaves "Authenticating with ..." showing | decide |
| Transfer link validity (`credential_transfer_token_validity_in_days`) | `user_notifier.ex:475-477` | yes, in the email | preserve |
| Purge runs daily at 02:30 | `bootstrap.ex:310-311` | no | preserve |

### 6.5 Things seen but not understood

- `credential_live_test.exs:2481-2522`: five transfer validation tests end in `render_change(...) =~ "..."` without `assert`, so they pass whatever the form shows. "Validates receiver exists", "cannot transfer to self" and "receiver has project access" are not verified by these tests.
- `credential_live_test.exs:1255-1284` is named "cannot add new project with access by support user" but asserts only that a support user sees no edit action on someone else's credential.
- `credential_live_test.exs:1782-1857` says "credential should not be created even if form is submitted" but never submits; it does not cover the 6.1 crash.
- `oauth_clients_live_test.exs:525-545`: both OAuth client deletion tests are `@tag :skip`.
- External ID uniqueness across a project and its sandboxes (`credentials.ex:459-536`) is enforced, but nothing on this page explains what external IDs are used for, so the value of the rule is unclear.
- `assign_scopes/3` pushes `clear_input` when a client already has scopes (`oauth_client_form_component.ex:74-85`); the intent is unclear.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the edit form's "Transfer ownership" section exist at all, given the email transfer flow (6.1)?
- With `purge_deleted_after_days` 0, should scheduling delete immediately, or should the purge still run (6.1)?
- Should the transfer form keep revealing whether an email has an account (6.1)?
- Why are Google Sheets and Gmail excluded from the credential types (6.2)?
- Should removing a parent project's access also remove the credential from its sandboxes (6.2)?

## Proposed flows

- `flow-credential-transfer`: the owner submits a recipient here; the owner gets a "Transfer <name> to <first name>" email with `/credentials/transfer/:token`; opening it as the owner runs `CredentialTransferController.confirm`, which moves ownership, records "transfered" in the audit and emails the recipient a link back to `/credentials`. Surfaces: credentials-index (also project-settings-credentials), email:credential-transfer-confirmation (`user_notifier.ex:469-497`), controller:credential-transfer-confirm (`router.ex:238-240`, `credential_transfer_controller.ex:6-25`, `credentials.ex:1656-1702`), email:credential-transfer-completed (`user_notifier.ex:503-517`), credentials-index (recipient).
- `flow-oauth-credential-authorize`: "Sign in with <provider>" opens the provider in a second window; the provider redirects to `/oauth/:provider/callback`, which decodes the state and broadcasts `{:forward, GenericOauthComponent, code}` on the LiveView's topic; the page forwards it to the component, which exchanges the code, validates scopes and fetches userinfo. Surfaces: credentials-index (also project-settings-credentials and the workflow editor), external OAuth provider, controller:oauth-callback (`router.ex:79`, `oidc_controller.ex:75-83`, `:269-280`), pubsub:oauth_credential:<socket id> (`oauth_credential_helper.ex:51-78`), credentials-index `handle_info` (`index.ex:32-36`).
- `flow-credential-scheduled-deletion`: scheduling here unshares the credential, revokes OAuth tokens and emails the owner that they can cancel from the Credentials menu; the daily purge later scrubs bodies and deletes records with no run activity. Surfaces: credentials-index, email:credential-deletion-scheduled (`user_notifier.ex:226-246`), capability:credentials-purge-deleted (`credentials.ex:42-71`, `bootstrap.ex:310-311`), credentials-index (cancel, shared-credential-index-component S05).

## Proposed shared

- `shared-authenticated-session`: the `InitAssigns` gate and chrome for every signed-in LiveView: redirect to `/users/log_in` without a valid session, lockout redirect for unconfirmed accounts, `toggle_sidebar` preference hook, book-a-demo and GDPR banners. Surfaces: every view in live_sessions `:default`, `:settings`, `:services` (`init_assigns.ex:17-90`, `router.ex:268`, `:288`, `:351`).
- `shared-credential-form-component` (optional): the credential form modal (`CredentialFormComponent`, `GenericOauthComponent`, body components) is catalogued here as its main home, but project-settings-credentials and the workflow editor (`workflow_live/collaborate.ex:291`) render it too, the latter with `from_collab_editor` pages this view cannot reach. If the lead prefers, S02 to S13 and S27 to S32 can move to a shared annotation that those views inherit.

## Lead resolution (batch 1)

- All three flows created as proposed.
- `shared-authenticated-session` created. `shared-credential-form-component` declined: this view stays the home of the credential form, and other views that open it reference this file in `related` and assert only that the form opens.
