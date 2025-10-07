import tippy, {
  type Instance as TippyInstance,
  type Placement,
} from 'tippy.js';
import { format, formatRelative } from 'date-fns';
import { enUS } from 'date-fns/locale';
import type { PhoenixHook } from './PhoenixHook';

import LogLineHighlight from './LogLineHighlight';
import WorkflowToYAML from '../yaml/WorkflowToYAML';
import YAMLToWorkflow from '../yaml/YAMLToWorkflow';
import TemplateToWorkflow from '../yaml/TemplateToWorkflow';
import ElapsedIndicator from './ElapsedIndicator';
import {
  TabbedContainer,
  TabbedSelector,
  TabbedPanels,
} from './TabbedContainer';

import {
  SaveViaCtrlS,
  InspectorSaveViaCtrlS,
  OpenSyncModalViaCtrlShiftS,
  SendMessageViaCtrlEnter,
  DefaultRunViaCtrlEnter,
  AltRunViaCtrlShiftEnter,
  CloseInspectorPanelViaEscape,
  CloseNodePanelViaEscape,
} from './KeyHandlers';

import FileDropzone from './FileDropzone';
import CredentialSelector from './CredentialSelector';

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
  FileDropzone,
  CredentialSelector,
};

export { ReactComponent, HeexReactComponent } from '#/react/hooks';

