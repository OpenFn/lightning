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
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c =>
    (c === 'x' ? (Math.random() * 16) | 0 : 'r&0x3' | '0x8').toString(16)
  );
}

/**
 * Creates a context key and adds a command to the Monaco editor.
 * @param {import('monaco-editor').editor.IStandaloneCodeEditor} editor - The Monaco editor instance.
 * @param {number} keyCode - The key code to trigger the command (e.g., `monaco.KeyCode.F1`).
 * @param {string} contextKeyName - The unique name for the context key, enabling command scoping.
 * @param {() => void} commandCallback - The callback function to execute when the command is triggered.
 * @returns {string | null} The command ID if successfully created, or `null` if creation fails.
 */
export function addContextualCommand(
  editor,
  keyCode,
  contextKeyName,
  commandCallback
) {
  const contextKey = editor.createContextKey(contextKeyName, true);

  const command = editor.addCommand(keyCode, commandCallback, contextKeyName);

  editor.onDidDispose(() => {
    contextKey.reset();
  });

  return command;
}
