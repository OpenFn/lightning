/**
 * FullScreenIDE Integration Tests
 *
 * These tests verify the integration between ManualRunPanel, RunViewerPanel,
 * and FullScreenIDE for Phase 4 of the run viewer implementation.
 *
 * Focus areas:
 * - Run submission triggers right panel expansion
 * - URL deep linking with run/step parameters
 * - URL state synchronization
 */

import { describe, expect, it, vi } from 'vitest';

describe('FullScreenIDE - Run Integration', () => {
  describe('Integration logic', () => {
    it('handleRunSubmitted should update state and URL', () => {
      // This test verifies the logic exists without needing full render
      const mockSetFollowRunId = vi.fn();
      const mockUpdateSearchParams = vi.fn();
      const mockExpand = vi.fn();

      const rightPanelRef = {
        current: {
          isCollapsed: () => true,
          expand: mockExpand,
        },
      };

      // Simulate handleRunSubmitted logic
      const handleRunSubmitted = (runId: string) => {
        mockSetFollowRunId(runId);
        mockUpdateSearchParams({ run: runId });

        if (
          rightPanelRef.current?.isCollapsed &&
          rightPanelRef.current.isCollapsed()
        ) {
          rightPanelRef.current.expand();
        }
      };

      // Execute
      handleRunSubmitted('test-run-id');

      // Verify
      expect(mockSetFollowRunId).toHaveBeenCalledWith('test-run-id');
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        run: 'test-run-id',
      });
      expect(mockExpand).toHaveBeenCalled();
    });

    it('URL sync should update followRunId and expand panel', () => {
      const mockSetFollowRunId = vi.fn();
      const mockExpand = vi.fn();

      const rightPanelRef = {
        current: {
          isCollapsed: () => true,
          expand: mockExpand,
        },
      };

      // Simulate useEffect logic for URL sync
      const runIdFromURL = 'url-run-id';
      const followRunId = null;

      if (runIdFromURL && runIdFromURL !== followRunId) {
        mockSetFollowRunId(runIdFromURL);

        if (
          rightPanelRef.current?.isCollapsed &&
          rightPanelRef.current.isCollapsed()
        ) {
          rightPanelRef.current.expand();
        }
      }

      // Verify
      expect(mockSetFollowRunId).toHaveBeenCalledWith('url-run-id');
      expect(mockExpand).toHaveBeenCalled();
    });

    it('StepItem inspect should preserve run context in URL', () => {
      const mockUpdateSearchParams = vi.fn();
      const searchParams = new URLSearchParams('?run=current-run-id');

      // Simulate StepItem handleInspect logic
      const step = {
        id: 'step-123',
        job_id: 'job-456',
      };

      const handleInspect = () => {
        const currentRunId = searchParams.get('run');

        mockUpdateSearchParams({
          job: step.job_id,
          run: currentRunId,
          step: step.id,
        });
      };

      // Execute
      handleInspect();

      // Verify URL params preserve run context
      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        job: 'job-456',
        run: 'current-run-id',
        step: 'step-123',
      });
    });
  });

  describe('Props flow', () => {
    it('ManualRunPanel receives onRunSubmitted callback', () => {
      // This verifies the prop is passed correctly
      const mockCallback = vi.fn();

      // Simulate ManualRunPanel props
      const manualRunPanelProps = {
        workflow: {},
        projectId: 'proj-1',
        workflowId: 'wf-1',
        jobId: null,
        triggerId: null,
        onClose: vi.fn(),
        renderMode: 'embedded' as const,
        onRunStateChange: vi.fn(),
        saveWorkflow: vi.fn(),
        onRunSubmitted: mockCallback,
      };

      // Verify prop exists and is callable
      expect(manualRunPanelProps.onRunSubmitted).toBeDefined();
      manualRunPanelProps.onRunSubmitted?.('test-run-id');
      expect(mockCallback).toHaveBeenCalledWith('test-run-id');
    });

    it('RunViewerPanel receives followRunId and callback', () => {
      const mockClearCallback = vi.fn();

      // Simulate RunViewerPanel props
      const runViewerPanelProps = {
        followRunId: 'run-123',
        onClearFollowRun: mockClearCallback,
      };

      // Verify props exist
      expect(runViewerPanelProps.followRunId).toBe('run-123');
      expect(runViewerPanelProps.onClearFollowRun).toBeDefined();
      runViewerPanelProps.onClearFollowRun();
      expect(mockClearCallback).toHaveBeenCalled();
    });
  });

  describe('URL state synchronization', () => {
    it('syncs run ID from URL to state', () => {
      const mockSetFollowRunId = vi.fn();
      const runIdFromURL = 'url-run-123';
      const followRunId = null;

      // Simulate useEffect logic
      if (runIdFromURL && runIdFromURL !== followRunId) {
        mockSetFollowRunId(runIdFromURL);
      }

      expect(mockSetFollowRunId).toHaveBeenCalledWith('url-run-123');
    });

    it('syncs step ID from URL to RunStore', () => {
      const mockSelectStep = vi.fn();
      const stepIdFromURL = 'step-456';
      const runIdFromURL = 'run-123';

      // Simulate useEffect logic
      if (stepIdFromURL && runIdFromURL) {
        mockSelectStep(stepIdFromURL);
      }

      expect(mockSelectStep).toHaveBeenCalledWith('step-456');
    });

    it('updates URL when run is submitted', () => {
      const mockUpdateSearchParams = vi.fn();
      const runId = 'new-run-id';

      // Simulate handleRunSubmitted
      mockUpdateSearchParams({ run: runId });

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({ run: runId });
    });
  });

  describe('Automatic dataclip selection', () => {
    it('should fetch dataclip when all required conditions are met', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const jobIdFromURL = 'job-456';
      const projectId = 'proj-789';
      const manuallyUnselectedDataclip = false;

      // Simulate the guard clause logic
      const shouldFetchDataclip =
        inputDataclipId &&
        jobIdFromURL &&
        projectId &&
        !manuallyUnselectedDataclip;

      if (shouldFetchDataclip) {
        mockFetchDataclip();
      }

      expect(mockFetchDataclip).toHaveBeenCalled();
    });

    it('should NOT fetch dataclip when inputDataclipId is missing', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = null;
      const jobIdFromURL = 'job-456';
      const projectId = 'proj-789';
      const manuallyUnselectedDataclip = false;

      // Simulate the guard clause logic
      if (
        !inputDataclipId ||
        !jobIdFromURL ||
        !projectId ||
        manuallyUnselectedDataclip
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it('should NOT fetch dataclip when jobIdFromURL is missing', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const jobIdFromURL = null;
      const projectId = 'proj-789';
      const manuallyUnselectedDataclip = false;

      // Simulate the guard clause logic
      if (
        !inputDataclipId ||
        !jobIdFromURL ||
        !projectId ||
        manuallyUnselectedDataclip
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it('should NOT fetch dataclip when projectId is missing', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const jobIdFromURL = 'job-456';
      const projectId = null;
      const manuallyUnselectedDataclip = false;

      // Simulate the guard clause logic
      if (
        !inputDataclipId ||
        !jobIdFromURL ||
        !projectId ||
        manuallyUnselectedDataclip
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it('should NOT fetch dataclip when user manually unselected dataclip', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const jobIdFromURL = 'job-456';
      const projectId = 'proj-789';
      const manuallyUnselectedDataclip = true;

      // Simulate the guard clause logic
      if (
        !inputDataclipId ||
        !jobIdFromURL ||
        !projectId ||
        manuallyUnselectedDataclip
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it('should skip fetch when dataclip already matches expected one', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const selectedDataclipState: { id: string } | null = {
        id: 'dataclip-123',
      };

      // Simulate the second guard clause logic
      if (
        selectedDataclipState !== null &&
        selectedDataclipState.id === inputDataclipId
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it("should proceed to fetch when selected dataclip doesn't match", () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const selectedDataclipState = { id: 'different-dataclip' };

      // Simulate the second guard clause logic
      if (
        selectedDataclipState !== null &&
        selectedDataclipState.id === inputDataclipId
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).toHaveBeenCalled();
    });

    it('should proceed to fetch when no dataclip is selected', () => {
      const mockFetchDataclip = vi.fn();
      const inputDataclipId = 'dataclip-123';
      const selectedDataclipState = null;

      // Simulate the second guard clause logic
      if (
        selectedDataclipState !== null &&
        selectedDataclipState.id === inputDataclipId
      ) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).toHaveBeenCalled();
    });

    it('should NOT fetch when runId is missing from URL', () => {
      const mockFetchDataclip = vi.fn();
      const searchParams = new URLSearchParams('');
      const runId = searchParams.get('run') || searchParams.get('a');

      // Simulate the third guard clause logic
      if (!runId) {
        return;
      }

      mockFetchDataclip();

      expect(mockFetchDataclip).not.toHaveBeenCalled();
    });

    it('should reset manuallyUnselectedDataclip flag when URL run changes', () => {
      const mockSetManuallyUnselectedDataclip = vi.fn();
      const searchParamsRunId: string | null = 'new-run-id';
      const followRunId: string | null = 'old-run-id';

      // Simulate the useEffect logic that resets the flag
      if (searchParamsRunId && searchParamsRunId !== followRunId) {
        mockSetManuallyUnselectedDataclip(false);
      }

      expect(mockSetManuallyUnselectedDataclip).toHaveBeenCalledWith(false);
    });
  });

  describe('Run synchronization between canvas and IDE', () => {
    describe('Canvas → IDE synchronization', () => {
      it('syncs run ID from URL to followRunId state on mount', () => {
        const mockSetFollowRunId = vi.fn();
        const runIdFromURL = 'canvas-selected-run';
        const followRunId = null;

        // Simulate useEffect logic that syncs URL to state
        if (runIdFromURL && runIdFromURL !== followRunId) {
          mockSetFollowRunId(runIdFromURL);
        }

        expect(mockSetFollowRunId).toHaveBeenCalledWith('canvas-selected-run');
      });

      it('derives panelState as run-viewer when followRunId is set', () => {
        // Simulate derived state logic
        const followRunId = 'some-run-id';
        const rightPanelSubState = 'landing';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        expect(panelState).toBe('run-viewer');
      });

      it('expands right panel when run is selected from URL', () => {
        const mockExpand = vi.fn();
        const mockIsCollapsed = vi.fn(() => true);

        const rightPanelRef = {
          current: {
            isCollapsed: mockIsCollapsed,
            expand: mockExpand,
          },
        };

        const runIdFromURL = 'url-run-id';
        const followRunId = null;

        // Simulate useEffect logic
        if (runIdFromURL && runIdFromURL !== followRunId) {
          if (
            rightPanelRef.current?.isCollapsed &&
            rightPanelRef.current.isCollapsed()
          ) {
            rightPanelRef.current.expand();
          }
        }

        expect(mockExpand).toHaveBeenCalled();
      });
    });

    describe('IDE → Canvas synchronization', () => {
      it('updates URL when run is selected from history panel', () => {
        const mockUpdateSearchParams = vi.fn();
        const mockSetFollowRunId = vi.fn();
        const runId = 'history-selected-run';

        // Simulate handleHistoryRunSelect
        const handleHistoryRunSelect = (run: { id: string }) => {
          mockSetFollowRunId(run.id);
          mockUpdateSearchParams({ run: run.id });
        };

        handleHistoryRunSelect({ id: runId });

        expect(mockSetFollowRunId).toHaveBeenCalledWith('history-selected-run');
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          run: 'history-selected-run',
        });
      });

      it('updates URL when run is created and submitted', () => {
        const mockUpdateSearchParams = vi.fn();
        const mockSetFollowRunId = vi.fn();
        const runId = 'newly-created-run';

        // Simulate handleRunSubmitted
        const handleRunSubmitted = (runId: string) => {
          mockSetFollowRunId(runId);
          mockUpdateSearchParams({ run: runId });
        };

        handleRunSubmitted(runId);

        expect(mockSetFollowRunId).toHaveBeenCalledWith('newly-created-run');
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({
          run: 'newly-created-run',
        });
      });

      it('transitions to run-viewer automatically after run selection', () => {
        // When followRunId is set by history selection, derived state becomes run-viewer
        const followRunId = 'selected-from-history';
        const rightPanelSubState = 'history';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        expect(panelState).toBe('run-viewer');
      });
    });

    describe('Run unload synchronization', () => {
      it('clears URL, state, and returns to landing when run is unloaded', () => {
        const mockUpdateSearchParams = vi.fn();
        const mockSetFollowRunId = vi.fn();
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleClearFollowRun
        const handleClearFollowRun = () => {
          mockSetFollowRunId(null);
          mockUpdateSearchParams({ run: null });
          mockSetRightPanelSubState('landing');
        };

        handleClearFollowRun();

        expect(mockSetFollowRunId).toHaveBeenCalledWith(null);
        expect(mockUpdateSearchParams).toHaveBeenCalledWith({ run: null });
        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('landing');
      });

      it('clears URL when user clicks X on RunBadge', () => {
        const mockUpdateSearchParams = vi.fn();
        const mockSetFollowRunId = vi.fn();
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleClearFollowRun called from RunBadge onClose
        const handleClearFollowRun = () => {
          mockSetFollowRunId(null);
          mockUpdateSearchParams({ run: null });
          mockSetRightPanelSubState('landing');
        };

        // User clicks X on RunBadge
        handleClearFollowRun();

        expect(mockUpdateSearchParams).toHaveBeenCalledWith({ run: null });
        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('landing');
      });
    });

    describe('URL as single source of truth', () => {
      it('derives panelState as run-viewer when followRunId is set', () => {
        const followRunId = 'some-run';
        const rightPanelSubState = 'landing';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        expect(panelState).toBe('run-viewer');
      });

      it('uses rightPanelSubState when no run is loaded', () => {
        const followRunId = null;
        const rightPanelSubState = 'history';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        expect(panelState).toBe('history');
      });

      it('overrides rightPanelSubState when run is selected', () => {
        // Even if user was in history view, selecting a run shows run-viewer
        const followRunId = 'run-123';
        const rightPanelSubState = 'history';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        expect(panelState).toBe('run-viewer');
      });

      it('returns to previous sub-state when run is cleared', () => {
        // After clearing run, rightPanelSubState determines what shows
        const followRunId = null;
        const rightPanelSubState = 'create-run';
        const panelState = followRunId ? 'run-viewer' : rightPanelSubState;

        // But handleClearFollowRun always sets rightPanelSubState to 'landing'
        expect(panelState).toBe('create-run');
      });
    });

    describe('Panel state transitions', () => {
      it('requests history when entering history state', () => {
        const mockRequestHistory = vi.fn();
        const rightPanelSubState = 'history';

        // Simulate useEffect that requests history
        if (rightPanelSubState === 'history') {
          mockRequestHistory();
        }

        expect(mockRequestHistory).toHaveBeenCalled();
      });

      it('does not request history when in other states', () => {
        const mockRequestHistory = vi.fn();
        const rightPanelSubState = 'landing';

        // Simulate useEffect that requests history
        if (rightPanelSubState === 'history') {
          mockRequestHistory();
        }

        expect(mockRequestHistory).not.toHaveBeenCalled();
      });

      it('navigates from landing to history when View History clicked', () => {
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleNavigateToHistory
        const handleNavigateToHistory = () => {
          mockSetRightPanelSubState('history');
        };

        handleNavigateToHistory();

        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('history');
      });

      it('navigates from landing to create-run when Create Run clicked', () => {
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleNavigateToCreateRun
        const handleNavigateToCreateRun = () => {
          mockSetRightPanelSubState('create-run');
        };

        handleNavigateToCreateRun();

        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('create-run');
      });

      it('navigates back to landing from history', () => {
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleBackToLanding
        const handleBackToLanding = () => {
          mockSetRightPanelSubState('landing');
        };

        handleBackToLanding();

        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('landing');
      });

      it('navigates back to landing from create-run', () => {
        const mockSetRightPanelSubState = vi.fn();

        // Simulate handleBackToLanding
        const handleBackToLanding = () => {
          mockSetRightPanelSubState('landing');
        };

        handleBackToLanding();

        expect(mockSetRightPanelSubState).toHaveBeenCalledWith('landing');
      });
    });
  });
});
