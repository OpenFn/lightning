---
id: project-settings-credentials
type: view
title: Project settings › Credentials
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/settings#credentials
  new_route: /projects/:project_id/settings/credentials
  old_route_disposition: redirect
  reachable_when:
    - the project scope gate admits the viewer (shared-project-scope; on_mount :project_scope, settings.ex:51); this includes support users with no membership row when the project allows support access
    - the client-side tab hash is "credentials" (settings.html.heex:315; Tabbed.container defaults to "project", see shared-project-settings-tab-chrome S01, S02)

inherits:
  - shared-authenticated-session
  - shared-project-scope                  # login, MFA gate, non-member redirect, membership remount (refreshes the mount-time permission flags below)
  - shared-usage-limits-banner            # on_mount :check_limits (settings.ex:52)
  - shared-project-header
  - shared-project-settings-tab-chrome    # tab strip, "available credentials." notice (S06 row "viewer | Credentials"), sandbox "will sync to the parent project on merge" banner (S08 row "Credentials")
  - shared-credential-index-component     # the three tables, owner-only row actions (S01, S02), editor without keychain actions (S03), keychain delete (S04), cancel deletion (S05), forged-action refusal (S06)
  - shared-flash-messages   # added by lead (final pass)

url_params: []                            # the tab is chosen by fragment; apply_action(:index) ignores params (settings.ex:233)

config_variants:
  default: {}                             # read under this variant
  sandbox: { project.parent_id: <parent project id> }      # data state, named as in shared-project-settings-tab-chrome
  support-user: { current_user.support_user: true, project.allow_support_access: true, no project_users row }

inventory:
  routes:
    - live /projects/:project_id/settings  ProjectLive.Settings :index   # config-injected (config/config.exs:54-57); owned by project-settings-setup
  events:
    - ProjectLive.Settings handle_info {:forward, mod, opts}             # settings.ex:682-686; OAuth code re-entry, handoff to flow-oauth-credential-authorize
    - CredentialIndexComponent#show_modal (targets new_credential, new_keychain_credential, new_oauth_client)   # credential_index_component.ex:91-158; owned by shared-credential-index-component, project-specific gating asserted here
    - KeychainCredentialFormComponent#validate                           # keychain_credential_form_component.ex:74-81
    - KeychainCredentialFormComponent#save                               # keychain_credential_form_component.ex:83-85, :121-216
  js_hooks:
    - Common.simple_dropdown show_dropdown / hide_dropdown for "Add new" (common.ex:677-709)
    - ModalHook close_modal (hooks/index.ts:522-530); keychain save pushes close_modal, which runs the modal's on_close and reloads the lists via close_active_modal (keychain_credential_form_component.ex:110-114, :132, :178)
  policies:
    - Lightning.Policies.ProjectUsers (:create_project_credential), editor action (project_users.ex:39-49, :167-172); host flag settings.ex:166-171
    - Lightning.Policies.Credentials (:create_keychain_credential, :edit_keychain_credential), admin, owner or support (policies/credentials.ex:32-63, :87-98); host flag settings.ex:173-178, component flag credential_index_component.ex:41-47, form flags keychain_credential_form_component.ex:44-59
    - Lightning.Policies.Users (:edit_credential, :delete_credential), owner only (policies/users.ex:40-44), via shared-credential-index-component
  workers: []                             # the purge worker belongs to flow-credential-scheduled-deletion
  api_endpoints: []
  emails: []                              # deletion and transfer emails belong to their flows
  config: []
  not_reachable_here:
    - KeychainCredentialFormComponent on_back "back_to_advanced_picker" (keychain_credential_form_component.ex:109); the Back button renders only with from_collab_editor (components/credentials.ex:313-319), which this host never sets
    - CredentialFormComponent advanced picker and keychain pages (credential_form_component.ex:312-485); see credentials-index not_reachable_here

