import { z } from 'zod';

import {
  CONTROL_CHARS_MESSAGE,
  NAME_TOO_LONG_MESSAGE,
  NAME_TOO_WIDE_MESSAGE,
  hasControlChars,
  isInvisibleOnly,
  isNameTooLong,
  isNameTooWideForColumn,
  normalizeName,
} from '#/utils/nameValidation';

import { isoDateTimeSchema, uuidSchema } from './common';

// NPM package format validation for adaptor field
const adaptorSchema = z
  .string()
  .min(1, "can't be blank")
  .regex(
    /^@?[a-z0-9-~][a-z0-9-._~]*\/[a-z0-9-~][a-z0-9-._~]*@.+$/i,
    'Invalid adaptor format. Expected: @scope/package@version'
  );

// Main Job schema with comprehensive validation
export const JobSchema = z
  .object({
    // Core required fields
    id: uuidSchema,
    name: z
      .string()
      .transform(normalizeName)
      .pipe(
        z
          .string()
          .min(1, "Job name can't be blank")
          .refine(val => !isInvisibleOnly(val), "Job name can't be blank")
          .refine(val => !isNameTooLong(val), NAME_TOO_LONG_MESSAGE)
          .refine(val => !isNameTooWideForColumn(val), NAME_TOO_WIDE_MESSAGE)
          .refine(val => !hasControlChars(val), CONTROL_CHARS_MESSAGE)
      ),
    body: z.string().min(1, "can't be blank"),
    adaptor: adaptorSchema.default('@openfn/language-common@latest'),

    // Credential fields (mutually exclusive)
    project_credential_id: uuidSchema.nullable().default(null),
    keychain_credential_id: uuidSchema.nullable().default(null),

    // Association fields
    workflow_id: uuidSchema.optional(),

    // Virtual field for form deletion logic
    delete: z.boolean().optional(),

    // Timestamps (optional for new jobs)
    inserted_at: isoDateTimeSchema.optional(),
    updated_at: isoDateTimeSchema.optional(),
  })
  .refine(
    data => {
      // Enforce mutual exclusion of credential types
      const hasProjectCredential = !!data.project_credential_id;
      const hasKeychainCredential = !!data.keychain_credential_id;

      return !(hasProjectCredential && hasKeychainCredential);
    },
    {
      message: 'cannot be set when the other credential type is also set',
      path: ['project_credential_id'], // Show error on project_credential_id field
    }
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
