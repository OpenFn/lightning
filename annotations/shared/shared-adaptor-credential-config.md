---
id: shared-adaptor-credential-config
type: shared
title: Adaptor and credential configuration
status: not-started
owner:

trigger:
  old_route: rendered inside /projects/:project_id/w/:id by the step inspector (JobForm), the IDE header (FullScreenIDE) and, picker only, the canvas plus button (WorkflowDiagram)
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - workflow-editor-inspectors renders AdaptorDisplay, ConfigureAdaptorModal and AdaptorSelector for the selected step (JobForm.tsx:351-400); the inspector is keyed per job, so each step gets fresh dialog state (inspector/index.tsx:120-127)
    - workflow-editor-ide renders the same three for the IDE's current job (FullScreenIDE.tsx:849-862, :1344-1389); one instance survives job switches (WorkflowEditor.tsx:373-379)
    - workflow-editor-canvas renders AdaptorSelectionModal alone, while a new step is pending from a plus button or a dragged path (WorkflowDiagram.tsx:198-204, :1016-1021)
    - the Change and Edit or Connect entry buttons render only when the host says the workflow is not read-only (AdaptorDisplay.tsx:182, :263); the dialogs themselves check nothing
    - the LiveView credential form renders only after an `open_credential_modal` event the server accepts (collaborate.ex:145-187, :289-324)

inherits:
  - shared-editor-session        # lead-created; Y.Doc writes, the server write gate, read-only states, the save that persists adaptor and credential ids, and the credentials_updated / adaptors_updated channel forwarders (workflow_channel.ex:950-960)

url_params: []                   # none read; hosts own job, panel and the rest

config_variants:
  default: {}                    # everything below was read under this variant; nothing in scope branches on config

inventory:
  routes: []                     # host route /projects/:project_id/w/:id is owned by the editor views
  events:
    - WorkflowLive.Collaborate#open_credential_modal          # collaborate.ex:145-187
    - WorkflowLive.Collaborate#credential_modal_closed        # collaborate.ex:198-209
    - WorkflowLive.Collaborate#close_credential_modal         # collaborate.ex:189-196; no caller (6.3)
    - WorkflowLive.Collaborate handle_info {:credential_saved, _}   # collaborate.ex:393-430
    - WorkflowLive.Collaborate handle_info :clear_credential_page, {:update_credential_schema, _}, {:update_selected_credential_type, _}, {:back_to_advanced_picker}   # collaborate.ex:356-386
    - CredentialFormComponent#show_advanced_picker, #select_credential_type_option, #continue_from_advanced_picker, #cancel_advanced_picker, #back_to_advanced_picker_from_second, #back_to_advanced_picker_from_keychain, #validate_keychain, #save_keychain   # credential_form_component.ex:312-485; the "Advanced" button and keychain option render only with from_collab_editor (:1038-1046, :1366-1377)
    - WorkflowChannel "request_credentials"                   # workflow_channel.ex:119-132
    - push credential_saved, credential_modal_closed, close_credential_modal (collaborate.ex:176, :203, :419-420)
  js_hooks:
    - CredentialModalContext handleEvent "credential_saved", "credential_modal_closed" (CredentialModalContext.tsx:187-228)
    - ModalHook close_modal (hooks/index.ts:522-530), which turns a new-credential save into credential_modal_closed (helpers.ex:160-163; modal.ex:31-37)
    - keyboard Escape at priority 100 in AdaptorSelectionModal (AdaptorSelectionModal.tsx:59-66), ConfigureAdaptorModal (ConfigureAdaptorModal.tsx:230-237) and the credential modal blocker (CredentialModalContext.tsx:110-118); at 110 for the adaptor change confirmation (AdaptorSelector.tsx:78-85)
    - keyboard ArrowUp, ArrowDown, Enter in the adaptor search (AdaptorSelectionModal.tsx:163-183)
  react_components:
    - components/AdaptorSelectionModal.tsx
    - components/AdaptorSelector.tsx and hooks/useAdaptorChangeConfirmation.ts
    - components/ConfigureAdaptorModal.tsx and components/VersionPicker.tsx
    - components/AdaptorDisplay.tsx and constants/adaptors.ts
    - contexts/CredentialModalContext.tsx
    - hooks/useAdaptors.ts, stores/createAdaptorStore.ts, hooks/useCredentials.ts, stores/createCredentialStore.ts
  policies:
    - Lightning.Policies.Users :edit_credential (users.ex:40-44; collaborate.ex:156-162)
    - Lightning.Policies.ProjectUsers :create_project_credential (project_users.ex:39-49, :132-158; collaborate.ex:316-323; credential_form_component.ex:525-542)
    - Lightning.Policies.Credentials :create_keychain_credential (policies/credentials.ex:32-38, :51-67, :87-98; credentials.ex:1956-1971)
  workers: []
  api_endpoints:
    - get /adaptors/catalogue  AdaptorController :index (router.ex:155-160; adaptor_controller.ex:21-49); read here, owned by a capability not yet written (INVENTORY.md:112)
  emails: []
  config: []
  not_reachable_here:
    - CredentialFormComponent standard pages, GenericOauthComponent and the OAuth callback; owned by credentials-index, project-settings-credentials and flow-oauth-credential-authorize (this file asserts only that the form opens)
    - KeychainCredentialFormComponent; the editor builds keychains through CredentialFormComponent's own keychain page (credential_form_component.ex:1181-1204)
    - Adaptor catalogue loading, the Adaptors.ChannelBroadcaster and the adaptors_updated PubSub source (channel_broadcaster.ex:58-80); see Proposed flows

