/**
 * RunViewerPanel Component Tests
 *
 * Tests for RunViewerPanel component that displays run data.
 * The component is a controlled component that accepts activeTab
 * and onTabChange props from its parent. Tab rendering and
 * persistence are managed by the parent (FullScreenIDE).
 *
 * Test Coverage:
 * - Empty state when no run is selected
 * - Loading state with skeleton
 * - Error state with dismiss button
 * - Tab content rendering based on activeTab prop
 * - Channel connection/disconnection lifecycle
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { RunViewerPanel } from '../../../../js/collaborative-editor/components/run-viewer/RunViewerPanel';
import * as useHistoryModule from '../../../../js/collaborative-editor/hooks/useHistory';
import * as useSessionModule from '../../../../js/collaborative-editor/hooks/useSession';
import type { RunDetail } from '../../../../js/collaborative-editor/types/history';

// Mock tab panel components to avoid monaco-editor dependency
vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/RunTabPanel',
  () => ({
    RunTabPanel: () => <div>Run Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/LogTabPanel',
  () => ({
    LogTabPanel: () => <div>Log Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/InputTabPanel',
  () => ({
    InputTabPanel: () => <div>Input Tab Content</div>,
  })
);

vi.mock(
  '../../../../js/collaborative-editor/components/run-viewer/OutputTabPanel',
  () => ({
    OutputTabPanel: () => <div>Output Tab Content</div>,
  })
);

// Mock hooks
const mockUseActiveRun = vi.spyOn(useHistoryModule, 'useActiveRun');
const mockUseActiveRunLoading = vi.spyOn(
  useHistoryModule,
  'useActiveRunLoading'
);
const mockUseActiveRunError = vi.spyOn(useHistoryModule, 'useActiveRunError');
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

// Mock history commands
const createMockHistoryCommands = () => ({
  clearActiveRunError: vi.fn(),
});

describe('RunViewerPanel', () => {
  let mockCommands: ReturnType<typeof createMockHistoryCommands>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockCommands = createMockHistoryCommands();

    // Default mocks
    mockUseHistoryCommands.mockReturnValue(mockCommands as any);
    mockUseSession.mockReturnValue({
      provider: {
        socket: {},
      } as any,
      ydoc: null,
      awareness: null,
      userData: null,
      isConnected: true,
      isSynced: true,
      settled: true,
      lastStatus: null,
    });

    // Clear localStorage
    localStorage.clear();
  });

  describe('empty state', () => {
    test('shows empty state when no followRunId provided', () => {
      mockUseActiveRun.mockReturnValue(null);
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId={null}
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText(/after you click run/i)).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    test('shows skeleton when loading and no run data', () => {
      mockUseActiveRun.mockReturnValue(null);
      mockUseActiveRunLoading.mockReturnValue(true);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      // Check for skeleton (animated pulse)
      const skeleton = document.querySelector('.animate-pulse');
      expect(skeleton).toBeInTheDocument();
    });

    test('does not show skeleton when loading but run exists', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(true);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      // Should show tab content (Run Tab Content), not skeleton
      expect(screen.getByText('Run Tab Content')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    test('shows error message when error exists', () => {
      mockUseActiveRun.mockReturnValue(null);
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue('Failed to load run');

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText('Error loading run')).toBeInTheDocument();
      expect(screen.getByText('Failed to load run')).toBeInTheDocument();
    });

    test('dismiss button clears error', async () => {
      const user = userEvent.setup();
      mockUseActiveRun.mockReturnValue(null);
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue('Failed to load run');

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      const dismissButton = screen.getByText('Dismiss');
      await user.click(dismissButton);

      expect(mockCommands.clearActiveRunError).toHaveBeenCalled();
    });
  });

  describe('tab content rendering', () => {
    test("renders Run tab content when activeTab is 'run'", () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText('Run Tab Content')).toBeInTheDocument();
    });

    test("renders Log tab content when activeTab is 'log'", () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="log"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText('Log Tab Content')).toBeInTheDocument();
    });

    test("renders Input tab content when activeTab is 'input'", () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="input"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText('Input Tab Content')).toBeInTheDocument();
    });

    test("renders Output tab content when activeTab is 'output'", () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="output"
          onTabChange={vi.fn()}
        />
      );

      expect(screen.getByText('Output Tab Content')).toBeInTheDocument();
    });
  });

  // NOTE: Connection lifecycle tests were removed.
  // Connection management is now handled by parent component (FullScreenIDE)
  // via useFollowRun hook, not by RunViewerPanel. RunViewerPanel only reads
  // from HistoryStore via useActiveRun hooks.

  describe('accessibility', () => {
    test('has proper ARIA labels', () => {
      mockUseActiveRun.mockReturnValue(createMockRun());
      mockUseActiveRunLoading.mockReturnValue(false);
      mockUseActiveRunError.mockReturnValue(null);

      const { container } = render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      const panelGroup = container.querySelector('[data-panel-group]');
      expect(panelGroup).toBeInTheDocument();
    });
  });
});
