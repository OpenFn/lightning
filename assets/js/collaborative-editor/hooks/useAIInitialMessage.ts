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
import {
  prepareWorkflowForSerialization,
  serializeWorkflowToYAML,
} from '../utils/workflowSerialization';

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
  /**
   * Race condition prevention:
   * - initialMessageSentRef ensures we only send once per initial message
   * - The flag is set to true immediately when we decide to send (line 86)
   * - The flag resets when initialMessage is cleared OR panel closes (line 135-137)
   * - This handles rapid state changes safely since React batches updates
   *   and the ref check happens synchronously before any async operations
   */
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
