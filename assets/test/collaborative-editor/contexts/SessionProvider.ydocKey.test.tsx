/**
 * Which value keys the Y.Doc.
 *
 * `useYDocPersistence` resets the document when its `version` changes. That was
 * the release parameter, which is null for anyone without experimental
 * features, so on that path pinning an older version never read as a change:
 * the connection indicator kept the previous room's error and last sync time.
 * The room name changes for every view parameter, so it is what keys it.
 *
 * Tested at the call, not through the effect. Driving it through a mock
 * provider proves nothing, because the provider re-syncs the moment the room
 * changes and paints the cleared state straight back over.
 */

import { render } from '@testing-library/react';

import type React from 'react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';

const useYDocPersistence = vi.fn();

vi.mock('../../../js/collaborative-editor/hooks/useYDocPersistence', () => ({
  useYDocPersistence: (options: unknown) => {
    useYDocPersistence(options);
    return { ydoc: null, hasInitialized: { current: false } };
  },
}));

vi.mock('../../../js/react/contexts/SocketProvider', () => ({
  useSocket: () => ({ socket: null, isConnected: false }),
  SocketProvider: ({ children }: { children: React.ReactNode }) => children,
}));

import { SessionProvider } from '../../../js/collaborative-editor/contexts/SessionProvider';

const versionPassed = () =>
  (useYDocPersistence.mock.calls.at(-1)?.[0] as { version: string | null })
    .version;

beforeEach(() => {
  useYDocPersistence.mockClear();
});

afterEach(() => {
  window.history.pushState({}, '', '/');
});

test('keys the document on the room, not on the release parameter', () => {
  window.history.pushState({}, '', '/?v=2');

  render(
    <SessionProvider
      workflowId="wf-1"
      projectId="proj-1"
      isNewWorkflow={false}
      experimentalFeatures={false}
    >
      <div />
    </SessionProvider>
  );

  // `?v=` leaves the release parameter null, which is the whole point: a user
  // without the flag pins snapshots, so keying on the release meant the
  // document never changed for them.
  expect(versionPassed()).toBe('workflow:collaborate:wf-1:v2');
});

test('and on the plain room when nothing is pinned', () => {
  render(
    <SessionProvider
      workflowId="wf-1"
      projectId="proj-1"
      isNewWorkflow={false}
      experimentalFeatures={false}
    >
      <div />
    </SessionProvider>
  );

  expect(versionPassed()).toBe('workflow:collaborate:wf-1');
});
