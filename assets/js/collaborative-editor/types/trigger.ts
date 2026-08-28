import { isValidCron } from 'cron-validator';
import { z } from 'zod';

import _logger from '#/utils/logger';

import { uuidSchema } from './common';

const logger = _logger.ns('TriggerTypes').seal();

// Base trigger fields common to all trigger types
const baseTriggerSchema = z.object({
  id: uuidSchema,
  enabled: z.boolean().default(true),
  has_auth_method: z.boolean().default(false),
});

// Webhook trigger schema
const webhookTriggerSchema = baseTriggerSchema.extend({
  type: z.literal('webhook'),
  cron_expression: z.null().default(null),
  cron_cursor_job_id: z.null().default(null),
  webhook_reply: z
    .enum(['before_start', 'after_completion'])
    .nullable()
    .default('before_start'),
  webhook_response_config: z
    .object({
      success_code: z.number().int().nullable().default(null),
      error_code: z.number().int().nullable().default(null),
    })
    .nullable()
    .default(null),
});

// Cron trigger schema with professional validation using cron-validator
const cronTriggerSchema = baseTriggerSchema.extend({
  type: z.literal('cron'),
  cron_expression: z
    .string()
    .min(1, 'Cron expression is required')
    .refine(
      expr => {
        logger.log('validating cron expression', expr);
        // Use cron-validator for professional validation
        return isValidCron(expr, {
          seconds: false, // Standard 5-field format without seconds
          alias: true, // Allow @yearly, @monthly, etc.
          allowBlankDay: true, // Allow ? in day fields
        });
      },
      {
        message:
          'Invalid cron expression. Use format: minute hour day month weekday',
      }
    ),
  cron_cursor_job_id: z.string().uuid().nullable().default(null),
  webhook_response_config: z.null().default(null),
  webhook_reply: z.null().default(null).catch(null),
});

/**
 * Main discriminated union schema for all trigger types.
 * This provides compile-time type safety and runtime validation.
 */
export const TriggerSchema = z.discriminatedUnion('type', [
  webhookTriggerSchema,
  cronTriggerSchema,
]);

export type Trigger = z.infer<typeof TriggerSchema>;

/**
 * Helper function to create default trigger values by type
 */
export const createDefaultTrigger = (
  type: 'webhook' | 'cron'
): Partial<Trigger> => {
  const base = {
    enabled: true,
  };

  switch (type) {
    case 'webhook':
      return {
        ...base,
        type: 'webhook' as const,
        cron_expression: null,
        cron_cursor_job_id: null,
        webhook_reply: 'before_start' as const,
        webhook_response_config: null,
      };

    case 'cron':
      return {
        ...base,
        type: 'cron' as const,
        cron_expression: '0 0 * * *', // Daily at midnight default
        cron_cursor_job_id: null,
        webhook_reply: null,
      };

    default:
      return base;
  }
};
