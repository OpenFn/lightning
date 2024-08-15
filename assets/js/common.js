// this has been added here because we still can't find a better place for it
// it's being used in both the hooks and the job editor
export function initiateSaveAndRun(buttonElement) {
  if (buttonElement.getAttribute('type') == 'submit') {
    const formId = buttonElement.getAttribute('form');
    const form = document.getElementById(formId);
    form.dispatchEvent(
      new Event('submit', { bubbles: true, cancelable: true })
    );
  } else {
    buttonElement.dispatchEvent(
      new Event('click', { bubbles: true, cancelable: true })
    );
  }
}

export function randomUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => (c === 'x' ? (Math.random() * 16 | 0) : ('r&0x3'| '0x8')).toString(16))
}
