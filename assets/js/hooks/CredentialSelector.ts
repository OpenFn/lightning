import type { PhoenixHook } from './PhoenixHook';

export default {
  mounted() {
    this.setFields();
    this.removeEvents = this.attachEvents();
  },

  destroyed() {
    this.removeEvents();
  },

  handleSelection(event: Event) {
    event.stopImmediatePropagation();

    const target = event.target as HTMLSelectElement;
    const selectedOption = target.selectedOptions[0];

    if (!selectedOption || !selectedOption.value) {
      this.projectCredentialField.value = '';
      this.keychainCredentialField.value = '';
    } else {
      const value = selectedOption.value;
      const isKeychain = this.isKeychainCredential(selectedOption);

      if (isKeychain) {
        this.keychainCredentialField.value = value;
        this.projectCredentialField.value = '';
      } else {
        this.projectCredentialField.value = value;
        this.keychainCredentialField.value = '';
      }
    }

    this.dispatchFormChange();
  },

  dispatchFormChange() {
    // We only need to emit a change on one of the fields, LiveViews top level
    // handler generates a call to `validate` which will have all the fields.
    this.projectCredentialField.dispatchEvent(
      new Event('change', { bubbles: true })
    );
  },

  isKeychainCredential(option: HTMLOptionElement): boolean {
    // Check if the option is within a "Keychain Credentials" optgroup
    const optgroup = option.closest('optgroup');
    return optgroup?.label === 'Keychain Credentials';
  },

  attachEvents() {
    // Store bound function references so we can remove them later
    const inputHandler = (e: Event) => {
      e.stopImmediatePropagation();
    };
    const changeHandler = this.handleSelection.bind(this);

    this.selector.addEventListener('input', inputHandler);
    this.selector.addEventListener('change', changeHandler);

    return () => {
      this.selector.removeEventListener('input', inputHandler);
      this.selector.removeEventListener('change', changeHandler);
    };
  },

  setFields() {
    const selector = this.el.querySelector('select') as HTMLSelectElement;
    const projectCredentialField = this.el.querySelector(
      `[name="${this.el.dataset.projectField}"]`
    ) as HTMLInputElement;
    const keychainCredentialField = this.el.querySelector(
      `[name="${this.el.dataset.keychainField}"]`
    ) as HTMLInputElement;

    if (!selector || !projectCredentialField || !keychainCredentialField) {
      console.error('CredentialSelector: Required elements not found', {
        selector: this.selector,
        projectField: this.projectCredentialField,
        keychainField: this.keychainCredentialField,
      });
      return;
    }

    this.selector = selector;
    this.projectCredentialField = projectCredentialField;
    this.keychainCredentialField = keychainCredentialField;
  },
} as PhoenixHook<
  {
    selector: HTMLSelectElement;
    projectCredentialField: HTMLInputElement;
    keychainCredentialField: HTMLInputElement;
    attachEvents: () => () => void;
    dispatchFormChange: () => void;
    handleSelection: (event: Event) => void;
    isKeychainCredential: (option: HTMLOptionElement) => boolean;
    removeEvents: () => void;
    setFields: () => void;
  },
  {
    projectField: string;
    keychainField: string;
  }
>;
