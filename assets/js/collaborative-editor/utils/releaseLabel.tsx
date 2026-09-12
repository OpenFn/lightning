/**
 * Shared label for a published workflow release (a go-live or a promote).
 *
 * Used by both the version dropdown and the Recent History markers so the two
 * surfaces read identically. Label set:
 * - promote → "Promoted sandbox {source_project}" (sandbox name emphasised)
 * - restore → "Restored v{n}", naming the version it put back
 * - first release (v1 go-live) → "Initial go-live"
 * - any later go-live → "Published from draft"
 */

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
