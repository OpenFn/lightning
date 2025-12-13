/**
 * Tests for JobSelector component
 *
 * Tests the job selection dropdown that displays jobs in topological order
 * based on the workflow graph structure.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';

import { JobSelector } from '../../../js/collaborative-editor/components/JobSelector';
import type { Job } from '../../../js/collaborative-editor/types/job';

/**
 * Create a mock job with minimal required fields
 */
function createMockJob(overrides: Partial<Job> = {}): Job {
  return {
    id: 'job-1',
    name: 'Test Job',
    body: 'fn(state => state);',
    adaptor: '@openfn/language-common@latest',
    enabled: true,
    ...overrides,
  } as Job;
}

describe('JobSelector', () => {
  it('renders current job name in button', () => {
    const currentJob = createMockJob({ id: 'job-1', name: 'Fetch Data' });
    const jobs = [currentJob];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    expect(screen.getByText('Fetch Data')).toBeInTheDocument();
  });

  it('displays chevron icon in button', () => {
    const currentJob = createMockJob({ id: 'job-1', name: 'Fetch Data' });
    const jobs = [currentJob];
    const onChange = vi.fn();

    const { container } = render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    const chevron = container.querySelector('.hero-chevron-up-down');
    expect(chevron).toBeInTheDocument();
  });

  it('marks currently selected job as selected', async () => {
    const user = userEvent.setup();
    const currentJob = createMockJob({ id: 'job-1', name: 'Fetch Data' });
    const jobs = [
      currentJob,
      createMockJob({ id: 'job-2', name: 'Transform Data' }),
    ];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown
    const button = screen.getByRole('button');
    await user.click(button);

    // Get all options
    const options = screen.getAllByRole('option');

    // First option (Fetch Data) should have aria-selected="true"
    expect(options[0]).toHaveAttribute('aria-selected', 'true');
    // Second option (Transform Data) should have aria-selected="false"
    expect(options[1]).toHaveAttribute('aria-selected', 'false');
  });

  it('calls onChange when a different job is selected', async () => {
    const user = userEvent.setup();
    const currentJob = createMockJob({ id: 'job-1', name: 'Fetch Data' });
    const job2 = createMockJob({ id: 'job-2', name: 'Transform Data' });
    const jobs = [currentJob, job2];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown
    const button = screen.getByRole('button');
    await user.click(button);

    // Click on different job
    await user.click(screen.getByText('Transform Data'));

    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith(job2);
  });

  it('renders jobs in the order they are provided', async () => {
    const user = userEvent.setup();
    const currentJob = createMockJob({ id: 'job-1', name: 'Job A' });
    const jobs = [
      createMockJob({ id: 'job-3', name: 'Job C' }),
      createMockJob({ id: 'job-1', name: 'Job A' }),
      createMockJob({ id: 'job-2', name: 'Job B' }),
    ];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown
    await user.click(screen.getByText('Job A'));

    // Get all job options
    const options = screen.getAllByRole('option');

    // Jobs should be in the provided order (not alphabetical)
    expect(options[0]).toHaveTextContent('Job C');
    expect(options[1]).toHaveTextContent('Job A');
    expect(options[2]).toHaveTextContent('Job B');
  });

  it('handles single job workflow', async () => {
    const user = userEvent.setup();
    const currentJob = createMockJob({ id: 'job-1', name: 'Only Job' });
    const jobs = [currentJob];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown
    await user.click(screen.getByText('Only Job'));

    // Should show the single job
    const options = screen.getAllByRole('option');
    expect(options).toHaveLength(1);
    expect(options[0]).toHaveTextContent('Only Job');
  });

  it('does not sort jobs alphabetically', async () => {
    const user = userEvent.setup();
    // Jobs are passed in workflow execution order, NOT alphabetical order
    const currentJob = createMockJob({ id: 'job-z', name: 'Zebra Job' });
    const jobs = [
      createMockJob({ id: 'job-z', name: 'Zebra Job' }),
      createMockJob({ id: 'job-a', name: 'Apple Job' }),
      createMockJob({ id: 'job-m', name: 'Mango Job' }),
    ];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown
    await user.click(screen.getByText('Zebra Job'));

    // Get all job options
    const options = screen.getAllByRole('option');

    // Should maintain original order (Zebra, Apple, Mango), not alphabetical
    expect(options[0]).toHaveTextContent('Zebra Job');
    expect(options[1]).toHaveTextContent('Apple Job');
    expect(options[2]).toHaveTextContent('Mango Job');
  });

  it('updates display when currentJob prop changes', () => {
    const job1 = createMockJob({ id: 'job-1', name: 'Job 1' });
    const job2 = createMockJob({ id: 'job-2', name: 'Job 2' });
    const jobs = [job1, job2];
    const onChange = vi.fn();

    const { rerender } = render(
      <JobSelector currentJob={job1} jobs={jobs} onChange={onChange} />
    );

    expect(screen.getByText('Job 1')).toBeInTheDocument();

    // Update currentJob
    rerender(<JobSelector currentJob={job2} jobs={jobs} onChange={onChange} />);

    expect(screen.getByText('Job 2')).toBeInTheDocument();
  });

  it('handles empty job names gracefully', async () => {
    const user = userEvent.setup();
    const currentJob = createMockJob({ id: 'job-1', name: '' });
    const jobs = [
      currentJob,
      createMockJob({ id: 'job-2', name: 'Named Job' }),
    ];
    const onChange = vi.fn();

    render(
      <JobSelector currentJob={currentJob} jobs={jobs} onChange={onChange} />
    );

    // Click to open dropdown (clicking on the button, not the empty text)
    const button = screen.getByRole('button');
    await user.click(button);

    // Should show both jobs
    const options = screen.getAllByRole('option');
    expect(options).toHaveLength(2);
  });

  it('shows "Select a job" placeholder when currentJob is null', () => {
    const jobs = [
      createMockJob({ id: 'job-1', name: 'Job 1' }),
      createMockJob({ id: 'job-2', name: 'Job 2' }),
    ];
    const onChange = vi.fn();

    render(<JobSelector currentJob={null} jobs={jobs} onChange={onChange} />);

    expect(screen.getByText('Select a job')).toBeInTheDocument();
  });

  it('allows selecting a job when currentJob is null', async () => {
    const user = userEvent.setup();
    const job1 = createMockJob({ id: 'job-1', name: 'Job 1' });
    const job2 = createMockJob({ id: 'job-2', name: 'Job 2' });
    const jobs = [job1, job2];
    const onChange = vi.fn();

    render(<JobSelector currentJob={null} jobs={jobs} onChange={onChange} />);

    // Click to open dropdown
    const button = screen.getByRole('button');
    await user.click(button);

    // Select a job
    await user.click(screen.getByText('Job 1'));

    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith(job1);
  });

  it('shows all jobs in dropdown when currentJob is null', async () => {
    const user = userEvent.setup();
    const jobs = [
      createMockJob({ id: 'job-1', name: 'Job 1' }),
      createMockJob({ id: 'job-2', name: 'Job 2' }),
      createMockJob({ id: 'job-3', name: 'Job 3' }),
    ];
    const onChange = vi.fn();

    render(<JobSelector currentJob={null} jobs={jobs} onChange={onChange} />);

    // Click to open dropdown
    const button = screen.getByRole('button');
    await user.click(button);

    // All jobs should be visible
    const options = screen.getAllByRole('option');
    expect(options).toHaveLength(3);
    expect(options[0]).toHaveTextContent('Job 1');
    expect(options[1]).toHaveTextContent('Job 2');
    expect(options[2]).toHaveTextContent('Job 3');
  });
});
