import { describe, it, expect } from 'vitest';

import type { RunStepsData } from '#/collaborative-editor/types/history';

import {
  transformToRunInfo,
  createEmptyRunInfo,
} from '#/collaborative-editor/utils/runStepsTransformer';

describe('runStepsTransformer', () => {
  describe('transformToRunInfo', () => {
    it('transforms backend step data to RunInfo format', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-01T10:00:00Z',
            finished_at: '2025-01-01T10:01:00Z',
            input_dataclip_id: 'clip-1',
          },
          {
            id: 'step-2',
            job_id: 'job-2',
            exit_reason: 'fail',
            error_type: 'RuntimeError',
            started_at: '2025-01-01T10:01:00Z',
            finished_at: '2025-01-01T10:02:00Z',
            input_dataclip_id: 'clip-2',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'demo@openfn.org',
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      expect(result.steps).toHaveLength(2);
      expect(result.start_from).toBe('job-1');
      expect(result.inserted_at).toBe('2025-01-01T10:00:00Z');
      expect(result.run_by).toBe('demo@openfn.org');
      expect(result.isTrigger).toBe(false);

      const [step1, step2] = result.steps;
      expect(step1?.exit_reason).toBe('success');
      expect(step1?.startNode).toBe(true);
      expect(step1?.startBy).toBe('demo@openfn.org');
      expect(step2?.exit_reason).toBe('fail');
      expect(step2?.error_type).toBe('RuntimeError');
      expect(step2?.startNode).toBe(false);
    });

    it('handles trigger-initiated runs', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-01T10:00:00Z',
            finished_at: '2025-01-01T10:01:00Z',
            input_dataclip_id: 'clip-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: 'trigger-1',
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: null,
          created_by_email: null,
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      expect(result.isTrigger).toBe(true);
      expect(result.run_by).toBe(null);

      const [step1] = result.steps;
      expect(step1?.startBy).toBe('unknown');
    });

    it('handles in-progress steps with null exit_reason', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: null, // Still running
            error_type: null,
            started_at: '2025-01-01T10:00:00Z',
            finished_at: null,
            input_dataclip_id: 'clip-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'demo@openfn.org',
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      const [step1] = result.steps;
      expect(step1?.exit_reason).toBe(null);
      expect(step1?.finished_at).toBe('');
    });

    it('maps crash/exception/lost to crash exit_reason', () => {
      const testCases = ['crash', 'exception', 'lost'];

      testCases.forEach(exitReason => {
        const backendData: RunStepsData = {
          run_id: 'run-123',
          steps: [
            {
              id: 'step-1',
              job_id: 'job-1',
              exit_reason: exitReason,
              error_type: 'Error',
              started_at: '2025-01-01T10:00:00Z',
              finished_at: '2025-01-01T10:01:00Z',
              input_dataclip_id: 'clip-1',
            },
          ],
          metadata: {
            starting_job_id: 'job-1',
            starting_trigger_id: null,
            inserted_at: '2025-01-01T10:00:00Z',
            created_by_id: null,
            created_by_email: null,
          },
        };

        const result = transformToRunInfo(backendData, 'workflow-1');

        const [step1] = result.steps;
        expect(step1?.exit_reason).toBe('crash');
      });
    });

    it('treats unknown exit_reason as fail', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'unknown_state',
            error_type: null,
            started_at: '2025-01-01T10:00:00Z',
            finished_at: '2025-01-01T10:01:00Z',
            input_dataclip_id: 'clip-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'demo@openfn.org',
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      const [step1] = result.steps;
      expect(step1?.exit_reason).toBe('fail');
    });

    it('preserves null error_type', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [
          {
            id: 'step-1',
            job_id: 'job-1',
            exit_reason: 'success',
            error_type: null,
            started_at: '2025-01-01T10:00:00Z',
            finished_at: '2025-01-01T10:01:00Z',
            input_dataclip_id: 'clip-1',
          },
        ],
        metadata: {
          starting_job_id: 'job-1',
          starting_trigger_id: null,
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'demo@openfn.org',
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      const [step1] = result.steps;
      expect(step1?.error_type).toBe(null);
    });

    it('handles empty steps array', () => {
      const backendData: RunStepsData = {
        run_id: 'run-123',
        steps: [],
        metadata: {
          starting_job_id: null,
          starting_trigger_id: null,
          inserted_at: '2025-01-01T10:00:00Z',
          created_by_id: 'user-1',
          created_by_email: 'demo@openfn.org',
        },
      };

      const result = transformToRunInfo(backendData, 'workflow-1');

      expect(result.steps).toEqual([]);
      expect(result.start_from).toBe(null);
    });
  });

  describe('createEmptyRunInfo', () => {
    it('creates empty RunInfo with no steps', () => {
      const result = createEmptyRunInfo();

      expect(result.steps).toEqual([]);
      expect(result.start_from).toBe(null);
      expect(result.run_by).toBe(null);
      expect(result.inserted_at).toBe('');
      expect(result.isTrigger).toBe(false);
    });
  });
});
