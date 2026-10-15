---
id: flow-ai-session-collaborators
type: flow
title: An AI assistant session seen by collaborators
status: not-started
owner:

trigger:
  entry: workflow-editor-ai-assistant          # tab A, the person asking
  exit: workflow-editor-ai-assistant            # tab B, a collaborator in the same conversation; also workflow-editor-canvas (tab B) for the canvas and Save
  surfaces:
    - workflow-editor-ai-assistant              # tab A: first message, question, apply in the browser
    - pubsub:workflow:collaborate:<workflow_id>#ai_session_created
    - oban:Lightning.AiAssistant.MessageProcessor
    - pubsub:ai_session:<session_id>            # status and streaming, relayed by every joined AiAssistantChannel
    - pubsub:workflow:collaborate:<workflow_id>#workflow_applying
    - shared-editor-session                     # the shared Y.Doc the asker's apply writes into
    - pubsub:workflow:collaborate:<workflow_id>#workflow_applied
    - workflow-editor-ai-assistant              # tab B: list, messages, stream, lock
    - workflow-editor-canvas                    # tab B: canvas changes and the Save lock
  reachable_when:
    - both people pass workflow-editor-ai-assistant reachable_when (assistant configured, latest version, AI channel join authorised against the project)
    - both are in the editor room `workflow:collaborate:<workflow_id>` (shared-editor-session)
    - for the conversation hops, both have joined the same `ai_assistant:workflow_template:<session_id>` topic (ai_assistant_channel.ex:34-73)

inherits:
  - shared-editor-session           # Y.Doc sync between tabs, unsaved state, Save; this flow only adds what an AI apply does to it
  - shared-workflow-yaml-format     # the YAML-to-Y.Doc write that replaces the workflow on apply (YAMLStateToYDoc.ts:127-203)
  - shared-project-scope            # membership; removal and role change teardown are workflow-editor-ai-assistant S28, S29

url_params:
  - name: w-chat
    set_by: workflow-editor-ai-assistant (tab A, after the first message; useAIPanelURLSync.ts:91-118)
    effect: a collaborator opening the same link joins the same conversation (useAISession.ts:133-231)

config_variants:
  ai-enabled: { apollo.endpoint: <url>, apollo.ai_assistant_api_key: <key> }   # every scenario read under this one (collaborate.ex:84; ai_assistant.ex:80-84)
  experimental-features: { ai-enabled, user.preferences.experimental_features: true }   # live content lock makes the asker read-only (useWorkflow.tsx:1096-1101); only reaches 6.1

inventory:
  routes: []                                    # live /projects/:project_id/w/:id is owned by shared-editor-session
  events:
    - WorkflowChannel#start_applying_workflow   # workflow_channel.ex:773-787
    - WorkflowChannel#done_applying_workflow    # workflow_channel.ex:790-799
    - WorkflowChannel#start_applying_job_code, #done_applying_job_code   # workflow_channel.ex:804-831; unreachable (6.3)
    - AiAssistantChannel broadcast_session_created -> workflow:collaborate:<id> ai_session_created   # ai_assistant_channel.ex:57-61, :1590-1615
    - AiAssistantChannel broadcasts user_message, message_status_changed, message_processing, new_message, message_error, streaming_*   # :342-457, :1355-1358, :1438-1442, :1501-1510
  js_hooks: []
  react_components:
    - stores/createWorkflowStore.ts (workflowApplyingHandler, workflowAppliedHandler, startApplyingWorkflow, doneApplyingWorkflow)   # :748-799, :1995-2064
    - stores/createAIAssistantStore.ts (_connectChannel, _prependSession, _setProcessingState)   # :577-597, :629-637, :784-818
    - contexts/StoreProvider.tsx (connects the AI store to the editor channel)   # :232-246
    - hooks/useWorkflow.tsx useCanSave   # :886-929
  policies:
    - none on the applying lock (workflow_channel.ex:773-831 check nothing beyond the channel join)
    - Lightning.Policies.Workflows / ProjectUsers via AiAssistantChannel (owned by workflow-editor-ai-assistant)
  workers:
    - Lightning.AiAssistant.MessageProcessor     # owned by workflow-editor-ai-assistant; its broadcasts are this flow's middle hop
  api_endpoints: []
  emails: []
  config: []
  not_reachable_here:
    - job-code apply coordination (`job_code_applying`, `job_code_applied`, `applyingJobCodeMessageId`), see 6.3

