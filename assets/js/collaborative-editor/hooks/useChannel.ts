import type { Channel } from 'phoenix';

import { ChannelRequestError } from '../lib/errors';

/**
 * Channel error response from backend
 *
 * Error formats:
 * - Business logic errors (unauthorized, deleted, etc.) use `errors.base`
 * - Validation errors from Ecto changesets use field-specific keys (e.g., `errors.name`)
 */
/**
 * One field's errors as Ecto renders them.
 *
 * Top-level fields carry flat messages. Embedded associations (`jobs`, `edges`,
 * `triggers`) carry an entry per entity, each a map of that entity's own field
 * errors, wrapped in two levels of array — which is why
 * `formatChannelErrorMessage` flattens twice to reach them.
 */
export type ChannelFieldErrors = string[] | Record<string, string[]>[][];

export interface ChannelError {
  /**
   * Error messages organized by field or "base" for general errors.
   *
   * Examples:
   * - Business error: `{ base: ["This workflow has been deleted"] }`
   * - Validation error: `{ name: ["can't be blank"] }`
   * - Embedded association: `{ jobs: [[{ name: ["can't be blank"] }]] }`
   *
   * Optional: handlers that reply `{reason: "..."}` send no error map at all.
   */
  errors?:
    | ({
        /** Business logic errors (unauthorized, deleted, system failures) */
        base?: string[];
      } & Record<string, ChannelFieldErrors>)
    | undefined;

  /**
   * Error type indicating the category of error.
   * - unauthorized: User lacks permission
   * - workflow_deleted: Workflow was deleted
   * - deserialization_error: Failed to extract workflow data from Y.Doc
   * - internal_error: Unexpected server error
   * - validation_error: Ecto changeset validation failed
   * - optimistic_lock_error: Concurrent modification conflict (stale lock_version)
   * - limit_error: Usage limit exceeded (AI assistant, runs, etc.)
   *
   * Optional for the same reason as `errors`.
   */
  type?:
    | 'unauthorized'
    | 'workflow_deleted'
    | 'deserialization_error'
    | 'internal_error'
    | 'validation_error'
    | 'optimistic_lock_error'
    | 'limit_error'
    | 'adaptor_catalogue_unavailable'
    | undefined;

  /**
   * Plain-text message used by handlers that reply `{reason: "..."}` instead of
   * an `errors` map — `update_trigger_auth_methods` is the current example.
   */
  reason?: string | undefined;
}

export async function channelRequest<T = unknown>(
  channel: Channel,
  message: string,
  payload: object,
  timeout?: number
): Promise<T> {
  return new Promise((resolve, reject) => {
    const push =
      timeout === undefined
        ? channel.push(message, payload)
        : channel.push(message, payload, timeout);

    push
      .receive('ok', (response: T) => {
        resolve(response);
      })
      .receive('error', (channelError: ChannelError) => {
        reject(
          new ChannelRequestError(
            channelError.type,
            channelError.errors,
            channelError.reason
          )
        );
      })
      .receive('timeout', () => {
        reject(new Error('Request timed out'));
      });
  });
}
