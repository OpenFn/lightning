import { useMemo, useState, useRef, useEffect, useCallback } from 'react';
import YAML from 'yaml';

import { SocketProvider } from '../react/contexts/SocketProvider';
import { useURLState } from '../react/lib/use-url-state';
import type { WithActionProps } from '../react/lib/with-props';
import {
  convertWorkflowStateToSpec,
  parseWorkflowYAML,
  convertWorkflowSpecToState,
} from '../yaml/util';

import { AIAssistantPanel } from './components/AIAssistantPanel';
import { MessageList } from './components/MessageList';
import { BreadcrumbLink, BreadcrumbText } from './components/Breadcrumbs';
import { Header } from './components/Header';
import { LoadingBoundary } from './components/LoadingBoundary';
import { Toaster } from './components/ui/Toaster';
import { VersionDebugLogger } from './components/VersionDebugLogger';
import { VersionDropdown } from './components/VersionDropdown';
import { WorkflowEditor } from './components/WorkflowEditor';
import { LiveViewActionsProvider } from './contexts/LiveViewActionsContext';
import { SessionProvider } from './contexts/SessionProvider';
import { StoreProvider } from './contexts/StoreProvider';
import {
  useAIConnectionState,
  useAIIsLoading,
  useAIMessages,
  useAISessionId,
  useAISessionType,
  useAIStore,
  useAIWorkflowTemplateContext,
} from './hooks/useAIAssistant';
import { useAIMode } from './hooks/useAIMode';
import { useAIAssistantChannel } from './hooks/useAIAssistantChannel';
import {
  useLatestSnapshotLockVersion,
  useProject,
} from './hooks/useSessionContext';
import {
  useIsAIAssistantPanelOpen,
  useIsRunPanelOpen,
  useUICommands,
} from './hooks/useUI';
import { useVersionSelect } from './hooks/useVersionSelect';
import { useWorkflowState, useWorkflowActions } from './hooks/useWorkflow';
import { notifications } from './lib/notifications';
import { KeyboardProvider } from './keyboard';

