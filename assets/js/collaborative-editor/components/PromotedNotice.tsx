import { useEffect, useRef } from 'react';

import { notifications } from '../lib/notifications';
import { takePromoted } from '../lib/promoteHandoff';

/**
 * Says what happened when the server lands you here from an archived sandbox.
 *
 * Archiving is the server's navigation, and it marks the destination with
 * `?archived=1` rather than setting a flash, because this page is React and a
 * flash would put a second notification from a different system over the
 * canvas. The marker reaches everyone the redirect moved, not only whoever
 * archived.
 *
 * Whoever promoted also carries a local marker, so their message names the
 * promote as well. Both are consumed on read, so a refresh stays quiet.
 *
 * Renders nothing; it exists to run the effect beside the mounted Toaster.
 */
export function PromotedNotice() {
  const shown = useRef(false);

  useEffect(() => {
    if (shown.current) return;

    const params = new URLSearchParams(window.location.search);
    if (params.get('archived') !== '1') {
      takePromoted();
      return;
    }

    shown.current = true;

    notifications.success(
      takePromoted()
        ? {
            title: 'Promoted to parent project',
            description:
              'This workflow was merged into the parent project. The sandbox has been archived.',
          }
        : {
            title: 'Sandbox archived',
            description: "You are now on the parent project's workflow.",
          }
    );

    // Strip the marker without adding a history entry, so a refresh does not
    // replay the message.
    params.delete('archived');
    const search = params.toString();
    const url = `${window.location.pathname}${search ? `?${search}` : ''}${window.location.hash}`;
    window.history.replaceState(window.history.state, '', url);
  }, []);

  return null;
}
