import type { Channel } from "phoenix";

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
      .receive("error", (error: { reason: string }) => {
        reject(new Error(error.reason));
      })
      .receive("timeout", () => {
        reject(new Error("Request timed out"));
      });
  });
}