related:
  - workflow-editor-inspectors           # host (JobForm); its S04 to S15 move here
  - workflow-editor-ide                  # host (IDE header); its credential-connect scenario moves here
  - workflow-editor-canvas               # host of the picker only (new step)
  - credentials-index                    # home of the credential form
  - project-settings-credentials         # home of the keychain form
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/live/credential_live/credential_form_component.ex
  - lib/lightning_web/controllers/adaptor_controller.ex
  - lib/lightning/adaptors/catalogue.ex
  - assets/js/collaborative-editor/components/{AdaptorSelectionModal,AdaptorSelector,ConfigureAdaptorModal,VersionPicker,AdaptorDisplay}.tsx
  - assets/js/collaborative-editor/contexts/CredentialModalContext.tsx
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - assets/test/collaborative-editor/components/{AdaptorSelectionModal,ConfigureAdaptorModal}.test.tsx
flows:
  - flow-oauth-credential-authorize      # starts from the credential form opened here; only the handoff is asserted
---

## 1. Purpose

Every step in a workflow runs one adaptor, at one version, with at most one credential. People
building a workflow choose those three in the same dialogs whether they start from the canvas, the
step inspector or the code editor, and can create the credential they need without leaving the
workflow. Get this wrong and a step sends one system's secret to another, breaks when a new
adaptor release ships, or runs with a credential its builder had no right to change.

## 2. What it does

- **See how a step connects**
  - Anyone on the project sees a step's adaptor, version and credential, and whether the credential is missing or gone
- **Choose the adaptor and version** (editors)
  - Pick an adaptor from the catalogue by search or keyboard, with HTTP suggested when nothing matches
  - Get warned that changing a step's adaptor clears its credential, and back out if they want
  - Pin the step to an adaptor version or leave it on latest
- **Choose the credential** (editors)
  - Pick or clear a step's credential, either a project credential or a keychain, with ones matching the adaptor offered first
- **Create or edit credentials without leaving the step**
  - Editors create a credential and have it attached to the step when saved
  - Only a credential's owner can open it for editing from the step
  - Admins create keychain credentials from the step; others cannot
- **Step back through the dialogs**
  - Escape and Back close one dialog at a time and return to the one beneath

**Straightforwardness: 2 of 5.** The happy path is simple, but the stacked dialogs, the link to the credential form and the way choices are saved later produce several outcomes you'd only predict after careful thought.

### Most surprising behaviours

- **(2)** Editing a credential that's shared with several projects, or unticking this project in the form, may leave the step showing "Not found" and the workflow refusing to save. (6.1, S16)
- **(2)** In the code editor, opening "Configure connection" after switching to a step with a different adaptor may quietly change that step's version to the newest numbered release. (6.1)
- **(2)** After editing a credential or creating a keychain, the page seems to think a dialog is still open: Escape stops closing the step panel or the code editor, and "Configure connection" doesn't come back. (6.1)
- **(3)** Viewers and editors are offered "Keychain" in the advanced credential setup, but when they save, nothing happens and nothing tells them why. (6.1, S15)
- **(3)** Saving an edit to any credential in the list also makes it the step's credential, even if the step was using a different one. (6.2)

