import { useHotkeys } from 'react-hotkeys-hook';

/**
 * Options for useRunRetryShortcuts hook
 */
export interface UseRunRetryShortcutsOptions {
  /**
   * Handler for run action (creates new work order)
   */
  onRun: () => void;

  /**
   * Handler for retry action (retries with previous input)
   */
  onRetry: () => void;

  /**
   * Whether the run/retry action can be executed
   */
  canRun: boolean;

  /**
   * Whether a run/retry operation is currently in progress
   */
  isRunning: boolean;

  /**
   * Whether retry is available (following a run with matching dataclip)
   */
  isRetryable: boolean;

  /**
   * Whether the shortcuts should be enabled
   * @default true
   */
  enabled?: boolean;

  /**
   * Hotkeys scope (e.g., "ide" for fullscreen IDE)
   * If not provided, shortcuts work globally
   */
  scope?: string;

  /**
   * Whether to enable shortcuts on form elements (input, textarea, select)
   * @default true
   */
  enableOnFormTags?: boolean;

  /**
   * Whether to enable shortcuts on contenteditable elements (Monaco editor)
   * @default false for non-IDE contexts, true for IDE
   */
  enableOnContentEditable?: boolean;
}

/**
 * Custom hook for run/retry keyboard shortcuts
 *
 * Provides two keyboard shortcuts:
 * - **Cmd/Ctrl+Enter**: Run (new work order) OR Retry (same input)
 * - **Cmd/Ctrl+Shift+Enter**: Force new work order (even when retry is available)
 *
 * The shortcuts automatically handle:
 * - Platform differences (Cmd on Mac, Ctrl on Windows/Linux)
 * - Preventing default browser behavior
 * - Checking if action can be executed (canRun, isRunning)
 * - Switching between run and retry based on context
 *
 * @example
 * ```tsx
 * // In ManualRunPanel (standalone mode)
 * useRunRetryShortcuts({
 *   onRun: handleRun,
 *   onRetry: handleRetry,
 *   canRun,
 *   isRunning: isSubmitting || runIsProcessing,
 *   isRetryable,
 *   enabled: renderMode === RENDER_MODES.STANDALONE,
 * });
 *
 * // In IDEHeader (fullscreen IDE)
 * useRunRetryShortcuts({
 *   onRun: handleRun,
 *   onRetry: handleRetry,
 *   canRun,
 *   isRunning: isSubmitting,
 *   isRetryable,
 *   scope: "ide",
 *   enableOnContentEditable: true,
 * });
 * ```
 */
export function useRunRetryShortcuts({
  onRun,
  onRetry,
  canRun,
  isRunning,
  isRetryable,
  enabled = true,
  scope,
  enableOnFormTags = true,
  enableOnContentEditable = false,
}: UseRunRetryShortcutsOptions): void {
  // Cmd/Ctrl+Enter: Run or Retry based on state
  useHotkeys(
    'mod+enter',
    e => {
      e.preventDefault();
      e.stopPropagation(); // Prevent parent handlers from firing

      if (canRun && !isRunning) {
        if (isRetryable) {
          onRetry();
        } else {
          onRun();
        }
      }
    },
    {
      enabled,
      scopes: scope ? [scope] : [],
      enableOnFormTags,
      enableOnContentEditable,
    }
  );

  // Cmd/Ctrl+Shift+Enter: Force new work order
  useHotkeys(
    'mod+shift+enter',
    e => {
      e.preventDefault();
      e.stopPropagation();

      if (canRun && !isRunning && isRetryable) {
        // Force new work order even in retry mode
        onRun();
      }
    },
    {
      enabled,
      scopes: scope ? [scope] : [],
      enableOnFormTags,
      enableOnContentEditable,
    }
  );
}
