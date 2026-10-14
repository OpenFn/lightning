---
id: workflow-editor-new
type: view
title: New workflow (landing screen, templates, YAML import)
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/new
  new_route: /projects/:project_id/w/new
  old_route_disposition: unchanged
  reachable_when:
    - the project scope gate admits the viewer (see shared-project-scope)
    - the viewer may create workflows in this project, otherwise mount redirects to /projects/:project_id/w (collaborate.ex:35-59)

inherits:
  - shared-authenticated-session      # :default live_session, InitAssigns (router.ex:288)
  - shared-project-scope              # on_mount :project_scope (collaborate.ex:25)
  - shared-usage-limits-banner        # on_mount :check_limits and the :banner slot (collaborate.ex:27, :238-242)
  - shared-editor-session
  - shared-workflow-yaml-format
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: id
    set_by: nobody legitimately; a hand-edited or stale URL
    effect: ignored on /w/new; a fresh workflow id is always generated (collaborate.ex:456-470, collaborate_new_test.exs:195-209)
  - name: run
    set_by: legacy redirect (a remapped to run, legacy_redirect_controller.ex:39-43)
    effect: ignored on /w/new (collaborate.ex:100-104)
  - name: chat, panel, job, trigger, edge
    set_by: links into the editor; forwarded by the legacy redirect
    effect: ignored on /w/new; the landing screen is the only entry point (createUIStore.ts:78-86, WorkflowEditor.tsx:116-119, :285-292)
  - name: (any query string)
    set_by: controller:legacy-redirect (/w/new/legacy forwards its query string, legacy_redirect_controller.ex:17-19, :25-37)
    effect: carried into the page; nothing on /w/new reads it
  - name: (entry, no params)
    set_by: workflows-index "Create new workflow" button and empty-state link (dashboard_components.ex:41, :48, :366); controller:user-registration after sign-up (user_registration_controller.ex:40-49)
    effect: opens the landing screen

config_variants:
  default: {}                                                             # Apollo not configured: AiAssistant.enabled? false (ai_assistant.ex:80-84)
  ai-enabled: { apollo.endpoint: <url>, apollo.ai_assistant_api_key: <key> }   # read at collaborate.ex:84
  ai-limit-reached: { ai-enabled, AiAssistant.Limiter.validate_quota(project_id): {:error, _, %Message{}} }   # workflow_channel.ex:2429-2431, :2442
  activation-limited: { Lightning.Extensions.usage_limiter: <adapter whose limit_action(:activate_workflow) returns {:error, _, %Message{}}> }   # session.ex:934-950

inventory:
  routes:
    - live /projects/:project_id/w/new  WorkflowLive.Collaborate :new
  events:
    - WorkflowChannel join "workflow:collaborate:<id>" with action "new" (workflow_channel.ex:43-112, :2214-2237)
    - WorkflowChannel#list_templates (workflow_channel.ex:761-766)
    - WorkflowChannel#validate_workflow_name (workflow_channel.ex:568-575)
    - WorkflowChannel#save_workflow (first save of a new workflow; workflow_channel.ex:300-313, :852-877)
    - WorkflowChannel#get_context (limits.ai_assistant read by the landing screen; workflow_channel.ex:1381, :2437-2452)
  js_hooks:
    - ReactComponent CollaborativeEditor (collaborate.ex:252-287)
    - CollaborativeEditor LandingScreenWrapper, LandingScreen, TemplateBrowserModalWrapper, TemplateBrowserModal, YAMLImportModal, YAMLFileDropzone, YAMLCodeEditor, ValidationErrorDisplay
    - keyboard Control+\ / Meta+\ opens YAML import while the landing screen is up (WorkflowEditor.tsx:304-316)
    - keyboard Escape closes the template browser and YAML import modals (TemplateBrowserModalWrapper.tsx:35-37, YAMLImportModal.tsx:22)
  policies:
    - Lightning.Policies.ProjectUsers :create_workflow (collaborate.ex:35-42, workflow_channel.ex:2225)
    - Lightning.Policies.ProjectUsers :edit_workflow (save_workflow, workflow_channel.ex:1915-1956)
  workers: []
  api_endpoints: []
  emails: []
  config:
    - :lightning, :apollo endpoint and ai_assistant_api_key (AiAssistant.enabled?/0)
    - AI assistant quota (AiAssistant.Limiter.validate_quota/1)
    - :lightning, Lightning.Extensions, :usage_limiter (limit_action :activate_workflow)
    - Lightning.Adaptors.Config.first_load_timeout (save waits on the adaptor catalogue, session.ex:244-250, :352-368)
  not_reachable_here:
    - WorkflowLive.Collaborate#open_credential_modal, #close_credential_modal, #credential_modal_closed (collaborate.ex:145-209); the inspector that opens them is blocked on /new (WorkflowEditor.tsx:285-292)
    - WorkflowLive.Collaborate#open_webhook_auth_modal, #close_webhook_auth_modal_complete (collaborate.ex:211-233)
    - WorkflowLive.Collaborate handle_info credential and webhook auth messages (collaborate.ex:356-443)
    - WorkflowLive.Collaborate maybe_load_initial_run_data run branch (collaborate.ex:106-114); short-circuited for new workflows (:100-104)
    - Lightning.Workflows.WorkflowUsageLimiter.limit_workflow_creation/1 (workflow_usage_limiter.ex:45-50); no caller in lib/
    - parseWorkflowTemplate lenient template parser (yaml/util.ts:66-93); the template browser uses the strict parseWorkflowYAML (templateWorkflowState.ts:46-48)
    - createWorkflowStore deduplicateJobNames (createWorkflowStore.ts:1840-1870); duplicate job names are rejected by the parser first (yaml/v1.ts:250-262)

