/**
 * # Workflow Run History Types
 *
 * Type definitions for workflow execution history (work orders and runs).
 * These types match the actual API response structure from the backend.
 *
 * ## Usage Example:
 * ```typescript
 * const history: WorkflowRunHistory[] = [
 *   {
 *     id: "e2107d46-cf29-4930-b11b-cbcfcf83549d",
 *     version: 29,
 *     state: "success",
 *     runs: [...],
 *     last_activity: "2025-10-23T21:00:02.293382Z",
 *     selected: false,
 *   }
 * ];
 * ```
 */

/**
 * Represents a work order with its associated runs
 */
export interface WorkflowRunHistory {
  /** Work order ID (UUID) */
  id: string;
  /** Workflow snapshot version this work order executed against */
  version: number;
  /** Overall work order state (highest priority state from runs) */
  state: RunState;
  /** Array of runs for this work order */
  runs: Run[];
  /** ISO timestamp of last activity (most recent run update) */
  last_activity: string;
  /** UI state for selection (not from backend) */
  selected: boolean;
}

/**
 * Represents an individual run within a work order
 */
export interface Run {
  /** Run ID (UUID) */
  id: string;
  /** Current state of the run */
  state: RunState;
  /** ISO timestamp when run started */
  started_at: string;
  /** ISO timestamp when run finished (null if still running) */
  finished_at: string | null;
  /** Error type if failed (null if successful) */
  error_type: string | null;
  /** UI state for selection (not from backend) */
  selected: boolean;
}

/**
 * All possible states for runs and work orders
 */
export type RunState =
  | "available"
  | "claimed"
  | "started"
  | "success"
  | "failed"
  | "crashed"
  | "cancelled"
  | "killed"
  | "exception"
  | "lost";
