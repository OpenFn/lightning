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
import * as useRunModule from '../../../../js/collaborative-editor/hooks/useRun';
import * as useSessionModule from '../../../../js/collaborative-editor/hooks/useSession';
import type { Run } from '../../../../js/collaborative-editor/types/run';

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
const mockUseCurrentRun = vi.spyOn(useRunModule, 'useCurrentRun');
const mockUseRunLoading = vi.spyOn(useRunModule, 'useRunLoading');
const mockUseRunError = vi.spyOn(useRunModule, 'useRunError');
const mockUseRunStoreInstance = vi.spyOn(useRunModule, 'useRunStoreInstance');
const mockUseRunActions = vi.spyOn(useRunModule, 'useRunActions');
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

// Mock store instance
const createMockRunStore = () => ({
  _connectToRun: vi.fn(() => vi.fn()),
  _disconnectFromRun: vi.fn(),
  clearError: vi.fn(),
  selectStep: vi.fn(),
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

describe('RunViewerPanel', () => {
  let mockStore: ReturnType<typeof createMockRunStore>;

  beforeEach(() => {
    vi.clearAllMocks();
    mockStore = createMockRunStore();

    // Default mocks
    mockUseRunStoreInstance.mockReturnValue(mockStore as any);
    mockUseRunActions.mockReturnValue({
      selectStep: mockStore.selectStep,
      clearError: mockStore.clearError,
    } as any);
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
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(true);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(true);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue('Failed to load run');

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
      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue('Failed to load run');

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      const dismissButton = screen.getByText('Dismiss');
      await user.click(dismissButton);

      expect(mockStore.clearError).toHaveBeenCalled();
    });
  });

  describe('tab content rendering', () => {
    test("renders Run tab content when activeTab is 'run'", () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

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
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

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

  // NOTE: Connection lifecycle tests were removed in this PR.
  // Connection management is now handled by parent component (FullScreenIDE),
  // not by RunViewerPanel. RunViewerPanel only reads from RunStore.
  describe('channel connection lifecycle', () => {
    test('does not connect when provider is null', () => {
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

      mockUseCurrentRun.mockReturnValue(null);
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      // Should not attempt connection without provider
      expect(mockStore._connectToRun).not.toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    test('has proper ARIA labels', () => {
      mockUseCurrentRun.mockReturnValue(createMockRun());
      mockUseRunLoading.mockReturnValue(false);
      mockUseRunError.mockReturnValue(null);

      render(
        <RunViewerPanel
          followRunId="run-1"
          activeTab="run"
          onTabChange={vi.fn()}
        />
      );

      const region = screen.getByRole('region', {
        name: /run output viewer/i,
      });
      expect(region).toBeInTheDocument();
    });
  });
});