related:
  - lib/lightning_web/live/workflow_live/collaborate.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/collaboration/workflow_resolver.ex
  - lib/lightning/collaboration/session.ex
  - lib/lightning/workflows.ex
  - lib/lightning/workflow_templates.ex
  - lib/lightning/workflows/workflow_usage_limiter.ex
  - lib/lightning/policies/project_users.ex
  - assets/js/collaborative-editor/CollaborativeEditor.tsx
  - assets/js/collaborative-editor/components/LandingScreen.tsx
  - assets/js/collaborative-editor/components/TemplateBrowserModal.tsx
  - assets/js/collaborative-editor/components/TemplateBrowserModalWrapper.tsx
  - assets/js/collaborative-editor/components/YAMLImportModal.tsx
  - assets/js/collaborative-editor/components/yaml-import/
  - assets/js/collaborative-editor/constants/baseTemplates.ts
  - assets/js/collaborative-editor/hooks/useWorkflow.tsx (useCreateWorkflowFlow, saveWorkflow wrapper)
  - assets/js/collaborative-editor/stores/createUIStore.ts
  - assets/js/collaborative-editor/stores/createWorkflowStore.ts (importWorkflow, validateWorkflowName)
  - assets/js/yaml/
  - workflow-editor-canvas (where a created workflow lands)
  - workflow-editor-ai-assistant (where "Build with AI" hands off)
  - workflows-index (entry)
  - test/lightning_web/live/workflow_live/collaborate_new_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs (join authorization, validate_workflow_name, list_templates)
  - assets/test/collaborative-editor/components/{LandingScreen,TemplateBrowserModal,TemplateBrowserModalWrapper,TemplateBrowserModalWrapper.templateFetch,CollaborativeEditor.build-from-scratch}.test.tsx
  - assets/test/collaborative-editor/components/yaml-import/{YAMLImportModal,YAMLFileDropzone}.test.tsx
  - assets/test/collaborative-editor/stores/createUIStore.{landing-screen,modals}.test.ts
flows:
  - flow-register-first-workflow
  - flow-legacy-editor-redirect
  - flow-workflow-api-edit-conflict
---

## 1. Purpose

This is where someone who can build in a project starts a new workflow. They pick a starting
point (a blank webhook workflow, a template, a YAML file exported from another project or the
CLI, or a description for the AI assistant) and land in the editor with a saved workflow. Without
it, every workflow would start from nothing, moving a workflow between projects or instances would
mean rebuilding it by hand, and a half-created workflow could exist only in the browser and be lost.

## 2. What it does

- Editors and above see a landing screen with the ways to start a workflow
- People who cannot create workflows are sent back to the workflow list
- Editors build a blank workflow (webhook trigger, one empty step) in one click
- Editors browse, search and preview templates, then create a workflow from one
- Editors import a workflow from a pasted or uploaded YAML file, with validation errors shown before creating
- On instances with the AI assistant, editors describe a workflow and hand it to the assistant
- A created workflow is saved straight away under a name unique in the project, and the editor moves to its address
- Creation that cannot reach the server, or fails to save, tells the user and can be retried
- At the workflow activation limit, a new workflow is still created but with its triggers off
- When the AI assistant quota is spent, the AI prompt is disabled with the limit message

## 3. Who can do what

Source: `lib/lightning/policies/project_users.ex:39-49` (`:create_workflow` and `:edit_workflow` are
editor actions), `:167-172` (editor actions allow owner, admin, editor, and support with no row when
support access is on), `:134` (MFA unsatisfied denies everything). Page gate: `collaborate.ex:35-59`.
Channel gate: `workflow_channel.ex:2224-2237`. Save gate: `workflow_channel.ex:300-313`, `:1915-1956`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the landing screen | no, redirected | yes | yes | yes | no | yes, when support access is on |
| Build from scratch | no | yes | yes | yes | no | yes, when support access is on |
| Browse templates and create from one | no | yes | yes | yes | no | yes, when support access is on |
| Import YAML | no | yes | yes | yes | no | yes, when support access is on |
| Build with AI (hand-off) | no | yes | yes | yes | no | yes, when support access is on |
| Save the new workflow (channel) | no | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Page access is the shared project scope gate (`collaborate.ex:25`, see shared-project-scope); a member who has not met the project's MFA requirement is denied by the policy (`project_users.ex:134`).
- The collaboration channel re-checks `:create_workflow` on join with action "new" before anything is resolved (`workflow_channel.ex:2224-2237`).
- A "new" join for an id that already belongs to another project is refused as "workflow not found" (`workflow_channel.ex:2229-2233`, `workflow_resolver.ex:82-107`).
- A "new" join cannot be pinned to a version (`workflow_channel.ex:2219-2222`).
- Build with AI requires the instance to have the AI assistant configured (`collaborate.ex:84`, `ai_assistant.ex:80-84`) and the project to have AI quota left (`CollaborativeEditor.tsx:367-368`).
- Every create path requires a live connection to the collaboration channel (`useWorkflow.tsx:790-798`).

