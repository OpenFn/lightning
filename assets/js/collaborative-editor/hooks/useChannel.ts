import type { Channel } from 'phoenix';

import { ChannelRequestError } from '../lib/errors';

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
    | 'unauthorized'
    | 'workflow_deleted'
    | 'deserialization_error'
    | 'internal_error'
    | 'validation_error'
    | 'optimistic_lock_error';
}

export async function channelRequest<T = unknown>(
  channel: Channel,
  message: string,
  payload: object
): Promise<T> {
  return new Promise((resolve, reject) => {
    channel
      .push(message, payload)
      .receive('ok', (response: T) => {
        resolve(response);
      })
      .receive('error', (channelError: ChannelError) => {
        reject(new ChannelRequestError(channelError.type, channelError.errors));
      })
      .receive('timeout', () => {
        reject(new Error('Request timed out'));
      });
  });
}
