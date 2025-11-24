import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';

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
   * Priority level for the keyboard shortcuts
   * Higher priority = executes first when multiple handlers registered
   *
   * Recommended values:
   * - 100: MODAL priority
   * - 50: IDE priority
   * - 25: RUN_PANEL priority
   * - 10: PANEL priority
   * - 0: GLOBAL priority
   */
  priority: number;

  /**
   * Whether the shortcuts should be enabled
   * @default true
   */
  enabled?: boolean;
}

/**
 * Custom hook for run/retry keyboard shortcuts using KeyboardProvider
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
 * - Works in form fields and Monaco editor by default
 *
 * @example
 * ```tsx
 * // In ManualRunPanel (standalone mode, priority 25)
 * useRunRetryShortcuts({
 *   onRun: handleRun,
 *   onRetry: handleRetry,
 *   canRun,
 *   isRunning: isSubmitting || runIsProcessing,
 *   isRetryable,
 *   priority: 25, // RUN_PANEL priority
 *   enabled: renderMode === RENDER_MODES.STANDALONE,
 * });
 *
 * // In FullScreenIDE (priority 50)
 * useRunRetryShortcuts({
 *   onRun: handleRun,
 *   onRetry: handleRetry,
 *   canRun,
 *   isRunning: isSubmitting,
 *   isRetryable,
 *   priority: 50, // IDE priority
 * });
 * ```
 */
export function useRunRetryShortcuts({
  onRun,
  onRetry,
  canRun,
  isRunning,
  isRetryable,
  priority,
  enabled = true,
}: UseRunRetryShortcutsOptions): void {
  // Cmd/Ctrl+Enter: Run or Retry based on state
  useKeyboardShortcut(
    'Control+Enter, Meta+Enter',
    () => {
      if (canRun && !isRunning) {
        if (isRetryable) {
          onRetry();
        } else {
          onRun();
        }
      }
    },
    priority,
    { enabled }
  );

  // Cmd/Ctrl+Shift+Enter: Force new work order
  useKeyboardShortcut(
    'Control+Shift+Enter, Meta+Shift+Enter',
    () => {
      if (canRun && !isRunning && isRetryable) {
        // Force new work order even in retry mode
        onRun();
      }
    },
    priority,
    { enabled }
  );
}
