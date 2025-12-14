import { submitOrClick } from '../common';

import type { PhoenixHook } from './PhoenixHook';

/**
 * Priority levels for key handlers.
 *
 * This enumeration defines priority levels for keybinding handlers, allowing the application
 * to resolve conflicts when multiple handlers match the same key combination. Handlers with
 * a higher priority value will take precedence over those with lower priority values.
 *
 * ### Values:
 * - `HIGH` (1): Indicates that the handler has a high priority. Handlers with this priority
 *   will take precedence over those with `NORMAL` priority in cases of conflict.
 * - `NORMAL` (0): Indicates that the handler has a normal priority. This is the default
 *   priority for handlers unless specified otherwise.
 *
 * ### Why Priority Levels Are Important:
 * 1. **Conflict Resolution:**
 *    When multiple handlers match the same key combination, the system uses the `priority`
 *    value to determine which handler should execute. This ensures predictable behavior
 *    in cases where keybindings overlap.
 *
 * 2. **Fine-Grained Control:**
 *    Developers can assign priority levels to handlers to explicitly control their
 *    execution order. For example, a high-priority handler can override global handlers
 *    within a specific context.
 *
 * 3. **Readability and Maintainability:**
 *    Using named constants (`HIGH`, `NORMAL`) instead of raw numbers improves code
 *    readability and reduces the likelihood of errors.
 *
 * ### Example Usage:
 * ```typescript
 * const handler1 = createKeyCombinationHook(
 *   isCtrlOrMetaS,
 *   submitAction,
 *   PRIORITY.HIGH // High priority, overrides normal handlers
 * );
 *
 * const handler2 = createKeyCombinationHook(
 *   isEscape,
 *   closeAction,
 *   PRIORITY.NORMAL // Normal priority, default level
 * );
 * ```
 */
enum PRIORITY {
  HIGH = 1,
  NORMAL = 0,
}

/**
 * Alias type for priority levels, ensuring strict typing and consistency.
 *
 * This type ensures that only valid priority values defined in the `PRIORITY` enum
 * can be used in keybinding handlers, preventing accidental use of unsupported values.
 */
type PriorityLevel = PRIORITY;

/**
 * Global registry to track all active key handlers.
 *
 * This `Set` serves as the core mechanism for managing all keybinding handlers in a given page of the app.
 * It ensures that keybinding logic is centralized, making it easier to manage, resolve conflicts, and maintain consistency.
 *
 * ### Structure of a Handler:
 * Each handler is an object with the following properties:
 * - `hook`: The `PhoenixHook` instance where the handler is defined. This provides context for lifecycle management and ensures handlers are correctly removed when hooks are unmounted.
 * - `keyCheck`: A function that determines whether a given `KeyboardEvent` matches the key combination for the handler. This allows flexible and precise matching of keybindings.
 * - `action`: A function that executes when the key combination matches. It receives the `KeyboardEvent` and the associated DOM element (`el`) from the `hook`.
 * - `priority`: A `PriorityLevel` value (e.g., `PRIORITY.HIGH` or `PRIORITY.NORMAL`) used to resolve conflicts when multiple handlers match the same key combination. Handlers with higher priority take precedence.
 * - `bindingScope`: (Optional) A string representing the scope (defined via the `data-keybinding-scope` attribute in the DOM) where the handler should apply. This ensures that keybindings can be context-aware and prevents unintended execution in irrelevant parts of the application.
 *
 * ### Example Usage:
 * ```typescript
 * keyHandlers.add({
 *   hook: this,
 *   keyCheck: (e) => e.ctrlKey && e.key === 's',
 *   action: (e, el) => console.log("Ctrl+S pressed"),
 *   priority: PRIORITY.NORMAL,
 *   bindingScope: 'editor'
 * });
 * ```
 */
const keyHandlers = new Set<{
  hook: any;
  keyCheck: (e: KeyboardEvent) => boolean;
  action: (e: KeyboardEvent, el: HTMLElement) => void;
  priority: PriorityLevel;
  bindingScope?: string | undefined;
}>();

