import tippy, { Instance as TippyInstance } from 'tippy.js';
import { PhoenixHook } from './PhoenixHook';

import LogLineHighlight from './LogLineHighlight';
import ElapsedIndicator from './ElapsedIndicator';
import {
  TabbedContainer,
  TabbedSelector,
  TabbedPanels,
} from './TabbedContainer';
import { initiateSaveAndRun } from '../common';

export {
  LogLineHighlight,
  ElapsedIndicator,
  TabbedContainer,
  TabbedSelector,
  TabbedPanels,
};

export const TabIndent = {
  mounted() {
    this.el.addEventListener('keydown', e => {
      const indent = '\t';

      if (e.key === 'Tab') {
        e.preventDefault();

        const start = this.el.selectionStart;
        const end = this.el.selectionEnd;

        this.el.value =
          this.el.value.substring(0, start) +
          indent +
          this.el.value.substring(end);

        this.el.selectionStart = this.el.selectionEnd = start + indent.length;
      }
    });
  },
};

export const Combobox = {
  mounted() {
    this.input = this.el.querySelector('input');
    this.dropdown = this.el.querySelector('ul');
    this.options = Array.from(this.el.querySelectorAll('li'));
    this.toggleButton = this.el.querySelector('button');
    this.highlightedIndex = -1;
    this.navigatingWithKeys = false;
    this.navigatingWithMouse = false;

    this.input.addEventListener('focus', () => this.handleInputFocus());
    this.input.addEventListener(
      'input',
      this.debounce(e => this.handleInput(e), 300)
    );
    this.input.addEventListener('keydown', e => this.handleKeydown(e));
    this.toggleButton.addEventListener('click', () => this.toggleDropdown());

    this.options.forEach((option, index) => {
      option.addEventListener('click', () =>
        this.selectOption(this.options.indexOf(option))
      );
      option.addEventListener('mouseenter', () => this.handleMouseEnter(index));
      option.addEventListener('mousemove', () => this.handleMouseMove(index));
    });

    document.addEventListener('click', e => {
      if (!this.el.contains(e.target)) this.hideDropdown();
    });

    this.initializeSelectedOption();
  },

  handleInputFocus() {
    this.showDropdown();
    this.input.select();
  },

  handleInput(event) {
    this.filterOptions(event.target.value);
    this.showDropdown();
    this.highlightFirstMatch();
    this.navigatingWithKeys = false;
    this.navigatingWithMouse = false;
  },

  handleKeydown(event) {
    if (!this.isDropdownVisible()) {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        this.showDropdown();
      }
      return;
    }

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.navigatingWithKeys = true;
        this.navigatingWithMouse = false;
        this.highlightNextOption();
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.navigatingWithKeys = true;
        this.navigatingWithMouse = false;
        this.highlightPreviousOption();
        break;
      case 'Enter':
        event.preventDefault();
        if (this.highlightedIndex !== -1) {
          const visibleOptions = this.getVisibleOptions();
          const selectedOptionIndex = this.options.indexOf(
            visibleOptions[this.highlightedIndex]
          );
          this.selectOption(selectedOptionIndex);
        }
        break;
      case 'Escape':
        this.hideDropdown();
        break;
    }
  },

  handleMouseEnter(index) {
    if (!this.navigatingWithKeys) {
      this.navigatingWithMouse = true;
      this.highlightOption(index);
    }
  },

  handleMouseMove(index) {
    if (this.navigatingWithKeys) {
      this.navigatingWithKeys = false;
      this.navigatingWithMouse = true;
      this.highlightOption(index);
    }
  },

  filterOptions(searchTerm) {
    const lowercaseSearchTerm = searchTerm.toLowerCase();
    let hasVisibleOptions = false;

    this.options.forEach(option => {
      const text = option.textContent.toLowerCase();
      if (text.includes(lowercaseSearchTerm)) {
        option.style.display = 'block';
        hasVisibleOptions = true;
      } else {
        option.style.display = 'none';
      }
    });

    this.updateNoResultsMessage(!hasVisibleOptions);
    return hasVisibleOptions;
  },

  highlightFirstMatch() {
    const visibleOptions = this.getVisibleOptions();
    if (visibleOptions.length > 0) {
      this.highlightedIndex = 0;
      this.updateHighlight();
    } else {
      this.highlightedIndex = -1;
      this.updateHighlight();
    }
  },

  updateNoResultsMessage(show) {
    let noResultsEl = this.dropdown.querySelector('.no-results');
    if (show) {
      if (!noResultsEl) {
        noResultsEl = document.createElement('li');
        noResultsEl.className =
          'no-results text-gray-500 py-2 px-3 text-sm cursor-default';
        noResultsEl.textContent = 'No results found';
        this.dropdown.appendChild(noResultsEl);
      }
      noResultsEl.style.display = 'block';
    } else if (noResultsEl) {
      noResultsEl.style.display = 'none';
    }
  },

  getVisibleOptions() {
    return this.options.filter(option => option.style.display !== 'none');
  },

  highlightNextOption() {
    const visibleOptions = this.getVisibleOptions();
    if (visibleOptions.length === 0) return;
    this.highlightedIndex = (this.highlightedIndex + 1) % visibleOptions.length;
    this.updateHighlight();
  },

  highlightPreviousOption() {
    const visibleOptions = this.getVisibleOptions();
    if (visibleOptions.length === 0) return;
    this.highlightedIndex =
      (this.highlightedIndex - 1 + visibleOptions.length) %
      visibleOptions.length;
    this.updateHighlight();
  },

  updateHighlight() {
    const visibleOptions = this.getVisibleOptions();
    visibleOptions.forEach((option, index) => {
      if (index === this.highlightedIndex) {
        option.setAttribute('data-highlighted', 'true');
        if (this.navigatingWithKeys) {
          option.scrollIntoView({ block: 'nearest' });
        }
      } else {
        option.removeAttribute('data-highlighted');
      }
    });
  },

  highlightOption(index) {
    const visibleOptions = this.getVisibleOptions();
    this.highlightedIndex = visibleOptions.indexOf(this.options[index]);
    this.updateHighlight();
  },

  selectOption(index) {
    const selectedOption = this.options[index];

    if (selectedOption && selectedOption.style.display !== 'none') {
      this.input.value = selectedOption.textContent.trim();
      this.hideDropdown();
      this.navigateToItem(selectedOption.dataset.url);
    }
  },

  navigateToItem(url) {
    if (url) {
      window.location.href = url;
    }
  },

  toggleDropdown() {
    if (this.isDropdownVisible()) {
      this.hideDropdown();
    } else {
      this.showDropdown();
    }
  },

  showDropdown() {
    this.dropdown.classList.remove('hidden');
    this.scrollToSelectedOption();
    if (this.highlightedIndex === -1) {
      this.highlightedIndex = this.getSelectedOptionIndex();
      this.updateHighlight();
    }
  },

  hideDropdown() {
    this.dropdown.classList.add('hidden');
    this.highlightedIndex = -1;
    this.navigatingWithKeys = false;
    this.navigatingWithMouse = false;
  },

  isDropdownVisible() {
    return !this.dropdown.classList.contains('hidden');
  },

  initializeSelectedOption() {
    const selectedOptionIndex = this.getSelectedOptionIndex();
    if (selectedOptionIndex !== -1) {
      this.input.value = this.options[selectedOptionIndex].textContent.trim();
    }
  },

  getSelectedOptionIndex() {
    return this.options.findIndex(option =>
      option.hasAttribute('data-item-selected')
    );
  },

  scrollToSelectedOption() {
    const selectedOptionIndex = this.getSelectedOptionIndex();
    if (selectedOptionIndex !== -1) {
      this.options[selectedOptionIndex].scrollIntoView({ block: 'nearest' });
    }
  },

  debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  },
};

