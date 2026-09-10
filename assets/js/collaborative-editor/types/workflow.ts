/* eslint-disable @typescript-eslint/no-namespace */
// What should we do about this?

/**
 * Updated workflow types following useSyncExternalStore + Immer + Y.Doc pattern
 * Provides referentially stable state management with clear separation between
 * collaborative data (Y.Doc sourced) and local UI state.
 */

import type * as Y from 'yjs';
import { z } from 'zod';

import {
  CONTROL_CHARS_MESSAGE,
  NAME_BLANK_MESSAGE,
  NAME_TOO_WIDE_MESSAGE,
  hasControlChars,
  isInvisibleOnly,
  isNameTooWideForColumn,
  normalizeName,
} from '#/utils/nameValidation';

import { EdgeSchema } from './edge';
import { JobSchema, type Job as JobType } from './job';
import type { Session } from './session';
import { TriggerSchema, type Trigger as TriggerType } from './trigger';

/**
 * The workflow name rule, in one place, used by every schema that validates a
 * name the user typed. Normalise first, then check, which is the order the
 * server uses. Mirrors `Lightning.Workflows.Workflow.validate/1`.
 *
 * Deliberately not used by `BaseWorkflowSchema`, which parses what the server
 * sends rather than what the user typed. See the note there.
 */
export const workflowNameSchema = z
  .string()
  .transform(normalizeName)
  .pipe(
    z
      .string()
      .min(1, "can't be blank")
      .refine(val => !isInvisibleOnly(val), NAME_BLANK_MESSAGE)
      // Codepoints only. A grapheme count is never above a codepoint count, so
      // a grapheme cap at the same 255 could not reject anything this does not.
      .refine(val => !isNameTooWideForColumn(val), NAME_TOO_WIDE_MESSAGE)
      .refine(val => !hasControlChars(val), CONTROL_CHARS_MESSAGE)
  );

export const WorkflowSchema = z.object({
  id: z.string().uuid(),
  name: workflowNameSchema,
  lock_version: z.number().int(),
  deleted_at: z.string().nullable(),

  // Note: These fields exist in backend but not in Y.Doc Session.Workflow type
  // They will be added to form state as virtual fields for future use
  concurrency: z
    .number()
    .int()
    .min(1, 'must be at least 1')
    .nullable()
    .optional(),
  enable_job_logs: z.boolean().optional(),
});

export type WorkflowFormValues = z.infer<typeof WorkflowSchema>;

export const BaseWorkflowSchema = z.object({
  jobs: z.array(JobSchema),
  triggers: z.array(TriggerSchema),
  edges: z.array(EdgeSchema),
  positions: z.record(z.string(), z.object({}).loose()).nullable(),
  // This schema parses the workflow arriving FROM the server, and one failed
  // safeParse throws the whole session context away, so a name the server
  // stored happily must never be refused here. Codepoints, and no control
  // character check: the server is the authority on what may be written.
  name: z
    .string()
    .min(1)
    .refine(val => !isNameTooWideForColumn(val)),
  concurrency: z.number().nullable().optional(),
  enable_job_logs: z.boolean().default(false),
});

export type BaseWorkflow = z.infer<typeof BaseWorkflowSchema>;

/**
 * Creates a workflow schema with dynamic project concurrency validation
 *
 * @param projectConcurrency - The project's max concurrency limit (null = unlimited)
 * @returns Zod schema with appropriate concurrency validation
 */
export function createWorkflowSchema(projectConcurrency: number | null) {
  return z.object({
    id: z.string().uuid(),
    name: workflowNameSchema,
    lock_version: z.number().int(),
    deleted_at: z.string().nullable(),

    concurrency:
      projectConcurrency !== null
        ? z
            .number()
            .int()
            .min(1, 'must be at least 1')
            .max(
              projectConcurrency,
              `exceeds project concurrency limit (${projectConcurrency}) and has no effect`
            )
            .nullable()
            .optional()
        : z.number().int().min(1, 'must be at least 1').nullable().optional(),
    enable_job_logs: z.boolean().optional(),
  });
}

export interface Workflow extends Session.Workflow {
  jobs: Workflow.Job[];
  triggers: Workflow.Trigger[];
  edges: Workflow.Edge[];
  positions: Workflow.Positions;
}

export namespace Workflow {
  // Domain objects - use comprehensive Job type from job.ts with errors
  export type Job = JobType & { errors?: Record<string, string[]> };

  export type Trigger = TriggerType & { errors?: Record<string, string[]> };

  export interface Edge {
    id: string;
    source_job_id?: string | null;
    source_trigger_id?: string | null;
    target_job_id: string;
    condition?: string;
    condition_type?: string;
    condition_expression?: string;
    condition_label?: string;
    enabled?: boolean;
    errors?: Record<string, string[]>;
  }

  export type NodeType = 'job' | 'trigger' | 'edge';
  export type Node = Job | Trigger | Edge;

  export type Positions = Record<string, { x: number; y: number }>;

  export interface State {
    // Y.Doc sourced data (synced via observers) - all now have errors denormalized
    workflow: Session.Workflow | null; // Has errors property
    jobs: Workflow.Job[]; // Has errors property
    triggers: Workflow.Trigger[]; // Has errors property
    edges: Workflow.Edge[]; // Has errors property
    positions: Workflow.Positions;

    // UndoManager for undo/redo operations
    undoManager: Y.UndoManager | null;

    // Local UI state
    selectedJobId: string | null;
    selectedTriggerId: string | null;
    selectedEdgeId: string | null;

    // Computed/derived state
    enabled: boolean | null; // Computed from triggers
    selectedNode: Workflow.Job | Workflow.Trigger | null;
    selectedEdge: Workflow.Edge | null;

    // Active trigger webhook auth methods (loaded on-demand from server)
    activeTriggerAuthMethods: {
      trigger_id: string;
      webhook_auth_methods: Array<{
        id: string;
        name: string;
        auth_type: string;
      }>;
    } | null;

    // AI workflow apply coordination state
    // Tracks when someone is applying an AI-generated workflow to prevent concurrent applies
    isApplyingWorkflow: boolean;
    applyingUser: { id: string; name: string } | null;

    // AI job code apply coordination state
    // Tracks when someone is applying AI-generated job code to prevent concurrent applies
    isApplyingJobCode: boolean;
    applyingJobUser: { id: string; name: string } | null;
    applyingJobCodeMessageId: string | null;
  }
}

/* eslint-enable @typescript-eslint/no-namespace */