## 4. What it touches

**Reads**: `projects`, `project_users`, `users` (scope and policy); `workflow_templates`, every row on the
instance, ordered by name (`workflow_templates.ex:146-150`); `workflows` names in the project for the
unique-name check (`workflows.ex:287-320`); `workflows` by id in the resolver (`workflow_resolver.ex:82-107`)

**Writes** (on create, through the first save; `session.ex:507-535`, `workflows.ex:327-352`)
- `workflows` (insert, state `:draft` by schema default, `workflow.ex:64`), `jobs`, `triggers`, `edges`
- `workflow_snapshots` and `audit_events` `snapshot_created` (`workflows.ex:460`, `:730`)
- `audit_events` workflow state change `enabled` when a trigger is created enabled (`workflows.ex:734-759`)
- `workflow_versions` (`workflows.ex:354-363`)
- AI chat sessions that referenced the unsaved workflow or its jobs are reconciled (`session.ex:528-533`, `ai_assistant.ex:297-391`)
- the collaborative document state (owned by shared-editor-session)

**Immediate side effects** (in the same request)
- Usage limiter `limit_action(:activate_workflow)` when the new workflow has an enabled trigger; at the limit the triggers are switched off instead of failing (`session.ex:934-963`)
- PubSub `workflow_events:<project_id>` `WorkflowUpdated` (`workflows.ex:513-516`, `workflows/events.ex:9-14`)
- Channel broadcast `workflow_saved` to other clients in the room (`workflow_channel.ex:852-857`)
- Sandbox save telemetry (`workflows.ex:529-536`)
- The browser URL is patched to `/projects/:project_id/w/:id` and the editor leaves "new" mode (`useWorkflow.tsx:440-460`)

**Deferred side effects** (later, elsewhere)
- A created webhook trigger is enabled unless the YAML says otherwise (`yaml/v1.ts:72-73`, `baseTemplates.ts:21-23`), so its URL starts accepting requests at once (`webhooks_controller.ex:40`); a "Scheduled workflow" template's cron trigger is enabled and fires on its schedule (`baseTemplates.ts:76-80`)

