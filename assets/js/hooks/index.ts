import { format, formatRelative } from 'date-fns';
import { enUS } from 'date-fns/locale';
import tippy, {
  type Instance as TippyInstance,
  type Placement,
} from 'tippy.js';

import TemplateToWorkflow from '../yaml/TemplateToWorkflow';
import WorkflowToYAML from '../yaml/WorkflowToYAML';
import YAMLToWorkflow from '../yaml/YAMLToWorkflow';

import CredentialSelector from './CredentialSelector';
import ElapsedIndicator from './ElapsedIndicator';
import FileDropzone from './FileDropzone';
import {
  SaveViaCtrlS,
  InspectorSaveViaCtrlS,
  OpenSyncModalViaCtrlShiftS,
  SendMessageViaCtrlEnter,
  DefaultRunViaCtrlEnter,
  AltRunViaCtrlShiftEnter,
  CloseInspectorPanelViaEscape,
  CloseNodePanelViaEscape,
  ToggleSidebarViaCtrlM,
  OpenProjectPickerViaCtrlP,
} from './KeyHandlers';
import LogLineHighlight from './LogLineHighlight';
import type { PhoenixHook } from './PhoenixHook';
import {
  TabbedContainer,
  TabbedSelector,
  TabbedPanels,
} from './TabbedContainer';

export {
  LogLineHighlight,
  WorkflowToYAML,
  YAMLToWorkflow,
  TemplateToWorkflow,
  ElapsedIndicator,
  TabbedContainer,
  TabbedSelector,
  TabbedPanels,
  SaveViaCtrlS,
  InspectorSaveViaCtrlS,
  OpenSyncModalViaCtrlShiftS,
  SendMessageViaCtrlEnter,
  DefaultRunViaCtrlEnter,
  AltRunViaCtrlShiftEnter,
  CloseInspectorPanelViaEscape,
  CloseNodePanelViaEscape,
  ToggleSidebarViaCtrlM,
  OpenProjectPickerViaCtrlP,
  FileDropzone,
  CredentialSelector,
};

export { ReactComponent, HeexReactComponent } from '#/react/hooks';

export const TabIndent = {
  mounted() {
    this.el.addEventListener('keydown', e => {
      const indent = '\t';

      if (e.key === 'Tab') {
        e.preventDefault();

        const start = this.el.selectionStart;
        const end = this.el.selectionEnd;

        if (start == null || end == null) return;

        this.el.value =
          this.el.value.substring(0, start) +
          indent +
          this.el.value.substring(end);

        this.el.selectionStart = this.el.selectionEnd = start + indent.length;
      }
    });
  },
} as PhoenixHook<{}, {}, HTMLInputElement>;

