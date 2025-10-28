import type { Channel } from "phoenix";

/**
 * Channel error response from backend
 */
export interface ChannelError {
  errors: Record<string, string[] | undefined>;
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
      .receive("ok", (response: T) => {
        resolve(response);
      })
      .receive("error", (error: ChannelError) => {
        // Extract error message - try "base" first, then format field-specific errors
        let errorMessage: string;

        if (error.errors["base"]?.[0]) {
          // Use base error if available
          errorMessage = error.errors["base"][0];
        } else {
          // Format field-specific error with field name for context
          const firstField = Object.keys(error.errors)[0];
          const firstError = error.errors[firstField]?.[0];

          if (firstField && firstError) {
            // Capitalize and format field name (e.g., "workflow_name" -> "Workflow name")
            const formattedField = firstField
              .replace(/_/g, " ")
              .replace(/\b\w/g, char => char.toUpperCase());
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