/**
 * Creates a PhoenixHook to listen for specific key combinations and trigger defined actions.
 *
 * This function is used to bind a key combination to a specific action with optional priority and scope.
 * It supports scoped key bindings using the `data-keybinding-scope` attribute and resolves conflicts
 * between overlapping handlers by priority.
 *
 * Example:
 * ```typescript
 * const hook = createKeyCombinationHook(
 *   (e) => e.ctrlKey && e.key === "s",
 *   (e, el) => console.log("Ctrl+S pressed!", el),
 *   PRIORITY.HIGH,
 *   "example-scope"
 * );
 * ```
 *
 * @param keyCheck - A function that determines whether the current key combination matches.
 *                   It should return `true` for matching key events and `false` otherwise.
 * @param action - A function to execute when the key combination is triggered.
 *                 This function receives the `KeyboardEvent` and the hook's associated DOM element (`el`).
 * @param priority - (Optional) The priority of the handler. Higher-priority handlers are executed first.
 *                   Defaults to `PRIORITY.NORMAL`.
 * @param bindingScope - (Optional) A string representing the scope of the handler.
 *                       Handlers with a `bindingScope` only execute within elements with a matching `data-keybinding-scope`.
 *                       Defaults to `undefined`, making the handler global.
 * @returns A PhoenixHook object that manages the keybinding lifecycle.
 */
function createKeyCombinationHook(
  keyCheck: (e: KeyboardEvent) => boolean,
  action: (e: KeyboardEvent, el: HTMLElement) => void,
  priority: PriorityLevel = PRIORITY.NORMAL,
  bindingScope?: string
): PhoenixHook {
  return {
    mounted() {
      const handler = { hook: this, keyCheck, action, priority, bindingScope };
      keyHandlers.add(handler);

      this.abortController = new AbortController();

      this.callback = (e: KeyboardEvent) => {
        if (!keyCheck(e)) return;

        e.preventDefault();

        const target = e.target as HTMLElement;
        const focusedScope =
          target
            ?.closest('[data-keybinding-scope]')
            ?.getAttribute('data-keybinding-scope') || null;

        const keyMatchingHandlers = Array.from(keyHandlers).filter(h =>
          h.keyCheck(e)
        );

        const hasScopedHandlers = keyMatchingHandlers.some(
          h => h.bindingScope === focusedScope
        );

        const matchingHandlers = keyMatchingHandlers.filter(h => {
          if (h.bindingScope) {
            return h.bindingScope === focusedScope;
          } else {
            return !hasScopedHandlers;
          }
        });

        const maxPriority = Math.max(...matchingHandlers.map(h => h.priority));
        const topPriorityHandlers = matchingHandlers.filter(
          h => h.priority === maxPriority
        );

        // Take the last handler if there are more than one with the same priority.
        const lastHandler = topPriorityHandlers[topPriorityHandlers.length - 1];

        if (lastHandler?.hook === this) {
          lastHandler.action(e, this.el);
        }
      };

      window.addEventListener('keydown', this.callback, {
        signal: this.abortController.signal,
      });
    },

    destroyed() {
      keyHandlers.forEach(handler => {
        if (handler.hook === this) {
          keyHandlers.delete(handler);
        }
      });
      this.abortController.abort();
    },
  } as PhoenixHook<{
    callback: (e: KeyboardEvent) => void;
    abortController: AbortController;
  }>;
}

/**
 * Determines if the key combination for "Ctrl+S" (or "Cmd+S" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+S" or "Cmd+S" is pressed, otherwise `false`.
 */
const isCtrlOrMetaS = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.key === 's';

/**
 * Determines if the key combination for "Ctrl+Enter" (or "Cmd+Enter" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+Enter" or "Cmd+Enter" is pressed, otherwise `false`.
 */
const isCtrlOrMetaEnter = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && !e.shiftKey && e.key === 'Enter';

