import { act, renderHook, waitFor } from '@testing-library/react';
import type React from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import type { StoreContextValue } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../js/collaborative-editor/contexts/StoreProvider';
import { SessionContext } from '../../../js/collaborative-editor/contexts/SessionProvider';
import {
  useRunRetry,
  type UseRunRetryOptions,
} from '../../../js/collaborative-editor/hooks/useRunRetry';
import type { Dataclip } from '../../../js/collaborative-editor/api/dataclips';
import * as dataclipApi from '../../../js/collaborative-editor/api/dataclips';
import { createSessionStore } from '../../../js/collaborative-editor/stores/createSessionStore';
import type {
  RunDetail,
  StepDetail,
} from '../../../js/collaborative-editor/types/history';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../mocks/phoenixChannel';
import { createMockSocket } from '../mocks/phoenixSocket';

// Mock the dataclip API module
vi.mock('../../../js/collaborative-editor/api/dataclips', () => ({
  submitManualRun: vi.fn(),
  searchDataclips: vi.fn(),
  updateDataclipName: vi.fn(),
  getRunDataclip: vi.fn(),
}));

// Mock the notifications module
vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: {
    success: vi.fn(),
    alert: vi.fn(),
  },
}));

// Mock CSRF token
vi.mock('../../../js/collaborative-editor/lib/csrf', () => ({
  getCsrfToken: () => 'mock-csrf-token',
}));

// Create a global variable to control URL state mocking
let mockParams: Record<string, string> = {};

// Mock URL state hook
vi.mock('../../../js/react/lib/use-url-state', () => ({
  useURLState: () => ({
    params: mockParams,
    updateSearchParams: vi.fn(),
  }),
}));

// Global variable to control active run in tests
let mockActiveRun: RunDetail | null = null;

/**
 * Helper to set the active run in tests
 */
function setMockActiveRun(run: RunDetail | null) {
  mockActiveRun = run;
}

/**
 * Creates a React wrapper with store providers for hook testing
 */
function createWrapper(): React.ComponentType<{ children: React.ReactNode }> {
  // Create session store and initialize it
  const sessionStore = createSessionStore();
  const mockSocket = createMockSocket();
  sessionStore.initializeSession(mockSocket, 'test:room', {
    id: 'user-1',
    name: 'Test User',
    email: 'test@example.com',
    color: '#ff0000',
  });

  // Create a mock history store with the methods useActiveRun needs
  const mockHistoryStore = {
    subscribe: vi.fn(() => vi.fn()),
    withSelector: vi.fn(
      selector => () => selector({ activeRun: mockActiveRun })
    ),
  };

  const mockStoreValue: StoreContextValue = {
    workflowStore: {} as any,
    sessionContextStore: {} as any,
    adaptorStore: {} as any,
    credentialStore: {} as any,
    awarenessStore: {} as any,
    historyStore: mockHistoryStore as any,
    uiStore: {} as any,
    editorPreferencesStore: {} as any,
  };

  return ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={mockStoreValue}>
        {children}
      </StoreContext.Provider>
    </SessionContext.Provider>
  );
}

/**
 * Creates mock options for useRunRetry hook
 */
function createMockOptions(
  overrides?: Partial<UseRunRetryOptions>
): UseRunRetryOptions {
  return {
    projectId: 'project-123',
    workflowId: 'workflow-456',
    runContext: { type: 'job', id: 'job-789' },
    selectedTab: 'empty',
    selectedDataclip: null,
    customBody: '{}',
    canRunWorkflow: true,
    workflowRunTooltipMessage: '',
    saveWorkflow: vi.fn().mockResolvedValue({}),
    onRunSubmitted: vi.fn(),
    edgeId: null,
    ...overrides,
  };
}

/**
 * Creates a mock dataclip
 */
function createMockDataclip(overrides?: Partial<Dataclip>): Dataclip {
  return {
    id: 'dataclip-123',
    type: 'saved_input',
    body: { foo: 'bar' },
    inserted_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
    wiped_at: null,
    step_id: null,
    project_id: 'project-123',
    name: null,
    ...overrides,
  };
}

/**
 * Creates a mock run
 */
function createMockRun(overrides?: Partial<RunDetail>): RunDetail {
  return {
    id: 'run-123',
    work_order_id: 'wo-123',
    work_order: {
      id: 'wo-123',
      workflow_id: 'wf-123',
    },
    state: 'success',
    created_by: null,
    starting_trigger: null,
    started_at: '2024-01-01T00:00:00Z',
    finished_at: '2024-01-01T00:01:00Z',
    steps: [],
    ...overrides,
  };
}

/**
 * Creates a mock step
 */
function createMockStep(overrides?: Partial<StepDetail>): StepDetail {
  return {
    id: 'step-123',
    job_id: 'job-789',
    job: { name: 'Job 1' },
    exit_reason: 'success',
    error_type: null,
    started_at: '2024-01-01T00:00:00Z',
    finished_at: '2024-01-01T00:01:00Z',
    input_dataclip_id: 'dataclip-123',
    output_dataclip_id: 'dataclip-456',
    inserted_at: '2024-01-01T00:00:00Z',
    ...overrides,
  };
}

