/**
 * CollaborativeEditorPromoBanner - Promotional banner encouraging users to try the collaborative editor
 *
 * Displays when:
 * - Banner hasn't been previously dismissed (checked via cookie)
 *
 * Features:
 * - Absolute position at bottom-center of workflow canvas
 * - Dark themed design matching Tailwind sticky banner pattern
 * - Dismissible via X button
 * - Persists dismissal in cookies for 90 days
 * - Navigation handled by LiveView via switch_to_collab_editor pushEvent
 */

import { useState, useEffect } from 'react';

import { cn } from '#/utils/cn';

interface CollaborativeEditorPromoBannerProps {
  className?: string;
  pushEvent?:
    | ((name: string, payload: Record<string, unknown>) => void)
    | undefined;
}

const COOKIE_NAME = 'openfn_collaborative_editor_promo_dismissed';
const COOKIE_EXPIRY_DAYS = 90;

function getCookie(name: string): string | null {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) {
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
}

function setCookie(name: string, value: string, days: number): void {
  const expires = new Date();
  expires.setDate(expires.getDate() + days);
  document.cookie = `${name}=${value}; expires=${expires.toUTCString()}; path=/; SameSite=Lax`;
}

export function CollaborativeEditorPromoBanner({
  className,
  pushEvent,
}: CollaborativeEditorPromoBannerProps) {
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Check if banner was previously dismissed
    const isDismissed = getCookie(COOKIE_NAME) === 'true';
    setDismissed(isDismissed);
  }, []);

  const handleDismiss = () => {
    setCookie(COOKIE_NAME, 'true', COOKIE_EXPIRY_DAYS);
    setDismissed(true);
  };

  if (dismissed) {
    return null;
  }

  return (
    <div
      className={cn(
        'pointer-events-none absolute inset-x-0 bottom-0 flex justify-center px-6 pb-5 z-10',
        className
      )}
      role="alert"
      aria-live="polite"
    >
      <div className="pointer-events-auto flex items-center gap-x-4 bg-primary-700 px-6 py-2.5 rounded-xl sm:py-3 sm:pr-3.5 sm:pl-4">
        <button
          type="button"
          onClick={() =>
            pushEvent?.('switch_to_collab_editor', { banner: true })
          }
          className="text-sm/6 text-white cursor-pointer"
        >
          <strong className="font-semibold">
            Try the new collaborative editor
          </strong>
          <svg
            viewBox="0 0 2 2"
            aria-hidden="true"
            className="mx-2 inline size-0.5 fill-current"
          >
            <circle r={1} cx={1} cy={1} />
          </svg>
          Real-time editing with your team&nbsp;
          <span aria-hidden="true">&rarr;</span>
        </button>
        <button
          type="button"
          onClick={handleDismiss}
          className="-m-1.5 flex-none p-1.5 cursor-pointer"
          aria-label="Dismiss collaborative editor promotion"
        >
          <span className="hero-x-mark size-5 text-white" />
        </button>
      </div>
    </div>
  );
}