/**
 * Determines if the key combination for "Ctrl+Shift+Enter" (or "Cmd+Shift+Enter" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+Shift+Enter" or "Cmd+Shift+Enter" is pressed, otherwise `false`.
 */
const isCtrlOrMetaShiftEnter = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'Enter';

/**
 * Determines if the key combination for "Ctrl+Shift+S" (or "Cmd+Shift+S" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+Shift+S" or "Cmd+Shift+S" is pressed, otherwise `false`.
 */
const isCtrlOrMetaShiftS = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 's';

/**
 * Determines if the "Escape" key is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if the "Escape" key is pressed, otherwise `false`.
 */
const isEscape = (e: KeyboardEvent) => e.key === 'Escape';

/**
 * Simulates a "click" action, used to trigger save and run functionality.
 * Will skip saving if the element is disabled.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
const clickAction = (_e: KeyboardEvent, el: HTMLElement) => {
  if (el.hasAttribute('disabled')) return;
  submitOrClick(el);
};

/**
 * Simulates a form submission action.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
const submitAction = (_e: KeyboardEvent, el: HTMLElement) => {
  el.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
};

/**
 * Simulates a "close" action, used to close modals, panels, or other UI components.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
const closeAction = (_e: KeyboardEvent, el: HTMLElement) => el.click();

/**
 * Hook to trigger a form submission when "Ctrl+S" (or "Cmd+S" on macOS) is pressed.
 *
 * This hook listens globally and executes the `submitAction`, which simulates form submission.
 * It is commonly used to save a workflow by just using the keybindng CTRL/CMD + S.
 *
 * Priority: `PRIORITY.NORMAL` (default), meaning it can be overridden by higher-priority handlers.
 */
export const SaveViaCtrlS = createKeyCombinationHook(
  isCtrlOrMetaS,
  submitAction
);

export const InspectorSaveViaCtrlS = createKeyCombinationHook(
  isCtrlOrMetaS,
  clickAction
);
/**
 * Hook to open the Github Sync modal when "Ctrl+Shift+S" (or "Cmd+Shift+S" on macOS) is pressed.
 *
 * This hook listens globally and executes the `clickAction`, which sends a click event.
 *
 * Priority: `PRIORITY.NORMAL` (default), meaning it can be overridden by higher-priority handlers.
 */
export const OpenSyncModalViaCtrlShiftS = createKeyCombinationHook(
  isCtrlOrMetaShiftS,
  clickAction,
  PRIORITY.HIGH
);

/**
 * Hook to send a chat message when "Ctrl+Enter" (or "Cmd+Enter" on macOS) is pressed.
 *
 * This hook is scoped to elements with `data-keybinding-scope="chat"`. It executes the
 * `submitAction`, which simulates a form submission for chat input fields.
 *
 * Priority: `PRIORITY.HIGH`, ensuring it takes precedence over other handlers for "Ctrl+Enter".
 * Scope: `"chat"`, meaning this hook is active only within the chat UI.
 */
export const SendMessageViaCtrlEnter = createKeyCombinationHook(
  isCtrlOrMetaEnter,
  submitAction,
  PRIORITY.HIGH,
  'chat'
);

/**
 * Hook to trigger the default "Run" action when "Ctrl+Enter" (or "Cmd+Enter" on macOS) is pressed.
 *
 * This hook listens globally and executes the `clickAction`, typically used to trigger
 * "Run" for a step in a workflow.
 *
 * Priority: `PRIORITY.NORMAL`, meaning it can be overridden by higher-priority handlers.
 */
export const DefaultRunViaCtrlEnter = createKeyCombinationHook(
  isCtrlOrMetaEnter,
  clickAction
);

