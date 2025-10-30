import type { Channel } from "phoenix";

import { toTitleCase } from "#/collaborative-editor/utils/adaptorUtils";

/**
 * Channel error response from backend
 *
 * Error formats:
 * - Business logic errors (unauthorized, deleted, etc.) use `errors.base`
 * - Validation errors from Ecto changesets use field-specific keys (e.g., `errors.name`)
 */
export interface ChannelError {
  /**
   * Error messages organized by field or "base" for general errors.
   * Each field contains an array of error messages.
   *
   * Examples:
   * - Business error: `{ base: ["This workflow has been deleted"] }`
   * - Validation error: `{ name: ["can't be blank"] }`
   * - Multiple fields: `{ name: ["can't be blank"], concurrency: ["must be greater than 0"] }`
   */
  errors: {
    /** Business logic errors (unauthorized, deleted, system failures) */
    base?: string[];
  } & Record<string, string[]>;

  /**
   * Error type indicating the category of error.
   * - unauthorized: User lacks permission
   * - workflow_deleted: Workflow was deleted
   * - deserialization_error: Failed to extract workflow data from Y.Doc
   * - internal_error: Unexpected server error
   * - validation_error: Ecto changeset validation failed
   * - optimistic_lock_error: Concurrent modification conflict (stale lock_version)
   */
  type:
    | "unauthorized"
    | "workflow_deleted"
    | "deserialization_error"
    | "internal_error"
    | "validation_error"
    | "optimistic_lock_error";
}

export async function channelRequest<T = unknown>(
  channel: Channel,
  message: string,
  payload: object
): Promise<T> {
  return new Promise((resolve, reject) => {
    channel
      .push(message, payload)
      .receive("ok", (response: T) => {
        resolve(response);
      })
      .receive("error", (error: ChannelError) => {
        // Extract error message - try "base" first, then format field-specific errors
        let errorMessage: string;

        if (error.errors.base?.[0]) {
          // Use base error if available
          errorMessage = error.errors.base[0];
        } else {
          // Format field-specific error with field name for context
          const firstField = Object.keys(error.errors)[0];
          const firstError = error.errors[firstField]?.[0];

          if (firstField && firstError) {
            // Format field name with title case (e.g., "workflow_name" -> "Workflow Name")
            const formattedField = toTitleCase(firstField);
            errorMessage = `${formattedField}: ${firstError}`;
          } else {
            errorMessage = "An error occurred";
          }
        }

        const customError = new Error(errorMessage) as Error & {
          type?: string;
          errors?: Record<string, string[] | undefined>;
        };
        customError.type = error.type;
        customError.errors = error.errors;
        reject(customError);
      })
      .receive("timeout", () => {
        reject(new Error("Request timed out"));
      });
  });
}
