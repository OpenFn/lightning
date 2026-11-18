/**
 * MessageList - "Take me there" navigation fences
 *
 * Apollo ends some replies with an `openfn-navigate` fence whose JSON body
 * names an app-map page. Covers the fence rendering as a NavigateButton, the
 * `lightning:start-tour` event it dispatches, malformed bodies rendering
 * nothing (a fence re-renders on every streaming delta, so half-parsed JSON
 * is routine), and ordinary fences still rendering as code blocks.
 */

import { fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { MessageList } from '../../../js/collaborative-editor/components/MessageList';
import { resetButtonShownTracking } from '../../../js/collaborative-editor/components/NavigateButton';
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

type FetchMock = ReturnType<typeof vi.fn>;

/** The telemetry bodies posted to /api/tour_events, in order. */
const tourTelemetry = (fetchMock: FetchMock): Array<Record<string, unknown>> =>
  fetchMock.mock.calls
    .filter(call => call[0] === '/api/tour_events')
    .map(
      call =>
        JSON.parse((call[1] as RequestInit).body as string) as Record<
          string,
          unknown
        >
    );

describe('MessageList openfn-navigate fences', () => {
  let tour: ReturnType<typeof startTourEvents>;
  let fetchMock: FetchMock;

  beforeEach(() => {
    project = { id: 'project-123', name: 'Test Project' };
    tour = startTourEvents();
    fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    vi.stubGlobal('fetch', fetchMock);
    resetButtonShownTracking();
  });

  afterEach(() => {
    tour.cleanup();
    vi.unstubAllGlobals();
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

  it('includes element in the event detail when the fence names one', async () => {
    render(
      <MessageList
        messages={navigateReply(
          '{"page": "workflow_edit", "element": "credential-picker"}'
        )}
      />
    );

    await userEvent.click(screen.getByTestId('navigate-button'));

    expect(tour.events).toHaveLength(1);
    expect(tour.events[0].detail).toEqual({
      page: 'workflow_edit',
      element: 'credential-picker',
      params: { project_id: 'project-123' },
    });
  });

  it('drops a non-string element but still dispatches the tour', async () => {
    render(
      <MessageList
        messages={navigateReply('{"page": "workflow_edit", "element": 42}')}
      />
    );

    await userEvent.click(screen.getByTestId('navigate-button'));

    expect(tour.events[0].detail).toEqual({
      page: 'workflow_edit',
      params: { project_id: 'project-123' },
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
    // No button, no telemetry.
    expect(tourTelemetry(fetchMock)).toEqual([]);
  });

  describe('grand tours and autopilot', () => {
    it('renders Start the tour for a tour fence and dispatches the tour detail', async () => {
      render(
        <MessageList
          messages={navigateReply(
            '{"tour": ["project_workflows", "project_history"]}'
          )}
        />
      );

      const button = screen.getByTestId('navigate-button');
      expect(button).toHaveTextContent('Start the tour');
      expect(button).toHaveAttribute('title', 'Shift-click: let it drive');

      await userEvent.click(button);

      expect(tour.events[0].detail).toEqual({
        tour: ['project_workflows', 'project_history'],
        params: { project_id: 'project-123' },
      });
    });

    it('ignores malformed tour arrays', () => {
      const bodies = [
        '{"tour": []}',
        '{"tour": ["project_history", 5]}',
        '{"tour": "project_history"}',
      ];
      for (const body of bodies) {
        const { unmount } = render(
          <MessageList messages={navigateReply(body)} />
        );
        expect(screen.queryByTestId('navigate-button')).not.toBeInTheDocument();
        unmount();
      }
    });

    it('falls back to page when tour is malformed but page is present', () => {
      render(
        <MessageList
          messages={navigateReply(
            '{"tour": "nope", "page": "project_history"}'
          )}
        />
      );
      expect(screen.getByTestId('navigate-button')).toHaveTextContent(
        'Take me there'
      );
    });

    it('shift-click sets autopilot on the dispatched detail', () => {
      render(
        <MessageList messages={navigateReply('{"page": "project_history"}')} />
      );

      fireEvent.click(screen.getByTestId('navigate-button'), {
        shiftKey: true,
      });

      expect(tour.events[0].detail).toEqual({
        page: 'project_history',
        autopilot: true,
        params: { project_id: 'project-123' },
      });
    });
  });

  describe('telemetry', () => {
    it('emits button_shown once per mounted button, across re-renders', () => {
      const messages = navigateReply(
        '{"page": "project_settings", "tab": "vcs"}'
      );
      const { rerender } = render(<MessageList messages={messages} />);
      // A new array of the same messages re-renders the same mounted button.
      rerender(<MessageList messages={[...messages]} />);

      expect(
        tourTelemetry(fetchMock).filter(e => e.event === 'button_shown')
      ).toEqual([
        { event: 'button_shown', page: 'project_settings', tab: 'vcs' },
      ]);
    });

    it('emits button_clicked (with element) before dispatching the tour event', async () => {
      let clickedBeforeDispatch = 0;
      const probe = () => {
        clickedBeforeDispatch = tourTelemetry(fetchMock).filter(
          e => e.event === 'button_clicked'
        ).length;
      };
      document.addEventListener('lightning:start-tour', probe);

      render(
        <MessageList
          messages={navigateReply(
            '{"page": "workflow_edit", "element": "credential-picker"}'
          )}
        />
      );
      await userEvent.click(screen.getByTestId('navigate-button'));

      document.removeEventListener('lightning:start-tour', probe);
      expect(clickedBeforeDispatch).toBe(1);
      expect(
        tourTelemetry(fetchMock).filter(e => e.event === 'button_clicked')
      ).toEqual([
        {
          event: 'button_clicked',
          page: 'workflow_edit',
          element: 'credential-picker',
        },
      ]);
    });

    it('swallows telemetry fetch failures and still dispatches the tour', async () => {
      fetchMock.mockRejectedValue(new Error('offline'));

      render(<MessageList messages={navigateReply('{"page": "dashboard"}')} />);
      await userEvent.click(screen.getByTestId('navigate-button'));

      expect(tour.events).toHaveLength(1);
      expect(tour.events[0].detail).toEqual({
        page: 'dashboard',
        params: { project_id: 'project-123' },
      });
    });
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
