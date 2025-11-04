import type { Channel } from 'phoenix';

/**
 * Channel error response from backend
 */
export interface ChannelError {
  errors: Record<string, string[]>;
  type: string;
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
      .receive('error', (error: ChannelError) => {
        const errorMessage =
          error.errors['base'][0] ||
          Object.values(error.errors || {})[0]?.[0] ||
          'An error occurred';
        const customError = new Error(errorMessage) as Error & {
          type?: string;
          errors?: Record<string, string[]>;
        };
        customError.type = error.type;
        customError.errors = error.errors;
        reject(customError);
      })
      .receive('timeout', () => {
        reject(new Error('Request timed out'));
      });
  });
}
