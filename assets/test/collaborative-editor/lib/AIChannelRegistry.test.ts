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
});