related:
  - workflow-editor-ai-assistant
  - workflow-editor-canvas
  - lib/lightning_web/channels/ai_assistant_channel.ex
  - lib/lightning_web/channels/workflow_channel.ex
  - lib/lightning/ai_assistant/ai_assistant.ex
  - lib/lightning/ai_assistant/message_processor.ex
  - assets/js/collaborative-editor/lib/AIChannelRegistry.ts
  - assets/js/collaborative-editor/components/AIAssistantPanelWrapper.tsx
  - assets/js/collaborative-editor/components/MessageList.tsx
  - assets/js/collaborative-editor/hooks/useAIWorkflowApplications.ts
  - assets/js/collaborative-editor/hooks/useAIWorkflowUndo.ts
  - test/lightning_web/channels/ai_assistant_channel_test.exs
  - test/lightning_web/channels/workflow_channel_test.exs
  - assets/test/collaborative-editor/stores/createWorkflowStore.test.ts
  - assets/test/collaborative-editor/hooks/useAIWorkflowApplications.autoApply.test.ts
flows: []
---

## 1. Purpose

Two or more people often have the same workflow open while one of them works with the AI assistant.
The others need to see the conversation and the changes it makes, and the shared workflow needs to
take each AI change once, from one browser, without someone saving or overwriting it halfway through.
Getting this wrong means duplicated or half-applied steps on a workflow that moves health data,
competing questions, or collaborators reading a record of changes that never reached the canvas.

## 2. What it does

1. Someone with the workflow open starts a conversation with the AI assistant, or asks a question in one.
   - A colleague with the same workflow open sees the new conversation appear at the top of their list without reloading.
2. Everyone in the conversation sees the question, who asked it, and the reply as it streams in.
   - Nobody can send another message while a question is being answered.
   - If the reply fails, everyone sees the failure, and a retry by anyone clears "Try again" for all.
3. Only the asker's browser applies the reply to the shared workflow.
   - Colleagues see the change appear on their canvas, and their Save shows unsaved changes.
4. While any apply is running, everyone else's Save, "Revert changes" and "Try again" are locked, and unlock when it finishes.

**Straightforwardness: 2 of 5.** The happy path is easy to picture, but the lock that protects it can get stuck, can be skipped, and several people's screens can end up showing changes that never happened.

### Most surprising behaviours

- **(2)** When the reply lands it replaces the whole workflow with the asker's copy from when they asked, so a colleague's edits made in the meantime quietly disappear from their canvas. (6.1)
- **(2)** If the asker closes their tab or drops off mid-apply, everyone else's Save seems to stay disabled until they reload. (6.1)
- **(2)** Two people in different conversations on the same workflow may both have replies auto-apply at once, ignoring the lock, and the last one wins. (6.1)
- **(2)** Colleagues can be shown a list of changes, with a "Revert changes" button, for edits that never reached the workflow, because the asker's apply failed or the asker couldn't edit. (6.1, 6.2)
- **(3)** With several people in one conversation, streamed text may repeat once per extra person, and someone starting a conversation elsewhere at the same moment could briefly see another conversation's status. (6.1)

## 3. Who can do what

Source: AI channel authorisation `ai_assistant_channel.ex:99-111`, `:874-945`, `:1539-1569`
(read is project membership, `policies/workflows.ex:14-22`); apply gate
`AIAssistantPanelWrapper.tsx:190`, `:720-730`; `useAIWorkflowApplications.ts:662`, `:708-726`;
lock `workflow_channel.ex:773-799`; revert `MessageList.tsx:1029-1043`.

| Action | Viewer | Editor | Admin | Owner | Superuser (no row) | Support (no row) |
|--------|--------|--------|-------|-------|--------------------|------------------|
| See a new conversation appear in the list | yes | yes | yes | yes | no | yes, when support access is on |
| Join a colleague's conversation and watch it stream | yes | yes | yes | yes | no | yes, when support access is on |
| Send while a colleague's question is being answered | no | no | no | no | no | no |
| Have a reply applied to the shared workflow | no | only to own questions | only to own questions | only to own questions | no | only to own questions, when support access is on |
| Start or end the applying lock for everyone | yes (6.1) | yes | yes | yes | no | yes, when support access is on |
| Save while anyone's apply is running | no | no | no | no | no | no |
| Revert the last reply's changes, whoever asked | no | yes (6.2) | yes | yes | no | yes, when support access is on |

