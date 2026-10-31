/**
 * The three URL parameters that pin a view of the past, and the view they
 * describe. One place, so the suffix a client builds and the suffix the channel
 * parses cannot drift.
 */

import { useURLState } from '#/react/lib/use-url-state';

export const RELEASE_PARAM = 'release';

export const SNAPSHOT_PARAM = 'v';

export const AS_RUN_PARAM = 'as_run';

export interface PinnedView {
  release: string | null;
  snapshot: string | null;
  asRun: string | null;
  isPinnedRelease: boolean;
  isPinnedSnapshot: boolean;
  isViewingAsExecuted: boolean;
  isPinnedVersion: boolean;
  version: string | null;
  isPinnedView: boolean;
}

const value = (param: string | undefined): string | null =>
  param === undefined || param === null || param === '' ? null : param;

export function readPinnedView(
  params: Record<string, string | undefined>
): PinnedView {
  const release = value(params[RELEASE_PARAM]);
  const snapshot = value(params[SNAPSHOT_PARAM]);
  const asRun = value(params[AS_RUN_PARAM]);

  return {
    release,
    snapshot,
    asRun,
    isPinnedRelease: release !== null,
    isPinnedSnapshot: snapshot !== null,
    isViewingAsExecuted: asRun !== null,
    isPinnedVersion: release !== null || snapshot !== null,
    version: release ?? snapshot,
    isPinnedView: release !== null || snapshot !== null || asRun !== null,
  };
}

export function usePinnedView(): PinnedView {
  const { params } = useURLState();

  return readPinnedView(params);
}

export function collaborationRoomName(
  workflowId: string,
  view: Pick<PinnedView, 'release' | 'snapshot' | 'asRun'>
): string {
  const room = `workflow:collaborate:${workflowId}`;

  if (view.asRun !== null) return `${room}:run:${view.asRun}`;
  if (view.release !== null) return `${room}:release${view.release}`;
  if (view.snapshot !== null) return `${room}:v${view.snapshot}`;

  return room;
}

export const CLEAR_PINNED_VIEW = {
  [RELEASE_PARAM]: null,
  [SNAPSHOT_PARAM]: null,
  [AS_RUN_PARAM]: null,
} as const;
