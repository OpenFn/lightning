/** The toast shown after landing in the parent project from a promote. */

import { useEffect, useRef } from 'react';

import { notifications } from '../lib/notifications';
import { takePromoted } from '../lib/promoteHandoff';

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

    params.delete('archived');
    const search = params.toString();
    const url = `${window.location.pathname}${search ? `?${search}` : ''}${window.location.hash}`;
    window.history.replaceState(window.history.state, '', url);
  }, []);

  return null;
}
