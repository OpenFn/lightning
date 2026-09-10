/**
 * The URL parameters that pin the editor to something other than the live
 * workflow, and the collaboration room each one joins.
 *
 * These two things live in one file because they are one contract. A
 * collaborative document is identified by its room suffix and nothing else, and
 * a document that is already running is handed to the next joiner as it stands,
 * content included. So two views that mean different content must never build
 * the same suffix.
 *
 * That is why `?release=` and `?v=` are separate. A release is numbered by the
 * publish trail; a snapshot is numbered by its own lock_version. Release 3 and
 * lock_version 3 are ordinarily different content, so they build `:release3`
 * and `:v3`. When both numbering schemes were spelled `?v=` they built the same
 * room, and whichever view opened first decided what the other one saw.
 *
 * Reading the parameters in one place also means the names appear once. Every
 * component used to test `params['v']` by hand, which is what made the release
 * experience hard to put behind a flag.
 */

import { useURLState } from '#/react/lib/use-url-state';

/** A published release, numbered by the publish trail. */
export const RELEASE_PARAM = 'release';

/** A snapshot, numbered by its own lock_version. */
export const SNAPSHOT_PARAM = 'v';

/** The workflow exactly as one run executed it. */
export const AS_RUN_PARAM = 'as_run';

export interface PinnedView {
  /** `?release=<version_number>`, or null. */
  release: string | null;
  /** `?v=<lock_version>`, or null. */
  snapshot: string | null;
  /** `?as_run=<run_id>`, or null. */
  asRun: string | null;
  isPinnedRelease: boolean;
  isPinnedSnapshot: boolean;
  isViewingAsExecuted: boolean;
  /**
   * Pinned by either numbering. Use this wherever the question is "is a version
   * pinned?" and the number itself does not matter, so the answer cannot depend
   * on which scheme the URL happens to be using.
   */
  isPinnedVersion: boolean;
  /**
   * Any of the three. A view of the past is for reading, so this is the answer
   * to "may this be edited, run, or saved?" for all of them at once.
   */
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
    isPinnedView: release !== null || snapshot !== null || asRun !== null,
  };
}

/**
 * Deliberately not memoised. It is three property reads, and the object it
 * returns is rebuilt every render, so callers must depend on the fields rather
 * than on the object. Memoising on the params object would make the answer stale
 * wherever that object is mutated in place rather than replaced.
 */
export function usePinnedView(): PinnedView {
  const { params } = useURLState();

  return readPinnedView(params);
}

/**
 * The room a given view joins. The server splits this suffix back apart in
 * `LightningWeb.WorkflowChannel.parse_room_topic/1`, so the two must agree
 * exactly.
 *
 * `as_run` wins over a pinned number: it is the more specific intent, and the
 * views are mutually exclusive anyway.
 */
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

/**
 * The parameters to clear when leaving a pinned view. Both numbering schemes go,
 * not just the one in use: a link or bookmark carrying the other one would
 * otherwise survive the switch and pin the view straight back.
 */
export const CLEAR_PINNED_VIEW = {
  [RELEASE_PARAM]: null,
  [SNAPSHOT_PARAM]: null,
  [AS_RUN_PARAM]: null,
} as const;
