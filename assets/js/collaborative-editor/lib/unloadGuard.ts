/**
 * Lets a deliberate navigation leave without the browser's unload warning.
 *
 * Leaving for a sandbox is a hard navigation, so it triggers `beforeunload`
 * even after the person has already answered our own dialog. Call this
 * immediately before navigating and the warning stays quiet for that one.
 */
let suppressed = false;

export function suppressUnloadWarning() {
  suppressed = true;
}

export function isUnloadWarningSuppressed() {
  return suppressed;
}

/** Test-only: forget a suppression so it cannot leak between cases. */
export function resetUnloadWarning() {
  suppressed = false;
}
