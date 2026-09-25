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
      isPinnedVersion: false,
      isPinnedView: true,
    });
  });

  test('carries the pinned number whichever numbering set it', () => {
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
    expect(readPinnedView({ [RELEASE_PARAM]: '' }).isPinnedRelease).toBe(false);
    expect(readPinnedView({ [SNAPSHOT_PARAM]: '' }).isPinnedSnapshot).toBe(
      false
    );
  });
});

describe('collaborationRoomName', () => {
  test('the number 3 builds two different rooms, depending on what it numbers', () => {
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
