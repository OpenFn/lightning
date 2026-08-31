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
  custom_path: z.string().nullable().default(null),
  cron_expression: z.null().default(null),
  cron_cursor_job_id: z.null().default(null),
  kafka_configuration: z.null().default(null),
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
  // Serialised for every trigger type; a pre-migration row can hold one here.
  // Accept and ignore rather than failing the whole workflow parse.
  custom_path: z.string().nullable().default(null),
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
  kafka_configuration: z.null().default(null),
  webhook_response_config: z.null().default(null),
  webhook_reply: z.null().default(null).catch(null),
});

// Kafka configuration sub-schema
const kafkaConfigSchema = z
  .object({
    hosts_string: z
      .string()
      .min(1, 'Kafka hosts are required')
      .regex(
        /^[^,\s]+(:\d+)?(,\s*[^,\s]+(:\d+)?)*$/,
        "Hosts must be in format 'host:port, host:port'"
      ),
    topics_string: z
      .string()
      .min(1, 'At least one topic is required')
      .regex(/^[^,\s]+(,\s*[^,\s]+)*$/, 'Invalid topic format'),
    ssl: z.boolean().default(false),
    sasl: z
      .enum(['plain', 'scram_sha_256', 'scram_sha_512'])
      .nullable()
      .default(null),
    username: z.string().nullable().optional(),
    password: z.string().nullable().optional(),
    initial_offset_reset_policy: z
      .enum(['earliest', 'latest'])
      .default('latest'),
    connect_timeout: z
      .number()
      .min(1000, 'Timeout must be at least 1000ms')
      .default(30000),
    group_id: z.string().optional(), // Auto-generated as lightning-{uuid}
  })
  .refine(
    data => {
      // If SASL is not "none", username and password are required
      if (data.sasl !== null) {
        return data.username && data.password;
      }
      return true;
    },
    {
      message:
        'Username and password are required when SASL authentication is enabled',
      path: ['username'], // Show error on username field
    }
  );

// Kafka trigger schema
const kafkaTriggerSchema = baseTriggerSchema.extend({
  type: z.literal('kafka'),
  // See the note on the cron schema.
  custom_path: z.string().nullable().default(null),
  cron_expression: z.null().default(null),
  cron_cursor_job_id: z.null().default(null),
  kafka_configuration: kafkaConfigSchema,
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
  kafkaTriggerSchema,
]);

export type Trigger = z.infer<typeof TriggerSchema>;

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Mirrors the server rule in `Lightning.Workflows.Trigger`. */
export const isValidCustomPath = (path: string): boolean =>
  /^[a-z0-9_-]{1,255}$/.test(path) && !UUID_RE.test(path);

/**
 * Derives a usable path, the way the project form derives a project name from
 * `raw_name`. Narrower: a webhook path is `[a-z0-9_-]` only.
 */
export const toCustomPath = (typed: string): string => {
  // Deriving would strip hyphens off a value the server accepts.
  if (isValidCustomPath(typed)) return typed;

  return typed
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '');
};

/**
 * What a user is allowed to write. `TriggerSchema` stays permissive because it
 * also parses what the server sends, including pre-migration paths.
 */
export const TriggerDraftSchema = TriggerSchema.superRefine((trigger, ctx) => {
  // Blank is no path, which is how the server reads it too.
  if (trigger.type !== 'webhook') return;
  if (trigger.custom_path == null || trigger.custom_path === '') return;

  if (!/^[a-z0-9_-]{1,255}$/.test(trigger.custom_path)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['custom_path'],
      message:
        'Custom URL path: use lowercase letters, numbers, hyphens and underscores only.',
    });
    return;
  }

  // A UUID-shaped path resolves against trigger ids, so it is unreachable.
  if (UUID_RE.test(trigger.custom_path)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['custom_path'],
      message: 'Custom URL path: cannot be a UUID.',
    });
  }
});

/**
 * Helper function to create default trigger values by type
 */
export const createDefaultTrigger = (
  type: 'webhook' | 'cron' | 'kafka'
): Partial<Trigger> => {
  const base = {
    enabled: true,
  };

  switch (type) {
    case 'webhook':
      return {
        ...base,
        type: 'webhook' as const,
        custom_path: null,
        cron_expression: null,
        cron_cursor_job_id: null,
        kafka_configuration: null,
        webhook_reply: 'before_start' as const,
        webhook_response_config: null,
      };

    case 'cron':
      return {
        ...base,
        type: 'cron' as const,
        custom_path: null,
        cron_expression: '0 0 * * *', // Daily at midnight default
        cron_cursor_job_id: null,
        kafka_configuration: null,
        webhook_reply: null,
      };

    case 'kafka':
      return {
        ...base,
        type: 'kafka' as const,
        custom_path: null,
        cron_expression: null,
        cron_cursor_job_id: null,
        kafka_configuration: {
          hosts_string: '',
          topics_string: '',
          ssl: false,
          sasl: null,
          username: '',
          password: '',
          initial_offset_reset_policy: 'latest' as const,
          connect_timeout: 30000,
        },
        webhook_reply: null,
      };

    default:
      return base;
  }
};
