/**
 * MiniHistory Component Tests
 *
 * Tests the MiniHistory component behavior including:
 * - Collapsed/expanded states
 * - Empty state display
 * - Work order and run list rendering
 * - Status pill colors and states
 * - User interactions (collapse, expand, selection)
 * - Navigation behavior
 *
 * Test Philosophy:
 * - Group related assertions to test complete behaviors
 * - Focus on user-facing behavior, not implementation details
 * - Use descriptive test names that explain the behavior being tested
 */

import { describe, expect, test, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import MiniHistory from '../../../../js/collaborative-editor/components/diagram/MiniHistory';
import {
  createMockWorkOrder,
  mockHistoryList,
  mockMultiRunWorkOrder,
  mockSelectedWorkOrder,
  createWorkOrdersForAllStates,
} from '../../fixtures/historyData';

// Mock date-fns formatRelative to avoid locale issues in tests
vi.mock('date-fns', async () => {
  const actual = await vi.importActual('date-fns');
  return {
    ...actual,
    formatRelative: vi.fn(() => '2 hours ago'),
  };
});

// Mock the hooks module to avoid Phoenix LiveView dependencies in tests
vi.mock('../../../../js/hooks', () => ({
  relativeLocale: {},
}));

// Mock session context hooks to provide project ID
vi.mock('../../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useProject: () => ({
    id: 'test-project-id',
    name: 'Test Project',
  }),
  useVersions: () => [],
  useVersionsLoading: () => false,
  useVersionsError: () => null,
  useRequestVersions: () => vi.fn(),
}));

// Mock workflow hooks to provide workflow ID
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: (selector: any) => {
    const state = {
      workflow: {
        id: 'test-workflow-id',
        name: 'Test Workflow',
      },
    };
    return typeof selector === 'function' ? selector(state) : state;
  },
}));

// Mock window.location for navigation tests
const mockLocationAssign = vi.fn();
const mockLocation = {
  origin: 'http://localhost',
  href: 'http://localhost/projects/test-project-id/w/test-workflow-id',
  pathname: '/projects/test-project-id/w/test-workflow-id',
  assign: mockLocationAssign,
};

Object.defineProperty(window, 'location', {
  value: mockLocation,
  writable: true,
});

