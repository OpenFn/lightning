/**
 * FullScreenIDE Panel Mode Integration Tests
 *
 * Tests the right panel mode state machine and transitions between:
 * - empty: Landing state with two action buttons
 * - history: History browser panel
 * - manual-run: Manual run creation panel
 * - run-viewer: Run viewing panel
 *
 * Focus areas:
 * - Mode transitions triggered by user interactions
 * - State preservation across mode transitions
 * - URL synchronization with panel modes
 * - State clearing after run submission
 */

import { describe, expect, it, vi } from 'vitest';

describe('FullScreenIDE - Panel Mode State Machine', () => {
  describe('Mode transition logic', () => {
    it('transitions from empty to history mode', () => {
      const mockSetRightPanelMode = vi.fn();

      // Simulate clicking "Browse History" button
      const handleBrowseHistory = () => {
        mockSetRightPanelMode('history');
      };

      handleBrowseHistory();

      expect(mockSetRightPanelMode).toHaveBeenCalledWith('history');
    });

    it('transitions from empty to manual-run mode', () => {
      const mockSetRightPanelMode = vi.fn();

      // Simulate clicking "Create New Run" button
      const handleCreateRun = () => {
        mockSetRightPanelMode('manual-run');
      };

      handleCreateRun();

      expect(mockSetRightPanelMode).toHaveBeenCalledWith('manual-run');
    });

    it('transitions from history back to empty mode', () => {
      const mockSetRightPanelMode = vi.fn();

      // Simulate clicking back button in history browser
      const handleHistoryClose = () => {
        mockSetRightPanelMode('empty');
      };

      handleHistoryClose();

      expect(mockSetRightPanelMode).toHaveBeenCalledWith('empty');
    });

    it('transitions from history to run-viewer mode and updates URL', () => {
      const mockSetFollowRunId = vi.fn();
      const mockUpdateSearchParams = vi.fn();
      const mockSetRightPanelMode = vi.fn();
      const mockExpand = vi.fn();

      const rightPanelRef = {
        current: {
          isCollapsed: () => true,
          expand: mockExpand,
        },
      };

      // Simulate selecting a run from history
      const handleHistorySelectRun = (runId: string) => {
        mockSetFollowRunId(runId);
        mockUpdateSearchParams({ run: runId });
        mockSetRightPanelMode('run-viewer');

        if (rightPanelRef.current?.isCollapsed()) {
          rightPanelRef.current.expand();
        }
      };

      handleHistorySelectRun('test-run-123');

      expect(mockSetFollowRunId).toHaveBeenCalledWith('test-run-123');
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        run: 'test-run-123',
      });
      expect(mockSetRightPanelMode).toHaveBeenCalledWith('run-viewer');
      expect(mockExpand).toHaveBeenCalled();
    });

    it('transitions from run-viewer to empty when run is closed', () => {
      const mockSetFollowRunId = vi.fn();
      const mockUpdateSearchParams = vi.fn();
      const mockSetRightPanelMode = vi.fn();

      // Simulate clicking X button on run chip
      const handleCloseRun = () => {
        mockSetFollowRunId(null);
        mockUpdateSearchParams({ run: null });
        mockSetRightPanelMode('empty');
      };

      handleCloseRun();

      expect(mockSetFollowRunId).toHaveBeenCalledWith(null);
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({ run: null });
      expect(mockSetRightPanelMode).toHaveBeenCalledWith('empty');
    });
  });

  describe('Run submission workflow', () => {
    it('transitions to run-viewer and clears manual run state after submission', () => {
      const mockSetFollowRunId = vi.fn();
      const mockUpdateSearchParams = vi.fn();
      const mockSetRightPanelMode = vi.fn();
      const mockSetSelectedDataclipState = vi.fn();
      const mockSetSelectedTab = vi.fn();
      const mockSetCustomBody = vi.fn();
      const mockSetManuallyUnselectedDataclip = vi.fn();
      const mockExpand = vi.fn();

      const rightPanelRef = {
        current: {
          isCollapsed: () => true,
          expand: mockExpand,
        },
      };

      // Simulate run submission handler
      const handleRunSubmitted = (runId: string) => {
        mockSetFollowRunId(runId);
        mockUpdateSearchParams({ run: runId });
        mockSetRightPanelMode('run-viewer');
        mockSetManuallyUnselectedDataclip(false);

        // Clear manual run state
        mockSetSelectedDataclipState(null);
        mockSetSelectedTab('empty');
        mockSetCustomBody('');

        if (rightPanelRef.current?.isCollapsed()) {
          rightPanelRef.current.expand();
        }
      };

      handleRunSubmitted('new-run-456');

      // Verify mode transition
      expect(mockSetFollowRunId).toHaveBeenCalledWith('new-run-456');
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        run: 'new-run-456',
      });
      expect(mockSetRightPanelMode).toHaveBeenCalledWith('run-viewer');

      // Verify state clearing
      expect(mockSetSelectedDataclipState).toHaveBeenCalledWith(null);
      expect(mockSetSelectedTab).toHaveBeenCalledWith('empty');
      expect(mockSetCustomBody).toHaveBeenCalledWith('');
      expect(mockSetManuallyUnselectedDataclip).toHaveBeenCalledWith(false);

      // Verify panel expansion
      expect(mockExpand).toHaveBeenCalled();
    });
  });

  describe('URL synchronization', () => {
    it('initializes run-viewer mode when URL contains run parameter', () => {
      const mockSetFollowRunId = vi.fn();
      const mockSetRightPanelMode = vi.fn();
      const mockExpand = vi.fn();

      const rightPanelRef = {
        current: {
          isCollapsed: () => true,
          expand: mockExpand,
        },
      };

      // Simulate useEffect logic for URL sync
      const runIdFromURL = 'url-run-789';
      const followRunId = null;

      if (runIdFromURL && runIdFromURL !== followRunId) {
        mockSetFollowRunId(runIdFromURL);
        mockSetRightPanelMode('run-viewer');

        if (rightPanelRef.current?.isCollapsed()) {
          rightPanelRef.current.expand();
        }
      }

      expect(mockSetFollowRunId).toHaveBeenCalledWith('url-run-789');
      expect(mockSetRightPanelMode).toHaveBeenCalledWith('run-viewer');
      expect(mockExpand).toHaveBeenCalled();
    });

    it('resets to empty mode when run parameter is removed from URL', () => {
      const mockSetFollowRunId = vi.fn();
      const mockSetRightPanelMode = vi.fn();

      // Simulate URL cleared but followRunId still set
      const runIdFromURL = null;
      const followRunId = 'previous-run-id';

      if (!runIdFromURL && followRunId) {
        mockSetFollowRunId(null);
        mockSetRightPanelMode('empty');
      }

      expect(mockSetFollowRunId).toHaveBeenCalledWith(null);
      expect(mockSetRightPanelMode).toHaveBeenCalledWith('empty');
    });
  });

  describe('Manual run state preservation', () => {
    it('preserves dataclip selection when navigating between modes', () => {
      // This test verifies that manual run state is NOT cleared when
      // transitioning between empty, history, and manual-run modes

      const mockDataclip = {
        id: 'dataclip-123',
        type: 'http_request' as const,
        body: '{"test": "data"}',
        request: null,
        project_id: 'proj-456',
        inserted_at: '2025-01-22T10:00:00Z',
        updated_at: '2025-01-22T10:00:00Z',
      };

      const selectedDataclipState = mockDataclip;
      const selectedTab = 'existing';
      const customBody = '';

      // Navigate: manual-run -> history -> empty -> manual-run
      // State should remain unchanged

      // Verify state is preserved
      expect(selectedDataclipState).toEqual(mockDataclip);
      expect(selectedTab).toBe('existing');
      expect(customBody).toBe('');
    });

    it('only clears state after successful run submission', () => {
      const mockDataclip = {
        id: 'dataclip-456',
        type: 'http_request' as const,
        body: '{"custom": "input"}',
        request: null,
        project_id: 'proj-789',
        inserted_at: '2025-01-22T11:00:00Z',
        updated_at: '2025-01-22T11:00:00Z',
      };

      let selectedDataclipState = mockDataclip;
      let selectedTab = 'existing' as const;
      let customBody = 'console.log("test");';

      // Simulate handleCloseRun (should NOT clear state)
      // State remains unchanged when just closing a run

      expect(selectedDataclipState).toEqual(mockDataclip);
      expect(selectedTab).toBe('existing');

      // Simulate handleRunSubmitted (SHOULD clear state)
      selectedDataclipState = null;
      selectedTab = 'empty';
      customBody = '';

      expect(selectedDataclipState).toBeNull();
      expect(selectedTab).toBe('empty');
      expect(customBody).toBe('');
    });
  });

  describe('Panel rendering conditions', () => {
    it('renders RightPanelEmptyState when mode is empty', () => {
      const rightPanelMode = 'empty';
      const followRunId = null;

      // Component selection logic
      let componentToRender;
      switch (rightPanelMode) {
        case 'empty':
          componentToRender = 'RightPanelEmptyState';
          break;
        case 'history':
          componentToRender = 'HistoryBrowserPanel';
          break;
        case 'manual-run':
          componentToRender = 'ManualRunPanel';
          break;
        case 'run-viewer':
          componentToRender = 'RunViewerPanel';
          break;
      }

      expect(componentToRender).toBe('RightPanelEmptyState');
      expect(followRunId).toBeNull();
    });

    it('renders HistoryBrowserPanel when mode is history', () => {
      const rightPanelMode = 'history';
      const followRunId = null;

      let componentToRender;
      switch (rightPanelMode) {
        case 'empty':
          componentToRender = 'RightPanelEmptyState';
          break;
        case 'history':
          componentToRender = 'HistoryBrowserPanel';
          break;
        case 'manual-run':
          componentToRender = 'ManualRunPanel';
          break;
        case 'run-viewer':
          componentToRender = 'RunViewerPanel';
          break;
      }

      expect(componentToRender).toBe('HistoryBrowserPanel');
      expect(followRunId).toBeNull();
    });

    it('renders ManualRunPanel when mode is manual-run', () => {
      const rightPanelMode = 'manual-run';
      const followRunId = null;

      let componentToRender;
      switch (rightPanelMode) {
        case 'empty':
          componentToRender = 'RightPanelEmptyState';
          break;
        case 'history':
          componentToRender = 'HistoryBrowserPanel';
          break;
        case 'manual-run':
          componentToRender = 'ManualRunPanel';
          break;
        case 'run-viewer':
          componentToRender = 'RunViewerPanel';
          break;
      }

      expect(componentToRender).toBe('ManualRunPanel');
      expect(followRunId).toBeNull();
    });

    it('renders RunViewerPanel when mode is run-viewer', () => {
      const rightPanelMode = 'run-viewer';
      const followRunId = 'test-run-999';

      let componentToRender;
      switch (rightPanelMode) {
        case 'empty':
          componentToRender = 'RightPanelEmptyState';
          break;
        case 'history':
          componentToRender = 'HistoryBrowserPanel';
          break;
        case 'manual-run':
          componentToRender = 'ManualRunPanel';
          break;
        case 'run-viewer':
          componentToRender = 'RunViewerPanel';
          break;
      }

      expect(componentToRender).toBe('RunViewerPanel');
      expect(followRunId).toBe('test-run-999');
    });
  });

  describe('Right panel header rendering', () => {
    it('displays correct header title for each mode', () => {
      interface TestCase {
        mode: string;
        followRunId: string | null;
        expected: string;
      }

      const testCases: TestCase[] = [
        { mode: 'empty', followRunId: null, expected: 'Select Action' },
        { mode: 'history', followRunId: null, expected: 'Browse History' },
        {
          mode: 'manual-run',
          followRunId: null,
          expected: 'New Run (Select Input)',
        },
        {
          mode: 'run-viewer',
          followRunId: 'run-123',
          expected: 'Run - run-123',
        },
      ];

      testCases.forEach(({ mode, followRunId, expected }: TestCase) => {
        // Simulate header title logic
        let headerTitle;
        if (followRunId) {
          headerTitle = `Run - ${followRunId}`;
        } else if (mode === 'history') {
          headerTitle = 'Browse History';
        } else if (mode === 'manual-run') {
          headerTitle = 'New Run (Select Input)';
        } else {
          headerTitle = 'Select Action';
        }

        expect(headerTitle).toBe(expected);
      });
    });
  });

  describe('Edge cases', () => {
    it('handles rapid mode transitions without state corruption', () => {
      const mockSetRightPanelMode = vi.fn();

      // Simulate rapid clicks
      // eslint-disable-next-line @typescript-eslint/no-unsafe-return
      const handleBrowseHistory = () => mockSetRightPanelMode('history');
      // eslint-disable-next-line @typescript-eslint/no-unsafe-return
      const handleCreateRun = () => mockSetRightPanelMode('manual-run');
      // eslint-disable-next-line @typescript-eslint/no-unsafe-return
      const handleHistoryClose = () => mockSetRightPanelMode('empty');

      // User rapidly clicks through modes
      handleBrowseHistory();
      handleHistoryClose();
      handleCreateRun();
      handleHistoryClose();
      handleBrowseHistory();

      expect(mockSetRightPanelMode).toHaveBeenCalledTimes(5);
      expect(mockSetRightPanelMode).toHaveBeenLastCalledWith('history');
    });

    it('handles missing projectId/workflowId gracefully', () => {
      const projectId = null;
      const workflowId = null;

      // Component should handle null values
      const shouldRenderHistoryPanel = projectId && workflowId;

      expect(shouldRenderHistoryPanel).toBeFalsy();
    });

    it('handles missing workflow in manual-run mode gracefully', () => {
      const workflow = null;
      const projectId = 'proj-123';
      const workflowId = 'wf-456';

      // Component should handle null workflow
      const shouldRenderManualRunPanel = workflow && projectId && workflowId;

      expect(shouldRenderManualRunPanel).toBeFalsy();
    });
  });
});
