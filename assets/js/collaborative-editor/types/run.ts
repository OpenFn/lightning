import { z } from "zod";
import type { PhoenixChannelProvider } from "y-phoenix-channel";

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

export const RunSchema = z.object({
  id: z.string().uuid(),
  work_order_id: z.string().uuid(),
  state: z.enum([
    "available",
    "claimed",
    "started",
    "success",
    "failed",
    "crashed",
    "cancelled",
    "killed",
    "exception",
    "lost",
  ]),
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
export type Run = z.infer<typeof RunSchema>;

// Final states for UI logic
export const FINAL_STATES = [
  "success",
  "failed",
  "crashed",
  "cancelled",
  "killed",
  "exception",
  "lost",
] as const;
export type FinalState = (typeof FINAL_STATES)[number];

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
