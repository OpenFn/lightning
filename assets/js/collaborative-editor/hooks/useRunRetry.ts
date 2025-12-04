import { useCallback, useMemo, useRef, useState } from 'react';

import _logger from '#/utils/logger';

import { useURLState } from '#/react/lib/use-url-state';
import * as dataclipApi from '../api/dataclips';
import type { Dataclip } from '../api/dataclips';
import { getCsrfToken } from '../lib/csrf';
import { notifications } from '../lib/notifications';
import type { Workflow } from '../types/workflow';
import { findFirstJobFromTrigger } from '../utils/workflowGraph';

import { useActiveRun } from './useHistory';

const logger = _logger.ns('useRunRetry').seal();

/**
 * Final states for a run (matches Lightning.Run.final_states/0)
 * - success: Run completed successfully
 * - failed: Run failed but error was caught
 * - crashed: Run crashed unexpectedly
 * - cancelled: User cancelled the run
 * - killed: Run was forcibly terminated
 * - exception: Unhandled exception occurred
 * - lost: Run state unknown/lost connection
 */
const FINAL_RUN_STATES = [
  'success',
  'failed',
  'crashed',
  'cancelled',
  'killed',
  'exception',
  'lost',
];

function isFinalState(state: string): boolean {
  return FINAL_RUN_STATES.includes(state);
}

function isProcessing(state: string | null): boolean {
  return state !== null && !isFinalState(state);
}

export interface UseRunRetryOptions {
  projectId: string;
  workflowId: string;
  runContext: {
    type: 'job' | 'trigger';
    id: string;
  };
  selectedTab: 'empty' | 'custom' | 'existing';
  selectedDataclip: Dataclip | null;
  customBody: string;
  canRunWorkflow: boolean;
  workflowRunTooltipMessage: string;
  saveWorkflow: (options?: {
    silent?: boolean;
  }) => Promise<{ saved_at?: string; lock_version?: number } | null>;
  onRunSubmitted: ((runId: string, dataclip?: Dataclip) => void) | undefined;
  edgeId: string | null;
  workflowEdges?: Workflow.Edge[];
}

export interface UseRunRetryReturn {
  handleRun: () => Promise<void>;
  handleRetry: () => Promise<void>;
  isSubmitting: boolean;
  isRetryable: boolean;
  runIsProcessing: boolean;
  canRun: boolean;
}

/**
 * Custom hook for managing run/retry functionality
 *
 * Handles:
 * - Running workflows with different input types (empty, custom, existing dataclip)
 * - Retrying existing runs with the same input
 * - WebSocket connection for real-time run state updates
 * - Permission checks and validation
 * - Success/error notifications
 *
 * @example
 * const { handleRun, handleRetry, isRetryable, isSubmitting } = useRunRetry({
 *   projectId,
 *   workflowId,
 *   runContext: { type: 'job', id: jobId },
 *   selectedDataclip,
 *   canRunWorkflow,
 *   saveWorkflow,
 * });
 */
