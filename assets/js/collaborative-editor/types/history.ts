import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as z from 'zod';

import { isoDateTimeSchema, uuidSchema } from './common';

/**
 * Zod schema for a single RunSummary (lightweight run data in work orders)
 * Matches the backend Run structure from WorkOrders
 */
export const RunSummarySchema = z.object({
  id: uuidSchema,
  state: z.enum([
    'available',
    'claimed',
    'started',
    'success',
    'failed',
    'killed',
    'exception',
    'crashed',
    'cancelled',
    'lost',
  ]),
  error_type: z.string().nullable(),
  started_at: isoDateTimeSchema.nullable(),
  finished_at: isoDateTimeSchema.nullable(),
});

/**
 * Zod schema for a single WorkOrder
 * Matches the backend WorkOrder structure from WorkOrders
 */
export const WorkOrderSchema = z.object({
  id: uuidSchema,
  state: z.enum([
    'pending',
    'running',
    'success',
    'failed',
    'rejected',
    'killed',
    'exception',
    'crashed',
    'cancelled',
    'lost',
  ]),
  last_activity: isoDateTimeSchema,
  version: z.number(),
  runs: z.array(RunSummarySchema),
});

/**
 * Zod schema for the history list response from the server
 */
export const HistoryListSchema = z.array(WorkOrderSchema);

/**
 * Define run states as constants (single source of truth)
 */
export const ALL_RUN_STATES = [
  'available',
  'claimed',
  'started',
  'success',
  'failed',
  'crashed',
  'cancelled',
  'killed',
  'exception',
  'lost',
] as const;

export const FINAL_STATES = [
  'success',
  'failed',
  'crashed',
  'cancelled',
  'killed',
  'exception',
  'lost',
] as const;

export type RunState = (typeof ALL_RUN_STATES)[number];
export type FinalState = (typeof FINAL_STATES)[number];

/**
 * Type guard function to check if a state is final
 */
export function isFinalState(state: RunState): state is FinalState {
  return FINAL_STATES.includes(state as FinalState);
}

/**
 * Zod schema for StepDetail (detailed step data from run channel)
 */
export const StepDetailSchema = z.object({
  id: z.string().uuid(),
  job_id: z.string().uuid().nullable(),
  job: z
    .object({
      name: z.string(),
    })
    .nullish(), // Allow null or undefined
  exit_reason: z.string().nullable(),
  error_type: z.string().nullable(),
  started_at: z.string().nullable(),
  finished_at: z.string().nullable(),
  input_dataclip_id: z.string().uuid().nullable(),
  output_dataclip_id: z.string().uuid().nullable(),
  inserted_at: z.string(),
});

/**
 * Zod schema for RunDetail (full run data from dedicated run channel)
 */
export const RunDetailSchema = z.object({
  id: z.string().uuid(),
  work_order_id: z.string().uuid(),
  work_order: z.object({
    id: z.string().uuid(),
    workflow_id: z.string().uuid(),
  }),
  state: z.enum(ALL_RUN_STATES),
  created_by: z
    .object({
      email: z.string(),
    })
    .nullable(),
  starting_trigger: z
    .object({
      type: z.string(),
    })
    .nullable(),
  started_at: z.string().nullable(),
  finished_at: z.string().nullable(),
  inserted_at: z.string(),
  steps: z.array(StepDetailSchema),
});

/**
 * TypeScript types inferred from Zod schemas
 */
export type RunSummary = z.infer<typeof RunSummarySchema>;
export type WorkOrder = z.infer<typeof WorkOrderSchema>;
export type WorkflowRunHistory = WorkOrder[];
export type StepDetail = z.infer<typeof StepDetailSchema>;
export type RunDetail = z.infer<typeof RunDetailSchema>;

/**
 * Step data from backend
 */
export interface Step {
  id: string;
  job_id: string;
  exit_reason: string | null;
  error_type: string | null;
  started_at: string | null;
  finished_at: string | null;
  input_dataclip_id: string;
}

/**
 * Run steps data response from backend
 */
export interface RunStepsData {
  run_id: string;
  steps: Step[];
  metadata: {
    starting_job_id: string | null;
    starting_trigger_id: string | null;
    inserted_at: string;
    created_by_id: string | null;
    created_by_email: string | null;
  };
}

/**
 * Store state interface
 */
export interface HistoryState {
  // === HISTORY BROWSER STATE (Existing) ===
  history: WorkflowRunHistory;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
  isChannelConnected: boolean;
  runStepsCache: Record<string, RunStepsData>;
  runStepsSubscribers: Record<string, Set<string>>;
  runStepsLoading: Set<string>;

  // === ACTIVE RUN VIEWER STATE (New) ===
  activeRunId: string | null;
  activeRun: RunDetail | null;
  activeRunChannel: Channel | null;
  activeRunLoading: boolean;
  activeRunError: string | null;
  selectedStepId: string | null;
}

/**
 * Commands interface - Following CQS pattern
 * Commands mutate state and return void
 */
interface HistoryCommands {
  // Existing history commands
  requestHistory: (runId?: string) => Promise<void>;
  requestRunSteps: (runId: string) => Promise<RunStepsData | null>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  subscribeToRunSteps: (runId: string, subscriberId: string) => void;
  unsubscribeFromRunSteps: (runId: string, subscriberId: string) => void;

  // New active run commands
  _viewRun: (runId: string) => void;
  _closeRunViewer: () => void;
  selectStep: (stepId: string | null) => void;
  setActiveRunLoading: (loading: boolean) => void;
  setActiveRunError: (error: string | null) => void;
  clearActiveRunError: () => void;
}

/**
 * Queries interface - Following CQS pattern
 * Queries return data without side effects
 */
interface HistoryQueries {
  // Existing queries
  getSnapshot: () => HistoryState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: HistoryState) => T) => () => T;
  getRunSteps: (runId: string) => RunStepsData | null;

  // New active run queries
  getActiveRun: () => RunDetail | null;
  getSelectedStep: () => StepDetail | null;
  isActiveRunLoading: () => boolean;
  getActiveRunError: () => string | null;
}

/**
 * Internal methods interface
 * Methods prefixed with _ are for internal use only
 */
interface HistoryStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
  _viewRun: (runId: string) => void;
  _closeRunViewer: () => void;
  _switchingFromRun: () => void;
  _setActiveRunForTesting: (run: RunDetail) => void;
}

/**
 * Full HistoryStore interface
 * Combines queries, commands, and internals following CQS pattern
 */
export type HistoryStore = HistoryQueries &
  HistoryCommands &
  HistoryStoreInternals;
