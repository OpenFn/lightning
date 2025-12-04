/**
 * useAISession Hook
 *
 * Manages AI Assistant channel lifecycle with the registry pattern.
 * Replaces the giant useEffect in AIAssistantPanelWrapper.
 *
 * ## What This Hook Does
 *
 * 1. **Detects context changes** - Mode switches (job ↔ workflow), job switches
 * 2. **Manages channel subscriptions** - Subscribes/unsubscribes via registry
 * 3. **Handles URL session loading** - Loads session from URL params
 * 4. **Initializes context** - Sets up job or workflow context
 *
 * ## Benefits Over Previous Pattern
 *
 * - No timing workarounds (setTimeout)
 * - No manual connect/disconnect orchestration
 * - No race conditions during mode switching
 * - Declarative: "I need this session" not "connect then disconnect then connect again"
 *
 * ## Usage
 *
 * ```typescript
 * // In AIAssistantPanelWrapper
 * useAISession({
 *   isOpen: isAIAssistantPanelOpen,
 *   aiMode,
 *   sessionIdFromURL,
 *   workflowData: { workflow, jobs, triggers, edges, positions }
 * });
 * ```
 */

import { useEffect, useId, useRef } from 'react';

import _logger from '#/utils/logger';

import type {
  JobCodeContext,
  SessionType,
  WorkflowTemplateContext,
} from '../types/ai-assistant';
import {
  serializeWorkflowToYAML,
  type SerializableWorkflow,
} from '../utils/workflowSerialization';

import { useAIStore } from './useAIAssistant';
import {
  buildChannelTopic,
  useAIChannelRegistry,
} from './useAIChannelRegistry';

const logger = _logger.ns('useAISession').seal();

interface WorkflowData {
  workflow: { id: string; name: string } | null;
  jobs: unknown[];
  triggers: unknown[];
  edges: unknown[];
  positions: unknown;
}

interface AIMode {
  mode: SessionType;
  context: JobCodeContext | WorkflowTemplateContext;
}

interface UseAISessionOptions {
  isOpen: boolean;
  aiMode: AIMode | null;
  sessionIdFromURL: string | null;
  workflowData?: WorkflowData;
  onSessionIdChange?: (sessionId: string | null) => void;
}

/**
 * Manages AI session channel lifecycle with registry pattern
 */