**Preconditions beyond role**
- Only the browser of the person whose message triggered the reply applies it; every other tab marks it handled without importing (`useAIWorkflowApplications.ts:708-726`; `AIAssistantPanelWrapper.tsx:728-730`).
- The asker's tab applies only when it is not read-only: a viewer, a deleted or pinned workflow, or a live-locked workflow under `experimental-features` (`AIAssistantPanelWrapper.tsx:190`; `useWorkflow.tsx:1067-1112`).
- The lock is client state set by broadcasts; a tab that joins after `workflow_applying` was sent is not locked (`createWorkflowStore.ts:208-209`, `:748-769`).

## 4. What it touches

**Reads**: `ai_chat_sessions`, `ai_chat_messages`, `users`, `projects`, `project_users`, `workflows` (join and per-frame authorisation, owned by workflow-editor-ai-assistant); the shared Y.Doc on each tab

**Writes**
- Hop 1 (tab A, first message): `ai_chat_sessions` and `ai_chat_messages` insert, `oban_jobs` insert (owned by workflow-editor-ai-assistant S04)
- Hop 3 (tab A, apply): the shared Y.Doc, replacing name, jobs, triggers, edges and positions in one transaction (`useAIWorkflowApplications.ts:291-306`; `YAMLStateToYDoc.ts:127-203`); persistence is shared-editor-session's
- Hop 3 (tab A, apply outcome): `ai_chat_messages.meta.apply_failed` set on failure and cleared on a later success (`ai_assistant_channel.ex:184-215`, `:1064-1072`; `ai_assistant.ex:811-835`)

**Immediate side effects** (in the same request)
- Hop 1: `ai_session_created` with the session summary and its creator to `workflow:collaborate:<workflow_id>` when the join was for `new` (`ai_assistant_channel.ex:57-61`, `:1590-1615`); tab B prepends it only if no conversation is open and its list is loaded (`createAIAssistantStore.ts:577-597`, `:784-818`)
- Hop 1 and every later question: `user_message` to the conversation topic (`ai_assistant_channel.ex:1355-1358`, `:1438-1442`); tab B adds it, deduplicated by id (`AIChannelRegistry.ts:767-772`; `createAIAssistantStore.ts:432-438`)
- Retry: `message_status_changed` to the conversation topic (`ai_assistant_channel.ex:1501-1510`)
- Hop 3: `workflow_applying {user_id, user_name, message_id}` then `workflow_applied {message_id}` to the whole editor room, including the sender, around every apply, streamed apply, revert and restore (`workflow_channel.ex:773-799`; `useAIWorkflowApplications.ts:282`, `:343-348`; `useAIWorkflowUndo.ts:76`, `:102`)
- Hop 3, on failure: Sentry warning "AI assistant workflow apply failed" (`ai_assistant_channel.ex:184-201`)

**Deferred side effects** (later, elsewhere)
- Hop 2: `MessageProcessor` broadcasts status and stream events on `ai_session:<session_id>` (`message_processor.ex:405-415`; `ai_assistant.ex:1574-1610`); every `AiAssistantChannel` process joined to that conversation is subscribed (`ai_assistant_channel.ex:56`) and re-broadcasts each one to the conversation topic as `message_processing`, `new_message`, `message_error`, `streaming_chunk`, `streaming_status`, `streaming_segment`, `streaming_changes`, `streaming_error` (`ai_assistant_channel.ex:342-457`)
- Hop 4: the Y.Doc update reaches tab B through the editor channel; tab B's Save shows unsaved changes (shared-editor-session)

**External, non-transactional effects**
- Apollo, owned by workflow-editor-ai-assistant; nothing on the collaborator side calls out
- Sentry message on apply failure (above)

**Depends on config**
- Apollo endpoint and key (variant `ai-enabled`)
- `experimental_features` user preference (variant `experimental-features`; 6.1)

**Product limits**
- none

## 5. Scenarios

Verified against `ai-enabled`. All read from code and tests; nothing was run. No test drives two
browsers or two channel subscribers on one conversation (6.5).