related:
  - credentials-index                     # home of the credential form, OAuth client form, transfer and delete modals
  - project-settings-setup                # owns the host route and mount
  - lib/lightning_web/live/project_live/settings.ex
  - lib/lightning_web/live/project_live/settings.html.heex
  - lib/lightning_web/live/components/credentials.ex
  - lib/lightning_web/live/credential_live/credential_index_component.ex
  - lib/lightning_web/live/credential_live/credential_index_component.html.heex
  - lib/lightning_web/live/credential_live/keychain_credential_form_component.ex
  - lib/lightning_web/live/components/data_tables.ex
  - lib/lightning/credentials.ex
  - lib/lightning/credentials/keychain_credential.ex
  - lib/lightning/oauth_clients.ex
  - lib/lightning/policies/credentials.ex
  - lib/lightning/policies/project_users.ex
  - test/lightning_web/live/project_live_test.exs
  - test/lightning_web/live/credential_live_test.exs
  - test/lightning_web/live/oauth_clients_live_test.exs
flows:
  - flow-credential-transfer
  - flow-oauth-credential-authorize
  - flow-credential-scheduled-deletion
  - flow-editor-credentials-broadcast
---

## 1. Purpose

Members of a project use this tab to see which secrets and OAuth apps their workflows can use,
who owns each one, and which keychains pick a credential per run. Editors add credentials and
OAuth clients straight into the project, and admins set up keychains. Without it, a project's
team couldn't tell what a failing job is authenticating with or whom to ask about it, and anyone
adding a secret would have to leave the project and remember to share it back.

## 2. What it does

- **See what the project can use** (every member)
  - The credentials and OAuth clients the project can use, with their owners
  - The project's keychains, with their JSONPath and creator
- **Add credentials and OAuth clients** (editors, admins, owners and support users)
  - Create a credential already shared with this project; in a sandbox, with the sandbox only
  - Create an OAuth client already shared with this project
  - Build new OAuth credentials on the project's OAuth clients and global ones
- **Set up keychains** (admins, owners and support users)
  - Create and edit keychains, whose default credential must be one this project can use
- **Look after your own credentials** (credential owners)
  - Schedule deletion, start a transfer and authorize OAuth from here, landing back on this tab
- Viewers can't create anything here, even by sending the event

**Straightforwardness: 3 of 5.** Seeing and adding is simple, but what you can do to an existing credential depends on whether you own it rather than your role, and that produces some odd moments.

### Most surprising behaviours

