import { useState, useRef, useEffect, useCallback } from 'react';

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
  useAIWorkflowTemplateContext,
} from '../hooks/useAIAssistant';
import { useAISessionCommands } from '../hooks/useAIChannelRegistry';
import { useAIInitialMessage } from '../hooks/useAIInitialMessage';
import { useAIMode } from '../hooks/useAIMode';
import { useAIPanelDiffManager } from '../hooks/useAIPanelDiffManager';
import { useAIPanelURLSync } from '../hooks/useAIPanelURLSync';
import { useAISession } from '../hooks/useAISession';
import { useAIWorkflowApplications } from '../hooks/useAIWorkflowApplications';
import { useAutoPreview } from '../hooks/useAutoPreview';
import { useResizablePanel } from '../hooks/useResizablePanel';
import {
  useProject,
  useHasReadAIDisclaimer,
  useMarkAIDisclaimerRead,
  useSessionContextLoaded,
  useLimits,
  useIsNewWorkflow,
  useUser,
} from '../hooks/useSessionContext';
import {
  useIsAIAssistantPanelOpen,
  useUICommands,
  useAIAssistantInitialMessage,
} from '../hooks/useUI';
import {
  useWorkflowState,
  useWorkflowActions,
  useWorkflowReadOnly,
} from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import type { JobCodeContext } from '../types/ai-assistant';
import { Z_INDEX } from '../utils/constants';
import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
import flowEvents from './diagram/react-flow-events';
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
export function AIAssistantPanelWrapper() {
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();
  const initialMessage = useAIAssistantInitialMessage();
  const {
    closeAIAssistantPanel,
    toggleAIAssistantPanel,
    clearAIAssistantInitialMessage,
    collapseCreateWorkflowPanel,
  } = useUICommands();
  const { updateSearchParams, params } = useURLState();
  const currentVersion = params['v'];

  // Check if viewing a pinned version (not latest) to disable AI Assistant
  const isPinnedVersion =
    currentVersion !== undefined && currentVersion !== null;

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
  // Disabled when viewing a pinned version (not latest)
  useKeyboardShortcut(
    '$mod+k',
    () => {
      // Close create workflow panel when opening AI Assistant
      if (!isAIAssistantPanelOpen) {
        collapseCreateWorkflowPanel();
      }
      toggleAIAssistantPanel();
    },
    0,
    { enabled: !isPinnedVersion }
  );

  const aiStore = useAIStore();
  const {
    sendMessage: sendMessageToChannel,
    loadSessions,
    retryMessage: retryMessageViaChannel,
    updateContext: updateContextViaChannel,
  } = useAISessionCommands();
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const sessionContextLoaded = useSessionContextLoaded();
  const hasReadDisclaimer = useHasReadAIDisclaimer();
  const markAIDisclaimerRead = useMarkAIDisclaimerRead();
  const workflowTemplateContext = useAIWorkflowTemplateContext();
  const project = useProject();
  const user = useUser();
  const workflow = useWorkflowState(state => state.workflow);
  const limits = useLimits();

  // Check readonly state and new workflow status
  // AI can apply changes if: not readonly OR is a new workflow (being created)
  const { isReadOnly } = useWorkflowReadOnly();
  const isNewWorkflow = useIsNewWorkflow();
  const canApplyChanges = !isReadOnly || isNewWorkflow;
  const isWriteDisabled = !canApplyChanges;

  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
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

  // Handle initial message from template selection
  // When user clicks "AI workflow from description" from LeftPanel,
  // the initial message is stored in UI state and we auto-send it
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
        };

        // Add workflow YAML if in workflow mode
        if (page === 'workflow_template') {
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
          }
        | undefined = {
        ...messageOptions, // Include attach_code, attach_logs, attach_io_data, step_id
      };

      if (aiMode?.page === 'workflow_template') {
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
      } else {
        // important: determines what ai to be used
        options = { ...options, job_id: aiMode?.context.job_id };
      }

      // Update store state and send through registry
      aiStore.setMessageSending();
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
      retryMessageViaChannel(messageId);
    },
    [aiStore, retryMessageViaChannel]
  );

  const handleMarkDisclaimerRead = useCallback(() => {
    // Persist to backend via workflow channel and update local state
    markAIDisclaimerRead();
    // Also update AI store for consistency
    aiStore.markDisclaimerRead();
  }, [aiStore, markAIDisclaimerRead]);

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
  } = useWorkflowActions();

  // Get applying state from workflow store for disabling Apply button across all users
  const isApplyingWorkflow = useWorkflowState(
    state => state.isApplyingWorkflow
  );
  const isApplyingJobCode = useWorkflowState(state => state.isApplyingJobCode);
  const applyingJobCodeMessageId = useWorkflowState(
    state => state.applyingJobCodeMessageId
  );

  // Hook to handle workflow/job code application logic
  const { handleApplyWorkflow, handlePreviewJobCode, handleApplyJobCode } =
    useAIWorkflowApplications({
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
      workflowActions: {
        importWorkflow,
        startApplyingWorkflow,
        doneApplyingWorkflow,
        startApplyingJobCode,
        doneApplyingJobCode,
        updateJob,
      },
      monacoRef,
      jobs,
      canApplyChanges,
      connectionState,
      setPreviewingMessageId,
      previewingMessageId,
      setApplyingMessageId,
      appliedMessageIdsRef,
    });

  // Auto-preview job code when AI responds with code
  // Only for the user who authored the triggering message
  useAutoPreview({
    aiMode,
    session: sessionId
      ? { id: sessionId, session_type: 'workflow_template', messages }
      : null,
    currentUserId: user?.id,
    onPreview: handlePreviewJobCode,
  });

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
              onClose={handleClosePanel}
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
              showDisclaimer={sessionContextLoaded && !hasReadDisclaimer}
              onAcceptDisclaimer={handleMarkDisclaimerRead}
              aiLimit={limits.ai_assistant ?? null}
            >
              <MessageList
                messages={messages}
                isLoading={isLoading}
                onApplyWorkflow={
                  aiMode?.page === 'workflow_template' && !isApplyingWorkflow
                    ? (yaml, messageId) => {
                        void handleApplyWorkflow(yaml, messageId);
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
              />
            </AIAssistantPanel>
          </div>
        </>
      )}
    </div>
  );
}
