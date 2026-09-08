import { render, screen, within } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { TriageTable } from '#/health/charts/TriageTable';
import type { FailureSignature } from '#/health/types';

const signature = (
  overrides: Partial<FailureSignature> = {}
): FailureSignature => ({
  count: 62,
  exit_reason: 'fail',
  error_type: 'RuntimeError',
  job_id: 'a1b2c3d4-0000-0000-0000-000000000000',
  step_name: 'Map-beneficiary',
  adaptor: '@openfn/language-common@2.0.0',
  ...overrides,
});

const rowText = (name: string | RegExp) =>
  within(screen.getByRole('row', { name })).getByRole('cell', { name })
    .textContent;

// Every test renders the same workflow at the same window, since only the
// signature varies between them.
const table = (signatures: FailureSignature[], emptyMessage = 'No failures') =>
  render(
    <TriageTable
      signatures={signatures}
      emptyMessage={emptyMessage}
      projectId="proj-1"
      workflowId="wf-1"
      from="2026-08-01T10:00:00Z"
    />
  );

describe('TriageTable', () => {
  test('renders the full signature grammar for a step-level failure, adaptor version dropped', () => {
    table([signature()]);

    expect(rowText(/RuntimeError/)).toContain(
      'fail:RuntimeError @ Map-beneficiary [@openfn/language-common]'
    );
    expect(screen.getByRole('cell', { name: '62' })).toBeVisible();
    expect(
      screen.getByRole('columnheader', { name: 'Work orders' })
    ).toBeVisible();
  });

  // A run that crashed before any step has no job to name, so the grammar's
  // optional clause drops rather than rendering an empty ` @  []`.
  test('drops the step clause when nothing reached a step', () => {
    table([
      signature({
        exit_reason: 'crash',
        error_type: 'CompileError',
        job_id: null,
        step_name: null,
        adaptor: null,
      }),
    ]);

    const text = rowText(/CompileError/);
    expect(text).toContain('crash:CompileError');
    expect(text).not.toContain('@');
    expect(text).not.toContain('[');
  });

  // A work order the run limit refused has no run and no step to read a
  // signature off, so the server labels it outright — and the tip has to be
  // there, or the row reads as a bug in the page.
  test('names a rejected work order and tips it', () => {
    table([
      signature({
        exit_reason: 'rejected',
        error_type: 'RunLimitExceeded',
        job_id: null,
        step_name: null,
        adaptor: null,
      }),
    ]);

    expect(rowText(/RunLimitExceeded/)).toContain('rejected:RunLimitExceeded');
    expect(
      screen.getByText(
        'The project was over its run limit, so no run was created for this request.'
      )
    ).toBeVisible();
  });

  test('shows the tip written for the error type', () => {
    table([signature({ error_type: 'OOMError' })]);

    expect(
      screen.getByText(
        "The run used more memory than it's allowed and was stopped."
      )
    ).toBeVisible();
  });

  // A crashing step reports these, never `RuntimeCrash` — see TIPS. Untipped,
  // the most common crash there is falls through to "no recognised error type".
  test('tips the raw JS names that reach Lightning in place of RuntimeCrash', () => {
    table([
      signature({ exit_reason: 'crash', error_type: 'ReferenceError' }),
      signature({ exit_reason: 'crash', error_type: 'SyntaxError' }),
    ]);

    expect(screen.getByText(/often a typo or a missing import/)).toBeVisible();
    expect(screen.getByText(/wasn't in the format it expected/)).toBeVisible();
  });

  // `error_type` is not a closed enum — it is whatever name the throwing layer
  // set — and a step can finish without reporting one at all. Neither may
  // render a blank tip.
  test('falls back to the default tip for an unmapped or missing type', () => {
    table([
      signature({ error_type: 'SomeUnmappedError' }),
      signature({ error_type: null, step_name: 'Verify-cedula' }),
    ]);

    const fallback =
      'The step failed without a recognised error type; check its logs.';

    expect(screen.getAllByText(fallback)).toHaveLength(2);
    expect(rowText(/unknown/)).toContain('fail:unknown @ Verify-cedula');
  });

  // A worker can report the type as an empty string rather than omitting it.
  // `??` let that through, rendering the signature as a bare `fail:` and a
  // "Tip: " with no sentence after it.
  test('treats an empty error type as a missing one', () => {
    table([signature({ error_type: '' })]);

    expect(rowText(/unknown/)).toContain('fail:unknown @ Map-beneficiary');
    expect(
      screen.getByText(
        'The step failed without a recognised error type; check its logs.'
      )
    ).toBeVisible();
  });

  test('shows the empty message when nothing failed', () => {
    table([], 'No failures in the last 30 days');

    expect(screen.getByText('No failures in the last 30 days')).toBeVisible();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });

  describe('View button', () => {
    // The normal case: a step-level row, keyed and filtered on job_id.
    test('links a normal row to history filtered on the signature', () => {
      table([signature()]);

      const link = screen.getByRole('link', { name: 'View' });
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-1/history' +
          '?filters%5Bworkflow_id%5D=wf-1' +
          '&filters%5Bdate_after%5D=2026-08-01T10%3A00%3A00Z' +
          '&filters%5Bexit_reason%5D=fail' +
          '&filters%5Berror_type%5D=RuntimeError' +
          '&filters%5Bjob_id%5D=a1b2c3d4-0000-0000-0000-000000000000'
      );
    });

    // A run that crashed before reaching a step has no job to key on, so the
    // filter must omit job_id — matching the filter's own reading of an
    // absent job_id as "the run-level row" rather than matching nothing.
    test('omits job_id and error_type for a row with no step', () => {
      table([
        signature({
          exit_reason: 'crash',
          error_type: null,
          job_id: null,
          step_name: null,
          adaptor: null,
        }),
      ]);

      const link = screen.getByRole('link', { name: 'View' });
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-1/history' +
          '?filters%5Bworkflow_id%5D=wf-1' +
          '&filters%5Bdate_after%5D=2026-08-01T10%3A00%3A00Z' +
          '&filters%5Bexit_reason%5D=crash'
      );
    });

    // A rejected row has no run to key a signature filter on — that filter
    // fails closed server-side — so it links to history's own `rejected`
    // status filter instead, not to the signature's own fields.
    test('links a rejected row to the rejected status filter, not the signature', () => {
      table([
        signature({
          exit_reason: 'rejected',
          error_type: 'RunLimitExceeded',
          job_id: null,
          step_name: null,
          adaptor: null,
        }),
      ]);

      const link = screen.getByRole('link', { name: 'View' });
      expect(link).toHaveAttribute(
        'href',
        '/projects/proj-1/history' +
          '?filters%5Bworkflow_id%5D=wf-1' +
          '&filters%5Bdate_after%5D=2026-08-01T10%3A00%3A00Z' +
          '&filters%5Brejected%5D=true'
      );
      expect(link.getAttribute('href')).not.toContain('error_type');
      expect(link.getAttribute('href')).not.toContain('exit_reason');
    });

    // Nothing to filter history on without a resolved exit_reason.
    test('renders no button when exit_reason never resolved', () => {
      table([signature({ exit_reason: '' })]);

      expect(screen.queryByRole('link', { name: 'View' })).toBeNull();
    });
  });
});
