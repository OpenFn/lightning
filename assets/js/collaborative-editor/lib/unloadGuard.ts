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

/** Clears a suppression so a page that survived the navigation is warned again. */
export function resetUnloadWarning() {
  suppressed = false;
}

// A navigation can be abandoned, and Back can restore this page from the
// browser's cache. Either way the page lives on, so the suppression must not.
if (typeof window !== 'undefined') {
  window.addEventListener('pageshow', resetUnloadWarning);
}
