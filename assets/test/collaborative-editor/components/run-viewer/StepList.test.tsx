/**
 * StepList Component Tests
 *
 * Tests for StepList component that displays a list of execution steps
 * with selection handling.
 *
 * Test Coverage:
 * - Empty state when no steps
 * - Rendering multiple steps
 * - Step selection
 * - Step highlighting
 * - Accessibility (ARIA labels)
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import { StepList } from '../../../../js/collaborative-editor/components/run-viewer/StepList';
import type { StepDetail } from '../../../../js/collaborative-editor/types/history';

// Mock useURLState hook
const mockUpdateSearchParams = vi.fn();
const mockParams: Record<string, string> = {};
vi.mock('../../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    params: mockParams,
    updateSearchParams: mockUpdateSearchParams,
  }),
}));

// Mock useWorkflowState hook
vi.mock('../../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: (selector: any) => {
    // Return job name from step.job if available, otherwise "Unknown Job"
    const mockState = {
      jobs: [
        { id: 'job-1', name: 'Test Job' },
        { id: 'job-2', name: 'Job 2' },
        { id: 'job-3', name: 'Job 3' },
        { id: 'job-1', name: 'My Job' },
        { id: 'job-1', name: 'Data Fetch' },
        { id: 'job-1', name: 'Success Job' },
        { id: 'job-2', name: 'Failed Job' },
        { id: 'job-3', name: 'Running Job' },
        { id: 'job-1', name: 'Selected Job' },
        { id: 'job-1', name: 'Job 1' },
      ],
    };
    return selector(mockState);
  },
}));

// Mock step factory
const createMockStep = (overrides?: Partial<StepDetail>): StepDetail => ({
  id: `step-${Math.random()}`,
  job_id: 'job-1',
  job: {
    name: 'Test Job',
  },
  exit_reason: null,
  error_type: null,
  started_at: new Date().toISOString(),
  finished_at: null,
  input_dataclip_id: null,
  output_dataclip_id: null,
  inserted_at: new Date().toISOString(),
  ...overrides,
});

describe('StepList', () => {
  const mockRunInsertedAt = new Date().toISOString();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('empty state', () => {
    test('shows empty message when no steps', () => {
      render(
        <StepList
          steps={[]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      expect(screen.getByText('No steps yet')).toBeInTheDocument();
    });
  });

  describe('rendering steps', () => {
    test('renders single step', () => {
      const step = createMockStep({
        job: { name: 'My Job' },
      });

      render(
        <StepList
          steps={[step]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      expect(screen.getByText('My Job')).toBeInTheDocument();
    });

    test('renders multiple steps', () => {
      const steps = [
        createMockStep({ job: { name: 'Job 1' } }),
        createMockStep({ job: { name: 'Job 2' } }),
        createMockStep({ job: { name: 'Job 3' } }),
      ];

      render(
        <StepList
          steps={steps}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      expect(screen.getByText('Job 1')).toBeInTheDocument();
      expect(screen.getByText('Job 2')).toBeInTheDocument();
      expect(screen.getByText('Job 3')).toBeInTheDocument();
    });

    test('renders steps with different exit reasons', () => {
      const steps = [
        createMockStep({
          id: 'step-1',
          job: { name: 'Success Job' },
          exit_reason: 'success',
        }),
        createMockStep({
          id: 'step-2',
          job: { name: 'Failed Job' },
          exit_reason: 'fail',
        }),
        createMockStep({
          id: 'step-3',
          job: { name: 'Running Job' },
          exit_reason: null,
        }),
      ];

      render(
        <StepList
          steps={steps}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      expect(screen.getByText('Success Job')).toBeInTheDocument();
      expect(screen.getByText('Failed Job')).toBeInTheDocument();
      expect(screen.getByText('Running Job')).toBeInTheDocument();
    });
  });

  describe('step selection', () => {
    test('updates URL when step clicked', async () => {
      const user = userEvent.setup();
      const step = createMockStep({
        id: 'step-1',
        job_id: 'job-1',
        job: { name: 'My Job' },
      });

      render(
        <StepList
          steps={[step]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      await user.click(screen.getByText('My Job'));

      expect(mockUpdateSearchParams).toHaveBeenCalledWith({
        job: 'job-1',
        run: null,
        step: 'step-1',
      });
    });

    test('highlights selected step', () => {
      const steps = [
        createMockStep({
          id: 'step-1',
          job: { name: 'Job 1' },
        }),
        createMockStep({
          id: 'step-2',
          job: { name: 'Job 2' },
        }),
      ];

      const { container } = render(
        <StepList
          steps={steps}
          selectedStepId="step-2"
          runInsertedAt={mockRunInsertedAt}
        />
      );

      // Check for primary border color on selected step
      const selectedBorder = container.querySelector('.border-primary-500');
      expect(selectedBorder).toBeInTheDocument();
    });

    test('applies correct styles to selected step', () => {
      const steps = [
        createMockStep({
          id: 'step-1',
          job: { name: 'Selected Job' },
        }),
      ];

      const { container } = render(
        <StepList
          steps={steps}
          selectedStepId="step-1"
          runInsertedAt={mockRunInsertedAt}
        />
      );

      // Check for selected styles
      const selectedStep = container.querySelector('.bg-primary-50');
      expect(selectedStep).toBeInTheDocument();

      const boldText = container.querySelector('.font-semibold');
      expect(boldText).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    test('has proper ARIA list role', () => {
      const step = createMockStep();

      render(
        <StepList
          steps={[step]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      const list = screen.getByRole('list', {
        name: /execution steps/i,
      });
      expect(list).toBeInTheDocument();
    });

    test('each step is a list item', () => {
      const steps = [
        createMockStep({ id: 'step-1' }),
        createMockStep({ id: 'step-2' }),
      ];

      render(
        <StepList
          steps={steps}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      const listItems = screen.getAllByRole('listitem');
      expect(listItems).toHaveLength(2);
    });
  });

  describe('edge cases', () => {
    test('handles step without job name', () => {
      const step = createMockStep({
        job_id: 'nonexistent-job-id',
        job: undefined,
      });

      render(
        <StepList
          steps={[step]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      expect(screen.getByText('Unknown Job')).toBeInTheDocument();
    });

    test('handles step with very long job name', () => {
      const longName = 'A'.repeat(100);
      const step = createMockStep({
        job: { name: longName },
      });

      const { container } = render(
        <StepList
          steps={[step]}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      // Should have truncate class
      const truncatedText = container.querySelector('.truncate');
      expect(truncatedText).toBeInTheDocument();
    });

    test('handles many steps efficiently', () => {
      // Mock needs to have all jobs available
      const mockJobs = Array.from({ length: 50 }, (_, i) => ({
        id: `job-${i}`,
        name: `Job ${i}`,
      }));

      // Override the mock for this test
      vi.doMock(
        '../../../../js/collaborative-editor/hooks/useWorkflow',
        () => ({
          useWorkflowState: (selector: any) => {
            return selector({ jobs: mockJobs });
          },
        })
      );

      const steps = Array.from({ length: 50 }, (_, i) =>
        createMockStep({
          id: `step-${i}`,
          job: { name: `Job ${i}` },
        })
      );

      const { container } = render(
        <StepList
          steps={steps}
          selectedStepId={null}
          runInsertedAt={mockRunInsertedAt}
        />
      );

      const listItems = container.querySelectorAll('li');
      expect(listItems).toHaveLength(50);
    });
  });
});
