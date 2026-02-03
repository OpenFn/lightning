import { useState, useRef, useEffect, useCallback, useMemo } from 'react';

import { useURLState } from '../../react/lib/use-url-state';
import {
  parseWorkflowYAML,
  convertWorkflowSpecToState,
  applyJobCredsToWorkflowState,
  extractJobCredentials,
} from '../../yaml/util';
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
import { useAISession } from '../hooks/useAISession';
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
import { notifications } from '../lib/notifications';
import type { JobCodeContext } from '../types/ai-assistant';
import { Z_INDEX } from '../utils/constants';
import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../utils/workflowSerialization';

import { AIAssistantPanel } from './AIAssistantPanel';
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

  /**
   * isSyncingRef prevents re-entrant URL updates during panel state changes.
   *
   * Pattern explanation:
   * - When we update URL params, React re-renders with new searchParams
   * - This could trigger another URL update, creating an infinite loop
   * - We use a ref to track ongoing sync operations
   * - setTimeout(..., 0) breaks out of the current execution context,
   *   allowing the URL update to complete before we clear the flag
   *
   * This is a defensive pattern for synchronizing state with URL parameters.
   */
  const isSyncingRef = useRef(false);

  useEffect(() => {
    if (isSyncingRef.current) return;

    isSyncingRef.current = true;

    if (isAIAssistantPanelOpen) {
      updateSearchParams({
        chat: 'true',
      });
    } else {
      // When closing, clear chat param and session params
      updateSearchParams({
        chat: null,
        'w-chat': null,
        'j-chat': null,
      });
    }

    setTimeout(() => {
      isSyncingRef.current = false;
    }, 0);
  }, [isAIAssistantPanelOpen, updateSearchParams]);

  const aiMode = useAIMode();

  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = params[paramName];

    return sessionId;
  }, [aiMode, params]);

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

  useEffect(() => {
    // Don't sync session ID to URL when panel is closed
    if (!isAIAssistantPanelOpen) return;
    if (!sessionId || !aiMode) return;

    const state = aiStore.getSnapshot();
    const sessionType = state.sessionType;

    // CRITICAL: Only sync to URL if session type matches current mode
    // This prevents syncing a workflow session ID to job mode URL (or vice versa)
    if (sessionType !== aiMode.mode) {
      return;
    }

    const currentParamName =
      aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const otherParamName =
      aiMode.mode === 'workflow_template' ? 'j-chat' : 'w-chat';
    const currentValue = params[currentParamName];

    if (currentValue !== sessionId) {
      updateSearchParams({
        [currentParamName]: sessionId,
        [otherParamName]: null, // Clear the other mode's session
      });
    }
  }, [
    sessionId,
    aiMode,
    params,
    updateSearchParams,
    aiStore,
    isAIAssistantPanelOpen,
  ]);

  // Push job context updates to backend when job body/adaptor/name changes
  // This ensures the AI has access to the current code when "Attach code" is checked
  useEffect(() => {
    // Only update context for active job_code sessions
    if (
      !isAIAssistantPanelOpen ||
      !sessionId ||
      sessionType !== 'job_code' ||
      !aiMode ||
      aiMode.mode !== 'job_code'
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
  }, [
    isAIAssistantPanelOpen,
    sessionId,
    sessionType,
    aiMode,
    updateContextViaChannel,
  ]);

  /**
   * appliedMessageIdsRef tracks which AI-generated workflows have been automatically applied.
   *
   * Auto-apply behavior:
   * - When the AI responds with YAML code in workflow_template mode, we automatically
   *   apply it to the canvas (see useEffect below)
   * - This ref prevents applying the same message multiple times if the component re-renders
   * - The ref is cleared when:
   *   1. Starting a new conversation (handleNewConversation)
   *   2. Switching to a different session (handleSessionSelect)
   *
   * This provides a smooth UX where users see their workflow update in real-time
   * as the AI generates it, without requiring manual "Apply" button clicks.
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
      if (
        messageOptions?.attach_code &&
        aiMode?.mode === 'job_code' &&
        currentState.sessionType === 'job_code'
      ) {
        const context = aiMode.context as JobCodeContext;
        const jobId = context.job_id;

        if (jobId) {
          // Get fresh code from jobs array (backed by Y.Doc)
          const currentJob = jobs.find(j => j.id === jobId);
          if (currentJob) {
            // Update aiMode with new context (don't mutate)
            updatedAiMode = {
              ...aiMode,
              context: {
                ...context,
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
        const { mode, context } = updatedAiMode;

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
        if (mode === 'workflow_template') {
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

      if (currentState.sessionType === 'workflow_template') {
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

  // Close handler - clears diff preview and closes panel
  const handleClosePanel = useCallback(() => {
    const monaco = monacoRef?.current;
    // Clear any active diff preview when closing the panel
    if (previewingMessageId && monaco) {
      monaco.clearDiff();
      setPreviewingMessageId(null);
    }
    closeAIAssistantPanel();
  }, [closeAIAssistantPanel, previewingMessageId, monacoRef]);

  // Show sessions handler - clears diff preview and returns to session list
  const handleShowSessions = useCallback(() => {
    const monaco = monacoRef?.current;
    // Clear any active diff preview when going back to session list
    if (previewingMessageId && monaco) {
      monaco.clearDiff();
      setPreviewingMessageId(null);
    }

    aiStore.clearSession();
    // Clear session list to force reload - ensures fresh data after tab sleep
    aiStore._clearSessionList();

    // Ensure context is initialized for session list loading
    // This handles cases where context might have been lost (e.g., after tab sleep)
    if (aiMode) {
      aiStore._initializeContext(aiMode.mode, aiMode.context);
    }

    // Clear session ID from URL - shows session list
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });
  }, [updateSearchParams, aiStore, aiMode, previewingMessageId, monacoRef]);

  const hasLoadedSessionRef = useRef(false);
  const previousVersionRef = useRef(currentVersion);

  // Reset hasLoadedSessionRef when session changes
  useEffect(() => {
    hasLoadedSessionRef.current = false;
  }, [sessionId]);

  // Auto-dismiss diff AND close AI panel when version changes to pinned version
  useEffect(() => {
    // Only act if version actually changed (not on initial mount or state updates)
    if (previousVersionRef.current !== currentVersion) {
      const monaco = monacoRef?.current;
      // 1. Clear diff if one is being previewed
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }

      // 2. Close AI panel and clear session if switching TO a pinned version
      if (isPinnedVersion && isAIAssistantPanelOpen) {
        closeAIAssistantPanel();
        // Clear the AI session to prevent confusion about version context
        aiStore.clearSession();
        // Clear URL session params
        updateSearchParams({
          'w-chat': null,
          'j-chat': null,
        });
      }
    }

    previousVersionRef.current = currentVersion;
  }, [
    currentVersion,
    previewingMessageId,
    monacoRef,
    isPinnedVersion,
    isAIAssistantPanelOpen,
    closeAIAssistantPanel,
    aiStore,
    updateSearchParams,
  ]);

  // Track previous job ID to detect changes and clear diff
  const previousJobIdRef = useRef<string | null>(null);

  // Auto-dismiss diff when job changes (prevents showing Job A's diff while viewing Job B)
  useEffect(() => {
    // Only track job changes when in job_code mode
    if (!aiMode || aiMode.mode !== 'job_code') {
      previousJobIdRef.current = null;
      return;
    }

    const context = aiMode.context as JobCodeContext;
    if (!context?.job_id) {
      previousJobIdRef.current = null;
      return;
    }

    const currentJobId = context.job_id;

    // Detect actual job change (not initial mount)
    if (
      previousJobIdRef.current !== null &&
      previousJobIdRef.current !== currentJobId
    ) {
      const monaco = monacoRef?.current;

      // Clear any active diff preview when job changes
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }
    }

    // Update tracked job ID
    previousJobIdRef.current = currentJobId;
  }, [aiMode, previewingMessageId, monacoRef]);

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

  const handleApplyWorkflow = useCallback(
    async (yaml: string, messageId: string) => {
      setApplyingMessageId(messageId);

      // Signal to all collaborators that we're starting to apply
      // Returns false if coordination failed (other users won't be notified)
      const coordinated = await startApplyingWorkflow(messageId);

      try {
        const workflowSpec = parseWorkflowYAML(yaml);

        const validateIds = (spec: Record<string, unknown>) => {
          if (spec['jobs']) {
            for (const [jobKey, job] of Object.entries(
              spec['jobs'] as object
            )) {
              const jobItem = job as Record<string, unknown>;
              if (
                jobItem['id'] &&
                typeof jobItem['id'] === 'object' &&
                jobItem['id'] !== null
              ) {
                throw new Error(
                  `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec['triggers']) {
            for (const [triggerKey, trigger] of Object.entries(
              spec['triggers'] as object
            )) {
              const triggerItem = trigger as Record<string, unknown>;
              if (
                triggerItem['id'] &&
                typeof triggerItem['id'] === 'object' &&
                triggerItem['id'] !== null
              ) {
                throw new Error(
                  `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          if (spec['edges']) {
            for (const [edgeKey, edge] of Object.entries(
              spec['edges'] as object
            )) {
              const edgeItem = edge as Record<string, unknown>;
              if (
                edgeItem['id'] &&
                typeof edgeItem['id'] === 'object' &&
                edgeItem['id'] !== null
              ) {
                throw new Error(
                  `Invalid ID format for edge "${edgeKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
        };

        validateIds(workflowSpec);

        // IDs are already in the YAML from AI (sent with IDs, like legacy editor)
        const workflowState = convertWorkflowSpecToState(workflowSpec);

        const workflowStateWithCreds = applyJobCredsToWorkflowState(
          workflowState,
          extractJobCredentials(jobs)
        );

        importWorkflow(workflowStateWithCreds);
      } catch (error) {
        console.error('[AI Assistant] Failed to apply workflow:', error);

        notifications.alert({
          title: 'Failed to apply workflow',
          description:
            error instanceof Error ? error.message : 'Invalid workflow YAML',
        });
      } finally {
        setApplyingMessageId(null);
        // Only signal completion if we successfully coordinated
        // (otherwise other users weren't notified of the start)
        if (coordinated) {
          await doneApplyingWorkflow(messageId);
        }
      }
    },
    [importWorkflow, startApplyingWorkflow, doneApplyingWorkflow, jobs]
  );

  const handlePreviewJobCode = useCallback(
    (code: string, messageId: string) => {
      if (!aiMode || aiMode.mode !== 'job_code') {
        console.error('[AI Assistant] Cannot preview - not in job mode', {
          aiMode,
        });
        return;
      }

      const context = aiMode.context as JobCodeContext;
      const jobId = context.job_id;

      if (!jobId) {
        console.error('[AI Assistant] Cannot preview - no job ID', { context });
        notifications.alert({
          title: 'Cannot preview code',
          description: 'No job selected',
        });
        return;
      }

      // If already previewing this message, do nothing
      if (previewingMessageId === messageId) {
        return;
      }

      const monaco = monacoRef?.current;

      // Clear any existing diff first
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
      }

      // Get current job code from Y.Doc
      const currentJob = jobs.find(j => j.id === jobId);
      const currentCode = currentJob?.body ?? '';

      // Show diff in Monaco
      if (monaco) {
        monaco.showDiff(currentCode, code);
        setPreviewingMessageId(messageId);
      } else {
        console.error('[AI Assistant] ❌ Monaco ref not available', {
          hasMonacoRef: !!monacoRef,
          hasMonacoRefCurrent: !!monacoRef?.current,
        });
        notifications.alert({
          title: 'Preview unavailable',
          description: 'Editor not ready. Please try again in a moment.',
        });
      }
    },
    [aiMode, jobs, previewingMessageId, monacoRef]
  );

  const handleApplyJobCode = useCallback(
    async (code: string, messageId: string) => {
      if (!aiMode || aiMode.mode !== 'job_code') {
        console.error('[AI Assistant] Cannot apply job code - not in job mode');
        return;
      }

      const context = aiMode.context as JobCodeContext;
      const jobId = context.job_id;

      if (!jobId) {
        notifications.alert({
          title: 'Cannot apply code',
          description: 'No job selected',
        });
        return;
      }

      const monaco = monacoRef?.current;
      // Clear diff if showing
      if (previewingMessageId && monaco) {
        monaco.clearDiff();
        setPreviewingMessageId(null);
      }

      setApplyingMessageId(messageId);

      // Coordinate with collaborators (non-blocking)
      const coordinated = await startApplyingJobCode(messageId);

      try {
        // Update job body in Y.Doc (syncs to all collaborators)
        updateJob(jobId, { body: code });

        notifications.success({
          title: 'Code applied',
          description: 'Job code has been updated',
        });
      } catch (error) {
        console.error('[AI Assistant] Failed to apply job code:', error);

        notifications.alert({
          title: 'Failed to apply code',
          description:
            error instanceof Error ? error.message : 'Unknown error occurred',
        });
      } finally {
        setApplyingMessageId(null);
        // Only signal completion if we successfully coordinated
        if (coordinated) {
          await doneApplyingJobCode(messageId);
        }
      }
    },
    [
      aiMode,
      updateJob,
      startApplyingJobCode,
      doneApplyingJobCode,
      previewingMessageId,
      monacoRef,
    ]
  );

  // Auto-preview job code when AI responds with code
  // Only for the user who authored the triggering message
  useAutoPreview({
    aiMode,
    session:
      sessionId && sessionType
        ? { id: sessionId, session_type: sessionType, messages }
        : null,
    currentUserId: user?.id,
    onPreview: handlePreviewJobCode,
  });

  /**
   * Auto-apply workflow when AI responds with YAML code.
   *
   * This effect watches for new messages in workflow_template mode and automatically
   * applies the latest workflow YAML to the canvas. This creates a seamless experience
   * where users see their workflow update in real-time as the AI generates it.
   *
   * Conditions for auto-apply:
   * - Session type is 'workflow_template' (not job_code)
   * - There are messages in the conversation
   * - Connection is established (prevents applying during reconnection)
   * - The message has code and hasn't been applied yet (tracked in appliedMessageIdsRef)
   * - The current user is the one who sent the message that triggered the AI response
   *   (prevents duplicate applies in collaborative sessions where multiple users view the same chat)
   *
   * Note: We only apply the LATEST message with code to avoid applying intermediate
   * drafts if the AI sends multiple responses quickly.
   */
  useEffect(() => {
    if (sessionType !== 'workflow_template' || !messages.length) return;
    if (connectionState !== 'connected') return;
    // Don't auto-apply when readonly (except for new workflow creation)
    if (!canApplyChanges) return;

    const messagesWithCode = messages.filter(
      msg => msg.role === 'assistant' && msg.code && msg.status === 'success'
    );

    // On initial session load, mark all existing messages as already applied
    // to prevent re-applying workflows when opening existing sessions
    if (!hasLoadedSessionRef.current) {
      hasLoadedSessionRef.current = true;
      messagesWithCode.forEach(msg => {
        appliedMessageIdsRef.current.add(msg.id);
      });
      return;
    }

    const latestMessage = messagesWithCode.pop();

    if (
      latestMessage?.code &&
      !appliedMessageIdsRef.current.has(latestMessage.id)
    ) {
      // Find the user message that triggered this AI response
      // Look for the most recent user message before this assistant message
      const latestMessageIndex = messages.findIndex(
        m => m.id === latestMessage.id
      );
      const precedingUserMessage = messages
        .slice(0, latestMessageIndex)
        .reverse()
        .find(m => m.role === 'user');

      // Only auto-apply if the current user sent the triggering message
      // This prevents duplicate applies in collaborative sessions where
      // multiple users view the same chat and would otherwise all auto-apply
      const isCurrentUserAuthor =
        precedingUserMessage?.user_id === user?.id ||
        // Fallback: if no user_id on message (legacy), allow apply
        !precedingUserMessage?.user_id;

      appliedMessageIdsRef.current.add(latestMessage.id);

      if (isCurrentUserAuthor) {
        void handleApplyWorkflow(latestMessage.code, latestMessage.id);
      }
    }
  }, [
    messages,
    sessionType,
    sessionId,
    connectionState,
    workflowTemplateContext,
    workflow,
    handleApplyWorkflow,
    canApplyChanges,
    user?.id,
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
              onClose={handleClosePanel}
              onNewConversation={handleNewConversation}
              onSessionSelect={handleSessionSelect}
              onShowSessions={handleShowSessions}
              onSendMessage={sendMessage}
              sessionId={sessionId}
              messageCount={messages.length}
              isLoading={isLoading}
              isResizable={true}
              sessionType={sessionType}
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
                {...(sessionType && { sessionType })}
                onApplyWorkflow={
                  sessionType === 'workflow_template' && !isApplyingWorkflow
                    ? (yaml, messageId) => {
                        void handleApplyWorkflow(yaml, messageId);
                      }
                    : undefined
                }
                onApplyJobCode={
                  sessionType === 'job_code' && !isApplyingJobCode
                    ? (code, messageId) => {
                        void handleApplyJobCode(code, messageId);
                      }
                    : undefined
                }
                onPreviewJobCode={
                  sessionType === 'job_code' ? handlePreviewJobCode : undefined
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
                  sessionType === 'job_code'
                    ? // For job_code: hide ADD buttons when message has code field
                      !messages.some(m => m.role === 'assistant' && m.code)
                    : false
                }
                showApplyButton={
                  sessionType === 'workflow_template' ||
                  (sessionType === 'job_code' && messages.some(m => m.code))
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
