/**
 * Trigger enable/disable control tests.
 *
 * Covers the restored "enable a trigger on a non-live workflow" control:
 * - visibility gating (shown when editable, hidden when the workflow is live)
 * - enabling routes through a warning modal (off -> on)
 * - disabling is immediate and never warns (on -> off)
 * - the "don't show again" preference is persisted and honored
 */

import { fireEvent, render, screen } from '@testing-library/react';
import type React from 'react';
import { act } from 'react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { TriggerEnabledControl } from '../../../../js/collaborative-editor/components/inspector/TriggerEnabledControl';
import { TriggerInspector } from '../../../../js/collaborative-editor/components/inspector/TriggerInspector';
import { LiveViewActionsProvider } from '../../../../js/collaborative-editor/contexts/LiveViewActionsContext';
import { SessionContext } from '../../../../js/collaborative-editor/contexts/SessionProvider';
import type { StoreContextValue } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { StoreContext } from '../../../../js/collaborative-editor/contexts/StoreProvider';
import { KeyboardProvider } from '../../../../js/collaborative-editor/keyboard';
import { createAdaptorStore } from '../../../../js/collaborative-editor/stores/createAdaptorStore';
import { createAwarenessStore } from '../../../../js/collaborative-editor/stores/createAwarenessStore';
import { createCredentialStore } from '../../../../js/collaborative-editor/stores/createCredentialStore';
import { createSessionContextStore } from '../../../../js/collaborative-editor/stores/createSessionContextStore';
import { createSessionStore } from '../../../../js/collaborative-editor/stores/createSessionStore';
import { createUIStore } from '../../../../js/collaborative-editor/stores/createUIStore';
import type { WorkflowStoreInstance } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import { createWorkflowStore } from '../../../../js/collaborative-editor/stores/createWorkflowStore';
import type { Permissions } from '../../../../js/collaborative-editor/types/sessionContext';
import type { Workflow } from '../../../../js/collaborative-editor/types/workflow';
import {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
} from '../../__helpers__/channelMocks';
import { createSessionContext } from '../../__helpers__/sessionContextFactory';
import { createMockSocket } from '../../__helpers__/sessionStoreHelpers';
import { createWorkflowYDoc } from '../../__helpers__/workflowFactory';

// A minimal live session-context workflow (draft/live carries the lifecycle
// state that gates the toggle).
const liveWorkflow = {
  jobs: [],
  triggers: [],
  edges: [],
  positions: null,
  name: 'My workflow',
  state: 'live' as const,
};

interface SetupOptions {
  permissions?: Partial<Permissions>;
  workflow?: unknown;
  suppressWarning?: boolean;
  triggerEnabled?: boolean;
}

function setup(options: SetupOptions = {}) {
  const ydoc = createWorkflowYDoc({
    triggers: {
      'trigger-1': {
        id: 'trigger-1',
        type: 'webhook',
        enabled: options.triggerEnabled ?? false,
      },
    },
  });

  // deleted_at must be explicitly null; an absent key reads as "deleted" and
  // would force read-only, hiding the toggle for the wrong reason.
  const workflowMap = ydoc.getMap('workflow');
  workflowMap.set('id', '00000000-0000-4000-8000-000000000001');
  workflowMap.set('name', 'My workflow');
  workflowMap.set('lock_version', 1);
  workflowMap.set('deleted_at', null);

  const workflowChannel = createMockPhoenixChannel();
  const workflowStore: WorkflowStoreInstance = createWorkflowStore();
  workflowStore.connect(
    ydoc,
    createMockPhoenixChannelProvider(workflowChannel) as any
  );

  const sessionChannel = createMockPhoenixChannel();
  const sessionContextStore = createSessionContextStore();
  sessionContextStore._connectChannel(
    createMockPhoenixChannelProvider(sessionChannel) as any
  );

  act(() => {
    (sessionChannel as any)._test.emit(
      'session_context',
      createSessionContext({
        permissions: options.permissions,
        workflow: options.workflow,
        suppress_enable_trigger_warning: options.suppressWarning ?? false,
      })
    );
  });

  // Spy after the initial get_context push so assertions only see the pushes
  // driven by the control.
  vi.spyOn(workflowChannel, 'push');
  vi.spyOn(sessionChannel, 'push');

  const storeValue = {
    workflowStore,
    sessionContextStore,
    uiStore: createUIStore(),
    credentialStore: createCredentialStore(),
    adaptorStore: createAdaptorStore(),
    awarenessStore: createAwarenessStore(),
  } as unknown as StoreContextValue;

  const sessionStore = createSessionStore();
  sessionStore.initializeSession(
    createMockSocket(),
    'test:room',
    { id: 'test-user', name: 'Test', email: 'test@example.com', color: '#000' },
    { connect: false }
  );
  const provider = sessionStore.getSnapshot().provider;
  if (provider) {
    provider.emit('sync', [true]);
    provider.emit('status', [{ status: 'connected' }]);
  }

  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <SessionContext.Provider value={{ sessionStore, isNewWorkflow: false }}>
      <LiveViewActionsProvider
        actions={{
          pushEvent: vi.fn(),
          pushEventTo: vi.fn(),
          handleEvent: vi.fn(() => vi.fn()),
          navigate: vi.fn(),
        }}
      >
        <StoreContext.Provider value={storeValue}>
          <KeyboardProvider>{children}</KeyboardProvider>
        </StoreContext.Provider>
      </LiveViewActionsProvider>
    </SessionContext.Provider>
  );

  const trigger = workflowStore.getSnapshot().triggers[0];

  return { workflowChannel, sessionChannel, wrapper, trigger };
}

