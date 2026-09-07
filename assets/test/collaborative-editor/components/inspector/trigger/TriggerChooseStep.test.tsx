/**
 * TriggerChooseStep Component Tests
 *
 * Covers the shared wizard "Choose" step (#4787): the type badge,
 * the "Change" link that opens the type picker, and the "Next" primary button.
 *
 * This component takes only plain callbacks and renders no store hooks, so no
 * provider wrapper is needed.
 */

import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, test, vi } from 'vitest';

import { TriggerChooseStep } from '../../../../../js/collaborative-editor/components/inspector/trigger/TriggerChooseStep';

describe('TriggerChooseStep', () => {
  test('renders the cron badge and calls onChangeType/onNext for type="cron"', async () => {
    const onClose = vi.fn();
    const onBack = vi.fn();
    const onChangeType = vi.fn();
    const onNext = vi.fn();

    render(
      <TriggerChooseStep
        type="cron"
        onClose={onClose}
        onBack={onBack}
        onChangeType={onChangeType}
        onNext={onNext}
      />
    );

    expect(screen.getByText('Schedule / Cron')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Change' }));
    expect(onChangeType).toHaveBeenCalledTimes(1);

    await userEvent.click(screen.getByRole('button', { name: 'Next' }));
    expect(onNext).toHaveBeenCalledTimes(1);
  });

  test('header back arrow calls onBack', async () => {
    const onBack = vi.fn();
    const onClose = vi.fn();

    render(
      <TriggerChooseStep
        type="cron"
        onClose={onClose}
        onBack={onBack}
        onChangeType={vi.fn()}
        onNext={vi.fn()}
      />
    );

    await userEvent.click(screen.getByRole('button', { name: 'Back' }));
    expect(onBack).toHaveBeenCalledTimes(1);
    expect(onClose).not.toHaveBeenCalled();
  });
});
