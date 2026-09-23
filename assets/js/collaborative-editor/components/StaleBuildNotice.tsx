import { useEffect } from 'react';

import { notifications } from '../lib/notifications';

const TOAST_ID = 'stale-build';

export function StaleBuildNotice({
  staticChanged,
}: {
  staticChanged: boolean;
}) {
  useEffect(() => {
    if (!staticChanged) return;

    notifications.info({
      id: TOAST_ID,
      duration: Infinity,
      title: 'A new version of Lightning is available',
      description: 'Save any changes, then reload to update.',
      action: {
        label: 'Reload',
        onClick: () => window.location.reload(),
      },
    });
  }, [staticChanged]);

  return null;
}
