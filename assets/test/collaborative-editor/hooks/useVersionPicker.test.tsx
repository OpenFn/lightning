/**
 * useVersionPicker
 *
 * Decides which version list the editor shows. Publishing means production, so
 * the publish trail only appears where a workflow can publish: live, outside a
 * sandbox, for someone who opted into the lifecycle. Everywhere else browses
 * saves, which is the list the editor has always had.
 */
import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useVersionPicker } from '../../../js/collaborative-editor/hooks/useVersionPicker';

let experimentalFeatures = true;
let project: { is_sandbox?: boolean } | null = { is_sandbox: false };
let workflow: { state?: 'draft' | 'live' } | null = { state: 'live' };

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useExperimentalFeatures: () => experimentalFeatures,
  useProject: () => project,
  useSessionWorkflow: () => workflow,
}));

const picker = () => renderHook(() => useVersionPicker()).result.current;

describe('useVersionPicker', () => {
  beforeEach(() => {
    experimentalFeatures = true;
    project = { is_sandbox: false };
    workflow = { state: 'live' };
  });

  test('a live workflow in an ordinary project shows its publishes', () => {
    expect(picker()).toBe('releases');
  });

  test('a draft shows its saves, because it has published nothing', () => {
    workflow = { state: 'draft' };

    expect(picker()).toBe('snapshots');
  });

  test('a sandbox shows its saves even when the workflow is live there', () => {
    // Turning a workflow on inside a sandbox records a release, but nothing in
    // a sandbox reaches production, so calling that a publish would mean
    // something it does not.
    project = { is_sandbox: true };

    expect(picker()).toBe('snapshots');
  });

  test('without experimental features it is always saves', () => {
    experimentalFeatures = false;

    expect(picker()).toBe('snapshots');
  });

  test('an older server that sends no sandbox flag reads as not a sandbox', () => {
    project = {};

    expect(picker()).toBe('releases');
  });

  test('a context that has not loaded yet shows saves', () => {
    // The safe answer while nothing is known: the list the editor has always
    // had, rather than a publish trail that may not apply.
    project = null;
    workflow = null;

    expect(picker()).toBe('snapshots');
  });
});
