import { renderHook, waitFor } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { useCustomPathTaken } from '../../../../../js/collaborative-editor/components/inspector/trigger/useCustomPathTaken';
import {
  createMockChannelPushError,
  createMockChannelPushOk,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

/** Accepts the push and never answers. */
function silentPush() {
  return vi.fn(() => ({
    receive: () => ({ receive: () => ({ receive: () => ({}) }) }),
  })) as never;
}

describe('useCustomPathTaken', () => {
  test('asks the server and reports a name in use', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = createMockChannelPushOk({ taken: true });

    const { result } = renderHook(
      () => useCustomPathTaken('facility-001', TRIGGER_ID),
      { wrapper }
    );

    await waitFor(() => {
      expect(result.current.taken).toBe(true);
    });

    expect(sessionChannel.push).toHaveBeenCalledWith('check_custom_path', {
      custom_path: 'facility-001',
      trigger_id: TRIGGER_ID,
    });
  });

  test('reports a free name as free', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = createMockChannelPushOk({ taken: true });

    // Starting from a taken path, so this cannot pass on the initial state.
    const { result, rerender } = renderHook(
      ({ path }: { path: string }) => useCustomPathTaken(path, TRIGGER_ID),
      { wrapper, initialProps: { path: 'facility-001' } }
    );

    await waitFor(() => {
      expect(result.current.taken).toBe(true);
    });

    sessionChannel.push = createMockChannelPushOk({ taken: false });
    rerender({ path: 'facility-002' });

    await waitFor(() => {
      expect(result.current).toEqual({
        taken: false,
        pending: false,
        showPending: false,
      });
    });
  });

  test('drops the previous answer as soon as the path changes', async () => {
    // Otherwise someone who has just fixed a duplicate still reads "already
    // used" while looking at a free name.
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = createMockChannelPushOk({ taken: true });

    const { result, rerender } = renderHook(
      ({ path }: { path: string }) => useCustomPathTaken(path, TRIGGER_ID),
      { wrapper, initialProps: { path: 'facility-001' } }
    );

    await waitFor(() => {
      expect(result.current.taken).toBe(true);
    });

    sessionChannel.push = silentPush();
    rerender({ path: 'facility-001-fixed' });

    expect(result.current).toEqual({
      taken: false,
      pending: true,
      showPending: false,
    });
  });

  test('a quick answer is never overwritten by the pending state', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = createMockChannelPushOk({ taken: true });

    const seen: boolean[] = [];
    const { result } = renderHook(
      () => {
        const check = useCustomPathTaken('facility-001', TRIGGER_ID);
        seen.push(check.showPending);
        return check;
      },
      { wrapper }
    );

    await waitFor(() => {
      expect(result.current.taken).toBe(true);
    });

    // Past the point the reveal would have fired.
    await new Promise(resolve => setTimeout(resolve, 600));

    expect(seen).not.toContain(true);
    expect(result.current.taken).toBe(true);
  });

  test('says it is checking when the answer is slow to arrive', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = silentPush();

    const { result } = renderHook(
      () => useCustomPathTaken('facility-003', TRIGGER_ID),
      { wrapper }
    );

    await waitFor(() => {
      expect(result.current.showPending).toBe(true);
    });
  });

  test('a check that fails stops blocking rather than claiming free', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    sessionChannel.push = createMockChannelPushError('boom');

    const { result } = renderHook(
      () => useCustomPathTaken('facility-004', TRIGGER_ID),
      { wrapper }
    );

    await waitFor(() => {
      expect(result.current.pending).toBe(false);
    });

    expect(result.current.taken).toBe(false);
  });

  test('does not ask about a path the server would reject anyway', async () => {
    const { wrapper, sessionChannel } = await createTriggerTestHarness({});
    const push = vi.fn(createMockChannelPushOk({ taken: true }));
    sessionChannel.push = push;

    renderHook(() => useCustomPathTaken('Not A Path', TRIGGER_ID), { wrapper });

    await new Promise(resolve => setTimeout(resolve, 400));

    expect(push).not.toHaveBeenCalledWith(
      'check_custom_path',
      expect.anything()
    );
  });
});
