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

// Back can restore this page from the browser's cache, and then the page lives
// on, so the suppression must not. A navigation that never commits at all
// fires nothing, and the flag stands until the page goes; that window is the
// gap between clicking through our own dialog and the browser giving up on the
// request, which is short and already answered.
if (typeof window !== 'undefined') {
  window.addEventListener('pageshow', resetUnloadWarning);
}
