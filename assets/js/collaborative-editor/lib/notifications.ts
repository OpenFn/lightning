import { toast, type ExternalToast } from "sonner";

interface NotificationOptions extends ExternalToast {
  title: string;
  description?: string;
}

/**
 * Notification service for the collaborative editor
 *
 * Provides toast notifications with Lightning's design system styling.
 * All methods return a toast ID that can be used to dismiss programmatically.
 *
 * Usage:
 * ```typescript
 * import { notifications } from "./lib/notifications";
 *
 * // Info notification (2 second duration)
 * notifications.info({
 *   title: "Workflow saved",
 *   description: "All changes have been synced"
 * });
 *
 * // Alert notification (4 second duration)
 * notifications.alert({
 *   title: "Failed to save workflow",
 *   description: "Please check your connection and try again"
 * });
 *
 * // With action button
 * notifications.alert({
 *   title: "Validation error",
 *   description: "Job name cannot be empty",
 *   action: {
 *     label: "Fix",
 *     onClick: () => {
 *       // Handle action
 *     }
 *   }
 * });
 *
 * // Dismiss specific toast
 * const toastId = notifications.info({ title: "Processing..." });
 * notifications.dismiss(toastId);
 *
 * // Dismiss all toasts
 * notifications.dismiss();
 * ```
 */
export const notifications = {
  /**
   * Info notification - for general information and success feedback
   *
   * Blue color scheme with 2 second duration.
   * Auto-dismisses unless user hovers over toast.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  info: ({ title, description, ...options }: NotificationOptions) => {
    return toast.info(title, {
      description,
      duration: 2000, // 2s for info messages
      classNames: {
        toast: "border-l-4 border-blue-500 bg-blue-50",
        title: "text-blue-900 font-semibold",
        description: "text-blue-700 text-sm",
      },
      ...options,
    });
  },

  /**
   * Alert notification - for warnings and errors that need attention
   *
   * Red color scheme with 4 second duration (longer than info for visibility).
   * Auto-dismisses unless user hovers over toast.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  alert: ({ title, description, ...options }: NotificationOptions) => {
    return toast.error(title, {
      description,
      duration: 4000, // 4s for alert messages (need more attention)
      classNames: {
        toast: "border-l-4 border-red-500 bg-red-50",
        title: "text-red-900 font-semibold",
        description: "text-red-700 text-sm",
      },
      ...options,
    });
  },

  /**
   * Success notification - for completed operations
   *
   * Green color scheme with 2 second duration.
   * Currently an alias for info() but can be customized independently.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  success: ({ title, description, ...options }: NotificationOptions) => {
    return toast.success(title, {
      description,
      duration: 2000,
      classNames: {
        toast: "border-l-4 border-green-500 bg-green-50",
        title: "text-green-900 font-semibold",
        description: "text-green-700 text-sm",
      },
      ...options,
    });
  },

  /**
   * Warning notification - for non-critical warnings
   *
   * Amber color scheme with 3 second duration.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  warning: ({ title, description, ...options }: NotificationOptions) => {
    return toast.warning(title, {
      description,
      duration: 3000,
      classNames: {
        toast: "border-l-4 border-amber-500 bg-amber-50",
        title: "text-amber-900 font-semibold",
        description: "text-amber-700 text-sm",
      },
      ...options,
    });
  },

  /**
   * Dismiss a specific toast or all toasts
   *
   * @param toastId - Optional toast ID to dismiss. If omitted, dismisses all toasts.
   */
  dismiss: (toastId?: string | number) => {
    toast.dismiss(toastId);
  },
} as const;

// Export type for consumers
export type Notifications = typeof notifications;