```gherkin
Feature: An AI assistant session seen by collaborators
  In order to work on a workflow together while one of us uses the AI assistant
  As a member with the workflow open alongside a colleague
  I want to see the conversation and its changes, and have each change land once

  @S01 @pending
  Scenario: A colleague's new conversation appears in my list
    # Value: people working on the same workflow can find and join a conversation about it as soon as it starts.
    Given "Amara" and I both have workflow "Intake" open
    And I have the assistant's conversation list open on "Intake"
    When "Amara" starts a conversation with "Add a step that posts to DHIS2"
    Then "Add a step that posts to DHIS2" appears at the top of my list without a reload
    And the conversation count goes up by one
    # ai_assistant_channel.ex:57-61, :1590-1615; createAIAssistantStore.ts:577-597, :784-818; StoreProvider.tsx:232-246
    # no test covers ai_session_created (6.5)

  @S02 @pending
  Scenario: Everyone in the conversation sees the question, who asked it, and the reply as it streams
    # Value: two people on one workflow work from the same advice and know who asked for each change.
    Given "Amara" and I are both in the same conversation on "Intake"
    When "Amara" asks "Add a step that posts to DHIS2"
    Then I see her message with "Sent by Amara"
    And I see the assistant's status and reply text appear as they arrive
    And once complete the reply is the same one "Amara" sees
    # ai_assistant_channel.ex:342-376, :404-457, :1355-1358, :1438-1442; AIChannelRegistry.ts:755-772, :839-898
    # createAIAssistantStore.ts:432-494; MessageList.tsx:1490-1497
    # ai_assistant_channel_test.exs:3797-3824, :3858-3895, :4045-4092 (one subscriber each; 6.5)

  @S03 @pending
  Scenario: Nobody can send while a colleague's question is being answered
    # Value: a second question cannot race the first and produce competing changes to a shared workflow.
    Given "Amara" and I are in the same conversation on "Intake"
    When "Amara"'s question starts being answered
    Then my message box is disabled until the reply is in or fails
    And if I open the conversation while it is still being answered, my message box is disabled too
    # ai_assistant_channel.ex:350-354; AIChannelRegistry.ts:775-777; createAIAssistantStore.ts:412-427, :629-637
    # ChatInput.tsx:205-208, :294; ai_assistant_channel_test.exs:3826-3856

  @S04 @pending
  Scenario: Only the asker's browser applies the reply, and colleagues see it on their canvas
    # Value: an AI change lands on the shared workflow once, not once per person watching the conversation.
    Given "Amara", an editor, and I, an editor, are in the same conversation on "Intake"
    When "Amara" asks for a new step "Post to DHIS2" and the reply changes the workflow
    Then my browser does not import the reply
    And "Post to DHIS2" appears on my canvas through the shared workflow
    And my "Save" shows unsaved changes (shared-editor-session)
    # AIAssistantPanelWrapper.tsx:711-737; useAIWorkflowApplications.ts:646-731; YAMLStateToYDoc.ts:127-203
    # useAIWorkflowApplications.autoApply.test.ts:274-328 does not prove the authorship check (6.5)

  @S05 @pending
  Scenario: While anyone applies AI changes, collaborators cannot save or revert
    # Value: nobody commits, or writes over, a workflow halfway through an AI change.
    Given "Amara" and I have "Intake" open, and I am an editor
    When "Amara"'s browser starts applying the assistant's changes
    Then my "Save" is disabled and hovering it shows "Applying AI-generated workflow..."
    And "Revert changes" and the "Try again" on a failed apply are unavailable in my panel
    When her apply finishes
    Then my "Save" is enabled again
    # workflow_channel.ex:773-799; createWorkflowStore.ts:748-769, :1995-2064; useWorkflow.tsx:886-929
    # AIAssistantPanelWrapper.tsx:806-822, :868; MessageList.tsx:1029-1043, :1366-1374
    # workflow_channel_test.exs:6987-7044; createWorkflowStore.test.ts:1250-1330

  @S06 @pending
  Scenario: A failed reply, and its retry, are seen by everyone in the conversation
    # Value: nobody waits on a reply that has failed, or retries a question a colleague already retried and spends the quota twice.
    Given "Amara" and I are in the same conversation and her question fails
    Then I see the failure and "Try again" on her question
    When "Amara" clicks "Try again"
    Then "Try again" disappears for me as well
    # ai_assistant_channel.ex:369-398, :1501-1510; AIChannelRegistry.ts:780-810; createAIAssistantStore.ts:500-530
    # ai_assistant_channel_test.exs:3897-3983 (message_error); retry broadcast read from code
```

