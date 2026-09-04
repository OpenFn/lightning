/**
 * MessageList - Undo control on a global assistant reply
 *
 * Covers when the control is offered, which YAML it restores, and the copy
 * button on the diff blocks it sits under.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { MessageList } from '../../../js/collaborative-editor/components/MessageList';
import type { Message } from '../../../js/collaborative-editor/types/ai-assistant';
import { createMockAIMessage } from '../__helpers__/aiAssistantHelpers';

Object.assign(navigator, {
  clipboard: { writeText: vi.fn(() => Promise.resolve()) },
});
Element.prototype.scrollIntoView = vi.fn();

const workflowYaml = (body: string) => `name: Test workflow
jobs:
  transform-data:
    id: job-1
    name: Transform data
    adaptor: "@openfn/language-common@latest"
    body: |
      ${body}
triggers:
  webhook:
    id: trigger-1
    type: webhook
    enabled: true
edges:
  webhook->transform-data:
    id: edge-1
    source_trigger: webhook
    target_job: transform-data
    condition_type: always
    enabled: true`;

const BASELINE_YAML = workflowYaml('fn(state => state);');
const APPLIED_YAML = workflowYaml('fn(state => ({ ...state, done: true }));');

/** A user request carrying the pre-reply workflow, then the reply that changed it */
const conversation = (reply: Partial<Message> = {}): [Message, Message] => [
  createMockAIMessage({
    id: 'user-1',
    role: 'user',
    content: 'Update the transform',
    code: BASELINE_YAML,
  }),
  createMockAIMessage({
    id: 'reply-1',
    role: 'assistant',
    content: 'Updated the transform.',
    from_global: true,
    code: APPLIED_YAML,
    ...reply,
  }),
];

describe('MessageList - undo applied changes', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('restores the baseline from the last global reply', async () => {
    const onUndoChanges = vi.fn();
    render(
      <MessageList messages={conversation()} onUndoChanges={onUndoChanges} />
    );

    await userEvent.click(screen.getByTestId('undo-changes-button'));

    // Undo restores YAML this app serialized, so it needs no id validation
    expect(onUndoChanges).toHaveBeenCalledWith('reply-1', BASELINE_YAML, {
      fromModel: false,
    });
  });

  it('offers to redo the reply once its changes are undone', async () => {
    const onUndoChanges = vi.fn();
    render(
      <MessageList
        messages={conversation()}
        onUndoChanges={onUndoChanges}
        undoneMessageId="reply-1"
      />
    );

    const button = screen.getByTestId('undo-changes-button');
    expect(button).toHaveTextContent('Redo these changes');

    await userEvent.click(button);
    // Redo restores the reply's own YAML, which the model wrote
    expect(onUndoChanges).toHaveBeenCalledWith('reply-1', APPLIED_YAML, {
      fromModel: true,
    });
  });

  it.each([
    [
      'an apply is in flight',
      { isApplyInFlight: true },
      {} as Partial<Message>,
    ],
    ['the workflow is read-only', { isWriteDisabled: true }, {}],
    ['the apply failed', { failedApplyMessageIds: new Set(['reply-1']) }, {}],
    ['the reply is not global', {}, { from_global: false }],
    // Never auto-applied, so there is nothing to undo — and "redo" would
    // apply the failed reply's code.
    ['the reply errored', {}, { status: 'error' as const }],
    ['the reply was cancelled', {}, { status: 'cancelled' as const }],
  ])('is not offered when %s', (_case, props, reply) => {
    render(
      <MessageList
        messages={conversation(reply)}
        onUndoChanges={vi.fn()}
        {...props}
      />
    );

    expect(screen.queryByTestId('undo-changes-button')).not.toBeInTheDocument();
  });

  it('is not offered on a reply another message follows', () => {
    render(
      <MessageList
        messages={[
          ...conversation(),
          createMockAIMessage({
            id: 'user-2',
            role: 'user',
            content: 'And now the trigger',
          }),
        ]}
        onUndoChanges={vi.fn()}
      />
    );

    expect(screen.queryByTestId('undo-changes-button')).not.toBeInTheDocument();
  });

  it('is not offered when the request carried no workflow to restore', () => {
    const [user, reply] = conversation();
    render(
      <MessageList
        messages={[{ ...user, code: undefined }, reply]}
        onUndoChanges={vi.fn()}
      />
    );

    expect(screen.queryByTestId('undo-changes-button')).not.toBeInTheDocument();
  });

  it('copies a changed step body from its diff block', async () => {
    render(<MessageList messages={conversation()} />);

    await userEvent.click(screen.getAllByTestId('diff-block-copy')[0]!);

    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
      expect.stringContaining('done: true')
    );
  });
});
