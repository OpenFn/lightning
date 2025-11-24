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
  if (channelError.errors.base?.[0]) {
    return channelError.errors.base[0];
  }

  const fError = Object.values(channelError.errors)
    .flat(2)
    .find(v => Object.keys(v).length) as unknown as Record<string, string[]>;
  if (!fError) return 'An error occurred';
  const msg = Object.entries(fError)
    .map(([key, val]) => {
      return `${toTitleCase(key)}: ${val.join(', ')}`;
    })
    .join('\n');
  return msg;
}
