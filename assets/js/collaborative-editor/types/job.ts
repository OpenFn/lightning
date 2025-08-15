import { z } from "zod";

/**
 * Comprehensive Job validation schema following Lightning's backend validation
 * rules. This replaces the simple Job type and provides runtime validation
 * for all job fields with proper error messages that match the backend.
 */

// UUID validation helper
const uuidSchema = z.uuid({ message: "Invalid UUID format" }).optional();

// NPM package format validation for adaptor field
const adaptorSchema = z
  .string()
  .min(1, "can't be blank")
  .regex(
    /^@?[a-z0-9-~][a-z0-9-._~]*\/[a-z0-9-~][a-z0-9-._~]*@.+$/i,
    "Invalid adaptor format. Expected: @scope/package@version",
  );

// Main Job schema with comprehensive validation
export const JobSchema = z
  .object({
    // Core required fields
    id: uuidSchema,
    name: z
      .string()
      .min(1, "can't be blank")
      .max(100, "should be at most 100 character(s)")
      .regex(/^[a-zA-Z0-9_\- ]*$/, "has invalid format")
      .transform((val) => val.trim()), // Auto-trim whitespace like backend
    body: z.string().min(1, "can't be blank"),
    adaptor: adaptorSchema.default("@openfn/language-common@latest"),

    // Credential fields (mutually exclusive)
    project_credential_id: uuidSchema,
    keychain_credential_id: uuidSchema,

    // Association fields
    workflow_id: uuidSchema,

    // Virtual field for form deletion logic
    delete: z.boolean().optional(),

    // Timestamps (optional for new jobs)
    inserted_at: z
      .string()
      .datetime({ message: "Invalid datetime format" })
      .optional(),
    updated_at: z
      .string()
      .datetime({ message: "Invalid datetime format" })
      .optional(),

    // Additional fields that may be needed for UI state
    enabled: z.boolean().default(true),
  })
  .refine(
    (data) => {
      // Enforce mutual exclusion of credential types
      const hasProjectCredential = !!data.project_credential_id;
      const hasKeychainCredential = !!data.keychain_credential_id;

      return !(hasProjectCredential && hasKeychainCredential);
    },
    {
      message: "cannot be set when the other credential type is also set",
      path: ["project_credential_id"], // Show error on project_credential_id field
    },
  );

export type Job = z.infer<typeof JobSchema>;

// Export validation schemas for specific use cases
export const JobValidation = JobSchema;

// Partial schema for job updates (all fields optional except validation rules)
export const JobUpdateSchema = JobSchema.partial();

// Schema for creating new jobs (some fields required)
export const JobCreateSchema = JobSchema.omit({
  id: true,
  inserted_at: true,
  updated_at: true,
});

export type JobUpdate = z.infer<typeof JobUpdateSchema>;
export type JobCreate = z.infer<typeof JobCreateSchema>;