## 6. Unclear value

### 6.1 Possible bugs

| What | Where | What a user sees | Disposition |
|------|-------|------------------|-------------|
| The applying lock has no expiry and no owner: it clears only on a matching `done_applying_workflow`, and the channel does nothing when the applying tab leaves. If tab A closes or drops between start and done, every other tab stays locked. Read from code | `workflow_channel.ex:773-799`; `createWorkflowStore.ts:748-769`; `useWorkflow.tsx:922-925` | "Save" disabled with "Applying AI-generated workflow..." for every collaborator until they reload | fix |
| Any member joined to the editor room, viewers included, can start or end the lock; `start_applying_workflow` checks nothing | `workflow_channel.ex:773-799` | a viewer's modified browser can disable Save for everyone, or lift a real lock | fix |
| Auto-apply ignores the lock. Two people in different conversations on the same workflow both auto-apply when their replies arrive; only the manual buttons and Save read `isApplyingWorkflow`. Read from code | `AIAssistantPanelWrapper.tsx:711-737`, `:815`; `useAIWorkflowApplications.ts:224-306`, `:646-731` | two whole-workflow imports racing in the shared document, the last one winning; the lock's stated purpose is preventing exactly this | fix |
| Every joined `AiAssistantChannel` process is subscribed to `ai_session:<id>` and re-broadcasts each event to the conversation topic, so with N people in a conversation each tab receives every stream event N times. Read from code; no test joins two subscribers | `ai_assistant_channel.ex:56`, `:342-457`; `AIChannelRegistry.ts:167-180`, `:839-860` | streamed text and status lines repeat until the final reply replaces them; the asker's tab re-imports each streamed workflow once per extra viewer (`AIAssistantPanelWrapper.tsx:720`) | fix |
| The first message joins topic `ai_assistant:workflow_template:new`, which every user starting a conversation shares. Broadcasts the creator's channel makes before it leaves for the real id go to that shared topic. Read from code; the window is between the join reply and the URL-driven rejoin | `ai_assistant_channel.ex:34-73`, `:342-457`; `useAISession.ts:172-184`; `useAIPanelURLSync.ts:91-118` | someone on another workflow or project starting a conversation at the same moment could receive a processing state or status from someone else's conversation | fix |
| An apply failure in the asker's tab is stored on the message but not broadcast; collaborators keep the diff blocks as a record of changes and are offered "Revert changes" until they reload | `ai_assistant_channel.ex:184-215`; `useAIWorkflowApplications.ts:430-444`; `MessageList.tsx:1011-1043` | a list of changes their canvas does not contain, with a revert for them | fix |
| When the asker cannot write (viewer, or live-locked under `experimental-features`), no tab applies the reply, yet every tab in the conversation renders its diff blocks as changes made | `AIAssistantPanelWrapper.tsx:190`, `:728-730`; `useAIWorkflowApplications.ts:662`, `:717-726`; `MessageList.tsx:1011-1024` | an editor colleague reads a change record for edits nobody applied, and has no apply control on a global reply | fix |
| While locked, a collaborator's Apply on a "Generated workflow" panel stays enabled: `onApplyWorkflow` is withheld, but the button's own handler still flashes "Applied" | `AIAssistantPanelWrapper.tsx:806-822`; `MessageList.tsx:570-578`, `:586`, `:1320-1336` | "Applied" for two seconds and nothing changes | fix |
| The asker's apply replaces the whole workflow with YAML built from the asker's copy when they sent the question; edits a collaborator made in the meantime are overwritten without warning to them | `AIAssistantPanelWrapper.tsx:413-440`, `:473-490`; `useAIWorkflowApplications.ts:291-306`; `YAMLStateToYDoc.ts:127-203` | a colleague's unsaved step or code edit disappears from their canvas when the reply lands | fix |

### 6.2 Quirks and implementation details

