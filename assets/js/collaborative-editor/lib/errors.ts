import { toTitleCase } from '#/collaborative-editor/utils/adaptorUtils';

import type { ChannelError } from '../hooks/useChannel';

/**
 * Custom error thrown by channelRequest when backend returns an error.
 * Does not include a formatted message - formatting happens at higher levels.
 */
export class ChannelRequestError extends Error {
  type:
    | 'unauthorized'
    | 'validation_error'
    | 'workflow_deleted'
    | 'deserialization_error'
    | 'internal_error'
    | 'optimistic_lock_error';
  errors: Record<string, string[] | undefined>;

  constructor(
    type: ChannelRequestError['type'],
    errors: Record<string, string[] | undefined>
  ) {
    super('Channel request failed');
    this.name = 'ChannelRequestError';
    this.type = type;
    this.errors = errors;
  }
}

/**
 * Type guard to check if an error is a ChannelRequestError
 */
export function isChannelRequestError(
  error: unknown
): error is ChannelRequestError {
  return error instanceof ChannelRequestError;
}

/**
 * Format channel error into user-friendly message.
 * Tries "base" first, then formats field-specific errors with field names.
 * Handles both flat error structures and nested arrays from Phoenix changeset errors.
 */
export function formatChannelErrorMessage(channelError: ChannelError): string {
  // First try the base errors
  if (channelError.errors.base?.[0]) {
    return channelError.errors.base[0];
  }

  // Handle nested error structures from Phoenix changeset errors
  // Structure can be: { field: [[{ nested_field: ['messages'] }]] }
  const fError = Object.values(channelError.errors)
    .flat(2)
    .find(v => v && typeof v === 'object' && Object.keys(v).length > 0) as
    | Record<string, unknown>
    | undefined;

  if (fError) {
    const msg = Object.entries(fError)
      .map(([key, val]) => {
        // Handle both string arrays and single strings safely
        const messages = Array.isArray(val) ? val : [String(val)];
        // toTitleCase splits on underscores and capitalizes each word
        return `${toTitleCase(key)}: ${messages.join(', ')}`;
      })
      .join('\n');

    return msg || 'An error occurred';
  }

  // show max 3 errros
  const validationErrs = Object.values(channelError.errors)
    .flat()
    .map((v, i) => `- ${v}`);

  if (validationErrs.length) {
    return validationErrs.join('\n');
  }

  return 'An error occurred';
}
