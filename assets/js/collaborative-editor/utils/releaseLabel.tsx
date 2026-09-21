/** How a release describes itself in the version list: published, promoted or restored. */

import type { Release } from '../types/sessionContext';

type ReleaseLike = Pick<
  Release,
  'kind' | 'source_project' | 'version_number' | 'restored_from_version_number'
>;

export function releaseActionLabel(version: ReleaseLike): React.ReactNode {
  if (version.kind === 'promote') {
    return (
      <>
        Promoted sandbox{' '}
        <span className="font-medium">{version.source_project}</span>
      </>
    );
  }

  if (version.kind === 'restore') {
    return (
      <>
        Restored{' '}
        <span className="font-medium">
          v{version.restored_from_version_number}
        </span>
      </>
    );
  }

  return version.version_number === 1
    ? 'Initial go-live'
    : 'Published from draft';
}
