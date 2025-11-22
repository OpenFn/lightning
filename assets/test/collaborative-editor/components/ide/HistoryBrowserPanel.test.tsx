import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';

import { HistoryBrowserPanel } from '../../../../js/collaborative-editor/components/ide/HistoryBrowserPanel';
import * as useHistoryModule from '../../../../js/collaborative-editor/hooks/useHistory';

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

vi.mock('../../../../js/collaborative-editor/hooks/useHistory');

describe('HistoryBrowserPanel', () => {
  const mockUseHistory = vi.mocked(useHistoryModule.useHistory);
  const mockUseHistoryLoading = vi.mocked(useHistoryModule.useHistoryLoading);
  const mockUseHistoryError = vi.mocked(useHistoryModule.useHistoryError);
  const mockUseHistoryCommands = vi.mocked(useHistoryModule.useHistoryCommands);

  beforeEach(() => {
    vi.clearAllMocks();
    // Set default mock return values
    mockUseHistory.mockReturnValue([]);
    mockUseHistoryLoading.mockReturnValue(false);
    mockUseHistoryError.mockReturnValue(null);
    mockUseHistoryCommands.mockReturnValue({
      requestHistory: vi.fn(),
      requestRunSteps: vi.fn(),
      getRunSteps: vi.fn(),
      clearError: vi.fn(),
      selectStep: vi.fn(),
      clearActiveRunError: vi.fn(),
    });
  });

  it('renders header with back button', () => {
    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    expect(screen.getByText('Browse History')).toBeInTheDocument();
    expect(screen.getByLabelText('Close history browser')).toBeInTheDocument();
  });

  it('calls onClose when back button is clicked', () => {
    const onClose = vi.fn();
    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={onClose}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    fireEvent.click(screen.getByLabelText('Close history browser'));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('displays loading state', () => {
    mockUseHistoryLoading.mockReturnValue(true);

    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    expect(screen.getByText('Loading history...')).toBeInTheDocument();
  });

  it('displays empty state when no work orders', () => {
    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    expect(screen.getByText('No Runs Yet')).toBeInTheDocument();
    expect(screen.getByText('Create First Run')).toBeInTheDocument();
  });

  it('displays history list when work orders exist', () => {
    mockUseHistory.mockReturnValue([
      {
        id: 'wo-123',
        state: 'success',
        last_activity: '2025-01-22T10:00:00Z',
        inserted_at: '2025-01-22T09:00:00Z',
        version: 1,
        runs: [],
      },
    ]);

    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    expect(screen.getByText(/wo-123/)).toBeInTheDocument();
  });

  it('calls onSelectRun when run is selected from history list', () => {
    const onSelectRun = vi.fn();
    mockUseHistory.mockReturnValue([
      {
        id: 'wo-123',
        state: 'success',
        last_activity: '2025-01-22T10:00:00Z',
        inserted_at: '2025-01-22T09:00:00Z',
        version: 1,
        runs: [
          {
            id: 'run-456',
            state: 'success',
            error_type: null,
            started_at: '2025-01-22T09:30:00Z',
            finished_at: '2025-01-22T09:31:00Z',
          },
        ],
      },
    ]);

    render(
      <HistoryBrowserPanel
        onSelectRun={onSelectRun}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    // Expand work order
    fireEvent.click(screen.getByLabelText('Expand work order details'));

    // Click run
    fireEvent.click(screen.getByText(/run-456/));

    expect(onSelectRun).toHaveBeenCalledWith('run-456');
  });

  it('displays error state with retry', () => {
    const requestHistory = vi.fn();
    mockUseHistoryError.mockReturnValue('Network error');
    mockUseHistoryCommands.mockReturnValue({
      requestHistory,
      requestRunSteps: vi.fn(),
      getRunSteps: vi.fn(),
      clearError: vi.fn(),
      selectStep: vi.fn(),
      clearActiveRunError: vi.fn(),
    });

    render(
      <HistoryBrowserPanel
        onSelectRun={vi.fn()}
        onClose={vi.fn()}
        projectId="proj-123"
        workflowId="wf-456"
      />
    );

    expect(screen.getByText('Failed to load history')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Try again'));
    expect(requestHistory).toHaveBeenCalledTimes(1);
  });
});
