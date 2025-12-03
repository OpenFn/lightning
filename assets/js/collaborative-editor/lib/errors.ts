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
 */
export function formatChannelErrorMessage(channelError: ChannelError): string {
  // First try the base errors
  if (channelError.errors.base?.[0]) {
    return channelError.errors.base[0];
  }

  // Format field-specific errors
  const errorMessages: string[] = [];
  for (const [field, messages] of Object.entries(channelError.errors)) {
    if (field === 'base' || !messages) continue;

    // Handle both string arrays and single strings
    const msgArray = Array.isArray(messages) ? messages : [String(messages)];
    const fieldName = toTitleCase(
      field.replace(/\[\d+\]\./g, ' ').replace(/_/g, ' ')
    );
    errorMessages.push(`${fieldName}: ${msgArray.join(', ')}`);
  }

  return errorMessages.length > 0
    ? errorMessages.join('\n')
    : 'An error occurred';
}
