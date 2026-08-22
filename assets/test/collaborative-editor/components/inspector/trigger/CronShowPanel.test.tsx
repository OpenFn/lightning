/**
 * CronShowPanel Component Tests
 *
 * Covers the read-only cron "show" panel (#4787): the "Schedule / Cron" badge,
 * the Frequency label + humanized schedule box, the Cron Input Source field
 * (job name, or the default when unset), and the Edit button permission gating.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { CronShowPanel } from '../../../../../js/collaborative-editor/components/inspector/trigger/CronShowPanel';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createTriggerTestHarness } from '../../../__helpers__/triggerInspectorHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';
const JOB_ID = '33333333-3333-4333-8333-333333333333';

interface SetupOptions {
  canEdit?: boolean;
}

/**
 * Renders the panel inside a session + store context with permissions emitted
 * via the session context channel.
 */
async function setup(
  trigger: Workflow.Trigger,
  workflowStore: WorkflowStoreInstance,
  { canEdit = true }: SetupOptions = {}
) {
  const { wrapper } = await createTriggerTestHarness({
    canEdit,
    workflowStore,
  });

  const onClose = vi.fn();
  const onEdit = vi.fn();

  render(
    <CronShowPanel trigger={trigger} onClose={onClose} onEdit={onEdit} />,
    { wrapper }
  );

  return { onClose, onEdit };
}

function makeCronTrigger(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'cron',
    enabled: true,
    has_auth_method: false,
    cron_expression: '0 9 * * *',
    cron_cursor_job_id: null,
    kafka_configuration: null,
    webhook_reply: 'before_start',
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
}

/**
 * Builds a connected workflow store backed by a Y.Doc containing the supplied
 * jobs, so `useWorkflowState(s => s.jobs)` resolves the cron input-source name.
 */
function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

describe('CronShowPanel', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'cron' } },
      jobs: {
        [JOB_ID]: {
          id: JOB_ID,
          name: 'Fetch records',
          adaptor: '@openfn/language-common',
        },
      },
    });
    // Populate the workflow map so the store derives a saved (non-deleted)
    // workflow; otherwise useWorkflowReadOnly treats an empty map's
    // `deleted_at === undefined` as deleted.
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  test('renders the cron badge, Frequency label, and the humanized schedule', async () => {
    const workflowStore = createConnectedWorkflowStore(ydoc);
    await setup(makeCronTrigger(), workflowStore);

    expect(screen.getByText('Schedule / Cron')).toBeInTheDocument();
    expect(screen.getByText('Frequency')).toBeInTheDocument();
    expect(screen.getByText('At 09:00 AM')).toBeInTheDocument();
  });

  describe('edit button gating', () => {
    test('is enabled and calls onEdit when the user can edit', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onEdit } = await setup(makeCronTrigger(), workflowStore, {
        canEdit: true,
      });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).not.toBeDisabled();

      await userEvent.click(editButton);
      expect(onEdit).toHaveBeenCalledTimes(1);
    });

    test('is disabled with a tooltip for read-only / viewers', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onEdit } = await setup(makeCronTrigger(), workflowStore, {
        canEdit: false,
      });

      const editButton = screen.getByRole('button', { name: 'Edit trigger' });
      expect(editButton).toBeDisabled();
      await userEvent.click(editButton);
      expect(onEdit).not.toHaveBeenCalled();

      const wrapper = editButton.parentElement;
      if (wrapper) {
        await userEvent.hover(wrapper);
      }
      await waitFor(() => {
        expect(
          screen.getAllByText(
            'You do not have permission to edit this workflow'
          ).length
        ).toBeGreaterThan(0);
      });
    });
  });

  describe('cron input source field', () => {
    test('shows the job name when cron_cursor_job_id is set', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(
        makeCronTrigger({ cron_cursor_job_id: JOB_ID }),
        workflowStore
      );

      expect(screen.getByText('Cron Input Source')).toBeInTheDocument();
      expect(screen.getByText('Fetch records')).toBeInTheDocument();
    });

    test('shows the default source when cron_cursor_job_id is unset', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(makeCronTrigger(), workflowStore);

      expect(screen.getByText('Cron Input Source')).toBeInTheDocument();
      expect(screen.getByText('Final run state (default)')).toBeInTheDocument();
    });
  });
});
