import { toTitleCase } from '#/collaborative-editor/utils/adaptorUtils';

import type { ChannelError } from '../hooks/useChannel';

/**
 * Custom error thrown by channelRequest when backend returns an error.
 *
 * The message is formatted from the server's error payload at construction, so
 * every consumer gets a readable message without having to format it itself.
 * Callers that suppress a toast still hand a useful message to whoever catches
 * the rethrow.
 */
export class ChannelRequestError extends Error {
  type: ChannelError['type'];
  errors: NonNullable<ChannelError['errors']>;

  constructor(
    type: ChannelError['type'],
    errors: ChannelError['errors'],
    reason?: string
  ) {
    super(formatChannelErrorMessage({ type, errors, reason }));
    this.name = 'ChannelRequestError';
    this.type = type;
    // Consumers read `.errors` unconditionally, so keep it an object even when
    // the reply carried no error map.
    this.errors = errors ?? {};
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
  // Not every handler replies with an error map — several reply `{reason: ...}`
  // only. Treat a missing map as empty rather than dereferencing it: this runs
  // inside ChannelRequestError's constructor, which is evaluated as the argument
  // to `reject`, so throwing here stops the promise settling at all.
  const errors = channelError.errors ?? {};

  // First try the base errors
  if (errors.base?.[0]) {
    return errors.base[0];
  }

  // Handle nested error structures from Phoenix changeset errors
  // Structure can be: { field: [[{ nested_field: ['messages'] }]] }
  const fError = Object.values(errors)
    .flat(2)
    .find(v => v && typeof v === 'object' && Object.keys(v).length > 0) as
    Record<string, unknown> | undefined;

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
  // Only flat message arrays should reach here — anything nested was handled
  // above — but drop non-strings rather than assume, so an unfamiliar shape
  // falls through to the message below instead of rendering "[object Object]".
  const validationErrs = Object.values(errors)
    .flat()
    .filter((v): v is string => typeof v === 'string')
    .map(v => `- ${v}`)
    .splice(0, 3);

  if (validationErrs.length) {
    return validationErrs.join('\n');
  }

  // Replies with no error map still name the problem in `reason`; preferring it
  // over the generic fallback is the difference between "trigger not found" and
  // "An error occurred".
  if (channelError.reason) {
    return channelError.reason;
  }

  return 'An error occurred';
}
