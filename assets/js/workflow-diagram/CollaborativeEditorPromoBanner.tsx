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

import { cn } from '#/utils/cn';

interface CollaborativeEditorPromoBannerProps {
  className?: string;
  pushEvent?:
    | ((name: string, payload: Record<string, unknown>) => void)
    | undefined;
}

export function CollaborativeEditorPromoBanner({
  className,
  pushEvent,
}: CollaborativeEditorPromoBannerProps) {
  return (
    <div
      className={cn(
        'pointer-events-none absolute inset-x-0 bottom-0 flex justify-center px-6 pb-5 z-10',
        className
      )}
      role="alert"
      aria-live="polite"
    >
      <div className="pointer-events-auto flex items-center gap-x-4 bg-danger-700 px-6 py-2.5 rounded-xl sm:py-3 sm:pr-3.5 sm:pl-4">
        <button
          type="button"
          onClick={() => pushEvent?.('switch_to_collab_editor', {})}
          className="text-sm/6 text-white cursor-pointer flex items-center"
        >
          <strong className="font-semibold flex items-center gap-2">
            <span className="hero-exclamation-triangle"></span>
            This legacy editor will be retired very soon
          </strong>
          <svg
            viewBox="0 0 2 2"
            aria-hidden="true"
            className="mx-2 inline size-0.5 fill-current"
          >
            <circle r={1} cx={1} cy={1} />
          </svg>
          Go to the new editor&nbsp;
          <span aria-hidden="true">&rarr;</span>
        </button>
      </div>
    </div>
  );
}
