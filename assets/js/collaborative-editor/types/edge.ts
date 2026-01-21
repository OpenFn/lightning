import { z } from 'zod';

import { uuidSchema } from './common';

export const EdgeConditionType = z.enum([
  'on_job_success',
  'on_job_failure',
  'always',
  'js_expression',
]);

export const EdgeSchema = z.object({
  // Core identifiers
  id: uuidSchema,
  workflow_id: uuidSchema.optional(),

  // Source (mutually exclusive)
  source_job_id: uuidSchema.nullable().optional(),
  source_trigger_id: uuidSchema.nullable().optional(),

  // Target (required)
  target_job_id: uuidSchema,

  // Condition configuration
  condition_type: EdgeConditionType.default('on_job_success'),
  condition_expression: z.string().optional().nullable(),
  condition_label: z
    .string()
    .max(255, 'should be at most 255 character(s)')
    .nullable()
    .optional(),

  // Execution control
  enabled: z.boolean().default(true),

  // Virtual field for deletion
  delete: z.boolean().optional(),

  // Timestamps
  inserted_at: z.string().optional(),
  updated_at: z.string().optional(),
});
export const ExprEdgeSchema = EdgeSchema.extend({
  condition_expression: z
    .string()
    .trim()
    .min(1, "can't be blank")
    .max(255, 'should be at most 255 character(s)')
    .nullable(),
});
export type EdgeFormValues = z.infer<typeof EdgeSchema>;