export const OpenAuthorizeUrl = {
  mounted() {
    this.handleEvent('open_authorize_url', ({ url }: { url: string }) => {
      window.open(url, '_blank');
    });
  },
} as PhoenixHook;

export const EditScope = {
  mounted() {
    this.el.addEventListener('dblclick', _e => {
      const scopeValue = this.el.dataset.scope;
      const eventType = this.el.dataset.eventType;
      this.pushEventTo(this.el, eventType, { scope: scopeValue });
    });
  },
} as PhoenixHook<{}, { scope: string; eventType: string }>;

export const ClearInput = {
  mounted() {
    this.handleEvent('clear_input', () => {
      this.el.value = '';
    });
  },
} as PhoenixHook<{}, {}, HTMLInputElement>;

export const ModalHook = {
  mounted() {
    this.handleEvent('close_modal', () => {
      this.liveSocket.execJS(this.el, this.el.getAttribute('phx-on-close'));
    });
  },
} as PhoenixHook;

export const ShowActionsOnRowHover = {
  mounted() {
    this.el.addEventListener('mouseenter', e => {
      let target = this.el.querySelector('.hover-content');
      if (target) target.style.opacity = '1';
    });

    this.el.addEventListener('mouseleave', e => {
      let target = this.el.querySelector('.hover-content');
      if (target) target.style.opacity = '0';
    });
  },
} as PhoenixHook;

