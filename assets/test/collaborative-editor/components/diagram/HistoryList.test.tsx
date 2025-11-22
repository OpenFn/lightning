import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';

import { HistoryList } from '../../../../js/collaborative-editor/components/diagram/HistoryList';
import type { WorkOrder } from '../../../../js/collaborative-editor/types/history';

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

describe('HistoryList', () => {
  const mockWorkOrder: WorkOrder = {
    id: 'wo-123',
    state: 'success',
    last_activity: '2025-01-22T10:00:00Z',
    inserted_at: '2025-01-22T09:00:00Z',
    runs: [
      {
        id: 'run-456',
        state: 'success',
        started_at: '2025-01-22T09:30:00Z',
        finished_at: '2025-01-22T09:31:00Z',
        error_type: null,
        selected: false,
      },
    ],
  };

  it('renders loading state', () => {
    render(
      <HistoryList history={[]} selectRunHandler={vi.fn()} loading={true} />
    );

    expect(screen.getByText('Loading history...')).toBeInTheDocument();
  });

  it('renders error state with retry button', () => {
    const onRetry = vi.fn();
    render(
      <HistoryList
        history={[]}
        selectRunHandler={vi.fn()}
        error="Network error"
        onRetry={onRetry}
      />
    );

    expect(screen.getByText('Failed to load history')).toBeInTheDocument();
    expect(screen.getByText('Network error')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Try again'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it('renders empty state', () => {
    render(<HistoryList history={[]} selectRunHandler={vi.fn()} />);

    expect(screen.getByText('No related history')).toBeInTheDocument();
  });

  it('renders work orders and runs', () => {
    render(
      <HistoryList history={[mockWorkOrder]} selectRunHandler={vi.fn()} />
    );

    expect(screen.getByText(/wo-123/)).toBeInTheDocument();

    // Expand work order to see runs
    const expandButton = screen.getByRole('button', {
      name: /Expand work order details/i,
    });
    fireEvent.click(expandButton);

    expect(screen.getByText(/run-456/)).toBeInTheDocument();
  });

  it('calls selectRunHandler when run is clicked', () => {
    const selectRunHandler = vi.fn();
    render(
      <HistoryList
        history={[mockWorkOrder]}
        selectRunHandler={selectRunHandler}
      />
    );

    // Expand work order first
    fireEvent.click(screen.getByLabelText('Expand work order details'));

    // Click run
    const runElement = screen
      .getByText(/run-456/)
      .closest('div[class*="px-3"]');
    fireEvent.click(runElement!);

    expect(selectRunHandler).toHaveBeenCalledWith(mockWorkOrder.runs[0]);
  });

  it('expands work order on chevron click', () => {
    render(
      <HistoryList history={[mockWorkOrder]} selectRunHandler={vi.fn()} />
    );

    const chevron = screen.getByLabelText('Expand work order details');
    fireEvent.click(chevron);

    expect(
      screen.getByLabelText('Collapse work order details')
    ).toBeInTheDocument();
  });

  it('calls onWorkOrderClick when work order link is clicked', () => {
    const onWorkOrderClick = vi.fn();
    render(
      <HistoryList
        history={[mockWorkOrder]}
        selectRunHandler={vi.fn()}
        onWorkOrderClick={onWorkOrderClick}
      />
    );

    fireEvent.click(
      screen.getByLabelText('View full details for work order wo-123')
    );
    expect(onWorkOrderClick).toHaveBeenCalledWith('wo-123');
  });

  it('calls onRunClick when run link is clicked', () => {
    const onRunClick = vi.fn();
    render(
      <HistoryList
        history={[mockWorkOrder]}
        selectRunHandler={vi.fn()}
        onRunClick={onRunClick}
      />
    );

    // Expand work order first
    fireEvent.click(screen.getByLabelText('Expand work order details'));

    // Click run link
    fireEvent.click(screen.getByLabelText('View full details for run run-456'));

    expect(onRunClick).toHaveBeenCalledWith('run-456');
  });

  it('auto-selects single run when work order is expanded', () => {
    const selectRunHandler = vi.fn();
    render(
      <HistoryList
        history={[mockWorkOrder]}
        selectRunHandler={selectRunHandler}
      />
    );

    // Expand work order
    fireEvent.click(screen.getByLabelText('Expand work order details'));

    // Should auto-select the single run
    expect(selectRunHandler).toHaveBeenCalledWith(mockWorkOrder.runs[0]);
  });

  it('does not auto-select when work order has multiple runs', () => {
    const selectRunHandler = vi.fn();
    const multiRunWorkOrder: WorkOrder = {
      ...mockWorkOrder,
      runs: [
        mockWorkOrder.runs[0]!,
        {
          id: 'run-789',
          state: 'failed',
          started_at: '2025-01-22T09:32:00Z',
          finished_at: '2025-01-22T09:33:00Z',
          error_type: null,
          selected: false,
        },
      ],
    };

    render(
      <HistoryList
        history={[multiRunWorkOrder]}
        selectRunHandler={selectRunHandler}
      />
    );

    // Expand work order
    fireEvent.click(screen.getByLabelText('Expand work order details'));

    // Should NOT auto-select when there are multiple runs
    expect(selectRunHandler).not.toHaveBeenCalled();
  });

  it('calls onDeselectRun when selected run is clicked', () => {
    const onDeselectRun = vi.fn();
    const selectedWorkOrder: WorkOrder = {
      ...mockWorkOrder,
      selected: true,
      runs: [
        {
          ...mockWorkOrder.runs[0]!,
          selected: true,
        },
      ],
    };

    render(
      <HistoryList
        history={[selectedWorkOrder]}
        selectRunHandler={vi.fn()}
        onDeselectRun={onDeselectRun}
      />
    );

    // Selected work order is auto-expanded
    // Find the run's container div with the cursor-pointer class
    const runText = screen.getByText(/run-456/);
    const runClickableDiv = runText.closest('div[class*="cursor-pointer"]');
    fireEvent.click(runClickableDiv!);

    expect(onDeselectRun).toHaveBeenCalledTimes(1);
  });

  it('displays selected run with highlighted styling', () => {
    const selectedWorkOrder: WorkOrder = {
      ...mockWorkOrder,
      selected: true,
      runs: [
        {
          ...mockWorkOrder.runs[0]!,
          selected: true,
        },
      ],
    };

    render(
      <HistoryList history={[selectedWorkOrder]} selectRunHandler={vi.fn()} />
    );

    // Find the selected run element
    const runElement = screen
      .getByText(/run-456/)
      .closest('div[class*="px-3"]');

    // Check for highlighted styling classes
    expect(runElement?.className).toContain('bg-indigo-50');
    expect(runElement?.className).toContain('border-l-indigo-500');
  });
});