export function useRunRetry({
  projectId,
  workflowId,
  runContext,
  selectedTab,
  selectedDataclip,
  customBody,
  canRunWorkflow,
  workflowRunTooltipMessage,
  saveWorkflow,
  onRunSubmitted,
  edgeId,
  workflowEdges = [],
}: UseRunRetryOptions): UseRunRetryReturn {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const isRetryingRef = useRef(false);

  // Retry state tracking via HistoryStore (WebSocket updates)
  // Note: Connection management is handled by the parent component (FullScreenIDE or ManualRunPanel)
  // This hook only reads the current run state from HistoryStore
  const { params } = useURLState();
  const followedRunId = params.run ?? null; // 'run' param is run ID
  const currentRun = useActiveRun(); // Real-time from WebSocket

  // Get step for current context from followed run (from real-time RunStore)
  // For jobs: use the job's step directly
  // For triggers: find the first job connected to the trigger and use its step
  // This matches classical editor behavior (WorkflowController.get_selected_job)
  const dataclipJobId = useMemo(() => {
    if (runContext.type === 'job') {
      return runContext.id;
    }

    // For triggers: find the connected job (matching classical editor behavior)
    // This allows retry to work when a trigger is selected
    return findFirstJobFromTrigger(workflowEdges, runContext.id);
  }, [runContext, workflowEdges]);

  const followedRunStep = useMemo(() => {
    if (!currentRun || !dataclipJobId) return null;
    return currentRun.steps.find(s => s.job_id === dataclipJobId) || null;
  }, [currentRun, dataclipJobId]);

  // Check if the followed run is currently processing (from real-time WebSocket)
  const runIsProcessing = currentRun ? isProcessing(currentRun.state) : false;

  const isRetryable = useMemo(() => {
    if (!followedRunId || !followedRunStep || !selectedDataclip) {
      return false;
    }

    return (
      selectedDataclip.wiped_at === null &&
      followedRunStep.input_dataclip_id === selectedDataclip.id
    );
  }, [followedRunId, followedRunStep, selectedDataclip]);

  const isValidCustomBody = useMemo(() => {
    if (!customBody || !customBody.trim()) {
      return false;
    }
    try {
      const parsed = JSON.parse(customBody);
      return (
        parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed)
      );
    } catch {
      return false;
    }
  }, [customBody]);

  const hasValidInput =
    selectedTab === 'empty' ||
    (selectedTab === 'existing' && !!selectedDataclip) ||
    (selectedTab === 'custom' && isValidCustomBody);

  const canRun = !edgeId && canRunWorkflow && hasValidInput;

  /**
   * Handle run - Create new work order with selected input
   */
  const handleRun = useCallback(async () => {
    const contextId = runContext.id;
    if (!contextId) {
      logger.error('No context ID available');
      return;
    }

    // Check workflow-level permissions before running
    if (!canRunWorkflow) {
      notifications.alert({
        title: 'Cannot run workflow',
        description: workflowRunTooltipMessage,
      });
      return;
    }

    setIsSubmitting(true);
    try {
      // Save workflow first (silently - user action is "run", not "save")
      await saveWorkflow({ silent: true });

      const params: dataclipApi.ManualRunParams = {
        workflowId,
        projectId,
      };

      // Add job or trigger ID
      if (runContext.type === 'job') {
        params.jobId = contextId;
      } else {
        params.triggerId = contextId;
      }

      // Add dataclip or custom body based on selected tab
      if (selectedTab === 'existing' && selectedDataclip) {
        params.dataclipId = selectedDataclip.id;
      } else if (selectedTab === 'custom') {
        params.customBody = customBody;
      }
      // For 'empty' tab, no dataclip or body needed

      const response = await dataclipApi.submitManualRun(params);

      notifications.success({
        title: 'Run started',
        description: 'Saved latest changes and created new work order',
      });

      // Invoke callback with run_id and dataclip (if created from custom body)
      if (onRunSubmitted) {
        onRunSubmitted(response.data.run_id, response.data.dataclip);
      } else {
        // Fallback: navigate away if no callback (for standalone mode)
        window.location.href = `/projects/${projectId}/runs/${response.data.run_id}`;
      }

      setIsSubmitting(false);
    } catch (error) {
      logger.error('Failed to submit run:', error);
      notifications.alert({
        title: 'Failed to submit run',
        description:
          error instanceof Error ? error.message : 'An unknown error occurred',
      });
      setIsSubmitting(false);
    }
  }, [
    workflowId,
    projectId,
    runContext,
    selectedTab,
    selectedDataclip,
    customBody,
    saveWorkflow,
    canRunWorkflow,
    workflowRunTooltipMessage,
    onRunSubmitted,
  ]);

  /**
   * Handle retry - Retry existing run with same input
   */
  const handleRetry = useCallback(async () => {
    // Guard against double-calls (e.g., from rapid keyboard shortcuts)
    if (isRetryingRef.current) {
      return;
    }
    isRetryingRef.current = true;

    if (!followedRunId || !followedRunStep) {
      logger.error('Cannot retry: missing run or step data');
      isRetryingRef.current = false;
      return;
    }

    if (!canRunWorkflow) {
      notifications.alert({
        title: 'Cannot run workflow',
        description: workflowRunTooltipMessage,
      });
      isRetryingRef.current = false;
      return;
    }

    setIsSubmitting(true);
    try {
      // Save workflow first (silently to avoid double notifications)
      await saveWorkflow({ silent: true });

      // Call retry endpoint
      const retryUrl = `/projects/${projectId}/runs/${followedRunId}/retry`;
      const retryBody = { step_id: followedRunStep.id };

      const csrfToken = getCsrfToken();
      const response = await fetch(retryUrl, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken || '',
        },
        body: JSON.stringify(retryBody),
      });

      if (!response.ok) {
        const error = (await response.json()) as { error?: string };
        throw new Error(error.error || 'Failed to retry run');
      }

      const result = (await response.json()) as {
        data: { run_id: string; work_order_id?: string };
      };

      notifications.success({
        title: 'Retry started',
        description: 'Saved latest changes and re-running with previous input',
      });

      // Invoke callback with new run_id
      if (onRunSubmitted) {
        onRunSubmitted(result.data.run_id);
        // Reset submitting state after callback (component stays mounted)
        setIsSubmitting(false);
        isRetryingRef.current = false;
      } else {
        // Fallback: navigate to new run (component will unmount)
        window.location.href = `/projects/${projectId}/runs/${result.data.run_id}`;
        // No need to reset ref as component will unmount
      }
    } catch (error) {
      logger.error('Failed to retry run:', error);
      notifications.alert({
        title: 'Retry failed',
        description: error instanceof Error ? error.message : 'Unknown error',
      });
      setIsSubmitting(false);
      isRetryingRef.current = false;
    }
  }, [
    followedRunId,
    followedRunStep,
    canRunWorkflow,
    workflowRunTooltipMessage,
    saveWorkflow,
    projectId,
    onRunSubmitted,
  ]);

  return {
    handleRun,
    handleRetry,
    isSubmitting,
    isRetryable,
    runIsProcessing,
    canRun,
  };
}