| What | Where | Disposition |
|------|-------|-------------|
| "Revert changes" on the last reply is offered to every editor in the conversation, not only the asker; in a colleague's tab nothing was recorded, so it always asks to confirm with "Reverting replaces the whole workflow" | `MessageList.tsx:1029-1043`; `useAppliedCanvas.ts:44-47`; `useAIWorkflowUndo.ts:107-118` | decide |
| A colleague's message box is blocked by `message_processing`, not by the `user_message` that precedes it; between a question and the job starting, others can still send | `AIChannelRegistry.ts:767-777`; `createAIAssistantStore.ts:432-494`, `:629-637` | decide |
| A tab that opens the workflow while an apply runs is not locked; the lock exists only in the tabs that heard `workflow_applying` | `createWorkflowStore.ts:208-209`, `:748-769` | decide |
| Each streamed workflow snapshot, as well as the final reply, sends its own `workflow_applying` / `workflow_applied` pair, so collaborators' Save flickers during a long reply | `AIAssistantPanelWrapper.tsx:711-737`; `useAIWorkflowApplications.ts:282`, `:343-348` | preserve |
| Authorship is decided from `user_id` on the final reply and from `user.id` during streaming; both fall back to applying when absent (legacy rows; workflow-editor-ai-assistant 6.2) | `useAIWorkflowApplications.ts:708-720`; `AIAssistantPanelWrapper.tsx:728-730` | preserve |
| The asker's own tab also receives `workflow_applying`, so its own Save is disabled during its own apply | `workflow_channel.ex:776-781`; `createWorkflowStore.ts:748-758` | preserve |

### 6.3 Unreachable or dead code

| What | Where | Why unreachable |
|------|-------|-----------------|
| `applyingUser` and `applyingJobUser` are stored from the broadcast but never rendered; the applier's first name, or email when there is none, reaches every collaborator unused | `workflow_channel.ex:777-781`, `:808-812`; `createWorkflowStore.ts:756-757`, `:779-784`; `types/workflow.ts:200`, `:205` | no reader outside the store and its tests |
| `start_applying_job_code` / `done_applying_job_code` and `job_code_applying` / `job_code_applied` | `workflow_channel.ex:804-831`; `createWorkflowStore.ts:771-797`, `:2075-2130` | job-code Apply is unreachable (workflow-editor-ai-assistant 6.3) |

### 6.4 Performance and operational limits

none

### 6.5 Things seen but not understood

- `useAIWorkflowApplications.autoApply.test.ts:274-328` ("only auto-applies for message author") proves nothing about authorship: the session arrives on first render, so the initial-load seeding (`useAIWorkflowApplications.ts:670-680`) marks the reply handled before the authorship check runs. S04 has no test that would fail if the check were removed. (fix)
- Every test in "collaborative session behavior" joins one socket, and on the `ai_assistant:job_code:*` topic the UI no longer opens (`ai_assistant_channel_test.exs:3796-4093`); the relay is never exercised with two subscribers, which is how the duplicate rebroadcast in 6.1 went unseen. (preserve)
- `ai_session_created` and `_prependSession` have no test on either side. (preserve)
- No Playwright test drives two browsers through the assistant.

## 7. Not migrating

| Item | Reason | Decided by | Date |
|------|--------|------------|------|

## 8. Open questions

- Should the applying lock expire, belong to the tab that set it, and require edit rights (6.1)?
- Should auto-apply wait for, or take, the lock so two conversations cannot import at once (6.1)?
- Should a reply that no tab applied, or whose apply failed elsewhere, stop presenting diff blocks to collaborators (6.1)?
- Should a reply landing on a workflow a colleague has since edited warn them, or merge rather than replace (6.1)?
- Should revert be limited to the asker (6.2)?

## Proposed flows

none

## Proposed shared

none

## Summary

- Scenarios: 6 (S01 to S06), all `@pending`, read under `ai-enabled`.
- Section 6: 6.1 has 9, 6.2 has 6, 6.3 has 2, 6.4 has 0, 6.5 has 4.
- Flows: none proposed; this is the flow workflow-editor-ai-assistant proposed.
- Shared: inherits shared-editor-session, shared-workflow-yaml-format, shared-project-scope; none proposed.
- Unsure: the duplicate rebroadcast, the shared `new` topic, the stuck lock and auto-apply bypassing the lock are read from code only; workflow-editor-canvas is in `surfaces` but does not list this flow in its `flows`.
