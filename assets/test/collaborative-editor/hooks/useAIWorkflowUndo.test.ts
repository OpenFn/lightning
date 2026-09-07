/**
 * useAIWorkflowUndo - Undo/redo of a global reply's applied changes
 *
 * Runs against the real YAML utilities: the baseline undo restores is
 * written by our own serializer, so parsing it is part of what's under test.
 */

import { act, renderHook, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { useAIWorkflowUndo } from '../../../js/collaborative-editor/hooks/useAIWorkflowUndo';
import { notifications } from '../../../js/collaborative-editor/lib/notifications';
import type { Job } from '../../../js/collaborative-editor/types';

vi.mock('../../../js/collaborative-editor/lib/notifications', () => ({
  notifications: { alert: vi.fn() },
}));

const BASELINE_YAML = `name: Test workflow
jobs:
  transform-data:
    id: job-1
    name: Transform data
    adaptor: "@openfn/language-common@latest"
    body: |
      fn(state => state);
triggers:
  webhook:
    id: trigger-1
    type: webhook
    enabled: true
edges:
  webhook->transform-data:
    id: edge-1
    source_trigger: webhook
    target_job: transform-data
    condition_type: always
    enabled: true`;

const MESSAGE_ID = 'message-1';

const setup = ({ hasChanged = false }: { hasChanged?: boolean } = {}) => {
  const importWorkflow = vi.fn().mockResolvedValue(undefined);
  const startApplyingWorkflow = vi.fn().mockResolvedValue(true);
  const doneApplyingWorkflow = vi.fn().mockResolvedValue(undefined);
  const appliedCanvas = {
    record: vi.fn(),
    hasChangedSinceApply: vi.fn().mockReturnValue(hasChanged),
  };

  const jobs = [
    { id: 'job-1', project_credential_id: 'cred-1' },
  ] as unknown as Job[];

  const { result } = renderHook(() =>
    useAIWorkflowUndo({
      jobs,
      appliedCanvas,
      workflowActions: {
        importWorkflow,
        startApplyingWorkflow,
        doneApplyingWorkflow,
      },
    })
  );

  return {
    result,
    appliedCanvas,
    importWorkflow,
    startApplyingWorkflow,
    doneApplyingWorkflow,
  };
};

describe('useAIWorkflowUndo', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('restores the baseline without confirming when nothing changed since the apply', async () => {
    const {
      result,
      appliedCanvas,
      importWorkflow,
      startApplyingWorkflow,
      doneApplyingWorkflow,
    } = setup();

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });

    expect(result.current.isConfirmOpen).toBe(false);
    await waitFor(() => {
      expect(importWorkflow).toHaveBeenCalledTimes(1);
    });

    const imported = importWorkflow.mock.calls[0]![0] as {
      jobs: Array<{ id: string; project_credential_id: string | null }>;
    };
    expect(imported.jobs).toHaveLength(1);
    // Credentials come from the live canvas, not the baseline YAML
    expect(imported.jobs[0]!.project_credential_id).toBe('cred-1');

    expect(startApplyingWorkflow).toHaveBeenCalledWith(MESSAGE_ID);
    expect(doneApplyingWorkflow).toHaveBeenCalledWith(MESSAGE_ID);
    expect(appliedCanvas.record).toHaveBeenCalledTimes(1);
    await waitFor(() => {
      expect(result.current.undoneMessageId).toBe(MESSAGE_ID);
    });
  });

  it('rejects an object id when restoring YAML the model wrote', async () => {
    const { result, importWorkflow } = setup();
    // The model occasionally emits an id as a nested mapping. Redo restores
    // its YAML, so it gets the same check the apply path runs.
    const modelYaml = BASELINE_YAML.replace(
      /^(\s*)id: .*$/m,
      '$1id:\n$1  value: not-a-string'
    );

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, modelYaml, {
        fromModel: true,
      });
    });

    await waitFor(() => {
      expect(importWorkflow).not.toHaveBeenCalled();
    });
  });

  it('skips that check for the baseline, which this app serialized', async () => {
    const { result, importWorkflow } = setup();

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });

    await waitFor(() => {
      expect(importWorkflow).toHaveBeenCalledTimes(1);
    });
  });

  it('confirms before overwriting a workflow edited since the apply', async () => {
    const { result, importWorkflow } = setup({ hasChanged: true });

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });

    expect(result.current.isConfirmOpen).toBe(true);
    expect(importWorkflow).not.toHaveBeenCalled();

    act(() => {
      result.current.confirmUndoChanges();
    });

    await waitFor(() => {
      expect(importWorkflow).toHaveBeenCalledTimes(1);
    });
  });

  it('drops the pending restore when the confirmation is cancelled', () => {
    const { result, importWorkflow } = setup({ hasChanged: true });

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });
    act(() => {
      result.current.cancelUndoChanges();
    });

    expect(result.current.isConfirmOpen).toBe(false);
    expect(importWorkflow).not.toHaveBeenCalled();
  });

  it('toggles back to applied when the same reply is restored again', async () => {
    const { result, importWorkflow } = setup();

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });
    await waitFor(() => {
      expect(result.current.undoneMessageId).toBe(MESSAGE_ID);
    });

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });
    await waitFor(() => {
      expect(result.current.undoneMessageId).toBeNull();
    });
    expect(importWorkflow).toHaveBeenCalledTimes(2);
  });

  it('reports a failed restore and leaves the reply marked as applied', async () => {
    const { result, importWorkflow, doneApplyingWorkflow } = setup();
    importWorkflow.mockRejectedValue(new Error('Y.Doc write failed'));

    act(() => {
      result.current.requestUndoChanges(MESSAGE_ID, BASELINE_YAML);
    });

    await waitFor(() => {
      expect(notifications.alert).toHaveBeenCalledWith(
        expect.objectContaining({ description: 'Y.Doc write failed' })
      );
    });
    // Collaborators must not be left in "APPLYING..."
    expect(doneApplyingWorkflow).toHaveBeenCalledWith(MESSAGE_ID);
    expect(result.current.undoneMessageId).toBeNull();
  });
});
