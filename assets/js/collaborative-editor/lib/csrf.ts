/**
 * Get CSRF token from meta tag
 */
export function getCsrfToken(): string | null {
  const meta = document.querySelector<HTMLMetaElement>(
    'meta[name="csrf-token"]'
  );
  return meta?.getAttribute('content') || null;
}
