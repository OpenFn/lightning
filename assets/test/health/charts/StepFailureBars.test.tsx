import { render, screen } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import {
  StepFailureBars,
  stepFailureTotal,
} from '#/health/charts/StepFailureBars';
import type { ErrorSignature } from '#/health/types';

import { signature } from './counts';

// A run-level failure: nothing reached a step, so there is no job to blame.
const runLevel = (overrides: Partial<ErrorSignature> = {}) =>
  signature({
    exit_reason: 'lost',
    job_id: null,
    step_name: null,
    adaptor: null,
    ...overrides,
  });

const bars = (signatures: ErrorSignature[], emptyMessage = 'No failures') =>
  render(
    <StepFailureBars signatures={signatures} emptyMessage={emptyMessage} />
  );

const rows = () => screen.getAllByRole('listitem').map(li => li.textContent);

// The bar is `aria-hidden` decoration — the count beside it is the row's
// accessible value — so it is reachable only by walking the row's label out to
// it. The row is found by that label's `title`, which is there for a step name
// too long for the card.
const bar = (label: string) =>
  screen.getByTitle(label).closest('li')!.querySelector('[aria-hidden] > div');

describe('StepFailureBars', () => {
  test('lists one row per step, heaviest first', () => {
    bars([
      signature({ count: 36, job_id: 'job-b', step_name: 'Post-to-Punto' }),
      signature({ count: 62, job_id: 'job-a', step_name: 'Map-beneficiary' }),
      signature({ count: 12, job_id: 'job-c', step_name: 'Fetch-households' }),
    ]);

    expect(rows()).toEqual([
      'Map-beneficiary62',
      'Post-to-Punto36',
      'Fetch-households12',
    ]);
  });

  // Triage splits a job by exit reason and error type; a step is one place to
  // go and look however many ways it broke.
  test('folds a step together across its exit reasons and error types', () => {
    bars([
      signature({ count: 40, error_type: 'RuntimeError' }),
      signature({ count: 22, exit_reason: 'crash', error_type: 'OOMError' }),
    ]);

    expect(rows()).toEqual(['Map-beneficiary62']);
  });

  // The whole point of the "no step" row: these failures would otherwise be
  // invisible, since there is no job to file them under.
  test('counts failures with no failing step in their own row, and says so', () => {
    bars([
      signature({ count: 62 }),
      runLevel({ count: 20 }),
      runLevel({ count: 4, exit_reason: 'rejected' }),
    ]);

    expect(rows()).toEqual(['Map-beneficiary62', '(no step)24']);
    expect(
      screen.getByText(/24 failures have no failing step/)
    ).toBeInTheDocument();
  });

  test('says nothing about unattributed failures when every one has a step', () => {
    bars([signature()]);

    expect(screen.queryByText(/no failing step/)).not.toBeInTheDocument();
  });

  // Bars rank the rows against each other, not against the total: against a
  // total, every row on a workflow with ten failing steps is a sliver.
  test('scales each bar against the heaviest row, not the total', () => {
    bars([
      signature({ count: 60, job_id: 'job-a', step_name: 'Heaviest' }),
      signature({ count: 15, job_id: 'job-b', step_name: 'Lightest' }),
    ]);

    expect(bar('Heaviest')).toHaveStyle({ width: '100%' });
    expect(bar('Lightest')).toHaveStyle({ width: '25%' });
  });

  test('is empty when nothing failed', () => {
    bars([], 'No failures in the last 30 days');

    expect(screen.getByText('No failures in the last 30 days')).toBeVisible();
    expect(screen.queryAllByRole('listitem')).toEqual([]);
  });

  // A job that resolved off no snapshot in the window still has to render as
  // something, and it is not the same row as "no step".
  test('labels a step whose name never resolved without merging it into (no step)', () => {
    bars([signature({ count: 3, step_name: null }), runLevel({ count: 2 })]);

    expect(rows()).toEqual(['(unknown step)3', '(no step)2']);
  });
});

describe('stepFailureTotal', () => {
  // The sum of what is drawn, which is signatures and not work orders: a work
  // order that broke in two branches is counted under each step.
  test('sums every signature, formatted', () => {
    expect(
      stepFailureTotal([
        signature({ count: 1000 }),
        signature({ count: 287, job_id: 'job-b' }),
      ])
    ).toBe('1,287 total');
  });

  test('is zero with no failures', () => {
    expect(stepFailureTotal([])).toBe('0 total');
  });
});
