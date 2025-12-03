/**
 * useAIInitialMessage - Handles auto-sending initial messages to AI Assistant
 *
 * When users trigger AI Assistant from template search (e.g., "Build your workflow using AI"),
 * the initial message is stored in UI state. This hook:
 * - Detects when an initial message is present
 * - Prepares the workflow context
 * - Initiates the AI connection with the message
 * - Clears the initial message after sending
 */

import { useEffect, useRef } from 'react';

import type { AIAssistantStoreInstance } from '../stores/createAIAssistantStore';
import type {
  ConnectionState,
  JobCodeContext,
  WorkflowTemplateContext,
} from '../types/ai-assistant';
import { serializeWorkflowToYAML } from '../utils/workflowSerialization';

import type { AIModeResult } from './useAIMode';

interface WorkflowData {
  workflow: { id: string; name: string } | null;
  jobs: unknown[];
  triggers: unknown[];
  edges: unknown[];
  positions: unknown;
}

interface UseAIInitialMessageOptions {
  initialMessage: string | null;
  aiMode: AIModeResult | null;
  sessionId: string | null;
  connectionState: ConnectionState;
  isAIAssistantPanelOpen: boolean;
  aiStore: AIAssistantStoreInstance;
  workflowData: WorkflowData;
  updateSearchParams: (params: Record<string, string | null>) => void;
  clearAIAssistantInitialMessage: () => void;
}

/**
 * Helper function to prepare workflow data for serialization.
 * Transforms workflow store state into the format expected by serializeWorkflowToYAML.
 */
function prepareWorkflowForSerialization(
  workflow: { id: string; name: string } | null,
  jobs: unknown[],
  triggers: unknown[],
  edges: unknown[],
  positions: unknown
): import('../utils/workflowSerialization').SerializableWorkflow | null {
  if (!workflow || jobs.length === 0) {
    return null;
  }

  return {
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
    edges: edges.map((edge: unknown) => {
      const e = edge as Record<string, unknown>;
      const conditionType = e['condition_type'];
      const result: Record<string, unknown> = {
        id: String(e['id']),
        condition_type:
          conditionType && typeof conditionType === 'string'
            ? conditionType
            : 'always',
        enabled: e['enabled'] !== false,
        target_job_id: String(e['target_job_id']),
      };

      const sourceJobId = e['source_job_id'];
      if (sourceJobId && typeof sourceJobId === 'string') {
        result['source_job_id'] = sourceJobId;
      }
      const sourceTriggerId = e['source_trigger_id'];
      if (sourceTriggerId && typeof sourceTriggerId === 'string') {
        result['source_trigger_id'] = sourceTriggerId;
      }
      const conditionLabel = e['condition_label'];
      if (conditionLabel && typeof conditionLabel === 'string') {
        result['condition_label'] = conditionLabel;
      }
      const conditionExpression = e['condition_expression'];
      if (conditionExpression && typeof conditionExpression === 'string') {
        result['condition_expression'] = conditionExpression;
      }

      return result;
    }),
    positions,
  } as import('../utils/workflowSerialization').SerializableWorkflow;
}

/**
 * Hook that handles auto-sending initial messages to the AI Assistant.
 *
 * This hook watches for an initial message (typically set when user clicks
 * "Build your workflow using AI" from template search), and automatically
 * initiates an AI session with that message.
 *
 * Conditions for sending:
 * - Initial message is present
 * - AI mode is set
 * - No existing session
 * - Not currently connected
 * - Panel is open
 * - Message hasn't been sent yet (tracked via ref)
 */
export function useAIInitialMessage({
  initialMessage,
  aiMode,
  sessionId,
  connectionState,
  isAIAssistantPanelOpen,
  aiStore,
  workflowData,
  updateSearchParams,
  clearAIAssistantInitialMessage,
}: UseAIInitialMessageOptions): void {
  const initialMessageSentRef = useRef(false);

  useEffect(() => {
    // Check all conditions for sending the initial message
    const shouldSendMessage =
      initialMessage &&
      aiMode &&
      !sessionId &&
      connectionState === 'disconnected' &&
      !initialMessageSentRef.current &&
      isAIAssistantPanelOpen;

    if (shouldSendMessage) {
      initialMessageSentRef.current = true;

      // Prepare context with initial message
      const { mode, context } = aiMode;
      const { workflow, jobs, triggers, edges, positions } = workflowData;

      let finalContext: JobCodeContext | WorkflowTemplateContext = {
        ...context,
        content: initialMessage,
      };

      // Add workflow YAML if in workflow template mode
      if (mode === 'workflow_template') {
        const serializedWorkflow = prepareWorkflowForSerialization(
          workflow,
          jobs,
          triggers,
          edges,
          positions
        );
        if (serializedWorkflow) {
          const workflowYAML = serializeWorkflowToYAML(serializedWorkflow);
          if (workflowYAML) {
            finalContext = {
              ...(finalContext as WorkflowTemplateContext),
              code: workflowYAML,
            };
          }
        }
      }

      // Initialize store with context including content
      aiStore.connect(mode, finalContext);

      // Update URL to trigger subscription to "new" channel
      if (mode === 'workflow_template') {
        updateSearchParams({ 'w-chat': 'new', 'j-chat': null });
      } else {
        updateSearchParams({ 'j-chat': 'new', 'w-chat': null });
      }

      // Mark message as sending
      aiStore.setMessageSending();

      // Clear the initial message from UI state
      clearAIAssistantInitialMessage();
    }

    // Reset flag when initial message is cleared or panel closes
    if (!initialMessage || !isAIAssistantPanelOpen) {
      initialMessageSentRef.current = false;
    }
  }, [
    initialMessage,
    aiMode,
    sessionId,
    connectionState,
    isAIAssistantPanelOpen,
    aiStore,
    workflowData,
    updateSearchParams,
    clearAIAssistantInitialMessage,
  ]);
}
