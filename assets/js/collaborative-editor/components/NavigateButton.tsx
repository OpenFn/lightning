/**
 * NavigateButton - "Take me there" action for AI assistant replies
 *
 * Apollo can end a reply with a fenced code block tagged `openfn-navigate`
 * whose body is JSON like `{"page": "project_settings", "tab": "vcs"}`,
 * `{"page": "workflow_edit", "element": "credential-picker"}`, or a
 * multi-stop grand tour `{"tour": ["project_workflows", "project_history"]}`.
 * MessageList routes that fence here instead of rendering a code block.
 *
 * Clicking the button dispatches the frozen `lightning:start-tour` contract
 * on `document` (shift/alt-click adds `autopilot: true`); a global tour
 * module listens for it:
 *
 * ```js
 * document.dispatchEvent(new CustomEvent('lightning:start-tour', {
 *   detail: {
 *     page: string, tab?: string, element?: string,   // single destination…
 *     tour?: string[],                                // …or a grand tour
 *     autopilot?: boolean,
 *     params: { project_id?: string }
 *   }
 * }))
 * ```
 *
 * The fence content re-renders on every streaming delta, so a half-streamed
 * body is normal input, not an error: anything that does not parse to an
 * object with a string `page` renders nothing and never throws.
 */

import { useEffect } from 'react';

import { emitTourEvent } from '../../tour/telemetry';
import { useProject } from '../hooks/useSessionContext';

interface NavigateTarget {
  /** App-map page id, e.g. "project_settings" */
  page?: string;
  /** Optional settings-tab hash, e.g. "vcs" */
  tab?: string;
  /** Optional app-map element id to spotlight, e.g. "credential-picker" */
  element?: string;
  /** Multi-stop grand tour: an ordered list of app-map page ids. */
  tour?: string[];
}

/**
 * Parse an `openfn-navigate` fence body. Returns null for anything that is
 * not an object with a string `page` or a `tour` array of page-id strings —
 * including partially-streamed JSON. Non-string `tab` / `element` values and
 * malformed `tour` arrays are dropped, not errors.
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

  const { page, tab, element, tour } = parsed as Record<string, unknown>;

  if (
    Array.isArray(tour) &&
    tour.length > 0 &&
    tour.every(id => typeof id === 'string' && id.length > 0)
  ) {
    return { tour: tour as string[] };
  }

  if (typeof page !== 'string' || page.length === 0) return null;

  const target: NavigateTarget = { page };
  if (typeof tab === 'string') target.tab = tab;
  if (typeof element === 'string') target.element = element;
  return target;
};

const telemetryFields = (target: NavigateTarget) =>
  target.tour
    ? { page: target.tour.join(',') }
    : {
        ...(target.page !== undefined && { page: target.page }),
        ...(target.tab !== undefined && { tab: target.tab }),
        ...(target.element !== undefined && { element: target.element }),
      };

// MessageList's markdown renderer rebuilds its component map on every render,
// which remounts this button (new instance, fresh refs) on every streaming
// delta or list update. A per-instance ref therefore cannot dedup
// button_shown; track emitted targets for the lifetime of the page instead.
const shownTargets = new Set<string>();

const targetSignature = (target: NavigateTarget): string =>
  target.tour
    ? `tour:${target.tour.join(',')}`
    : `${target.page ?? ''}|${target.tab ?? ''}|${target.element ?? ''}`;

/** Test hook: forget which buttons have reported button_shown. */
export const resetButtonShownTracking = (): void => {
  shownTargets.clear();
};

export const NavigateButton = ({ content }: { content: string }) => {
  // Hooks run unconditionally; parsing comes after. The project can still be
  // loading, in which case the event goes out with empty params rather than
  // blocking the button.
  const project = useProject();

  const target = parseNavigateTarget(content);

  // button_shown: once per shown button. No dependency array — the fence body
  // may still be streaming at mount, so we emit on the first render where it
  // parses; the module-level set keeps it to one emission across the remounts
  // described above.
  useEffect(() => {
    if (!target) return;
    const signature = targetSignature(target);
    if (shownTargets.has(signature)) return;
    shownTargets.add(signature);
    emitTourEvent('button_shown', telemetryFields(target));
  });

  if (!target) return null;

  const handleClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    emitTourEvent('button_clicked', telemetryFields(target));
    // Shift- or alt-click puts the tour on autopilot: it drives the clicks.
    const autopilot = e.shiftKey || e.altKey;
    const detail = target.tour
      ? {
          tour: target.tour,
          ...(autopilot && { autopilot: true }),
          params: project?.id ? { project_id: project.id } : {},
        }
      : {
          page: target.page,
          ...(target.tab !== undefined && { tab: target.tab }),
          ...(target.element !== undefined && { element: target.element }),
          ...(autopilot && { autopilot: true }),
          params: project?.id ? { project_id: project.id } : {},
        };
    document.dispatchEvent(new CustomEvent('lightning:start-tour', { detail }));
  };

  return (
    <button
      type="button"
      data-testid="navigate-button"
      onClick={handleClick}
      title="Shift-click: let it drive"
      className="inline-flex items-center gap-1 rounded-md px-2 py-1 my-1 text-xs font-medium transition-all duration-300 ease-in-out bg-slate-300 text-white hover:bg-primary-600 hover:scale-105"
    >
      <span className="hero-map-pin-micro h-3.5 w-3.5" aria-hidden="true" />
      {target.tour ? 'Start the tour' : 'Take me there'}
    </button>
  );
};
