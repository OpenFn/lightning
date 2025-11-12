import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as z from 'zod';

import { isoDateTimeSchema, uuidSchema } from './common';

/**
 * Zod schema for a single Run
 * Matches the backend Run structure from WorkOrders
 */
export const RunSchema = z.object({
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
  runs: z.array(RunSchema),
});

/**
 * Zod schema for the history list response from the server
 */
export const HistoryListSchema = z.array(WorkOrderSchema);

/**
 * TypeScript types inferred from Zod schemas
 */
export type Run = z.infer<typeof RunSchema>;
export type WorkOrder = z.infer<typeof WorkOrderSchema>;
export type WorkflowRunHistory = WorkOrder[];

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
  history: WorkflowRunHistory;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
  isChannelConnected: boolean;
  runStepsCache: Record<string, RunStepsData>;
  runStepsSubscribers: Record<string, Set<string>>;
  runStepsLoading: Set<string>;
}

/**
 * Commands interface - Following CQS pattern
 * Commands mutate state and return void
 */
interface HistoryCommands {
  requestHistory: (runId?: string) => Promise<void>;
  requestRunSteps: (runId: string) => Promise<RunStepsData | null>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  subscribeToRunSteps: (runId: string, subscriberId: string) => void;
  unsubscribeFromRunSteps: (runId: string, subscriberId: string) => void;
}

/**
 * Queries interface - Following CQS pattern
 * Queries return data without side effects
 */
interface HistoryQueries {
  getSnapshot: () => HistoryState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: HistoryState) => T) => () => T;
  getRunSteps: (runId: string) => RunStepsData | null;
}

/**
 * Internal methods interface
 * Methods prefixed with _ are for internal use only
 */
interface HistoryStoreInternals {
  _connectChannel: (provider: PhoenixChannelProvider) => () => void;
}

/**
 * Full HistoryStore interface
 * Combines queries, commands, and internals following CQS pattern
 */
export type HistoryStore = HistoryQueries &
  HistoryCommands &
  HistoryStoreInternals;
