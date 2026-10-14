---
id: workflow-editor-ai-assistant
type: view
title: Workflow editor › AI assistant panel
status: not-started
owner:

trigger:
  old_route: /projects/:project_id/w/:id?chat=true[&w-chat=<session id>|new]  (also /w/new, opened by "Build with AI")
  new_route:
  old_route_disposition: unchanged
  reachable_when:
    - everything shared-editor-session lists under reachable_when (project scope, workflow belongs to the project, editor channel joined)
    - the panel is open: ?chat=true on load of /w/:id (createUIStore.ts:79-96), the header button or Cmd/Ctrl+K (AIButton.tsx:24-30; AIAssistantPanelWrapper.tsx:149-156), or "Build with AI" on /w/new (workflow-editor-new S20)
    - the header button and Cmd/Ctrl+K need the instance to have the assistant configured and the latest version open (Header.tsx:365-369, :904-908; AIAssistantPanelWrapper.tsx:155); ?chat=true does not check either (6.1)
    - the AI channel join is authorised against the session's project (ai_assistant_channel.ex:34-104, :835-945)

inherits:
  - shared-authenticated-session    # the AI channel rides the same user socket (user_socket.ex:13); a revoked account loses it with the rest
  - shared-project-scope            # LiveView half of removal (S07), role change (S08), support revoked (S09), deletion (S10)
  - shared-editor-session           # the shared Y.Doc AI changes land in, the Save that commits them, read-only states, limits in the session context
  - shared-workflow-yaml-format     # parsing, validation and the YAML-to-Y.Doc write behind apply, revert and restore (its S01-S11, and its 6.2 note on error copy here)
  - shared-flash-messages   # added by lead (final pass)

url_params:
  - name: chat
    set_by: this panel (useAIPanelURLSync.ts:50-78); any shared link
    effect: "true" opens the panel on load of an existing workflow; ignored on /w/new (createUIStore.ts:79-96)
  - name: w-chat
    set_by: this panel when a conversation starts or is picked (AIAssistantPanelWrapper.tsx:267-283, :340-361, :445-451; useAIPanelURLSync.ts:91-118)
    effect: "new" joins a new conversation once there is a first message; an id joins that conversation (useAISession.ts:133-231)
  - name: j-chat
    set_by: nothing reachable; mode is always workflow_template (useAIMode.ts:81-86)
    effect: none (6.3)
  - name: panel / job
    set_by: workflow-editor-ide; this panel's "open step" (AIAssistantPanelWrapper.tsx:211-228)
    effect: with the IDE open on a job, the assistant's page is that job and its code goes with each message (useAIMode.ts:42-75)
  - name: run
    set_by: run links and the IDE (workflow-editor-ide, flow-open-run-in-editor)
    effect: offers "Send run logs" and "Send run data" for that run (ChatInput.tsx:212-216, :253-285; AIAssistantPanel.tsx:121, :479)
  - name: v / release / as_run
    set_by: version pickers and run links (shared-editor-session)
    effect: AI button disabled; switching to one closes the panel and its conversation (useAIPanelDiffManager.ts:77-98)

config_variants:
  default: {}                                                                  # Apollo not configured: AiAssistant.enabled? false (ai_assistant.ex:80-84)
  ai-enabled: { apollo.endpoint: <url>, apollo.ai_assistant_api_key: <key> }   # read at collaborate.ex:84; most scenarios read under this one
  ai-limit-reached: { ai-enabled, UsageLimiter.limit_action(%Action{type: :ai_usage}): {:error, _, %Message{}} }   # limiter.ex:15-19; the default adapter always returns :ok (extensions/usage_limiter.ex:11)
  experimental-features: { ai-enabled, user.preferences.experimental_features: true }   # live content lock blocks AI changes (useWorkflow.tsx:1096-1101)

inventory:
  routes:
    - live /projects/:project_id/w/:id  WorkflowLive.Collaborate :edit    # router.ex:303; owned by shared-editor-session; this view is the ?chat= state
    - get /api/ai_assistant/sessions  API.AiAssistantController :list_sessions   # router.ex:140 (cookie-authenticated JSON)
  events:
    - AiAssistantChannel#join                     # ai_assistant_channel.ex:34-104
    - AiAssistantChannel#new_message              # :111-130
    - AiAssistantChannel#retry_message            # :136-153
    - AiAssistantChannel#update_context           # :156-174
    - AiAssistantChannel#apply_failed             # :184-206
    - AiAssistantChannel#apply_applied            # :209-215
    - AiAssistantChannel#list_sessions            # :218-256
    - AiAssistantChannel handle_info message_status_changed, streaming_chunk, streaming_status, streaming_changes, streaming_segment, streaming_error   # :342-466
    - AiAssistantChannel handle_info ProjectUserAdded, ProjectUserRemoved, ProjectUserRoleChanged, ProjectDeletionScheduled, WorkflowDeleted, SupportAccessUpdated   # :475-532
    - WorkflowChannel#start_applying_workflow, #done_applying_workflow, #start_applying_job_code, #done_applying_job_code   # workflow_channel.ex:773-831
    - workflow:collaborate:<id> ai_session_created (Endpoint.broadcast)   # ai_assistant_channel.ex:1590-1615; createAIAssistantStore.ts:784-818
  js_hooks: []                                    # React only; mounted by the CollaborativeEditor ReactComponent (shared-editor-session)
  react_components:
    - components/AIAssistantPanelWrapper.tsx
    - components/AIAssistantPanel.tsx
    - components/ChatInput.tsx
    - components/MessageList.tsx
    - components/SessionList.tsx
    - components/AIButton.tsx
    - components/AIDisclaimerFooter.tsx
    - lib/AIChannelRegistry.ts
    - stores/createAIAssistantStore.ts
    - hooks/useAIAssistant.ts, useAIChannelRegistry.ts, useAIInitialMessage.ts, useAIMode.ts, useAIPanelDiffManager.ts, useAIPanelURLSync.ts, useAISession.ts, useAIWorkflowApplications.ts, useAIWorkflowUndo.ts, useAppliedCanvas.ts, useAutoPreview.ts
  policies:
    - Lightning.Policies.Workflows (:access_read, :access_write; both are ProjectUsers :access_project) (policies/workflows.ex:14-22; ai_assistant_channel.ex:934-936; ai_assistant_controller.ex:122-127, :159-164)
    - Lightning.Policies.ProjectUsers (:edit_workflow for update_context and workflow binding) (ai_assistant_channel.ex:930-932, :1549-1569)
  workers:
    - Lightning.AiAssistant.MessageProcessor (queue ai_assistant, max_attempts 1)      # message_processor.ex:9-11
    - Lightning.AiAssistant.StuckMessageReaper (cron */5, queue background)           # stuck_message_reaper.ex:15-19; bootstrap.ex:292
  api_endpoints:
    - API.AiAssistantController#list_sessions
    - external: Apollo POST /services/global_chat/stream (job_chat/stream and workflow_chat/stream for legacy sessions only, 6.3)   # apollo_client.ex:57-186
  emails: []
  config:
    - :lightning, :apollo endpoint, ai_assistant_api_key (APOLLO_ENDPOINT, AI_ASSISTANT_API_KEY)   # bootstrap.ex:168-178
    - :lightning, :apollo connect_timeout, idle_timeout, request_timeout (APOLLO_*_TIMEOUT_MS)   # config.exs:16-19; bootstrap.ex:143-177
    - Oban queue ai_assistant: 10; shutdown_grace_period 6 min   # bootstrap.ex:332-345
    - usage limiter adapter (:ai_usage action, increment_ai_usage)
  not_reachable_here:
    - Job-chat and workflow-chat sessions and their Apollo endpoints (see 6.3)
    - "Add" buttons on code blocks; job-code Apply and Preview on non-global replies (see 6.3)
    - update_context with a workflow_id (see 6.3)
    - LandingScreen "Build with AI" prompt and the canvas clear on open for /w/new (owned by workflow-editor-new)
    - CollaborativeMonaco showDiff/clearDiff rendering (owned by workflow-editor-ide)
    - switch_to_draft itself (owned by workflow-editor-canvas)

