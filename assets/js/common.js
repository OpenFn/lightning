import pDebounce from 'p-debounce';

export const EDITOR_DEBOUNCE_MS = 300

const debouncedDispatchEvent = pDebounce(
  (eventTarget, event) => {
    eventTarget.dispatchEvent(event);
  },
  EDITOR_DEBOUNCE_MS
);

export function initiateSaveAndRun(buttonElement) {
  if (buttonElement.getAttribute('type') === 'submit') {
    const formId = buttonElement.getAttribute('form');
    const form = document.getElementById(formId);

    if (form) {
      debouncedDispatchEvent(
        form,
        new Event('submit', { bubbles: true, cancelable: true })
      );
    }
  } else {
    debouncedDispatchEvent(
      buttonElement,
      new Event('click', { bubbles: true, cancelable: true })
    );
  }
}

export function randomUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c =>
    (c === 'x' ? (Math.random() * 16) | 0 : 'r&0x3' | '0x8').toString(16)
  );
}
