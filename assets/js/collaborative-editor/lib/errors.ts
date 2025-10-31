import { toTitleCase } from "#/collaborative-editor/utils/adaptorUtils";

import type { ChannelError } from "../hooks/useChannel";

/**
 * Custom error thrown by channelRequest when backend returns an error.
 */
export interface ChannelRequestError extends Error {
  type:
    | "unauthorized"
    | "validation_error"
    | "workflow_deleted"
    | "deserialization_error"
    | "internal_error"
    | "optimistic_lock_error";
  errors: Record<string, string[] | undefined>;
}

/**
 * Type guard to check if an error is a ChannelRequestError
 */
export function isChannelRequestError(
  error: unknown
): error is ChannelRequestError {
  return error instanceof Error && "type" in error && "errors" in error;
}

/**
 * Format channel error into user-friendly message.
 * Tries "base" first, then formats field-specific errors with field names.
 */
export function formatChannelErrorMessage(channelError: ChannelError): string {
  if (channelError.errors.base?.[0]) {
    return channelError.errors.base[0];
  }

  const firstField = Object.keys(channelError.errors)[0];
  const firstError = channelError.errors[firstField]?.[0];

  if (firstField && firstError) {
    const formattedField = toTitleCase(firstField);
    return `${formattedField}: ${firstError}`;
  }

  return "An error occurred";
}
