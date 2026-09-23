/** Carries "you just promoted" across the navigation into the parent project. */

const KEY = 'openfn:promoted';

export function markPromoted(): void {
  try {
    window.sessionStorage.setItem(KEY, '1');
  } catch {}
}

export function clearPromoted(): void {
  try {
    window.sessionStorage.removeItem(KEY);
  } catch {}
}

export function takePromoted(): boolean {
  try {
    const marked = window.sessionStorage.getItem(KEY) === '1';
    if (marked) window.sessionStorage.removeItem(KEY);
    return marked;
  } catch {
    return false;
  }
}
