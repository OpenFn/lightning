import { useEffect, useRef } from 'react';

import { notifications } from '../lib/notifications';

/**
 * PromotedNotice - one-shot success toast for a completed sandbox promote.
 *
 * Promoting a sandbox hard-navigates into the parent project's editor (a
 * different Y.Doc session), so a toast fired before that navigation would be
 * destroyed on reload. Instead, the promote handler hands the feedback off
 * through the URL: `?promoted=1`. On load we read that marker, surface the
 * toast, and immediately strip the param via replaceState so a refresh doesn't
 * replay it.
 *
 * Renders nothing; it only exists to run the effect near the mounted Toaster.
 */
export function PromotedNotice() {
  const shown = useRef(false);

  useEffect(() => {
    if (shown.current) return;

    const params = new URLSearchParams(window.location.search);
    if (params.get('promoted') !== '1') return;
    shown.current = true;

    notifications.success({
      title: 'Promoted to parent project',
      description:
        'This workflow was merged into the parent project. The sandbox has been archived.',
    });

    // Strip the one-shot marker without adding a history entry so a refresh
    // doesn't re-show the toast.
    params.delete('promoted');
    const search = params.toString();
    const url = `${window.location.pathname}${search ? `?${search}` : ''}${window.location.hash}`;
    window.history.replaceState(window.history.state, '', url);
  }, []);

  return null;
}