export interface CollaborativeEditorDataProps {
  'data-workflow-id': string;
  'data-workflow-name': string;
  'data-project-id': string;
  'data-project-name'?: string;
  'data-project-color'?: string;
  'data-project-env'?: string;
  'data-root-project-id'?: string;
  'data-root-project-name'?: string;
  'data-is-new-workflow'?: string;
}

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
function AIAssistantPanelWrapper() {
  const isAIAssistantPanelOpen = useIsAIAssistantPanelOpen();
  const { closeAIAssistantPanel } = useUICommands();
  const { updateSearchParams, searchParams } = useURLState();

  // AI Assistant integration
  const aiStore = useAIStore();
  const {
    sendMessage: sendMessageToChannel,
    loadSessions,
    updateContext,
  } = useAIAssistantChannel(aiStore);
  const messages = useAIMessages();
  const isLoading = useAIIsLoading();
  const sessionId = useAISessionId();
  const sessionType = useAISessionType();
  const connectionState = useAIConnectionState();
  const workflowTemplateContext = useAIWorkflowTemplateContext();
  const project = useProject();
  const workflow = useWorkflowState(state => state.workflow);

  // Get workflow data for YAML serialization
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const positions = useWorkflowState(state => state.positions);

  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem('ai-assistant-panel-width');
    return saved ? parseInt(saved, 10) : 400;
  });
  const [isResizing, setIsResizing] = useState(false);
  const startXRef = useRef<number>(0);
  const startWidthRef = useRef<number>(0);
  const isSyncingRef = useRef(false);

  // Sync store state to URL
  useEffect(() => {
    if (isSyncingRef.current) return;

    isSyncingRef.current = true;
    updateSearchParams({
      chat: isAIAssistantPanelOpen ? 'true' : null,
    });
    setTimeout(() => {
      isSyncingRef.current = false;
    }, 0);
  }, [isAIAssistantPanelOpen, updateSearchParams]);

  useEffect(() => {
    if (!isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      const deltaX = startXRef.current - e.clientX;
      const newWidth = Math.max(
        300,
        Math.min(800, startWidthRef.current + deltaX)
      );
      setWidth(newWidth);
    };

    const handleMouseUp = () => {
      setIsResizing(false);
      localStorage.setItem('ai-assistant-panel-width', width.toString());
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isResizing, width]);

  const handleMouseDown = (e: React.MouseEvent) => {
    e.preventDefault();
    setIsResizing(true);
    startXRef.current = e.clientX;
    startWidthRef.current = width;
  };

  // Detect current AI mode (job_code or workflow_template)
  const aiMode = useAIMode();

  // Get session ID from URL params - ONLY read param that matches current mode
  // w-chat for workflow_template mode, j-chat for job_code mode
  const sessionIdFromURL = useMemo(() => {
    if (!aiMode) return null;

    // Get the parameter name for current mode
    const paramName = aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const sessionId = searchParams.get(paramName);

    console.log('[AI Assistant] Session from URL', {
      mode: aiMode.mode,
      paramName,
      sessionId,
    });

    return sessionId;
  }, [aiMode, searchParams]);

  // Clear session URL param when job/mode changes
  // This is separate from the main effect to avoid circular dependencies
  useEffect(() => {
    if (!isAIAssistantPanelOpen || !aiMode) return;

    const state = aiStore.getSnapshot();
    const { mode, context } = aiMode;

    // Check if we're switching modes or jobs
    const isModeSwitch = state.sessionType && state.sessionType !== mode;
    const jobIdChanged =
      mode === 'job_code' &&
      state.jobCodeContext &&
      (context as import('./types/ai-assistant').JobCodeContext).job_id !==
        state.jobCodeContext.job_id;

    if (isModeSwitch || jobIdChanged) {
      console.log('[AI Assistant] Clearing session URL on context change', {
        isModeSwitch,
        jobIdChanged,
        mode,
      });

      // Clear BOTH params to ensure we start fresh
      updateSearchParams({
        'w-chat': null,
        'j-chat': null,
      });
    }
  }, [isAIAssistantPanelOpen, aiMode, updateSearchParams, aiStore]);

  // Single unified effect for context initialization and session loading
  // This runs ONCE when panel opens or mode changes
  useEffect(() => {
    if (!isAIAssistantPanelOpen || !aiMode) return;

    const state = aiStore.getSnapshot();
    const { mode, context } = aiMode;

    console.log('[AI Assistant] Panel opened/mode changed', {
      mode,
      storeSessionType: state.sessionType,
      hasJobContext: !!state.jobCodeContext,
      hasWorkflowContext: !!state.workflowTemplateContext,
      sessionIdFromURL,
      connectionState: state.connectionState,
    });

    // STEP 1: Check if we're switching modes (job ↔ workflow)
    const isModeSwitch = state.sessionType && state.sessionType !== mode;

    if (isModeSwitch) {
      console.log('[AI Assistant] Mode switch detected:', {
        from: state.sessionType,
        to: mode,
      });

      // Disconnect and clear everything from the old mode
      if (state.connectionState !== 'disconnected') {
        aiStore.disconnect();
      }
      aiStore._clearSession();
      aiStore._clearSessionList(); // Clear sessions and show loading
    }

    // STEP 2: Initialize context for current mode
    // This MUST happen before any session loading
    // Also check if the context has changed (e.g., switching between jobs)
    const jobIdChanged =
      mode === 'job_code' &&
      state.jobCodeContext &&
      (context as import('./types/ai-assistant').JobCodeContext).job_id !==
        state.jobCodeContext.job_id;

    const needsContextInit =
      !state.sessionType ||
      (mode === 'job_code' && !state.jobCodeContext) ||
      (mode === 'workflow_template' && !state.workflowTemplateContext) ||
      jobIdChanged;

    if (needsContextInit || isModeSwitch) {
      console.log('[AI Assistant] Initializing context', {
        mode,
        needsInit: needsContextInit,
        isModeSwitch,
        jobIdChanged,
      });

      // If job changed OR mode switched, clear session and session list
      if (jobIdChanged || isModeSwitch) {
        console.log('[AI Assistant] Context changed, clearing sessions', {
          jobIdChanged,
          isModeSwitch,
          oldJobId: state.jobCodeContext?.job_id,
          newJobId:
            mode === 'job_code'
              ? (context as import('./types/ai-assistant').JobCodeContext)
                  .job_id
              : undefined,
        });

        // Disconnect and clear session data
        if (state.connectionState !== 'disconnected') {
          aiStore.disconnect();
        }
        aiStore._clearSession();
        aiStore._clearSessionList();
      }

      // Set context immediately and synchronously
      aiStore.connect(mode, context, undefined);
      aiStore.disconnect(); // Just set context, don't actually connect
    }

    // STEP 3: Load session if there's one in URL, otherwise we're done
    if (!sessionIdFromURL) {
      console.log(
        '[AI Assistant] No session in URL - ready for new conversation'
      );
      return;
    }

    // STEP 4: Connect to the session from URL
    console.log('[AI Assistant] Loading session from URL', {
      sessionId: sessionIdFromURL,
    });

    // Add workflow YAML for workflow_template mode
    let finalContext = context;
    if (mode === 'workflow_template' && workflow && jobs.length > 0) {
      try {
        const workflowSpec = convertWorkflowStateToSpec(
          {
            id: workflow.id,
            name: workflow.name,
            jobs: jobs.map(job => ({
              id: job.id,
              name: job.name,
              adaptor: job.adaptor,
              body: job.body,
            })),
            triggers: triggers,
            edges: edges.map(edge => ({
              id: edge.id,
              condition_type: edge.condition_type || 'always',
              enabled: edge.enabled !== false,
              target_job_id: edge.target_job_id,
              ...(edge.source_job_id && {
                source_job_id: edge.source_job_id,
              }),
              ...(edge.source_trigger_id && {
                source_trigger_id: edge.source_trigger_id,
              }),
              ...(edge.condition_label && {
                condition_label: edge.condition_label,
              }),
              ...(edge.condition_expression && {
                condition_expression: edge.condition_expression,
              }),
            })),
            positions: positions,
          },
          false
        );
        const workflowYAML = YAML.stringify(workflowSpec);
        finalContext = { ...context, code: workflowYAML };
      } catch (error) {
        console.error('Failed to serialize workflow to YAML:', error);
      }
    }

    // Connect with session ID from URL
    aiStore.connect(mode, finalContext, sessionIdFromURL);
  }, [
    isAIAssistantPanelOpen,
    aiMode,
    workflow,
    jobs,
    triggers,
    edges,
    positions,
    aiStore,
    sessionIdFromURL,
    updateSearchParams,
  ]);

  // Sync session ID to URL params - matches legacy editor behavior
  useEffect(() => {
    if (!sessionId || !aiMode) return;

    // Get the session type from store to verify it matches current mode
    const state = aiStore.getSnapshot();
    const sessionType = state.sessionType;

    // CRITICAL: Only sync to URL if session type matches current mode
    // This prevents syncing a workflow session ID to job mode URL (or vice versa)
    if (sessionType !== aiMode.mode) {
      console.log('[AI Assistant] Skipping URL sync - session type mismatch', {
        sessionType,
        currentMode: aiMode.mode,
      });
      return;
    }

    // Get parameter name for current mode
    const currentParamName =
      aiMode.mode === 'workflow_template' ? 'w-chat' : 'j-chat';
    const currentValue = searchParams.get(currentParamName);

    // Only update if session ID changed
    if (currentValue !== sessionId) {
      console.log('[AI Assistant] Syncing session to URL', {
        mode: aiMode.mode,
        paramName: currentParamName,
        sessionId,
      });

      updateSearchParams({
        [currentParamName]: sessionId,
        // NOTE: We do NOT clear the other mode's param anymore
        // Both params can coexist in the URL
      });
    }
  }, [sessionId, aiMode, searchParams, updateSearchParams, aiStore]);

  // Disconnect when panel closes and clear URL params
  useEffect(() => {
    if (!isAIAssistantPanelOpen) {
      aiStore.disconnect();
      // Clear chat params from URL
      updateSearchParams({
        'w-chat': null,
        'j-chat': null,
      });
    }
  }, [isAIAssistantPanelOpen, aiStore, updateSearchParams]);

  // Watch for job context changes (adaptor, body, name) and update AI Assistant
  useEffect(() => {
    // Only track changes when:
    // 1. Panel is open
    // 2. In job_code mode
    // 3. Connected to a session
    if (
      !isAIAssistantPanelOpen ||
      !aiMode ||
      aiMode.mode !== 'job_code' ||
      !sessionId
    ) {
      return;
    }

    const context =
      aiMode.context as import('./types/ai-assistant').JobCodeContext;

    console.log('[AI Assistant] Job context changed, updating backend', {
      job_adaptor: context.job_adaptor,
      job_body_length: context.job_body?.length,
      job_name: context.job_name,
    });

    // Notify backend of context changes
    const contextUpdate: {
      job_adaptor?: string;
      job_body?: string;
      job_name?: string;
    } = {};
    if (context.job_adaptor !== undefined)
      contextUpdate.job_adaptor = context.job_adaptor;
    if (context.job_body !== undefined)
      contextUpdate.job_body = context.job_body;
    if (context.job_name !== undefined)
      contextUpdate.job_name = context.job_name;

    updateContext(contextUpdate);
  }, [isAIAssistantPanelOpen, aiMode, sessionId, updateContext]);

  // Handler for starting a new conversation
  const handleNewConversation = useCallback(() => {
    if (!project) return;

    // Reset auto-apply tracking for new session
    hasCompletedInitialAutoApplyRef.current = null;

    // Clear the current session
    aiStore.clearSession();

    // Disconnect and reconnect to create a new session
    aiStore.disconnect();

    // The useEffect above will reconnect automatically when panel reopens
    // For now, just manually trigger reconnect after a brief delay
    setTimeout(() => {
      const state = aiStore.getSnapshot();
      if (state.connectionState === 'disconnected') {
        // Build fresh context
        let workflowYAML: string | undefined = undefined;
        if (workflow && jobs.length > 0) {
          try {
            const workflowSpec = convertWorkflowStateToSpec(
              {
                id: workflow.id,
                name: workflow.name,
                jobs: jobs.map(job => ({
                  id: job.id,
                  name: job.name,
                  adaptor: job.adaptor,
                  body: job.body,
                })),
                triggers: triggers,
                edges: edges.map(edge => ({
                  id: edge.id,
                  condition_type: edge.condition_type || 'always',
                  enabled: edge.enabled !== false,
                  target_job_id: edge.target_job_id,
                  ...(edge.source_job_id && {
                    source_job_id: edge.source_job_id,
                  }),
                  ...(edge.source_trigger_id && {
                    source_trigger_id: edge.source_trigger_id,
                  }),
                  ...(edge.condition_label && {
                    condition_label: edge.condition_label,
                  }),
                  ...(edge.condition_expression && {
                    condition_expression: edge.condition_expression,
                  }),
                })),
                positions: positions,
              },
              false
            );
            workflowYAML = YAML.stringify(workflowSpec);
          } catch (error) {
            console.error('Failed to serialize workflow to YAML:', error);
          }
        }

        const context = {
          project_id: project.id,
          ...(workflow?.id && { workflow_id: workflow.id }),
          ...(workflowYAML && { code: workflowYAML }),
        };

        // Connect with NO session ID to force creation of new session
        aiStore.connect('workflow_template', context);
      }
    }, 100);
  }, [aiStore, workflow, jobs, triggers, edges, positions, project]);

  // Handler for loading an existing session
  const handleSessionSelect = useCallback(
    (selectedSessionId: string) => {
      if (!project) return;

      console.log('[AI Assistant] handleSessionSelect called', {
        selectedSessionId,
      });

      // Reset auto-apply tracking for new session
      hasCompletedInitialAutoApplyRef.current = null;

      // Clear messages immediately to prevent flash of old session's messages
      // The new session's messages will load when the channel reconnects
      aiStore._clearSession();

      // Disconnect current session
      aiStore.disconnect();

      // Wait for clean disconnect, then reconnect with selected session
      setTimeout(() => {
        const state = aiStore.getSnapshot();
        if (state.connectionState === 'disconnected') {
          // Use the CURRENT session type from store (not hardcoded)
          // The session type was set during mode initialization
          const currentSessionType = state.sessionType;

          if (!currentSessionType) {
            console.error(
              '[AI Assistant] No session type in store, cannot reconnect'
            );
            return;
          }

          // Build context based on session type
          let context: any;

          if (currentSessionType === 'workflow_template') {
            // Build workflow context
            let workflowYAML: string | undefined = undefined;
            if (workflow && jobs.length > 0) {
              try {
                const workflowSpec = convertWorkflowStateToSpec(
                  {
                    id: workflow.id,
                    name: workflow.name,
                    jobs: jobs.map(job => ({
                      id: job.id,
                      name: job.name,
                      adaptor: job.adaptor,
                      body: job.body,
                    })),
                    triggers: triggers,
                    edges: edges.map(edge => ({
                      id: edge.id,
                      condition_type: edge.condition_type || 'always',
                      enabled: edge.enabled !== false,
                      target_job_id: edge.target_job_id,
                      ...(edge.source_job_id && {
                        source_job_id: edge.source_job_id,
                      }),
                      ...(edge.source_trigger_id && {
                        source_trigger_id: edge.source_trigger_id,
                      }),
                      ...(edge.condition_label && {
                        condition_label: edge.condition_label,
                      }),
                      ...(edge.condition_expression && {
                        condition_expression: edge.condition_expression,
                      }),
                    })),
                    positions: positions,
                  },
                  false
                );
                workflowYAML = YAML.stringify(workflowSpec);
              } catch (error) {
                console.error('Failed to serialize workflow to YAML:', error);
              }
            }

            context = {
              project_id: project.id,
              ...(workflow?.id && { workflow_id: workflow.id }),
              ...(workflowYAML && { code: workflowYAML }),
            };
          } else {
            // Use existing job context from store
            context = state.jobCodeContext;
            if (!context) {
              console.error(
                '[AI Assistant] No job context in store, cannot reconnect'
              );
              return;
            }
          }

          console.log('[AI Assistant] Reconnecting with session', {
            selectedSessionId,
            sessionType: currentSessionType,
            context,
          });

          // Reconnect with the selected session ID using the CURRENT session type
          aiStore.connect(currentSessionType, context, selectedSessionId);
        }
      }, 100);
    },
    [aiStore, project, workflow, jobs, triggers, edges, positions]
  );

  // Handler for showing sessions list
  const handleShowSessions = useCallback(() => {
    console.log('[AI Assistant] handleShowSessions called');

    // Clear session ID from URL (both w-chat and j-chat)
    updateSearchParams({
      'w-chat': null,
      'j-chat': null,
    });

    // Clear the current session from store and disconnect from channel
    // This clears sessionId and messages, but keeps the context
    // so sessions list can still be loaded
    aiStore.clearSession();
    aiStore.disconnect();
  }, [updateSearchParams, aiStore]);

  // Wrapper function to send messages with context (workflow code or job options)
  const sendMessage = useCallback(
    (
      content: string,
      messageOptions?: { attach_code?: boolean; attach_logs?: boolean }
    ) => {
      const currentState = aiStore.getSnapshot();

      console.log('[AI Assistant] sendMessage called', {
        content: content.substring(0, 50) + '...',
        hasSession: !!currentState.sessionId,
        sessionType: currentState.sessionType,
        connectionState: currentState.connectionState,
      });

      // If no session, connect first with initial message
      if (!currentState.sessionId && aiMode) {
        const { mode, context } = aiMode;

        // Build context based on mode
        let finalContext = context;
        if (mode === 'workflow_template' && workflow && jobs.length > 0) {
          try {
            const workflowSpec = convertWorkflowStateToSpec(
              {
                id: workflow.id,
                name: workflow.name,
                jobs: jobs.map(job => ({
                  id: job.id,
                  name: job.name,
                  adaptor: job.adaptor,
                  body: job.body,
                })),
                triggers: triggers,
                edges: edges.map(edge => ({
                  id: edge.id,
                  condition_type: edge.condition_type || 'always',
                  enabled: edge.enabled !== false,
                  target_job_id: edge.target_job_id,
                  ...(edge.source_job_id && {
                    source_job_id: edge.source_job_id,
                  }),
                  ...(edge.source_trigger_id && {
                    source_trigger_id: edge.source_trigger_id,
                  }),
                  ...(edge.condition_label && {
                    condition_label: edge.condition_label,
                  }),
                  ...(edge.condition_expression && {
                    condition_expression: edge.condition_expression,
                  }),
                })),
                positions: positions,
              },
              false
            );
            const workflowYAML = YAML.stringify(workflowSpec);
            finalContext = { ...context, code: workflowYAML };
          } catch (error) {
            console.error('Failed to serialize workflow to YAML:', error);
          }
        }

        // Connect with initial message as content
        aiStore.connect(mode, { ...finalContext, content }, undefined);
        return;
      }

      // For workflow_template mode: include workflow YAML
      if (currentState.sessionType === 'workflow_template') {
        let workflowYAML: string | undefined = undefined;
        if (workflow && jobs.length > 0) {
          try {
            const workflowSpec = convertWorkflowStateToSpec(
              {
                id: workflow.id,
                name: workflow.name,
                jobs: jobs.map(job => ({
                  id: job.id,
                  name: job.name,
                  adaptor: job.adaptor,
                  body: job.body,
                })),
                triggers: triggers,
                edges: edges.map(edge => ({
                  id: edge.id,
                  condition_type: edge.condition_type || 'always',
                  enabled: edge.enabled !== false,
                  target_job_id: edge.target_job_id,
                  ...(edge.source_job_id && {
                    source_job_id: edge.source_job_id,
                  }),
                  ...(edge.source_trigger_id && {
                    source_trigger_id: edge.source_trigger_id,
                  }),
                  ...(edge.condition_label && {
                    condition_label: edge.condition_label,
                  }),
                  ...(edge.condition_expression && {
                    condition_expression: edge.condition_expression,
                  }),
                })),
                positions: positions,
              },
              false
            );
            workflowYAML = YAML.stringify(workflowSpec);
          } catch (error) {
            console.error('Failed to serialize workflow to YAML:', error);
          }
        }

        const options = workflowYAML ? { code: workflowYAML } : undefined;
        // Set loading state BEFORE sending the message
        aiStore.sendMessage(content);
        sendMessageToChannel(content, options);
      }
      // For job_code mode: pass attach_code and attach_logs options
      else if (currentState.sessionType === 'job_code' && messageOptions) {
        // Set loading state BEFORE sending the message
        aiStore.sendMessage(content);
        sendMessageToChannel(content, messageOptions);
      }
      // Fallback
      else {
        // Set loading state BEFORE sending the message
        aiStore.sendMessage(content);
        sendMessageToChannel(content);
      }
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
    ]
  );

  // State for tracking which message is being applied
  const [applyingMessageId, setApplyingMessageId] = useState<string | null>(
    null
  );

  // Track if we've completed initial auto-apply for the current session
  // This prevents the effect from running multiple times during reconnections
  // We track the session ID to know when we've already applied for this session
  const hasCompletedInitialAutoApplyRef = useRef<string | null>(null);

  // Get workflow actions for importing
  const { importWorkflow } = useWorkflowActions();

  // Handler for applying AI-generated workflow YAML to canvas
  const handleApplyWorkflow = useCallback(
    async (yaml: string, messageId: string) => {
      console.log('[AI Assistant] Applying workflow YAML to canvas', {
        messageId,
        yamlLength: yaml.length,
      });

      setApplyingMessageId(messageId);

      try {
        // Parse YAML to workflow spec
        const workflowSpec = parseWorkflowYAML(yaml);

        // Validate that IDs are strings or null, not objects
        // The AI sometimes generates nested ID objects which are invalid
        const validateIds = (spec: any) => {
          // Check jobs
          if (spec.jobs) {
            for (const [jobKey, job] of Object.entries(spec.jobs)) {
              const jobItem = job as any;
              if (
                jobItem.id &&
                typeof jobItem.id === 'object' &&
                jobItem.id !== null
              ) {
                throw new Error(
                  `Invalid ID format for job "${jobKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          // Check triggers
          if (spec.triggers) {
            for (const [triggerKey, trigger] of Object.entries(spec.triggers)) {
              const triggerItem = trigger as any;
              if (
                triggerItem.id &&
                typeof triggerItem.id === 'object' &&
                triggerItem.id !== null
              ) {
                throw new Error(
                  `Invalid ID format for trigger "${triggerKey}". IDs must be strings or null, not objects. ` +
                    `Please ask the AI to regenerate the workflow with proper ID format.`
                );
              }
            }
          }
          // Check edges
          if (spec.edges) {
            for (const [edgeKey, edge] of Object.entries(spec.edges)) {
              const edgeItem = edge as any;
              if (
                edgeItem.id &&
                typeof edgeItem.id === 'object' &&
                edgeItem.id !== null
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

        // CRITICAL: Clear job editor URL params BEFORE importing workflow
        // This must happen FIRST to prevent race conditions where React tries
        // to reconnect to AI Assistant with stale job IDs during the import
        updateSearchParams({
          job: null,
          panel: null,
          'j-chat': null, // Also clear any job-mode AI sessions
        });

        // If AI Assistant panel is open in job mode, close it BEFORE import
        // since the job no longer exists
        if (sessionType === 'job_code') {
          closeAIAssistantPanel();
        }

        // Convert spec to state
        const workflowState = convertWorkflowSpecToState(workflowSpec);

        // Apply to canvas using existing import functionality
        // This will replace all jobs/triggers/edges with new IDs
        importWorkflow(workflowState);

        console.log('[AI Assistant] Workflow applied successfully');
      } catch (error) {
        console.error('[AI Assistant] Failed to apply workflow:', error);

        notifications.alert({
          title: 'Failed to apply workflow',
          description:
            error instanceof Error ? error.message : 'Invalid workflow YAML',
        });
      } finally {
        setApplyingMessageId(null);
      }
    },
    [importWorkflow, updateSearchParams, sessionType, closeAIAssistantPanel]
  );

  // Auto-apply workflow YAML when AI generates it in workflow_template mode
  // This effect runs once per session when first loaded
  useEffect(() => {
    if (sessionType !== 'workflow_template' || !messages.length) return;

    // Check if we've already completed initial auto-apply for this session
    // This prevents re-applying during reconnections or message updates
    if (
      sessionId &&
      hasCompletedInitialAutoApplyRef.current === sessionId &&
      connectionState === 'connected'
    ) {
      console.log(
        '[AI Assistant] Skipping auto-apply - already completed for session:',
        sessionId
      );
      return;
    }

    // Find the latest assistant message with code (most recent successful response)
    const messagesWithCode = messages.filter(
      msg => msg.role === 'assistant' && msg.code && msg.status === 'success'
    );

    console.log('[AI Assistant] Auto-apply check:', {
      sessionId,
      connectionState,
      hasCompletedForSession: hasCompletedInitialAutoApplyRef.current,
      sessionWorkflowId: workflowTemplateContext?.workflow_id,
      currentWorkflowId: workflow?.id,
      totalMessages: messages.length,
      messagesWithCode: messagesWithCode.length,
      messageIds: messagesWithCode.map(m => ({
        id: m.id,
        hasCode: !!m.code,
        codeLength: m.code?.length,
      })),
    });

    const latestMessage = messagesWithCode.pop(); // Get the most recent one

    if (latestMessage?.code && connectionState === 'connected') {
      console.log(
        '[AI Assistant] Auto-applying workflow from message:',
        latestMessage.id,
        '(newest of',
        messagesWithCode.length + 1,
        'messages with code)'
      );

      // Mark that we've completed initial auto-apply for this session
      // This prevents duplicate applications during reconnections
      if (sessionId) {
        hasCompletedInitialAutoApplyRef.current = sessionId;
      }

      // Apply the workflow
      void handleApplyWorkflow(latestMessage.code, latestMessage.id);
    }
  }, [
    messages,
    sessionType,
    sessionId,
    connectionState,
    workflowTemplateContext,
    workflow,
    handleApplyWorkflow,
  ]);

  return (
    <div
      className="flex h-full flex-shrink-0"
      style={{
        width: isAIAssistantPanelOpen ? `${width}px` : '0px',
        transition: isResizing
          ? 'none'
          : 'width 0.4s cubic-bezier(0.4, 0, 0.2, 1)',
      }}
    >
      {isAIAssistantPanelOpen && (
        <>
          <div
            className="w-1 bg-gray-200 hover:bg-blue-400 transition-colors cursor-col-resize flex-shrink-0"
            onMouseDown={handleMouseDown}
          />
          <div className="flex-1 overflow-hidden">
            <AIAssistantPanel
              isOpen={isAIAssistantPanelOpen}
              onClose={closeAIAssistantPanel}
              onNewConversation={handleNewConversation}
              onSessionSelect={handleSessionSelect}
              onShowSessions={handleShowSessions}
              onSendMessage={sendMessage}
              sessionId={sessionId}
              messageCount={messages.length}
              isLoading={isLoading}
              isResizable={true}
              store={aiStore}
              sessionType={sessionType}
              loadSessions={loadSessions}
            >
              <MessageList
                messages={messages}
                isLoading={isLoading}
                onApplyWorkflow={
                  sessionType === 'workflow_template'
                    ? handleApplyWorkflow
                    : undefined
                }
                applyingMessageId={applyingMessageId}
                showAddButtons={sessionType === 'job_code'}
              />
            </AIAssistantPanel>
          </div>
        </>
      )}
    </div>
  );
}

/**
 * BreadcrumbContent Component
 *
 * Internal component that renders breadcrumbs with store-first, props-fallback pattern.
 * This component must be inside StoreProvider to access sessionContextStore.
 *
 * Migration Strategy:
 * - Tries to get project data from sessionContextStore first
 * - Falls back to props if store data not yet available
 * - This ensures breadcrumbs work during migration and server-side rendering
 * - Eventually props can be removed when all project data flows through store
 */
interface BreadcrumbContentProps {
  workflowId: string;
  workflowName: string;
  projectIdFallback?: string;
  projectNameFallback?: string;
  projectEnvFallback?: string;
}

function BreadcrumbContent({
  workflowId,
  workflowName,
  projectIdFallback,
  projectNameFallback,
  projectEnvFallback,
}: BreadcrumbContentProps) {
  // Get project from store (may be null if not yet loaded)
  const projectFromStore = useProject();

  // Get workflow from store to read the current name
  const workflowFromStore = useWorkflowState(state => state.workflow);
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  // Get run panel state for Header tooltip logic
  const isRunPanelOpen = useIsRunPanelOpen();

  // Detect IDE mode
  const { searchParams } = useURLState();
  const isIDEOpen = searchParams.get('panel') === 'editor';

  // Store-first with props-fallback pattern
  // This ensures breadcrumbs work during:
  // 1. Initial server-side render (uses props)
  // 2. Store hydration period (uses props)
  // 3. Full collaborative mode (uses store)
  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;
  const projectEnv = projectFromStore?.env ?? projectEnvFallback;
  const currentWorkflowName = workflowFromStore?.name ?? workflowName;

  // Use shared version selection handler (destroys Y.Doc before switching)
  const handleVersionSelect = useVersionSelect();

  // Build breadcrumbs for Canvas mode only (IDE has its own breadcrumbs in FullScreenIDE)
  const breadcrumbElements = useMemo(() => {
    // Canvas mode: Projects > Project > Workflows > Workflow (with version dropdown)
    return [
      <BreadcrumbLink href="/projects" key="projects">
        Projects
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="project">
        {projectName}
      </BreadcrumbLink>,
      <BreadcrumbLink href={`/projects/${projectId}/w`} key="workflows">
        Workflows
      </BreadcrumbLink>,
      <div key="workflow" className="flex items-center gap-2">
        <BreadcrumbText>{currentWorkflowName}</BreadcrumbText>
        <div className="flex items-center gap-1.5">
          <VersionDropdown
            currentVersion={workflowFromStore?.lock_version ?? null}
            latestVersion={latestSnapshotLockVersion}
            onVersionSelect={handleVersionSelect}
          />
          {projectEnv && (
            <div
              id="canvas-project-env-container"
              className="flex items-middle text-sm font-normal"
            >
              <span
                id="canvas-project-env"
                className="inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium bg-primary-100 text-primary-800"
                title={`Project environment is ${projectEnv}`}
              >
                {projectEnv}
              </span>
            </div>
          )}
        </div>
      </div>,
    ];
  }, [
    projectId,
    projectName,
    projectEnv,
    currentWorkflowName,
    workflowId,
    workflowFromStore?.lock_version,
    latestSnapshotLockVersion,
    handleVersionSelect,
  ]);

  return (
    <Header
      key="canvas-header"
      {...(projectId !== undefined && { projectId })}
      workflowId={workflowId}
      isRunPanelOpen={isRunPanelOpen}
      isIDEOpen={isIDEOpen}
    >
      {breadcrumbElements}
    </Header>
  );
}

export const CollaborativeEditor: WithActionProps<
  CollaborativeEditorDataProps
> = props => {
  // Extract data from props (ReactComponent hook passes data attributes as props)
  const workflowId = props['data-workflow-id'];
  const workflowName = props['data-workflow-name'];
  // Migration: Props are now fallbacks, sessionContextStore is primary source
  const projectId = props['data-project-id'];
  const projectName = props['data-project-name'];
  const projectEnv = props['data-project-env'];
  const rootProjectId = props['data-root-project-id'] ?? null;
  const rootProjectName = props['data-root-project-name'] ?? null;
  const isNewWorkflow = props['data-is-new-workflow'] === 'true';

  // Extract LiveView actions from props
  const liveViewActions = {
    pushEvent: props.pushEvent,
    pushEventTo: props.pushEventTo,
    handleEvent: props.handleEvent,
    navigate: props.navigate,
  };

  return (
    <KeyboardProvider>
      <div
        className="collaborative-editor h-full flex flex-col relative"
        data-testid="collaborative-editor"
      >
        <SocketProvider>
          <SessionProvider
            workflowId={workflowId}
            projectId={projectId}
            isNewWorkflow={isNewWorkflow}
          >
            <StoreProvider>
              <LiveViewActionsProvider actions={liveViewActions}>
                <VersionDebugLogger />
                <Toaster />
                {/* Main content area - pushed by AI panel */}
                <div className="flex-1 min-h-0 h-full overflow-hidden flex flex-col">
                  {/* Breadcrumb bar at top */}
                  <BreadcrumbContent
                    workflowId={workflowId}
                    workflowName={workflowName}
                    {...(projectId !== undefined && {
                      projectIdFallback: projectId,
                    })}
                    {...(projectName !== undefined && {
                      projectNameFallback: projectName,
                    })}
                    {...(projectEnv !== undefined && {
                      projectEnvFallback: projectEnv,
                    })}
                    {...(rootProjectId !== null && {
                      rootProjectIdFallback: rootProjectId,
                    })}
                    {...(rootProjectName !== null && {
                      rootProjectNameFallback: rootProjectName,
                    })}
                  />
                  {/* Content area below breadcrumbs */}
                  <div className="flex-1 min-h-0 h-full overflow-hidden">
                    <LoadingBoundary>
                      <div className="h-full w-full">
                        <WorkflowEditor
                          {...(rootProjectId !== null && {
                            parentProjectId: rootProjectId,
                          })}
                          {...(rootProjectName !== null && {
                            parentProjectName: rootProjectName,
                          })}
                        />
                      </div>
                    </LoadingBoundary>
                  </div>
                </div>
                {/* AI Assistant Panel - at root level, pushes everything */}
                <AIAssistantPanelWrapper />
              </LiveViewActionsProvider>
            </StoreProvider>
          </SessionProvider>
        </SocketProvider>
      </div>
    </KeyboardProvider>
  );
};
