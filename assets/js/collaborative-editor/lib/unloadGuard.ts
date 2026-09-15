/** Lets a deliberate navigation leave without the unsaved-changes warning. */

let suppressed = false;

export function suppressUnloadWarning() {
  suppressed = true;
}

export function isUnloadWarningSuppressed() {
  return suppressed;
}

export function resetUnloadWarning() {
  suppressed = false;
}

if (typeof window !== 'undefined') {
  window.addEventListener('pageshow', resetUnloadWarning);
}
