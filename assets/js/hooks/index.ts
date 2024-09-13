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

export const EnableSelectForSubmission = {
  mounted() {
    this.wasDisabled = this.el.disabled;

    const form = this.el.closest('form');
    if (!form) {
      console.error('No form found');
      return;
    }

    form.addEventListener('submit', () => {
      if (this.wasDisabled) {
        this.el.disabled = false;
        setTimeout(() => {
          this.el.disabled = true;
        }, 0);
      }
    });
  },

  updated() {
    this.wasDisabled = this.el.disabled;
  },
};

export default EnableSelectForSubmission;

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
