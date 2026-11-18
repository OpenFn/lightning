/**
 * NavigateButton - "Take me there" action for AI assistant replies
 *
 * Apollo can end a reply with a fenced code block tagged `openfn-navigate`
 * whose body is JSON like `{"page": "project_settings", "tab": "vcs"}`.
 * MessageList routes that fence here instead of rendering a code block.
 *
 * Clicking the button dispatches the frozen `lightning:start-tour` contract
 * on `document`; a global tour module listens for it:
 *
 * ```js
 * document.dispatchEvent(new CustomEvent('lightning:start-tour', {
 *   detail: { page: string, tab?: string, params: { project_id: string } }
 * }))
 * ```
 *
 * The fence content re-renders on every streaming delta, so a half-streamed
 * body is normal input, not an error: anything that does not parse to an
 * object with a string `page` renders nothing and never throws.
 */

import { useProject } from '../hooks/useSessionContext';

interface NavigateTarget {
  /** App-map page id, e.g. "project_settings" */
  page: string;
  /** Optional settings-tab hash, e.g. "vcs" */
  tab?: string;
}

/**
 * Parse an `openfn-navigate` fence body. Returns null for anything that is
 * not an object with a string `page` — including partially-streamed JSON.
 */
export const parseNavigateTarget = (content: string): NavigateTarget | null => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    return null;
  }

  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return null;
  }

  const { page, tab } = parsed as Record<string, unknown>;
  if (typeof page !== 'string' || page.length === 0) return null;

  return typeof tab === 'string' ? { page, tab } : { page };
};

export const NavigateButton = ({ content }: { content: string }) => {
  // Hooks run unconditionally; parsing comes after. The project can still be
  // loading, in which case the event goes out with empty params rather than
  // blocking the button.
  const project = useProject();

  const target = parseNavigateTarget(content);
  if (!target) return null;

  const handleClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    document.dispatchEvent(
      new CustomEvent('lightning:start-tour', {
        detail: {
          page: target.page,
          ...(target.tab !== undefined && { tab: target.tab }),
          params: project?.id ? { project_id: project.id } : {},
        },
      })
    );
  };

  return (
    <button
      type="button"
      data-testid="navigate-button"
      onClick={handleClick}
      className="inline-flex items-center gap-1 rounded-md px-2 py-1 my-1 text-xs font-medium transition-all duration-300 ease-in-out bg-slate-300 text-white hover:bg-primary-600 hover:scale-105"
    >
      <span className="hero-map-pin-micro h-3.5 w-3.5" aria-hidden="true" />
      Take me there
    </button>
  );
};
