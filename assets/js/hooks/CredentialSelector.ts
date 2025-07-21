import type { PhoenixHook } from './PhoenixHook';

export default {
  mounted() {
    this.selector = this.el.querySelector('select') as HTMLSelectElement;
    this.projectField = this.el.querySelector(
      `[name="${this.el.dataset.projectField}"]`
    ) as HTMLInputElement;
    this.keychainField = this.el.querySelector(
      `[name="${this.el.dataset.keychainField}"]`
    ) as HTMLInputElement;

    if (!this.selector || !this.projectField || !this.keychainField) {
      console.error('CredentialSelector: Required elements not found', {
        selector: this.selector,
        projectField: this.projectField,
        keychainField: this.keychainField,
      });
      return;
    }

    this.selector.addEventListener('change', this.handleSelection.bind(this));

    this.initializeSelection();
  },

  handleSelection(event: Event) {
    const target = event.target as HTMLSelectElement;
    const selectedOption = target.selectedOptions[0];

    if (!selectedOption || !selectedOption.value) {
      this.clearFields();
      return;
    }

    const value = selectedOption.value;
    const isKeychain = this.isKeychainCredential(selectedOption);

    if (isKeychain) {
      this.keychainField.value = value;
      this.projectField.value = '';
    } else {
      this.projectField.value = value;
      this.keychainField.value = '';
    }

    this.dispatchFormChange();
  },

  clearFields() {
    this.projectField.value = '';
    this.keychainField.value = '';
    this.dispatchFormChange();
  },

  dispatchFormChange() {
    this.projectField.dispatchEvent(new Event('input', { bubbles: true }));
    this.keychainField.dispatchEvent(new Event('input', { bubbles: true }));
  },

  initializeSelection() {
    const projectValue = this.projectField.value;
    const keychainValue = this.keychainField.value;

    if (projectValue) {
      this.selector.value = projectValue;
    } else if (keychainValue) {
      this.selector.value = keychainValue;
    }
  },

  isKeychainCredential(option: HTMLOptionElement): boolean {
    // Check if the option is within a "Keychain Credentials" optgroup
    const optgroup = option.closest('optgroup');
    return optgroup?.label === 'Keychain Credentials';
  },
} as PhoenixHook<{
  selector: HTMLSelectElement;
  projectField: HTMLInputElement;
  keychainField: HTMLInputElement;
  handleSelection: (event: Event) => void;
  clearFields: () => void;
  dispatchFormChange: () => void;
  initializeSelection: () => void;
  isKeychainCredential: (option: HTMLOptionElement) => boolean;
}>;
