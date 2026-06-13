/**
 * CronEditWizard Component Tests
 *
 * Covers the cron edit wizard (#4787): Choose → Configure navigation, the
 * CronFieldBuilder frequency dropdown, the Cron Input Source select, the
 * draft/commit lifecycle (Finish commits once via updateTrigger), and the
 * back-arrow exit from Choose.
 */

import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';
import type * as Y from 'yjs';

import { CronEditWizard } from '../../../../../js/collaborative-editor/components/inspector/trigger/CronEditWizard';
import { LiveViewActionsProvider } from '../../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '../../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../../js/collaborative-editor/contexts/StoreProvider';
import { createSessionContextStore } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import type { SessionContextStoreInstance } from '../../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Workflow } from '../../../../../js/collaborative-editor/types/workflow';
import {
  createMockChannelPushOk,
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../../__helpers__/channelMocks';
import { createMockSocket } from '../../../__helpers__/sessionStoreHelpers';
import { createWorkflowYDoc } from '../../../__helpers__/workflowFactory';

const mockLiveViewActions = {
  pushEvent: vi.fn(),
  pushEventTo: vi.fn(),
  handleEvent: vi.fn(() => () => {}),
  navigate: vi.fn(),
};

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';
const JOB_ID = '44444444-4444-4444-8444-444444444444';

function createConnectedWorkflowStore(ydoc: Y.Doc): WorkflowStoreInstance {
  const store = createWorkflowStore();
  const channel = createMockPhoenixChannel();
  channel.push = createMockChannelPushOk({ ok: true });
  const provider = createMockPhoenixChannelProvider(channel);
  store.connect(ydoc, provider as never);
  return store;
}

function makeCronTrigger(
  overrides: Partial<Workflow.Trigger> = {}
): Workflow.Trigger {
  return {
    id: TRIGGER_ID,
    type: 'cron',
    enabled: true,
    has_auth_method: false,
    cron_expression: '0 0 * * *',
    cron_cursor_job_id: null,
    kafka_configuration: null,
    webhook_reply: null,
    webhook_response_config: null,
    ...overrides,
  } as Workflow.Trigger;
}

async function setup(
  trigger: Workflow.Trigger,
  workflowStore: WorkflowStoreInstance
) {
  const sessionStore = createSessionStore();
  sessionStore.initializeSession(
    createMockSocket(),
    'test:room',
    { id: 'user-1', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: true }
  );

  await new Promise(resolve => setTimeout(resolve, 50));

  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

  const sessionContextStore: SessionContextStoreInstance =
    createSessionContextStore();
  const ctxChannel = createMockPhoenixChannel();
  const ctxProvider = createMockPhoenixChannelProvider(ctxChannel);
  sessionContextStore._connectChannel(ctxProvider as never);

  act(() => {
    (
      ctxChannel as never as {
        _test: { emit: (e: string, m: unknown) => void };
      }
    )._test.emit('session_context', {
      user: null,
      project: null,
      config: {
        require_email_verification: false,
        kafka_triggers_enabled: true,
      },
      permissions: {
        can_edit_workflow: true,
        can_run_workflow: true,
        can_write_webhook_auth_method: true,
      },
      latest_snapshot_lock_version: 1,
      project_repo_connection: null,
      webhook_auth_methods: [],
      workflow_template: null,
      has_read_ai_disclaimer: false,
    });
  });

  const storeValue = {
    workflowStore,
    sessionContextStore,
    uiStore: createUIStore(),
  } as unknown as StoreContextValue;

  const onClose = vi.fn();
  const onDone = vi.fn();

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <StoreContext.Provider value={storeValue}>
        <LiveViewActionsProvider actions={mockLiveViewActions}>
          {children}
        </LiveViewActionsProvider>
      </StoreContext.Provider>
    </SessionContext.Provider>
  );

  render(
    <CronEditWizard trigger={trigger} onClose={onClose} onDone={onDone} />,
    {
      wrapper,
    }
  );

  return { onClose, onDone };
}

describe('CronEditWizard', () => {
  let ydoc: Y.Doc;

  beforeEach(() => {
    mockLiveViewActions.pushEvent.mockClear();
    ydoc = createWorkflowYDoc({
      triggers: { [TRIGGER_ID]: { id: TRIGGER_ID, type: 'cron' } },
      jobs: {
        [JOB_ID]: { id: JOB_ID, name: 'Transform data' },
      },
    });
    const workflowMap = ydoc.getMap('workflow');
    workflowMap.set('id', 'workflow-1');
    workflowMap.set('lock_version', 1);
    workflowMap.set('deleted_at', null);
  });

  describe('navigation', () => {
    test('Choose -> Next -> Configure, then back-arrow from Choose exits', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const { onDone } = await setup(makeCronTrigger(), workflowStore);

      // Choose step is the landing screen.
      expect(
        screen.getByRole('heading', { name: 'On a Schedule' })
      ).toBeInTheDocument();
      expect(
        screen.getByRole('button', { name: 'Change' })
      ).toBeInTheDocument();

      // Next -> Configure (Configure-only control present).
      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      expect(screen.getByLabelText('Cron Input Source')).toBeInTheDocument();

      // Breadcrumb "Choose" crumb returns to Choose.
      await userEvent.click(screen.getByRole('button', { name: 'Choose' }));
      expect(
        screen.queryByLabelText('Cron Input Source')
      ).not.toBeInTheDocument();

      // Header back-arrow from Choose exits the wizard.
      await userEvent.click(screen.getByRole('button', { name: 'Back' }));
      expect(onDone).toHaveBeenCalledTimes(1);
    });
  });

  describe('commit lifecycle', () => {
    test('Finish commits cron_expression + cron_cursor_job_id via updateTrigger then onDone', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      const updateSpy = vi.spyOn(workflowStore, 'updateTrigger');
      const { onDone } = await setup(makeCronTrigger(), workflowStore);

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));

      // Pick a frequency from the CronFieldBuilder dropdown → draft cron.
      await userEvent.selectOptions(
        screen.getByLabelText('Frequency'),
        'every_n_minutes'
      );

      // Pick a Cron Input Source.
      await userEvent.selectOptions(
        screen.getByLabelText('Cron Input Source'),
        JOB_ID
      );

      await userEvent.click(screen.getByRole('button', { name: 'Finish' }));

      await waitFor(() => {
        expect(updateSpy).toHaveBeenCalledTimes(1);
      });
      expect(updateSpy).toHaveBeenCalledWith(
        TRIGGER_ID,
        expect.objectContaining({
          cron_expression: '*/15 * * * *',
          cron_cursor_job_id: JOB_ID,
        })
      );
      expect(onDone).toHaveBeenCalledTimes(1);
    });

    test('an existing schedule seeds the frequency dropdown', async () => {
      const workflowStore = createConnectedWorkflowStore(ydoc);
      await setup(
        makeCronTrigger({ cron_expression: '*/15 * * * *' }),
        workflowStore
      );

      await userEvent.click(screen.getByRole('button', { name: 'Next' }));
      // "*/15 * * * *" is recognised as the "every N minutes" frequency.
      expect(screen.getByLabelText('Frequency')).toHaveValue('every_n_minutes');
    });
  });
});
