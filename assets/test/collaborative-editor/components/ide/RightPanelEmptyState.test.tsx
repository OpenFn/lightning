import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';

import { RightPanelEmptyState } from '../../../../js/collaborative-editor/components/ide/RightPanelEmptyState';

describe('RightPanelEmptyState', () => {
  it('renders both action buttons', () => {
    render(
      <RightPanelEmptyState onBrowseHistory={vi.fn()} onCreateRun={vi.fn()} />
    );

    expect(screen.getByText('Browse History')).toBeInTheDocument();
    expect(screen.getByText('Create New Run')).toBeInTheDocument();
  });

  it('calls onBrowseHistory when browse button is clicked', () => {
    const onBrowseHistory = vi.fn();
    render(
      <RightPanelEmptyState
        onBrowseHistory={onBrowseHistory}
        onCreateRun={vi.fn()}
      />
    );

    fireEvent.click(screen.getByText('Browse History'));
    expect(onBrowseHistory).toHaveBeenCalledTimes(1);
  });

  it('calls onCreateRun when create button is clicked', () => {
    const onCreateRun = vi.fn();
    render(
      <RightPanelEmptyState
        onBrowseHistory={vi.fn()}
        onCreateRun={onCreateRun}
      />
    );

    fireEvent.click(screen.getByText('Create New Run'));
    expect(onCreateRun).toHaveBeenCalledTimes(1);
  });

  it('displays descriptive subtitles', () => {
    render(
      <RightPanelEmptyState onBrowseHistory={vi.fn()} onCreateRun={vi.fn()} />
    );

    expect(screen.getByText('Pick a run to inspect')).toBeInTheDocument();
    expect(screen.getByText('Select input and execute')).toBeInTheDocument();
  });
});
