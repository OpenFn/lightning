import { z } from 'zod';

import { isNameTooWideForColumn } from '#/utils/nameValidation';

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
  // Codepoints, like the label below. This had no cap at all, while the
  // ExprEdgeSchema override nineteen lines down capped it in UTF-16 units;
  // the server validates it on every condition type, so this side does too.
  condition_expression: z
    .string()
    .refine(
      val => !isNameTooWideForColumn(val),
      'should be at most 255 character(s)'
    )
    .optional()
    .nullable(),
  // Counted in codepoints, which is the unit the column is measured in, not
  // UTF-16 units. EdgeSchema sits inside BaseWorkflowSchema and
  // createSessionContextStore does one safeParse over the whole payload, so a
  // label the server stored happily must never be refused here: a 128 emoji
  // label stores fine and measured 256 under `.max(255)`, which killed the
  // collaborative editor for the whole project. Reachable on legacy rows too,
  // because the label cap used to live inside the :js_expression branch.
  condition_label: z
    .string()
    .refine(
      val => !isNameTooWideForColumn(val),
      'should be at most 255 character(s)'
    )
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
  // Codepoints, not UTF-16 units. This runs on every keystroke through
  // EdgeForm, so 200 astral emoji -- 200 codepoints the server stores fine --
  // were refused in the browser at 400.
  condition_expression: z
    .string()
    .trim()
    .min(1, "can't be blank")
    .refine(
      val => !isNameTooWideForColumn(val),
      'should be at most 255 character(s)'
    )
    .nullable(),
});
export type EdgeFormValues = z.infer<typeof EdgeSchema>;