export const Combobox = {
  mounted() {
    this.input = this.el.querySelector('input')!;
    this.dropdown = this.el.querySelector('ul')!;
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
    this.toggleButton?.addEventListener('click', () => this.toggleDropdown());

    this.options.forEach((option, index) => {
      option.addEventListener('click', () =>
        this.selectOption(this.options.indexOf(option))
      );
      option.addEventListener('mouseenter', () => this.handleMouseEnter(index));
      option.addEventListener('mousemove', () => this.handleMouseMove(index));
    });

    document.addEventListener('click', e => {
      if (!(e.target instanceof Node) && e.target !== null) return;
      if (!this.el.contains(e.target)) this.hideDropdown();
    });

    this.initializeSelectedOption();
  },

  handleInputFocus() {
    this.showDropdown();
    this.input.select();
  },

  handleInput(event: Event) {
    if (!(event.target instanceof HTMLInputElement)) return;
    this.filterOptions(event.target.value);
    this.showDropdown();
    this.highlightFirstMatch();
    this.navigatingWithKeys = false;
    this.navigatingWithMouse = false;
  },

  handleKeydown(event: KeyboardEvent) {
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

  handleMouseEnter(index: number) {
    if (!this.navigatingWithKeys) {
      this.navigatingWithMouse = true;
      this.highlightOption(index);
    }
  },

  handleMouseMove(index: number) {
    if (this.navigatingWithKeys) {
      this.navigatingWithKeys = false;
      this.navigatingWithMouse = true;
      this.highlightOption(index);
    }
  },

  filterOptions(searchTerm: string) {
    const lowercaseSearchTerm = searchTerm.toLowerCase();
    let hasVisibleOptions = false;

    this.options.forEach(option => {
      const text = (option.textContent ?? '').toLowerCase();
      if (text.includes(lowercaseSearchTerm)) {
        option.style.display = '';
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

  updateNoResultsMessage(show: boolean) {
    let noResultsEl = this.dropdown.querySelector<HTMLElement>('.no-results');
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

  highlightOption(index: number) {
    const visibleOptions = this.getVisibleOptions();
    this.highlightedIndex = visibleOptions.indexOf(this.options[index]);
    this.updateHighlight();
  },

  selectOption(index: number) {
    const selectedOption = this.options[index];

    if (selectedOption && selectedOption.style.display !== 'none') {
      this.input.value = (selectedOption.textContent ?? '').trim();
      this.hideDropdown();
      this.navigateToItem(selectedOption.dataset.url);
    }
  },

  navigateToItem(url?: string) {
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
      this.input.value = (
        this.options[selectedOptionIndex].textContent ?? ''
      ).trim();
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

  debounce<E extends Event>(
    func: (event: E) => void,
    wait: number
  ): (event: E) => void {
    let timeout = 0;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  },
} as PhoenixHook<{
  input: HTMLInputElement;
  dropdown: HTMLUListElement;
  options: HTMLLIElement[];
  toggleButton: HTMLButtonElement;
  highlightedIndex: number;
  navigatingWithKeys: boolean;
  navigatingWithMouse: boolean;
  handleInputFocus(): void;
  handleInput(event: Event): void;
  handleKeydown(event: KeyboardEvent): void;
  handleMouseEnter(index: number): void;
  handleMouseMove(index: number): void;
  filterOptions(searchTerm: string): boolean;
  highlightFirstMatch(): void;
  updateNoResultsMessage(show: boolean): void;
  getVisibleOptions(): HTMLLIElement[];
  highlightNextOption(): void;
  highlightPreviousOption(): void;
  updateHighlight(): void;
  highlightOption(index: number): void;
  selectOption(index: number): void;
  navigateToItem(url?: string): void;
  toggleDropdown(): void;
  showDropdown(): void;
  hideDropdown(): void;
  isDropdownVisible(): boolean;
  initializeSelectedOption(): void;
  getSelectedOptionIndex(): number;
  scrollToSelectedOption(): void;
  debounce<E extends Event>(
    func: (event: E) => void,
    wait: number
  ): (event: E) => void;
}>;

export const OpenAuthorizeUrl = {
  mounted() {
    this.handleEvent<{ url: string }>('open_authorize_url', ({ url }) => {
      window.open(url, 'oauth_authorization');
    });
  },
} as PhoenixHook;

export const TagInput = {
  mounted() {
    this.container = this.el;
    this.textInput = document.getElementById(this.el.dataset.textEl);
    this.hiddenInput = document.getElementById(this.el.dataset.hiddenEl);
    this.tagList = document.getElementById(this.el.dataset.tagList);

    if (!this.textInput) {
      console.error('TagInput: textInput element not found.', {
        textInput: this.textInput,
      });
      return;
    }
    if (!this.hiddenInput) {
      console.error('TagInput: hiddenInput element not found.', {
        hiddenInput: this.hiddenInput,
      });
      return;
    }
    if (!this.tagList) {
      console.error('TagInput: tagList element not found.', {
        tagList: this.tagList,
      });
      return;
    }

    this.isInForm = !!this.el.closest('form[phx-change]');

    this.setupTextInputEvents();
    this.setupTagListEvents();
  },

  setupTextInputEvents() {
    this.textInput.addEventListener('keydown', e => {
      if (e.key === ',' || e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault();
        this.addTag();
      }
    });

    this.textInput.addEventListener('blur', () => {
      this.addTag();
    });
  },

  setupTagListEvents() {
    this.tagList.addEventListener('click', e => {
      const button = e.target.closest('button');
      if (!button) return;

      const tagSpan = button.closest('span[data-tag]');
      if (!tagSpan) return;

      const tagToRemove = tagSpan.dataset.tag;
      this.removeTag(tagToRemove);
    });

    this.tagList.addEventListener('dblclick', e => {
      const tagSpan = e.target.closest('span[data-tag]');
      if (!tagSpan) return;

      const tagToEdit = tagSpan.dataset.tag;
      this.editTag(tagToEdit);
    });
  },

  addTag() {
    const value = this.textInput.value.trim();
    if (!value) return;

    const cleanValue = value.replace(/,+$/, '');
    if (!cleanValue) return;

    const currentTags = this.getCurrentTags();

    const newTags = cleanValue
      .split(',')
      .map(tag => tag.trim())
      .filter(tag => tag !== '');

    for (const tag of newTags) {
      if (!currentTags.includes(tag)) {
        currentTags.push(tag);
      }
    }

    currentTags.sort();
    this.updateTags(currentTags);
    this.textInput.value = '';
  },

  removeTag(tagToRemove) {
    const currentTags = this.getCurrentTags();
    const updatedTags = currentTags.filter(tag => tag !== tagToRemove);
    this.updateTags(updatedTags);
  },

  editTag(tagToEdit) {
    const currentTags = this.getCurrentTags();
    const updatedTags = currentTags.filter(tag => tag !== tagToEdit);

    this.updateTags(updatedTags);

    this.textInput.focus();
    this.textInput.value = tagToEdit;
  },

  getCurrentTags() {
    const value = this.hiddenInput.value.trim();
    return value
      ? value
          .split(',')
          .map(tag => tag.trim())
          .filter(tag => tag !== '')
      : [];
  },

  updateTags(tags) {
    this.hiddenInput.value = tags.join(',');

    this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));

    if (!this.isInForm || this.el.dataset.standaloneMode === 'true') {
      this.pushEvent('tags_updated', { tags: tags });
    }
  },
};

export const ClearInput = {
  mounted() {
    this.handleEvent('clear_input', () => {
      this.el.value = '';
    });
  },
};

export const ModalHook = {
  mounted() {
    this.handleEvent('close_modal', () => {
      const onClose = this.el.getAttribute('phx-on-close');
      if (!onClose) return;
      this.liveSocket.execJS(this.el, onClose);
    });
  },
} as PhoenixHook;

export const Flash = {
  mounted() {
    const hide = () => {
      const click = this.el.getAttribute('phx-click');
      if (!click) return;
      this.liveSocket.execJS(this.el, click);
    };
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
} as PhoenixHook<{ timer: number }>;

export const FragmentMatch = {
  mounted() {
    if (this.el.id != '' && `#${this.el.id}` == window.location.hash) {
      const js = this.el.getAttribute('phx-fragment-match');
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

export const Tooltip = {
  mounted() {
    if (!this.el.ariaLabel) {
      console.warn('Tooltip element missing aria-label attribute', this.el);
      return;
    }

    const content = this.el.ariaLabel;
    const placement = this.el.dataset.placement
      ? this.el.dataset.placement
      : 'top';
    const allowHTML = this.el.dataset.allowHtml
      ? this.el.dataset.allowHtml
      : 'false';
    const hideOnClick = this.el.dataset.hideOnClick !== 'false';

    const interactive = this.el.dataset.interactive || false;

    this._tippyInstance = tippy(this.el, {
      placement: placement,
      animation: false,
      allowHTML: allowHTML === 'true',
      interactive,
      hideOnClick: hideOnClick,
    });
    this._tippyInstance.setContent(content);

    // Store the original content for restoration
    this._originalContent = content;

    // Listen for custom events to show "Copied!" message
    this.el.addEventListener('show-copied', () => {
      if (this._tippyInstance) {
        this._tippyInstance.setContent('Copied!');
        this._tippyInstance.show();

        setTimeout(() => {
          if (this._tippyInstance) {
            this._tippyInstance.setContent(this._originalContent);
            this._tippyInstance.hide();
          }
        }, 1500);
      }
    });
  },
  updated() {
    const content = this.el.ariaLabel;
    if (content && this._tippyInstance) {
      this._tippyInstance.setContent(content);
      this._originalContent = content;
    }
  },
  destroyed() {
    if (this._tippyInstance) this._tippyInstance.destroy();
  },
} as PhoenixHook<
  { _tippyInstance: TippyInstance | null; _originalContent: string },
  { placement: Placement }
>;

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
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;

      // If the click target smells like a link, expand the panel.
      if (target.closest('a[href]')) {
        target
          .closest('.collapsed')
          ?.dispatchEvent(new Event('expand-panel', { bubbles: true }));
      }
    });

    this.el.addEventListener('collapse', event => {
      const target = event.target;
      if (!(target instanceof HTMLElement)) return;
      if (target) {
        const collection = this.el.getElementsByClassName('collapsed');
        if (collection.length < 2) {
          target.classList.add('collapsed');
        }
      }
    });

    this.el.addEventListener('expand-panel', event => {
      if (!(event.target instanceof HTMLElement)) return;
      event.target.classList.remove('collapsed');
    });
  },
} as PhoenixHook;

export const BlurDataclipEditor = {
  mounted() {
    this.el.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        if (document.activeElement instanceof HTMLElement) {
          document.activeElement.blur();
        }
        event.stopImmediatePropagation();
      }
    });
  },
} as PhoenixHook;

export const ScrollToMessage = {
  mounted() {
    this.handleScroll();
  },

  updated() {
    this.handleScroll();
  },

  handleScroll() {
    const targetMessageId = this.el.dataset['scrollToMessage'];

    if (targetMessageId) {
      this.scrollToSpecificMessage(targetMessageId);
    } else {
      this.scrollToBottom();
    }
  },

  scrollToSpecificMessage(messageId: string) {
    const targetMessage = this.el.querySelector(
      `[data-message-id="${messageId}"]`
    );

    if (targetMessage) {
      const relativeTop = (targetMessage as HTMLElement).offsetTop;
      const scrollPosition = relativeTop - 100;

      this.el.scrollTo({
        top: scrollPosition,
        behavior: 'smooth',
      });
    }
  },

  scrollToBottom() {
    setTimeout(() => {
      this.el.scrollTo({
        top: this.el.scrollHeight,
        behavior: 'smooth',
      });
    }, 600);
  },
} as PhoenixHook<{
  handleScroll: () => void;
  scrollToSpecificMessage: (messageId: string) => void;
  scrollToBottom: () => void;
}>;

export const Copy = {
  mounted() {
    const { to, content } = this.el.dataset;
    const phxThenAttribute = this.el.getAttribute('phx-then');

    this.el.addEventListener('click', ev => {
      ev.preventDefault();
      ev.stopPropagation();

      let text = '';

      if (content) {
        text = content;
      } else if (to) {
        const target = document.querySelector(to);
        if (
          target instanceof HTMLInputElement ||
          target instanceof HTMLTextAreaElement
        ) {
          text = target.value;
        } else if (target) {
          text = target.textContent || target.innerText || '';
        }
      }

      if (text) {
        const element = this.el;
        navigator.clipboard
          .writeText(text)
          .then(() => {
            this.showCopiedTooltip();
          })
          .catch(err => {
            console.error('Failed to copy text: ', err);
          });
      }
    });
  },

  showCopiedTooltip() {
    // Find the tooltip element that contains this copy element
    const tooltipElement = this.el.closest('[phx-hook="Tooltip"]');

    if (tooltipElement) {
      // Dispatch a custom event to trigger the "Copied!" tooltip
      tooltipElement.dispatchEvent(new CustomEvent('show-copied'));
    }
  },
} as PhoenixHook;

export const DownloadText = {
  mounted() {
    const { target, contentType, fileName } = this.el.dataset;

    if (!target || !contentType || !fileName) {
      throw new Error(
        'target element or content-type or  file-name data attributes are not set'
      );
    }

    this.el.addEventListener('click', ev => {
      ev.preventDefault();
      const targetEl = document.querySelector(target);
      if (
        targetEl instanceof HTMLInputElement ||
        targetEl instanceof HTMLTextAreaElement
      ) {
        const blob = new Blob([targetEl.value], { type: contentType });

        // Create a URL for the Blob
        const url = window.URL.createObjectURL(blob);

        // Create a temporary anchor element
        const downloadLink = document.createElement('a');
        downloadLink.href = url;
        downloadLink.download = fileName;

        // Append to the body (required for Firefox)
        document.body.appendChild(downloadLink);

        // Trigger click event to start download
        downloadLink.click();

        // Clean up
        window.URL.revokeObjectURL(url);
        document.body.removeChild(downloadLink);
      }
    });
  },
} as PhoenixHook<{}>;

// Sets the checkbox to indeterminate state if the element has the
// `indeterminate` class
export const CheckboxIndeterminate = {
  mounted() {
    this.el.indeterminate = this.el.classList.contains('indeterminate');
  },
  updated() {
    this.el.indeterminate = this.el.classList.contains('indeterminate');
  },
} as PhoenixHook<{}, {}, HTMLInputElement>;

// assets/js/typewriter_hook.js
export const TypewriterHook = {
  mounted() {
    const userName = this.el.dataset.userName;
    const pHtml = this.el.dataset.pHtml;

    // Extract plain text from HTML for typing animation
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = pHtml;
    const pText = tempDiv.textContent || tempDiv.innerText || '';

    // Generate time-based greeting
    const now = new Date();
    const hour = now.getHours();

    let greeting;
    if (hour >= 22 || hour < 3) {
      // 10pm - 3am
      greeting = `Good evening, ${userName}. You're up late!`;
    } else if (hour >= 3 && hour < 7) {
      // 3am - 7am
      greeting = `Good morning, ${userName}. You're up early!`;
    } else if (hour >= 7 && hour < 12) {
      // 7am - 12pm
      greeting = `Good morning, ${userName}!`;
    } else if (hour >= 12 && hour < 18) {
      // 12pm - 6pm
      greeting = `Good afternoon, ${userName}!`;
    } else {
      // 6pm - 10pm
      greeting = `Good evening, ${userName}!`;
    }

    const h1Text = greeting;

    const h1Element = this.el.querySelector('#typewriter-h1');
    const pElement = this.el.querySelector('#typewriter-p');
    const h1Cursor = this.el.querySelector('#cursor-h1');
    const pCursor = this.el.querySelector('#cursor-p');

    let h1Index = 0;
    let pIndex = 0;

    const typeH1 = () => {
      if (h1Index < h1Text.length) {
        h1Element.textContent = h1Text.slice(0, h1Index + 1);
        h1Index++;
        setTimeout(typeH1, 50);
      } else {
        // Move cursor from h1 to p
        h1Cursor.style.display = 'none';
        pCursor.style.display = 'inline';
        setTimeout(typeP, 200);
      }
    };

    const typeP = () => {
      if (pIndex < pText.length) {
        pElement.textContent = pText.slice(0, pIndex + 1);
        pIndex++;
        setTimeout(typeP, 50);
      } else {
        // Remove cursor and replace with HTML version if available
        setTimeout(() => {
          pCursor.style.display = 'none';
          if (pHtml) {
            pElement.innerHTML = pHtml;
          }
        }, 1000);
      }
    };

    // Start the typewriter effect
    typeH1();
  },
};

export const relativeLocale = {
  ...enUS,
  formatRelative: (token, date, baseDate, options) => {
    const formatters = {
      lastWeek: "'last' eeee 'at' p",
      yesterday: "'yesterday at' p",
      today: "'today at' p",
      tomorrow: "'tomorrow at' p",
      nextWeek: "eeee 'at' p",
      other: (date, baseDate) => {
        const currentYear = new Date().getFullYear();
        const dateYear = date.getFullYear();
        return dateYear === currentYear ? 'MMMM do, p' : 'yyyy-MM-dd, p';
      },
    };

    if (token === 'other') {
      return formatters.other(date, baseDate);
    }

    return formatters[token] || formatters.other(date, baseDate);
  },
};

const relativeDetailedLocale = {
  ...enUS,
  formatRelative: (token, date, baseDate, options) => {
    const formatters = {
      lastWeek: "'last' eeee 'at' h:mm:ss a",
      yesterday: "'yesterday at' h:mm:ss a",
      today: "'today at' h:mm:ss a",
      tomorrow: "'tomorrow at' h:mm:ss a",
      nextWeek: "eeee 'at' h:mm:ss a",
      other: (date, baseDate) => {
        const currentYear = new Date().getFullYear();
        const dateYear = date.getFullYear();
        return dateYear === currentYear
          ? 'MMMM do, h:mm:ss a'
          : 'yyyy-MM-dd, h:mm:ss a';
      },
    };

    if (token === 'other') {
      return formatters.other(date, baseDate);
    }

    return formatters[token] || formatters.other(date, baseDate);
  },
};

export const LocalTimeConverter = {
  mounted() {
    this.convertDateTime();
  },

  updated() {
    this.convertDateTime();
  },

  convertDateTime() {
    const isoTimestamp = this.el.dataset['isoTimestamp'];
    const display = this.el.dataset['format'];

    if (!isoTimestamp) return;
    this.convertToDisplayTime(isoTimestamp, display || 'relative');
  },

  convertToDisplayTime(isoTimestamp: string, display: string) {
    try {
      const now = new Date();
      const date = new Date(isoTimestamp);
      let displayTime: string | undefined;

      switch (display) {
        case 'detailed':
          displayTime = format(date, "MMMM do, yyyy 'at' h:mm:ss a");
          break;

        case 'relative_detailed':
          displayTime = formatRelative(date, now, {
            locale: relativeDetailedLocale,
          });
          break;

        case 'time_only':
          displayTime = format(date, 'h:mm:ss a');
          break;

        // case 'relative':
        default:
          displayTime = formatRelative(date, now, { locale: relativeLocale });
          break;

        // Is there any need for a default? Detailed or relative make sense.
        // default:
        //   displayTime = format(date, "MMM do 'at' h:mmaaa");
      }

      const textElement = this.el.querySelector('.datetime-text');
      if (textElement && displayTime) {
        textElement.textContent = displayTime;
      }
    } catch (err) {
      console.error('Failed to convert timestamp to display time:', err);
    }
  },
} as PhoenixHook<{
  convertDateTime: () => void;
  convertToDisplayTime: (isoTimestamp: string, display: string) => void;
}>;

/**
 * Delays sidebar expansion on hover by 1 second.
 * This allows power users to click icons directly without triggering expansion.
 * Collapse is immediate when mouse leaves.
 */
export const SidebarHoverDelay = {
  mounted() {
    this.hoverTimer = null;

    this.handleMouseEnter = () => {
      // Only apply delay when sidebar is collapsed
      if (this.el.dataset['collapsed'] !== 'true') return;

      // Start timer to add expanded class after 1s
      this.hoverTimer = window.setTimeout(() => {
        this.el.classList.add('sidebar-hover-expanded');
      }, 1000);
    };

    this.handleMouseLeave = () => {
      // Cancel pending expansion
      if (this.hoverTimer) {
        clearTimeout(this.hoverTimer);
        this.hoverTimer = null;
      }

      // Immediately remove expanded class
      this.el.classList.remove('sidebar-hover-expanded');
    };

    this.el.addEventListener('mouseenter', this.handleMouseEnter);
    this.el.addEventListener('mouseleave', this.handleMouseLeave);
  },

  destroyed() {
    if (this.hoverTimer) {
      clearTimeout(this.hoverTimer);
    }
    this.el.removeEventListener('mouseenter', this.handleMouseEnter);
    this.el.removeEventListener('mouseleave', this.handleMouseLeave);
  },
} as PhoenixHook<{
  hoverTimer: number | null;
  handleMouseEnter: () => void;
  handleMouseLeave: () => void;
}>;