/**
 * Hook to trigger an alternative "Run" action when "Ctrl+Shift+Enter" (or "Cmd+Shift+Enter" on macOS) is pressed.
 *
 * This hook listens globally and executes the `clickAction`, which can trigger a
 * secondary or alternative execution flow. It is used to create a workorder for an already ran step in a
 * worklflow instead of running it.
 *
 * Priority: `PRIORITY.NORMAL`, meaning it can be overridden by higher-priority handlers.
 */
export const AltRunViaCtrlShiftEnter = createKeyCombinationHook(
  isCtrlOrMetaShiftEnter,
  clickAction
);

/**
 * Hook to close the inspector panel when the "Escape" key is pressed.
 *
 * This hook listens globally and executes the `closeAction`, which simulates a click
 * to close the inspector panel UI. It is assigned a higher priority to ensure it
 * overrides other handlers for the "Escape" key.
 *
 * Priority: `PRIORITY.HIGH`, ensuring it takes precedence over other "Escape" handlers.
 */
export const CloseInspectorPanelViaEscape = createKeyCombinationHook(
  isEscape,
  closeAction,
  PRIORITY.HIGH
);

/**
 * Hook to close a node panel when the "Escape" key is pressed.
 *
 * This hook listens globally and executes the `closeAction`, which simulates a click
 * to close a node panel in the workflow canvas. It has a lower priority, ensuring it does
 * not interfere with higher-priority handlers for the "Escape" key (e.g., `CloseInspectorPanelViaEscape`).
 *
 * Priority: `PRIORITY.NORMAL`, meaning it will yield to higher-priority handlers for the "Escape" key.
 */
export const CloseNodePanelViaEscape = createKeyCombinationHook(
  isEscape,
  closeAction,
  PRIORITY.NORMAL
);

/**
 * Determines if the key combination for "Ctrl+Shift+P" (or "Cmd+Shift+P" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+Shift+P" or "Cmd+Shift+P" is pressed, otherwise `false`.
 */
const isCtrlOrMetaShiftP = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'p';

/**
 * Action to open the project picker modal.
 * Clicks the project picker trigger button to open the modal via Phoenix JS.
 */
const openProjectPickerAction = (_e: KeyboardEvent, _el: HTMLElement) => {
  const trigger = document.getElementById(
    'project-picker-trigger'
  ) as HTMLButtonElement;
  if (trigger) {
    trigger.click();
  }
};

/**
 * Hook to open the project picker when "Ctrl+Shift+P" (or "Cmd+Shift+P" on macOS) is pressed.
 *
 * This hook listens globally and opens the command palette style project picker modal.
 *
 * Priority: `PRIORITY.HIGH`, ensuring it takes precedence over other handlers.
 */
export const OpenProjectPickerViaCtrlShiftP = createKeyCombinationHook(
  isCtrlOrMetaShiftP,
  openProjectPickerAction,
  PRIORITY.HIGH
);

/**
 * Determines if the key combination for "Ctrl+M" (or "Cmd+M" on macOS) is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if "Ctrl+M" or "Cmd+M" is pressed, otherwise `false`.
 */
const isCtrlOrMetaM = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && !e.shiftKey && e.key.toLowerCase() === 'm';

/**
 * Action to toggle the sidebar collapsed state.
 * Clicks the sidebar toggle button to trigger the toggle_sidebar event.
 */
const toggleSidebarAction = (_e: KeyboardEvent, _el: HTMLElement) => {
  // Find and click the sidebar toggle button
  const toggleButton = document.querySelector(
    '[phx-click="toggle_sidebar"]'
  ) as HTMLButtonElement;
  if (toggleButton) {
    toggleButton.click();
  }
};

/**
 * Hook to toggle the sidebar when "Ctrl+M" (or "Cmd+M" on macOS) is pressed.
 *
 * This hook listens globally and toggles the sidebar collapsed/expanded state.
 *
 * Priority: `PRIORITY.HIGH`, ensuring it takes precedence over other handlers.
 */
export const ToggleSidebarViaCtrlM = createKeyCombinationHook(
  isCtrlOrMetaM,
  toggleSidebarAction,
  PRIORITY.HIGH
);