related:
  - workflow-editor-new          # "Build with AI" hands its prompt to this panel (its S20)
  - workflow-editor-ide          # job page context and code diff preview (its S20)
  - workflow-editor-canvas       # Save disabled while an AI apply runs; switch to draft
  - lib/lightning_web/channels/ai_assistant_channel.ex
  - lib/lightning_web/channels/ai_assistant_json.ex
  - lib/lightning_web/controllers/api/ai_assistant_controller.ex
  - lib/lightning/ai_assistant/ai_assistant.ex
  - lib/lightning/ai_assistant/message_processor.ex
  - lib/lightning/ai_assistant/stuck_message_reaper.ex
  - lib/lightning/ai_assistant/limiter.ex
  - lib/lightning/ai_assistant/chat_session.ex
  - lib/lightning/ai_assistant/chat_message.ex
  - lib/lightning/apollo_client.ex
  - test/lightning_web/channels/ai_assistant_channel_test.exs
  - test/lightning_web/controllers/api/ai_assistant_controller_test.exs
  - test/lightning/ai_assistant/
  - assets/test/collaborative-editor/ (AIAssistantPanel, ChatInput, MessageList, SessionList, useAI*, AIChannelRegistry tests)
flows:
  - flow-workflow-api-edit-conflict       # AI changes only touch the open editor's shared draft; while it is open, API writes are refused there
  - flow-delete-open-workflow             # its S02: the AI channel for the deleted workflow stops (ai_assistant_channel.ex:499-506)
  - flow-schedule-project-deletion        # its S04: the AI channel stops (ai_assistant_channel.ex:491-493)
  - flow-account-revocation-teardown
  - flow-ai-session-collaborators
---

## 1. Purpose

People building or fixing a workflow ask the AI assistant to explain, write or change it without
leaving the editor. The assistant reads the workflow as it stands, writes its changes straight onto
the shared canvas for the person who asked, and keeps every conversation with the project so the
team can come back to it. Getting this wrong means changes nobody asked for (or nobody can undo)
landing on a workflow that moves health data, a viewer using the assistant to get around edit
rights, run data leaking to a project it doesn't belong to, or questions and answers silently lost.

## 2. What it does

- Members with the assistant configured open and close the panel from the header, Cmd/Ctrl+K or a `?chat=true` link
- The panel is unavailable on older versions and on instances without the assistant
- Members start a conversation with a first message, and every message carries the current workflow
- Replies stream in, and nobody can send again until the answer is in
- Changes the assistant writes land on the canvas for the person who asked, unsaved
- Applied changes keep each step's credential
- On a new workflow, the assistant's first workflow is saved for the person who asked
- On a new workflow, the assistant's changes wait for a connection rather than being lost
- A change that did not reach the canvas says so, offers a retry and is still flagged after reload
- The person who asked can revert the last reply's changes, and restore them
- Viewers can ask but cannot apply changes or change the assistant's job context
- On a live workflow (experimental), the assistant cannot change it and offers "Switch to draft"
- A failed reply says why and offers "Try again"
- Text that streamed before a failure is kept
- A reply whose code edit failed says so and offers to try again
- A message stuck by a crash or deploy is released with a reason
- When the project's AI quota is spent, the panel says so and blocks sending
- Members browse, search, page through and reopen this workflow's conversations
- Conversations are shared with everyone on the project
- Non-members and unenrolled members of MFA projects cannot read or join conversations
- With a run open, members attach its logs and the shape of its data
- A run from another project is never attached
- Messages are limited to 10,000 characters, with a countdown near the limit
- A conversation started on an unsaved workflow or job stays with it once saved
- Losing access to the project closes the assistant; becoming a viewer does not
- Project deletion and workflow deletion close the assistant (handoff)
- Members can read what the assistant sends and stores before they use it
- Members open a step the assistant changed straight in the code editor

## 3. Who can do what

Source: `lib/lightning/policies/workflows.ex:14-22` (`:access_read` and `:access_write` are both
`ProjectUsers :access_project`); `lib/lightning/policies/project_users.ex:39-49`, `:134-136`, `:160-172`,
`:190-194`; channel resolution `ai_assistant_channel.ex:831-945`, `:1539-1569`; controller
`ai_assistant_controller.ex:96-164`; client gate `AIAssistantPanelWrapper.tsx:189-191`,
`useWorkflow.tsx:1036-1112`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See the panel and the project's conversations for this workflow | yes | yes | yes | yes | no | yes, when support access is on |
| Start a conversation, send, retry | yes | yes | yes | yes | no | yes, when support access is on |
| Attach a run's logs or data | yes | yes | yes | yes | no | yes, when support access is on |
| Have replies applied to the canvas, Apply, Revert, Restore | no | yes | yes | yes | no | yes, when support access is on |
| Update the job context the assistant reads (`update_context`) | no | yes | yes | yes | no | yes, when support access is on |
| List conversations through `/api/ai_assistant/sessions` | yes | yes | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- The instance must have the Apollo endpoint and key configured, or the header button and Cmd/Ctrl+K are disabled (`ai_assistant.ex:80-84`; `Header.tsx:365-369`, `:906`).
- On a pinned version, release or as-run view the header button is disabled and the panel closes (`Header.tsx:367-368`; `useAIPanelDiffManager.ts:88-97`).
- Members of an MFA-required project who have not enrolled are refused (`project_users.ex:134`).
- Every inbound frame re-reads the session row and re-authorises; joining is a snapshot (`ai_assistant_channel.ex:1539-1569`).
- Applying changes also requires the workflow not to be read-only: deleted, pinned, live-locked (experimental) or an unsaved new workflow already holding content, except that a new workflow may always take the assistant's output (`AIAssistantPanelWrapper.tsx:189-191`; `useWorkflow.tsx:1067-1112`).
- Only the person whose message triggered a reply has it auto-applied in their browser (`AIAssistantPanelWrapper.tsx:722-730`; `useAIWorkflowApplications.ts:708-731`).
- The project's AI quota, when an adapter enforces one, blocks new messages and retries (`ai_assistant_channel.ex:119`, `:142-148`).
- A session with no project, job or unsaved workflow falls back to "creator only" (`ai_assistant_channel.ex:861-868`, `:884-891`; `ai_assistant_controller.ex:152-157`).

