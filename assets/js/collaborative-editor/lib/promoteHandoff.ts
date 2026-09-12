/**
 * Carries "the promote landed" across the reload that follows an archive.
 *
 * Archiving the sandbox is the server's navigation: it schedules the deletion
 * and the LiveView teardown hook redirects every socket on that project to the
 * parent. That is a full page load, so a toast raised before it is destroyed,
 * and the server cannot say the promote happened because the event driving the
 * redirect knows only that a project is being wound down.
 *
 * So the client hands the fact to itself. `sessionStorage` survives the load,
 * is scoped to this tab, and keeps the marker out of the URL, where a copied
 * link would replay the message for someone who promoted nothing.
 */
const KEY = 'openfn:promoted';

export function markPromoted(): void {
  try {
    window.sessionStorage.setItem(KEY, '1');
  } catch {
    // A browser refusing storage costs a confirmation message, nothing more.
  }
}

export function clearPromoted(): void {
  try {
    window.sessionStorage.removeItem(KEY);
  } catch {
    // As above.
  }
}

/** Reads the marker and consumes it, so a refresh does not replay the toast. */
export function takePromoted(): boolean {
  try {
    const marked = window.sessionStorage.getItem(KEY) === '1';
    if (marked) window.sessionStorage.removeItem(KEY);
    return marked;
  } catch {
    return false;
  }
}
