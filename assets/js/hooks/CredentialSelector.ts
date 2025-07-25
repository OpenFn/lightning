import type { PhoenixHook } from './PhoenixHook';

export default {
  mounted() {
    this.selector = this.el.querySelector('select') as HTMLSelectElement;
    console.log('selector', this.selector);
    this.projectCredentialField = this.el.querySelector(
      `[name="${this.el.dataset.projectField}"]`
    ) as HTMLInputElement;
    this.keychainCredentialField = this.el.querySelector(
      `[name="${this.el.dataset.keychainField}"]`
    ) as HTMLInputElement;

    if (
      !this.selector ||
      !this.projectCredentialField ||
      !this.keychainCredentialField
    ) {
      console.error('CredentialSelector: Required elements not found', {
        selector: this.selector,
        projectField: this.projectCredentialField,
        keychainField: this.keychainCredentialField,
      });
      return;
    }

    this.selector.addEventListener('input', e => {
      e.stopImmediatePropagation();
    });
    this.selector.addEventListener('change', this.handleSelection.bind(this));
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
} as PhoenixHook<
  {
    selector: HTMLSelectElement;
    projectCredentialField: HTMLInputElement;
    keychainCredentialField: HTMLInputElement;
    handleSelection: (event: Event) => void;
    clearFields: () => void;
    dispatchFormChange: () => void;
    initializeSelection: () => void;
    isKeychainCredential: (option: HTMLOptionElement) => boolean;
  },
  {
    projectField: string;
    keychainField: string;
  }
>;
