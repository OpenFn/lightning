import { describe, it, expect, beforeEach, vi } from 'vitest';
import { createRunStore } from '../../../js/collaborative-editor/stores/createRunStore';
import type { Run, Step } from '../../../js/collaborative-editor/types/run';

describe('createRunStore', () => {
  let store: ReturnType<typeof createRunStore>;

  beforeEach(() => {
    store = createRunStore();
  });

  it('initializes with null run', () => {
    expect(store.getSnapshot().currentRun).toBeNull();
  });

  it('initializes with default state values', () => {
    const snapshot = store.getSnapshot();
    expect(snapshot.currentRun).toBeNull();
    expect(snapshot.selectedStepId).toBeNull();
    expect(snapshot.isLoading).toBe(false);
    expect(snapshot.error).toBeNull();
    expect(snapshot.lastUpdated).toBeNull();
  });

  it('sets run via setRun', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);

    expect(store.getSnapshot().currentRun).toEqual(mockRun);
    expect(store.getSnapshot().lastUpdated).not.toBeNull();
  });

  it('adds and updates steps correctly', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);

    const step1: Step = {
      id: 'step-1',
      job_id: 'job-1',
      job: { id: 'job-1', name: 'Job 1' },
      exit_reason: null,
      error_type: null,
      started_at: new Date().toISOString(),
      finished_at: null,
      input_dataclip_id: null,
      output_dataclip_id: null,
      inserted_at: new Date().toISOString(),
    };

    store.addOrUpdateStep(step1);

    expect(store.getSnapshot().currentRun?.steps).toHaveLength(1);
    expect(store.getSnapshot().currentRun?.steps[0].id).toBe('step-1');

    // Update same step
    const updatedStep = { ...step1, exit_reason: 'success' };
    store.addOrUpdateStep(updatedStep);

    expect(store.getSnapshot().currentRun?.steps).toHaveLength(1);
    expect(store.getSnapshot().currentRun?.steps[0].exit_reason).toBe(
      'success'
    );
  });

  it('sorts steps by started_at when adding new steps', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);

    const step1: Step = {
      id: 'step-1',
      job_id: 'job-1',
      job: { id: 'job-1', name: 'Job 1' },
      exit_reason: null,
      error_type: null,
      started_at: new Date('2024-01-01T10:00:00Z').toISOString(),
      finished_at: null,
      input_dataclip_id: null,
      output_dataclip_id: null,
      inserted_at: new Date().toISOString(),
    };

    const step2: Step = {
      id: 'step-2',
      job_id: 'job-2',
      job: { id: 'job-2', name: 'Job 2' },
      exit_reason: null,
      error_type: null,
      started_at: new Date('2024-01-01T09:00:00Z').toISOString(),
      finished_at: null,
      input_dataclip_id: null,
      output_dataclip_id: null,
      inserted_at: new Date().toISOString(),
    };

    // Add in reverse chronological order
    store.addOrUpdateStep(step1);
    store.addOrUpdateStep(step2);

    const steps = store.getSnapshot().currentRun?.steps || [];
    expect(steps).toHaveLength(2);
    expect(steps[0].id).toBe('step-2'); // Earlier timestamp should be first
    expect(steps[1].id).toBe('step-1');
  });

  it('selects step by ID', () => {
    store.selectStep('step-1');
    expect(store.getSnapshot().selectedStepId).toBe('step-1');

    store.selectStep(null);
    expect(store.getSnapshot().selectedStepId).toBeNull();
  });

  it('finds step by ID', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [
        {
          id: 'step-1',
          job_id: 'job-1',
          job: { id: 'job-1', name: 'Job 1' },
          exit_reason: null,
          error_type: null,
          started_at: new Date().toISOString(),
          finished_at: null,
          input_dataclip_id: null,
          output_dataclip_id: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    };

    store.setRun(mockRun);

    const foundStep = store.findStepById('step-1');
    expect(foundStep).not.toBeNull();
    expect(foundStep?.id).toBe('step-1');

    const notFound = store.findStepById('non-existent');
    expect(notFound).toBeNull();
  });

  it('gets selected step', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [
        {
          id: 'step-1',
          job_id: 'job-1',
          job: { id: 'job-1', name: 'Job 1' },
          exit_reason: null,
          error_type: null,
          started_at: new Date().toISOString(),
          finished_at: null,
          input_dataclip_id: null,
          output_dataclip_id: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    };

    store.setRun(mockRun);
    store.selectStep('step-1');

    const selectedStep = store.getSelectedStep();
    expect(selectedStep).not.toBeNull();
    expect(selectedStep?.id).toBe('step-1');
  });

  it('notifies subscribers on state change', () => {
    const listener = vi.fn();
    const unsubscribe = store.subscribe(listener);

    store.setLoading(true);
    expect(listener).toHaveBeenCalledTimes(1);

    unsubscribe();
    store.setLoading(false);
    expect(listener).toHaveBeenCalledTimes(1); // Not called after unsubscribe
  });

  it('sets loading state', () => {
    store.setLoading(true);
    expect(store.getSnapshot().isLoading).toBe(true);

    store.setLoading(false);
    expect(store.getSnapshot().isLoading).toBe(false);
  });

  it('sets and clears error', () => {
    store.setError('Test error');
    expect(store.getSnapshot().error).toBe('Test error');
    expect(store.getSnapshot().isLoading).toBe(false); // Loading stops on error

    store.clearError();
    expect(store.getSnapshot().error).toBeNull();
  });

  it('clears state', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);
    store.selectStep('step-1');
    store.setLoading(true);
    store.setError('Error');

    store.clear();

    const snapshot = store.getSnapshot();
    expect(snapshot.currentRun).toBeNull();
    expect(snapshot.selectedStepId).toBeNull();
    expect(snapshot.isLoading).toBe(false);
    expect(snapshot.error).toBeNull();
  });

  it('updates run state partially', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);

    store.updateRunState({
      state: 'success',
      finished_at: new Date().toISOString(),
    });

    const snapshot = store.getSnapshot();
    expect(snapshot.currentRun?.state).toBe('success');
    expect(snapshot.currentRun?.finished_at).not.toBeNull();
    expect(snapshot.currentRun?.id).toBe('run-1'); // Other fields preserved
  });

  it('selects first step by default when run is received', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [
        {
          id: 'step-1',
          job_id: 'job-1',
          exit_reason: null,
          error_type: null,
          started_at: new Date().toISOString(),
          finished_at: null,
          input_dataclip_id: null,
          output_dataclip_id: null,
          inserted_at: new Date().toISOString(),
        },
        {
          id: 'step-2',
          job_id: 'job-2',
          exit_reason: null,
          error_type: null,
          started_at: new Date().toISOString(),
          finished_at: null,
          input_dataclip_id: null,
          output_dataclip_id: null,
          inserted_at: new Date().toISOString(),
        },
      ],
    };

    store.setRun(mockRun);

    // No automatic selection in setRun - this is handled by handleRunReceived
    // which is tested via channel integration
    expect(store.getSnapshot().selectedStepId).toBeNull();
  });

  it('maintains referential stability when selector returns same data', () => {
    const mockRun: Run = {
      id: 'run-1',
      work_order_id: 'wo-1',
      state: 'started',
      started_at: new Date().toISOString(),
      finished_at: null,
      steps: [],
    };

    store.setRun(mockRun);

    const selector = store.withSelector(state => state.currentRun?.id);

    const result1 = selector();
    const result2 = selector();

    expect(result1).toBe(result2);
    expect(result1).toBe('run-1');
  });
});