## 4. What it touches

**Reads**: `ai_chat_sessions`, `ai_chat_messages`, `users`, `projects`, `project_users`, `workflows`, `jobs`, `runs`, `steps`, `dataclips` (scrubbed), `log_lines`, `oban_jobs` (reaper only); the client also reads the shared Y.Doc to serialise the workflow (`AIAssistantPanelWrapper.tsx:413-427`, `:473-490`)

**Writes**
- `ai_chat_sessions`: insert on a first message with the title cut from it (`ai_assistant.ex:233-282`, `:1115-1136`); `meta` merged per message (`:737-743`); `runtime_context` per job context update (`ai_assistant_channel.ex:236-271`); `follow_run_id` on join (`:722-736`); `workflow_id`/`job_id` linked and `unsaved_*` dropped on first save (`session.ex:528-533`; `ai_assistant.ex:297-415`)
- `ai_chat_messages`: user message insert (`ai_assistant.ex:667-687`); status `processing`/`success`/`error` with failure category and sentence (`message_processor.ex:456-518`); assistant reply or partial reply insert (`ai_assistant.ex:1152-1257`); `meta.apply_failed` set or cleared (`ai_assistant.ex:813-835`); status reset to `pending` on retry (`:1008-1026`)
- `oban_jobs`: a `MessageProcessor` job per pending user message and per retry, in the same transaction (`ai_assistant.ex:745-754`, `:1008-1026`)
- The shared Y.Doc (not the database) on apply, revert and restore (`useAIWorkflowApplications.ts:291-306`; `useAIWorkflowUndo.ts:74-105`); persistence is shared-editor-session's

**Immediate side effects** (in the same request)
- `ai_session_created` broadcast to `workflow:collaborate:<workflow id>` when a new conversation starts (`ai_assistant_channel.ex:57-60`, `:1590-1615`)
- `user_message` broadcast to everyone on the conversation (`ai_assistant_channel.ex:1355-1358`, `:1438-1441`); `message_status_changed` on retry (`:1504-1510`)
- `workflow_applying` / `workflow_applied` (and job-code equivalents) to everyone in the editor room around each apply, revert or restore (`workflow_channel.ex:773-831`; `createWorkflowStore.ts:2003-2063`)
- Sentry warning "AI assistant workflow apply failed" with the stage, no content (`ai_assistant_channel.ex:184-206`)

**Deferred side effects** (later, elsewhere)
- `MessageProcessor` marks the message `processing`, streams from Apollo, saves the reply, marks `success` or `error`, and broadcasts each step on `ai_session:<id>`, which the channel relays to every subscriber (`message_processor.ex:39-88`, `:405-415`; `ai_assistant_channel.ex:342-466`)
- AI usage is incremented in the same transaction as each assistant reply (`ai_assistant.ex:681`, `:1874-1896`)
- Oban exception and non-success stop handlers mark the message `error` and report to Sentry (`message_processor.ex:538-689`; `oban_manager.ex:15`, `:57`)
- `StuckMessageReaper` every 5 minutes errors messages left `processing` past the grace period and tells the panel (`stuck_message_reaper.ex:34-109`)
- Saving the workflow (shared-editor-session) relinks conversations started on unsaved jobs and workflows (`session.ex:528-533`)

**External, non-transactional effects**
- Apollo: `POST /services/global_chat/stream` with the message, workflow YAML, page, history, session meta (including any `runtime_context` job code), user id and persona, metrics opt-in, and any run attachments (`apollo_client.ex:157-186`; `ai_assistant.ex:908-922`, `:977-1003`; `message_processor.ex:156-261`). Apollo calls Anthropic, which keeps messages up to 30 days per the About copy (`AIAssistantPanel.tsx:569-571`). Nothing can be recalled if the job then fails.
- Sentry messages on apply failure, AI timeouts and stops (`ai_assistant_channel.ex:189-201`; `message_processor.ex:597-617`, `:668-687`)
- The usage limiter adapter, when a hosted one is configured (`limiter.ex:15-19`; `ai_assistant.ex:1891`)

**Depends on config**
- Apollo endpoint and key (variant `ai-enabled`); Apollo timeouts bound how long a reply may run
- Usage limiter adapter (variant `ai-limit-reached`)
- `experimental_features` user preference (content lock, variant `experimental-features`)

**Product limits** (limits a user would notice and that we intend to keep)
- A message is at most 10,000 characters (`ChatInput.tsx:60`; `chat_message.ex:137`, `:243`) (S26)
- The project's AI quota, when enforced (S19, S20)

## 5. Scenarios

Verified against `ai-enabled` unless tagged. All read from code and tests; nothing was run.