export const CredentialTabs = {
  mounted() {
    this.environments = JSON.parse(this.el.dataset.environments || '[]');
    this.currentTab = this.el.dataset.currentTab || 'main';
    this.targetId = this.el.dataset.phxTarget;
    this.showingNewTab = false;
    this.errorMessage = null;
    
    this.render();
    this.attachEventListeners();
  },

  updated() {
    // Only update if environments changed
    const newEnvironments = JSON.parse(this.el.dataset.environments || '[]');
    const newCurrentTab = this.el.dataset.currentTab || 'main';
    
    if (JSON.stringify(newEnvironments) !== JSON.stringify(this.environments) ||
        newCurrentTab !== this.currentTab) {
      this.environments = newEnvironments;
      this.currentTab = newCurrentTab;
      this.showingNewTab = false;
      this.render();
      this.attachEventListeners();
    }
  },

  render() {
    const nav = this.el;
    nav.innerHTML = '';
    
    // Render environment tabs
    this.environments.forEach(env => {
      const button = this.createTabButton(env);
      nav.appendChild(button);
    });
    
    // Render new tab input if showing
    if (this.showingNewTab) {
      const form = this.createNewTabForm();
      nav.appendChild(form);
    }
    
    // Render plus button
    const plusButton = this.createPlusButton();
    nav.appendChild(plusButton);
    
    // Render error message if exists
    if (this.errorMessage) {
      const errorDiv = this.createErrorMessage();
      this.el.parentElement.appendChild(errorDiv);
    } else {
      // Remove existing error message if any
      const existingError = this.el.parentElement.querySelector('.tab-error-message');
      if (existingError) {
        existingError.remove();
      }
    }
  },

  createTabButton(envName) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `pb-4 px-1 border-b-2 font-medium text-sm transition-all duration-200 ease-in-out whitespace-nowrap ${
      this.currentTab === envName
        ? 'border-indigo-500 text-indigo-600 dark:border-indigo-400 dark:text-indigo-400'
        : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-200 dark:hover:border-gray-600'
    }`;
    button.textContent = envName.charAt(0).toUpperCase() + envName.slice(1);
    button.dataset.env = envName;
    
    return button;
  },

  createNewTabForm() {
    const form = document.createElement('form');
    form.className = 'inline-flex opacity-0 animate-fade-in';
    form.style.animation = 'fadeIn 0.2s ease-in forwards';
    
    const hiddenInput = document.createElement('input');
    hiddenInput.type = 'hidden';
    hiddenInput.name = 'old_name';
    hiddenInput.value = 'new';
    
    const textInput = document.createElement('input');
    textInput.type = 'text';
    textInput.name = 'name';
    textInput.className = 'pb-4 px-1 border-0 border-b-2 border-indigo-500 bg-transparent font-medium text-sm text-indigo-600 dark:text-indigo-400 focus:outline-none focus:ring-0 focus:border-b-2 focus:border-indigo-600 dark:focus:border-indigo-300 w-32 transition-all duration-200';
    textInput.placeholder = 'New environment';
    textInput.dataset.newTabInput = 'true';
    
    form.appendChild(hiddenInput);
    form.appendChild(textInput);
    
    // Auto-focus with a slight delay for smooth animation
    setTimeout(() => textInput.focus(), 100);
    
    return form;
  },

  createPlusButton() {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `pb-4 px-1 transition-all duration-200 ${
      this.showingNewTab
        ? 'text-gray-300 dark:text-gray-600 cursor-not-allowed'
        : 'text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300'
    }`;
    button.disabled = this.showingNewTab;
    button.title = 'Add new environment';
    button.dataset.plusButton = 'true';
    button.innerHTML = '<svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>';
    
    return button;
  },

  createErrorMessage() {
    const div = document.createElement('div');
    div.className = 'tab-error-message mt-2 text-sm text-red-600 dark:text-red-400 animate-fade-in';
    div.style.animation = 'fadeIn 0.2s ease-in forwards';
    div.textContent = this.errorMessage;
    
    // Auto-dismiss after 5 seconds
    if (this.errorTimeout) {
      clearTimeout(this.errorTimeout);
    }
    
    this.errorTimeout = setTimeout(() => {
      this.errorMessage = null;
      const existingError = this.el.parentElement.querySelector('.tab-error-message');
      if (existingError) {
        existingError.style.animation = 'fadeOut 0.2s ease-out forwards';
        setTimeout(() => existingError.remove(), 200);
      }
    }, 5000);
    
    return div;
  },

  attachEventListeners() {
    // Tab click handler
    this.el.addEventListener('click', (e) => {
      const tabButton = e.target.closest('button[data-env]');
      if (tabButton) {
        e.preventDefault();
        e.stopPropagation();
        const envName = tabButton.dataset.env;
        this.switchTab(envName);
        return;
      }
      
      const plusButton = e.target.closest('button[data-plus-button]');
      if (plusButton && !this.showingNewTab) {
        e.preventDefault();
        e.stopPropagation();
        this.showNewTab();
        return;
      }
    });

    // Form submit handler
    this.el.addEventListener('submit', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const form = e.target;
      const input = form.querySelector('input[name="name"]');
      const name = input.value.trim().toLowerCase();
      
      if (name) {
        this.saveEnvironment(name);
      } else {
        this.hideNewTab();
      }
    });

    // Input blur handler
    this.el.addEventListener('blur', (e) => {
      if (e.target.dataset.newTabInput) {
        e.stopPropagation();
        const input = e.target;
        const name = input.value.trim().toLowerCase();
        
        setTimeout(() => {
          if (name) {
            this.saveEnvironment(name);
          } else {
            this.hideNewTab();
          }
        }, 100);
      }
    }, true);

    // Input keydown handler
    this.el.addEventListener('keydown', (e) => {
      if (e.target.dataset.newTabInput) {
        if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          this.hideNewTab();
        } else if (e.key === 'Enter') {
          e.preventDefault();
          e.stopPropagation();
          const name = e.target.value.trim().toLowerCase();
          if (name) {
            this.saveEnvironment(name);
          } else {
            this.hideNewTab();
          }
        }
      }
    });
  },

  switchTab(envName) {
    if (this.currentTab !== envName) {
      this.currentTab = envName;
      this.pushEventTo(this.targetId, 'change_tab', { tab: envName });
      this.render();
      this.attachEventListeners();
    }
  },

  showNewTab() {
    this.showingNewTab = true;
    this.errorMessage = null; // Clear any existing errors
    this.render();
    this.attachEventListeners();
  },

  hideNewTab() {
    const form = this.el.querySelector('form');
    if (form) {
      form.style.animation = 'fadeOut 0.2s ease-out forwards';
      setTimeout(() => {
        this.showingNewTab = false;
        this.errorMessage = null; // Clear errors when hiding
        this.render();
        this.attachEventListeners();
      }, 200);
    } else {
      this.showingNewTab = false;
      this.errorMessage = null; // Clear errors when hiding
      this.render();
      this.attachEventListeners();
    }
  },

  saveEnvironment(name) {
    // Validate name
    if (!name.match(/^[a-z0-9][a-z0-9_-]{0,31}$/)) {
      this.showingNewTab = false;
      this.errorMessage = 'Environment name must be lowercase alphanumeric with hyphens or underscores';
      this.render();
      this.attachEventListeners();
      return;
    }

    if (this.environments.includes(name)) {
      this.showingNewTab = false;
      this.errorMessage = `Environment '${name}' already exists`;
      this.render();
      this.attachEventListeners();
      return;
    }

    // Send to server
    this.pushEventTo(this.targetId, 'save_environment', { 
      name: name, 
      old_name: 'new' 
    });

    // Optimistically update UI
    this.environments.push(name);
    this.currentTab = name;
    this.showingNewTab = false;
    this.errorMessage = null;
    this.render();
    this.attachEventListeners();
  }
};

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
    this.toggleButton = this.el.querySelector('button')!;
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

  navigateToItem(url?: string | undefined) {
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
  navigateToItem(url?: string | undefined): void;
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

    let currentTags = this.getCurrentTags();

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
    let currentTags = this.getCurrentTags();
    const updatedTags = currentTags.filter(tag => tag !== tagToRemove);
    this.updateTags(updatedTags);
  },

  editTag(tagToEdit) {
    let currentTags = this.getCurrentTags();
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
      let onClose = this.el.getAttribute('phx-on-close');
      if (!onClose) return;
      this.liveSocket.execJS(this.el, onClose);
    });
  },
} as PhoenixHook;

export const Flash = {
  mounted() {
    let hide = () => {
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
    let hideOnClick = this.el.dataset.hideOnClick !== 'false';

    let interactive = this.el.dataset.interactive || false;

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
    let content = this.el.ariaLabel;
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
    let { to, content } = this.el.dataset;
    const phxThenAttribute = this.el.getAttribute('phx-then');

    this.el.addEventListener('click', ev => {
      ev.preventDefault();
      ev.stopPropagation();

      let text = '';

      if (content) {
        text = content;
      } else if (to) {
        let target = document.querySelector(to);
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
        let element = this.el;
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