## 3. Who can do what

Sources: `project_users.ex:39-49` (`:edit_workflow` and `:create_project_credential` are editor
actions), `:132-158` (MFA unsatisfied denies all; support with no row counts when support access is
on); `users.ex:40-44` (credential edit by its owner only); `policies/credentials.ex:32-38`,
`:87-98` (keychain create: owner, admin, or support access, MFA required). The UI gate on the entry
buttons is the host's read-only flag (`AdaptorDisplay.tsx:182`, `:263`); document writes are
gated server side by shared-editor-session.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|------------------------------|
| See adaptor, version and credential badge | yes | yes | yes | yes | no (no project access) | yes |
| Change adaptor, version or credential | no | yes | yes | yes | no | yes |
| Save a new credential from a step | no | yes | yes | yes | no | yes |
| Edit a credential from a step | owner of that credential only | same | same | same | no | same |
| Create a keychain credential from a step | no | no | yes | yes | no | yes |

**Preconditions beyond role**
- A member who has not met the project's MFA requirement is denied every action (`project_users.ex:134`; `policies/credentials.ex:87-98`).
- Read-only states (deleted workflow, pinned version, new unsaved workflow, live-workflow lock) hide the entry buttons; they belong to shared-editor-session.
- The edit pencil appears only on project credentials that have an owner, and is enabled only for that owner (`ConfigureAdaptorModal.tsx:108-143`, `:458-465`); keychain rows have none.
- A credential saved on a step must belong to the workflow's project, whatever the shared document says (`workflows.ex:416-428`; `job.ex:117-127`, `:175-200`).

## 4. What it touches

**Reads**: adaptor catalogue (`adaptors`, `adaptor_versions`, non-deprecated only; `catalogue.ex:262-300`, `:332-337`) over `GET /adaptors/catalogue`; `project_credentials`, `credentials`, `keychain_credentials`, `users` (owner), `oauth_clients` (`workflow_channel.ex:119-132`); `credentials` by id for an edit (`collaborate.ex:153-164`); the step's `adaptor`, `project_credential_id`, `keychain_credential_id` from the shared document.

**Writes**
- Shared document only, persisted by the workflow save in shared-editor-session: job `adaptor` (`useAdaptorChangeConfirmation.ts:96-108`, `:119-153`; `JobForm.tsx:234-251`; `FullScreenIDE.tsx:627-643`) and the exclusive pair `project_credential_id` / `keychain_credential_id` (`JobForm.tsx:254-298`, `:129-165`; `FullScreenIDE.tsx:646-708`).
- Database, immediately, through the credential form: `credentials` and `project_credentials` (`credential_form_component.ex:1255-1305`), `keychain_credentials` (`credentials.ex:1956-1971`).

**Immediate side effects** (in the same request)
- `push_event` `credential_saved` with `{credential: {id, name, schema, project_credential_id?}, is_project_credential}` (`collaborate.ex:411-419`, `:473-517`)
- PubSub `workflow:collaborate:<workflow_id>` `credentials_updated` with the full project and keychain list (`collaborate.ex:519-532`), forwarded by the channel (`workflow_channel.ex:950-954`)
- `push_event` `credential_modal_closed` after a cancel, a refused edit, or a new-credential save via `close_modal` (`collaborate.ex:176`, `:198-209`; `helpers.ex:160-163`; `hooks/index.ts:522-530`)

**Deferred side effects** (later, elsewhere)
- The chosen adaptor and credential reach `jobs` only at the next workflow save (shared-editor-session)

**External, non-transactional effects**
- OAuth authorization with a provider, when the new credential is an OAuth one (flow-oauth-credential-authorize)

**Depends on config**
- none

**Product limits** (limits a user would notice and that we intend to keep)
- A step holds at most one credential: a project credential or a keychain, never both (`job.ex:117-120`)
- Deprecated adaptors, deprecated versions and four internal packages are never offered (`catalogue.ex:52-55`, `:290-293`, `:332-337`)

## 5. Scenarios