**External, non-transactional effects** (calls out that can't be rolled back if the request fails)
- A hosted usage limiter or AI quota adapter may call out; the default adapters do not

**Depends on config**
- AI assistant configuration and quota (variants `ai-enabled`, `ai-limit-reached`)
- Usage limiter (variant `activation-limited`)
- Adaptor catalogue first load: a save waits for it and fails with `adaptor_catalogue_unavailable` if it cannot load (`session.ex:352-368`)

**Product limits** (limits a user would notice and that we intend to keep)
- YAML uploads must be `.yml` or `.yaml` and at most 8MB (`YAMLFileDropzone.tsx:34-55`)
- At the workflow activation limit a new workflow is created with its triggers off (S27)
- AI assistant quota disables Build with AI (S25)

## 5. Scenarios

```gherkin
Feature: Start a new workflow
  In order to get a working workflow into my project quickly
  As a project editor
  I want to start from a blank workflow, a template, a YAML file or a description

  @S01 @pending
  Scenario: Editor sees the ways to start a workflow
    # Value: people starting a workflow see every starting point in one place instead of an empty canvas.
    # LandingScreen.tsx:59-166; createUIStore.ts:107; useUI.ts:126-137; CollaborativeEditor.tsx:361-407
    Given I am an editor on project "Malawi HIV"
    When I open "/projects/<Malawi HIV id>/w/new"
    Then I see "Where would you like to start today?"
    And I see a "Build from scratch" card and a "Browse templates" card
    And I see a link "import a YAML file manually"
    And the workflow header and canvas are not shown

  @S02 @pending
  Scenario: A viewer who opens the new workflow URL is sent back to the list
    # Value: someone who cannot create a workflow never sees a landing screen where every option silently does nothing.
    # collaborate.ex:35-59; collaborate_new_test.exs:165-193
    Given I am a viewer on project "Malawi HIV"
    When I open "/projects/<Malawi HIV id>/w/new"
    Then I am on "/projects/<Malawi HIV id>/w"
    And I see "You are not authorized to perform this action."

  @S03 @pending
  Scenario: A new workflow cannot claim an id owned by another project
    # Value: a crafted id cannot be used to overwrite or read another project's workflow.
    # workflow_channel.ex:2224-2233; workflow_resolver.ex:82-107; workflow_channel_test.exs:1521-1541
    Given I am an editor on project "Malawi HIV"
    And workflow "Lab results" with id "<lab id>" belongs to project "Kenya TB"
    When my editor joins the new workflow room for id "<lab id>" in project "Malawi HIV"
    Then the join is refused with "workflow not found"

  @S04 @pending
  Scenario: Editor builds a blank workflow from scratch
    # Value: the most common starting shape is one click away and is saved before the user starts editing.
    # CollaborativeEditor.tsx:375-384; baseTemplates.ts:12-29; useWorkflow.tsx:790-829, :440-460; CollaborativeEditor.build-from-scratch.test.tsx:372-396
    Given I am an editor on project "Malawi HIV" with no workflow named "Untitled workflow"
    And I am on the new workflow landing screen
    When I click "Build from scratch"
    Then a workflow named "Untitled workflow" is saved with a webhook trigger, a step "Untitled step" on "@openfn/language-common@latest" and an always edge between them
    And the address becomes "/projects/<Malawi HIV id>/w/<new id>"
    And the landing screen is gone and the workflow editor (workflow-editor-canvas) shows the new workflow

  @S05 @pending
  Scenario: Clicking build from scratch twice creates one workflow
    # Value: an impatient double click doesn't leave a duplicate workflow behind.
    # LandingScreen.tsx:141-146, :185; useActionLock.ts; CollaborativeEditor.build-from-scratch.test.tsx:447-470
    Given I am on the new workflow landing screen
    When I click "Build from scratch" twice while the first save is still running
    Then the "Build from scratch" card is disabled until the save finishes
    And exactly one workflow is created

  @S06 @pending
  Scenario Outline: Creating while not connected tells me why nothing happened
    # Value: a user never ends up with an unsaved workflow that exists only in their browser.
    # useWorkflow.tsx:748-762, :790-798; CollaborativeEditor.build-from-scratch.test.tsx:398-412; YAMLImportModal.test.tsx:272-296; TemplateBrowserModalWrapper.test.tsx:189
    Given I am on the new workflow landing screen
    And the editor is <state> to the server
    When I click "Build from scratch"
    Then I see an alert "<title>"
    And no workflow is created and the landing screen stays

    Examples:
      | state                | title            |
      | disconnected from    | Not connected    |
      | still connecting     | Still connecting |

  @S07 @pending
  Scenario: A new workflow that fails to save can be retried
    # Value: a temporary server failure does not lose the starting point the user chose.
    # useWorkflow.tsx:490-570, :500-502, :572-586; CollaborativeEditor.build-from-scratch.test.tsx:414-429
    Given I am on the new workflow landing screen
    And the next save of the workflow will fail with a server error
    When I click "Build from scratch"
    Then I see a "Failed to save workflow" notification with a "Retry" action that does not disappear on its own
    And the landing screen stays
    When the server recovers and I click "Retry"
    Then the workflow is saved and the editor shows it at "/projects/<Malawi HIV id>/w/<new id>"

  @S08 @pending
  Scenario: A created workflow gets a name unique in the project
    # Value: creating a workflow never fails, or produces two indistinguishable workflows, because the name is taken.
    # createWorkflowStore.ts:1892-1911, :1802-1831; workflow_channel.ex:568-575, :2123-2131; workflows.ex:287-320; workflow_channel_test.exs:4409-4530
    Given project "Malawi HIV" already has workflows "Event-based workflow" and "Untitled workflow"
    When I create a workflow from the "Event-based workflow" template
    Then the new workflow is named "Event-based workflow 1"
    When I go back to the landing screen and click "Build from scratch"
    Then the new workflow is named "Untitled workflow 1"

  @S09 @pending
  Scenario: Editor browses templates
    # Value: people start from a known-good shape instead of rebuilding common patterns.
    # TemplateBrowserModalWrapper.tsx:39-84; TemplateBrowserModal.tsx:41-78, :183-207; baseTemplates.ts:31-80; workflow_templates.ex:146-150; workflow_channel.ex:761-766; TemplateBrowserModal.test.tsx:198-213
    Given templates "Kobo to DHIS2" and "Appointment reminders" have been published on this instance
    And I am on the new workflow landing screen
    When I click "Browse templates"
    Then I see a "Templates" dialog listing "Event-based workflow" and "Scheduled workflow" first
    And then "Appointment reminders" and "Kobo to DHIS2"
    And "Event-based workflow" is previewed as a diagram with its name and description

  @S10 @pending
  Scenario: Clicking a template previews it without creating anything
    # Value: people can compare templates before committing to one.
    # TemplateBrowserModal.tsx:189-197, :243-296; TemplateBrowserModal.test.tsx:215-247
    Given the template browser is open
    When I click "Scheduled workflow"
    Then the preview shows "Scheduled workflow" and its description
    And no workflow has been created

  @S11 @pending
  Scenario: Searching narrows the published templates but keeps the shipped ones
    # Value: people find a relevant template in a long list without losing the basic starting points.
    # TemplateBrowserModal.tsx:41-62, :168-179, :198-205; filterTemplates.ts:7-30; TemplateBrowserModal.test.tsx:141-195, :249-273; filterTemplates.test.ts
    Given templates "Kobo to DHIS2" tagged "survey" and "Appointment reminders" have been published
    And the template browser is open with "Appointment reminders" previewed
    When I search for "SURVEY"
    Then the list shows "Event-based workflow", "Scheduled workflow" and "Kobo to DHIS2"
    And "Appointment reminders" is not listed and the preview moves to "Event-based workflow"
    When I search for "zzz"
    Then I see "No saved templates match your search."

  @S12 @pending
  Scenario: Editor creates a workflow from a template
    # Value: a chosen template becomes a saved workflow the user can start editing immediately.
    # TemplateBrowserModalWrapper.tsx:86-96; TemplateBrowserModal.tsx:279-294; templateWorkflowState.ts:46-48; TemplateBrowserModalWrapper.test.tsx:151-187
    Given the template browser is open with "Scheduled workflow" previewed
    When I click "Create"
    Then the button reads "Creating..." and every template card is disabled while it saves
    And a workflow "Scheduled workflow" is saved with a cron trigger "0 0 * * *" and a step "Get data"
    And the dialog and the landing screen close and the editor shows the new workflow
    But if the save fails the dialog stays open and "Create" is enabled again

  @S13 @pending
  Scenario: An unreadable template cannot be used
    # Value: a broken published template can't produce a broken workflow, and the user is told why.
    # TemplateBrowserModal.tsx:85-88, :245-259, :279-294; templateWorkflowState.ts:62-74; TemplateBrowserModal.test.tsx:297-331
    Given a published template "Broken" whose definition is not valid workflow YAML
    And the template browser is open
    When I click "Broken"
    Then the preview says "This template can't be previewed." with the parse error
    And "Create" is disabled with the tooltip "This template can't be read."

  @S14 @pending
  Scenario: The shipped templates are still offered when published templates fail to load
    # Value: a server hiccup doesn't stop someone starting a workflow.
    # TemplateBrowserModalWrapper.tsx:46-70; TemplateBrowserModalWrapper.templateFetch.test.tsx:152-173
    Given loading published templates will fail
    When I open the template browser
    Then I see an alert "Failed to load templates" with "Please check your connection and try again."
    And "Event-based workflow" and "Scheduled workflow" are listed and can be created

  @S15 @pending
  Scenario: Editor imports a workflow from a YAML file
    # Value: a workflow exported from another project, instance or the CLI moves in without being rebuilt by hand.
    # YAMLImportModal.tsx:110-132, :154-179; YAMLFileDropzone.tsx:21-94; YAMLFileDropzone.test.tsx:33-63, :153-171; YAMLImportModal.test.tsx:225-248
    Given I am on the new workflow landing screen
    When I click "import a YAML file manually"
    Then I see "Import a workflow" with "Upload or drop a YAML file." and "YML or YAML, up to 8MB"
    When I upload "kobo-sync.yaml" containing a valid workflow named "Kobo sync"
    Then the file's text is shown in the text editor
    And "Create" becomes enabled
    When I click "Create"
    Then a workflow "Kobo sync" is saved with the file's steps, triggers and edges
    And the dialog and the landing screen close and the editor shows the new workflow

  @S16 @pending
  Scenario Outline: Only YAML files up to 8MB are accepted
    # Value: users get an immediate, specific reason instead of a confusing parse failure or a stalled browser.
    # YAMLFileDropzone.tsx:34-55, :138; YAMLFileDropzone.test.tsx:65-126
    Given the YAML import dialog is open in upload mode
    When I upload <file>
    Then I see "<message>"
    And nothing is loaded into the editor

    Examples:
      | file                     | message                                    |
      | "workflow.json"          | File must be .yml or .yaml format          |
      | a 9MB file "big.yaml"    | File size 9.0MB exceeds maximum of 8MB     |

  @S17 @pending
  Scenario: Invalid YAML is explained before anything is created
    # Value: users fix their file against a specific message instead of creating a broken workflow.
    # YAMLImportModal.tsx:72-99, :134-152, :181-185; ValidationErrorDisplay.tsx:32-61; workflow-errors.ts:219-247; YAMLImportModal.test.tsx:194-222
    Given the YAML import dialog is open
    When I click "Paste text"
    Then "Create" is disabled with the tooltip "Enter YAML content to create workflow"
    When I paste YAML whose edge refers to a step "load-data" that does not exist
    Then I see "Validation Error" with the code "JOB_NOT_FOUND" and "Job reference error: The job 'load-data' referenced in edge"
    And "Create" is disabled with the tooltip "Fix validation errors to continue"

  @S18 @pending
  Scenario Outline: Both workflow YAML formats import
    # Value: files written by older Lightning exports and by the current CLI and canvas export both work.
    # yaml/util.ts:41-58; YAMLCodeEditor.tsx:16-39; YAMLImportModal.test.tsx:334-390
    Given the YAML import dialog is open in paste mode
    When I paste the canonical workflow in <format> format and click "Create"
    Then the created workflow has steps "ingest", "load", "maybe skip", "report failure" and "transform"
    And it has a cron trigger and a webhook trigger

    Examples:
      | format                                   |
      | v1 (jobs, triggers, edges maps)          |
      | v2 (steps list)                          |

  @S19 @pending
  Scenario: A failed import save keeps the dialog usable
    # Value: a user's pasted YAML is not thrown away when the save fails.
    # YAMLImportModal.tsx:116-127; YAMLImportModal.test.tsx:250-270, :298-332
    Given the YAML import dialog holds valid YAML
    And the next save will fail
    When I click "Create"
    Then the button reads "Importing..." while it saves
    And afterwards the dialog is still open with my YAML and "Create" is enabled
    And the landing screen is still shown

  @S20 @pending @variant:ai-enabled
  Scenario: Editor hands a description to the AI assistant
    # Value: people who don't know the workflow shape yet can start from a plain-language goal.
    # LandingScreen.tsx:41-49, :66-136; CollaborativeEditor.tsx:394-397; createUIStore.ts:173-178; AIAssistantPanelWrapper.tsx:363-375; LandingScreen.test.tsx:71-104
    Given the AI assistant is configured on this instance
    And I am on the new workflow landing screen
    Then I see "Build with AI" marked "Recommended" with the AI disclaimer and a "Learn more." link
    When I type "Sync new KoboToolbox submissions into Postgres" and press Enter
    Then the landing screen closes
    And the AI assistant panel opens and sends "Sync new KoboToolbox submissions into Postgres" (handoff to workflow-editor-ai-assistant)

  @S21 @pending @variant:ai-enabled
  Scenario: Build with AI needs a description
    # Value: an empty request never reaches the assistant or uses quota.
    # LandingScreen.tsx:44-49, :106-111, :126; LandingScreen.test.tsx:44-69, :106-124
    Given the AI assistant is configured and I am on the landing screen
    When the prompt is empty or only spaces
    Then "Build it" is disabled and Enter does nothing
    When I type a first line and press Shift+Enter or Alt+Enter
    Then a new line is added and nothing is sent

  @S22 @pending
  Scenario: Without the AI assistant, the other options still show
    # Value: instances without AI see no option they cannot use.
    # LandingScreen.tsx:66; collaborate.ex:84, :277; ai_assistant.ex:80-84; LandingScreen.test.tsx:147-177
    Given the AI assistant is not configured on this instance
    When I open the new workflow landing screen
    Then I do not see "Build with AI", "Recommended" or the AI disclaimer
    And I see "Build from scratch", "Browse templates" and "import a YAML file manually"

  @S23 @pending @variant:ai-limit-reached
  Scenario: When the AI quota is spent the prompt is disabled with the reason
    # Value: users understand why AI is unavailable and still have the other ways to start.
    # CollaborativeEditor.tsx:367-368, :391-393; LandingScreen.tsx:41-44, :90-115; workflow_channel.ex:2429-2431, :2442-2449; LandingScreen.test.tsx:218-250
    Given project "Malawi HIV" has used its AI assistant quota with the message "AI usage limit reached for this month"
    When I open the new workflow landing screen
    Then the "Build with AI" prompt and "Build it" are disabled
    And hovering the prompt shows "AI usage limit reached for this month"
    And "Build from scratch" is enabled

  @S24 @pending
  Scenario: Links into the editor cannot bypass the landing screen
    # Value: nobody lands in a half-built editor with panels open on a workflow that has no saved record.
    # createUIStore.ts:78-86; WorkflowEditor.tsx:116-119, :274, :285-292; collaborate.ex:100-104, :456-470; collaborate_new_test.exs:195-209; collaborate_test.exs:2747-2768
    Given I am an editor on project "Malawi HIV" with an existing workflow "Lab results"
    When I open "/projects/<Malawi HIV id>/w/new?id=<lab id>&chat=true&panel=settings&run=<run id>"
    Then I see the landing screen for a brand new workflow
    And "Lab results" is not shown, and no settings, code, run or AI panel is open

  @S25 @pending
  Scenario: Only one creation dialog is open at a time
    # Value: two half-finished creation paths can't compete to create the workflow.
    # createUIStore.ts:211-243; createUIStore.modals.test.ts:34-55
    Given the template browser is open
    When the YAML import dialog is opened
    Then the template browser is closed

  @S26 @pending
  Scenario: Closing a creation dialog returns to the landing screen
    # Value: users can back out of a starting point and choose another.
    # TemplateBrowserModal.tsx:103-108, :126-133; YAMLImportModal.tsx:22-30, :189-195; YAMLImportModal.test.tsx:162-170
    Given the YAML import dialog is open
    When I click "Cancel"
    Then the dialog closes and the landing screen is shown
    And the same happens when I press Escape or click "Close" on the template browser

  @S27 @pending @variant:activation-limited
  Scenario: At the activation limit a new workflow is created with its triggers off
    # Value: users at their plan's activation limit can still create and build workflows without exceeding the limit.
    # session.ex:934-963; workflow.ex:150-160; session_test.exs:1422-1480
    Given project "Malawi HIV" is at its workflow activation limit
    When I click "Build from scratch"
    Then the workflow is created
    And its webhook trigger is saved disabled
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| After the first save the client patches the URL to `/w/:id` inside the same LiveView, so `mount` and the `:ensure_workflow_belongs_to_project` on_mount do not run again. The socket keeps `is_new_workflow: true`, `page_title: "New Workflow"` and no `current_workflow_id`. | `useWorkflow.tsx:451`; `react-component.tsx:73-79` (navigate is a LiveView patch); `collaborate.ex:94-98`, `:456-470`; `hooks.ex:138-158` | The browser tab keeps saying "New Workflow" until a reload. The LiveView deletion teardown in flow-delete-open-workflow keys on `current_workflow_id`, so this tab is not sent away by that path when the new workflow is deleted (the channel path may still cover it; shared-editor-session). | fix |
| Every creation path saves triggers enabled (the YAML default when `enabled` is absent is true, and the blank workflow and both shipped templates set `enabled: true`), while the workflow row gets the schema default state `:draft`. | `yaml/v1.ts:72-73`; `baseTemplates.ts:21-23`, `:51-53`, `:76-80`; `workflow.ex:64`; `webhooks_controller.ex:40` | A "Build from scratch" webhook URL accepts requests immediately, and a "Scheduled workflow" created from the template runs daily at midnight against `https://www.example.com`. With experimental features on, the workflow can read as Draft while its trigger is live. | decide |
| YAML validation that throws something other than a `WorkflowError` marks the import invalid but shows no error. | `YAMLImportModal.tsx:88-96` | "Create" disabled with "Fix validation errors to continue" and no error listed. | fix |
| At the activation limit a new workflow's triggers are switched off silently: creation saves with `notify: 'error-only'` and the limiter message is not shown. | `session.ex:939-946`; `useWorkflow.tsx:822` | A workflow appears with its trigger off and no explanation. | decide |
| If the server name check fails, import proceeds with the original name; a clash then fails the save on the unique index. | `createWorkflowStore.ts:1898-1908`; `workflows.ex:275-277` | A "Save failed: invalid workflow" or "Failed to save workflow" toast instead of a suffixed name. | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| The LiveView's placeholder name is "Untitled Workflow" while the resolver and the unique-name default use "Untitled workflow" | `collaborate.ex:461`; `workflow_resolver.ex:93`; `workflows.ex:295` | decide |
| Name suffixing appends to an already-numbered name ("My Workflow 1" becomes "My Workflow 1 1") and skips taken numbers ("My Workflow" becomes "My Workflow 2" when "1" is taken) | `workflows.ex:314-320`; `workflow_channel_test.exs:4427-4455` | decide |
| The workflow header, breadcrumbs and version picker are hidden until the first save, so the landing screen has no in-editor link back to the workflow list | `CollaborativeEditor.tsx:315-316` | decide |
| Once "Build with AI" dismisses the landing screen it cannot be shown again, and the AI panel has no close button on a new workflow; switching to a template or import needs a reload | `CollaborativeEditor.tsx:394-397`; `createUIStore.ts:204-209`; `AIAssistantPanelWrapper.tsx:790` | decide |
| Opening the AI panel on a new workflow clears whatever is on the canvas | `WorkflowEditor.tsx:245-272` | preserve |
| Keyboard Control+\ or Meta+\ opens the YAML import dialog, only while the landing screen is up | `WorkflowEditor.tsx:304-316` | preserve |
| Escape closes the creation dialogs through a keyboard-shortcut registration as well as the dialog's own handler | `TemplateBrowserModalWrapper.tsx:35-37`; `YAMLImportModal.tsx:22` | preserve |
| Uploading a file switches the dialog to paste mode with the file's text shown | `YAMLImportModal.tsx:110-114` | preserve |
| YAML validation is debounced by 300ms; the button reads "Validating..." meanwhile | `YAMLImportModal.tsx:72-99`, `:140-145` | preserve |
| Template search, browser reset and preview selection reset on every open; search box is disabled and "Loading templates..." shown while published templates load | `TemplateBrowserModalWrapper.tsx:40-48`; `TemplateBrowserModal.tsx:64-69`, `:174`, `:183-186` | preserve |
| A stale template fetch from a previous open cannot overwrite a newer one | `TemplateBrowserModalWrapper.tsx:51-77`; `TemplateBrowserModalWrapper.templateFetch.test.tsx:90-150` | preserve |
| The type comment says base templates "are labelled so users can tell them apart", but the cards show no label distinguishing shipped from published templates | `types/template.ts:24-28`; `TemplateBrowserModal.tsx:338-343` | decide |
| A successful Retry after a failed creation save runs with `notify: 'all'`, so it shows "Workflow saved" where the original path was silent | `useWorkflow.tsx:476-489`, `:572-573` | preserve |
| Saving the new workflow waits for the adaptor catalogue's first load | `session.ex:244-250`, `:352-368` | preserve |
| The channel's `save_workflow` checks `:edit_workflow`, not `:create_workflow`; the two currently allow the same roles | `workflow_channel.ex:300-313`, `:1950-1956`; `project_users.ex:39-49` | preserve |
| The LiveView generates a fresh workflow id on every mount, including a LiveView reconnect, while the React root keeps the first id (`phx-update="ignore"`) | `collaborate.ex:457`, `:256` | decide |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Credential and webhook auth modal events and their handle_info clauses | `collaborate.ex:145-233`, `:356-443` | the inspector that opens them is blocked while the workflow is new (`WorkflowEditor.tsx:285-292`); owned by workflow-editor-inspectors |
| `maybe_load_initial_run_data` run branch | `collaborate.ex:106-114` | short-circuited for new workflows (`:100-104`) |
| `deduplicateJobNames` on import | `createWorkflowStore.ts:1840-1870` | the parser throws `DUPLICATE_JOB_NAME` first (`yaml/v1.ts:250-262`) on every path from this view |
| `parseWorkflowTemplate` lenient template parsing | `yaml/util.ts:66-93` | the template browser uses the strict parser (`templateWorkflowState.ts:46-48`); only `yaml/TemplateToWorkflow.ts` calls the lenient one |
| `YAMLCodeEditor` `isValidating` prop | `YAMLCodeEditor.tsx:13`, `:41` | passed by `YAMLImportModal.tsx:176` but never read |
| `ValidationErrorDisplay` `onDismiss` | `ValidationErrorDisplay.tsx:62-70` | `YAMLImportModal.tsx:183` never passes it |
| `WorkflowUsageLimiter.limit_workflow_creation/1` | `workflow_usage_limiter.ex:45-50` | no caller in `lib/` |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| YAML uploads capped at 8MB | `YAMLFileDropzone.tsx:46-52` | yes, error message and "up to 8MB" hint | preserve |
| `list_templates` returns every template on the instance, unpaginated, and the browser filters client-side | `workflow_templates.ex:146-150`; `filterTemplates.ts:24-30` | no, until the catalogue is large | preserve |
| Save request timeout 75s on the client | `createWorkflowStore.ts:157`, `:1571` | yes, as a save failure toast | preserve |
| Server save waits up to the adaptor catalogue first-load timeout plus 10s | `session.ex:244-250` | yes, as a slow first create on a cold node | preserve |
| YAML validation debounce 300ms | `YAMLImportModal.tsx:98` | barely | preserve |

### 6.5 Things seen but not understood

- Published templates carry `positions` to the client (`workflow_channel.ex:1495-1505`), but the browser builds both preview and workflow from `code` only (`templateWorkflowState.ts:46-48`). Whether a published layout should survive into the new workflow is unclear.
- The template catalogue is instance-wide: every editor sees every published template, including its job code, whichever project it came from (`workflow_templates.ex:146-150`). Publishing is limited to support users (`project_users.ex:144-150`), which suggests a curated catalogue, but this was not confirmed.
- `collaborate_new_test.exs:7-157` tests the sandbox root project and display name attributes on `/w/new`, but the header that would show them is hidden until the first save (`CollaborativeEditor.tsx:315-316`); where they are visible on this view was not established.
- The YAML parser's `id` (`yaml/v1.ts:167`) may differ from the room's workflow id; how `YAMLStateToYDoc` reconciles a YAML-supplied workflow id with the generated one was not traced.
- The first creation save reconciles AI chat sessions for the unsaved workflow (`session.ex:528-533`); whether that matters outside the AI path was not traced (owned by workflow-editor-ai-assistant).

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should a workflow created from the landing screen start with its triggers enabled (6.1 row 2)? This decides whether a new webhook URL or the "Scheduled workflow" cron goes live on create.
- Should users be told when their new workflow's triggers were switched off by the activation limit (6.1 row 4)?
- Is the instance-wide template catalogue intended (6.5)?
- After first save, should the LiveView be remounted at `/w/:id` (navigate) rather than patched, so title and deletion teardown match an opened workflow (6.1 row 1)?

---

## Proposed flows

- **flow-register-first-workflow**: a new user who signs up and already belongs to a project (for example the starter project created under `init_project_for_new_user`) is redirected straight to that project's new workflow landing screen (`user_registration_controller.ex:28-49`). This view only asserts the landing. Surfaces: auth-register, controller:user-registration, workflow-editor-new.
- **flow-legacy-editor-redirect**: old legacy editor bookmarks `/projects/:project_id/w/new/legacy` and `/w/:id/legacy` redirect to the collaborative editor, forwarding the query string and renaming `a` to `run` (`legacy_redirect_controller.ex:17-44`, `router.ex:310-311`, `legacy_redirect_controller_test.exs`). This view only asserts that `/w/new/legacy` lands here. Surfaces: controller:legacy-redirect, workflow-editor-new, workflow-editor-canvas.

## Proposed shared

- **shared-editor-session** (lead's id; inherited here as proposed). Plumbing this view relies on: the ReactComponent mount and data attributes (`collaborate.ex:252-287`); the channel join with action "new" and its rejoin as "edit" after the first save (`SessionProvider.tsx:89-107`, `workflow_channel.ex:43-112`, `:2214-2237`); connected and connecting state used to gate creation (`useWorkflow.tsx:783-798`); `saveWorkflow` with its error toasts, persistent toast and Retry for new workflows (`useWorkflow.tsx:421-586`); the first-save transition (URL patch, `clearIsNewWorkflow`, fit view; `useWorkflow.tsx:440-460`) and the channel's self-promotion to `:existing` (`workflow_channel.ex:870-876`); the header hidden while new (`CollaborativeEditor.tsx:315-316`); limits delivered in the session context (`workflow_channel.ex:1381`, `:2437-2452`); the write guard on `importWorkflow` (`createWorkflowStore.ts:284-290`, `:1896`). Surfaces: workflow-editor-new and every workflow-editor-* panel.
- **shared-workflow-yaml-format**: the workflow YAML parser and error model (`assets/js/yaml/`: v1 and v2 detection `yaml/util.ts:41-58`, trigger defaults `yaml/v1.ts:72-73`, duplicate-name rejection `:250-262`, error codes and messages `workflow-errors.ts:3-23`, `:219-247`). Used by this view's import, templates and blank workflow, and by the AI assistant's apply path (`useAIWorkflowApplications.ts:290-300`) and the canvas code export. Surfaces: workflow-editor-new, workflow-editor-ai-assistant, workflow-editor-inspectors (code panel), project export.

## Lead resolution (batch 5)

- `shared-workflow-yaml-format` and `flow-legacy-editor-redirect` created. `flow-register-first-workflow` is held until auth-register is catalogued.
- `shared-editor-session` created.
