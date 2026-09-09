/**
 * WorkflowStore - what edit_in_sandbox puts on the wire.
 *
 * A reviewed body travels by value so the person's edits are what land; a saved
 * dataclip travels by id and is copied server-side.
 */

import type { Channel } from 'phoenix';
import type { PhoenixChannelProvider } from 'y-phoenix-channel';
import * as Y from 'yjs';
import { beforeEach, describe, expect, test } from 'vitest';

import { createWorkflowStore } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { WorkflowStoreInstance } from '../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Session } from '../../../js/collaborative-editor/types/session';
import { createMockChannelPushWithHandler } from '../__helpers__/channelMocks';

describe('WorkflowStore - editInSandbox', () => {
  let store: WorkflowStoreInstance;
  let sent: { event: string; payload: unknown }[];

  beforeEach(() => {
    store = createWorkflowStore();
    const ydoc = new Y.Doc() as Session.WorkflowDoc;
    sent = [];

    const mockChannel = {
      push: createMockChannelPushWithHandler((event, payload) => {
        sent.push({ event, payload });
        return {
          okResponse: {
            project_id: 'p1',
            workflow_id: 'w1',
            dataclip_id: 'dc1',
          },
        };
      }),
      on: () => {},
    } as unknown as Channel;

    const provider = {
      channel: mockChannel,
      synced: true,
      awareness: null,
      doc: ydoc,
    } as unknown as PhoenixChannelProvider & { channel: Channel };

    ydoc.getMap('workflow').set('id', 'workflow-123');
    ydoc.getArray('jobs');
    ydoc.getArray('triggers');
    ydoc.getArray('edges');
    ydoc.getMap('positions');

    store.connect(ydoc, provider);
  });

  const lastPayload = () => sent[sent.length - 1]?.payload;

  test('sends nothing extra when no starting data is chosen', async () => {
    await store.editInSandbox('My SB');

    expect(lastPayload()).toEqual({ name: 'My SB' });
  });

  test('sends a reviewed body by value, with the name it should carry', async () => {
    await store.editInSandbox('My SB', {
      body: '{"email":"redacted"}',
      bodyName: 'Input from run abcdef',
    });

    expect(lastPayload()).toEqual({
      name: 'My SB',
      starting_dataclip: {
        body: '{"email":"redacted"}',
        name: 'Input from run abcdef',
      },
    });
  });

  test('sends a saved dataclip by id instead', async () => {
    await store.editInSandbox('My SB', { dataclipId: 'dc-saved' });

    expect(lastPayload()).toEqual({
      name: 'My SB',
      dataclip_id: 'dc-saved',
    });
  });

  test('prefers the reviewed body when both are somehow given', async () => {
    await store.editInSandbox('My SB', {
      body: '{}',
      dataclipId: 'dc-saved',
    });

    expect(lastPayload()).toEqual({
      name: 'My SB',
      starting_dataclip: { body: '{}', name: null },
    });
  });

  test('returns where the reviewed body landed', async () => {
    const result = await store.editInSandbox('My SB', { body: '{}' });

    expect(result.dataclip_id).toBe('dc1');
  });
});
