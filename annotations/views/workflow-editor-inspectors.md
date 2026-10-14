---
id: workflow-editor-inspectors
type: view
title: Workflow editor › Inspector panels (step, trigger, path, workflow settings, code, publish template)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id with ?job=<id>, ?trigger=<id>, ?edge=<id>, ?panel=settings, ?panel=code or ?panel=publish-template
  new_route:                                  # open question 1
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (collaborate.ex:25, see shared-project-scope)
    - the workflow belongs to the project (collaborate.ex:26)
    - the page is an existing workflow, not /w/new; on /new the inspector is blocked whatever the URL says (WorkflowEditor.tsx:284-291)
    - the run panel is not open; it replaces the inspector slot (WorkflowEditor.tsx:333-349)
    - for a node panel, the id in the URL resolves to a job, trigger or edge in the current Y.Doc; otherwise nothing renders (useWorkflow.tsx:271-299; inspector/index.tsx:42-54, :77-78)

inherits:
  - shared-authenticated-session      # :default live_session (router.ex:302-303)
  - shared-project-scope              # on_mount :project_scope (collaborate.ex:25)
  - shared-usage-limits-banner        # on_mount :check_limits and the :banner slot (collaborate.ex:27, :238-242)
  - shared-webhook-auth-method-form   # create-only host, opened from the trigger's Authentication section (collaborate.ex:211-233, :326-352)
  - shared-editor-session
  - shared-adaptor-credential-config
  - shared-run-retry-controls
  - shared-workflow-yaml-format
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: job
    set_by: workflow-editor-canvas (node click), workflow-editor-ide (closing returns here), flow-open-run-in-editor links
    effect: opens the step inspector for that job (useWorkflow.tsx:271-287; inspector/index.tsx:119-129)
  - name: trigger
    set_by: workflow-editor-canvas (node click)
    effect: opens the trigger inspector (useWorkflow.tsx:288-291; inspector/index.tsx:131-140)
  - name: edge
    set_by: workflow-editor-canvas (edge click)
    effect: opens the path inspector (useWorkflow.tsx:292-294; inspector/index.tsx:142-150)
  - name: (precedence)
    set_by: n/a
    effect: job wins over trigger, trigger over edge (useWorkflow.tsx:272, :283-294); panel=settings, code or publish-template win over any node (inspector/index.tsx:44-54)
  - name: panel=settings
    set_by: workflow-editor-canvas header settings button, which toggles it (Header.tsx:717); this panel's Escape from the code view (inspector/index.tsx:57-59)
    effect: opens workflow settings (inspector/index.tsx:81-91)
  - name: panel=code
    set_by: workflow settings "View your workflow as YAML code" (WorkflowSettings.tsx:38-40, :115-122); Back from publish template (TemplatePublishPanel.tsx:168-171)
    effect: opens the YAML code view (inspector/index.tsx:94-104)
  - name: panel=publish-template
    set_by: code view publish button (CodeViewPanel.tsx:78-80)
    effect: opens the template publish form (inspector/index.tsx:107-117)
  - name: panel=editor
    set_by: this view (step inspector Code button, Mod+E)
    effect: exit to workflow-editor-ide (JobInspector.tsx:411-416; WorkflowEditor.tsx:318-325)

config_variants:
  default: {}                                                              # read under this variant
  experimental-features: { user.preferences.experimental_features: true }  # a live workflow is content-locked (workflow_channel.ex:1507-1510; useWorkflow.tsx:1096-1102)
  # Data state rather than config, named in Given steps: user.support_user (publish template), project.concurrency (settings limit).

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit   # owned by workflow-editor-canvas; panels are query params on it
  events:
    - WorkflowLive.Collaborate#open_credential_modal (collaborate.ex:145-187)
    - WorkflowLive.Collaborate#close_credential_modal (collaborate.ex:189-196)
    - WorkflowLive.Collaborate#credential_modal_closed (collaborate.ex:198-209)
    - WorkflowLive.Collaborate#open_webhook_auth_modal (collaborate.ex:211-223)
    - WorkflowLive.Collaborate#close_webhook_auth_modal_complete (collaborate.ex:225-233)
    - WorkflowLive.Collaborate handle_info {:credential_saved, _} (collaborate.ex:393-430)
    - WorkflowLive.Collaborate handle_info :webhook_auth_method_saved (collaborate.ex:432-443)
    - WorkflowLive.Collaborate handle_info {:update_credential_schema, _}, :clear_credential_page (collaborate.ex:356-371)
    - CredentialFormComponent#show_advanced_picker, #select_credential_type_option, #continue_from_advanced_picker, #cancel_advanced_picker, #back_to_advanced_picker_from_second, #back_to_advanced_picker_from_keychain, #validate_keychain, #save_keychain (credential_form_component.ex:312-485); reachable only with from_collab_editor (collaborate.ex:315)
    - WorkflowChannel "request_credentials" (workflow_channel.ex:119-132)
    - WorkflowChannel "check_custom_path" (workflow_channel.ex:577-592)
    - WorkflowChannel "request_trigger_auth_methods" (workflow_channel.ex:653-684)
    - WorkflowChannel "update_trigger_auth_methods" (workflow_channel.ex:686-745)   # also listed by flow-webhook-auth-method-enforcement
    - WorkflowChannel "reset_workflow" (workflow_channel.ex:549-566)
    - WorkflowChannel "publish_template" (workflow_channel.ex:747-759)
    - WorkflowChannel forwarders "credentials_updated", "adaptors_updated", "webhook_auth_methods_updated" (workflow_channel.ex:950-969)
  js_hooks:
    - CollaborativeEditor Inspector, InspectorLayout, InspectorFooter (components/inspector/index.tsx, InspectorLayout.tsx, InspectorFooter.tsx)
    - CollaborativeEditor JobInspector, JobForm, AdaptorDisplay, ConfigureAdaptorModal, AdaptorSelector, AdaptorSelectionModal, VersionPicker
    - CollaborativeEditor TriggerInspector, WebhookShowPanel, CronShowPanel, TriggerEditWizard, TriggerChooseStep, TriggerPicker, WebhookConfigureStep, CronConfigureStep, CronFieldBuilder, WebhookUrlList, WebhookAuthMethodSelect, ResponseTypeSelect, EditFooter, WizardFooter, WizardBreadcrumb
    - CollaborativeEditor EdgeInspector, EdgeForm, WorkflowSettings, CodeViewPanel, TemplatePublishPanel
    - CredentialModalContext handleEvent "credential_saved", "credential_modal_closed" (CredentialModalContext.tsx:187-228)
    - DOM event "close_webhook_auth_modal" on #collaborative-editor-react, relayed as close_webhook_auth_modal_complete (collaborate.ex:330-332, :341-343; WebhookConfigureStep.tsx:120-134)
    - keyboard Escape: panel at priority 10 (inspector/index.tsx:69-75); modals at 100 (ConfigureAdaptorModal.tsx:230-237, AdaptorSelectionModal.tsx:59-66, CredentialModalContext.tsx:110-118); adaptor change confirmation at 110 (AdaptorSelector.tsx:481-488)
    - keyboard Control+e / Meta+e opens the code editor for the selected step (WorkflowEditor.tsx:318-325); exit to workflow-editor-ide
    - keyboard ArrowUp, ArrowDown, Enter in the adaptor search (AdaptorSelectionModal.tsx:163-183); Enter and Tab in the custom path field (WebhookUrlList.tsx:209-226)
  policies:
    - Lightning.Policies.ProjectUsers :edit_workflow, :write_webhook_auth_method, :publish_template, :create_project_credential (project_users.ex:28-49, :127-158; workflow_channel.ex:1915-1975, :2106-2121; collaborate.ex:316-323)
    - Lightning.Policies.Users :edit_credential (users.ex:40-44; collaborate.ex:156-162)
    - Lightning.Policies.Credentials :create_keychain_credential (policies/credentials.ex:32-63, :87-98; credentials.ex:1956-1971)
  workers: []
  api_endpoints:
    - get /adaptors/catalogue  AdaptorController :index (router.ex:155-160; adaptor_controller.ex:21-45)   # also read by workflow-editor-canvas and workflow-editor-ide
  emails: []
  config: []
  not_reachable_here:
    - GenericOauthComponent and the OAuth callback hop; owned by flow-oauth-credential-authorize (collaborate.ex:388-391 forwards it)
    - WebhookAuthMethodFormComponent edit and view actions, WebhookAuthMethodDeleteModal; this host passes action={:new} only (collaborate.ex:335-351); owned by shared-webhook-auth-method-form
    - KeychainCredentialFormComponent; the editor builds keychains through CredentialFormComponent's own keychain page (credential_form_component.ex:1181-1204); the standalone form's home is project-settings-credentials
    - Code editor, run panel and manual run; reached from the step inspector but owned by workflow-editor-ide and workflow-editor-manual-run
    - see 6.3 for handlers and props with no caller