describe('useRunRetry - Basic Functionality', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockActiveRun = null;
  });

  test('initializes with correct default state', () => {
    const options = createMockOptions();
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.isSubmitting).toBe(false);
    expect(result.current.isRetryable).toBe(false);
    expect(result.current.runIsProcessing).toBe(false);
    expect(result.current.canRun).toBe(true);
  });

  test('canRun is false when edge is selected', () => {
    const options = createMockOptions({ edgeId: 'edge-123' });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test('canRun is false when workflow cannot be run', () => {
    const options = createMockOptions({ canRunWorkflow: false });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false when on 'existing' tab without selected dataclip", () => {
    const options = createMockOptions({
      selectedTab: 'existing',
      selectedDataclip: null,
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is true when on 'existing' tab with selected dataclip", () => {
    const options = createMockOptions({
      selectedTab: 'existing',
      selectedDataclip: createMockDataclip(),
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(true);
  });

  test("canRun is true for 'empty' tab", () => {
    const options = createMockOptions({ selectedTab: 'empty' });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(true);
  });

  test("canRun is true for 'custom' tab with valid JSON", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '{"valid": "json"}',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(true);
  });

  test("canRun is false for 'custom' tab with empty body", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with whitespace-only body", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '   ',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with invalid JSON", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '{ invalid json }',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with JSON array (must be object)", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '["array", "not", "object"]',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with JSON null (must be object)", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: 'null',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with JSON string (must be object)", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '"string value"',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });

  test("canRun is false for 'custom' tab with JSON number (must be object)", () => {
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '123',
    });
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.canRun).toBe(false);
  });
});

describe('useRunRetry - Retry Detection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockActiveRun = null;

    // Set URL state to include run parameter
    mockParams = { run: 'run-123' };
  });

  test('isRetryable is false when no run is followed', () => {
    const options = createMockOptions();
    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.isRetryable).toBe(false);
  });

  test('isRetryable is true when following run with matching dataclip', async () => {
    const dataclip = createMockDataclip({ id: 'dataclip-123' });
    const step = createMockStep({
      job_id: 'job-789',
      input_dataclip_id: 'dataclip-123',
    });
    const run = createMockRun({ id: 'run-123', steps: [step] });

    const options = createMockOptions({
      selectedDataclip: dataclip,
      runContext: { type: 'job', id: 'job-789' },
    });

    act(() => {
      setMockActiveRun(run);
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    // Wait for the hook to process the run from store
    await waitFor(() => {
      expect(result.current.isRetryable).toBe(true);
    });
  });

  test('isRetryable is false when dataclip does not match step input', () => {
    const dataclip = createMockDataclip({ id: 'dataclip-999' });
    const step = createMockStep({
      job_id: 'job-789',
      input_dataclip_id: 'dataclip-123',
    });
    const run = createMockRun({ id: 'run-123', steps: [step] });

    const options = createMockOptions({
      selectedDataclip: dataclip,
      runContext: { type: 'job', id: 'job-789' },
    });

    act(() => {
      setMockActiveRun(run);
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.isRetryable).toBe(false);
  });

  test('isRetryable is false when dataclip is wiped', () => {
    const dataclip = createMockDataclip({
      id: 'dataclip-123',
      wiped_at: '2024-01-01T00:00:00Z',
    });
    const step = createMockStep({
      job_id: 'job-789',
      input_dataclip_id: 'dataclip-123',
    });
    const run = createMockRun({ id: 'run-123', steps: [step] });

    const options = createMockOptions({
      selectedDataclip: dataclip,
      runContext: { type: 'job', id: 'job-789' },
    });

    act(() => {
      setMockActiveRun(run);
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.isRetryable).toBe(false);
  });

  test('runIsProcessing is true when run is in non-final state', async () => {
    const run = createMockRun({ state: 'started' });

    // Set run in store BEFORE rendering hook
    act(() => {
      setMockActiveRun(run);
    });

    const options = createMockOptions();

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    // Wait for the hook to process the run from store
    await waitFor(() => {
      expect(result.current.runIsProcessing).toBe(true);
    });
  });

  test('runIsProcessing is false when run is in final state', () => {
    const run = createMockRun({ state: 'success' });
    const options = createMockOptions();

    act(() => {
      setMockActiveRun(run);
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    expect(result.current.runIsProcessing).toBe(false);
  });
});

describe('useRunRetry - handleRun', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockActiveRun = null;
  });

  test('submits run with empty input', async () => {
    const mockResponse = { data: { run_id: 'run-456' } };
    vi.mocked(dataclipApi.submitManualRun).mockResolvedValue(
      mockResponse as any
    );

    const saveWorkflow = vi.fn().mockResolvedValue({});
    const onRunSubmitted = vi.fn();
    const options = createMockOptions({
      selectedTab: 'empty',
      saveWorkflow,
      onRunSubmitted,
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    await act(async () => {
      await result.current.handleRun();
    });

    expect(saveWorkflow).toHaveBeenCalledWith({ silent: true });
    expect(dataclipApi.submitManualRun).toHaveBeenCalledWith({
      workflowId: 'workflow-456',
      projectId: 'project-123',
      jobId: 'job-789',
    });
    expect(onRunSubmitted).toHaveBeenCalledWith('run-456', undefined);
  });

  test('submits run with existing dataclip', async () => {
    const dataclip = createMockDataclip({ id: 'dataclip-123' });
    const mockResponse = { data: { run_id: 'run-456' } };
    vi.mocked(dataclipApi.submitManualRun).mockResolvedValue(
      mockResponse as any
    );

    const saveWorkflow = vi.fn().mockResolvedValue({});
    const onRunSubmitted = vi.fn();
    const options = createMockOptions({
      selectedTab: 'existing',
      selectedDataclip: dataclip,
      saveWorkflow,
      onRunSubmitted,
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    await act(async () => {
      await result.current.handleRun();
    });

    expect(dataclipApi.submitManualRun).toHaveBeenCalledWith({
      workflowId: 'workflow-456',
      projectId: 'project-123',
      jobId: 'job-789',
      dataclipId: 'dataclip-123',
    });
    expect(onRunSubmitted).toHaveBeenCalledWith('run-456', undefined);
  });

  test('submits run with custom body and receives created dataclip', async () => {
    const createdDataclip = createMockDataclip({
      id: 'dataclip-new',
      name: null,
      type: 'saved_input',
    });
    const mockResponse = {
      data: { run_id: 'run-456', dataclip: createdDataclip },
    };
    vi.mocked(dataclipApi.submitManualRun).mockResolvedValue(
      mockResponse as any
    );

    const saveWorkflow = vi.fn().mockResolvedValue({});
    const onRunSubmitted = vi.fn();
    const options = createMockOptions({
      selectedTab: 'custom',
      customBody: '{"custom": "data"}',
      saveWorkflow,
      onRunSubmitted,
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    await act(async () => {
      await result.current.handleRun();
    });

    expect(dataclipApi.submitManualRun).toHaveBeenCalledWith({
      workflowId: 'workflow-456',
      projectId: 'project-123',
      jobId: 'job-789',
      customBody: '{"custom": "data"}',
    });
    expect(onRunSubmitted).toHaveBeenCalledWith('run-456', createdDataclip);
  });

  test('submits run from trigger context', async () => {
    const mockResponse = { data: { run_id: 'run-456' } };
    vi.mocked(dataclipApi.submitManualRun).mockResolvedValue(
      mockResponse as any
    );

    const saveWorkflow = vi.fn().mockResolvedValue({});
    const onRunSubmitted = vi.fn();
    const options = createMockOptions({
      runContext: { type: 'trigger', id: 'trigger-123' },
      saveWorkflow,
      onRunSubmitted,
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    await act(async () => {
      await result.current.handleRun();
    });

    expect(dataclipApi.submitManualRun).toHaveBeenCalledWith({
      workflowId: 'workflow-456',
      projectId: 'project-123',
      triggerId: 'trigger-123',
    });
    expect(onRunSubmitted).toHaveBeenCalledWith('run-456', undefined);
  });
});

describe('useRunRetry - handleRetry', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockActiveRun = null;

    // Set URL state to include run parameter
    mockParams = { run: 'run-123' };

    // Mock global fetch for retry endpoint
    global.fetch = vi.fn();
  });

  test('submits retry request with correct parameters', async () => {
    const dataclip = createMockDataclip({ id: 'dataclip-123' });
    const step = createMockStep({
      id: 'step-123',
      job_id: 'job-789',
      input_dataclip_id: 'dataclip-123',
    });
    const run = createMockRun({ id: 'run-123', steps: [step] });

    const saveWorkflow = vi.fn().mockResolvedValue({});
    const onRunSubmitted = vi.fn();
    const options = createMockOptions({
      selectedDataclip: dataclip,
      runContext: { type: 'job', id: 'job-789' },
      saveWorkflow,
      onRunSubmitted,
    });

    vi.mocked(fetch).mockResolvedValue({
      ok: true,
      json: async () => ({ data: { run_id: 'run-456' } }),
    } as Response);

    act(() => {
      setMockActiveRun(run);
    });

    const { result } = renderHook(() => useRunRetry(options), {
      wrapper: createWrapper(),
    });

    await act(async () => {
      await result.current.handleRetry();
    });

    expect(saveWorkflow).toHaveBeenCalledWith({ silent: true });
    expect(fetch).toHaveBeenCalledWith(
      '/projects/project-123/runs/run-123/retry',
      {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': 'mock-csrf-token',
        },
        body: JSON.stringify({ step_id: 'step-123' }),
      }
    );
    expect(onRunSubmitted).toHaveBeenCalledWith('run-456');
  });
});