export const Flash = {
  mounted() {
    let hide = () =>
      this.liveSocket.execJS(this.el, this.el.getAttribute('phx-click'));
    this.timer = setTimeout(() => hide(), 5000);
    this.el.addEventListener('phx:hide-start', () => clearTimeout(this.timer));
    this.el.addEventListener('mouseover', () => {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => hide(), 5000);
    });
  },
  destroyed() {
    clearTimeout(this.timer);
  },
} as PhoenixHook<{ timer: ReturnType<typeof setTimeout> }>;

export const FragmentMatch = {
  mounted() {
    if (this.el.id != '' && `#${this.el.id}` == window.location.hash) {
      let js = this.el.getAttribute('phx-fragment-match');
      if (js === null) {
        console.warn(
          'Fragment element missing phx-fragment-match attribute',
          this.el
        );
        return;
      }
      this.liveSocket.execJS(this.el, js);
    }
  },
} as PhoenixHook;

export const TogglePassword = {
  mounted() {
    if (this.el.dataset.target === undefined) {
      console.warn('Toggle element missing data-target attribute', this.el);
      return;
    }

    this.el.addEventListener('click', () => {
      let passwordInput = document.getElementById(this.el.dataset.target);

      if (passwordInput === null) {
        console.warn('Target password input element was not found', this.el);
        return;
      }

      if (passwordInput.type === 'password') {
        passwordInput.type = 'text';
      } else {
        passwordInput.type = 'password';
      }

      let thenJS = this.el.getAttribute('phx-then');
      if (thenJS) {
        this.liveSocket.execJS(this.el, thenJS);
      }
    });
  },
} as PhoenixHook;

export const Tooltip = {
  mounted() {
    if (!this.el.ariaLabel) {
      console.warn('Tooltip element missing aria-label attribute', this.el);
      return;
    }

    let content = this.el.ariaLabel;
    let placement = this.el.dataset.placement
      ? this.el.dataset.placement
      : 'top';
    let allowHTML = this.el.dataset.allowHtml
      ? this.el.dataset.allowHtml
      : 'false';
    this._tippyInstance = tippy(this.el, {
      placement: placement,
      animation: false,
      allowHTML: allowHTML === 'true',
      interactive: true,
    });
    this._tippyInstance.setContent(content);
  },
  updated() {
    let content = this.el.ariaLabel;
    if (content && this._tippyInstance) {
      this._tippyInstance.setContent(content);
    }
  },
  destroyed() {
    if (this._tippyInstance) this._tippyInstance.unmount();
  },
} as PhoenixHook<{ _tippyInstance: TippyInstance | null }>;

export const AssocListChange = {
  mounted() {
    this.el.addEventListener('change', _event => {
      this.pushEventTo(this.el, 'select_item', { id: this.el.value });
    });
  },
} as PhoenixHook<{}, {}, HTMLSelectElement>;

export const CollapsiblePanel = {
  mounted() {
    this.el.addEventListener('click', event => {
      const target = event.target as HTMLElement;

      // If the click target smells like a link, expand the panel.
      if (target.closest('a[href]')) {
        target
          .closest('.collapsed')
          ?.dispatchEvent(new Event('expand-panel', { bubbles: true }));
      }
    });

    this.el.addEventListener('collapse', event => {
      const target = event.target;
      if (target) {
        const collection = this.el.getElementsByClassName('collapsed');
        if (collection.length < 2) {
          target.classList.add('collapsed');
        }
      }
    });

    this.el.addEventListener('expand-panel', event => {
      event.target.classList.remove('collapsed');
    });
  },
} as PhoenixHook;