- **(2)** A viewer who owns a credential gets an "Edit" button here, fills in the form, and is refused on save, losing the edit. The same edit works on their own credentials page. (6.1)
- **(3)** Row actions follow ownership, not role: an admin can't edit or delete a colleague's credential from here, while a viewer can manage one they own. (3)
- **(3)** Deleting a credential from here makes it disappear from the list at once, and the only way to cancel the deletion is on the separate credentials page, which nothing points to. (6.1, S17)
- **(3)** The "Projects with access" column lists every project a credential is shared with, including ones the viewer isn't on, so members can learn the names of other projects. (6.1)
- **(3)** When a list is empty its "Create" button looks live even for people who can't create, and clicking it just says they aren't authorized. (6.1)

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:39-49`, `:134`, `:167-172` (credentials and OAuth
clients); `lib/lightning/policies/credentials.ex:32-63`, `:87-98` (keychains);
`lib/lightning/policies/users.ex:40-44` (row actions on credentials and OAuth clients); flags at
`settings.ex:166-178`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|-----------------------------|
| See the tab, credentials, OAuth clients and keychains | yes | yes | yes | yes | no (cannot open the project) | yes |
| Create a credential | no | yes | yes | yes | no | yes |
| Create an OAuth client | no | yes | yes | yes | no | yes |
| Create a keychain | no | no | yes | yes | no | yes |
| Edit a keychain | no | no | yes | yes | no | yes |
| Delete a keychain (shared-credential-index-component S04) | no | no | yes | yes | no | yes |
| Edit, delete, transfer a credential or OAuth client | owner of that row | owner of that row | owner of that row | owner of that row | no | owner of that row |
| Save an edit to an owned credential or OAuth client from this tab | no (see 6.1) | yes, if owner | yes, if owner | yes, if owner | no | yes, if owner |

**Preconditions beyond role**
- A support user with a membership row gets that row's role, not support standing (`project_users.ex:163-172`, `policies/credentials.ex:89-93`).
- Every action is denied when the project requires MFA and the actor hasn't enrolled (`project_users.ex:134`, `policies/credentials.ex:90-93`); in practice the scope gate redirects first (shared-project-scope).
- Row actions on credentials and OAuth clients depend on ownership, not role (shared-credential-index-component section 3).
- The create flags are fixed at mount (`settings.ex:118-188`) and re-checked on the server when a form opens (`credential_index_component.ex:91-158`) and on save (`credential_form_component.ex:525-541`, `oauth_client_form_component.ex:199-211`, `keychain_credential_form_component.ex:121-216`).

## 4. What it touches

**Reads**: `credentials` joined through `project_credentials` for this project, with `users`, `projects`, `credential_bodies`, `oauth_clients` (`credentials.ex:106-122`); `oauth_clients` shared with the project or global (`oauth_clients.ex:60-80`); `keychain_credentials` for the project with creator and default credential (`credentials.ex:1912-1919`); `projects` for the picker (`projects.ex:1160-1176`, `settings.ex:117`); `project_users` (`credential_index_component.ex:32-33`)

**Writes**:
- `keychain_credentials` (insert, update; `credentials.ex:1956-2002`)
- Credential, OAuth client, transfer and deletion writes happen in the forms and modals catalogued by credentials-index and the flows below

**Immediate side effects**
- none from this tab's own handlers; keychain create and update record no audit event (`credentials.ex:1956-2002`)

**Deferred side effects**
- none here; scheduled deletion and transfer side effects belong to flow-credential-scheduled-deletion and flow-credential-transfer

**External, non-transactional effects**
- none here; OAuth provider calls belong to flow-oauth-credential-authorize

**Depends on config**
- none

**Product limits**
- Keychain name up to 255 characters, JSONPath up to 500 (`keychain_credential.ex:52-53`)

## 5. Scenarios

```gherkin
Feature: Project credentials
  In order to know and control which secrets my project's workflows use
  As a member of a project
  I want to see the project's credentials, OAuth clients and keychains, and add new ones here

  @S01 @pending
  Scenario: Members see the project's credentials and who owns them
    # Value: a member debugging a failing job can see which secret the project has and whom to ask about it.
    Given I am a viewer on project "Malawi HIV"
    And "amara@example.org" owns credential "DHIS2 prod" shared with "Malawi HIV"
    And "amara@example.org" owns credential "Personal sandbox" not shared with "Malawi HIV"
    When I open the project's settings on the "Credentials" tab
    Then I see "DHIS2 prod" with type, owner "amara@example.org" and its environments
    And I do not see "Personal sandbox"
    # settings.html.heex:358-365 (show_owner_in_tables), credentials.ex:106-122, data_tables.ex:36-83; project_live_test.exs:944-987

  @S02 @pending
  Scenario: Members see the OAuth clients the project can use
    # Value: someone setting up an OAuth credential knows which approved OAuth apps this project already has.
    Given OAuth client "Google" is shared with "Malawi HIV"
    And OAuth client "Salesforce" is global
    And OAuth client "Other" is shared only with another project
    When I open the "Credentials" tab of "Malawi HIV"
    Then I see "Google" and "Salesforce"
    And I do not see "Other"
    # oauth_clients.ex:60-80, credential_index_component.ex:444-454, data_tables.ex:209-245

  @S03 @pending
  Scenario: Members see only this project's keychains
    # Value: a project's run-time credential routing is visible to its team and not to other projects.
    Given project "Malawi HIV" has keychain "By district" with path "$.organization.id"
    And another project I belong to has keychain "Other keychain"
    When I open the "Credentials" tab of "Malawi HIV"
    Then I see "By district" and "$.organization.id"
    And I do not see "Other keychain"
    # credential_index_component.ex:60-80, credentials.ex:1912-1919; project_live_test.exs:1244-1289

  @S04 @pending
  Scenario: Editor creates a credential that is shared with this project
    # Value: a secret added from the project is usable there at once, without a separate sharing step.
    Given I am an editor on project "Malawi HIV"
    When I choose "Add new" then "Credential"
    Then the credential form opens with "Malawi HIV" already selected under projects access
    When I complete and save the credential "HTTP API"
    Then I am back on the "Credentials" tab of "Malawi HIV"
    And "HTTP API" is listed
    # settings.html.heex:323-333, credential_index_component.ex:91-109, helpers.ex:152-168; the form itself is credentials-index S02
    # project_live_test.exs:989-1033 (admin and editor)

  @S05 @pending @variant:sandbox
  Scenario: A credential created in a sandbox is shared with the sandbox only
    # Value: a credential made while experimenting does not reach the parent or ancestor projects before a merge.
    Given I am an admin on project "root" and its nested sandbox "sandbox-project"
    When I choose "Add new" then "Credential" on the "Credentials" tab of "sandbox-project"
    Then "sandbox-project" is selected under projects access
    And neither "root" nor the intermediate project is selected
    # helpers.ex:156-158, credential_index_component.ex:93-96; project_live_test.exs:1035-1075

  @S06 @pending @variant:support-user
  Scenario: Support user creates a credential in a project that allows support access
    # Value: support staff can add a missing secret for a project they are helping without being made a member.
    Given I am a support user with no membership on "Malawi HIV"
    And "Malawi HIV" allows support access
    When I choose "Add new" then "Credential", complete and save it
    Then I am back on the "Credentials" tab and the credential is listed
    # project_users.ex:167-169, settings.ex:166-171; project_live_test.exs:1077-1123

  @S07 @pending
  Scenario: Viewer cannot create anything on this tab
    # Value: read-only members can't add secrets or OAuth apps to a project, even by crafting a request.
    Given I am a viewer on project "Malawi HIV"
    When I open "Add new" on the "Credentials" tab
    Then "Credential", "Keychain" and "OAuth client" are disabled
    When I send "show_modal" with target "new_credential" anyway
    Then I see "You are not authorized to perform this action"
    And no credential form is open
    # settings.html.heex:327-348, components/credentials.ex:389-399, credential_index_component.ex:91-109, :419-424
    # project_live_test.exs:1125-1153 (credential); :1668-1695 (keychain)

  @S08 @pending
  Scenario: Editor sees the keychain option disabled
    # Value: keychains decide at run time which secret a job uses, so only admins set them up.
    Given I am an editor on project "Malawi HIV"
    When I open "Add new" on the "Credentials" tab
    Then "Credential" and "OAuth client" are enabled
    And "Keychain" is disabled
    # settings.html.heex:334-340, settings.ex:173-178, policies/credentials.ex:87-98; project_live_test.exs:1193-1213 asserts the admin side only

  @S09 @pending
  Scenario: Editor creates an OAuth client shared with this project
    # Value: a team can register its own OAuth app for the project without asking a superuser.
    Given I am an editor on project "Malawi HIV"
    When I choose "Add new" then "OAuth client"
    Then the OAuth client form opens with "Malawi HIV" already selected under projects access
    When I complete and save it
    Then I am back on the "Credentials" tab with "Oauth client created successfully"
    # credential_index_component.ex:133-158, oauth_client_form_component.ex:36-48; the form itself is credentials-index
    # oauth_clients_live_test.exs:206-270 (runs against both /credentials and this tab)

  @S10 @pending
  Scenario: New OAuth credentials are offered the project's OAuth clients
    # Value: owners build OAuth credentials on the apps approved for this project rather than only their own.
    Given OAuth client "Google" owned by someone else is shared with "Malawi HIV"
    And OAuth client "Mine only" is owned by me and not shared with "Malawi HIV"
    When I choose "Add new" then "Credential" on the "Credentials" tab of "Malawi HIV"
    Then the type picker offers "Google"
    And it does not offer "Mine only"
    # credential_form_component.ex:1355-1395 (list_clients(project) when a project is assigned), oauth_clients.ex:60-80

  @S11 @pending
  Scenario: Admin creates a keychain
    # Value: one job can use the right secret per organisation or district, picked from the run's input.
    Given I am an admin on project "Malawi HIV"
    And credential "DHIS2 prod" is shared with "Malawi HIV"
    When I choose "Add new" then "Keychain"
    And I enter name "By district", JSONPath "$.user_id" and default credential "DHIS2 prod"
    And I choose "Create"
    Then I see "Keychain credential created successfully"
    And "By district" is listed with me as its creator
    # credential_index_component.ex:112-131, keychain_credential_form_component.ex:162-188, components/credentials.ex:229-325
    # project_live_test.exs:1523-1571

  @S12 @pending
  Scenario: A keychain needs a name and a JSONPath starting with "$"
    # Value: a keychain that could never select a credential is caught when it is set up, not when runs fail.
    Given I am creating a keychain on "Malawi HIV"
    When I submit it with an empty name and path
    Then I see "can't be blank"
    When I enter path "user_id"
    Then I see "JSONPath must start with '$'"
    And "Create" is disabled
    # keychain_credential.ex:51-80, keychain_credential_form_component.ex:74-81, components/credentials.ex:304; project_live_test.exs:1633-1666

  @S13 @pending
  Scenario: A keychain's default credential must be shared with the project
    # Value: a keychain can't route a run to a secret this project was never given.
    Given credential "DHIS2 prod" is shared with "Malawi HIV"
    And credential "Elsewhere" is not
    When I create a keychain on "Malawi HIV"
    Then the default credential choices are "No default credential" and "DHIS2 prod"
    When I submit it with the id of "Elsewhere" as default anyway
    Then I see "must belong to the same project"
    And no keychain is created
    # keychain_credential_form_component.ex:37-42, components/credentials.ex:282-290, keychain_credential.ex:98-145

  @S14 @pending
  Scenario: Two keychains in a project cannot share a name
    # Value: people choosing a keychain for a job can tell them apart.
    Given "Malawi HIV" has keychain "By district"
    When I create another keychain named "By district" on "Malawi HIV"
    Then I see an error on the name
    And only one "By district" exists
    # keychain_credential.ex:55, priv/repo/migrations/20250709121359_create_keychain_credentials.exs:21

  @S15 @pending
  Scenario: Admin edits a keychain
    # Value: admins can repoint a keychain when the run data or the default secret changes.
    Given "Malawi HIV" has keychain "Original Name" with path "$.org_id"
    When I edit it to name "Updated Name" and path "$.updated_path" and choose "Save changes"
    Then I see "Keychain credential updated successfully"
    And the keychain is stored with the new name and path
    # credential_index_component.ex:272-293, keychain_credential_form_component.ex:121-160; project_live_test.exs:1573-1631

  @S16 @pending
  Scenario: A forged keychain edit from a viewer is refused
    # Value: hiding the action is not the only thing protecting a project's credential routing.
    Given I am a viewer on "Malawi HIV" with keychain "Protected"
    When I send "edit_keychain_credential" for "Protected"
    Then I see "You are not authorized to perform this action"
    And no keychain form is open
    # credential_index_component.ex:272-293, :419-424; project_live_test.exs:1697-1740

  @S17 @pending
  Scenario: Owner schedules a credential for deletion from project settings
    # Value: an owner can retire a secret from where they found it, and the project stops using it at once.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    When I delete "DHIS2 prod" from the "Credentials" tab of "Malawi HIV" and confirm
    Then I am back on the "Credentials" tab with "Credential scheduled for deletion"
    And "DHIS2 prod" is no longer listed on this tab
    And the flow "flow-credential-scheduled-deletion" has started for "DHIS2 prod"
    # credential_index_component.ex:240-254, credential_deletion_modal.ex:40-51, credentials.ex:1036-1052; credential_live_test.exs:541-580

  @S18 @pending
  Scenario: Owner starts a credential transfer from project settings
    # Value: a departing team member can hand over a project's credential without leaving the project.
    Given I own credential "DHIS2 prod" shared with "Malawi HIV"
    When I choose "Transfer" on "DHIS2 prod" on the "Credentials" tab
    Then the transfer modal opens for "DHIS2 prod"
    And submitting it returns me to the "Credentials" tab
    And the flow "flow-credential-transfer" has started for "DHIS2 prod"
    # credential_index_component.ex:256-270, credential_index_component.html.heex:244-251, transfer_credential_modal.ex:46-55, :100

  @S19 @pending
  Scenario: OAuth sign-in started on this tab returns to this tab
    # Value: an editor can connect an OAuth credential for the project without leaving project settings.
    Given I am an editor on "Malawi HIV" and OAuth client "Google" is shared with it
    When I start a new credential of type "Google" on the "Credentials" tab and sign in with the provider
    Then the flow "flow-oauth-credential-authorize" has started
    And the provider's answer is delivered to the credential form on this tab
    # settings.ex:682-686 (handle_info {:forward, ...} -> send_update), credential_form_component.ex:1355-1395
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| A viewer who owns a credential or OAuth client shared with the project gets "Edit" (ownership check) but saving is refused because the form checks the host's `can_create_project_credential` | `credential_index_component.html.heex:22`, `:72`, `:190`, `:211`, `:239`; `credential_form_component.ex:525-541`; `oauth_client_form_component.ex:199-211`; `settings.html.heex:362` | fills in the edit form, then "You are not authorized to perform this action." and a reload; the same edit works on /credentials | fix |
| Empty-state buttons "Create a new Credential", "Create a new OAuth client" and "Create a new keychain credential" are always enabled, while the matching "Add new" options are disabled | `credential_index_component.html.heex:10-19`, `:60-69`, `:122-131` (`button_disabled={false}`); handlers `credential_index_component.ex:91-158` | a viewer (or an editor, for keychains) clicks a live-looking button and gets "You are not authorized to perform this action" | fix |
| Scheduling deletion removes every project share, so the credential disappears from this tab, and "Cancel deletion" and "Delete now" can't be reached here; the owner must go to /credentials | `credentials.ex:1036-1052`, `:106-122`; `credential_index_component.ex:459-490` | the credential vanishes after "Credential scheduled for deletion", with no hint where to undo it | decide |
| "Projects with access" lists every project a credential is shared with, including projects the viewer is not a member of | `credentials.ex:111-116` (preload `:projects`), `credential_index_component.ex:426-441`, `data_tables.ex:79-83` | a viewer learns the names of other projects that use a colleague's secret | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The "Add new" button is never disabled; `new_credential_menu_button` takes `disabled` but never reads it, only the options are disabled | `components/credentials.ex:349-380`; `settings.html.heex:325` | decide |
| Disabled options are `<span>`s with `phx-click={false}` and grey text, with no tooltip saying why | `components/credentials.ex:389-399` | decide |
| Keychain creation is gated three times: host flag for the menu, component flag for `show_modal`, form flag on save, each calling the policy separately | `settings.ex:173-178`; `credential_index_component.ex:41-47`; `keychain_credential_form_component.ex:44-59` | preserve |
| Stale TODO "check if user can create keychain credential" above a check that exists | `credential_index_component.ex:117` | preserve |
| Keychain create and update record no audit event, unlike credentials and OAuth clients | `credentials.ex:1956-2002` | decide |
| The keychain table always shows the creator, and the credential and OAuth client tables show the owner here only because the host passes `show_owner_in_tables={true}` | `settings.html.heex:363`; `credential_index_component.html.heex:119` | preserve |
| Label casing is mixed: menu "OAuth Client" with an "Advanced" badge, tables "OAuth Clients" and "Keychain Credentials", modal "Delete Oauth Client", flash "Oauth client deleted", button "Save Changes" | `settings.html.heex:341-348`; `credential_index_component.html.heex:5`, `:117`; `credential_index_component.ex:210`, `:496`; `components/credentials.ex:308` | decide |
| The keychain unauthorized branches on save are reachable only if role or project state changes between opening and saving the form | `keychain_credential_form_component.ex:138-144`, `:194-200` | preserve |
| A successful keychain save closes the modal by `push_event("close_modal")`, which the ModalHook turns into `close_active_modal` to reload the lists; edits otherwise leave the table stale | `keychain_credential_form_component.ex:132`, `:178`, `:110-114`; `hooks/index.ts:522-530`; `credential_index_component.ex:84-89` | preserve |
| Refusals `push_patch` to `return_to`, which includes `#credentials`; the tests observe the path without the fragment | `credential_index_component.ex:419-424`; `project_live_test.exs:1149-1150` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `selected_credential_type: nil` assign | `settings.ex:214` | nothing in settings reads it; the form keeps its own (`credential_form_component.ex:329`) |
| Keychain form "Back" button and `back_to_advanced_picker` push | `keychain_credential_form_component.ex:109`; `components/credentials.ex:313-319` | renders only with `from_collab_editor`, which this host never sets |
| Credential form advanced picker and keychain pages | `credential_form_component.ex:312-485` | same; listed in credentials-index |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| All project credentials, OAuth clients and keychains load unpaginated on every component update and every modal close | `credential_index_component.ex:60-89` | no, until a project has many credentials | preserve |
| The project picker list is loaded once at mount | `settings.ex:117` | yes, a project joined while the page is open is missing until reload | preserve |

