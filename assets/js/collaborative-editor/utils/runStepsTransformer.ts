/**
 * # Run Steps Transformer
 *
 * Transforms backend run steps data into frontend RunInfo format.
 *
 * ## Purpose:
 * The backend provides step data in a structure optimized for the
 * database schema, while the frontend visualization code expects
 * RunInfo format. This utility bridges the gap.
 *
 * ## Key Transformations:
 * - Maps backend exit_reason values to frontend types
 * - Converts null values to empty strings for consistency
 * - Adds computed fields (startNode, startBy)
 * - Handles in-progress steps (null exit_reason)
 *
 * ## Exit Reason Mapping:
 * - success → success
 * - fail → fail
 * - crash/exception/lost → crash
 * - null → null (in progress)
 * - unknown states → fail (defensive)
 */

import type { RunInfo, RunStep } from '#/workflow-store/store';

import type { RunStepsData, Step } from '../types/history';

/**
 * Transform backend run steps data to frontend RunInfo format
 * expected by fromWorkflow() utility.
 *
 * @param runStepsData - Backend run steps data from channel
 * @param _workflowId - Current workflow ID (not used currently but
 *                      available for future use)
 * @returns RunInfo object ready for fromWorkflow()
 */
export function transformToRunInfo(
  runStepsData: RunStepsData,
  _workflowId: string
): RunInfo {
  const steps: RunStep[] = runStepsData.steps.map((step: Step) => ({
    id: step.id,
    job_id: step.job_id,
    error_type: step.error_type ?? null,
    exit_reason: mapExitReason(step.exit_reason),
    started_at: step.started_at || '',
    finished_at: step.finished_at || '',
    input_dataclip_id: step.input_dataclip_id,
    startNode: step.job_id === runStepsData.metadata.starting_job_id,
    startBy: runStepsData.metadata.created_by_email || 'unknown',
  }));

  return {
    start_from:
      runStepsData.metadata.starting_job_id ||
      runStepsData.metadata.starting_trigger_id,
    inserted_at: runStepsData.metadata.inserted_at,
    isTrigger: !!runStepsData.metadata.starting_trigger_id,
    steps,
    run_by: runStepsData.metadata.created_by_email,
  };
}

/**
 * Map backend exit_reason to frontend exit_reason type.
 * Handle null (in-progress) and map states.
 *
 * @param exitReason - Backend exit_reason value
 * @returns Frontend exit_reason type
 */
function mapExitReason(
  exitReason: string | null
): 'fail' | 'success' | 'crash' | null {
  if (!exitReason) return null; // Step not finished yet

  switch (exitReason) {
    case 'success':
      return 'success';
    case 'fail':
      return 'fail';
    case 'crash':
    case 'exception':
    case 'lost':
      return 'crash';
    default:
      // Treat unknown states as failures (defensive)
      return 'fail';
  }
}

/**
 * Create a minimal empty RunInfo for when no run is selected.
 *
 * @returns Empty RunInfo object
 */
export function createEmptyRunInfo(): RunInfo {
  return {
    start_from: null,
    inserted_at: '',
    isTrigger: false,
    steps: [],
    run_by: null,
  };
}
