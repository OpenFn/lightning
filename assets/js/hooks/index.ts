import tippy, { Instance as TippyInstance } from 'tippy.js';
import { PhoenixHook } from './PhoenixHook';

import LogLineHighlight from './LogLineHighlight';
import ElapsedIndicator from './ElapsedIndicator';
import TabSelector from './TabSelector';

export { LogLineHighlight, ElapsedIndicator, TabSelector };

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
    this._tippyInstance = tippy(this.el, {
      content: content,
      placement: placement,
      animation: false,
    });
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

export const collapsiblePanel = {
  mounted() {
    this.el.addEventListener('collapse', event => {
      const target = event.target;
      const collection = document.getElementsByClassName('collapsed');
      if (collection.length < 2) {
        target.classList.toggle('collapsed');
      }
      document.dispatchEvent(new Event('update-layout'));
    });

    this.el.addEventListener('expand-panel', event => {
      const target = event.target;
      target.classList.toggle('collapsed');
      document.dispatchEvent(new Event('update-layout'));
    });
  },
} as PhoenixHook;

/**
 * Factory function to create a hook for listening to specific key combinations.
 *
 * @param keyCheck - Function to check if a keyboard event matches the desired key combination.
 * @param action - Action function to be executed when the keyCheck condition is satisfied.
 * @returns - A PhoenixHook with mounted and destroyed lifecycles.
 */
function createKeyCombinationHook(
  keyCheck: (e: KeyboardEvent) => boolean,
  action: (e: KeyboardEvent, el: HTMLElement) => void
): PhoenixHook {
  return {
    mounted() {
      this.callback = (e: KeyboardEvent) => {
        if (keyCheck(e)) {
          e.preventDefault();
          action(e, this.el);
        }
      };
      window.addEventListener('keydown', this.callback);
    },
    destroyed() {
      window.removeEventListener('keydown', this.callback);
    },
  } as PhoenixHook<{
    callback: (e: KeyboardEvent) => void;
  }>;
}

/**
 * Function to dispatch a submit event on the provided element.
 *
 * @param e - The keyboard event triggering the action.
 * @param el - The HTML element to which the action will be applied.
 */
function submitAction(e: KeyboardEvent, el: HTMLElement) {
  el.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
}

/**
 * Function to simulate a click event on the provided element.
 *
 * @param e - The keyboard event triggering the action.
 * @param el - The HTML element to which the action will be applied.
 */
function closeAction(e: KeyboardEvent, el: HTMLElement) {
  el.click();
}

const isCtrlOrMetaS = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.key === 's';
const isCtrlOrMetaEnter = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.key === 'Enter';
const isEscape = (e: KeyboardEvent) => e.key === 'Escape';

/**
 * Hook to trigger a save action on the job panel when the Ctrl (or Cmd on Mac) + 's' key combination is pressed.
 */
export const SaveViaCtrlS = createKeyCombinationHook(
  isCtrlOrMetaS,
  submitAction
);

/**
 * Hook to trigger a save and run action on the job panel when the Ctrl (or Cmd on Mac) + Enter key combination is pressed.
 */
export const SaveAndRunViaCtrlEnter = createKeyCombinationHook(
  isCtrlOrMetaEnter,
  submitAction
);

/**
 * Hook to trigger a close action on the job panel when the Escape key is pressed.
 */
export const ClosePanelViaEscape = createKeyCombinationHook(
  isEscape,
  closeAction
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
