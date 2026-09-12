/**
 * Tests for the pinned-view contract: which URL parameter means what, and which
 * collaboration room each one joins.
 *
 * The room suffix is not cosmetic. A collaborative document is identified by its
 * name and nothing else, and a document that is already running is handed to the
 * next joiner exactly as it stands, so two views that mean different content
 * must never build the same suffix.
 *
 * Both numbering schemes used to be spelled `?v=`. A release is numbered by the
 * publish trail and a snapshot by its own lock_version, so release 3 and
 * lock_version 3 are ordinarily different content — and under one `:v3` room
 * whichever view opened first decided what the other one saw.
 *
 * The suffixes here are parsed on the server by
 * `LightningWeb.WorkflowChannel.parse_room_topic/1`. Change one side and the
 * other must change with it.
 */

import { describe, expect, test } from 'vitest';

import {
  AS_RUN_PARAM,
  CLEAR_PINNED_VIEW,
  RELEASE_PARAM,
  SNAPSHOT_PARAM,
  collaborationRoomName,
  readPinnedView,
} from '../../../js/collaborative-editor/lib/pinnedView';

const WORKFLOW = 'wf-1';

const roomFor = (params: Record<string, string>) =>
  collaborationRoomName(WORKFLOW, readPinnedView(params));

describe('readPinnedView', () => {
  test('reads each parameter, and answers the questions asked of it', () => {
    expect(readPinnedView({ [RELEASE_PARAM]: '3' })).toMatchObject({
      release: '3',
      snapshot: null,
      asRun: null,
      isPinnedRelease: true,
      isPinnedSnapshot: false,
      isViewingAsExecuted: false,
      isPinnedVersion: true,
      isPinnedView: true,
    });

    expect(readPinnedView({ [SNAPSHOT_PARAM]: '3' })).toMatchObject({
      release: null,
      snapshot: '3',
      isPinnedRelease: false,
      isPinnedSnapshot: true,
      isPinnedVersion: true,
      isPinnedView: true,
    });

    expect(readPinnedView({ [AS_RUN_PARAM]: 'run-1' })).toMatchObject({
      asRun: 'run-1',
      isViewingAsExecuted: true,
      // A run's own view pins no version number, so a caller asking "which
      // version is pinned?" must be told none, while a caller asking "may this
      // be edited?" is told no.
      isPinnedVersion: false,
      isPinnedView: true,
    });
  });

  test('carries the pinned number whichever numbering set it', () => {
    // For callers that only need to notice a switch, not resolve the number.
    // Reading one scheme means missing every switch made in the other, which is
    // how the AI assistant kept a stale panel open across a `?v=` switch.
    expect(readPinnedView({ [RELEASE_PARAM]: '3' }).version).toBe('3');
    expect(readPinnedView({ [SNAPSHOT_PARAM]: '7' }).version).toBe('7');
    expect(readPinnedView({ [AS_RUN_PARAM]: 'run-1' }).version).toBe(null);
    expect(readPinnedView({}).version).toBe(null);
  });

  test('the live workflow is nothing pinned at all', () => {
    expect(readPinnedView({})).toMatchObject({
      release: null,
      snapshot: null,
      asRun: null,
      isPinnedVersion: false,
      isPinnedView: false,
    });
  });

  test('an empty parameter is no parameter', () => {
    // A URL left with `?release=` after a partial edit must not read as a
    // release pinned to nothing, which would join `:release` and fail to parse.
    expect(readPinnedView({ [RELEASE_PARAM]: '' }).isPinnedRelease).toBe(false);
    expect(readPinnedView({ [SNAPSHOT_PARAM]: '' }).isPinnedSnapshot).toBe(
      false
    );
  });
});

describe('collaborationRoomName', () => {
  test('the number 3 builds two different rooms, depending on what it numbers', () => {
    // The assertion this whole change exists for.
    const release = roomFor({ [RELEASE_PARAM]: '3' });
    const snapshot = roomFor({ [SNAPSHOT_PARAM]: '3' });

    expect(release).toBe(`workflow:collaborate:${WORKFLOW}:release3`);
    expect(snapshot).toBe(`workflow:collaborate:${WORKFLOW}:v3`);
    expect(release).not.toBe(snapshot);
  });

  test('a run gets a room of its own, and wins over a version pin', () => {
    expect(roomFor({ [AS_RUN_PARAM]: 'run-1' })).toBe(
      `workflow:collaborate:${WORKFLOW}:run:run-1`
    );

    // The two are mutually exclusive views, and reading a run as it executed is
    // the more specific intent.
    expect(roomFor({ [AS_RUN_PARAM]: 'run-1', [RELEASE_PARAM]: '3' })).toBe(
      `workflow:collaborate:${WORKFLOW}:run:run-1`
    );
  });

  test('nothing pinned is the live collaborative room', () => {
    expect(roomFor({})).toBe(`workflow:collaborate:${WORKFLOW}`);
  });
});

describe('CLEAR_PINNED_VIEW', () => {
  test('clears both numbering schemes, not only the one in use', () => {
    // A bookmark carrying the other scheme would otherwise survive the switch
    // and pin the view straight back.
    expect(CLEAR_PINNED_VIEW).toEqual({
      [RELEASE_PARAM]: null,
      [SNAPSHOT_PARAM]: null,
      [AS_RUN_PARAM]: null,
    });

    expect(readPinnedView({ ...CLEAR_PINNED_VIEW } as never).isPinnedView).toBe(
      false
    );
  });
});