related:
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/collaboration/session.ex (reset_workflow, session.ex:301-418)
  - lib/lightning/webhook_auth_methods.ex (update_trigger_auth_methods, :334-390)
  - lib/lightning/workflows.ex (custom_path_taken?, :1209-1229)
  - lib/lightning/workflow_templates.ex (create_template, :26-38)
  - lib/lightning/workflows/trigger.ex, lib/lightning/workflows/edge.ex, lib/lightning/workflows/triggers/webhook_response_config.ex
  - lib/lightning_web/live/credential_live/credential_form_component.ex
  - lib/lightning_web/controllers/adaptor_controller.ex
  - assets/js/collaborative-editor/components/inspector/
  - assets/js/collaborative-editor/components/{AdaptorSelectionModal,ConfigureAdaptorModal,AdaptorSelector,AdaptorDisplay,VersionPicker}.tsx
  - assets/js/collaborative-editor/contexts/CredentialModalContext.tsx
  - assets/js/collaborative-editor/hooks/{useAdaptorChangeConfirmation,useJobDeleteValidation,useWorkflow,useAdaptors,useCredentials}.ts(x)
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts (updateJob, removeJob, updateEdge, removeEdge, updateTrigger, resetWorkflow, trigger auth broadcast)
  - assets/js/collaborative-editor/types/{trigger,edge,job,workflow}.ts
  - assets/js/collaborative-editor/components/form/index.tsx (Y.Doc to form sync, error map)
  - workflow-editor-canvas (hosts the panels), workflow-editor-ide, workflow-editor-manual-run
  - project-settings-credentials (keychain form home), credentials-index (credential form home)
  - test/lightning_web/live/workflow_live/collaborate_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs (reset_workflow :4049-4128, check_custom_path :4328-4410, trigger auth :5466-6030, publish_template :6100-6320)
  - assets/test/collaborative-editor/components/inspector/*.test.tsx and inspector/trigger/*.test.tsx
  - assets/test/collaborative-editor/components/{Inspector.keyboard,AdaptorSelectionModal,ConfigureAdaptorModal}.test.tsx
  - assets/test/e2e/specs/collaborative/{job-inspector-configuration,collaborative-editor-credentials}.spec.ts (stale, see 6.5)
flows:
  - flow-oauth-credential-authorize           # entry from "New credential" or the edit pencil in Configure connection
  - flow-webhook-auth-method-enforcement      # this view is its attach hop (Finish in the trigger wizard)
  - flow-editor-credentials-broadcast
  - flow-adaptor-catalogue-update
---

## 1. Purpose

People building a workflow use these side panels to say what each piece does: which adaptor,
version and credential a step runs with, how a trigger is reached (webhook URLs, authentication,
response timing, schedule), when a path between steps is taken, and workflow-wide settings like
name, logging and concurrency. Get this wrong and a step sends the wrong secret to the wrong
system, a partner's webhook stops working or is left open to anyone, or a schedule runs at the
wrong time; and because several people edit at once, one person's half-finished change must not
overwrite another's.

## 2. What it does

- Anyone on the project opens a step, trigger, path or the workflow settings in a side panel from the canvas or a link
- Editors rename a step and see collaborators' changes to it live
- Editors pick a step's adaptor, version and credential in one dialog, with matching credentials offered first
- Editors are warned that changing adaptor clears the step's credential
- Editors create a credential from the step and have it attached when saved; only a credential's owner can edit it from here
- Admins create keychain credentials from the step; others cannot
- Editors delete a step, except one other steps depend on or the first step
- Editors jump from a step to its code editor or a manual run from it
- Anyone sees a webhook trigger's URLs, attached authentication and response behaviour, and copies the URLs
- Editors change a trigger in a draft wizard that writes nothing until Finish
- Editors give a webhook a custom URL path, checked for format and uniqueness before Finish
- Editors choose when a webhook responds and its default status codes
- Admins attach and detach webhook authentication methods, and create new ones from the trigger
- Editors switch a trigger between webhook and schedule without re-enabling it
- Editors build a cron schedule from presets or a raw expression, and choose its input source
- Editors set a path's condition, label and JavaScript expression, and disable or delete job-to-job paths
- Editors rename the workflow, toggle console logging and cap concurrency within the project limit
- Editors reset the workflow to its last saved snapshot for everyone
- Anyone views, copies and downloads the workflow as YAML
- Support users publish or update the workflow as a template
- Read-only viewers see every panel with editing controls disabled and a reason
- Escape closes the topmost layer, one at a time
- A panel for a node someone else deleted closes

## 3. Who can do what

Sources: `lib/lightning/policies/project_users.ex:28-49` (`:write_webhook_auth_method` is an admin
action; `:edit_workflow` and `:create_project_credential` are editor actions), `:127-158`
(`permitted?`: MFA unsatisfied denies all; admin actions need owner or admin; editor actions allow
owner, admin, editor, and support with no row when support access is on; `:publish_template` needs a
support user who has a role or support access). Credentials: `lib/lightning/policies/users.ex:40-44`
(edit only by the credential's owner), `lib/lightning/policies/credentials.ex:32-63`, `:87-98`
(keychain create: owner, admin, or support access). Channel gates: `workflow_channel.ex:1915-1975`,
`:2106-2121`. Client gates: `useWorkflow.tsx:1036-1113`, `:1153-1185`; `useJobDeleteValidation.ts:221-247`;
`WebhookConfigureStep.tsx:102-107`; `ConfigureAdaptorModal.tsx:458-465`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row, access on) |
|--------|--------|--------|-------|-------|--------------------|------------------------------|
| See any panel, view and download YAML | yes | yes | yes | yes | no (no project access) | yes |
| Edit step, trigger, path and workflow settings fields | no | yes | yes | yes | no | yes |
| Delete a step or a path | no | yes | yes | yes | no | yes |
| Reset workflow to latest snapshot | no | yes | yes | yes | no | yes |
| Save a new credential from a step | no | yes | yes | yes | no | yes |
| Edit an existing credential from a step | owner of the credential only, if they can edit the workflow | same | same | same | no | same |
| Create a keychain credential from a step | no | no | yes | yes | no | yes |
| Attach or detach webhook auth methods | no | no | yes | yes | no | no |
| Create a webhook auth method from the trigger | no | no (link hidden) | yes | yes | no | no |
| Publish or update a template | only if a support user | only if a support user | only if a support user | only if a support user | no | yes if a support user |

**Preconditions beyond role**
- A member who has not met the project's MFA requirement is denied every action (`project_users.ex:134`; `policies/credentials.ex:89-93`).
- Editing is off while the workflow is deleted, a pinned version or as-run view is shown, or the page is an unsaved new workflow (`useWorkflow.tsx:1068-1110`); these states belong to shared-editor-session.
- Under `experimental-features`, a live workflow is content-locked: fields, delete, reset and auth method changes are refused until it is back in draft (`useWorkflow.tsx:1096-1102`; `useJobDeleteValidation.ts:230-232`; `workflow_channel.ex:1915-1937`).
- Attaching auth methods needs both `:edit_workflow` and `:write_webhook_auth_method`, and the trigger must already be saved in this workflow (`workflow_channel.ex:697-700`, `:2133-2143`).
- Deleting a step also needs a connected session (`JobInspector.tsx:375-381`; `useWorkflow.tsx:905-913`).
- The publish button is shown on `user.support_user` alone (`useWorkflow.tsx:1159`); the server adds the role or support-access check (`project_users.ex:136-141`).

## 4. What it touches

**Reads**: Y.Doc of the workflow (jobs, triggers, edges, workflow map, positions, errors) via
shared-editor-session; `project_credentials`, `credentials`, `keychain_credentials`, `users` (owner)
and `oauth_clients` (`workflow_channel.ex:119-132`); `webhook_auth_methods` and the trigger join table
(`workflow_channel.ex:653-684`, `:1358`); `triggers` (`workflows.ex:1209-1227`); `workflow_templates`
(`workflow_channel.ex:1361-1362`); the adaptor catalogue (`adaptor_controller.ex:21-45`).

**Writes**
- Y.Doc only, persisted by the workflow save in shared-editor-session: job name, adaptor, credential ids (`JobForm.tsx:95-110`, `:213-298`); job removal with its incoming edges and any cron cursor pointing at it (`createWorkflowStore.ts:1017-1046`); trigger fields on Finish (`useTriggerDraft.ts:216-222`; `createWorkflowStore.ts:1116-1136`); edge fields and removal (`EdgeForm.tsx:136-148`; `EdgeInspector.tsx:30-53`; `createWorkflowStore.ts:1070-1108`); workflow name, concurrency, enable_job_logs (`WorkflowSettings.tsx:62-79`; `createWorkflowStore.ts:967-993`); `has_auth_method` on the trigger after an auth broadcast (`createWorkflowStore.ts:514-525`).
- Database, immediately: trigger to webhook auth method associations (`webhook_auth_methods.ex:334-390`); `workflow_templates` insert or update (`workflow_templates.ex:26-38`); `credentials` and `project_credentials` via CredentialFormComponent (`credential_form_component.ex:1255-1300`, `:520-535`); `keychain_credentials` insert (`credentials.ex:1956-1971`); `webhook_auth_methods` insert via shared-webhook-auth-method-form.
- Shared document reset from the database row (`session.ex:387-397`).

**Immediate side effects** (in the same request)
- Audit: webhook auth method `added_to_trigger` and `removed_from_trigger` per changed id (`webhook_auth_methods.ex:356-385`)
- Channel broadcast `trigger_auth_methods_updated` to every collaborator (`workflow_channel.ex:704-712`)
- PubSub `workflow:collaborate:<workflow_id>` `credentials_updated` after a credential save (`collaborate.ex:519-532`) and `webhook_auth_methods_updated` after an auth method save (`collaborate.ex:534-561`), forwarded by the channel (`workflow_channel.ex:950-969`)
- Channel `broadcast_from` `template_updated` (`workflow_channel.ex:750-752`)
- Toasts: "Authentication updated" or "Failed to update" (`useWebhookTrigger.ts:448-461`); template success and failure (`TemplatePublishPanel.tsx:144-162`); "Failed to reset workflow" (`WorkflowSettings.tsx:88-94`)

**Deferred side effects** (later, elsewhere)
- Trigger, step and path changes reach the database, the webhook router and the scheduler only at the next workflow save (shared-editor-session)

**External, non-transactional effects**
- OAuth credential authorization with a provider (flow-oauth-credential-authorize)
- YAML file download to the user's machine (`CodeViewPanel.tsx:58-68`)

**Depends on config**
- `experimental-features` (a user preference) turns on the live-workflow content lock (`workflow_channel.ex:1507-1510`)

**Product limits** (limits a user would notice and that we intend to keep)
- Custom webhook path: lowercase letters, numbers, hyphens and underscores, 1 to 255 characters, not a UUID, unique per project (`types/trigger.ts:76-124`; `trigger.ex:29-30`, `:216-222`)
- Path condition expression at most 255 characters (`types/edge.ts:57-67`; `edge.ex:163-171`)
- Workflow concurrency from 1 to the project's concurrency (`types/workflow.ts:111-133`)
- Template name at most 255 codepoints, description at most 1000 graphemes (`TemplatePublishPanel.tsx:29-46`)
- Cron expressions are five-field (`types/trigger.ts:42-59`)

## 5. Scenarios

```gherkin
Feature: Workflow editor inspector panels
  In order to configure what a workflow does, step by step
  As someone building a workflow with colleagues
  I want side panels for steps, triggers, paths and workflow settings

  Background:
    Given project "Malawi HIV" has workflow "Intake" with a webhook trigger, steps "Fetch" and "Load", a path from the trigger to "Fetch" and a path from "Fetch" to "Load"

  # ---------- Steps ----------

  @S01 @pending
  Scenario: Selecting a step opens its inspector
    # Value: a builder sees and changes what a step does without leaving the canvas.
    Given I am an editor on "Malawi HIV"
    When I open "Intake" with "?job=<Fetch id>"
    Then I see a panel titled "Fetch" with "Job Name" and "Adaptor"
    When I open "?job=<Fetch id>&panel=settings"
    Then I see "Workflow settings" instead
    # useWorkflow.tsx:271-299; inspector/index.tsx:44-54, :119-129; JobForm.tsx:327-359
    # Inspector.keyboard.test.tsx:375-430

  @S02 @pending
  Scenario: Step edits reach collaborators and theirs reach me
    # Value: two people editing one step never work from different copies of it.
    Given "amara@example.org" and I are editors with "Fetch" open
    When I rename "Fetch" to "Fetch patients"
    Then "amara@example.org" sees "Fetch patients" in the "Job Name" field without reloading
    # JobForm.tsx:95-110; form/index.tsx:72-103; createWorkflowStore.ts:906-940

  @S03 @pending
  Scenario: A step's validation errors show on its own fields
    # Value: a problem is visible at the field before saving, and only on the step it belongs to.
    Given the workflow error map holds a "name" error for "Fetch"
    When I open "Fetch"
    Then the "Job Name" field shows that error
    And opening "Load" shows no error
    # JobForm.tsx:105-109; form/index.tsx:105; JobForm.test.tsx:834-1086

  @S04 @pending
  Scenario Outline: A step without a credential is flagged when its adaptor needs one
    # Value: a step that would fail for want of a credential is spotted before it runs.
    Given "Fetch" uses <adaptor> and has no credential
    When I open "Fetch"
    Then the adaptor box offers "<button>"
    # AdaptorDisplay.tsx:336-341, :511-529; constants/adaptors.ts:2-12; JobForm.test.tsx:325-399

    Examples:
      | adaptor                      | button  |
      | @openfn/language-dhis2@latest | Connect |
      | @openfn/language-http@latest  | Edit    |

  @S05 @pending
  Scenario: Picking a credential attaches it to the step
    # Value: the step runs with the secret the builder chose.
    Given "Fetch" uses the DHIS2 adaptor
    And the project has DHIS2 credential "DHIS2 prod"
    When I open "Configure connection" from "Fetch" and choose "DHIS2 prod"
    Then "Fetch" shows a "DHIS2 prod" credential badge
    And the step's project credential is set and its keychain credential is empty
    When I clear the selection
    Then "Fetch" has no credential
    # ConfigureAdaptorModal.tsx:631-647, :144-160; JobForm.tsx:254-298; ConfigureAdaptorModal.test.tsx:1002-1060, :1124-1140

  @S06 @pending
  Scenario: Credentials that match the adaptor are offered first
    # Value: it is harder to send one system's secret to another.
    Given "Fetch" uses the Salesforce adaptor
    And the project has a Salesforce credential, a raw credential and a keychain credential
    When I open "Configure connection"
    Then I see only the Salesforce credential
    When I click "Other credentials"
    Then I see the raw one under "Generic Credentials" and the keychain under "Keychain Credentials"
    # ConfigureAdaptorModal.tsx:286-345, :350-388, :652-731; ConfigureAdaptorModal.test.tsx:443-500, :765-905

  @S07 @pending
  Scenario: Changing adaptor on a step with a credential asks first and clears it
    # Value: a credential meant for one system is never sent to another by accident.
    Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
    When I pick "Salesforce" in the adaptor picker
    Then I see "Change Adaptor?" warning that the credential will be reset
    When I click "Continue"
    Then "Fetch" uses Salesforce and has no credential
    And "Configure connection" opens
    # useAdaptorChangeConfirmation.ts:63-117, :119-153; AdaptorSelector.tsx:499-508

  @S08 @pending
  Scenario: Cancelling an adaptor change keeps everything as it was
    # Value: a mis-click in the picker costs nothing.
    Given "Fetch" uses DHIS2 with credential "DHIS2 prod"
    When I pick "Salesforce" and then "Cancel" the warning
    Then "Fetch" still uses DHIS2 with "DHIS2 prod"
    And the adaptor picker is open again
    # useAdaptorChangeConfirmation.ts:158-167; AdaptorSelector.tsx:473-477

  @S09 @pending
  Scenario: A step can be pinned to an adaptor version
    # Value: a step keeps behaving the same when a new adaptor release ships.
    Given the DHIS2 adaptor has versions "4.2.0", "4.10.0" and "4.9.1"
    When I open "Configure connection" on "Fetch"
    Then the version list reads "latest", "4.10.0", "4.9.1", "4.2.0"
    When I choose "4.9.1"
    Then "Fetch" shows "v4.9.1"
    # ConfigureAdaptorModal.tsx:32-47, :416-427, :563-573; JobForm.tsx:234-251; ConfigureAdaptorModal.test.tsx:405-440

  @S10 @pending
  Scenario: Searching for an adaptor that does not exist suggests HTTP
    # Value: a builder can still connect to a system that has no dedicated adaptor.
    When I search the adaptor picker for "zzz-unknown"
    Then I see "No adaptor found" and the HTTP adaptor
    # AdaptorSelectionModal.tsx:95-146, :264-275

  @S11 @pending
  Scenario: A failed adaptor catalogue load can be retried
    # Value: a transient failure does not look like "there are no adaptors".
    Given the adaptor catalogue request fails
    When I open the adaptor picker
    Then I see "Couldn't load adaptors. Please try again." and "Retry"
    When the catalogue becomes available and I click "Retry"
    Then the adaptor list appears
    # AdaptorSelectionModal.tsx:35-40, :229-255; adaptor_controller.ex:21-45; AdaptorSelectionModal.test.tsx:149-190

  @S12 @pending
  Scenario: A credential created from a step is attached to it and offered to collaborators
    # Value: a builder connects a step to a new system without leaving the editor, and colleagues can use the credential at once.
    Given I am an editor with "Fetch" (DHIS2) open and "amara@example.org" has "Intake" open
    When I click "New Credential" in "Configure connection" and save a DHIS2 credential "DHIS2 test"
    Then "Fetch" has "DHIS2 test" as its project credential
    And "Configure connection" opens again with "DHIS2 test" selected
    And "credentials_updated" is broadcast on "workflow:collaborate:<Intake id>"
    And "amara@example.org" sees "DHIS2 test" in her credential list
    # collaborate.ex:180-187, :289-324, :393-430, :519-532; CredentialModalContext.tsx:121-136, :187-203
    # JobForm.tsx:121-165; collaborate_test.exs:267-335
    # For an OAuth client this hands off to flow-oauth-credential-authorize; only the start and the saved result are asserted here

  @S13 @pending
  Scenario: Only a credential's owner can edit it from a step
    # Value: a credential's secrets are only changed by the person responsible for them.
    Given "DHIS2 prod" is owned by "amara@example.org" and shared with the project
    When I open "Configure connection" on "Fetch"
    Then the edit button on "DHIS2 prod" is disabled with a tooltip naming its owner
    When "open_credential_modal" is sent with the id of "DHIS2 prod"
    Then no credential form opens and "credential_modal_closed" is pushed back
    # ConfigureAdaptorModal.tsx:108-143, :458-470; collaborate.ex:151-177; users.ex:40-44
    # collaborate_test.exs:998-1057; ConfigureAdaptorModal.test.tsx:1319-1440

  @S14 @pending
  Scenario: An admin creates a keychain credential from a step
    # Value: an admin can set up a credential that is chosen per run without leaving the workflow.
    Given I am an admin on "Malawi HIV"
    When I open a new credential from "Fetch", click "Advanced", choose keychain and save a keychain "Per facility" with path "$.facility_id"
    Then the keychain credential exists on the project
    And "Fetch" has "Per facility" as its keychain credential
    # credential_form_component.ex:312-366, :460-470, :1087-1170, :1181-1204; collaborate.ex:393-430, :486-517
    # collaborate_test.exs:1756-1828

  @S15 @pending
  Scenario: People below admin cannot create a keychain credential from a step
    # Value: per-run credential selection, which can reach any project credential, stays with admins.
    Given I am an editor on "Malawi HIV"
    When I submit a keychain credential "Planted" from the step's advanced credential setup
    Then no keychain credential "Planted" exists
    # credentials.ex:1956-1971; policies/credentials.ex:87-98; collaborate_test.exs:1829-1873 (viewer)

  @S16 @pending
  Scenario: Deleting a step removes it with its incoming paths and any cron input pointing at it
    # Value: no path or schedule is left referring to a step that is gone.
    Given "Load" is a leaf step and the cron input source of a schedule trigger is "Load"
    When I delete "Load" and confirm "Delete Job"
    Then "Load" and the path from "Fetch" to "Load" are gone
    And the schedule's input source reads "Final run state (default)"
    # JobInspector.tsx:362-373, :421-436, :461-473; createWorkflowStore.ts:1017-1046; CronShowPanel.tsx:325-331

  @S17 @pending
  Scenario Outline: Some steps cannot be deleted
    # Value: deleting a step can never orphan the steps after it or leave the trigger with nothing to start.
    When I open <step>
    Then the delete button is disabled with "<reason>"
    # useJobDeleteValidation.ts:214-247; JobInspector.tsx:377-381, :421-436; JobInspector.test.tsx:484-570

    Examples:
      | step  | reason                                          |
      | Fetch | Cannot delete: other jobs depend on this step   |

  @S18 @pending
  Scenario: The first step cannot be deleted
    # Value: the trigger always has a step to start.
    Given "Solo" is the only step, reached from the trigger
    When I open "Solo"
    Then the delete button is disabled with "You can't delete the first step in a workflow."
    # useJobDeleteValidation.ts:219, :236-239

  @S19 @pending
  Scenario: A step hands off to its code editor and to a manual run
    # Value: a builder goes from configuring a step to writing or testing it in one move.
    When I open "Fetch" and click the code button
    Then the URL has "panel=editor" and "job=<Fetch id>" (workflow-editor-ide takes over)
    When I return and click "Run From Here"
    Then the manual run panel opens for "Fetch" (workflow-editor-manual-run takes over)
    # JobInspector.tsx:400-446; WorkflowEditor.tsx:318-325, :333-349

  # ---------- Triggers ----------

  @S20 @pending
  Scenario: A webhook trigger shows the URLs it answers on
    # Value: a partner integration is given the exact address that will reach the workflow.
    Given the webhook trigger has custom path "kobo-intake"
    When I open the trigger
    Then I see a "Default" URL ending "/i/<trigger id>" and a "Custom" URL ending "/i/<project id>/kobo-intake"
    And each can be copied
    # WebhookShowPanel.tsx:94-107; useWebhookTrigger.ts:299-339; WebhookUrlList.tsx:85-170; useWebhookTrigger.test.tsx:57-150

  @S21 @pending
  Scenario: The webhook panel says how the trigger is protected
    # Value: a builder can tell at a glance whether anyone holding the URL can start the workflow.
    Given "Kobo basic" is attached to the trigger
    When I open the trigger and expand "Authentication"
    Then the header reads "(1 configured)" and lists "Kobo basic (Basic Auth)"
    Given no method is attached and I am an editor
    Then I see "No authentication configured." with "Add authentication", which opens the wizard on Configure with Authentication expanded
    # WebhookShowPanel.tsx:68-73, :119-185; TriggerInspector.tsx:62-69; TriggerEditWizard.tsx:188-190; WebhookShowPanel.test.tsx:143-195

  @S22 @pending
  Scenario: Trigger edits are a draft until Finish
    # Value: half-finished trigger changes never reach a live endpoint, and a colleague's change to another field is not reverted.
    Given I opened the trigger wizard and "amara@example.org" then disabled the trigger on the canvas
    When I change the response type and click "Finish"
    Then only the response type is written to the trigger
    And the trigger stays disabled
    When I open the wizard again, change the response type and click "Cancel"
    Then nothing is written
    # useTriggerDraft.ts:71-82, :96-113, :196-231; TriggerEditWizard.tsx:192-198
    # useTriggerDraft.test.tsx:369-412; TriggerEditWizard.test.tsx:214-240

  @S23 @pending
  Scenario Outline: A custom webhook path is checked before Finish
    # Value: two workflows cannot claim the same address, and the builder finds out while still on the panel.
    Given another workflow in "Malawi HIV" uses path "kobo"
    When I add a custom URL and type "<path>"
    Then I see "<message>"
    And "Finish" is <finish>
    # WebhookConfigureStep.tsx:158-186, :222-225, :257-261; useCustomPathTaken.ts:516-574
    # workflow_channel.ex:577-592; workflows.ex:1209-1227; WebhookConfigureStep.test.tsx:624-960; workflow_channel_test.exs:4328-4410

    Examples:
      | path                                 | message                                                        | finish   |
      | kobo                                 | Already used by another workflow in this project.             | disabled |
      | Kobo Intake                          | Use lowercase letters, numbers, hyphens and underscores only. | disabled |
      | 0b3c5e1a-3f1d-4c4e-9d55-4c0a7f2e9a11 | A UUID cannot be used as a path.                               | disabled |
      | kobo-intake                          | (nothing)                                                      | enabled  |

  @S24 @pending
  Scenario: A path the server refused is reported on the trigger
    # Value: if a save loses the uniqueness race, the builder sees which URL did not take and is not handed it to share.
    Given the last save returned a "custom_path" error for the trigger
    When I open the trigger
    Then I see "The custom path was not saved:" followed by the error
    And the custom URL cannot be copied
    # WebhookShowPanel.tsx:75, :109-117; useWebhookTrigger.ts:427-432; WebhookShowPanel.test.tsx:236-290

  @S25 @pending
  Scenario: Deleting a custom URL asks first
    # Value: a URL partners post to is not dropped by a stray click.
    Given the trigger has custom path "kobo-intake"
    When I click "Delete custom URL" in the wizard
    Then I see "Delete this webhook URL?" saying the default URL is unaffected
    When I confirm and click "Finish"
    Then the trigger has no custom path
    # WebhookConfigureStep.tsx:300-322; WebhookConfigureStep.test.tsx:837-870

  @S26 @pending
  Scenario: Response timing and default status codes
    # Value: a partner gets the response timing and status it was integrated against.
    When I set "Response Type" to "On Complete" and set success code 200 and error code 422 and click "Finish"
    Then the trigger replies after completion with those defaults
    When I set "Response Type" to "Immediately" and click "Finish"
    Then the response configuration is cleared
    # WebhookConfigureStep.tsx:263, :324-343, :382-460; WebhookShowPanel.tsx:187-280; TriggerEditWizard.test.tsx:241-269

  @S27 @pending
  Scenario: Attaching auth methods on Finish starts enforcement
    # Value: an admin can protect a webhook from the place they configure it.
    Given I am an admin and "Kobo basic" exists in the project
    When I open the trigger wizard, expand "Authentication", select "Kobo basic" and click "Finish"
    Then "update_trigger_auth_methods" is sent once, on Finish, with "Kobo basic"
    And I see "Authentication updated"
    And every collaborator's trigger shows "(1 configured)"
    And the flow "flow-webhook-auth-method-enforcement" has taken over for requests to the trigger
    # useTriggerDraft.ts:203-214; useWebhookTrigger.ts:434-465; workflow_channel.ex:686-745; createWorkflowStore.ts:493-540
    # TriggerEditWizard.test.tsx:306-345; workflow_channel_test.exs:5625-5690
    # Editors seeing a disabled picker and a refused request is flow-webhook-auth-method-enforcement S09; the live lock is its S10

  @S28 @pending
  Scenario: A failed auth change keeps the wizard open and writes nothing
    # Value: a trigger is never left half-updated, with new settings but old protection.
    Given the auth method request will fail
    When I select a method, change the response type and click "Finish"
    Then I see "Failed to update"
    And the wizard is still open and no trigger field was written
    # useTriggerDraft.ts:203-214; useWebhookTrigger.ts:452-462; useTriggerDraft.test.tsx:281-306

  @S29 @pending
  Scenario: Auth methods that load late are not wiped by Finish
    # Value: editing another field never silently removes a webhook's protection.
    Given "Kobo basic" is attached and the auth methods load after the wizard opens
    When I change only the response type and click "Finish"
    Then "Kobo basic" is still attached and no auth request was sent
    # useTriggerDraft.ts:115-136, :149-152, :208-214; WebhookAuthMethodSelect.tsx:524-537; useTriggerDraft.test.tsx:334-368

  @S30 @pending
  Scenario: Creating an auth method from the trigger hands off to the shared form
    # Value: an admin who needs a new credential for a partner does not have to leave the workflow.
    Given I am an admin in the trigger wizard with Authentication expanded
    When I click "Create a new authentication method"
    Then the webhook auth method form opens (shared-webhook-auth-method-form S12 owns the rest)
    When I cancel it
    Then "close_webhook_auth_modal_complete" is pushed and it can be opened again
    # WebhookConfigureStep.tsx:116-134, :370-377; WebhookAuthMethodSelect.tsx:567-583, :693-702
    # collaborate.ex:211-233, :326-352, :432-443; collaborate_test.exs:2418-2614; WebhookConfigureStep.test.tsx:266-300

  @S31 @pending
  Scenario: Switching trigger type does not re-enable it or drop its path
    # Value: changing how a workflow starts never silently turns a disabled trigger back on or loses a live URL name.
    Given the webhook trigger is disabled and has custom path "kobo-intake"
    When I click "Change", pick "On a schedule", then "Change" again and pick "On webhook call", and click "Finish"
    Then the trigger is still disabled and still has path "kobo-intake"
    When I click "Change" and pick the type it already has
    Then its configuration is unchanged
    # TriggerPicker.tsx:430-445; TriggerEditWizard.test.tsx:270-305, :505-540

  @S32 @pending
  Scenario: Building a schedule
    # Value: a builder sets when a workflow runs without memorising cron syntax, and cannot save one that never parses.
    Given the trigger is a schedule
    When I choose "Every weekday (Mon-Fri)" at hour "09" minute "30"
    Then the expression is "30 9 * * 1-5" and Finish saves it
    When I type "every morning" under "Cron Expression"
    Then I see "Invalid cron expression"
    And clicking "Finish" shows "Invalid cron expression. Use format: minute hour day month weekday" and keeps the wizard open
    # CronFieldBuilder.tsx:43-200, :221-261, :743-790; types/trigger.ts:42-59; useTriggerDraft.ts:173-201
    # CronFieldBuilder.test.tsx:51-60, :230-246, :456-506; TriggerEditWizard.test.tsx:439-504

  @S33 @pending
  Scenario: A schedule can take its input from a step's last output
    # Value: a scheduled run can carry on from where the previous one left off.
    Given the trigger is a schedule
    When I set "Cron Input Source" to "Fetch" and click "Finish"
    Then the schedule panel shows "Fetch" as its input source
    # CronConfigureStep.tsx:438-474; CronShowPanel.tsx:325-331, :349-350; CronShowPanel.test.tsx:157-175

  # ---------- Paths ----------

  @S34 @pending
  Scenario: A path's condition decides when the next step runs
    # Value: a builder can route failures, successes and specific data to different steps.
    When I open the path from "Fetch" to "Load"
    Then "Condition" offers "Always", "On Success", "On Failure" and "On Match"
    When I open the path from the trigger to "Fetch"
    Then "Condition" offers only "Always" and "On Match"
    When I choose "On Match" and leave the expression empty
    Then I see "can't be blank"
    When I type "require('fs')"
    Then a warning says the expression contains potentially unsafe functions
    # EdgeForm.tsx:150-163, :174-208, :228-261; types/edge.ts:57-67; edge.ex:135-151
    # EdgeForm.test.tsx:203-250, :701-860

  @S35 @pending
  Scenario: A job-to-job path can be disabled or deleted, a trigger path cannot
    # Value: a builder can switch off a branch without losing it, and cannot cut a trigger off from its first step here.
    When I open the path from "Fetch" to "Load" and turn off "Enabled"
    Then the path is disabled
    When I click "Delete" and confirm
    Then the path is gone and the panel closes
    When I open the path from the trigger to "Fetch"
    Then there is no footer and I see "This path will be active if its trigger is enabled"
    # EdgeInspector.tsx:30-89; EdgeForm.tsx:296-300; EdgeInspector.test.tsx:231-290

  # ---------- Workflow settings, code, templates ----------

  @S36 @pending
  Scenario: Workflow concurrency is bounded by the project
    # Value: a builder cannot set a limit that would silently have no effect.
    Given "Malawi HIV" allows 3 concurrent runs
    When I set "Max Concurrency" to 5 in "Workflow settings"
    Then I see "exceeds project concurrency limit (3) and has no effect"
    Given "Malawi HIV" allows 1 concurrent run
    Then "Max Concurrency" is disabled and a note links to the project setup page
    # WorkflowSettings.tsx:33-36, :136-177; types/workflow.ts:111-133; WorkflowSettings.test.tsx:201-394

  @S37 @pending
  Scenario: Workflow name and console logging are set from settings
    # Value: the team controls what the workflow is called and whether job code may print to run logs.
    When I rename "Intake" to "Intake v2" and turn off "Allow console.log() usage" in "Workflow settings"
    Then collaborators see the new name and setting without reloading
    # WorkflowSettings.tsx:62-79, :104-134; createWorkflowStore.ts:967-993

  @S38 @pending
  Scenario: Resetting discards everyone's unsaved changes after confirmation
    # Value: a team can back out of a muddled editing session to the last version that was saved.
    Given "amara@example.org" and I have unsaved changes to "Intake"
    When I click "Reset to Latest Snapshot" and confirm "Reset Workflow"
    Then both of us see "Intake" as last saved
    Given I am a viewer
    Then I do not see "Reset Workflow"
    And a "reset_workflow" request from me is refused
    # WorkflowSettings.tsx:81-99, :179-218; createWorkflowStore.ts:1773-1790; workflow_channel.ex:549-566; session.ex:377-418
    # workflow_channel_test.exs:4049-4128

  @S39 @pending
  Scenario: The workflow can be viewed, copied and downloaded as YAML
    # Value: a builder can move a workflow to the CLI or another instance, or share it for review.
    When I click "View your workflow as YAML code" in "Workflow settings"
    Then I see the workflow as YAML
    When I click "Download"
    Then a file "Intake.yaml" is saved
    Given the workflow is named "ワークフロー"
    Then the download is named "workflow.yaml"
    # WorkflowSettings.tsx:38-40, :110-123; CodeViewPanel.tsx:24-68, :86-138; CodeViewPanel.test.tsx:180-300

  @S40 @pending
  Scenario: A support user publishes the workflow as a template
    # Value: proven workflows become starting points for every user on the instance.
    Given I am a support user and an editor on "Malawi HIV" and "Intake" has no unsaved changes
    When I open the YAML view, click "Publish Template", enter tags "hiv, intake" and publish
    Then I see "Workflow published as template"
    And the template has tags "hiv" and "intake"
    When I publish again
    Then the same template is updated and I see "Template updated"
    # CodeViewPanel.tsx:73-80, :139-155; useWorkflow.tsx:1153-1185; TemplatePublishPanel.tsx:62-171
    # workflow_channel.ex:747-759, :1543-1551; workflow_templates.ex:26-38; workflow_channel_test.exs:6101-6206

  @S41 @pending
  Scenario: Templates are published only from saved work, and only by support users
    # Value: a template always matches a saved workflow, and the shared catalogue is curated.
    Given I am a support user and "Intake" has unsaved changes
    Then "Publish Template" is disabled with "You must save your workflow first before publishing a template."
    Given I am not a support user
    Then I do not see "Publish Template"
    And a "publish_template" request from me is refused with "You don't have permission to publish templates"
    # useWorkflow.tsx:1159-1176; workflow_channel.ex:2106-2121; CodeViewPanel.test.tsx:303-414; workflow_channel_test.exs:6207-6230

  # ---------- Read-only, keyboard, deletions ----------

  @S42 @pending
  Scenario: Viewers see the panels with editing disabled and a reason
    # Value: people without edit rights can still inspect the configuration, and know why they cannot change it.
    Given I am a viewer on "Malawi HIV"
    When I open "Fetch", the trigger and the path from "Fetch" to "Load"
    Then the fields are disabled, and "Edit trigger" and the delete buttons are disabled with "You do not have permission to edit this workflow"
    And the code button on "Fetch" still works
    # useWorkflow.tsx:1036-1081; JobForm.tsx:332, :351-358; EditFooter.tsx:631-653; useCanEditWorkflow.ts; EdgeInspector.tsx:55-89
    # JobInspector.test.tsx:180-480; EdgeInspector.test.tsx:175-230; CronShowPanel.test.tsx:131-155

  @S45 @pending @variant:experimental-features
  Scenario: A live workflow's panels are locked until it is back in draft
    # Value: a workflow in production only changes through a deliberate switch to draft or a sandbox.
    Given "Intake" is live and I am an editor with experimental features on
    When I open "Fetch" and the trigger
    Then the fields are disabled, and "Edit trigger" and the delete button are disabled with "This workflow is live. Switch to draft or edit in a sandbox to make changes."
    And a "reset_workflow" request from me is refused
    # useWorkflow.tsx:78-79, :1096-1102; useJobDeleteValidation.ts:230-232; workflow_channel.ex:1507-1510, :1915-1937
    # JobInspector.test.tsx:180-230, :324-372; workflow_channel_test.exs:515-530

  @S43 @pending
  Scenario: Escape backs out one layer at a time
    # Value: a user can dismiss a dialog without also losing the panel beneath it.
    Given "Configure connection" is open over "Fetch"
    When I press Escape
    Then the dialog closes and "Fetch" stays open
    When I press Escape again, even with focus in a field
    Then the panel closes
    Given the YAML view is open
    When I press Escape
    Then "Workflow settings" is shown
    # inspector/index.tsx:56-75; ConfigureAdaptorModal.tsx:230-237; AdaptorSelector.tsx:481-488
    # Inspector.keyboard.test.tsx:92-357; JobForm.test.tsx:247-290

  @S44 @pending
  Scenario: A panel for a node a collaborator deleted closes
    # Value: nobody keeps editing something that no longer exists.
    Given I have "Load" open
    When "amara@example.org" deletes "Load"
    Then my inspector closes
    # useWorkflow.tsx:283-287; inspector/index.tsx:42-54, :77-78; WorkflowEditor.tsx:286-291
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| After a credential save the client never receives `credential_modal_closed`: the server pushes `close_credential_modal`, which nothing listens for, so the credential modal state stays open and its Escape blocker (priority 100) stays enabled | `collaborate.ex:417-429`; `CredentialModalContext.tsx:110-118`, `:187-228` | after saving a credential from a step, Escape no longer closes the inspector until something else closes the modal state (not run) | fix |
| Editing a credential shared with several projects puts the credential's first `project_credentials` row into the payload, which may belong to another project | `collaborate.ex:402-409`, `:486-497`; `JobForm.tsx:131-153` | the step may be pointed at another project's project credential, which then fails on save or shows "Not found" (not run) | fix |
| The advanced setup offers keychain to everyone, but saving is refused for non-admins and the refusal flash stays on the component socket | `credential_form_component.ex:1087-1103`, `:460-483`; `collaborate_test.exs:1866-1872` | an editor fills in the keychain form, clicks save, and nothing happens | fix |
| "Adaptors in this project" lists only adaptors used by this workflow's steps | `AdaptorSelectionModal.tsx:277-278`; `useAdaptors.ts:150-160` | adaptors used in the project's other workflows appear under "All adaptors" | fix |
| Warning copy names an option that does not exist: "Switching to async will clear your response configuration." while the choices are "Immediately" and "On Complete" | `WebhookConfigureStep.tsx:338-342`; `ResponseTypeSelect.tsx:687-703` | copy that does not match the control | fix |
| Webhook success and error codes accept any integer; nothing checks the range on client or server | `WebhookConfigureStep.tsx:412-455`; `types/trigger.ts:27-33`; `webhook_response_config.ex:24-26` | a code like 999 or -5 saves, and the reply to the partner may fail (not run) | fix |
| Switching to "Every N minutes" or "Every N hours" with no interval yet renders an extra option labelled " minute" or " hour" | `CronFieldBuilder.tsx:329-336`, `:361-368` | a blank-looking stray option at the top of the interval list | fix |
| `:clear_credential_page` reads `original_credential_schema` from the LiveView's assigns, but only the component sets it, so cancelling the advanced picker sets the page's `credential_schema` to nil | `collaborate.ex:356-363`; `credential_form_component.ex:313-317`, `:409-414` | the standard form may re-render without its schema after "Cancel" from advanced setup (not run) | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Auth method changes are written to the database on Finish, while every other trigger field waits for the workflow save; Cancel after a save-less Finish cannot undo them | `useTriggerDraft.ts:203-222`; `workflow_channel.ex:686-745` | decide |
| Path delete uses the browser `window.confirm`; step delete uses an in-app dialog | `EdgeInspector.tsx:30-46`; `JobInspector.tsx:461-473` | decide |
| Path toggle and delete are gated only on read-only, not on connection; step delete also needs a connected session | `EdgeInspector.tsx:55-89`; `JobInspector.tsx:375-381` | decide |
| Saving an edit to a credential row also selects that credential for the step | `JobForm.tsx:129-153`; `ConfigureAdaptorModal.tsx:449-455` | decide |
| A newly picked adaptor is written as `@latest`, then reopening "Configure connection" pins it to the newest numbered version | `useAdaptorChangeConfirmation.ts:98`, `:127`; `ConfigureAdaptorModal.tsx:241-276` | decide |
| "Configure connection" clears a credential that no longer exists when the adaptor changes | `ConfigureAdaptorModal.tsx:261-264` | preserve |
| "This adaptor does not require credentials" is shown only for common, while the step button treats http, testing, ping and the fhir adaptors as not needing one | `ConfigureAdaptorModal.tsx:279-283`, `:604-609`; `AdaptorDisplay.tsx:339-341`; `constants/adaptors.ts:2-12` | decide |
| HTTP adaptor treats every OAuth credential as matching; other adaptors match OAuth by client name substring | `ConfigureAdaptorModal.tsx:306-315` | preserve |
| `credentials_updated` is broadcast on the workflow's topic only, so editors open on other workflows in the project do not refresh | `collaborate.ex:527-531` | decide |
| `webhook_auth_methods_updated` carries username, project id and timestamps, while `get_context` sends only id, name and auth type | `collaborate.ex:538-553`; `workflow_channel.ex:1483-1491` | decide |
| Every client that receives `trigger_auth_methods_updated` writes `has_auth_method` into the shared Y.Doc | `createWorkflowStore.ts:514-525` | decide |
| The auth method picker is labelled "Select a credential" and "Authentication credential N" | `WebhookAuthMethodSelect.tsx:609-620` | decide |
| The publish button shows for any support user; the server accepts a support user with any role, viewer included | `useWorkflow.tsx:1159`; `project_users.ex:136-141` | decide |
| The form sync loop updates its reference from a stale snapshot when several fields change at once, so earlier keys are re-applied on the next pass | `form/index.tsx:87-102` | decide |
| Escape closes the panel even when focus is in a field | `inspector/index.tsx:69-75`; `Inspector.keyboard.test.tsx:230-320` | preserve |
| Tab in an empty custom path field takes the suggested path derived from the workflow name | `WebhookUrlList.tsx:216-226`; `WebhookConfigureStep.tsx:215-216` | preserve |
| Template name error says "less than 255 characters" though 255 is accepted | `TemplatePublishPanel.tsx:31-36` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `push_event("close_credential_modal")` | `collaborate.ex:420` | no JS listener |
| `push_event("webhook_auth_method_saved")` | `collaborate.ex:441` | no JS listener; the list refresh comes from the PubSub broadcast |
| `handle_info({:back_to_advanced_picker})` | `collaborate.ex:380-386` | nothing sends it |
| `credential_page` and `selected_credential_type_for_picker` assigns | `collaborate.ex:356-378` | never read in render |
| `openWorkflowSettings` | `inspector/index.tsx:155-158` | no caller; the header sets the param itself (`Header.tsx:717`) |
| `InspectorLayout` `nodeType` badge | `InspectorLayout.tsx:169`, `:236-242` | no caller passes it |
| `ConfigureAdaptorModal` `onAdaptorChange` and `JobForm` `handleAdaptorChange` | `ConfigureAdaptorModal.tsx:188`, `:209-211`; `JobForm.tsx:213-231` | adaptor changes go through the picker instead |
| `handleCancelAdaptorChange` | `useAdaptorChangeConfirmation.ts:169-172` | no caller |
| `useTriggerDraft` `isDirty` and `reset` | `useTriggerDraft.ts:142-158` | the wizard uses neither |
| `TriggerInspector` `onOpenRunPanel` | `TriggerInspector.tsx:27` | ignored; running lives on the header |
| Single-weekday cron regex | `CronFieldBuilder.tsx:132-142` | the multi-weekday regex above it matches first (`:120-130`) |
| Commented-out credential display in JobForm | `JobForm.tsx:300-325` | commented out |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| Custom path uniqueness check debounced 300 ms; "Checking this name…" after 400 ms more; a failed check stops blocking | `useCustomPathTaken.ts:499-504`, `:537-567` | yes | preserve |
| Credential callbacks wait 200 ms for the modal close animation | `CredentialModalContext.tsx:18`, `:195-199`, `:221-224` | no | preserve |
| Adaptor catalogue served with an ETag and `no-cache`, 304 when unchanged | `adaptor_controller.ex:21-36` | no | preserve |
| Reset waits up to 10 s on the session process | `session.ex:301-303` | only on a slow server | preserve |
| Credential lists scroll after a fixed height | `ConfigureAdaptorModal.tsx:630`, `:658`, `:687` | yes | preserve |

### 6.5 Things seen but not understood

- The Playwright specs `job-inspector-configuration.spec.ts` and `collaborative-editor-credentials.spec.ts` drive a `select[name="credential_id"]` and a "Configure Your Adaptor" title (`job-inspector.page.ts:47-49`; `job-inspector-configuration.spec.ts:101`) that the current JobForm and "Configure connection" dialog do not render. They look stale; they were not used as evidence here.
- `ConfigureAdaptorModal.test.tsx:1677-1775` is named "edits a credential from keychain credentials section" but asserts only that the row renders; keychain rows have no edit button.
- `request_trigger_auth_methods` scopes by project but not by workflow (`workflow_channel.ex:666-674`), unlike the update path, which checks the workflow (`:2133-2143`). Not clear whether that matters.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

1. New route shape for the panels: keep query params (`?job=`, `?panel=settings`) or move to path segments?
2. Should trigger auth method changes stay an immediate database write on Finish, or join the workflow save like other trigger fields (6.2)?
3. Who may publish templates: any support user with a role, including viewers, or only those who can edit the workflow (6.2)?
4. Should the adaptor and credential pickers become a shared annotation (see Proposed shared), with S04 to S15 moving there?

## Proposed flows

none. The handoffs in this file go to existing flows (flow-oauth-credential-authorize from S12, flow-webhook-auth-method-enforcement from S27) or to sibling editor views on the same page (workflow-editor-ide and workflow-editor-manual-run from S19).

## Proposed shared

- `shared-editor-session` (lead to create): this panel relies on Y.Doc writes and the write guard (`createWorkflowStore.ts:906-1136`), the workflow save that persists step, trigger, path and settings changes, permissions and `content_locked` from `get_context` (`workflow_channel.ex:1309-1388`), read-only states (`useWorkflow.tsx:1036-1113`), connection state for `useCanSave` (`useWorkflow.tsx:886-930`), the Y.Doc error map behind field errors (`form/index.tsx:105`), and the `credentials_updated`, `adaptors_updated` and `webhook_auth_methods_updated` forwarders (`workflow_channel.ex:950-969`). Surfaces: workflow-editor-canvas, workflow-editor-inspectors, workflow-editor-ide and the other editor panels.
- `shared-adaptor-credential-config`: the adaptor picker, adaptor change confirmation, "Configure connection" dialog, adaptor display and the credential modal bridge (`AdaptorSelectionModal.tsx`, `AdaptorSelector.tsx`, `ConfigureAdaptorModal.tsx`, `AdaptorDisplay.tsx`, `CredentialModalContext.tsx`, `collaborate.ex:145-209`, `:289-324`, `:393-430`). Used by this view (JobForm), workflow-editor-ide (`FullScreenIDE.tsx:63-66`) and workflow-editor-canvas (`WorkflowDiagram.tsx`, picker only). S04 to S15 are written here as the inventory's home and would move. Surfaces: workflow-editor-inspectors, workflow-editor-ide, workflow-editor-canvas.

## Lead resolution (batch 5)

- `shared-adaptor-credential-picker` merged with the IDE's `shared-configure-adaptor-modal` into `shared-adaptor-credential-config`. S04 to S15 now overlap it; listed for the final cleanup.
- `shared-editor-session` created.
