/**
 * CollaborativeEditorPromoBanner - Promotional banner encouraging users to try the collaborative editor
 *
 * Displays when:
 * - User has experimental features enabled
 * - Banner hasn't been previously dismissed
 *
 * Features:
 * - Compact design with call-to-action
 * - Dismissible via X button
 * - Persists dismissal in cookies for 90 days
 * - Positioned at top-center of canvas
 * - Extracts projectId and workflowId from window.location.pathname
 * - Preserves 'a' (run) and 'v' (version) query params when navigating
 */

import { useState, useEffect } from 'react';

import { cn } from '#/utils/cn';

interface CollaborativeEditorPromoBannerProps {
  className?: string;
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

  const buildCollaborativeUrl = (): string => {
    // Extract projectId and workflowId from current URL
    // URL pattern: /projects/{projectId}/w/{workflowId} or /projects/{projectId}/w/new
    const pathname = window.location.pathname;
    const match = pathname.match(/\/projects\/([^/]+)\/w\/([^/]+)/);

    if (!match) {
      // Fallback - shouldn't happen in practice
      return '/projects';
    }

    const [, projectId, workflowId] = match;

    // Build base URL
    const basePath =
      workflowId === 'new'
        ? `/projects/${projectId}/w/new/collaborate`
        : `/projects/${projectId}/w/${workflowId}/collaborate`;

    // Preserve 'a' (run) and 'v' (version) query params
    const searchParams = new URLSearchParams(window.location.search);
    const preservedParams = new URLSearchParams();

    if (searchParams.has('a')) {
      preservedParams.set('a', searchParams.get('a')!);
    }
    if (searchParams.has('v')) {
      preservedParams.set('v', searchParams.get('v')!);
    }

    const queryString = preservedParams.toString();
    return queryString ? `${basePath}?${queryString}` : basePath;
  };

  if (dismissed) {
    return null;
  }

  return (
    <div
      className={cn('bg-blue-50 rounded-md shadow-sm', className)}
      role="alert"
      aria-live="polite"
    >
      <div className="flex items-start gap-2 p-3">
        <span
          className="hero-information-circle h-5 w-5 text-blue-800 shrink-0"
          aria-hidden="true"
        />
        <div className="flex-1 min-w-0">
          <div className="text-xs text-blue-800 font-medium">
            Try the new collaborative editor!
          </div>
          <div className="text-xs text-blue-700 mt-0.5">
            Real-time editing with your team.{' '}
            <a
              href={buildCollaborativeUrl()}
              className="font-semibold hover:text-blue-900 underline"
            >
              Try it now →
            </a>
          </div>
        </div>
        <button
          type="button"
          onClick={handleDismiss}
          className="shrink-0 text-blue-700 cursor-pointer hover:text-blue-800 transition-colors"
          aria-label="Dismiss collaborative editor promotion"
        >
          <span className="hero-x-mark h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
