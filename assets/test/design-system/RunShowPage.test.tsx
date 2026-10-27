import { act, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
  RunShowPage,
  type Props,
} from '../../js/design-system/pages/RunShowPage';

import { renderIsland } from './renderIsland';

// Monaco doesn't run in jsdom: the design system's plain-text stand-in, and a
// loader for Lightning's setup in js/monaco to configure.
vi.mock('@monaco-editor/react', async () => ({
  ...(await import('../../node_modules/@openfn/ui/src/test/monaco')),
  loader: { config: () => {} },
}));

const RUN_ID = '5e9a1c2b-1111-4a4a-8b8b-0123456789ab';

const props: Props = {
  project: { id: 'p1', parentId: null, color: null },
  projectLabel: 'Malawi HIV',
  runId: RUN_ID,
  loading: false,
  run: {
    id: RUN_ID,
    workOrderId: '7c1d2e3f-2222-4a4a-8b8b-0123456789ab',
    state: 'started',
    startedBy: 'Webhook trigger',
    insertedAt: '2026-10-14T09:30:00Z',
    startedAt: '2026-10-14T09:30:01Z',
    finishedAt: null,
    finalDataclipId: null,
    snapshot: {
      id: 'abcdef1234',
      lockVersion: 1,
      insertedAt: '2026-10-13T08:00:00Z',
    },
  },
  workflow: { id: 'wf-1', name: 'Register patients', lockVersion: 1 },
  steps: [],
  selectedStepId: null,
  inputDataclip: null,
  outputDataclip: null,
  logLevel: 'info',
  experimentalFeatures: false,
  canRunWorkflow: true,
  canEditDataRetention: true,
  adminContacts: [],
};

describe('RunShowPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    window.location.hash = '';
  });

  test('draws the run from data-props and shows the log lines the LiveView pushes', () => {
    const { handleEvent } = renderIsland<Props>(RunShowPage, props);
    expect(
      document.getElementById(`run-detail-${RUN_ID}`)!.textContent
    ).toContain('Register patients');
    expect(screen.getByText('Nothing yet')).toBeTruthy();

    const line = (id: string, timestamp: string, message: string) => ({
      id,
      source: 'R/T',
      level: 'info',
      message,
      timestamp,
      step_id: null,
    });
    const handlers = Object.fromEntries(handleEvent.mock.calls);
    const push = handlers[`logs-${RUN_ID}`];
    expect(push).toBeDefined();
    act(() => {
      push?.({ logs: [line('b', '2026-10-14T09:30:02Z', 'second')] });
      push?.({
        logs: [
          line('a', '2026-10-14T09:30:01Z', 'first'),
          line('b', '2026-10-14T09:30:02Z', 'second'),
        ],
      });
    });
    const text = document.body.textContent!;
    expect(text.indexOf('first')).toBeLessThan(text.indexOf('second'));
    expect(text.match(/second/g)).toHaveLength(1);
  });

  test('shows why a step input could not be loaded, with nothing to copy', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve(new Response('', { status: 500 })))
    );
    window.location.hash = '#input';
    renderIsland<Props>(RunShowPage, {
      ...props,
      steps: [
        {
          id: 'step-a',
          jobId: 'job-a',
          jobName: 'Map to FHIR',
          exitReason: 'success',
          startedAt: '2026-10-14T09:30:01Z',
          finishedAt: '2026-10-14T09:30:02Z',
          insertedAt: '2026-10-14T09:30:01Z',
          inputDataclipId: 'dc-in',
          outputDataclipId: null,
          snapshotLockVersion: 1,
        },
      ],
      selectedStepId: 'step-a',
      inputDataclip: { id: 'dc-in', wiped: false },
    });
    await waitFor(() =>
      expect(screen.getByText('Failed to load content')).toBeTruthy()
    );
    expect(
      screen.queryByRole('button', { name: 'Copy to clipboard' })
    ).toBeNull();
  });
});
