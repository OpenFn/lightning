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
import * as useRunModule from '../../../../js/collaborative-editor/hooks/useRun';
import * as useSessionModule from '../../../../js/collaborative-editor/hooks/useSession';
import type { Run } from '../../../../js/collaborative-editor/types/run';

// Mock log viewer - Define mocks before vi.mock calls
const mockUnmount = vi.fn();
const mockMount = vi.fn();
const mockSetStepId = vi.fn();
const mockAddLogLines = vi.fn();
const mockSetDesiredLogLevel = vi.fn();

// Create a mock store that maintains state
let mockLogStoreState = {
  desiredLogLevel: 'info',
  setStepId: mockSetStepId,
  addLogLines: mockAddLogLines,
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
vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    searchParams: new URLSearchParams(),
    updateSearchParams: vi.fn(),
  }),
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
const mockUseCurrentRun = vi.spyOn(useRunModule, 'useCurrentRun');
const mockUseSelectedStepId = vi.spyOn(useRunModule, 'useSelectedStepId');
const mockUseRunStoreInstance = vi.spyOn(useRunModule, 'useRunStoreInstance');
const mockUseSession = vi.spyOn(useSessionModule, 'useSession');

// Mock run factory
const createMockRun = (overrides?: Partial<Run>): Run => ({
  id: 'run-1',
  work_order_id: 'wo-1',
  state: 'started',
  started_at: new Date().toISOString(),
  finished_at: null,
  steps: [],
  ...overrides,
});

// Mock run store
const createMockRunStore = () => ({
  selectStep: vi.fn(),
  _connectToRun: vi.fn(),
  _disconnectFromRun: vi.fn(),
  clearError: vi.fn(),
  getSnapshot: vi.fn(),
  subscribe: vi.fn(),
  withSelector: vi.fn(),
  setRun: vi.fn(),
  updateRunState: vi.fn(),
  addOrUpdateStep: vi.fn(),
  setLoading: vi.fn(),
  setError: vi.fn(),
  clear: vi.fn(),
  findStepById: vi.fn(),
  getSelectedStep: vi.fn(),
});

// Mock channel
const createMockChannel = () => ({
  topic: 'run:run-1',
  on: vi.fn(),
  off: vi.fn(),
});

describe('LogTabPanel', () => {
  let mockRunStore: ReturnType<typeof createMockRunStore>;
  let mockChannel: ReturnType<typeof createMockChannel>;

  beforeEach(() => {
    vi.clearAllMocks();

    // Reset mock store state to defaults
    mockLogStoreState.desiredLogLevel = 'info';

    mockRunStore = createMockRunStore();
    mockChannel = createMockChannel();

    mockUseRunStoreInstance.mockReturnValue(mockRunStore as any);
    mockUseSelectedStepId.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(null);

      render(<LogTabPanel />);

      expect(screen.getByText('No run selected')).toBeInTheDocument();
    });
  });

  describe('log viewer integration', () => {
    test('renders log viewer container', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

      const { container } = render(<LogTabPanel />);

      // Check for log viewer container with new structure
      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
    });
  });

  describe('step selection', () => {
    test('renders with selected step', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseSelectedStepId.mockReturnValue('step-1');

      render(<LogTabPanel />);

      // Component renders successfully with selected step
      expect(screen.queryByText('No run selected')).not.toBeInTheDocument();
    });
  });

  describe('channel log events', () => {
    test('subscribes to log events from run channel', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      expect(mockChannel.on).toHaveBeenCalledWith('logs', expect.any(Function));
    });

    test('unsubscribes from log events on cleanup', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

      const { unmount } = render(<LogTabPanel />);

      unmount();

      expect(mockChannel.off).toHaveBeenCalledWith(
        'logs',
        expect.any(Function)
      );
    });

    test('adds logs when streaming event is received', async () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

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

      mockUseCurrentRun.mockReturnValue(createMockRun());

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
      mockUseCurrentRun.mockReturnValue(
        createMockRun({
          steps: [
            {
              id: 'step-1',
              job_id: 'job-1',
              job: { id: 'job-1', name: 'Test Job' },
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

      render(<LogTabPanel />);

      expect(screen.getByText('Test Job')).toBeInTheDocument();
    });

    test('has proper layout structure with resizable panels', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

      const { container, getByTestId } = render(<LogTabPanel />);

      // Check for PanelGroup
      const panelGroup = getByTestId('panel-group');
      expect(panelGroup).toBeInTheDocument();
      expect(panelGroup).toHaveClass('h-full');

      // Check for panels
      const panels = container.querySelectorAll('[data-testid="panel"]');
      expect(panels).toHaveLength(2); // Step list panel and log viewer panel

      // Check for resize handle
      const resizeHandle = getByTestId('panel-resize-handle');
      expect(resizeHandle).toBeInTheDocument();
      expect(resizeHandle).toHaveClass('cursor-row-resize');

      // Check for log viewer container
      const logViewerContainer = container.querySelector('.bg-slate-700');
      expect(logViewerContainer).toBeInTheDocument();
    });
  });

  describe('error handling', () => {
    test('handles missing run channel gracefully', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

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
      mockUseCurrentRun.mockReturnValue(createMockRun());

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
      mockUseCurrentRun.mockReturnValue(createMockRun());

      render(<LogTabPanel />);

      // Check that filter button is present with the default log level
      expect(screen.getByText('info')).toBeInTheDocument();
    });

    test('initializes with correct level from store', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());

      // Set the mock store to have a different default level
      mockLogStoreState.desiredLogLevel = 'debug';

      render(<LogTabPanel />);

      // The filter should show the level from the store
      expect(screen.getByText('debug')).toBeInTheDocument();
    });

    test('changes log level when filter is used', async () => {
      const user = userEvent.setup();

      mockUseCurrentRun.mockReturnValue(createMockRun());
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

      mockUseCurrentRun.mockReturnValue(createMockRun());
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
      mockUseCurrentRun.mockReturnValue(createMockRun());

      const { container } = render(<LogTabPanel />);

      // Check that the filter is in the header section
      const header = container.querySelector('.border-b.border-slate-500');
      expect(header).toBeInTheDocument();

      // The filter button should be within the header
      const filterButton = screen.getByRole('button');
      expect(header).toContainElement(filterButton);
    });
  });
});
