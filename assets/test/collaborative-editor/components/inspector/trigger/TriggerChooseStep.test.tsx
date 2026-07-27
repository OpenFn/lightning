/**
 * TriggerChooseStep Component Tests
 *
 * Covers the shared cron/kafka wizard "Choose" step (#4787): the type badge,
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

  test('renders the kafka badge for type="kafka"', () => {
    render(
      <TriggerChooseStep
        type="kafka"
        onClose={vi.fn()}
        onBack={vi.fn()}
        onChangeType={vi.fn()}
        onNext={vi.fn()}
      />
    );

    // Both the header title and the badge show "Kafka"; assert the badge element
    // (a span with the green pill classes) is present.
    const badges = screen.getAllByText('Kafka');
    expect(badges.length).toBeGreaterThanOrEqual(1);
    const badge = badges.find(el => el.tagName === 'SPAN');
    expect(badge).toBeTruthy();
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