export const useAISession = ({
  isOpen,
  aiMode,
  sessionIdFromURL,
  workflowData,
  onSessionIdChange,
}: UseAISessionOptions) => {
  const { registry } = useAIChannelRegistry();
  const aiStore = useAIStore();
  const subscriberId = useId();

  // Extract stable values from aiMode for dependency array
  const mode = aiMode?.mode ?? null;
  const jobId =
    aiMode?.mode === 'job_code'
      ? (aiMode.context as JobCodeContext).job_id
      : null;

  // Track what we're currently subscribed to and previous mode/job for change detection
  const currentSubscriptionRef = useRef<string | null>(null);
  const prevModeRef = useRef<SessionType | null>(null);
  const prevJobIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (!isOpen || !aiMode || !registry) {
      // Panel closed - unsubscribe immediately (no delay)
      if (currentSubscriptionRef.current && registry) {
        registry.unsubscribeImmediate(
          currentSubscriptionRef.current,
          subscriberId
        );
        currentSubscriptionRef.current = null;
      }
      // Reset refs
      prevModeRef.current = null;
      prevJobIdRef.current = null;
      return;
    }

    const { mode, context } = aiMode;
    const state = aiStore.getSnapshot();
    const currentJobId =
      mode === 'job_code' ? (context as JobCodeContext).job_id : null;

    // Detect if mode or job changed
    const modeChanged =
      prevModeRef.current !== null && prevModeRef.current !== mode;
    const jobChanged =
      prevJobIdRef.current !== null && prevJobIdRef.current !== currentJobId;

    // Update tracking refs
    prevModeRef.current = mode;
    prevJobIdRef.current = currentJobId;

    // Clear session/list when mode or job changes
    if (modeChanged || jobChanged) {
      aiStore._clearSession();
      aiStore._clearSessionList();
      aiStore._setConnectionState('disconnected');
      onSessionIdChange?.(null);
    }

    // Build the topic we want to subscribe to
    const desiredTopic = sessionIdFromURL
      ? buildChannelTopic(mode, sessionIdFromURL)
      : null;

    // If we're already subscribed to the desired topic, nothing to do
    if (desiredTopic && currentSubscriptionRef.current === desiredTopic) {
      return;
    }

    // Unsubscribe from old topic ONLY if it's different from desired topic
    if (
      currentSubscriptionRef.current &&
      currentSubscriptionRef.current !== desiredTopic
    ) {
      // Always use immediate cleanup to ensure fresh channel joins with current data.
      // This eliminates stale-channel bugs and simplifies state management.
      registry.unsubscribeImmediate(
        currentSubscriptionRef.current,
        subscriberId
      );
      currentSubscriptionRef.current = null;
    }

    // If no session to subscribe to, initialize context for session list loading
    if (!sessionIdFromURL) {
      // Initialize context when mode changes OR when job changes within job_code mode
      // The jobChanged check ensures context is updated when switching between jobs
      const needsContextUpdate =
        state.sessionType !== mode || modeChanged || jobChanged;

      if (needsContextUpdate) {
        aiStore._initializeContext(mode, context);
      }
      return;
    }

    // Handle "new" session - only subscribe if we have content
    if (sessionIdFromURL === 'new') {
      const topic = buildChannelTopic(mode, null);
      const storeContext =
        state.jobCodeContext || state.workflowTemplateContext;

      if (storeContext && 'content' in storeContext && storeContext.content) {
        registry.subscribe(topic, subscriberId, storeContext);
        currentSubscriptionRef.current = topic;
      } else {
        logger.debug('Waiting for content before joining new session');
      }
      return;
    }

    // Subscribe to the actual session
    const topic = desiredTopic!; // We know it exists here

    // Mark this topic as pending immediately to prevent race conditions
    // This ensures fast session switching doesn't lose track of pending subscriptions
    currentSubscriptionRef.current = topic;

    // Build context with workflow YAML if needed
    if (
      mode === 'workflow_template' &&
      workflowData?.workflow &&
      workflowData.jobs.length > 0
    ) {
      const { workflow, jobs, triggers, edges, positions } = workflowData;

      // Synchronous workflow serialization - static import eliminates race conditions
      // that occurred with dynamic imports during rapid session switching
      const workflowForSerialization: SerializableWorkflow = {
        id: workflow.id,
        name: workflow.name,
        jobs: jobs.map((job: unknown) => {
          const j = job as Record<string, unknown>;
          return {
            id: String(j['id']),
            name: String(j['name']),
            adaptor: String(j['adaptor']),
            body: String(j['body']),
          };
        }),
        triggers,
        edges,
        positions,
      };

      const workflowYAML = serializeWorkflowToYAML(workflowForSerialization);

      const finalContext = workflowYAML
        ? ({ ...context, code: workflowYAML } as WorkflowTemplateContext)
        : context;

      // Registry handles connection and sets session when join succeeds
      registry.subscribe(topic, subscriberId, finalContext);
    } else {
      // No workflow serialization needed - registry handles connection
      registry.subscribe(topic, subscriberId, context);
    }
  }, [
    isOpen,
    mode, // Stable primitive
    jobId, // Stable primitive
    sessionIdFromURL,
    workflowData?.workflow?.id,
    aiStore,
    registry,
    subscriberId,
    onSessionIdChange,
  ]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (currentSubscriptionRef.current && registry) {
        registry.unsubscribe(currentSubscriptionRef.current, subscriberId);
      }
    };
  }, [registry, subscriberId]);
};
