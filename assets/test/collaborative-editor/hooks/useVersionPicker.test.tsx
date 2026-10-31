import { renderHook } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { useVersionPicker } from '../../../js/collaborative-editor/hooks/useVersionPicker';

let experimentalFeatures = true;
let project: { is_sandbox?: boolean } | null = { is_sandbox: false };
let workflow: { state?: 'draft' | 'live' } | null = { state: 'live' };

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useSessionContextError: () => null,
  useSessionContextLoaded: () => true,
  useRequestVersions: () => vi.fn(),
  useVersionsError: () => null,
  useVersionsLoading: () => false,
  useVersionsLoaded: () => true,
  useContentLocked: () => false,
  useVersions: () => [],
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
    project = null;
    workflow = null;

    expect(picker()).toBe('snapshots');
  });
});
