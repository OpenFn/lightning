import type { PhoenixChannelProvider } from "y-phoenix-channel";
import * as z from "zod";

import { isoDateTimeSchema, uuidSchema } from "./common";

/**
 * Zod schema for a single Run
 * Matches the backend Run structure from WorkOrders
 */
export const RunSchema = z.object({
  id: uuidSchema,
  state: z.enum([
    "available",
    "claimed",
    "started",
    "success",
    "failed",
    "killed",
    "exception",
    "crashed",
    "cancelled",
    "lost",
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
    "pending",
    "running",
    "success",
    "failed",
    "rejected",
    "killed",
    "exception",
    "crashed",
    "cancelled",
    "lost",
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
 * Store state interface
 */
export interface HistoryState {
  history: WorkflowRunHistory;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
  isChannelConnected: boolean;
}

/**
 * Commands interface - Following CQS pattern
 * Commands mutate state and return void
 */
interface HistoryCommands {
  requestHistory: (runId?: string) => Promise<void>;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
}

/**
 * Queries interface - Following CQS pattern
 * Queries return data without side effects
 */
interface HistoryQueries {
  getSnapshot: () => HistoryState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: HistoryState) => T) => () => T;
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