### 6.5 Things seen but not understood

- `oauth_clients_live_test.exs:128-183` (list, empty state) and `:514-560` (delete from this tab) are `@tag :skip`, so OAuth client listing and deletion on this tab have no running coverage; S02 is read from code.
- flow-oauth-credential-authorize section 3 says "Add new" is hidden for a role on project settings; the button is always rendered and enabled, only its options are disabled (`components/credentials.ex:360-380`). The flow file may need a wording fix; not changed here.
- Whether the browser stays on the Credentials tab after a refusal's `push_patch` to `.../settings#credentials` was not verified (see shared-project-settings-tab-chrome S04).
- `project_live_test.exs:1193-1213` checks the keychain option exists for an admin but not that it is disabled for an editor; S08's editor half is read from code.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a viewer who owns a credential be able to save edits to it from project settings, as they can on /credentials (6.1)? (owner: product)
- After scheduling deletion from this tab, should the credential stay visible here with "Cancel deletion" (6.1)?
- Should viewers see the names of other projects a credential is shared with (6.1)?
- Should keychain create, update and delete be audited like credentials (6.2)?
- The keychain form also renders inside the workflow editor's credential form (`credential_form_component.ex:1181-1204`). Should keychain scenarios S11 to S16 move to a shared annotation (see Proposed shared)?

## Proposed flows

none. This view starts flow-credential-transfer (S18), flow-oauth-credential-authorize (S19) and flow-credential-scheduled-deletion (S17), which already exist; each should list project-settings-credentials as an entry surface (flow-credential-scheduled-deletion asks this in its section 8).

## Proposed shared

- `shared-keychain-credential-form` (optional): `KeychainCredentialFormComponent` and `Components.Credentials.keychain_credential_form` (name, JSONPath, default credential, project-scoped validation). Surfaces: project-settings-credentials (catalogued here as its main home, S11 to S16), workflow editor credential modal (`credential_form_component.ex:1181-1204`, `from_collab_editor` pages with "Back").

## Lead resolution (batch 2)

- `shared-keychain-credential-form` declined: this tab stays the home of the keychain form, as credentials-index is for the credential form. The editor references this file.
- flow-credential-transfer, flow-oauth-credential-authorize and flow-credential-scheduled-deletion now list this view as an entry surface.
