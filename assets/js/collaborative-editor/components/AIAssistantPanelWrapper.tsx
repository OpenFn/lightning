import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

const INITIAL_LOADING_STATUSES = [
  'Thinking about the question...',
  'Working on it...',
  'Processing your request...',
  'Examining your question...',
  'Taking a look...',
  'Looking into it...',
] as const;

const getRandomStatus = () =>
  INITIAL_LOADING_STATUSES[
    Math.floor(Math.random() * INITIAL_LOADING_STATUSES.length)
  ];

import { randomUUID } from '#/common';

import { useURLState } from '../../react/lib/use-url-state';
import {
  useMonacoRef,
  useRegisterDiffDismissalCallback,
} from '../contexts/MonacoRefContext';
import {
  useAIConnectionState,
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAISessionType,
  useAIStore,
  useAIStreamingApply,
  useAIStreamingChanges,
  useAIStreamingContent,
  useAIStreamingSegments,
  useAIStreamingSnapshots,
  useAISnapshotsByMessageId,
  useAIStreamingStatus,
  useAIWorkflowTemplateContext,
} from '../hooks/useAIAssistant';
import { useAISessionCommands } from '../hooks/useAIChannelRegistry';
import { useAIInitialMessage } from '../hooks/useAIInitialMessage';
import { useAIMode } from '../hooks/useAIMode';
import { useAIPanelDiffManager } from '../hooks/useAIPanelDiffManager';
import { useAIPanelURLSync } from '../hooks/useAIPanelURLSync';
import { useAISession } from '../hooks/useAISession';
import { useAIWorkflowApplications } from '../hooks/useAIWorkflowApplications';
import { useAIWorkflowUndo } from '../hooks/useAIWorkflowUndo';
import { useAppliedCanvas } from '../hooks/useAppliedCanvas';
import { useAutoPreview } from '../hooks/useAutoPreview';
import { useResizablePanel } from '../hooks/useResizablePanel';
import {
  selectIsConnected,
  selectIsConnecting,
  useSession,
} from '../hooks/useSession';
import {
  useExperimentalFeaturesEnabled,
  useIsNewWorkflow,
  useLimits,
  useProject,
  useUser,
} from '../hooks/useSessionContext';
import {
  useAIAssistantInitialMessage,
  useIsAIAssistantPanelOpen,
  useUICommands,
} from '../hooks/useUI';
import {
  useWorkflowActions,
  useWorkflowReadOnly,
  useWorkflowState,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import type { JobCodeContext, Message } from '../types/ai-assistant';
import { STREAMING_MESSAGE_ID } from '../types/ai-assistant';
import { Z_INDEX } from '../utils/constants';
import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
import { AlertDialog } from './AlertDialog';
import { MessageList } from './MessageList';

/**
 * AIAssistantPanelWrapper Component
 *
 * Wrapper for AI Assistant panel that accesses UI store state.
 * Must be inside StoreProvider to access uiStore.
 *
 * Features:
 * - Smooth CSS animations when opening/closing
 * - Draggable resize handle
 * - Persists width in localStorage
 * - Syncs open/closed state with URL query param (?chat=true)
 */
export function AIAssistantPanelWrapper({
  aiAssistantEnabled = false,
}: {
  aiAssistantEnabled?: boolean;
}) {
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();
  const initialMessage = useAIAssistantInitialMessage();
  const {
    closeAIAssistantPanel,
    toggleAIAssistantPanel,
    clearAIAssistantInitialMessage,
  } = useUICommands();
  const { updateSearchParams, params } = useURLState();
  const currentVersion = params['v'];

  // Check if viewing a pinned version (not latest) to disable AI Assistant
  const isPinnedVersion =
    currentVersion !== undefined && currentVersion !== null;

  const { isReadOnly } = useWorkflowReadOnly();
  const isNewWorkflow = useIsNewWorkflow();

  // Track IDE state changes to re-focus chat input when IDE closes
  const isIDEOpen = params.panel === 'editor';
  const [focusTrigger, setFocusTrigger] = useState(0);
  const prevIDEOpenRef = useRef(isIDEOpen);

  useEffect(() => {
    // When IDE closes (was true, now false), increment focus trigger
    if (prevIDEOpenRef.current && !isIDEOpen) {
      setFocusTrigger(prev => prev + 1);
    }
    prevIDEOpenRef.current = isIDEOpen;
  }, [isIDEOpen]);

  // Cmd+K toggles AI Assistant with mutual exclusivity
  // Disabled when viewing a pinned version (not latest) or when Apollo not configured
  useKeyboardShortcut(
    '$mod+k',
    () => {
      toggleAIAssistantPanel();
    },
    0,
    { enabled: !isPinnedVersion && aiAssistantEnabled && !isNewWorkflow }
  );

  const aiStore = useAIStore();
  const {
    sendMessage: sendMessageToChannel,
    loadSessions,
    retryMessage: retryMessageViaChannel,
    updateContext: updateContextViaChannel,
    reportApplyFailure,
  } = useAISessionCommands();
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const streamingContent = useAIStreamingContent();
  const streamingStatus = useAIStreamingStatus();
  const streamingSegments = useAIStreamingSegments();
  const streamingSnapshots = useAIStreamingSnapshots();

  const snapshotsByMessageId = useAISnapshotsByMessageId();
  const streamingChanges = useAIStreamingChanges();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const isSessionConnected = useSession(selectIsConnected);
  const isSessionConnecting = useSession(selectIsConnecting);
  const experimentalFeaturesEnabled = useExperimentalFeaturesEnabled();
  const [isGlobalAssistantActive, setIsGlobalAssistantActive] = useState(false);
  const workflowTemplateContext = useAIWorkflowTemplateContext();
  const project = useProject();
  const user = useUser();
  const workflow = useWorkflowState(state => state.workflow);
  const limits = useLimits();

  // AI can apply changes if: not readonly OR is a new workflow (being created)
  const canApplyChanges = !isReadOnly || isNewWorkflow;
  const isWriteDisabled = !canApplyChanges;

  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  /**
   * Open a step from a diff block in the IDE, selecting the node and opening
   * the editor in one navigation.
   *
   * Resolves by id first, then by name. Parsing YAML without `id:` fields
   * invents ids, and the apply path parses the same YAML separately, so for
   * a step the reply just added the diff's id and the canvas's id disagree.
   * Navigating to an id nothing owns opens an empty editor.
   */
  /** Whether a diff block's step actually exists on the canvas */
  const canOpenStep = useCallback(
    ({ jobId, name }: { jobId?: string; name: string }) =>
      jobs.some(job => job.id === jobId || job.name === name),
    [jobs]
  );

  const handleOpenStep = useCallback(
    ({ jobId, name }: { jobId?: string; name: string }) => {
      const match =
        (jobId && jobs.find(job => job.id === jobId)) ??
        jobs.find(job => job.name === name);
      if (!match) return;
      // Clears the sibling selections too: leaving a stale trigger or edge
      // behind still resolves to the job, but leaves a URL that is wrong to
      // share and wrong to go back to.
      updateSearchParams({
        panel: 'editor',
        job: match.id,
        trigger: null,
        edge: null,
      });
    },
    [jobs, updateSearchParams]
  );
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);

  const {
    width,
    isResizing,
    handleMouseDown: handleResizeMouseDown,
  } = useResizablePanel({
    storageKey: 'ai-assistant-panel-width',
    defaultWidth: 400,
    direction: 'left',
  });

  const aiMode = useAIMode();

  // URL synchronization hook - manages ?chat=true and session ID params
  const { sessionIdFromURL } = useAIPanelURLSync({
    isOpen: isAIAssistantPanelOpen,
    isNewWorkflow,
    sessionId,
    aiMode,
    aiStore,
    updateSearchParams,
    params,
  });

  // Use registry-based session management
  useAISession({
    isOpen: isAIAssistantPanelOpen,
    aiMode,
    sessionIdFromURL,
    workflowData: {
      workflow,
      jobs,
      triggers,
      edges,
      positions,
    },
    onSessionIdChange: newSessionId => {
      if (!aiMode) return;

      // When mode changes, clear the other mode's session param
      if (aiMode.mode === 'workflow_template') {
        updateSearchParams({
          'w-chat': newSessionId,
          'j-chat': null, // Clear job session when in workflow mode
        });
      } else {
        updateSearchParams({
          'j-chat': newSessionId,
          'w-chat': null, // Clear workflow session when in job mode
        });
      }
    },
  });

  // Push job context updates to backend when job body/adaptor/name changes
  // This ensures the AI has access to the current code when "Attach code" is checked
  useEffect(() => {
    // Only update context for active job_code sessions
    if (
      !isAIAssistantPanelOpen ||
      !sessionId ||
      !aiMode ||
      aiMode?.page !== 'job_code'
    ) {
      return;
    }

    const context = aiMode.context as JobCodeContext;
    if (context.job_body !== undefined || context.job_adaptor !== undefined) {
      updateContextViaChannel({
        job_body: context.job_body,
        job_adaptor: context.job_adaptor,
        job_name: context.job_name,
      });
    }
  }, [isAIAssistantPanelOpen, sessionId, aiMode, updateContextViaChannel]);

  /**
   * appliedMessageIdsRef tracks which AI-generated workflows have been
   * automatically applied.
   *
   * Auto-apply behavior:
   * - When the AI responds with YAML code in workflow_template mode, we
   *   automatically apply it to the canvas
   * - This ref prevents applying the same message multiple times if the
   *   component re-renders
   * - The ref is cleared when:
   *   1. Starting a new conversation (handleNewConversation)
   *   2. Switching to a different session (handleSessionSelect)
   *
   * This provides a smooth UX where users see their workflow update in
   * real-time as the AI generates it, without requiring manual "Apply"
   * button clicks.
   */
  const appliedMessageIdsRef = useRef<Set<string>>(new Set());

  const handleNewConversation = useCallback(() => {
    if (!project) return;

    appliedMessageIdsRef.current.clear();
    aiStore.clearSession();

    // Clear session ID from URL - useAISession will handle creating new session
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [aiStore, project, updateSearchParams]);

  const handleSessionSelect = useCallback(
    (selectedSessionId: string) => {
      if (!project || !aiMode) return;

      appliedMessageIdsRef.current.clear();
      aiStore._clearSession();

      // Update URL with selected session ID - useAISession will handle loading it
      if (aiMode.mode === 'workflow_template') {
        updateSearchParams({
          'w-chat': selectedSessionId,
          'j-chat': null,
        });
      } else {
        updateSearchParams({
          'j-chat': selectedSessionId,
          'w-chat': null,
        });
      }
    },
    [aiStore, project, aiMode, updateSearchParams]
  );

  // The landing screen's "Build with AI" card stores the user's prompt in UI
  // state rather than sending it, because the panel isn't mounted yet. Send it
  // once the panel is open and the AI connection is ready.
  useAIInitialMessage({
    initialMessage,
    aiMode,
    sessionId,
    connectionState,
    isAIAssistantPanelOpen,
    aiStore,
    workflowData: { workflow, jobs, triggers, edges, positions },
    updateSearchParams,
    clearAIAssistantInitialMessage,
  });

  // Note: AI session creation events are now handled by AIAssistantStore._connectChannel
  // which receives events directly from the workflow channel

  const sendMessage = useCallback(
    (
      content: string,
      messageOptions?: {
        attach_code?: boolean;
        attach_logs?: boolean;
        attach_io_data?: boolean;
        step_id?: string;
        use_global_assistant?: boolean;
      }
    ) => {
      const currentState = aiStore.getSnapshot();

      // For job_code with attach_code, get CURRENT code from Y.Doc
      let updatedAiMode = aiMode;
      if (messageOptions?.attach_code && aiMode?.mode === 'job_code') {
        const context = aiMode.context as JobCodeContext;
        const jobId = context.job_id;

        if (jobId) {
          // Get fresh code from jobs array (backed by Y.Doc)
          const currentJob = jobs.find(j => j.id === jobId);
          if (currentJob) {
            // Update aiMode with new context (don't mutate)
            const projectId =
              'project_id' in context
                ? (context.project_id as string)
                : project!.id;
            updatedAiMode = {
              ...aiMode,
              context: {
                ...context,
                project_id: projectId,
                job_body: currentJob.body,
              },
            };
          }
          // If job not found, fall back to existing context.job_body
          // (job could be unsaved or deleted)
        }
      }

      // If no session exists, we need to include content in context for first message
      if (!currentState.sessionId && updatedAiMode) {
        const { mode, context, page } = updatedAiMode;

        // Prepare context with content and message options for channel join
        let finalContext = {
          ...context,
          content,
          // Include attach_code/attach_logs so backend knows to include them in first message
          ...(messageOptions?.attach_code && { attach_code: true }),
          ...(messageOptions?.attach_logs && { attach_logs: true }),
          ...(messageOptions?.attach_io_data && { attach_io_data: true }),
          ...(messageOptions?.step_id && { step_id: messageOptions.step_id }),
          ...(messageOptions?.use_global_assistant && {
            use_global_assistant: true,
          }),
        };

        // Add workflow YAML if in workflow mode or global assistant
        if (
          page === 'workflow_template' ||
          messageOptions?.use_global_assistant
        ) {
          const workflowData = prepareWorkflowForSerialization(
            workflow,
            jobs,
            triggers,
            edges,
            positions
          );
          if (workflowData) {
            const workflowYAML = serializeWorkflowToYAML(workflowData);
            if (workflowYAML) {
              finalContext = { ...finalContext, code: workflowYAML };
            }
          }

          // Derive page for global assistant routing
          if (messageOptions?.use_global_assistant) {
            const jobName = (context as JobCodeContext)?.job_name;
            const workflowName = workflow?.name || 'workflow';
            finalContext = {
              ...finalContext,
              page: jobName
                ? `workflows/${workflowName}/${jobName}`
                : `workflows/${workflowName}`,
            };
          }
        }

        // Initialize store with context including content
        aiStore.connect(mode, finalContext, undefined);

        // Update URL to trigger subscription to "new" channel
        // useAISession will see the URL change and subscribe with the context (including content)
        if (mode === 'workflow_template') {
          updateSearchParams({ 'w-chat': 'new', 'j-chat': null });
        } else {
          updateSearchParams({ 'j-chat': 'new', 'w-chat': null });
        }

        // Mark message as sending in store
        aiStore.setMessageSending();
        aiStore.setStreamingStatus(getRandomStatus());
        return;
      }

      // For existing sessions, prepare options and send
      let options:
        | {
            attach_code?: boolean;
            attach_logs?: boolean;
            attach_io_data?: boolean;
            step_id?: string;
            code?: string;
            use_global_assistant?: boolean;
            page?: string;
          }
        | undefined = {
        ...messageOptions, // Include attach_code, attach_logs, attach_io_data, step_id
      };

      if (
        aiMode?.page === 'workflow_template' ||
        messageOptions?.use_global_assistant
      ) {
        const workflowData = prepareWorkflowForSerialization(
          workflow,
          jobs,
          triggers,
          edges,
          positions
        );
        const workflowYAML = workflowData
          ? serializeWorkflowToYAML(workflowData)
          : undefined;

        if (workflowYAML) {
          options = { ...options, code: workflowYAML };
        }

        // Derive page for global assistant routing
        if (messageOptions?.use_global_assistant) {
          const jobName = (aiMode?.context as JobCodeContext)?.job_name;
          const workflowName = workflow?.name || 'workflow';
          options.page = jobName
            ? `workflows/${workflowName}/${jobName}`
            : `workflows/${workflowName}`;
        }
      } else {
        // important: determines what ai to be used
        options = { ...aiMode?.context, ...options };
      }

      // Update store state and send through registry
      aiStore.setMessageSending();
      aiStore.setStreamingStatus(getRandomStatus());
      sendMessageToChannel(content, options);
    },
    [
      workflow,
      jobs,
      triggers,
      edges,
      positions,
      sendMessageToChannel,
      aiStore,
      aiMode,
      updateSearchParams,
      project,
    ]
  );

  const handleRetryMessage = useCallback(
    (messageId: string) => {
      aiStore.retryMessage(messageId);
      aiStore.setStreamingStatus(getRandomStatus());
      retryMessageViaChannel(messageId);
    },
    [aiStore, retryMessageViaChannel]
  );

  const handleGlobalAssistantChange = useCallback((active: boolean) => {
    setIsGlobalAssistantActive(active);
  }, []);

  const [applyingMessageId, setApplyingMessageId] = useState<string | null>(
    null
  );
  const [previewingMessageId, setPreviewingMessageId] = useState<string | null>(
    null
  );

  // Get shared monaco ref from context for diff preview
  const monacoRef = useMonacoRef();

  // Register callback to be notified when diff is dismissed
  useRegisterDiffDismissalCallback(() => {
    setPreviewingMessageId(null);
  });

  // Extract diff lifecycle management into hook
  const { handleClosePanel, handleShowSessions } = useAIPanelDiffManager({
    isOpen: isAIAssistantPanelOpen,
    previewingMessageId,
    setPreviewingMessageId,
    monacoRef,
    currentVersion,
    aiMode,
    closeAIAssistantPanel,
    aiStore,
    updateSearchParams,
  });

  const {
    importWorkflow,
    startApplyingWorkflow,
    doneApplyingWorkflow,
    startApplyingJobCode,
    doneApplyingJobCode,
    updateJob,
    saveWorkflow,
  } = useWorkflowActions();

  // Get applying state from workflow store for disabling Apply button across all users
  const isApplyingWorkflow = useWorkflowState(
    state => state.isApplyingWorkflow
  );
  const isApplyingJobCode = useWorkflowState(state => state.isApplyingJobCode);
  const applyingJobCodeMessageId = useWorkflowState(
    state => state.applyingJobCodeMessageId
  );

  const onValidationError = useCallback(
    (errorMessage: string) => {
      const message: Message = {
        id: randomUUID(),
        role: 'assistant',
        content: errorMessage,
        status: 'error',
        inserted_at: new Date().toISOString(),
      };
      aiStore._addMessage(message);
    },
    [aiStore]
  );

  // Pending streaming apply record (YAML already imported during streaming),
  // read by the hook's auto-apply effect to skip the duplicate import when
  // the final new_message arrives with the same YAML
  const streamingApply = useAIStreamingApply();
  const streamingApplyActions = useMemo(
    () => ({
      set: aiStore._setStreamingApply,
      setSaveFailed: aiStore._setStreamingApplySaveFailed,
      clear: aiStore._clearStreamingApply,
    }),
    [aiStore]
  );

  const appliedCanvas = useAppliedCanvas();

  const {
    undoneMessageId,
    requestUndoChanges,
    isConfirmOpen,
    confirmUndoChanges,
    cancelUndoChanges,
  } = useAIWorkflowUndo({
    jobs,
    appliedCanvas,
    workflowActions: {
      importWorkflow,
      startApplyingWorkflow,
      doneApplyingWorkflow,
    },
  });

  // Hook to handle workflow/job code application logic
  const {
    handleApplyWorkflow,
    launchApply,
    failedApplyMessageIds,
    handlePreviewJobCode,
    handlePreviewGlobalStep,
    handleApplyJobCode,
  } = useAIWorkflowApplications({
    sessionId,
    page: aiMode?.page || 'workflow_template',
    currentSession:
      sessionId && messages.length > 0
        ? {
            messages,
            workflowTemplateContext,
          }
        : null,
    currentUserId: user?.id,
    aiMode,
    isGlobalSession: isGlobalAssistantActive,
    isNewWorkflow,
    isSessionConnected,
    isSessionConnecting,
    onValidationError,
    onCanvasApplied: appliedCanvas.record,
    onApplyFailure: reportApplyFailure,
    workflowActions: {
      importWorkflow,
      startApplyingWorkflow,
      doneApplyingWorkflow,
      startApplyingJobCode,
      doneApplyingJobCode,
      updateJob,
      saveWorkflow,
    },
    monacoRef,
    jobs,
    canApplyChanges,
    connectionState,
    setPreviewingMessageId,
    previewingMessageId,
    setApplyingMessageId,
    appliedMessageIdsRef,
    streamingApply,
    streamingApplyActions,
  });

  // Route auto-preview to the right handler: global messages carry a full
  // workflow YAML (the open step's diff is extracted from it), job-code
  // messages carry the job body directly.
  const handleAutoPreview = useCallback(
    (code: string, messageId: string) => {
      const message = messages.find(m => m.id === messageId);
      if (message?.from_global) {
        handlePreviewGlobalStep(code, messageId);
      } else {
        handlePreviewJobCode(code, messageId);
      }
    },
    [messages, handlePreviewGlobalStep, handlePreviewJobCode]
  );

  // Auto-preview job code when AI responds with code
  // Only for the user who authored the triggering message
  useAutoPreview({
    aiMode,
    session: sessionId
      ? { id: sessionId, session_type: 'workflow_template', messages }
      : null,
    currentUserId: user?.id,
    onPreview: handleAutoPreview,
  });

  // Auto-apply streaming changes as soon as they arrive (before text finishes)
  // This triggers the same apply/preview logic that normally runs on new_message,
  // but earlier — as soon as Apollo sends the structured changes event.
  const appliedStreamingChangesRef = useRef<Record<string, unknown> | null>(
    null
  );
  useEffect(() => {
    if (!streamingChanges || !canApplyChanges) return;
    // Avoid re-applying the same streaming changes object. The ref is only
    // set once a handler is invoked for the change (whatever its outcome —
    // a failed apply is recovered by the final new_message auto-apply), so
    // a change that never reached a handler stays eligible if the page
    // switches mid-stream.
    if (appliedStreamingChangesRef.current === streamingChanges) return;

    // Every collaborator's browser receives streaming_changes, but only the
    // author's client auto-applies: the Y.Doc is shared, so concurrent
    // applies from multiple viewers of the same session would race. Other
    // collaborators still see the result through the shared doc. When the
    // author can't be determined (no user info on the message) we fall back
    // to applying, preserving single-user behavior.
    const triggeringUserId = messages.findLast(m => m.role === 'user')?.user
      ?.id;
    if (triggeringUserId && user?.id && triggeringUserId !== user.id) return;

    // Workflow YAML applies to the shared Y.Doc, so global streams are
    // page-independent: global chat streams it from the job code view too,
    // and the diagram must be up to date whenever the user navigates there.
    // Non-global workflow chat keeps its workflow_template-only gate (a
    // stream can outlive a mid-stream switch to a job page).
    if ('yaml' in streamingChanges) {
      const yaml = streamingChanges['yaml'] as string;
      const yamlCanApply =
        isGlobalAssistantActive || aiMode?.page === 'workflow_template';
      if (yaml && yamlCanApply) {
        appliedStreamingChangesRef.current = streamingChanges;
        // handleApplyWorkflow records the streaming apply in the store
        // (after a successful import) so the final new_message can skip it
        void handleApplyWorkflow(yaml, STREAMING_MESSAGE_ID);
      }
    } else if (aiMode?.page === 'job_code' && 'code' in streamingChanges) {
      // Job code previews open job-editor UI, so they stay page-gated.
      const code = streamingChanges['code'] as string;
      if (code) {
        appliedStreamingChangesRef.current = streamingChanges;
        handlePreviewJobCode(code, STREAMING_MESSAGE_ID);
      }
    }
  }, [
    streamingChanges,
    aiMode?.page,
    canApplyChanges,
    isGlobalAssistantActive,
    messages,
    user?.id,
    handleApplyWorkflow,
    handlePreviewJobCode,
  ]);

  return (
    <div
      className="flex h-full flex-shrink-0"
      style={{
        zIndex: Z_INDEX.SIDE_PANEL,
        width: isAIAssistantPanelOpen ? `${width}px` : '0px',
        overflow: 'hidden',
        transition: isResizing
          ? 'none'
          : 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
      }}
    >
      {isAIAssistantPanelOpen && (
        <>
          <button
            type="button"
            data-testid="ai-panel-resize-handle"
            className="w-1 bg-gray-200 hover:bg-primary-500 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleResizeMouseDown}
            aria-label="Resize AI Assistant panel"
            onKeyDown={e => {
              if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
                e.preventDefault();
              }
            }}
          />
          <div className="flex-1 overflow-hidden">
            <AIAssistantPanel
              isOpen={isAIAssistantPanelOpen}
              onClose={isNewWorkflow ? undefined : handleClosePanel}
              onNewConversation={handleNewConversation}
              onSessionSelect={handleSessionSelect}
              onShowSessions={handleShowSessions}
              onSendMessage={sendMessage}
              sessionId={sessionId}
              messageCount={messages.length}
              isLoading={isLoading}
              isResizable={true}
              page={aiMode?.page}
              loadSessions={loadSessions}
              focusTrigger={focusTrigger}
              connectionState={sessionId ? connectionState : 'connected'}
              aiLimit={limits.ai_assistant ?? null}
              showGlobalAssistantOption={experimentalFeaturesEnabled}
              isGlobalAssistantActive={isGlobalAssistantActive}
              onGlobalAssistantChange={handleGlobalAssistantChange}
            >
              <MessageList
                messages={messages}
                isLoading={isLoading}
                onApplyWorkflow={
                  (aiMode?.page === 'workflow_template' ||
                    // Global messages apply the full workflow even while a
                    // job is open; handleApplyWorkflow still no-ops for
                    // non-global messages outside workflow_template mode.
                    messages.some(m => m.from_global && m.code)) &&
                  !isApplyingWorkflow
                    ? (yaml, messageId) => {
                        // Route through the hook's guarded launcher (not
                        // handleApplyWorkflow raw) so a manual apply marks the
                        // message and the auto-apply effect can't later re-fire
                        // a duplicate import/save for it.
                        launchApply(messageId, yaml);
                      }
                    : undefined
                }
                onApplyJobCode={
                  aiMode?.page === 'job_code' && !isApplyingJobCode
                    ? (code, messageId) => {
                        void handleApplyJobCode(code, messageId);
                      }
                    : undefined
                }
                onPreviewJobCode={
                  aiMode?.page === 'job_code' ? handlePreviewJobCode : undefined
                }
                applyingMessageId={
                  // If anyone is applying (including other users), pass the message ID
                  // to show "APPLYING..." state. Prioritize stored message ID from store,
                  // then fall back to local state.
                  isApplyingJobCode
                    ? (applyingJobCodeMessageId ?? applyingMessageId)
                    : undefined
                }
                previewingMessageId={previewingMessageId}
                showAddButtons={
                  aiMode?.page === 'job_code'
                    ? // For job_code: hide ADD buttons when message has code field
                      !messages.some(m => m.role === 'assistant' && m.code)
                    : false
                }
                showApplyButton={
                  aiMode?.page === 'workflow_template' ||
                  (aiMode?.page === 'job_code' && messages.some(m => m.code))
                }
                onRetryMessage={handleRetryMessage}
                isWriteDisabled={isWriteDisabled}
                streamingContent={streamingContent}
                streamingStatus={streamingStatus}
                streamingSegments={streamingSegments}
                streamingSnapshots={streamingSnapshots}
                snapshotsByMessageId={snapshotsByMessageId}
                onOpenStep={handleOpenStep}
                canOpenStep={canOpenStep}
                failedApplyMessageIds={failedApplyMessageIds}
                onUndoChanges={requestUndoChanges}
                undoneMessageId={undoneMessageId}
                isApplyInFlight={!!applyingMessageId || isApplyingWorkflow}
                isGlobalAssistantActive={isGlobalAssistantActive}
              />
            </AIAssistantPanel>
          </div>
        </>
      )}

      <AlertDialog
        isOpen={isConfirmOpen}
        onClose={cancelUndoChanges}
        onConfirm={confirmUndoChanges}
        title="Overwrite changes to the workflow?"
        // Neutral about whose changes they are: a collaborator's edits are
        // taken by the same whole-document replace.
        description="The workflow has been edited since the assistant applied these changes. Continuing replaces the whole workflow, discarding those edits."
        confirmLabel="Continue"
        variant="danger"
      />
    </div>
  );
}
