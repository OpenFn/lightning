import { toast, type ExternalToast } from 'sonner';

interface NotificationOptions extends ExternalToast {
  title: string;
  description?: React.ReactNode;
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
 *
 * Architecture:
 * - Styling & durations: THIS FILE (notifications.ts)
 * - Container setup: Toaster.tsx (position, close button)
 *
 * All toast styling is self-contained here using Tailwind classes with !important
 * to override Sonner's defaults. This keeps everything in one place.
 */
export const notifications = {
  /**
   * Info notification - for general information and success feedback
   *
   * Blue color scheme with 3 second duration.
   * Auto-dismisses unless user hovers over toast.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  info: ({ title, description, ...options }: NotificationOptions) => {
    return toast.info(title, {
      description,
      duration: 3000, // 3s for info messages
      classNames: {
        toast: '!bg-blue-50 !border-l-4 !border-l-blue-500',
        title: '!text-blue-900 !font-semibold',
        description: '!text-blue-700 !text-sm',
        icon: '!text-blue-500',
      },
      ...options,
    });
  },

  /**
   * Alert notification - for warnings and errors that need attention
   *
   * Red color scheme with 6 second duration (longer than info for visibility).
   * Auto-dismisses unless user hovers over toast.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  alert: ({ title, description, ...options }: NotificationOptions) => {
    return toast.error(title, {
      description,
      duration: 6000, // 6s for alert messages (need more attention)
      classNames: {
        toast: '!bg-red-50 !border-l-4 !border-l-red-500',
        title: '!text-red-900 !font-semibold',
        description: '!text-red-700 !text-sm',
        icon: '!text-red-500',
      },
      ...options,
    });
  },

  /**
   * Success notification - for completed operations
   *
   * Green color scheme with 3 second duration.
   * Currently an alias for info() but can be customized independently.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  success: ({ title, description, ...options }: NotificationOptions) => {
    return toast.success(title, {
      description,
      duration: 3000,
      classNames: {
        toast: '!bg-green-50 !border-l-4 !border-l-green-500',
        title: '!text-green-900 !font-semibold',
        description: '!text-green-700 !text-sm',
        icon: '!text-green-500',
      },
      ...options,
    });
  },

  /**
   * Warning notification - for non-critical warnings
   *
   * Amber color scheme with 6 second duration.
   *
   * @param options - Notification configuration
   * @returns Toast ID for programmatic dismissal
   */
  warning: ({ title, description, ...options }: NotificationOptions) => {
    return toast.warning(title, {
      description,
      duration: 6000,
      classNames: {
        toast: '!bg-amber-50 !border-l-4 !border-l-amber-500',
        title: '!text-amber-900 !font-semibold',
        description: '!text-amber-700 !text-sm',
        icon: '!text-amber-500',
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