export const BlurDataclipEditor = {
  mounted() {
    this.el.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        document.activeElement.blur();
        event.stopImmediatePropagation();
      }
    });
  },
} as PhoenixHook;

export const ScrollToBottom = {
  mounted() {
    this.scrollToLastElement();
  },
  updated() {
    this.scrollToLastElement();
  },
  scrollToLastElement() {
    this.el.lastElementChild &&
      this.el.lastElementChild.scrollIntoView({
        behavior: 'smooth',
        block: 'start',
      });
  },
} as PhoenixHook<{ scrollToLastElement: () => void }>;

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
  NORMAL = 0
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
  bindingScope?: string;
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

      this.callback = (e: KeyboardEvent) => {
        if (!keyCheck(e)) return;

        e.preventDefault();

        const target = e.target as HTMLElement;
        const focusedScope =
          target?.closest('[data-keybinding-scope]')?.getAttribute('data-keybinding-scope') || null;

        const keyMatchingHandlers = Array.from(keyHandlers).filter(h => h.keyCheck(e));

        const hasScopedHandlers = keyMatchingHandlers.some(h => h.bindingScope === focusedScope);

        const matchingHandlers = keyMatchingHandlers
          .filter(h => {
            if (h.bindingScope) {
              return h.bindingScope === focusedScope;
            } else {
              return !hasScopedHandlers;
            }
          })
          .sort((a, b) => b.priority - a.priority);

        const topHandler = matchingHandlers[0];
        if (topHandler?.hook === this) {
          topHandler.action(e, this.el);
        }
      };

      window.addEventListener('keydown', this.callback);
    },

    destroyed() {
      keyHandlers.forEach(handler => {
        if (handler.hook === this) {
          keyHandlers.delete(handler);
        }
      });
      window.removeEventListener('keydown', this.callback);
    }
  } as PhoenixHook<{
    callback: (e: KeyboardEvent) => void;
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
 * Determines if the "Escape" key is pressed.
 *
 * @param e - The keyboard event to evaluate.
 * @returns `true` if the "Escape" key is pressed, otherwise `false`.
 */
const isEscape = (e: KeyboardEvent) => e.key === 'Escape';

/**
 * Simulates a "click" action, used to trigger save and run functionality.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
function clickAction(e: KeyboardEvent, el: HTMLElement) {
  initiateSaveAndRun(el);
}

/**
 * Simulates a form submission action.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
function submitAction(e: KeyboardEvent, el: HTMLElement) {
  el.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
}

/**
 * Simulates a "close" action, used to close modals, panels, or other UI components.
 *
 * @param e - The keyboard event that triggered the action.
 * @param el - The DOM element associated with the hook.
 */
function closeAction(e: KeyboardEvent, el: HTMLElement) {
  el.click();
}

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

export const Copy = {
  mounted() {
    let { to } = this.el.dataset;
    const phxThenAttribute = this.el.getAttribute('phx-then');
    this.el.addEventListener('click', ev => {
      ev.preventDefault();
      let text = document.querySelector(to).value;
      let element = this.el;
      navigator.clipboard.writeText(text).then(() => {
        console.log('Copied!');
        if (phxThenAttribute == null) {
          let originalText = element.textContent;
          element.textContent = 'Copied!';
          setTimeout(function () {
            element.textContent = originalText;
          }, 3000);
        } else {
          this.liveSocket.execJS(this.el, phxThenAttribute);
        }
      });
    });
  },
} as PhoenixHook<{}, { to: string }>;

// Sets the checkbox to indeterminate state if the element has the
// `indeterminate` class
export const CheckboxIndeterminate = {
  mounted() {
    this.el.indeterminate = this.el.classList.contains('indeterminate');
  },
  updated() {
    this.el.indeterminate = this.el.classList.contains('indeterminate');
  },
} as PhoenixHook;