```gherkin
Feature: AI assistant in the workflow editor
  In order to build and fix workflows faster without handing over control of them
  As a member of a project
  I want to ask an assistant about the workflow and have its changes land where I can review and save them

  @S01 @pending
  Scenario: Without the assistant configured, the AI button says why it is off
    # Value: people on instances without AI aren't offered something that can't work, and know who to ask.
    Given the instance has no Apollo endpoint or key
    And I have workflow "Intake" open
    Then the AI button in the header is disabled
    And hovering it shows "Your instance does not have build-time AI enabled. Contact your administrator or support@openfn.org to configure it."
    And Cmd/Ctrl+K does nothing
    # Header.tsx:365-369, :904-908; AIAssistantPanelWrapper.tsx:149-156; ai_assistant.ex:80-84; collaborate.ex:84, :277
    # Header.test.tsx:1426-1452

  @S02 @pending
  Scenario: Members open and close the assistant without leaving the workflow
    # Value: help is at hand next to the workflow, and a link can bring a colleague straight to it.
    Given I have workflow "Intake" open
    When I click the AI button
    Then the "Assistant" panel opens and the URL has "chat=true"
    And hovering the button shows "Close AI Assistant" with the Cmd/Ctrl+K shortcut
    When I press Cmd/Ctrl+K
    Then the panel closes and "chat", "w-chat" and "j-chat" leave the URL
    When I open "/projects/<id>/w/<Intake id>?chat=true"
    Then the panel is open on load
    # AIButton.tsx:15-64; AIAssistantPanelWrapper.tsx:149-156; useAIPanelURLSync.ts:50-78; createUIStore.ts:79-96, :173-195
    # useAIPanelURLSync.test.ts:51-88; Header.test.tsx:1399-1425

  @S03 @pending
  Scenario: The assistant is not available on an older version
    # Value: the assistant never reads or writes a version that is no longer the one being edited.
    Given I have workflow "Intake" open with the assistant panel open
    When I switch to version 3 of "Intake"
    Then the panel closes and its conversation is cleared from the URL
    And the AI button is disabled with "Switch to the latest version of this workflow to use the AI Assistant."
    # useAIPanelDiffManager.ts:77-98; Header.tsx:367-368, :906; AIAssistantPanelWrapper.tsx:155
    # Header.test.tsx:1453-1482

  @S04 @pending
  Scenario: A first message starts a conversation
    # Value: questions and answers are kept, titled, and reachable by link, so work with the assistant isn't lost.
    Given I am an editor with "Intake" open and the panel showing "No conversations yet"
    When I type "Add a step that posts to DHIS2" and press Enter
    Then a conversation titled "Add a step that posts to DHIS2" is created
    And my message shows "Sent by <my name>"
    And the URL has "w-chat=<conversation id>"
    # AIAssistantPanelWrapper.tsx:381-457; useAISession.ts:172-184; AIChannelRegistry.ts:917-937
    # ai_assistant_channel.ex:34-73, :600-660; ai_assistant.ex:233-282, :1115-1136; MessageList.tsx:1483-1500
    # ai_assistant_channel_test.exs:617-646, :4359-4387

  @S05 @pending
  Scenario: Every message carries the workflow as it is now
    # Value: answers are about the workflow on screen, including edits nobody has saved yet, not a stale copy.
    Given I have "Intake" open with an unsaved new step "Clean data"
    When I ask "What does this workflow do?"
    Then the request to the assistant includes the workflow with "Clean data"
    And with the code editor open on "Clean data", the page sent is "workflows/Intake/Clean data"
    # AIAssistantPanelWrapper.tsx:413-440, :473-507; useAIMode.ts:42-75; message_processor.ex:156-171; apollo_client.ex:157-186
    # ai_assistant_channel_test.exs:4506-4553, :4586-4631

  @S06 @pending
  Scenario: A reply streams in and sending waits until it is done
    # Value: long answers show progress, and nobody fires a second request that would race the first.
    Given I have sent a message in a conversation
    Then I see a status such as "Thinking..." while the assistant works
    And the reply text appears as it arrives and stays once complete
    And the message box is disabled until the reply is in
    # ai_assistant.ex:1532-1572; ai_assistant_channel.ex:342-376, :404-457; AIChannelRegistry.ts:167-276, :755-777
    # createAIAssistantStore.ts:412-494; ChatInput.tsx:205-208, :294; MessageList.tsx:1236-1250
    # ai_assistant_channel_test.exs:4188-4291; AIChannelRegistry.test.ts:201-305

  @S07 @pending
  Scenario: The assistant's workflow changes land on the canvas for the person who asked, unsaved
    # Value: the asker sees the proposed workflow at once, and nothing reaches production until someone saves it.
    Given I am an editor with "Intake" open
    When I ask "Add a step that posts to DHIS2" and the reply changes the workflow
    Then the canvas shows the new step as the reply arrives
    And "Save" shows unsaved changes (shared-editor-session S19)
    And the reply lists the changed steps
    And the YAML is parsed and written as shared-workflow-yaml-format describes
    # AIAssistantPanelWrapper.tsx:707-759, :806-870; useAIWorkflowApplications.ts:224-391, :445-483, :646-743
    # MessageList.tsx:1187-1230, :1252-1268; useAIWorkflowApplications.autoApply.test.ts:141-222; useAIWorkflowApplications.workflowAutoSave.test.ts:108-144
    # handoff: shared-workflow-yaml-format, shared-editor-session

  @S08 @pending
  Scenario: Applied changes keep each step's credential
    # Value: accepting an AI change does not silently disconnect a step from the system it talks to.
    Given step "Send to DHIS2" uses credential "DHIS2 prod"
    When an applied reply rewrites "Send to DHIS2"
    Then "Send to DHIS2" still uses "DHIS2 prod"
    # useAIWorkflowApplications.ts:300-305; useAIWorkflowUndo.ts:86-88; useAIWorkflowApplications.workflow.test.ts:182-224

  @S09 @pending
  Scenario: On a new workflow, the assistant's workflow is created for the person who asked
    # Value: starting from a description ends with a real workflow, not a canvas that vanishes on reload.
    Given I started a new workflow with "Build with AI" (workflow-editor-new S20)
    When the reply carries a workflow
    Then it is applied and saved with errors only reported
    And a validation failure appears as an assistant message instead of a toast
    # AIAssistantPanelWrapper.tsx:588-600; useAIWorkflowApplications.ts:202-215, :317-341; useAIInitialMessage.ts:83-144
    # useAIWorkflowApplications.workflowAutoSave.test.ts:68-107, :145-178
    # handoff: workflow-editor-new (creation), shared-editor-session S06/S09 (save and retry toast)

  @S10 @pending
  Scenario: On a new workflow, changes wait for a connection
    # Value: a new workflow is never left on screen with nothing behind it.
    Given I am creating a new workflow and my editor connection has dropped
    When the assistant's reply carries a workflow
    Then I see "Not connected" with "Connect to the server before creating a workflow."
    And while the editor is still joining I see "Still connecting" instead
    And once I reconnect the workflow is applied and saved
    # useAIWorkflowApplications.ts:257-262, :445-458, :751-760; useWorkflow.tsx:748-762
    # useAIWorkflowApplications.workflowOfflineGate.test.ts:55-200

  @S11 @pending
  Scenario: A change that did not reach the canvas says so and can be retried
    # Value: a reply is never mistaken for changes that actually landed, even after a reload.
    Given the assistant replies with a workflow that cannot be applied
    Then I see "Failed to apply workflow" with the reason
    And the reply says "These changes were not applied to the canvas." with "Try again"
    And there is no "Revert changes" on it
    When I reload the page and reopen the conversation
    Then the reply still says the changes were not applied
    When I click "Try again" and the apply succeeds
    Then the notice is gone and the server forgets the failure
    # useAIWorkflowApplications.ts:321-341, :417-483; MessageList.tsx:1356-1380, :1029-1047
    # ai_assistant_channel.ex:184-215, :1064-1072; ai_assistant.ex:813-835
    # ai_assistant_channel_test.exs:214-321; MessageList.test.tsx:1787; useAIWorkflowApplications.workflow.test.ts:143-181, :258-292

  @S12 @pending
  Scenario: The last reply's changes can be reverted and restored
    # Value: people can back out an AI change without hand-editing, and are warned before losing their own edits.
    Given the assistant's last reply changed "Intake" and I have edited nothing since
    When I click "Revert changes" on that reply
    Then the workflow is back as it was before the reply, and the control reads "Restore changes"
    Given instead I edited the workflow after the reply
    When I click "Revert changes"
    Then I see "Reverting replaces the whole workflow" with "Revert anyway"
    And only the last settled reply offers "Revert changes"
    # MessageList.tsx:478-498, :1029-1047, :1460-1478; useAIWorkflowUndo.ts:55-139; useAppliedCanvas.ts:27-50
    # AIAssistantPanelWrapper.tsx:876-897; MessageList.undoChanges.test.tsx:68-154

  @S13 @pending
  Scenario: Viewers can ask but cannot change the workflow through the assistant
    # Value: the assistant is not a way around edit permissions.
    Given I am a viewer on the project with "Intake" open
    When I ask the assistant a question
    Then my message is sent and answered
    And no reply is applied to the canvas
    And "Apply" is disabled with "Cannot apply workflow in readonly mode"
    And a job context update I send is refused with "unauthorized"
    # ai_assistant_channel.ex:99-111, :156-174, :1549-1569; AIAssistantPanelWrapper.tsx:189-191, :713-714
    # useAIWorkflowApplications.ts:662; MessageList.tsx:648-655
    # ai_assistant_channel_test.exs:1411-1452, :1496-1534; useAIWorkflowApplications.autoApply.test.ts:330-393

  @S14 @pending @variant:experimental-features
  Scenario: On a live workflow the assistant offers to switch to draft
    # Value: the assistant never edits a workflow that is processing data in production.
    Given "Intake" is live outside a sandbox and I have experimental features on
    When I open the assistant
    Then I see "The Assistant cannot make changes while this workflow is live." with "Switch to draft"
    And replies are not applied
    When I click "Switch to draft"
    Then I see "This takes the workflow out of production. Its triggers will be turned off and it will stop processing data until you go live again."
    # AIAssistantPanel.tsx:434-459, :670-680; useWorkflow.tsx:1096-1101; AIAssistantPanelWrapper.tsx:189-191
    # handoff: workflow-editor-canvas owns switch to draft

  @S15 @pending
  Scenario: A failed reply says why and can be tried again
    # Value: a transient AI failure costs a click, not the question.
    Given the assistant fails to answer "What does this do?" with "The connection to the assistant was lost. Please try again."
    Then the reply area shows "The connection to the assistant was lost." with "Try again"
    And my question is not marked failed a second time
    When I click "Try again"
    Then the question is sent again and the button disappears
    # message_processor.ex:274-326; ai_assistant.ex:1321-1372, :1612-1650; ai_assistant_channel.ex:136-153, :1501-1517
    # MessageList.tsx:781-829, :1147-1166, :1501-1507; AIChannelRegistry.ts:582-616
    # MessageList.test.tsx:207-293, :413, :542; ai_assistant_channel_test.exs:2342-2437, :510-556

  @S16 @pending
  Scenario: Text that streamed before a failure is kept
    # Value: an answer the person watched appear does not vanish because the connection dropped at the end.
    Given the assistant's reply stops partway through
    Then the text that arrived stays on screen with the failure reason below it
    And it is still there after reload
    # ai_assistant.ex:1167-1170, :1204-1257; ai_assistant_channel.ex:369-373, :1112-1128; AIChannelRegistry.ts:780-799
    # ai_assistant_channel_test.exs:442-509; stream_failure_test.exs; AIChannelRegistry.test.ts:170-200

  @S17 @pending
  Scenario: A reply whose code edit failed says so
    # Value: nobody believes a code change was made when the assistant could not make it.
    Given the assistant answers but could not apply its edit to a step's code
    Then the reply shows "I tried to update the code but couldn't apply the change." with "Try again"
    And "Try again" re-runs my question, and disappears once a later reply arrives
    # ai_assistant.ex:1701-1746; ai_assistant_channel.ex:1101; MessageList.tsx:1166-1180, :1382-1391
    # MessageList.test.tsx:584-660; ai_assistant_channel_test.exs:407-441

  @S18 @pending
  Scenario: A message stuck by a crash or deploy is released
    # Value: a dead job does not leave the conversation locked for everyone.
    Given a message has been "processing" longer than the reply time limit plus two minutes and its job is gone
    When the reaper runs
    Then the message shows "The assistant was interrupted before it finished." with "Try again"
    And the message box is enabled again
    # stuck_message_reaper.ex:34-109; message_processor.ex:424-435, :632-689; bootstrap.ex:292
    # stuck_message_reaper_test.exs:46-164

  @S19 @pending @variant:ai-limit-reached
  Scenario: When the AI quota is spent the panel says so
    # Value: people know why the assistant is unavailable instead of sending into nothing.
    Given project "Malawi HIV" has used its AI quota with the message "AI usage limit reached for this month"
    When I open the assistant on "Intake"
    Then I see "AI usage limit reached for this month" at the top of the panel
    And the message box is disabled and hovering it shows the same text
    # AIAssistantPanel.tsx:147-154, :405-420, :464-469; AIAssistantPanelWrapper.tsx:803; workflow_channel.ex:2429-2452

  @S20 @pending @variant:ai-limit-reached
  Scenario: A message sent after the quota runs out is kept but not answered
    # Value: the question isn't lost, nothing is spent, and the person knows why there is no answer.
    Given the quota runs out while I have the panel open
    When I send "Why did step 2 fail?"
    Then I see "Message limit exceeded" with the limit message
    And my message is shown as failed and is not sent to the assistant
    And "Try again" checks the quota again before sending
    # ai_assistant_channel.ex:111-130, :142-148, :1467-1474, :1489-1498; ai_assistant.ex:745-754; AIChannelRegistry.ts:485-499
    # ai_assistant_channel_test.exs:939-978

  @S21 @pending
  Scenario: Members browse and reopen this workflow's conversations
    # Value: past advice on a workflow is findable later instead of being asked for again.
    Given "Intake" has 25 conversations
    When I open "Conversations" from the panel menu
    Then I see the 20 most recently updated, each with its title, relative time and message count
    And "Load 5 more" loads the rest
    When I search "dhis2"
    Then only conversations whose title contains "dhis2" are listed
    When I click one
    Then its messages load and the URL has its id
    And conversations from other workflows are not listed
    # AIAssistantPanel.tsx:162-202, :313-342; SessionList.tsx:34-279; createAIAssistantStore.ts:295-373
    # ai_assistant_controller.ex:30-66; ai_assistant.ex:498-531, :1028-1070
    # SessionList.test.tsx:130-461; ai_assistant_controller_test.exs:513-557; ai_assistant_channel_test.exs:720-891

  @S22 @pending
  Scenario: Conversations are shared with everyone on the project
    # Value: the team can see what the assistant was asked and what it changed.
    Given editor "Amara" had a conversation on "Intake"
    When viewer "Ben" opens its link
    Then "Ben" sees every message, each attributed to who sent it
    # AIAssistantPanel.tsx:624-628; ai_assistant_channel.ex:874-892; MessageList.tsx:1490-1497
    # ai_assistant_channel_test.exs:3985-4093

  @S23 @pending
  Scenario Outline: People outside the project cannot read or join its conversations
    # Value: questions often quote job code and run errors; they must not leak outside the project.
    Given a conversation on workflow "Intake" in project "Malawi HIV"
    When <who> joins it or lists the project's conversations
    Then the join is refused with "unauthorized" and the listing with 403
    Examples:
      | who                                                      |
      | a registered user not on "Malawi HIV"                    |
      | a support user while support access is off               |
      | an editor who has not enrolled in MFA, on an MFA project |
    # ai_assistant_channel.ex:44-45, :874-945; ai_assistant_controller.ex:122-164; project_users.ex:134
    # ai_assistant_channel_test.exs:1536-1726, :2814-2915, :4326-4357; ai_assistant_controller_test.exs:225-245, :591-611

  @S24 @pending
  Scenario: With a run open, members attach its logs and the shape of its data
    # Value: the assistant can debug a real run without anyone pasting data, and field values never leave.
    Given I have run "R" of "Intake" open
    Then above the message box I see "Send run logs" and "Send run data", unticked
    When I tick "Send run data" and ask "Why did step 2 fail?"
    Then the assistant receives each step's input and output with values replaced by their types
    And the next time I open "Intake" "Send run data" is still ticked
    And with no run open neither box is offered
    # ChatInput.tsx:36-52, :80-186, :205-219, :253-285; message_processor.ex:176-261; scrubber.ex:195-198
    # ChatInput.test.tsx:65-85; AIChannelRegistry.test.ts:365-400; ai_assistant_channel_test.exs:4388-4439

  @S25 @pending
  Scenario: A run from another project is never attached
    # Value: one project's run logs and data cannot be sent to the assistant from another project.
    Given I am on "Malawi HIV" and run "X" belongs to a project I am not on
    When I send a message, or start a conversation, naming run "X"
    Then run "X" is dropped and nothing from it is attached
    # ai_assistant_channel.ex:737-775, :1001-1020; message_processor.ex:189-232
    # ai_assistant_channel_test.exs:1888-1933, :2074-2150, :4473-4505

  @S26 @pending
  Scenario: Messages over 10,000 characters cannot be sent
    # Value: people find out before sending that a message is too long, instead of losing it to a refusal.
    Given I have typed 9,500 characters
    Then I see "9,500 / 10,000"
    When I type past 10,000 characters
    Then the counter says it is too long to send and "Send" is disabled
    # ChatInput.tsx:56-63, :77-78, :205-208, :315-327, :334-336; chat_message.ex:137, :243
    # ChatInput.test.tsx:284-318

  @S27 @pending
  Scenario: A conversation started on an unsaved workflow stays with it once saved
    # Value: the conversation that produced a workflow is still there after the workflow is created.
    Given I started a conversation while creating a new workflow
    When the workflow is saved for the first time
    Then the conversation is listed under the saved workflow
    # session.ex:528-533; ai_assistant.ex:297-415; ai_assistant_channel.ex:631-648
    # unsaved_workflow_test.exs:89-246; unsaved_job_test.exs; ai_assistant_channel_test.exs:647-719

  @S28 @pending
  Scenario Outline: Losing access to the project closes the assistant
    # Value: a person whose access was taken away stops receiving the project's AI conversation straight away.
    Given <who> has a conversation open on "Intake"
    When <change>
    Then their assistant channel closes and further messages they send are refused with "unauthorized"
    Examples:
      | who                         | change                                 |
      | an editor                   | an admin removes them from the project |
      | a support user with no role | an owner turns support access off      |
    # ai_assistant_channel.ex:468-485, :507-516, :534-539, :1539-1569
    # ai_assistant_channel_test.exs:1176-1210, :1236-1312; LiveView side: shared-project-scope S07, S09

  @S29 @pending
  Scenario: Becoming a viewer keeps the conversation open
    # Value: a demotion takes away writing, not reading, so nobody loses a conversation they may still see.
    Given I am an editor with a conversation open
    When my role changes to viewer
    Then my assistant channel stays open and I can still list conversations and send messages
    And a job context update I send is refused
    # ai_assistant_channel.ex:468-485, :534-539; ai_assistant_channel_test.exs:1212-1234, :1411-1452

  @S30 @pending
  Scenario: Deleting the workflow or scheduling the project for deletion closes the assistant
    # Value: nobody keeps chatting with the assistant about, or spending quota on, something being removed.
    Given I have a conversation open on "Intake"
    When another member deletes "Intake"
    Then the flow "flow-delete-open-workflow" ends here: my assistant channel closes (its S02)
    When instead the project is scheduled for deletion
    Then the flow "flow-schedule-project-deletion" ends here: my assistant channel closes (its S04)
    # ai_assistant_channel.ex:487-506; ai_assistant_channel_test.exs:1314-1362

  @S31 @pending
  Scenario: Members can read what the assistant sends and keeps before they use it
    # Value: people decide what to share knowing it is stored, sent to a third party and visible to the project.
    Given I have the assistant open
    Then under the message box I see "Please use AI responsibly. Never share PII." with "Learn more."
    When I choose "About the AI Assistant" from the menu
    Then I see that messages are saved unencrypted, kept by Anthropic up to 30 days, not used for training, and shared with project collaborators
    And the menu links to "Responsible AI Policy"
    # AIDisclaimerFooter.tsx:7-37; AIAssistantPanel.tsx:343-372, :483-657
    # AIAssistantPanel.test.tsx:277-290, :313-394; ChatInput.test.tsx:53-64

  @S32 @pending
  Scenario: A step the assistant changed opens in the code editor
    # Value: people can read the code the assistant wrote before saving it.
    Given a reply lists changes to step "Send to DHIS2"
    When I click "Send to DHIS2" in the reply
    Then the code editor opens on "Send to DHIS2" (handoff to workflow-editor-ide)
    # AIAssistantPanelWrapper.tsx:204-228; MessageList.tsx:1199-1230
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| `?chat=true` opens the panel even when the instance has no assistant configured or a pinned version is loaded; the panel is mounted regardless of `aiAssistantEnabled`, and only the button and shortcut check. Read from code | `createUIStore.ts:79-96`; `CollaborativeEditor.tsx:504-506`; `AIAssistantPanelWrapper.tsx:149-156` | a working-looking panel; sending creates a conversation and a job that fails against a missing endpoint, or an assistant open on an old version | fix |
| `start_applying_workflow` / `start_applying_job_code` broadcast to the whole room with no permission check and no expiry; the flag clears only on the matching `done_*`. If the applying tab closes or disconnects mid-apply, everyone else stays "applying". Read from code | `workflow_channel.ex:773-831`; `createWorkflowStore.ts:748-799`; `useWorkflow.tsx:920-926` | Apply hidden and Save disabled for every collaborator until they reload; a viewer's modified browser could cause the same | fix |
| A global reply with code renders its diff blocks as "what changed" whenever it succeeded, but it is only applied in the asker's browser when the asker can write. A viewer's own reply, or one received while live-locked, shows a change record that never reached the canvas, with no "not applied" notice | `MessageList.tsx:1011-1024`, `:1252-1268`; `AIAssistantPanelWrapper.tsx:713-714`; `useAIWorkflowApplications.ts:662` | a list of changes the canvas does not contain | fix |
| The AI quota shown in the panel comes from the session context and only refreshes on context fetch, so a quota spent mid-session shows no banner; the send is refused with an alert instead (S20). Root cause is shared-editor-session 6.1 (`getLimits`) | `AIAssistantPanelWrapper.tsx:187`, `:803`; `createSessionContextStore.ts:605-661` | an enabled message box until a send fails | fix |
| `list_sessions` on the API calls `String.to_integer` on `offset` and `limit` | `ai_assistant_controller.ex:36-37` | a 500 for a non-numeric value (crafted URL only) | fix |
| Registry `cleanup/1` detaches every handler except `streaming_error`; `destroy/0` detaches it | `AIChannelRegistry.ts:1010-1023` vs `:728-741` | nothing visible; the left channel keeps a reference | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| Viewers can chat, so they add to shared history and spend the project's AI quota; this is a stated choice in the channel ("Requiring edit rights here would be a product change") | `ai_assistant_channel.ex:99-111` | decide |
| A role change answers twice: the AI channel re-checks and stays (S29), while the LiveView remounts the whole editor (shared-project-scope S08), which rejoins anyway | `ai_assistant_channel.ex:468-485`; `hooks.ex:361-368` | preserve |
| Apply on an existing workflow leaves it unsaved, apply on a new workflow saves it (S07, S09) | `useAIWorkflowApplications.ts:317-320` | preserve |
| Auto-apply falls back to applying when the triggering message has no user id (legacy rows) | `useAIWorkflowApplications.ts:717-720`; `AIAssistantPanelWrapper.tsx:728-730` | decide |
| The close button with a conversation open goes back to the conversation list (tooltip "Close current session"), not closed; on a new workflow there is no close button at all (workflow-editor-new 6.2) | `AIAssistantPanel.tsx:229-237`, `:376-400`; `AIAssistantPanelWrapper.tsx:790` | preserve |
| "Conversations" is hidden on a new workflow | `AIAssistantPanel.tsx:313`; `AIAssistantPanel.test.tsx:291-312` | preserve |
| Cmd/Ctrl+K is disabled on a new workflow | `AIAssistantPanelWrapper.tsx:155` | decide |
| Search and the Latest/Oldest toggle work only on the loaded page; in "Oldest" order, "Load more" appends the next page of newest-first results | `SessionList.tsx:48-80`; `ai_assistant.ex:1056` | decide |
| Conversation titles are the first message cut to 40 characters on a word boundary, trailing punctuation dropped | `ai_assistant.ex:31`, `:1115-1136` | preserve |
| The attachment ticks are remembered per workflow (or per project on a new workflow) in browser storage | `ChatInput.tsx:80-186`; `useAIMode.ts:77-79` | preserve |
| While waiting, a random phrase ("Thinking about the question...", "Taking a look...") stands in for status until the server sends one | `AIAssistantPanelWrapper.tsx:3-15`, `:455`, `:515` | preserve |
| Reply text is revealed one character every 15 ms regardless of how fast it arrived | `AIChannelRegistry.ts:158`, `:228-249` | decide |
| After a successful apply on an existing workflow the canvas fits the view | `useAIWorkflowApplications.ts:356-358` | preserve |
| A failure is shown once, on the reply rather than the question, and "Please try again" is dropped when a button says it | `MessageList.tsx:781-829`, `:1073-1100` | preserve |
| Apollo error text is shown only for a fixed list of error types; anything else reads "Something went wrong. Please try again." and is logged | `ai_assistant.ex:36-57`, `:1386-1421` | preserve |
| The quota alert title is "Message limit exceeded" whatever the limit's own wording | `AIChannelRegistry.ts:493-498` | decide |
| Join errors are matched on reason text ("session not found", "session type mismatch") to clear the session from the store | `AIChannelRegistry.ts:944-961` | decide |
| `ai_session_created` reaches every client in the editor room, but is only prepended when that client has no conversation open and has already loaded the list | `ai_assistant_channel.ex:1590-1615`; `createAIAssistantStore.ts:582-597`, `:796-809` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| Job-chat sessions (`ai_assistant:job_code:*`), the `j-chat` param, and their listing by `job_id` | `useAIMode.ts:81-86`; `useAIPanelURLSync.ts:84`, `:106-109`; `ai_assistant_channel.ex:588-593`, `:826-871`; `ai_assistant_controller.ex:77-120`, `:129-157` | the client always uses mode `workflow_template`; every first message carries `use_global_assistant`, which routes to a workflow_template session (`ai_assistant_channel.ex:580-586`). Old job_code rows can only be joined by a hand-built topic |
| `query_stream` (job chat) and `query_workflow_stream` (workflow chat) and their Apollo endpoints | `message_processor.ex:136-146`, `:328-394`; `ai_assistant.ex:859-975` | every new message stores `use_global_assistant` in session meta (`ai_assistant_channel.ex:983-990`; `ai_assistant.ex:737-743`); only a retry of a message in a session that never received a global message reaches them |
| `isGlobalAssistantActive` is a constant `true`, so `showAddButtons` is always false: "Add" on code blocks never renders | `AIAssistantPanelWrapper.tsx:182`, `:103-111`, `:844-850` | constant |
| Job-code Apply and Preview, and `useAutoPreview` | `useAIWorkflowApplications.ts:485-626`; `AIAssistantPanelWrapper.tsx:687-705`, `:825-834` | need a non-global reply with `job_id` and code; global replies never carry a job (`ai_assistant.ex:700-716`). Whether Apollo's global stream ever sends a `code` change on a job page was not established (6.5) |
| `update_context` with `workflow_id` | `ai_assistant_channel.ex:167-168`, `:274-319` | the client only ever sends `job_body`, `job_adaptor`, `job_name` (`AIChannelRegistry.ts:662-689`) |
| Join error branch for `Ecto.NoResultsError` / "join crashed" with "Job not available" | `AIChannelRegistry.ts:963-980` | no current join path returns those reasons; job joins answer with plain strings |
| `validateWorkflowIds` on apply and restore | `useAIWorkflowApplications.ts:294`; `useAIWorkflowUndo.ts:83` | listed in shared-workflow-yaml-format 6.3 |
| `connect`, `disconnect`, `loadSession` on the AI store | `createAIAssistantStore.ts:144-263` | `disconnect` and `loadSession` have no caller outside tests (not exhaustively checked) |

### 6.4 Performance and operational limits

| What | Where | User-visible? | Disposition |
|------|-------|---------------|-------------|
| A reply may run connect (5 s) + request (300 s) + idle (30 s) + 10 s before the job times out; each is an env var | `message_processor.ex:59-75`; `config.exs:16-19`; `bootstrap.ex:143-177` | yes, "The assistant took too long to respond." or "...stopped responding partway through." | preserve |
| Reaper every 5 minutes, grace = job timeout + 2 minutes, 200 messages per sweep | `stuck_message_reaper.ex:32`, `:61`, `:69`; `bootstrap.ex:292` | yes, a stuck message can take up to about 13 minutes to clear | preserve |
| `ai_assistant` Oban queue runs 10 jobs per node, one attempt each | `bootstrap.ex:345`; `message_processor.ex:9-11` | yes, under load messages wait in "pending" | preserve |
| Every change to the open job's code, name or adaptor in job page mode pushes `update_context`, which writes the session row | `AIAssistantPanelWrapper.tsx:287-306`; `ai_assistant_channel.ex:236-271` | no | decide |
| Conversation list page size 20; the API takes any `limit` without a cap | `ai_assistant_controller.ex:36-39`; `SessionList.tsx:72-80` | yes, "Load N more" | preserve |
| Stored sizes: message 10,000 chars, failure 500, 200 segments of 10,000, 100 steps per segment, step key/name 500 | `chat_message.ex:63`, `:87-90`, `:135-141` | message length yes (S26); others no | preserve |
| Streaming snapshots kept for the last 10 replies only, so older replies lose per-step diff history in the session | `createAIAssistantStore.ts:87`, `:464-481` | partly | preserve |
| An unused channel is left 2 s after its last subscriber goes (immediate on mode or session change) | `AIChannelRegistry.ts:135`, `:394-451` | no | preserve |
| Panel width defaults to 400 px, resizable, remembered in browser storage | `AIAssistantPanelWrapper.tsx:232-240` | yes | preserve |

### 6.5 Things seen but not understood

- Session `meta` is sent to Apollo whole, including `runtime_context` job code, `unsaved_job` bodies and message options, plus a Langfuse persona and a metrics opt-in for users with an `@openfn.org` email (`ai_assistant.ex:908-922`; `user.ex:64-78`). Whether that is intended for every field was not checked. (decide)
- Whether Apollo's global stream ever sends a `code` change on a job page, which is the only live trigger for job-code preview (`AIAssistantPanelWrapper.tsx:742-748`; `AIChannelRegistry.test.ts:154-169` says job-code changes are ignored for snapshots). (decide)
- Most channel tests join `ai_assistant:job_code:*` topics, which the UI no longer opens (6.3); they still prove the authorisation and teardown logic, which is shared, but not the path users take. `useAIPanelURLSync.test.ts:160-197`, `:317-332` exercise a job mode `useAIMode` never returns. (preserve)
- `useAIWorkflowApplications.autoApply.test.ts:274-328` ("only auto-applies for message author") proves nothing about authorship: the session arrives on first render, so the initial-load seeding marks every message applied before the authorship check runs. The YAML parser is mocked in the apply tests (`:25-60`), so parsing is only proven by shared-workflow-yaml-format's tests. (fix)
- No Playwright test covers the assistant.
- The channel's `with_authorized_frame` re-reads the session by id only; whether a session id from another workflow in the same project should be joinable from this workflow's editor (it is) was not decided anywhere visible (`ai_assistant_channel.ex:671-676`, `:874-892`). (decide)

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should viewers be able to spend the project's AI quota and add to shared history (6.2)?
- Should job chat and workflow chat (6.3) be removed, or is the global assistant expected to revert to them?
- Should `?chat=true` be gated like the button (6.1)?
- Should an abandoned "applying" state expire, and should starting one require edit rights (6.1)?
- Should a reply that was never applied in this browser stop presenting diff blocks as a record (6.1)?
- Which session meta fields should reach Apollo (6.5)?
- flow-workflow-yaml-copy (proposed by the lead) may cover the "Copy" on a generated workflow panel (`MessageList.tsx:660-670`); not referenced here because its scope was not available to read.

## Proposed flows

- `flow-ai-session-collaborators`: two people on the same workflow and conversation. A new conversation appears in the other's Conversations list (`ai_session_created`); each sees the other's questions, the streamed reply, the "processing" lock, failures and retries; only the asker's browser applies a reply and the other sees it through the shared document; while one applies, the other's Apply and Save are disabled. Surfaces: workflow-editor-ai-assistant (tab A), pubsub:ai_session:<session id>, workflow:collaborate:<workflow id> (`ai_session_created`, `workflow_applying`, `workflow_applied`), workflow-editor-ai-assistant (tab B), shared-editor-session. Code: `ai_assistant_channel.ex:342-466`, `:1355-1358`, `:1590-1615`; `workflow_channel.ex:773-831`; `AIAssistantPanelWrapper.tsx:722-730`; tests `ai_assistant_channel_test.exs:3796-4093`. This file asserts only the asker's side (S06, S07).
- `flow-account-revocation-teardown` (already proposed by shared-authenticated-session): revoking an account drops the user socket, and with it the AI channel. Surfaces: profile / user admin, pubsub:user_socket:<user id>, workflow-editor-ai-assistant. Referenced only.

## Proposed shared

- `shared-channel-project-scope` (already proposed by flow-schedule-project-deletion and flow-delete-open-workflow): the project-event handlers that end a channel on removal, role change, support revocation, deletion and workflow deletion. `AiAssistantChannel` has the same set (`ai_assistant_channel.ex:468-539`); S28 to S30 here would move there. Surfaces: shared-editor-session, workflow-editor-ai-assistant, run channel views.

## Summary

- Scenarios: 32 (S01 to S32), all `@pending`; S14 tagged `@variant:experimental-features`, S19 and S20 `@variant:ai-limit-reached`, S01 read under `default`, the rest under `ai-enabled`.
- Section 6: 6.1 has 6, 6.2 has 17, 6.3 has 8, 6.4 has 9, 6.5 has 6.
- Flows: proposed flow-ai-session-collaborators; referenced flow-workflow-api-edit-conflict, flow-delete-open-workflow (S02), flow-schedule-project-deletion (S04), flow-account-revocation-teardown (proposed elsewhere).
- Shared: inherits shared-authenticated-session, shared-project-scope, shared-editor-session, shared-workflow-yaml-format; re-proposes shared-channel-project-scope.
- Unsure: the `?chat=true`, stuck "applying" and viewer diff-block bugs are read from code only; job-code preview reachability depends on what Apollo's global stream sends; the flow-workflow-api-edit-conflict link is a handoff the lead asked for, not something the AI code calls.

## Lead resolution (batch 6)

- `flow-ai-session-collaborators` and `flow-account-revocation-teardown` created.
- `shared-channel-project-scope` declined again: the AI channel's teardown stays in this view (S28 to S30).
