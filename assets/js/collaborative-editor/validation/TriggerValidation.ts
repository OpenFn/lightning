import { isValidCron } from "cron-validator";
import { z } from "zod";

/**
 * Validation schemas for Lightning Workflow Triggers using Zod discriminated unions
 *
 * Following TanStack Form integration guidelines with CQS architecture.
 * These schemas validate trigger forms and ensure type safety across the app.
 */

// Base trigger fields common to all trigger types
const baseTriggerSchema = z.object({
  id: z.string().optional(),
  enabled: z.boolean().default(true),
});

// Webhook trigger schema
const webhookTriggerSchema = baseTriggerSchema.extend({
  type: z.literal("webhook"),
  cron_expression: z.null(),
  kafka_configuration: z.null(),
});

// Cron trigger schema with professional validation using cron-validator
const cronTriggerSchema = baseTriggerSchema.extend({
  type: z.literal("cron"),
  cron_expression: z
    .string()
    .min(1, "Cron expression is required")
    .refine(
      (expr) => {
        console.log("validating cron expression", expr);
        // Use cron-validator for professional validation
        return isValidCron(expr, {
          seconds: false, // Standard 5-field format without seconds
          alias: true, // Allow @yearly, @monthly, etc.
          allowBlankDay: true, // Allow ? in day fields
        });
      },
      {
        message:
          "Invalid cron expression. Use format: minute hour day month weekday",
      },
    ),
  kafka_configuration: z.null(),
});

// Kafka configuration sub-schema
const kafkaConfigSchema = z
  .object({
    hosts: z
      .string()
      .min(1, "Kafka hosts are required")
      .regex(
        /^[^,]+:\d+(,[^,]+:\d+)*$/,
        "Hosts must be in format 'host:port,host:port'",
      ),
    topics: z
      .string()
      .min(1, "At least one topic is required")
      .regex(/^[^,]+(,[^,]+)*$/, "Invalid topic format"),
    ssl: z.boolean().default(false),
    sasl: z
      .enum(["none", "plain", "scram_sha_256", "scram_sha_512"])
      .default("none"),
    username: z.string().optional(),
    password: z.string().optional(),
    initial_offset_reset_policy: z
      .enum(["earliest", "latest"])
      .default("latest"),
    connect_timeout: z
      .number()
      .min(1000, "Timeout must be at least 1000ms")
      .default(30000),
    group_id: z.string().optional(), // Auto-generated as lightning-{uuid}
  })
  .refine(
    (data) => {
      // If SASL is not "none", username and password are required
      if (data.sasl !== "none") {
        return data.username && data.password;
      }
      return true;
    },
    {
      message:
        "Username and password are required when SASL authentication is enabled",
      path: ["username"], // Show error on username field
    },
  );

// Kafka trigger schema
const kafkaTriggerSchema = baseTriggerSchema.extend({
  type: z.literal("kafka"),
  cron_expression: z.null(),
  kafka_configuration: kafkaConfigSchema,
});

/**
 * Main discriminated union schema for all trigger types.
 * This provides compile-time type safety and runtime validation.
 */
export const TriggerValidation = z.discriminatedUnion("type", [
  webhookTriggerSchema,
  cronTriggerSchema,
  kafkaTriggerSchema,
]);

// Export individual schemas for specific use cases
export const WebhookValidation = webhookTriggerSchema;
export const CronValidation = cronTriggerSchema;
export const KafkaValidation = kafkaTriggerSchema;
export const KafkaConfigValidation = kafkaConfigSchema;

// Type inference from schemas
export type ValidatedTrigger = z.infer<typeof TriggerValidation>;
export type ValidatedWebhookTrigger = z.infer<typeof WebhookValidation>;
export type ValidatedCronTrigger = z.infer<typeof CronValidation>;
export type ValidatedKafkaTrigger = z.infer<typeof KafkaValidation>;
export type ValidatedKafkaConfig = z.infer<typeof KafkaConfigValidation>;

/**
 * Helper function to create default trigger values by type
 */
export const createDefaultTrigger = (
  type: "webhook" | "cron" | "kafka",
): Partial<ValidatedTrigger> => {
  const base = {
    enabled: true,
  };

  switch (type) {
    case "webhook":
      return {
        ...base,
        type: "webhook" as const,
        cron_expression: null,
        kafka_configuration: null,
      };

    case "cron":
      return {
        ...base,
        type: "cron" as const,
        cron_expression: "0 0 * * *", // Daily at midnight default
        kafka_configuration: null,
      };

    case "kafka":
      return {
        ...base,
        type: "kafka" as const,
        cron_expression: null,
        kafka_configuration: {
          hosts: "",
          topics: "",
          ssl: false,
          sasl: "none" as const,
          username: "",
          password: "",
          initial_offset_reset_policy: "latest" as const,
          connect_timeout: 30000,
        },
      };

    default:
      return base;
  }
};

/**
 * Type guard functions for runtime type checking
 */
export const isWebhookTrigger = (
  trigger: any,
): trigger is ValidatedWebhookTrigger => {
  return trigger?.type === "webhook";
};

export const isCronTrigger = (
  trigger: any,
): trigger is ValidatedCronTrigger => {
  return trigger?.type === "cron";
};

export const isKafkaTrigger = (
  trigger: any,
): trigger is ValidatedKafkaTrigger => {
  return trigger?.type === "kafka";
};
