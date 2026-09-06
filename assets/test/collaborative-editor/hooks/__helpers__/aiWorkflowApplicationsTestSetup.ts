/**
 * Shared test setup for the useAIWorkflowApplications.* split test files.
 *
 * A handful of the scenario files (workflow, workflowAutoSave,
 * workflowOfflineGate, workflowStreamingApplyDedup,
 * workflowStreamingApplyRecording, workflowStreamingApplyStale) exercise the
 * same YAML-apply code path and therefore need byte-for-byte identical
 * `../../../js/yaml/util` / notifications mocks and the same set of mock
 * functions (`mockImportWorkflow`, `mockWorkflowActions`,
 * `createMockMonacoRef`, `createMockAIMode`, `createMockJob`, ...).
 *
 * `vi.mock()` calls are hoisted above imports, so this module cannot call
 * `vi.mock()` itself on a consuming file's behalf. Instead it exports the
 * plain factory functions (the object literals normally passed as the
 * second argument to `vi.mock`); each test file still declares its own
 * top-level `vi.mock('module', () => factory())` call using the imported
 * factory. This keeps hoisting semantics correct while eliminating the
 * duplication of the mock *implementations*.
 *
 * Other files in the split (autoApply, globalStep, jobCode) have
 * meaningfully different mocks (different YAML fixtures, different
 * notification methods mocked, or no yaml/util mock at all) and
 * intentionally do not use this helper.
 */

import { vi } from 'vitest';

import type { MonacoHandle } from '../../../../js/collaborative-editor/components/CollaborativeMonaco';
import type { AIModeResult } from '../../../../js/collaborative-editor/hooks/useAIMode';
import type { Job } from '../../../../js/collaborative-editor/types';

/**
 * Factory for `vi.mock('../../../js/yaml/util', () => aiWorkflowApplicationsYamlUtilMock())`.
 *
 * Parses a fixed set of well-known YAML fixtures used across the shared
 * scenario tests: an "invalid" marker throws, an "object-id" marker
 * returns an invalid (object) job id, everything else returns a single
 * valid job.
 */
export function aiWorkflowApplicationsYamlUtilMock() {
  return {
    parseWorkflowYAML: vi.fn((yaml: string) => {
      if (yaml.includes('invalid')) {
        throw new Error('Invalid YAML syntax');
      }
      if (yaml.includes('object-id')) {
        return {
          jobs: {
            'job-1': {
              id: { invalid: 'object' }, // Object ID (invalid)
              name: 'Job 1',
            },
          },
        };
      }
      return {
        name: 'Test Workflow',
        jobs: {
          'job-1': {
            id: 'job-1',
            name: 'Job 1',
            body: 'console.log("test");',
          },
        },
        triggers: {},
        edges: [],
      };
    }),
    convertWorkflowSpecToState: vi.fn(
      (spec: {
        name: string;
        jobs: Record<string, unknown>;
        triggers?: Record<string, unknown>;
        edges?: unknown[];
      }) => ({
        name: spec.name,
        jobs: spec.jobs,
        triggers: spec.triggers || {},
        edges: spec.edges || [],
      })
    ),
    applyJobCredsToWorkflowState: vi.fn((state: unknown, _creds: unknown) => ({
      ...(state as Record<string, unknown>),
      _credentialsApplied: true,
    })),
    extractJobCredentials: vi.fn((jobs: Job[]) =>
      jobs.reduce(
        (acc: Record<string, string>, job: Job & { credential?: string }) => {
          if (job.credential) {
            acc[job.id] = job.credential;
          }
          return acc;
        },
        {} as Record<string, string>
      )
    ),
  };
}

/**
 * Factory for `vi.mock('.../lib/notifications', () => aiWorkflowApplicationsNotificationsMock())`.
 */
export function aiWorkflowApplicationsNotificationsMock() {
  return {
    notifications: {
      alert: vi.fn(),
      success: vi.fn(),
      dismiss: vi.fn(),
    },
  };
}

/**
 * Creates the shared set of mock functions/factories used by the
 * workflow-apply scenario tests. Call once per describe block (mirroring
 * the previous per-file `const mock... = vi.fn()` declarations) and reset
 * call history with `vi.clearAllMocks()` in `beforeEach`.
 */
export function createAIWorkflowApplicationsMocks() {
  const mockImportWorkflow = vi.fn(() => Promise.resolve());
  const mockStartApplyingWorkflow = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingWorkflow = vi.fn(() => Promise.resolve());
  const mockStartApplyingJobCode = vi.fn(() => Promise.resolve(true));
  const mockDoneApplyingJobCode = vi.fn(() => Promise.resolve());
  const mockUpdateJob = vi.fn();
  const mockSetPreviewingMessageId = vi.fn();
  const mockSetApplyingMessageId = vi.fn();
  const mockClearDiff = vi.fn();
  const mockShowDiff = vi.fn();

  const mockSaveWorkflow = vi.fn(() => Promise.resolve());

  const mockStreamingApplyActions = {
    set: vi.fn(),
    setSaveFailed: vi.fn(),
    clear: vi.fn(),
  };

  const mockWorkflowActions = {
    importWorkflow: mockImportWorkflow,
    startApplyingWorkflow: mockStartApplyingWorkflow,
    doneApplyingWorkflow: mockDoneApplyingWorkflow,
    startApplyingJobCode: mockStartApplyingJobCode,
    doneApplyingJobCode: mockDoneApplyingJobCode,
    updateJob: mockUpdateJob,
    saveWorkflow: mockSaveWorkflow,
  };

  const createMockMonacoRef = () => ({
    current: {
      clearDiff: mockClearDiff,
      showDiff: mockShowDiff,
    } as MonacoHandle,
  });

  const createMockAIMode = (
    mode: 'workflow_template' | 'job_code',
    context: Record<string, unknown> = {}
  ): AIModeResult => ({
    mode: 'workflow_template',
    page: mode,
    context,
    storageKey: `ai-${mode}`,
  });

  const createMockJob = (overrides: Partial<Job> = {}): Job => ({
    id: 'job-1',
    name: 'Test Job',
    body: 'console.log("old code");',
    adaptor: '@openfn/language-http@latest',
    enabled: true,
    ...overrides,
  });

  return {
    mockImportWorkflow,
    mockStartApplyingWorkflow,
    mockDoneApplyingWorkflow,
    mockStartApplyingJobCode,
    mockDoneApplyingJobCode,
    mockUpdateJob,
    mockSetPreviewingMessageId,
    mockSetApplyingMessageId,
    mockClearDiff,
    mockShowDiff,
    mockSaveWorkflow,
    mockStreamingApplyActions,
    mockWorkflowActions,
    createMockMonacoRef,
    createMockAIMode,
    createMockJob,
  };
}
