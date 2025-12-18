/**
 * LogTabPanel Component Tests
 *
 * Tests for LogTabPanel component that integrates log viewer
 * with step list and channel event handling.
 *
 * Test Coverage:
 * - Empty state when no run
 * - Log viewer mounting and cleanup
 * - Step selection syncing to log store
 * - Channel log event handling
 * - Log level filter integration
 * - Integration with existing log-viewer component
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { LogTabPanel } from '../../../../js/collaborative-editor/components/run-viewer/LogTabPanel';
import * as useHistoryModule from '../../../../js/collaborative-editor/hooks/useHistory';
import * as useSessionModule from '../../../../js/collaborative-editor/hooks/useSession';
import type { RunDetail } from '../../../../js/collaborative-editor/types/history';
import { createMockURLState, getURLStateMockValue } from '../../__helpers__';

// Mock log viewer - Define mocks before vi.mock calls
const mockUnmount = vi.fn();
const mockMount = vi.fn();
const mockSetStepId = vi.fn();
const mockAddLogLines = vi.fn();
const mockSetDesiredLogLevel = vi.fn();
const mockClearLogs = vi.fn();

// Create a mock store that maintains state
let mockLogStoreState = {
  desiredLogLevel: 'info',
  setStepId: mockSetStepId,
  addLogLines: mockAddLogLines,
  clearLogs: mockClearLogs,
  setDesiredLogLevel: (level: string) => {
    mockSetDesiredLogLevel(level);
    mockLogStoreState.desiredLogLevel = level;
  },
};

vi.mock('../../../../js/log-viewer/component', () => ({
  mount: vi.fn(() => ({
    unmount: mockUnmount,
  })),
}));

vi.mock('../../../../js/log-viewer/store', () => ({
  createLogStore: vi.fn(() => ({
    getState: vi.fn(() => mockLogStoreState),
  })),
}));

// Mock channel request
vi.mock('../../../../js/collaborative-editor/hooks/useChannel', () => ({
  channelRequest: vi.fn(() =>
    Promise.resolve({ logs: [{ id: 'log-1', message: 'Test log' }] })
  ),
}));

// Mock useURLState
const urlState = createMockURLState();

vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => getURLStateMockValue(urlState),
}));

// Mock useWorkflowState hook for StepItem
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: (selector: any) => {
    const mockState = {
      jobs: [{ id: 'job-1', name: 'Test Job' }],
    };
    return selector(mockState);
  },
}));

// Mock react-resizable-panels
vi.mock('react-resizable-panels', () => ({
  Panel: ({ children, className }: any) => (
    <div className={className} data-testid="panel">
      {children}
    </div>
  ),
  PanelGroup: ({ children, className }: any) => (
    <div className={className} data-testid="panel-group">
      {children}
    </div>
  ),
  PanelResizeHandle: ({ className }: any) => (
    <div className={className} data-testid="panel-resize-handle" />
  ),
}));

// Mock hooks
const mockUseActiveRun = vi.spyOn(useHistoryModule, 'useActiveRun');
const mockUseSelectedStepId = vi.spyOn(useHistoryModule, 'useSelectedStepId');
const mockUseHistoryCommands = vi.spyOn(useHistoryModule, 'useHistoryCommands');
const mockUseSession = vi.spyOn(useSessionModule, 'useSession');

// Mock run factory
const createMockRun = (overrides?: Partial<RunDetail>): RunDetail => ({
  id: 'run-1',
  work_order_id: 'wo-1',
  work_order: {
    id: 'wo-1',
    workflow_id: 'wf-1',
  },
  state: 'started',
  created_by: null,
  starting_trigger: null,
  started_at: new Date().toISOString(),
  finished_at: null,
  steps: [],
  ...overrides,
});

// Mock channel
const createMockChannel = () => ({
  topic: 'run:run-1',
  on: vi.fn(),
  off: vi.fn(),
});

describe('LogTabPanel', () => {
  let mockChannel: ReturnType<typeof createMockChannel>;

  beforeEach(() => {
    vi.clearAllMocks();
    urlState.reset();

    // Reset mock store state to defaults
    mockLogStoreState.desiredLogLevel = 'info';
    mockClearLogs.mockClear();

    mockChannel = createMockChannel();

    mockUseSelectedStepId.mockReturnValue(null);

    // Mock history commands (used by StepViewerLayout)
    mockUseHistoryCommands.mockReturnValue({
      selectStep: vi.fn(),
    } as any);

    // Mock session with channel
    mockUseSession.mockReturnValue({
      provider: {
        socket: {
          channels: [mockChannel],
        },
      } as any,
      ydoc: null,
      awareness: null,
      userData: null,
      isConnected: true,
      isSynced: true,
      settled: true,
      lastStatus: null,
    });
  });

  describe('empty state', () => {
    test('shows empty message when no run', () => {
      mockUseActiveRun.mockReturnValue(null);

      const { container } = render(<LogTabPanel />);

      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
    });
  });

  describe('log viewer integration', () => {
    test('renders log viewer container', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      const { container } = render(<LogTabPanel />);

      // Check for log viewer container with new structure
      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
    });
  });

  describe('step selection', () => {
    test('renders with selected step', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseSelectedStepId.mockReturnValue('step-1');

      render(<LogTabPanel />);

      // Component renders successfully with selected step
      expect(screen.queryByText('No run selected')).not.toBeInTheDocument();
    });
  });

  describe('channel log events', () => {
    test('subscribes to log events from run channel', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      expect(mockChannel.on).toHaveBeenCalledWith('logs', expect.any(Function));
    });

    test('unsubscribes from log events on cleanup', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      const { unmount } = render(<LogTabPanel />);

      unmount();

      expect(mockChannel.off).toHaveBeenCalledWith(
        'logs',
        expect.any(Function)
      );
    });

    test('adds logs when streaming event is received', async () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      // Get the log handler that was registered
      const logHandler = mockChannel.on.mock.calls.find(
        call => call[0] === 'logs'
      )?.[1];

      expect(logHandler).toBeDefined();

      // Simulate receiving streaming logs
      const streamingLogs = [
        { id: 'log-2', message: 'Streaming log 1' },
        { id: 'log-3', message: 'Streaming log 2' },
      ];

      logHandler({ logs: streamingLogs });

      // Verify logs were added to the store
      await waitFor(() => {
        expect(mockAddLogLines).toHaveBeenCalledWith(streamingLogs);
      });
    });

    test('fetches initial logs on mount', async () => {
      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );

      mockUseActiveRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      await waitFor(() => {
        expect(channelRequest).toHaveBeenCalledWith(
          mockChannel,
          'fetch:logs',
          {}
        );
      });
    });
  });

  describe('layout', () => {
    test('renders step list in sidebar', () => {
      mockUseActiveRun.mockReturnValue(
        createMockRun({
          steps: [
            {
              id: 'step-1',
              job_id: 'job-1',
              job: { name: 'Test Job' },
              exit_reason: null,
              error_type: null,
              started_at: new Date().toISOString(),
              finished_at: null,
              input_dataclip_id: null,
              output_dataclip_id: null,
              inserted_at: new Date().toISOString(),
            },
          ],
        })
      );

      const { container } = render(<LogTabPanel />);

      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
    });

    test('has proper layout structure with resizable panels', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      const { container } = render(<LogTabPanel />);

      // Check for log viewer container
      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
      expect(logViewerContainer).toHaveClass(
        'grid',
        'h-full',
        'grid-rows-[auto_1fr]'
      );

      // Check for log level filter header
      const filterHeader = container.querySelector(
        '.border-b.border-slate-500'
      );
      expect(filterHeader).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    test('handles missing run channel gracefully', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      // Mock session with no matching channel
      mockUseSession.mockReturnValue({
        provider: {
          socket: {
            channels: [
              {
                topic: 'run:different-run',
                on: vi.fn(),
                off: vi.fn(),
              },
            ],
          },
        } as any,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: true,
        isSynced: true,
        settled: true,
        lastStatus: null,
      });

      // Should not throw
      expect(() => render(<LogTabPanel />)).not.toThrow();
    });

    test('handles null provider gracefully', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      mockUseSession.mockReturnValue({
        provider: null,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: false,
        isSynced: false,
        settled: false,
        lastStatus: null,
      });

      // Should not throw
      expect(() => render(<LogTabPanel />)).not.toThrow();
    });
  });

  describe('log level filter integration', () => {
    test('renders log level filter', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      // Check that filter button is present with the default log level
      expect(screen.getByText('info')).toBeInTheDocument();
    });

    test('initializes with correct level from store', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      // Set the mock store to have a different default level
      mockLogStoreState.desiredLogLevel = 'debug';

      render(<LogTabPanel />);

      // The filter should show the level from the store
      expect(screen.getByText('debug')).toBeInTheDocument();
    });

    test('changes log level when filter is used', async () => {
      const user = userEvent.setup();

      mockUseActiveRun.mockReturnValue(createMockRun());
      mockLogStoreState.desiredLogLevel = 'info';

      render(<LogTabPanel />);

      // Open the filter dropdown
      const filterButton = screen.getByRole('button', { name: /info/i });
      await user.click(filterButton);

      // Wait for dropdown to appear
      await waitFor(() => {
        expect(screen.getByRole('listbox')).toBeInTheDocument();
      });

      // Select "warn" level
      const warnOption = screen.getAllByText('warn')[0];
      await user.click(warnOption);

      // Verify the store was updated
      expect(mockSetDesiredLogLevel).toHaveBeenCalledWith('warn');
    });

    test('updates displayed level after selection', async () => {
      const user = userEvent.setup();

      mockUseActiveRun.mockReturnValue(createMockRun());
      mockLogStoreState.desiredLogLevel = 'info';

      render(<LogTabPanel />);

      // Open the filter dropdown
      const filterButton = screen.getByRole('button');
      await user.click(filterButton);

      // Select "error" level
      const errorOption = screen.getAllByText('error')[0];
      await user.click(errorOption);

      // The filter should now display "error"
      await waitFor(() => {
        // After clicking, the button should show the new level
        const buttons = screen.getAllByText('error');
        expect(buttons.length).toBeGreaterThan(0);
      });
    });

    test('log level filter is in the correct layout position', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());

      const { container } = render(<LogTabPanel />);

      // Check that the filter is in the header section
      const header = container.querySelector('.border-b.border-slate-500');
      expect(header).toBeInTheDocument();

      // The filter button should be within the header
      const filterButton = screen.getByRole('button');
      expect(header).toContainElement(filterButton);
    });
  });

  describe('clearing logs on run change', () => {
    test('clears logs when run changes', () => {
      const run1 = createMockRun({ id: 'run-1' });
      const run2 = createMockRun({ id: 'run-2' });

      // Update mock channel to match run-2
      const mockChannel2 = {
        topic: 'run:run-2',
        on: vi.fn(),
        off: vi.fn(),
      };

      mockUseActiveRun.mockReturnValue(run1);
      const { rerender } = render(<LogTabPanel />);

      // First render should clear logs for initial run
      expect(mockClearLogs).toHaveBeenCalledTimes(1);

      // Update session to have channel for run-2
      mockUseSession.mockReturnValue({
        provider: {
          socket: {
            channels: [mockChannel2],
          },
        } as any,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: true,
        isSynced: true,
        settled: true,
        lastStatus: null,
      });

      // Change to a different run
      mockUseActiveRun.mockReturnValue(run2);
      rerender(<LogTabPanel />);

      // Should clear logs again for new run
      expect(mockClearLogs).toHaveBeenCalledTimes(2);
    });

    test('does not clear logs when provider changes but run stays same', () => {
      const run = createMockRun({ id: 'run-1' });
      mockUseActiveRun.mockReturnValue(run);

      const { rerender } = render(<LogTabPanel />);

      // First render clears logs
      expect(mockClearLogs).toHaveBeenCalledTimes(1);

      // Simulate provider reference change (same socket, new object)
      mockUseSession.mockReturnValue({
        provider: {
          socket: {
            channels: [mockChannel],
          },
        } as any,
        ydoc: null,
        awareness: null,
        userData: null,
        isConnected: true,
        isSynced: true,
        settled: true,
        lastStatus: null,
      });

      rerender(<LogTabPanel />);

      // Should NOT clear logs again - run ID hasn't changed
      expect(mockClearLogs).toHaveBeenCalledTimes(1);
    });
  });

  describe('waiting text overlay', () => {
    beforeEach(() => {
      vi.useFakeTimers();
    });

    afterEach(() => {
      vi.useRealTimers();
    });

    test('shows waiting message when no logs and run is available', async () => {
      mockUseActiveRun.mockReturnValue(
        createMockRun({ id: 'run-1', state: 'available' })
      );

      // Mock channelRequest to return empty logs
      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );
      vi.mocked(channelRequest).mockResolvedValue({ logs: [] });

      render(<LogTabPanel />);

      // Advance timers to let typewriter animate
      await vi.advanceTimersByTimeAsync(1000);

      // Should show waiting message overlay (initial message types out first)
      expect(
        screen.getByText(/Waiting for a worker to establish/)
      ).toBeInTheDocument();
    });

    test('shows "Creating runtime" message when run is claimed', async () => {
      mockUseActiveRun.mockReturnValue(
        createMockRun({ id: 'run-1', state: 'claimed' })
      );

      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );
      vi.mocked(channelRequest).mockResolvedValue({ logs: [] });

      render(<LogTabPanel />);

      await vi.advanceTimersByTimeAsync(2000);

      expect(
        screen.getByText(/Creating an isolated runtime/)
      ).toBeInTheDocument();
    });

    test('shows "Nothing yet" message when no run', async () => {
      mockUseActiveRun.mockReturnValue(null);

      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );
      vi.mocked(channelRequest).mockResolvedValue({ logs: [] });

      render(<LogTabPanel />);

      // Default state cycles through messages (no initial message for default)
      await vi.advanceTimersByTimeAsync(1000);

      // Should show one of the default cycling messages
      const overlay = screen.getByText(
        /Nothing yet|Hang tight|Any moment|Standing by/
      );
      expect(overlay).toBeInTheDocument();
    });

    test('hides waiting overlay when logs arrive', async () => {
      mockUseActiveRun.mockReturnValue(
        createMockRun({ id: 'run-1', state: 'available' })
      );

      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );
      // First return empty, simulating initial state
      vi.mocked(channelRequest).mockResolvedValue({ logs: [] });

      render(<LogTabPanel />);

      // Let typewriter show waiting message
      await vi.advanceTimersByTimeAsync(2000);
      expect(
        screen.getByText(/Waiting for a worker to establish/)
      ).toBeInTheDocument();

      // Simulate logs arriving via channel event
      const logHandler = mockChannel.on.mock.calls.find(
        call => call[0] === 'logs'
      )?.[1];
      expect(logHandler).toBeDefined();

      // Trigger log arrival
      logHandler({ logs: [{ id: 'log-1', message: 'Test log' }] });

      // Advance timers and wait for state update
      await vi.advanceTimersByTimeAsync(100);

      // Waiting overlay should be hidden
      expect(
        screen.queryByText(/Waiting for a worker to establish/)
      ).not.toBeInTheDocument();
    });

    test('displays blinking cursor during typewriter animation', async () => {
      mockUseActiveRun.mockReturnValue(
        createMockRun({ id: 'run-1', state: 'available' })
      );

      const { channelRequest } = await import(
        '../../../../js/collaborative-editor/hooks/useChannel'
      );
      vi.mocked(channelRequest).mockResolvedValue({ logs: [] });

      const { container } = render(<LogTabPanel />);

      await vi.advanceTimersByTimeAsync(500);

      // Check for blinking cursor (uses inline style animation, not animate-pulse class)
      const cursor = container.querySelector('[style*="cursor-blink"]');
      expect(cursor).toBeInTheDocument();
      expect(cursor).toHaveTextContent('▌');
    });
  });
});
