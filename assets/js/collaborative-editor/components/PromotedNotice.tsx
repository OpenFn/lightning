import { useEffect, useRef } from 'react';

import { notifications } from '../lib/notifications';
import { takePromoted } from '../lib/promoteHandoff';

/**
 * One-shot confirmation that a promote landed, shown on the parent project.
 *
 * The promote itself is confirmed in the dialog, but archiving the sandbox
 * reloads the page into the parent, and the flash that arrives with it speaks
 * only of the archive. This says the other half.
 *
 * Renders nothing; it exists to run the effect beside the mounted Toaster.
 */
export function PromotedNotice() {
  const shown = useRef(false);

  useEffect(() => {
    if (shown.current) return;
    if (!takePromoted()) return;

    shown.current = true;

    notifications.success({
      title: 'Promoted to parent project',
      description:
        'This workflow was merged into the parent project. The sandbox has been archived.',
    });
  }, []);

  return null;
}