describe('TriggerInspector - enable toggle footer placement', () => {
  const renderInspector = (
    wrapper: React.ComponentType<{ children: React.ReactNode }>,
    trigger: Workflow.Trigger
  ) =>
    render(
      <TriggerInspector
        trigger={trigger}
        onClose={vi.fn()}
        onOpenRunPanel={vi.fn()}
      />,
      { wrapper }
    );

  test('shows the "Enabled" toggle in the footer on an editable (non-live) workflow', () => {
    const { wrapper, trigger } = setup({
      permissions: { can_edit_workflow: true },
    });

    renderInspector(wrapper, trigger);

    // Footer carries both the enable toggle and the Run button.
    expect(screen.getByLabelText('Enabled')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /run/i })).toBeInTheDocument();
  });

  test('hides the enable toggle and run button on a live workflow', () => {
    const { wrapper, trigger } = setup({
      permissions: { can_edit_workflow: false, can_provision_sandbox: true },
      workflow: liveWorkflow,
    });

    renderInspector(wrapper, trigger);

    // A live workflow is read-only: the enable toggle is an edit action and the
    // Run button creates a run, and neither is allowed. To run a live workflow
    // you edit it in a sandbox.
    expect(screen.queryByLabelText('Enabled')).not.toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: /run/i })
    ).not.toBeInTheDocument();
  });
});

describe('TriggerEnabledControl - enable/disable behavior', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('disabling an enabled trigger pushes enabled:false without warning', () => {
    const { workflowChannel, wrapper, trigger } = setup({
      triggerEnabled: true,
    });

    render(<TriggerEnabledControl trigger={trigger} />, { wrapper });

    fireEvent.click(screen.getByLabelText('Enabled'));

    expect(screen.queryByText('Enable this trigger')).not.toBeInTheDocument();
    expect(workflowChannel.push).toHaveBeenCalledWith('set_trigger_enabled', {
      trigger_id: 'trigger-1',
      enabled: false,
    });
  });

  test('enabling opens the warning and confirm pushes enabled:true', () => {
    const { workflowChannel, sessionChannel, wrapper, trigger } = setup({
      triggerEnabled: false,
    });

    render(<TriggerEnabledControl trigger={trigger} />, { wrapper });

    fireEvent.click(screen.getByLabelText('Enabled'));

    // Warning is shown; nothing has been enabled yet.
    expect(screen.getByText('Enable this trigger')).toBeInTheDocument();
    expect(workflowChannel.push).not.toHaveBeenCalledWith(
      'set_trigger_enabled',
      expect.anything()
    );

    fireEvent.click(screen.getByRole('button', { name: 'Enable trigger' }));

    expect(workflowChannel.push).toHaveBeenCalledWith('set_trigger_enabled', {
      trigger_id: 'trigger-1',
      enabled: true,
    });
    // Preference was left unchecked, so it is not persisted.
    expect(sessionChannel.push).not.toHaveBeenCalledWith(
      'set_suppress_enable_trigger_warning',
      expect.anything()
    );
  });

  test('cancelling the warning leaves the trigger disabled', () => {
    const { workflowChannel, wrapper, trigger } = setup({
      triggerEnabled: false,
    });

    render(<TriggerEnabledControl trigger={trigger} />, { wrapper });

    fireEvent.click(screen.getByLabelText('Enabled'));
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(workflowChannel.push).not.toHaveBeenCalledWith(
      'set_trigger_enabled',
      expect.anything()
    );
  });

  test('confirming with "don\'t show again" persists the preference and enables', () => {
    const { workflowChannel, sessionChannel, wrapper, trigger } = setup({
      triggerEnabled: false,
    });

    render(<TriggerEnabledControl trigger={trigger} />, { wrapper });

    fireEvent.click(screen.getByLabelText('Enabled'));
    fireEvent.click(screen.getByLabelText(/don't show this warning again/i));
    fireEvent.click(screen.getByRole('button', { name: 'Enable trigger' }));

    expect(sessionChannel.push).toHaveBeenCalledWith(
      'set_suppress_enable_trigger_warning',
      { suppress: true }
    );
    expect(workflowChannel.push).toHaveBeenCalledWith('set_trigger_enabled', {
      trigger_id: 'trigger-1',
      enabled: true,
    });
  });

  test('enabling skips the warning when the preference is already suppressed', () => {
    const { workflowChannel, wrapper, trigger } = setup({
      triggerEnabled: false,
      suppressWarning: true,
    });

    render(<TriggerEnabledControl trigger={trigger} />, { wrapper });

    fireEvent.click(screen.getByLabelText('Enabled'));

    expect(screen.queryByText('Enable this trigger')).not.toBeInTheDocument();
    expect(workflowChannel.push).toHaveBeenCalledWith('set_trigger_enabled', {
      trigger_id: 'trigger-1',
      enabled: true,
    });
  });
});