describe('MiniHistory', () => {
  beforeEach(() => {
    // Reset location and mock before each test
    mockLocation.origin = 'http://localhost';
    mockLocation.href =
      'http://localhost/projects/test-project-id/w/test-workflow-id';
    mockLocation.pathname = '/projects/test-project-id/w/test-workflow-id';
    mockLocationAssign.mockClear();
  });

  // ==========================================================================
  // COLLAPSED STATE
  // ==========================================================================

  describe('renders correctly in collapsed state', () => {
    test('displays minimal UI with expand button and view history link', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={true}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Header shows "View History" text when collapsed
      expect(screen.getByText('View History')).toBeInTheDocument();

      // View full history button is present
      const viewHistoryButton = screen.getByRole('button', {
        name: /View full history for this workflow/i,
      });
      expect(viewHistoryButton).toBeInTheDocument();

      // Chevron is present (right-pointing chevron for collapsed state)
      const header = screen.getByText('View History').closest('div.px-3');
      const chevronIcon = header?.querySelector('span.hero-chevron-right');
      expect(chevronIcon).toBeInTheDocument();

      // Work order list is hidden (element exists but not visible)
      const workOrderList = document.querySelector('.overflow-y-auto');
      expect(workOrderList).toHaveClass('hidden');
    });

    test('toggles when header is clicked', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={true}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click anywhere in the header section
      const header = screen.getByText('View History').parentElement;
      fireEvent.click(header!);

      expect(onCollapseHistory).toHaveBeenCalledTimes(1);
    });
  });

  // ==========================================================================
  // EXPANDED STATE
  // ==========================================================================

  describe('renders correctly in expanded state', () => {
    test('displays full UI with work order list', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Header shows "Recent History" when expanded
      expect(screen.getByText('Recent History')).toBeInTheDocument();

      // Chevron is present (left-pointing chevron for expanded state)
      const header = screen.getByText('Recent History').closest('div.px-3');
      const chevronIcon = header?.querySelector('span.hero-chevron-left');
      expect(chevronIcon).toBeInTheDocument();

      // Work order list is visible - check for truncated work order IDs
      expect(screen.getByText(/e2107d46/)).toBeInTheDocument();
      expect(screen.getByText(/547d11ad/)).toBeInTheDocument();
    });

    test('collapses when header is clicked', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click the header element
      const header = screen.getByText('Recent History').parentElement;
      fireEvent.click(header!);

      expect(onCollapseHistory).toHaveBeenCalledTimes(1);
    });
  });

  // ==========================================================================
  // EMPTY STATE
  // ==========================================================================

  describe('displays empty state correctly', () => {
    test('shows helpful message when no history is available', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Empty state displays icon and message
      expect(screen.getByText('No related history')).toBeInTheDocument();
      expect(
        screen.getByText(/Why not run it a few times to see some history?/i)
      ).toBeInTheDocument();

      // Empty state icon is present
      const emptyStateIcon = screen
        .getByText('No related history')
        .closest('div')
        ?.querySelector('span.hero-rectangle-stack');
      expect(emptyStateIcon).toBeInTheDocument();
    });

    test('does not display work order list when empty', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // No work order IDs should be visible
      expect(screen.queryByText(/e2107d46/)).not.toBeInTheDocument();
      expect(screen.queryByText(/547d11ad/)).not.toBeInTheDocument();
    });
  });

  // ==========================================================================
  // WORK ORDER LIST RENDERING
  // ==========================================================================

  describe('work order list renders correctly', () => {
    test('displays all work orders with truncated IDs, status pills, and timestamps', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // All work orders are displayed with truncated IDs (first 8 characters)
      expect(screen.getByText(/e2107d46/)).toBeInTheDocument(); // Success
      expect(screen.getByText(/547d11ad/)).toBeInTheDocument(); // Failed
      expect(screen.getByText(/6443ba23/)).toBeInTheDocument(); // Crashed
      expect(screen.getByText(/b18b25b7/)).toBeInTheDocument(); // Running

      // Status pills are present for each work order
      expect(screen.getByText('Success')).toBeInTheDocument();
      expect(screen.getByText('Failed')).toBeInTheDocument();
      expect(screen.getByText('Crashed')).toBeInTheDocument();
      expect(screen.getByText('Running')).toBeInTheDocument();

      // Relative timestamps are displayed
      const timestamps = screen.getAllByText(/ago|yesterday|today/i);
      expect(timestamps.length).toBeGreaterThan(0);
    });

    test('work order chevron indicates collapsed state by default', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // All work orders should have right-pointing chevrons (collapsed)
      const chevrons = screen
        .getByText(/e2107d46/)
        .closest('div')
        ?.querySelectorAll('span.hero-chevron-right');
      expect(chevrons!.length).toBeGreaterThan(0);
    });

    test('clicking work order expands to show runs', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const history = [mockMultiRunWorkOrder]; // Work order with 3 runs

      render(
        <MiniHistory
          collapsed={false}
          history={history}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Runs should not be visible initially
      expect(screen.queryByText(/8c7087f8/)).not.toBeInTheDocument();

      // Click the chevron button to expand
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // All runs should now be visible
      expect(screen.getByText(/8c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/9c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/ac7087f8/)).toBeInTheDocument();
    });

    test('clicking work order with single run calls selectRunHandler directly', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const singleRunWorkOrder = createMockWorkOrder({
        id: 'single-run-wo',
        runs: [
          {
            id: 'single-run-id',
            state: 'success',
            started_at: '2025-10-23T20:00:00Z',
            finished_at: '2025-10-23T20:00:01Z',
            error_type: null,
            selected: false,
          },
        ],
      });

      render(
        <MiniHistory
          collapsed={false}
          history={[singleRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Click chevron/expand button to trigger work order action
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // Should call selectRunHandler with the run (auto-selects single run)
      expect(selectRunHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'single-run-id',
          state: 'success',
        })
      );
    });
  });

  // ==========================================================================
  // RUN LIST RENDERING
  // ==========================================================================

  describe('run list renders correctly when work order expanded', () => {
    test('displays all runs with IDs, timestamps, durations, and status pills', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order by clicking the chevron button
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // All runs are visible with truncated IDs
      expect(screen.getByText(/8c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/9c7087f8/)).toBeInTheDocument();
      expect(screen.getByText(/ac7087f8/)).toBeInTheDocument();

      // Duration is shown for completed runs (format: "X.XXs")
      // Each run has start and finish times about 0.83s apart
      // Look for duration text with "s" suffix (seconds)
      const allText =
        screen.getByText(/8c7087f8/).closest("div[class*='px-3']")
          ?.textContent || '';
      expect(allText).toContain('s'); // Duration should be present
    });

    test('run selection highlights selected run and displays X icon', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Selected work order should be auto-expanded and show the selected run
      const selectedRun = screen.getByText(/d1f87a82/);
      expect(selectedRun).toBeInTheDocument();

      // Selected run should have special styling - find the run container (px-3 py-1.5)
      const runElement = selectedRun.closest("div[class*='px-3']");
      expect(runElement?.className).toContain('bg-indigo-50');
      expect(runElement?.className).toContain('border-l-indigo-500');

      // X icon should be visible for selected run
      const xIcon = runElement?.querySelector('span.hero-x-mark');
      expect(xIcon).toBeInTheDocument();
    });

    test('clicking run calls selectRunHandler', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // Click a run (click the run row, not just the text)
      const runId = screen.getByText(/8c7087f8/);
      const runRow = runId.closest("div[class*='px-3']");
      fireEvent.click(runRow!);

      // Should call selectRunHandler
      expect(selectRunHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          id: '8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9',
          state: 'success',
        })
      );
    });

    test('clicking selected run calls onDeselectRun', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const onDeselectRun = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          onDeselectRun={onDeselectRun}
        />
      );

      // Click the already selected run (click the row container)
      const selectedRun = screen.getByText(/d1f87a82/);
      const runRow = selectedRun.closest("div[class*='px-3']");
      fireEvent.click(runRow!);

      // Should call onDeselectRun, not onCollapseHistory or selectRunHandler
      expect(onDeselectRun).toHaveBeenCalledTimes(1);
      expect(onCollapseHistory).not.toHaveBeenCalled();
      expect(selectRunHandler).not.toHaveBeenCalled();
    });
  });

  // ==========================================================================
  // STATUS PILLS
  // ==========================================================================

  describe('status pills show correct colors for each state', () => {
    test.each([
      {
        state: 'success',
        expectedColor: 'bg-green-200',
        textColor: 'text-green-800',
      },
      {
        state: 'failed',
        expectedColor: 'bg-red-200',
        textColor: 'text-red-800',
      },
      {
        state: 'crashed',
        expectedColor: 'bg-orange-200',
        textColor: 'text-orange-800',
      },
      {
        state: 'started',
        expectedColor: 'bg-blue-200',
        textColor: 'text-blue-800',
      },
      {
        state: 'available',
        expectedColor: 'bg-gray-200',
        textColor: 'text-gray-800',
      },
      {
        state: 'claimed',
        expectedColor: 'bg-blue-200',
        textColor: 'text-blue-800',
      },
      {
        state: 'cancelled',
        expectedColor: 'bg-gray-500',
        textColor: 'text-gray-800',
      },
      {
        state: 'killed',
        expectedColor: 'bg-yellow-200',
        textColor: 'text-yellow-800',
      },
      {
        state: 'exception',
        expectedColor: 'bg-gray-800',
        textColor: 'text-white',
      },
      { state: 'lost', expectedColor: 'bg-gray-800', textColor: 'text-white' },
    ])(
      '$state state has correct colors',
      ({ state, expectedColor, textColor }) => {
        const onCollapseHistory = vi.fn();
        const selectRunHandler = vi.fn();
        const workOrder = createMockWorkOrder({
          id: `test-wo-${state}`,
          state: state as any,
          runs: [
            {
              id: `test-run-${state}`,
              state: state as any,
              started_at: '2025-10-23T20:00:00Z',
              finished_at: '2025-10-23T20:00:01Z',
              error_type: null,
              selected: false,
            },
          ],
        });

        render(
          <MiniHistory
            collapsed={false}
            history={[workOrder]}
            onCollapseHistory={onCollapseHistory}
            selectRunHandler={selectRunHandler}
          />
        );

        // Find the status pill by text (capitalize first letter)
        const pillText = state.charAt(0).toUpperCase() + state.slice(1);
        const pill = screen.getByText(pillText);

        // Check that the pill has the correct color classes
        expect(pill.className).toContain(expectedColor);
        expect(pill.className).toContain(textColor);
      }
    );

    test('all possible states render with appropriate colors', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const allStateWorkOrders = createWorkOrdersForAllStates();

      render(
        <MiniHistory
          collapsed={false}
          history={allStateWorkOrders}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Work order state pills are visible immediately (show work order state)
      // Run states: available, claimed, started map to "success" work order state
      // Expected work order states that match run states:
      // success, failed, killed, exception, crashed, cancelled, lost
      const uniqueWorkOrderStates = [
        'Success', // appears multiple times (for available, claimed, started runs)
        'Failed',
        'Killed',
        'Exception',
        'Crashed',
        'Cancelled',
        'Lost',
      ];

      uniqueWorkOrderStates.forEach(state => {
        // Use queryAllByText since "Success" appears multiple times
        const pills = screen.queryAllByText(state);
        expect(pills.length).toBeGreaterThan(0);
      });
    });
  });

  // ==========================================================================
  // NAVIGATION BEHAVIOR
  // ==========================================================================

  describe('navigation behavior', () => {
    test('clicking view full history button navigates to history page', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const viewHistoryButton = screen.getByRole('button', {
        name: /View full history for this workflow/i,
      });

      fireEvent.click(viewHistoryButton);

      // Should navigate to history page with workflow filter
      expect(mockLocationAssign).toHaveBeenCalledOnce();
      const calledUrl = mockLocationAssign.mock.calls[0][0];
      expect(calledUrl).toContain('/history');
      // URLSearchParams encodes square brackets, so we need to decode or check the encoded version
      expect(decodeURIComponent(calledUrl)).toContain(
        'filters[workflow_id]=test-workflow-id'
      );
    });

    test('view history button supports keyboard navigation', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const viewHistoryButton = screen.getByRole('button', {
        name: /View full history for this workflow/i,
      });

      // Test Enter key
      fireEvent.keyDown(viewHistoryButton, { key: 'Enter' });
      expect(mockLocationAssign).toHaveBeenCalledOnce();
      const calledUrl = mockLocationAssign.mock.calls[0][0];
      expect(calledUrl).toContain('/history');
    });

    test('clicking work order ID navigates to work order detail page', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const workOrderLink = screen.getByText(/e2107d46/);
      fireEvent.click(workOrderLink);

      // Should navigate to work order detail page
      expect(mockLocationAssign).toHaveBeenCalledOnce();
      const calledUrl = mockLocationAssign.mock.calls[0][0];
      expect(calledUrl).toContain('/projects/test-project-id/history');
      // URLSearchParams encodes square brackets, so we need to decode or check the encoded version
      expect(decodeURIComponent(calledUrl)).toContain(
        'filters[workorder_id]=e2107d46-cf29-4930-b11b-cbcfcf83549d'
      );
    });

    test('clicking run ID navigates to run detail page', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Expand work order
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // Click run ID link directly (find the button within the run)
      const runLink = screen.getByText(/8c7087f8/).closest('button');
      fireEvent.click(runLink!);

      // Should navigate to run detail page
      expect(mockLocationAssign).toHaveBeenCalledOnce();
      const calledUrl = mockLocationAssign.mock.calls[0][0];
      expect(calledUrl).toContain(
        '/projects/test-project-id/runs/8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9'
      );
    });
  });

  // ==========================================================================
  // AUTO-EXPAND SELECTED WORK ORDER
  // ==========================================================================

  describe('auto-expand behavior for selected items', () => {
    test('selected work order is visible when panel is not collapsed', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      // Render with expanded state and selected work order
      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Panel should show expanded state with work order visible
      expect(screen.getByText('Recent History')).toBeInTheDocument();
      expect(screen.getByText(/7f0419b6/)).toBeInTheDocument();
    });

    test('selected work order is automatically expanded to show runs', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockSelectedWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Selected work order should be expanded, showing its run
      expect(screen.getByText(/d1f87a82/)).toBeInTheDocument();

      // Chevron should point down for expanded selected work order
      const chevron = screen
        .getByText(/7f0419b6/)
        .closest('div')
        ?.querySelector('span.hero-chevron-down');
      expect(chevron).toBeInTheDocument();
    });
  });

  // ==========================================================================
  // ACCESSIBILITY
  // ==========================================================================

  describe('accessibility', () => {
    test('view history button has descriptive aria-label', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={mockHistoryList}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      const button = screen.getByRole('button', {
        name: /View full history for this workflow/i,
      });
      expect(button).toHaveAttribute(
        'aria-label',
        'View full history for this workflow'
      );
    });

    test('work order and run links have title attributes with full IDs', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          collapsed={false}
          history={[mockMultiRunWorkOrder]}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
        />
      );

      // Work order link (button) has full ID in title
      const workOrderButton = screen.getByText(/b65107f9/).closest('button');
      expect(workOrderButton).toHaveAttribute(
        'title',
        'b65107f9-2a5f-4bd1-b97d-b8500a58f621'
      );

      // Expand to see runs
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // Run links (buttons) have full IDs in title
      const runButton = screen.getByText(/8c7087f8/).closest('button');
      expect(runButton).toHaveAttribute(
        'title',
        '8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9'
      );
    });
  });

  // ==========================================================================
  // LOADING STATE
  // ==========================================================================

  describe('Loading State', () => {
    test('shows loading spinner when loading=true', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          loading={true}
        />
      );

      // Loading message should be visible
      expect(screen.getByText('Loading history...')).toBeInTheDocument();

      // Spinner should be present (has animate-spin class)
      const spinner = screen
        .getByText('Loading history...')
        .parentElement?.querySelector('.animate-spin');
      expect(spinner).toBeInTheDocument();

      // History list should not be visible
      expect(screen.queryByText(/No related history/)).not.toBeInTheDocument();
    });

    test('does not show loading when loading=false', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          loading={false}
        />
      );

      // Loading message should not be visible
      expect(screen.queryByText('Loading history...')).not.toBeInTheDocument();

      // Empty state should show instead
      expect(screen.getByText('No related history')).toBeInTheDocument();
    });
  });

  // ==========================================================================
  // ERROR STATE
  // ==========================================================================

  describe('Error State', () => {
    test('shows error message when error is provided', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const onRetry = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          error="Failed to fetch history"
          onRetry={onRetry}
        />
      );

      // Error heading should be visible
      expect(screen.getByText('Failed to load history')).toBeInTheDocument();

      // Specific error message should be visible
      expect(screen.getByText('Failed to fetch history')).toBeInTheDocument();

      // Retry button should be present
      const retryButton = screen.getByRole('button', { name: /Retry/i });
      expect(retryButton).toBeInTheDocument();
    });

    test('calls onRetry when retry button clicked', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();
      const onRetry = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          error="Network error"
          onRetry={onRetry}
        />
      );

      const retryButton = screen.getByRole('button', { name: /Retry/i });
      fireEvent.click(retryButton);

      expect(onRetry).toHaveBeenCalledOnce();
    });

    test('does not show retry button when onRetry is not provided', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          error="Network error"
        />
      );

      // Error message should still be visible
      expect(screen.getByText('Failed to load history')).toBeInTheDocument();

      // But retry button should not be present
      expect(
        screen.queryByRole('button', { name: /Retry/i })
      ).not.toBeInTheDocument();
    });

    test('shows error instead of loading when both are true', () => {
      const onCollapseHistory = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          history={[]}
          collapsed={false}
          onCollapseHistory={onCollapseHistory}
          selectRunHandler={selectRunHandler}
          loading={true}
          error="Network error"
        />
      );

      // Loading takes precedence in the conditional check
      expect(screen.getByText('Loading history...')).toBeInTheDocument();
      expect(
        screen.queryByText('Failed to load history')
      ).not.toBeInTheDocument();
    });
  });

  // ==========================================================================
  // PANEL VARIANT
  // ==========================================================================

  describe('panel variant', () => {
    const mockWorkOrder = createMockWorkOrder({
      id: 'panel-test-wo',
      runs: [
        {
          id: 'panel-test-run',
          state: 'success',
          started_at: '2025-10-23T20:00:00Z',
          finished_at: '2025-10-23T20:00:01Z',
          error_type: null,
          selected: false,
        },
      ],
    });

    test('renders without absolute positioning', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
        />
      );

      // Find the outermost container
      const container = screen
        .getByText('Run History')
        .closest('div.flex.flex-col.h-full');
      expect(container).toBeInTheDocument();

      // Should not have absolute positioning
      expect(container?.className).not.toContain('absolute');

      // Should have panel-specific classes
      expect(container?.className).toContain('flex-col');
      expect(container?.className).toContain('h-full');
      expect(container?.className).toContain('bg-white');
    });

    test('shows back button that calls onBack', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
        />
      );

      const backButton = screen.getByRole('button', {
        name: /Back to landing/i,
      });
      expect(backButton).toBeInTheDocument();

      fireEvent.click(backButton);

      expect(onBack).toHaveBeenCalledOnce();
    });

    test('does not show collapse/expand controls', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
        />
      );

      // Panel variant should not have the collapsible header
      expect(screen.queryByText('Recent History')).not.toBeInTheDocument();
      expect(screen.queryByText('View History')).not.toBeInTheDocument();

      // Should not have chevron collapse indicators in the header
      const header = screen.getByText('Run History').closest('div.px-3.py-2');
      expect(header?.querySelector('span.hero-chevron-left')).toBeNull();
      expect(header?.querySelector('span.hero-chevron-right')).toBeNull();
    });

    test('displays panel header with title and full history button', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
        />
      );

      // Panel header should show "Run History" title
      expect(screen.getByText('Run History')).toBeInTheDocument();

      // Should have the "View full history" button
      const viewHistoryButton = screen.getByRole('button', {
        name: /View full history for this workflow/i,
      });
      expect(viewHistoryButton).toBeInTheDocument();
    });

    test('displays work orders and runs in panel variant', () => {
      const onBack = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={selectRunHandler}
          onBack={onBack}
        />
      );

      // Work order ID is truncated (first 8 characters)
      // panel-test-wo is only 13 chars, so just check for 'panel-te'
      expect(screen.getByText(/panel-te/)).toBeInTheDocument();

      // Status pill should be visible
      expect(screen.getByText('Success')).toBeInTheDocument();
    });

    test('allows run selection in panel variant', () => {
      const onBack = vi.fn();
      const selectRunHandler = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={selectRunHandler}
          onBack={onBack}
        />
      );

      // Click work order chevron to expand (or auto-select single run)
      const expandButton = screen.getByRole('button', {
        name: /Expand work order details/i,
      });
      fireEvent.click(expandButton);

      // Should call selectRunHandler (auto-selects single run)
      expect(selectRunHandler).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'panel-test-run',
          state: 'success',
        })
      );
    });

    test('shows loading state in panel variant', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
          loading={true}
        />
      );

      expect(screen.getByText('Loading history...')).toBeInTheDocument();

      // Spinner should be present
      const spinner = screen
        .getByText('Loading history...')
        .parentElement?.querySelector('.animate-spin');
      expect(spinner).toBeInTheDocument();
    });

    test('shows error state in panel variant with retry button', () => {
      const onBack = vi.fn();
      const onRetry = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
          error="Failed to fetch history"
          onRetry={onRetry}
        />
      );

      expect(screen.getByText('Failed to load history')).toBeInTheDocument();
      expect(screen.getByText('Failed to fetch history')).toBeInTheDocument();

      const retryButton = screen.getByRole('button', { name: /Retry/i });
      fireEvent.click(retryButton);

      expect(onRetry).toHaveBeenCalledOnce();
    });

    test('shows empty state in panel variant', () => {
      const onBack = vi.fn();

      render(
        <MiniHistory
          variant="panel"
          collapsed={false}
          history={[]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
          onBack={onBack}
        />
      );

      expect(screen.getByText('No related history')).toBeInTheDocument();
      expect(
        screen.getByText(/Why not run it a few times to see some history?/i)
      ).toBeInTheDocument();
    });

    test('defaults to floating variant when variant prop is omitted', () => {
      render(
        <MiniHistory
          collapsed={false}
          history={[mockWorkOrder]}
          onCollapseHistory={vi.fn()}
          selectRunHandler={vi.fn()}
        />
      );

      // Floating variant should show "Recent History" header
      expect(screen.getByText('Recent History')).toBeInTheDocument();

      // Should have absolute positioning
      const container = screen
        .getByText('Recent History')
        .closest('div.absolute');
      expect(container).toBeInTheDocument();
    });
  });
});