```gherkin
Feature: Adaptor and credential configuration
  In order to say which system a step talks to, with which release and which secret
  As someone building a workflow
  I want one set of dialogs for adaptor, version and credential wherever I edit a step

  Background:
    Given project "Malawi HIV" has workflow "Intake" with a step "Fetch"
    And I have "Fetch" open in the step inspector or the IDE

  @S01 @pending
  Scenario Outline: A step without a credential is flagged when its adaptor needs one
    # Value: a step that would fail for want of a credential is spotted before it runs.
    Given "Fetch" uses <adaptor> and has no credential
    Then the adaptor box offers "<button>"
    # AdaptorDisplay.tsx:89-93, :263-281; constants/adaptors.ts:2-12; JobForm.test.tsx:325-399

    Examples:
      | adaptor                       | button  |
      | @openfn/language-dhis2@latest | Connect |
      | @openfn/language-http@latest  | Edit    |

  @S02 @pending
  Scenario: A step whose credential has gone says so
    # Value: a step pointing at a deleted or inaccessible credential is noticed before it runs.
    Given "Fetch" references a project credential that is not in the project's credential list
    Then the adaptor box shows "Not found" with "Credential not found. It may have been deleted or you no longer have access."
    # AdaptorDisplay.tsx:85-90, :242-261; createCredentialStore.ts:157-177

  @S03 @pending
  Scenario: Picking a credential attaches it to the step, and only one kind at a time
    # Value: the step runs with the secret the builder chose, and never with two.
    Given "Fetch" uses the DHIS2 adaptor
    And the project has DHIS2 credential "DHIS2 prod" and keychain "Per facility"
    When I open "Configure connection" and choose "DHIS2 prod"
    Then "Fetch" shows a "DHIS2 prod" credential badge
    And the step's project credential is set and its keychain credential is empty
    When I choose "Per facility" under "Other credentials"
    Then the step's keychain credential is set and its project credential is empty
    When I clear the selection
    Then "Fetch" has no credential
    # ConfigureAdaptorModal.tsx:631-711; JobForm.tsx:254-298; FullScreenIDE.tsx:646-680; job.ex:117-120
    # ConfigureAdaptorModal.test.tsx:1002-1060, :1124-1140, :1544-1569

  @S04 @pending
  Scenario: Credentials that match the adaptor are offered first
    # Value: it is harder to send one system's secret to another.
    Given "Fetch" uses the Salesforce adaptor
    And the project has a Salesforce credential, a raw credential and a keychain credential
    When I open "Configure connection"
    Then I see only the Salesforce credential
    When I click "Other credentials"
    Then I see the raw one under "Generic Credentials" and the keychain under "Keychain Credentials"
    # ConfigureAdaptorModal.tsx:286-345, :350-388, :652-731; ConfigureAdaptorModal.test.tsx:443-500, :765-905

  @S05 @pending
  Scenario: Changing adaptor on a step with a credential asks first and clears it
    # Value: a credential meant for one system is never sent to another by accident.
    Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
    When I pick "DHIS2" again in the adaptor picker
    Then no warning appears, "Configure connection" opens and "DHIS2 prod" is still selected
    When I pick "Salesforce" in the adaptor picker
    Then I see "Change Adaptor?" warning that the credential will be reset
    When I click "Continue"
    Then "Fetch" uses Salesforce and has no credential
    And "Configure connection" opens
    # useAdaptorChangeConfirmation.ts:63-117, :119-153; AdaptorSelector.tsx:89-105

  @S06 @pending
  Scenario: Backing out of an adaptor change keeps everything as it was
    # Value: a mis-click in the picker costs nothing.
    Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
    When I pick "Salesforce" and then click "Cancel" on the warning
    Then "Fetch" still uses DHIS2 with "DHIS2 prod"
    And the adaptor picker is open again
    # useAdaptorChangeConfirmation.ts:158-167; AdaptorSelector.tsx:69-85

  @S07 @pending
  Scenario: A step can be pinned to an adaptor version
    # Value: a step keeps behaving the same when a new adaptor release ships.
    Given the DHIS2 adaptor has versions "4.2.0", "4.10.0" and "4.9.1"
    When I open "Configure connection" on "Fetch"
    Then the version list reads "latest", "4.10.0", "4.9.1", "4.2.0"
    When I choose "4.9.1"
    Then "Fetch" shows "v4.9.1"
    # ConfigureAdaptorModal.tsx:32-47, :416-427, :563-573; VersionPicker.tsx:30-36, :67-71; JobForm.tsx:234-251; FullScreenIDE.tsx:627-643
    # ConfigureAdaptorModal.test.tsx:405-440

  @S08 @pending
  Scenario: Searching for an adaptor that does not exist suggests HTTP
    # Value: a builder can still connect to a system that has no dedicated adaptor.
    When I search the adaptor picker for "zzz-unknown"
    Then I see "No adaptor found" and the HTTP adaptor
    When I press Enter
    Then the HTTP adaptor is chosen
    # AdaptorSelectionModal.tsx:95-146, :163-183, :264-275; AdaptorSelectionModal.test.tsx:299-318

  @S09 @pending
  Scenario: A catalogue that has not loaded can be retried
    # Value: a transient failure does not look like "there are no adaptors".
    Given the adaptor catalogue answers 503 "adaptor catalogue unavailable"
    When I open the adaptor picker
    Then I see "Couldn't load adaptors. Please try again." and "Retry"
    When the catalogue becomes available and I click "Retry"
    Then the adaptor list appears
    # AdaptorSelectionModal.tsx:35-40, :229-255; createAdaptorStore.ts:308-321; adaptor_controller.ex:38-48
    # AdaptorSelectionModal.test.tsx:149-190

  @S10 @pending
  Scenario: Retired adaptors and versions are not offered
    # Value: builders are not steered onto a release the maintainers have withdrawn.
    Given the DHIS2 adaptor's version "4.1.0" is deprecated and adaptor "@openfn/language-old" is deprecated
    When I open the adaptor picker and "Configure connection" for a DHIS2 step
    Then "@openfn/language-old" is not listed and "4.1.0" is not in the version list
    # catalogue.ex:262-300, :332-337; ConfigureAdaptorModal.tsx:416-427

  @S11 @pending
  Scenario: A credential created from a step is attached to it
    # Value: a builder connects a step to a new system without leaving the editor.
    Given I am an editor and "Fetch" uses DHIS2
    When I click "New Credential" in "Configure connection"
    Then the credential form opens with the DHIS2 schema and "Malawi HIV" preselected
    When I save a DHIS2 credential "DHIS2 test"
    Then "Fetch" has "DHIS2 test" as its project credential
    And "Configure connection" opens again with "DHIS2 test" selected
    And "credentials_updated" is broadcast on "workflow:collaborate:<Intake id>"
    # ConfigureAdaptorModal.tsx:441-446, :592-601; CredentialModalContext.tsx:121-136, :187-228
    # collaborate.ex:80-81, :180-187, :289-324, :393-430, :519-532; helpers.ex:160-163
    # JobForm.tsx:121-165; FullScreenIDE.tsx:682-708; collaborate_test.exs:267-335
    # Collaborators receiving the list is flow-editor-credentials-broadcast (proposed); an OAuth client hands off to flow-oauth-credential-authorize

  @S12 @pending
  Scenario: A viewer cannot save a credential from the editor
    # Value: read-only members cannot add secrets to a project.
    Given I am a viewer on "Malawi HIV"
    When "open_credential_modal" is sent with schema "raw" and I submit the form
    Then no credential is created
    # collaborate.ex:180-187, :316-323; credential_form_component.ex:525-542; collaborate_test.exs:772-818

  @S13 @pending
  Scenario: Only a credential's owner can edit it from a step
    # Value: a credential's secrets are only changed by the person responsible for them.
    Given "DHIS2 prod" is owned by "amara@example.org" and shared with "Malawi HIV"
    When I open "Configure connection" on "Fetch"
    Then the edit button on "DHIS2 prod" is disabled with "This credential can only be edited by the owner: amara@example.org"
    When "open_credential_modal" is sent with the id of "DHIS2 prod"
    Then no credential form opens and nothing of "DHIS2 prod" is rendered
    And "credential_modal_closed" is pushed back and "Configure connection" reopens
    # ConfigureAdaptorModal.tsx:108-143, :449-465; collaborate.ex:145-178; users.ex:40-44; CredentialModalContext.tsx:207-228
    # collaborate_test.exs:998-1057; ConfigureAdaptorModal.test.tsx:1319-1440

  @S14 @pending
  Scenario: An admin creates a keychain credential from a step
    # Value: an admin can set up a credential that is chosen per run without leaving the workflow.
    Given I am an admin on "Malawi HIV"
    When I open a new credential from "Fetch", click "Advanced", choose "Keychain" and save "Per facility" with path "$.facility_id"
    Then the keychain credential exists on "Malawi HIV"
    And "Fetch" has "Per facility" as its keychain credential
    # credential_form_component.ex:312-366, :461-472, :1038-1046, :1181-1204, :1366-1377; collaborate.ex:393-430, :486-517
    # collaborate_test.exs:1756-1828

  @S15 @pending
  Scenario: People below admin cannot create a keychain credential from a step
    # Value: per-run credential selection, which can reach any project credential, stays with admins.
    Given I am a viewer on "Malawi HIV"
    When I submit a keychain credential "Planted" from the step's advanced credential setup
    Then no keychain credential "Planted" exists
    # credentials.ex:1956-1971; policies/credentials.ex:32-38, :87-98; collaborate_test.exs:1829-1873
    # Only the viewer case is tested; an editor is refused by the same policy clause (policies/credentials.ex:91-93)

  @S16 @pending
  Scenario: A step cannot be saved with another project's credential
    # Value: one project's secrets never run in another project's workflow.
    Given the shared document points "Fetch" at a project credential belonging to project "Kenya TB"
    When the workflow is saved
    Then the save is refused with "credential doesn't exist or isn't available in this project" on "Fetch"
    # workflows.ex:416-428, :434-455; scoping.ex:116-117; job.ex:121-127, :175-200

  @S17 @pending
  Scenario: Escape and Back close one dialog at a time
    # Value: dismissing a dialog never also throws away the step panel or the code editor behind it.
    Given "Configure connection" is open over "Fetch"
    When I click "New Credential" and then press Escape in the credential form
    Then the credential form closes and "Configure connection" is shown again
    When I click "Change", pick "Salesforce" and press Escape on "Change Adaptor?"
    Then the adaptor picker is shown
    When I press Escape
    Then the picker closes and "Fetch" is still open
    # CredentialModalContext.tsx:110-118, :207-228; modal.ex:63-67; collaborate.ex:198-209, :312
    # AdaptorSelector.tsx:64-85; AdaptorSelectionModal.tsx:59-66; ConfigureAdaptorModal.tsx:230-237
    # JobForm.tsx:121-127, :384-394; FullScreenIDE.tsx:682-687, :710-727, :1373-1382
    # The step panel's own Escape is workflow-editor-inspectors; the IDE's is workflow-editor-ide

  @S18 @pending
  Scenario: Read-only viewers see the configuration but cannot change it
    # Value: nobody starts a change they are not allowed to save.
    Given I am a viewer on "Malawi HIV" and "Fetch" uses DHIS2 with "DHIS2 prod"
    Then I see the DHIS2 adaptor, its version and a "DHIS2 prod" badge
    And I see no "Change adaptor", "Edit" or "Connect" button
    # AdaptorDisplay.tsx:182-205, :215-241, :263; JobForm.tsx:59, :351-358; FullScreenIDE.tsx:849-862
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| Editing a credential or creating a keychain never yields `credential_modal_closed`: only a new-credential save pushes `close_modal` (which the ModalHook turns into the close event); edit and keychain saves do not, and the server's own `close_credential_modal` push has no listener. The React modal state stays open | `credential_form_component.ex:1255-1289`, `:461-472`; `helpers.ex:160-163`; `collaborate.ex:417-429`; `CredentialModalContext.tsx:110-118`, `:207-228` | inspector: Escape stops closing the step panel; IDE: Escape and Ctrl/Cmd+E stop closing the IDE (`FullScreenIDE.tsx:723-726`) and "Configure connection" does not come back (not run) | fix |
| The saved-credential payload takes the credential's first `project_credentials` row, whatever its project; a credential saved without this project is reported as non-project and its credential id is written as `keychain_credential_id` | `collaborate.ex:402-409`, `:486-497`, `:512-516`; `JobForm.tsx:131-153`; `FullScreenIDE.tsx:691-702` | after editing a credential shared with several projects, or deselecting this project in the form, the step shows "Not found" and the save is refused (S16) (not run) | fix |
| `:clear_credential_page` reads `original_credential_schema` from the LiveView's assigns, but only the component sets it | `collaborate.ex:356-363`; `credential_form_component.ex:312-317`, `:410-416` | after "Cancel" from the advanced picker the page's `credential_schema` becomes nil and the form may re-render without its schema (not run) | fix |
| Refusals from the editor's credential form put the flash on the component socket; the advanced picker offers "Keychain" to everyone | `credential_form_component.ex:474-480`, `:529-541`, `:1366-1377`; `collaborate_test.exs:1866-1872` | a viewer saving a credential, or an editor or viewer saving a keychain, clicks save and nothing happens | fix |
| "Adaptors in this project" lists only adaptors used by this workflow's steps | `AdaptorSelectionModal.tsx:277-278`; `useAdaptors.ts:126-167` | adaptors used in the project's other workflows appear under "All adaptors"; copy does not match the list | fix |
| A failed credential request leaves the list empty and the error unread (`useCredentialsError` has no caller) | `createCredentialStore.ts:323-348`; `ConfigureAdaptorModal.tsx:610-624`; `useCredentials.ts:49-55` | "No credentials found in this project" when the request failed (not run) | fix |
| In the IDE the dialog is not reset when the job changes, so its "adaptor changed" check compares against the previous job | `ConfigureAdaptorModal.tsx:241-276`; `FullScreenIDE.tsx:508-519`, `:1345-1371`; `WorkflowEditor.tsx:373-379` | opening "Configure connection" after switching to a job with a different adaptor rewrites that job's version to the newest numbered release (not run) | fix |
| IDE metadata is fetched for the job as saved, but cached under the unsaved adaptor and credential this dialog just wrote | `workflow_channel.ex:135-170`; `createMetadataStore.ts:269-294`; `useMetadata.ts:66-82` | after changing adaptor or credential without saving, the old adaptor's metadata or "No metadata found", with no refresh; carried from workflow-editor-ide 6.1 | fix |
| Jobs given a keychain credential here get no metadata: the server follows only `project_credential` | `job.ex:55-58`; `metadata_service.ex:80-89` | "No metadata found" in the IDE for keychain steps; carried from workflow-editor-ide 6.1 | decide |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Saving an edit to any credential row also selects that credential for the step | `JobForm.tsx:129-153`; `FullScreenIDE.tsx:689-708`; `ConfigureAdaptorModal.tsx:449-455` | decide |
| A changed adaptor is written as `@latest`, then opening "Configure connection" pins it to the newest numbered version; a new step from the canvas gets the numbered latest straight away | `useAdaptorChangeConfirmation.ts:98`, `:127`; `ConfigureAdaptorModal.tsx:241-259`; `AdaptorSelectionModal.tsx:153-160`; `WorkflowDiagram.tsx:772-779` | decide |
| "Configure connection" clears a credential that no longer exists when the adaptor changes | `ConfigureAdaptorModal.tsx:261-264`; `ConfigureAdaptorModal.test.tsx:1828` | preserve |
| "This adaptor does not require credentials" is shown only for common, while the adaptor box treats http, testing, ping and the fhir adaptors as not needing one | `ConfigureAdaptorModal.tsx:279-283`, `:604-609`; `AdaptorDisplay.tsx:91-93`; `constants/adaptors.ts:2-12` | decide |
| HTTP treats every OAuth credential as matching; other adaptors match OAuth by client name substring, ignoring spaces, hyphens and underscores | `ConfigureAdaptorModal.tsx:297-319` | preserve |
| Keychain credentials are never filtered by adaptor and always sit under "Other credentials" | `ConfigureAdaptorModal.tsx:338-342` | preserve |
| `credentials_updated` goes to this workflow's topic only; editors open on other workflows of the project do not refresh | `collaborate.ex:527-531` | decide |
| Every change is written to the shared document as it is made; the dialog has only "Close" | `ConfigureAdaptorModal.tsx:640-641`, `:738-750`; `JobForm.tsx:233-298` | preserve |
| The credential form opened from the editor offers only the current project and preselects it | `collaborate.ex:80-81`, `:296-304` | preserve |
| The dialogs have no read-only check of their own; only the entry buttons are hidden, and the IDE uses `useWorkflowReadOnly` there while its code editor uses `useCanSave` | `AdaptorDisplay.tsx:182`, `:263`; `FullScreenIDE.tsx:861` | decide |
| The step inspector reopens "Configure connection" twice after a new-credential save (once from `credential_saved`, once from `credential_modal_closed`); the IDE only from the second | `JobForm.tsx:121-165`; `FullScreenIDE.tsx:682-708` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `push_event("close_credential_modal")` | `collaborate.ex:420` | no JS listener |
| `handle_event("close_credential_modal")` | `collaborate.ex:189-196` | nothing pushes it |
| `handle_info({:back_to_advanced_picker})` | `collaborate.ex:380-386` | nothing sends it |
| `credential_page` and `selected_credential_type_for_picker` assigns | `collaborate.ex:356-378` | never read in render |
| `ConfigureAdaptorModal` `onAdaptorChange`, `JobForm` `handleAdaptorChange`, IDE `handleAdaptorChange` | `ConfigureAdaptorModal.tsx:188`, `:209-210`; `JobForm.tsx:213-231`; `FullScreenIDE.tsx:607-624` | adaptor changes go through the picker instead |
| `handleCancelAdaptorChange` | `useAdaptorChangeConfirmation.ts:170-172` | no caller |
| `credentials_list` channel listener | `createCredentialStore.ts:290-293`, `:302` | the server never pushes `credentials_list` |
| `useCredentialsError` | `useCredentials.ts:49-55` | no caller (6.1) |
| Commented-out credential display in JobForm and pulse in AdaptorDisplay | `JobForm.tsx:300-325`; `AdaptorDisplay.tsx:95-100`, `:282-288` | commented out |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Credential callbacks wait 200 ms for the modal close animation | `CredentialModalContext.tsx:18`, `:195-199`, `:221-224` | no | preserve |
| Catalogue served with an ETag, `private, no-cache`, 304 when unchanged; 503 with `retry-after: 5` before the first load | `adaptor_controller.ex:21-48` | only as the retry state (S09) | preserve |
| Catalogue refetched on every channel (re)connect and on each `adaptors_updated`, which is debounced 250 ms | `createAdaptorStore.ts:272-301`; `channel_broadcaster.ex:18`, `:58-80` | no | preserve |
| Credential lists scroll after a fixed height | `ConfigureAdaptorModal.tsx:630`, `:658`, `:687` | yes | preserve |

### 6.5 Things seen but not understood

- The Playwright specs `job-inspector-configuration.spec.ts` and `collaborative-editor-credentials.spec.ts` drive a `select[name="credential_id"]` and a "Configure Your Adaptor" title that the current dialogs do not render; they look stale and were not used as evidence.
- `ConfigureAdaptorModal.test.tsx:1677-1775` is named "edits a credential from keychain credentials section" but keychain rows have no edit button.
- `{:update_credential_schema, _}` re-renders the form with a new schema from the parent while the component comment says internal state is protected from it (`credential_form_component.ex:73`; `collaborate.ex:365-371`); not traced further since the form belongs to credentials-index.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. Should a newly picked adaptor stay on "latest" or be pinned to the numbered release, and should the canvas and the inspector agree (6.2)?
2. Should keychain creation be offered in the editor to people who cannot save it (6.1)?
3. Should a credential created in one workflow's editor reach editors open on the project's other workflows (6.2)?
4. Lead cleanup: workflow-editor-inspectors S04 to S15 and workflow-editor-ide's "Connecting a credential from the IDE" scenario duplicate S01 to S15 here, and the two metadata rows in workflow-editor-ide 6.1 are carried here; one copy should go.

## Proposed flows

- `flow-editor-credentials-broadcast`: a credential saved from one editor (S11, S14) is broadcast as `credentials_updated` on `workflow:collaborate:<id>` (`collaborate.ex:519-532`), forwarded by every joined channel (`workflow_channel.ex:950-954`) and lands in collaborators' "Configure connection" lists (`createCredentialStore.ts:295-303`). Surfaces: workflow-editor-inspectors or workflow-editor-ide, `pubsub:workflow:collaborate:<id>`, the same views in a second tab. This file asserts only the broadcast.
- `flow-adaptor-catalogue-refresh`: an adaptor publish reaches `Adaptors.ChannelBroadcaster`, which broadcasts `adaptors_updated` (`channel_broadcaster.ex:58-80`); the channel forwards it (`workflow_channel.ex:957-960`) and open pickers refetch `/adaptors/catalogue` (`createAdaptorStore.ts:278-286`). Surfaces: the adaptor catalogue capability (not yet written), `pubsub:adaptors_updated`, the three editor hosts. This file asserts nothing of it.

## Proposed shared

none. `shared-editor-session` is referenced in `inherits` as lead-created; no file for it existed in `annotations/shared/` when this was written.
