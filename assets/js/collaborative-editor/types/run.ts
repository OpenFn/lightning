import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import { z } from 'zod';

// Define run states as constants first (single source of truth)
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

export type RunStatus = (typeof ALL_RUN_STATES)[number];
export type FinalState = (typeof FINAL_STATES)[number];

// Zod schemas for runtime validation
export const StepSchema = z.object({
  id: z.string().uuid(),
  job_id: z.string().uuid(),
  job: z
    .object({
      id: z.string().uuid(),
      name: z.string(),
    })
    .optional(),
  exit_reason: z.string().nullable(),
  error_type: z.string().nullable(),
  started_at: z.string().nullable(),
  finished_at: z.string().nullable(),
  input_dataclip_id: z.string().uuid().nullable(),
  output_dataclip_id: z.string().uuid().nullable(),
  inserted_at: z.string(),
});

export const WorkOrderSchema = z.object({
  id: z.string().uuid(),
  state: z.string(),
  workflow_id: z.string().uuid(),
  snapshot_id: z.string().uuid().nullable(),
  trigger_id: z.string().uuid().nullable(),
  dataclip_id: z.string().uuid().nullable(),
  last_activity: z.string().datetime().nullable().optional(),
  inserted_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});

export const RunSchema = z.object({
  id: z.string().uuid(),
  work_order_id: z.string().uuid(),
  work_order: WorkOrderSchema.optional(),
  state: z.enum(ALL_RUN_STATES),
  started_at: z.string().nullable(),
  finished_at: z.string().nullable(),
  created_by: z
    .object({
      email: z.string(),
    })
    .nullable()
    .optional(),
  starting_trigger: z
    .object({
      type: z.string(),
    })
    .nullable()
    .optional(),
  steps: z.array(StepSchema),
});

export type Step = z.infer<typeof StepSchema>;
export type WorkOrder = z.infer<typeof WorkOrderSchema>;
export type Run = z.infer<typeof RunSchema>;

// Type guard function to check if a state is final
export function isFinalState(state: Run['state']): state is FinalState {
  return FINAL_STATES.includes(state as FinalState);
}

// State interface
export interface RunState {
  currentRun: Run | null;
  selectedStepId: string | null;
  isLoading: boolean;
  error: string | null;
  lastUpdated: number | null;
}

// Commands interface - state mutations
export interface RunCommands {
  setRun: (run: Run) => void;
  updateRunState: (updates: Partial<Run>) => void;
  addOrUpdateStep: (step: Step) => void;
  selectStep: (stepId: string | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  clearError: () => void;
  clear: () => void;
}

// Queries interface - state reads
export interface RunQueries {
  getSnapshot: () => RunState;
  subscribe: (listener: () => void) => () => void;
  withSelector: <T>(selector: (state: RunState) => T) => () => T;
  findStepById: (id: string) => Step | null;
  getSelectedStep: () => Step | null;
}

// Internals interface - channel connection
export interface RunInternals {
  _connectToRun: (
    provider: PhoenixChannelProvider,
    runId: string
  ) => () => void;
  _disconnectFromRun: () => void;
}

// Complete store interface
export type RunStore = RunCommands & RunQueries & RunInternals;
