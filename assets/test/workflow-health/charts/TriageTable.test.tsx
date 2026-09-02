import { render, screen, within } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { TriageTable } from '#/workflow-health/charts/TriageTable';
import type { FailureSignature } from '#/workflow-health/types';

const signature = (
  overrides: Partial<FailureSignature> = {}
): FailureSignature => ({
  count: 62,
  exit_reason: 'fail',
  error_type: 'RuntimeError',
  step_name: 'Map-beneficiary',
  adaptor: '@openfn/language-common@2.0.0',
  ...overrides,
});

const rowText = (name: string | RegExp) =>
  within(screen.getByRole('row', { name })).getByRole('cell', { name })
    .textContent;

describe('TriageTable', () => {
  test('renders the full signature grammar for a step-level failure', () => {
    render(
      <TriageTable signatures={[signature()]} emptyMessage="No failures" />
    );

    expect(rowText(/RuntimeError/)).toContain(
      'fail:RuntimeError @ Map-beneficiary [@openfn/language-common@2.0.0]'
    );
    expect(screen.getByRole('cell', { name: '62' })).toBeVisible();
    expect(
      screen.getByRole('columnheader', { name: 'Work orders' })
    ).toBeVisible();
  });

  // A run that crashed before any step has no job to name, so the grammar's
  // optional clause drops rather than rendering an empty ` @  []`.
  test('drops the step clause when nothing reached a step', () => {
    render(
      <TriageTable
        signatures={[
          signature({
            exit_reason: 'crash',
            error_type: 'CompileError',
            step_name: null,
            adaptor: null,
          }),
        ]}
        emptyMessage="No failures"
      />
    );

    const text = rowText(/CompileError/);
    expect(text).toContain('crash:CompileError');
    expect(text).not.toContain('@');
    expect(text).not.toContain('[');
  });

  // A work order the run limit refused has no run and no step to read a
  // signature off, so the server labels it outright — and the tip has to be
  // there, or the row reads as a bug in the page.
  test('names a rejected work order and tips it', () => {
    render(
      <TriageTable
        signatures={[
          signature({
            exit_reason: 'rejected',
            error_type: 'RunLimitExceeded',
            step_name: null,
            adaptor: null,
          }),
        ]}
        emptyMessage="No failures"
      />
    );

    expect(rowText(/RunLimitExceeded/)).toContain('rejected:RunLimitExceeded');
    expect(
      screen.getByText(
        'The project was over its run limit, so no run was created for this payload.'
      )
    ).toBeVisible();
  });

  test('shows the tip written for the error type', () => {
    render(
      <TriageTable
        signatures={[signature({ error_type: 'OOMError' })]}
        emptyMessage="No failures"
      />
    );

    expect(
      screen.getByText(
        "The run used more memory than it's allowed and was stopped."
      )
    ).toBeVisible();
  });

  // Raw JS error names reach Lightning through some paths, and a step can
  // finish without reporting a type at all — neither may render a blank tip.
  test('falls back to the default tip for an unmapped or missing type', () => {
    render(
      <TriageTable
        signatures={[
          signature({ error_type: 'TypeError' }),
          signature({ error_type: null, step_name: 'Verify-cedula' }),
        ]}
        emptyMessage="No failures"
      />
    );

    const fallback =
      'The step failed without a recognised error type; check its logs.';

    expect(screen.getAllByText(fallback)).toHaveLength(2);
    expect(rowText(/unknown/)).toContain('fail:unknown @ Verify-cedula');
  });

  // A worker can report the type as an empty string rather than omitting it.
  // `??` let that through, rendering the signature as a bare `fail:` and a
  // "Tip: " with no sentence after it.
  test('treats an empty error type as a missing one', () => {
    render(
      <TriageTable
        signatures={[signature({ error_type: '' })]}
        emptyMessage="No failures"
      />
    );

    expect(rowText(/unknown/)).toContain('fail:unknown @ Map-beneficiary');
    expect(
      screen.getByText(
        'The step failed without a recognised error type; check its logs.'
      )
    ).toBeVisible();
  });

  test('shows the empty message when nothing failed', () => {
    render(
      <TriageTable
        signatures={[]}
        emptyMessage="No failures in the last 30 days"
      />
    );

    expect(screen.getByText('No failures in the last 30 days')).toBeVisible();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });
});
