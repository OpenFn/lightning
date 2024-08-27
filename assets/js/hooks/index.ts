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

export const Combobox = {
  mounted() {
    this.input = this.el.querySelector('input');
    this.dropdown = this.el.querySelector('ul');
    this.options = this.el.querySelectorAll('li');
    this.toggleButton = this.el.querySelector('button');

    this.input.addEventListener(
      'input',
      this.debounce(event => this.handleInput(event), 300)
    );
    this.input.addEventListener('click', () => this.handleInputClick());
    this.toggleButton.addEventListener('click', () => this.toggleDropdown());

    this.options.forEach(option => {
      option.addEventListener('click', event => {
        event.preventDefault();
        this.selectOption(option);
      });
    });

    document.addEventListener('click', event => {
      if (!this.el.contains(event.target)) {
        this.hideDropdown();
      }
    });
  },

  handleInput(event) {
    this.filterOptions(event);
    this.showDropdown();
  },

  handleInputClick() {
    this.input.select(); // Highlight all text
    this.showAllOptions();
    this.showDropdown();
  },

  toggleDropdown() {
    if (this.dropdown.classList.contains('hidden')) {
      this.showDropdown();
    } else {
      this.hideDropdown();
    }
  },

  showDropdown() {
    this.dropdown.classList.remove('hidden');
    this.input.setAttribute('aria-expanded', 'true');
  },

  hideDropdown() {
    this.dropdown.classList.add('hidden');
    this.input.setAttribute('aria-expanded', 'false');
  },

  filterOptions(event) {
    const searchTerm = event.target.value.toLowerCase();
    let visibleCount = 0;

    this.options.forEach(option => {
      const text = option.textContent.toLowerCase();
      if (text.includes(searchTerm)) {
        option.style.display = 'block';
        visibleCount++;
      } else {
        option.style.display = 'none';
      }
    });

    if (visibleCount === 0) {
      this.showNoResultsMessage();
    } else {
      this.hideNoResultsMessage();
    }
  },

  showAllOptions() {
    this.options.forEach(option => (option.style.display = 'block'));
    this.hideNoResultsMessage();
  },

  showNoResultsMessage() {
    let noResultsEl = this.dropdown.querySelector('.no-results');
    if (!noResultsEl) {
      noResultsEl = document.createElement('li');
      noResultsEl.className =
        'no-results text-gray-500 py-2 px-3 text-sm cursor-default';
      noResultsEl.textContent = 'No projects found';
      this.dropdown.appendChild(noResultsEl);
    }
    noResultsEl.style.display = 'block';
  },

  hideNoResultsMessage() {
    const noResultsEl = this.dropdown.querySelector('.no-results');
    if (noResultsEl) {
      noResultsEl.style.display = 'none';
    }
  },

  selectOption(option) {
    this.input.value = option.querySelector('span').textContent.trim();
    this.hideDropdown();
    this.navigateToItem(option.dataset.url);
  },

  navigateToItem(url) {
    window.location.href = url;
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
 * Function to dispatch a click event on the provided element.
 *
 * @param e - The keyboard event triggering the action.
 * @param el - The HTML element to which the action will be applied.
 */
function clickAction(e: KeyboardEvent, el: HTMLElement) {
  initiateSaveAndRun(el);
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
  (e.ctrlKey || e.metaKey) && !e.shiftKey && e.key === 'Enter';

const isCtrlOrMetaShiftEnter = (e: KeyboardEvent) =>
  (e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'Enter';

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
export const DefaultRunViaCtrlEnter = createKeyCombinationHook(
  isCtrlOrMetaEnter,
  clickAction
);

export const AltRunViaCtrlShiftEnter = createKeyCombinationHook(
  isCtrlOrMetaShiftEnter,
  clickAction
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
