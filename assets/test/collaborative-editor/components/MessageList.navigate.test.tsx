/**
 * MessageList - "Take me there" navigation fences
 *
 * Apollo ends some replies with an `openfn-navigate` fence whose JSON body
 * names an app-map page. Covers the fence rendering as a NavigateButton, the
 * `lightning:start-tour` event it dispatches, malformed bodies rendering
 * nothing (a fence re-renders on every streaming delta, so half-parsed JSON
 * is routine), and ordinary fences still rendering as code blocks.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { MessageList } from '../../../js/collaborative-editor/components/MessageList';
import { createMockAIMessage } from '../__helpers__/aiAssistantHelpers';

Element.prototype.scrollIntoView = vi.fn();

let project: { id: string; name: string } | null = null;

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => project,
}));

const navigateReply = (body: string) => [
  createMockAIMessage({
    id: 'reply-1',
    role: 'assistant',
    content: `Here's how to set that up.\n\n\`\`\`openfn-navigate\n${body}\n\`\`\`\n`,
  }),
];

const startTourEvents = () => {
  const events: CustomEvent[] = [];
  const listener = (event: Event) => events.push(event as CustomEvent);
  document.addEventListener('lightning:start-tour', listener);
  return {
    events,
    cleanup: () =>
      document.removeEventListener('lightning:start-tour', listener),
  };
};

describe('MessageList openfn-navigate fences', () => {
  let tour: ReturnType<typeof startTourEvents>;

  beforeEach(() => {
    project = { id: 'project-123', name: 'Test Project' };
    tour = startTourEvents();
  });

  afterEach(() => {
    tour.cleanup();
    vi.clearAllMocks();
  });

  it('renders a Take me there button and dispatches the tour event on click', async () => {
    render(
      <MessageList
        messages={navigateReply('{"page": "project_settings", "tab": "vcs"}')}
      />
    );

    const button = screen.getByTestId('navigate-button');
    expect(button).toHaveTextContent('Take me there');

    await userEvent.click(button);

    expect(tour.events).toHaveLength(1);
    expect(tour.events[0].detail).toEqual({
      page: 'project_settings',
      tab: 'vcs',
      params: { project_id: 'project-123' },
    });
  });

  it('omits tab when the fence has none and sends empty params without a project', async () => {
    project = null;
    render(<MessageList messages={navigateReply('{"page": "dashboard"}')} />);

    await userEvent.click(screen.getByTestId('navigate-button'));

    expect(tour.events[0].detail).toEqual({
      page: 'dashboard',
      params: {},
    });
  });

  it('renders nothing for malformed or incomplete fence bodies', () => {
    const bodies = [
      '{"page": "project_set', // mid-stream truncation
      'not json at all',
      '{"tab": "vcs"}', // page missing
      '{"page": 42}', // page not a string
      '[]',
    ];

    for (const body of bodies) {
      const { unmount } = render(
        <MessageList messages={navigateReply(body)} />
      );
      expect(screen.queryByTestId('navigate-button')).not.toBeInTheDocument();
      unmount();
    }
  });

  it('still renders ordinary fences as code blocks', () => {
    render(
      <MessageList
        messages={[
          createMockAIMessage({
            id: 'reply-2',
            role: 'assistant',
            content: '```js\nfn(state => state);\n```\n',
          }),
        ]}
      />
    );

    expect(screen.queryByTestId('navigate-button')).not.toBeInTheDocument();
    // The highlighter splits the source into token spans, so match on the
    // block's whole text rather than a single node.
    const pre = document.querySelector('pre');
    expect(pre).toHaveTextContent('fn(state => state);');
  });
});
