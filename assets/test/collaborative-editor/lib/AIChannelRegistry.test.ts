/**
 * AIChannelRegistry - Tests for streaming chunk buffering
 *
 * Focuses on the streaming-status handoff that lives in the channel buffer:
 * a text chunk arriving over the wire supersedes any active status, while a
 * status Apollo streams *after* the text answer must survive the slow
 * char-by-char drain.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

import { AIChannelRegistry } from '../../../js/collaborative-editor/lib/AIChannelRegistry';
import { createAIAssistantStore } from '../../../js/collaborative-editor/stores/createAIAssistantStore';
import type { AIAssistantStore } from '../../../js/collaborative-editor/types/ai-assistant';
import { createMockJobCodeContext } from '../__helpers__/aiAssistantHelpers';
import { createMockPhoenixChannel } from '../mocks/phoenixChannel';
import type { MockPhoenixChannel } from '../mocks/phoenixChannel';

describe('AIChannelRegistry streaming', () => {
  const topic = 'ai_assistant:job_code:session-1';
  let store: AIAssistantStore;
  let channel: MockPhoenixChannel;
  let registry: AIChannelRegistry;

  beforeEach(() => {
    vi.useFakeTimers();

    store = createAIAssistantStore();
    channel = createMockPhoenixChannel(topic);

    const socket = {
      channel: () => channel,
      isConnected: () => true,
    };

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    registry = new AIChannelRegistry(socket as any, store as any);

    // Subscribe wires up the channel event handlers (streaming_chunk, etc.)
    registry.subscribe(topic, 'subscriber-1', createMockJobCodeContext());
  });

  afterEach(() => {
    registry.destroy();
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it('keeps the steps and summary a status reports', () => {
    channel._test.emit('streaming_segment', {
      segment: {
        type: 'status',
        content: 'Wrote code for "Transform data"',
        summary: 'Wrote code for 1 step',
        steps: [{ key: 'transform-data', name: 'Transform data' }],
      },
    });
    vi.advanceTimersByTime(100);

    expect(store.getSnapshot().streamingSegments).toEqual([
      {
        type: 'status',
        content: 'Wrote code for "Transform data"',
        summary: 'Wrote code for 1 step',
        steps: [{ key: 'transform-data', name: 'Transform data' }],
      },
    ]);
  });

  it('omits steps and summary when an older Apollo does not send them', () => {
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Edited workflow structure' },
    });
    vi.advanceTimersByTime(100);

    // Absent, not empty: the timeline must not read this as "touched no
    // steps", which would be a claim the payload never made.
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'status', content: 'Edited workflow structure' },
    ]);
  });

  it('drops steps that carry no key to identify them by', () => {
    channel._test.emit('streaming_segment', {
      segment: {
        type: 'status',
        content: 'Wrote code',
        steps: [{ name: 'Transform data' }, { key: 'send-to-gmail' }],
      },
    });
    vi.advanceTimersByTime(100);

    expect(store.getSnapshot().streamingSegments).toEqual([
      {
        type: 'status',
        content: 'Wrote code',
        steps: [{ key: 'send-to-gmail' }],
      },
    ]);
  });

  it('holds a workflow snapshot behind the text that preceded it on the wire', () => {
    channel._test.emit('streaming_chunk', { content: 'First' });
    channel._test.emit('streaming_changes', { changes: { yaml: 'yaml-a' } });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Edited workflow structure' },
    });

    // The snapshot must not enter the timeline while earlier prose is still
    // typing out, or it would attach to the wrong status row.
    vi.advanceTimersByTime(4 * 15);
    expect(store.getSnapshot().streamingSnapshots).toEqual([]);

    vi.advanceTimersByTime(1000);
    expect(store.getSnapshot().streamingSnapshots).toEqual([
      { yaml: 'yaml-a', segmentIndex: 1 },
    ]);
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'text', content: 'First' },
      { type: 'status', content: 'Edited workflow structure' },
    ]);
  });

  it('sets the scalar changes immediately so the canvas does not wait on the drain', () => {
    channel._test.emit('streaming_chunk', { content: 'Some long answer here' });
    channel._test.emit('streaming_changes', { changes: { yaml: 'yaml-a' } });

    // The canvas apply path reads the scalar and must fire at once, even
    // though the timeline snapshot is still queued behind the prose.
    expect(store.getSnapshot().streamingChanges).toEqual({ yaml: 'yaml-a' });
    expect(store.getSnapshot().streamingSnapshots).toEqual([]);
  });

  it('keeps snapshots and statuses in wire order across several actions', () => {
    channel._test.emit('streaming_changes', { changes: { yaml: 'yaml-a' } });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Edited workflow structure' },
    });
    channel._test.emit('streaming_changes', { changes: { yaml: 'yaml-b' } });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Wrote code for "Transform"' },
    });

    vi.advanceTimersByTime(1000);

    expect(store.getSnapshot().streamingSnapshots).toEqual([
      { yaml: 'yaml-a', segmentIndex: 0 },
      { yaml: 'yaml-b', segmentIndex: 1 },
    ]);
  });

  it('ignores a changes event that carries job code rather than a workflow', () => {
    channel._test.emit('streaming_changes', {
      changes: { code: 'fn(s => s);' },
    });
    vi.advanceTimersByTime(1000);

    expect(store.getSnapshot().streamingSnapshots).toEqual([]);
    expect(store.getSnapshot().streamingChanges).toEqual({
      code: 'fn(s => s);',
    });
  });

  it('clears an active status when a text chunk arrives over the wire', () => {
    // A status is showing (e.g. "Writing code...") when text starts streaming.
    channel._test.emit('streaming_status', { text: 'Writing code...' });
    expect(store.getSnapshot().streamingStatus).toBe('Writing code...');

    channel._test.emit('streaming_chunk', { content: 'Here is the answer' });

    // Cleared at network arrival, before any draining happens.
    expect(store.getSnapshot().streamingStatus).toBeNull();
  });

  it('keeps a status streamed after the text answer through the char drain', () => {
    // Text answer starts streaming first.
    channel._test.emit('streaming_chunk', { content: 'Answer' });

    // Apollo then streams a status *after* the text.
    channel._test.emit('streaming_status', { text: 'Writing code...' });

    // Drain the entire buffer char-by-char (15ms per char).
    vi.advanceTimersByTime(500);

    // The per-char drain must not wipe a status set after the text.
    expect(store.getSnapshot().streamingStatus).toBe('Writing code...');
    expect(store.getSnapshot().streamingContent).toBe('Answer');
  });

  it('preserves wire order of text and status segments in the streaming timeline', () => {
    channel._test.emit('streaming_chunk', { content: 'First' });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Added step' },
    });
    channel._test.emit('streaming_chunk', { content: 'Second' });

    // The segment must not enter the timeline before the text preceding it
    // on the wire has drained ("First" = 5 chars at 15ms each).
    vi.advanceTimersByTime(4 * 15);
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'text', content: 'Firs' },
    ]);

    // Drain everything.
    vi.advanceTimersByTime(1000);
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'text', content: 'First' },
      { type: 'status', content: 'Added step' },
      { type: 'text', content: 'Second' },
    ]);
    expect(store.getSnapshot().streamingContent).toBe('FirstSecond');
  });

  it('keeps thinking statuses out of the timeline and supersedes them with status segments', () => {
    // Thinking events only touch the scalar, never the timeline.
    channel._test.emit('streaming_status', { text: 'Reviewing workflow...' });
    expect(store.getSnapshot().streamingStatus).toBe('Reviewing workflow...');
    expect(store.getSnapshot().streamingSegments).toEqual([]);

    // A persistent status segment clears the thinking scalar at arrival...
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Reviewed workflow' },
    });
    expect(store.getSnapshot().streamingStatus).toBeNull();

    // ...and lands in the timeline via the drain.
    vi.advanceTimersByTime(200);
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'status', content: 'Reviewed workflow' },
    ]);
  });

  it('flushes a trailing status into the timeline before the final message lands', () => {
    // Track timeline appends so we can assert the status entered the
    // timeline before finalization cleared the streaming state.
    const appended: unknown[] = [];
    const originalAppend = store._appendStreamingSegment.bind(store);
    store._appendStreamingSegment = segment => {
      appended.push(segment);
      originalAppend(segment);
    };

    channel._test.emit('streaming_chunk', { content: 'Hi' });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Validated workflow' },
    });
    channel._test.emit('new_message', {
      message: {
        id: 'final-1',
        role: 'assistant',
        content: 'Hi',
        status: 'success',
      },
    });

    // Drain everything; drainThenRun must flush the due status marker
    // before running the finalize callback.
    vi.advanceTimersByTime(1000);

    expect(appended).toContainEqual({
      type: 'status',
      content: 'Validated workflow',
    });
    expect(
      store.getSnapshot().messages.find(m => m.id === 'final-1')
    ).toBeTruthy();
  });

  it('does not leak pending status markers from an errored stream into the next one', () => {
    // A status is pinned behind text that will never finish draining.
    channel._test.emit('streaming_chunk', { content: 'Long answer text' });
    channel._test.emit('streaming_segment', {
      segment: { type: 'status', content: 'Stale status from dead stream' },
    });

    // The stream errors before the drain reaches the status marker.
    vi.advanceTimersByTime(2 * 15);
    channel._test.emit('streaming_error', { error: 'boom' });
    expect(store.getSnapshot().streamingSegments).toEqual([]);

    // A fresh stream starts and fully drains.
    channel._test.emit('streaming_chunk', { content: 'New' });
    vi.advanceTimersByTime(500);

    // Only the new stream's text is in the timeline — the dead stream's
    // status marker must not resurface.
    expect(store.getSnapshot().streamingSegments).toEqual([
      { type: 'text', content: 'New' },
    ]);
  });
});
